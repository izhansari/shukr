//
//  MosqueFinder.swift
//  shukr
//
//  The map's mosque finder (2026-09-25). MapKit has no "mosque" point-of-interest category, so
//  this runs three text searches — "mosque", "masjid", "islamic center" — over the area, merges
//  them, keeps only places whose name reads like a place of prayer (and drops restaurants,
//  shops, halal markets, schools…), and de-duplicates. A tapped mosque opens `MosqueSheet`:
//  the drive (time + distance, MKDirections ETA), Look Around imagery when Apple has it,
//  Directions (Apple Maps, driving), Call, the website in an in-app browser, and "Photos &
//  details" — Apple Maps' own place card (`mapItemDetailSheet`), which is where place photos
//  live (MapKit doesn't hand them out directly).
//

import SwiftUI
import MapKit
import SafariServices

/// The finder's icon — the map button and the pins. No mosque SF Symbol exists and the moons are
/// taken (Isha, 99 Names), so the owner is choosing among these (Settings → My Dev Stuff).
enum MosqueIconStyle: String, CaseIterable, Identifiable {
    case finder, columns, lodge, jamaat, houseFlag
    static let key = "mosqueIconStyle"
    static var current: MosqueIconStyle {
        MosqueIconStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .finder
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .finder: "Finder (magnifier + columns)"
        case .columns: "Columns"
        case .lodge: "Lodge"
        case .jamaat: "Jamaat"
        case .houseFlag: "House & flag"
        }
    }
    /// The map button (off / on).
    func button(on: Bool) -> String {
        switch self {
        case .finder: on ? "sparkle.magnifyingglass" : "sparkle.magnifyingglass"
        case .columns: on ? "building.columns.fill" : "building.columns"
        case .lodge: on ? "house.lodge.fill" : "house.lodge"
        case .jamaat: on ? "person.2.wave.2.fill" : "person.2.wave.2"
        case .houseFlag: on ? "house.and.flag.fill" : "house.and.flag"
        }
    }
    var pin: String {
        switch self {
        case .finder, .columns: "building.columns.fill"
        case .lodge: "house.lodge.fill"
        case .jamaat: "person.2.wave.2.fill"
        case .houseFlag: "house.and.flag.fill"
        }
    }
}

/// How the mosque sheet measures the trip (explore sheet setting; tap the time to flip).
enum MosqueTravel: String, CaseIterable, Identifiable {
    case driving, walking
    static let key = "mosqueTravelMode"
    var id: String { rawValue }
    var icon: String { self == .driving ? "car.fill" : "figure.walk" }
    var noun: String { self == .driving ? "drive" : "walk" }
    var title: String { self == .driving ? "Driving" : "Walking" }
    var appleMapsMode: String { self == .driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking }
}

/// A mosque pin on the map.
final class MosqueAnnotation: MKPointAnnotation {
    let item: MKMapItem
    init(item: MKMapItem) {
        self.item = item
        super.init()
        coordinate = item.placemark.coordinate
        title = item.name
    }
}

/// The mosque the user tapped (drives the sheet).
struct MosqueSelection: Identifiable {
    let id = UUID()
    let item: MKMapItem
}

enum MosqueSearch {
    static let queries = ["mosque", "masjid", "islamic center"]

    /// Names that say "place of prayer".
    private static let prayerWords = [
        "mosque", "masjid", "masjed", "musalla", "musallah", "jamia", "jami ", "jame ",
        "islamic center", "islamic centre", "islamic society", "islamic association",
        "islamic foundation", "islamic institute", "islamic community", "islamic cultural",
        "muslim community", "muslim association", "darul", "dar al", "dar-al",
    ]
    /// Names of things that aren't, unless the name also says mosque / masjid outright.
    private static let notPrayerPlaces = [
        "restaurant", "grill", "kitchen", "cafe", "café", "market", "grocery", "halal meat",
        "bakery", "store", "shop", "books", "school", "academy", "daycare", "preschool",
        "funeral", "cemetery", "clinic", "travel", "tours", "catering",
    ]
    private static let notPrayerCategories: Set<MKPointOfInterestCategory> = [
        .restaurant, .cafe, .foodMarket, .store, .bakery, .hotel, .gasStation, .nightlife,
        .bank, .pharmacy, .parking,
    ]

    static func isMosque(_ item: MKMapItem) -> Bool {
        let name = " " + (item.name ?? "").lowercased() + " "
        guard prayerWords.contains(where: name.contains) else { return false }
        let saysMosque = name.contains("mosque") || name.contains("masjid")
        if !saysMosque && notPrayerPlaces.contains(where: name.contains) { return false }
        if let category = item.pointOfInterestCategory, notPrayerCategories.contains(category) { return false }
        return true
    }

    /// Mosques around `region`, nearest to its centre first.
    @MainActor
    static func find(in region: MKCoordinateRegion) async -> [MKMapItem] {
        var found: [MKMapItem] = []
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest
            if let response = try? await MKLocalSearch(request: request).start() {
                found += response.mapItems.filter(isMosque)
            }
        }
        // The three searches overlap: one pin per place (same name, or within 60 m).
        var unique: [MKMapItem] = []
        for item in found {
            let here = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let duplicate = unique.contains { other in
                let there = CLLocation(latitude: other.placemark.coordinate.latitude, longitude: other.placemark.coordinate.longitude)
                return here.distance(from: there) < 60
                    || (other.name?.lowercased() == item.name?.lowercased() && here.distance(from: there) < 500)
            }
            if !duplicate { unique.append(item) }
        }
        let centre = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return unique.sorted {
            CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude).distance(from: centre)
                < CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude).distance(from: centre)
        }
    }
}

