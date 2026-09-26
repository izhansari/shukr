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

    /// True when every query of the last `find` failed (offline) — "no mosques" can't be trusted.
    @MainActor static var lastSearchFailed = false

    /// Mosques around `region`, nearest to its centre first.
    @MainActor
    static func find(in region: MKCoordinateRegion) async -> [MKMapItem] {
        // At least ~5 km across: a zoomed-in map would otherwise find nothing.
        var region = region
        region.span.latitudeDelta = max(region.span.latitudeDelta, 0.05)
        region.span.longitudeDelta = max(region.span.longitudeDelta, 0.05)
        var found: [MKMapItem] = []
        var failures = 0
        defer { lastSearchFailed = failures == queries.count }
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            // Only inside the area. As a hint, "Search this area" somewhere new came back with
            // the same places near you (owner: "28 in my area" with no pins in view).
            request.regionPriority = .required
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                found += response.mapItems.filter(isMosque)
            } catch {
                // "No results" is an error too; only a network failure means "couldn't tell".
                if (error as? MKError)?.code != .placemarkNotFound { failures += 1 }
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

// MARK: - My masajid

/// The user's own mosques (owner, 2026-09-26: "allow me to favorite mosques"). Saved with name and
/// position, so they're on the map and at the top of the list even when a search doesn't return
/// them, and so later features (prayed-at-a-masjid, the entering dua) know which places are yours.
struct FavoriteMosque: Codable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }
}

enum MosqueFavorites {
    static let key = "favoriteMosques"

    static var all: [FavoriteMosque] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FavoriteMosque].self, from: data)) ?? []
    }

    private static func save(_ list: [FavoriteMosque]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
        NotificationCenter.default.post(name: MosqueHiding.changed, object: nil)
    }

    static func isFavorite(_ item: MKMapItem) -> Bool { all.contains { $0.id == MosqueHiding.id(item) } }

    static func setFavorite(_ item: MKMapItem, _ on: Bool) {
        var list = all.filter { $0.id != MosqueHiding.id(item) }
        if on {
            let c = item.placemark.coordinate
            list.append(FavoriteMosque(id: MosqueHiding.id(item), name: item.name ?? "Mosque",
                                       latitude: c.latitude, longitude: c.longitude))
            if MosqueHiding.hiddenOneByOne(item) { MosqueHiding.setHidden(item, false) }   // can't be both
        }
        save(list)
    }

    /// Search results plus any of your masajid inside the searched area that the search missed.
    static func merged(_ found: [MKMapItem], in region: MKCoordinateRegion) -> [MKMapItem] {
        let centre = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let radius = max(region.span.latitudeDelta, 0.05) * 111_000 / 2 + 2_000
        let extra = all.filter { fav in
            let here = CLLocation(latitude: fav.latitude, longitude: fav.longitude)
            guard here.distance(from: centre) < radius else { return false }
            return !found.contains { item in
                let c = item.placemark.coordinate
                return CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: here) < 60
                    || MosqueHiding.id(item) == fav.id
            }
        }
        return found + extra.map(\.mapItem)
    }
}

// MARK: - Not recommended

/// Mosques the user doesn't want recommended (owner, 2026-09-26: "don't recommend this one to me,
/// in any place"). One by one (long-press in the list, or the button on a mosque's sheet), or every
/// Ahmadiyya mosque at once (the list's filter menu; matched on "Ahmadi" in the name or their
/// alislam.org website — not on "Baitul", which plenty of Sunni mosques are called too). They're never the nearest card, sit greyed at the bottom of the list,
/// don't count in "N mosques", and their pins are grey. Stored in standard defaults.
enum MosqueHiding {
    static let key = "hiddenMosques"
    static let ahmadiyyaKey = "hideAhmadiyyaMosques"
    static let changed = Notification.Name("hiddenMosquesChanged")

    /// Name + position (~10 m), stable across searches.
    static func id(_ item: MKMapItem) -> String {
        let c = item.placemark.coordinate
        return "\((item.name ?? "").lowercased())|\(String(format: "%.4f", c.latitude))|\(String(format: "%.4f", c.longitude))"
    }

    private static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func isAhmadiyya(_ item: MKMapItem) -> Bool {
        let text = ((item.name ?? "") + " " + (item.url?.absoluteString ?? "")).lowercased()
        return text.contains("ahmadi") || text.contains("alislam.org")
    }

    static func hiddenOneByOne(_ item: MKMapItem) -> Bool { ids.contains(id(item)) }

    static func isHidden(_ item: MKMapItem) -> Bool {
        hiddenOneByOne(item) || (UserDefaults.standard.bool(forKey: ahmadiyyaKey) && isAhmadiyya(item))
    }