// MARK: - The sheet

struct MosqueSheet: View {
    let item: MKMapItem
    @State private var drive: (time: TimeInterval, meters: CLLocationDistance)?
    @State private var driveFailed = false
    @State private var scene: MKLookAroundScene?
    @State private var placeCard: MKMapItem?
    @State private var website: URL?
    /// Driving or walking: starts from the explore sheet's setting; a tap on the time flips it
    /// for this mosque (owner).
    @AppStorage(MosqueTravel.key) private var travelPreference = MosqueTravel.driving.rawValue
    @State private var travel: MosqueTravel?
    private var mode: MosqueTravel { travel ?? MosqueTravel(rawValue: travelPreference) ?? .driving }

    private var address: String? {
        let p = item.placemark
        let parts = [p.subThoroughfare.map { "\($0) \(p.thoroughfare ?? "")" } ?? p.thoroughfare, p.locality, p.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Mosque")
                        .font(.system(size: 26, weight: .light, design: .rounded))
                    if let address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // How far — by car or on foot; tap to switch.
                Button {
                    triggerSomeVibration(type: .light)
                    travel = mode == .driving ? .walking : .driving
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.icon)
                            .foregroundStyle(Color.green)
                            .frame(width: 22)
                            .contentTransition(.symbolEffect(.replace))
                        if let drive {
                            Text("\(minutes(drive.time)) \(mode.noun)")
                                .font(.headline.weight(.medium))
                            Text("· \(distance(drive.meters))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(driveFailed ? "couldn't work out the \(mode.noun)" : "working out the \(mode.noun)…")
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Street-level imagery, where Apple has it.
                if let scene {
                    LookAroundPreview(initialScene: scene)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                HStack(spacing: 10) {
                    // Directions (primary, green tint): a menu that opens at the button. Maps apps
                    // by name only, the way most apps list them (the map symbol already means
                    // "map style" on this screen — owner), then Share (a friend, the car).
                    Menu {
                        Section("Directions in") {
                            Button("Apple Maps") {
                                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.appleMapsMode])
                            }
                            Button("Google Maps") { open(googleMapsURL) }
                            Button("Waze") { open(wazeURL) }
                        }
                        ShareLink(item: shareURL,
                                  subject: Text(item.name ?? "Mosque"),
                                  message: Text([item.name, address].compactMap { $0 }.joined(separator: " · "))) {
                            Label("Share location", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        capsuleLabel("Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", primary: true)
                    }
                    .menuOrder(.fixed)
                    // Call (secondary, quiet gray).
                    if let phone = item.phoneNumber,
                       let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Button { UIApplication.shared.open(url) } label: {
                            capsuleLabel("Call", icon: "phone.fill", primary: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 0) {
                    if let url = item.url {
                        row(icon: "globe", title: url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? "Website",
                            subtitle: "website") { website = url }
                        Divider().padding(.leading, 44)
                    }
                    row(icon: "photo.on.rectangle", title: "Details & photos", subtitle: "Apple Maps' place card") {
                        placeCard = item
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
            }
            .padding(20)
        }
        .fontDesign(.rounded)
        .task(id: mode) { await loadDrive() }
        .task { await loadScene() }
        .mapItemDetailSheet(item: $placeCard)
        .sheet(item: Binding(get: { website.map { IdentifiedURL(url: $0) } }, set: { website = $0?.url })) {
            SafariView(url: $0.url).ignoresSafeArea()
        }
    }

    /// Primary: a green tint (owner: tint, not a solid fill). Secondary: quiet gray.
    private func capsuleLabel(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(primary ? .semibold : .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(primary ? Color.green : Color.primary.opacity(0.75))
            .background(Capsule().fill(primary ? Color.green.opacity(0.14) : Color(.tertiarySystemFill)))
            .contentShape(Capsule())
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.green)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var coordinateString: String {
        let c = item.placemark.coordinate
        return "\(c.latitude),\(c.longitude)"
    }

    /// Google's universal directions link: opens the Google Maps app when it's installed (no
    /// URL-scheme allow-listing needed), the website otherwise.
    private var googleMapsURL: URL? {
        var parts = URLComponents(string: "https://www.google.com/maps/dir/")!
        parts.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: coordinateString),
            URLQueryItem(name: "travelmode", value: mode == .walking ? "walking" : "driving"),
        ]
        return parts.url
    }

    /// Waze's universal link (app if installed).
    private var wazeURL: URL? {
        URL(string: "https://waze.com/ul?ll=\(coordinateString)&navigate=yes")
    }

    /// What Share sends: an Apple Maps link to the mosque by name — opens anywhere, and the
    /// Tesla app takes it as a destination.
    private var shareURL: URL {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [
            URLQueryItem(name: "q", value: item.name ?? "Mosque"),
            URLQueryItem(name: "ll", value: coordinateString),
        ]
        return parts.url ?? URL(string: "https://maps.apple.com/?ll=\(coordinateString)")!
    }

    private func open(_ url: URL?) {
        if let url { UIApplication.shared.open(url) }
    }

    private func loadDrive() async {
        drive = nil
        driveFailed = false
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = item
        request.transportType = mode == .walking ? .walking : .automobile
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            drive = (eta.expectedTravelTime, eta.distance)
        } catch {
            driveFailed = true
        }
    }

    private func loadScene() async {
        scene = try? await MKLookAroundSceneRequest(mapItem: item).scene
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 60 ? "\(max(m, 1)) min" : "\(m / 60) h \(m % 60) min"
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A website inside the app (the mosque's site), with Safari's own controls.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor.systemGreen
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