    static func setHidden(_ item: MKMapItem, _ hidden: Bool) {
        var set = ids
        if hidden { set.insert(id(item)) } else { set.remove(id(item)) }
        UserDefaults.standard.set(Array(set), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func setHideAhmadiyya(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: ahmadiyyaKey)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

// MARK: - The list

/// Every mosque the last search found, nearest first (owner, 2026-09-26: after "Search this area"
/// the pins can be off screen; a list gets you back to them). Opens by itself when Mosques is
/// picked in Explore. The nearest one is a card on top; the rest are rows in one rounded group,
/// each with the distance and — for the closest few — the drive / walk time. Tap → the map flies
/// there and opens that mosque.
struct MosqueListSheet: View {
    let items: [MKMapItem]
    let origin: CLLocation?
    let nearYou: Bool
    /// The search is still running (the sheet opens at once, 2026-09-26 — it used to wait for
    /// results behind a bar that meant nothing yet).
    var searching = false
    /// ✕: leave mosques (the sheet only shrinks to its header when swiped down).
    var close: () -> Void = {}
    let pick: (MKMapItem) -> Void
    @AppStorage(MosqueIconStyle.key) private var mosqueIconRaw = MosqueIconStyle.finder.rawValue
    @AppStorage(MosqueTravel.key) private var travelRaw = MosqueTravel.driving.rawValue
    /// Travel times for the closest few (MKDirections is rate-limited, so not all of them).
    @State private var etas: [Int: TimeInterval] = [:]
    /// Bumps when a mosque is hidden / shown, so the list regroups.
    @State private var hiddenRevision = 0
    @AppStorage(MosqueHiding.ahmadiyyaKey) private var hideAhmadiyya = false

    private var icon: String { (MosqueIconStyle(rawValue: mosqueIconRaw) ?? .finder).pin }
    private var travel: MosqueTravel { MosqueTravel(rawValue: travelRaw) ?? .driving }

    private func distance(_ item: MKMapItem) -> CLLocationDistance? {
        guard let origin else { return nil }
        let c = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    private var sorted: [MKMapItem] {
        guard origin != nil else { return items }
        return items.sorted { (distance($0) ?? 0) < (distance($1) ?? 0) }
    }
    /// Yours first, then recommended (nearest first), then the ones you've hidden.
    private var favorites: [MKMapItem] { let _ = hiddenRevision; return sorted.filter { MosqueFavorites.isFavorite($0) } }
    private var visible: [MKMapItem] { let _ = hiddenRevision; return sorted.filter { !MosqueHiding.isHidden($0) } }
    private var others: [MKMapItem] { visible.filter { !MosqueFavorites.isFavorite($0) } }
    private var hidden: [MKMapItem] { let _ = hiddenRevision; return sorted.filter { MosqueHiding.isHidden($0) } }

    private func address(_ item: MKMapItem) -> String {
        let p = item.placemark
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street.isEmpty ? nil : street, p.locality].compactMap { $0 }.joined(separator: ", ")
    }

    private func miles(_ d: CLLocationDistance) -> String {
        Measurement(value: d, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func eta(_ i: Int) -> String? {
        etas[i].map { "\(max(1, Int(($0 / 60).rounded()))) min" }
    }

    var body: some View {
        let list = others
        let mine = favorites
        let muted = hidden
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if searching && items.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for mosques around you…")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                if !mine.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").font(.system(size: 9))
                        Text("my masajid").tracking(1.4).textCase(.uppercase)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
                    .padding(.leading, 4)
                    .padding(.bottom, -8)
                    VStack(spacing: 0) {
                        ForEach(Array(mine.enumerated()), id: \.offset) { i, item in
                            row(item, index: -1, favorite: true)
                            if i < mine.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.green.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.green.opacity(0.18), lineWidth: 1))
                    )
                }
                if let nearest = list.first {
                    nearestCard(nearest, index: 0)
                }
                if list.count > 1 {
                    Text("more nearby")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.bottom, -8)
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated().dropFirst()), id: \.offset) { i, item in
                            row(item, index: i)
                            if i < list.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.045)))
                }
                if !muted.isEmpty {
                    Text("not recommended")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.bottom, -8)
                    VStack(spacing: 0) {
                        ForEach(Array(muted.enumerated()), id: \.offset) { i, item in
                            row(item, index: -1, muted: true)
                            if i < muted.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.03)))
                    Text("Long-press one to recommend it again.")
                        .font(.system(size: 12, weight: .light, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
        .task(id: "\(travelRaw)|\(hiddenRevision)|\(items.count)") { await loadETAs(list) }
        .onReceive(NotificationCenter.default.publisher(for: MosqueHiding.changed)) { _ in hiddenRevision += 1 }
    }

    /// Long-press menu on a mosque: add to / remove from My masajid; stop / start recommending it.
    @ViewBuilder private func hideMenu(_ item: MKMapItem) -> some View {
        if MosqueFavorites.isFavorite(item) {
            Button { MosqueFavorites.setFavorite(item, false) } label: {
                Label("Remove from My masajid", systemImage: "star.slash")
            }
        } else {
            Button { MosqueFavorites.setFavorite(item, true) } label: {
                Label("Add to My masajid", systemImage: "star")
            }
        }
        if MosqueHiding.hiddenOneByOne(item) {
            Button { MosqueHiding.setHidden(item, false) } label: {
                Label("Recommend again", systemImage: "hand.thumbsup")
            }
        } else if MosqueHiding.isHidden(item) {
            Button { MosqueHiding.setHideAhmadiyya(false) } label: {
                Label("Show Ahmadiyya mosques again", systemImage: "eye")
            }
        } else {
            Button(role: .destructive) { MosqueHiding.setHidden(item, true) } label: {
                Label("Don't recommend this mosque", systemImage: "hand.thumbsdown")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mosques")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Text(searching ? "finding mosques…" : "\(visible.count) \(nearYou ? "near you" : "in the area you searched")")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Toggle(isOn: Binding(get: { hideAhmadiyya }, set: { MosqueHiding.setHideAhmadiyya($0) })) {
                    Label("Hide Ahmadiyya mosques", systemImage: "eye.slash")
                }
                Text("Long-press a mosque to add it to My masajid or stop recommending it.")
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(hideAhmadiyya ? Color.green : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(hideAhmadiyya ? Color.green.opacity(0.14) : Color.primary.opacity(0.05)))
            }
            // Drive / walk, for the times in the list (same setting as the map's bar).
            HStack(spacing: 2) {
                ForEach(MosqueTravel.allCases) { mode in
                    let on = travel == mode
                    Button {
                        triggerSomeVibration(type: .light)
                        travelRaw = mode.rawValue
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? Color.green : Color.secondary)
                            .frame(width: 36, height: 30)
                            .background(Capsule().fill(on ? Color.green.opacity(0.14) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            // Leave mosques, back to the qibla.
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close mosques")
        }
    }

    private func nearestCard(_ item: MKMapItem, index: Int) -> some View {
        Button { pick(item) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 10))
                    Text("nearest").tracking(1.4).textCase(.uppercase)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.green)
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.green))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name ?? "Mosque")
                            .font(.system(size: 19, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        let line = address(item)
                        if !line.isEmpty {
                            Text(line)
                                .font(.system(size: 13, weight: .light, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 14) {
                    if let e = eta(index) {
                        Label(e, systemImage: travel.icon)
                    }
                    if let d = distance(item) {
                        Label(miles(d), systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Show")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.green)
                }
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.green.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.green.opacity(0.25), lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { hideMenu(item) }
    }

    private func row(_ item: MKMapItem, index: Int, muted: Bool = false, favorite: Bool = false) -> some View {
        Button { pick(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: favorite ? "star.fill" : icon)
                    .font(.system(size: 13))
                    .foregroundStyle(muted ? Color.secondary : Color.green)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(muted ? Color.primary.opacity(0.06) : Color.green.opacity(0.13)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Mosque")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let line = address(item)
                    if !line.isEmpty {
                        Text(line)
                            .font(.system(size: 12.5, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let d = distance(item) {
                        Text(miles(d))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    if let e = eta(index) {
                        HStack(spacing: 3) {
                            Image(systemName: travel.icon).font(.system(size: 9))
                            Text(e)
                        }
                        .font(.system(size: 11.5, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .opacity(muted ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { hideMenu(item) }
    }

    /// Drive / walk times for the closest six, one after another.
    private func loadETAs(_ list: [MKMapItem]) async {
        etas = [:]
        for (i, item) in list.prefix(6).enumerated() {
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = item
            request.transportType = travel == .walking ? .walking : .automobile
            guard let result = try? await MKDirections(request: request).calculateETA() else { continue }
            if Task.isCancelled { return }
            etas[i] = result.expectedTravelTime
        }
    }
}

// MARK: - The sheet

struct MosqueSheet: View {
    let item: MKMapItem
    /// Pushed from the mosque list: a back button in the header row (no navigation bar — it added
    /// a whole empty row above the name; owner, 2026-09-26).
    var showsBack = false
    @Environment(\.dismiss) private var dismiss
    @State private var hiddenHere = false
    @State private var favorite = false
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
                HStack(alignment: .top, spacing: 12) {
                    if showsBack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to the list")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? "Mosque")
                            .font(.system(size: 26, weight: .light, design: .rounded))
                        if let address {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    // ☆ → My masajid.
                    Button {
                        triggerSomeVibration(type: favorite ? .light : .success)
                        favorite.toggle()
                        MosqueFavorites.setFavorite(item, favorite)
                        if favorite { hiddenHere = false }
                    } label: {
                        Image(systemName: favorite ? "star.fill" : "star")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(favorite ? Color.green : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: favorite)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(favorite ? Color.green.opacity(0.14) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(favorite ? "Remove from My masajid" : "Add to My masajid")
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

                // Stop recommending this one (list, pins, nearest card).
                Button {
                    triggerSomeVibration(type: .light)
                    hiddenHere.toggle()
                    if hiddenHere && favorite { favorite = false; MosqueFavorites.setFavorite(item, false) }
                    MosqueHiding.setHidden(item, hiddenHere)
                } label: {
                    Label(hiddenHere ? "Recommend this mosque again" : "Don't recommend this mosque",
                          systemImage: hiddenHere ? "hand.thumbsup" : "hand.thumbsdown")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .fontDesign(.rounded)
        .task(id: mode) { await loadDrive() }
        .task { await loadScene() }
        .onAppear {
            hiddenHere = MosqueHiding.hiddenOneByOne(item)
            favorite = MosqueFavorites.isFavorite(item)
        }
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
