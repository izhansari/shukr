//
//  PrayerLocationPicker.swift
//  shukr
//
//  "Where did you pray?" (owner, 2026-09-26). A pin fixed in the middle of a map: drag the map
//  until the pin sits where you prayed, or tap the address and type one. The card under it shows
//  the address (or one of your masajid by name) and how far the pin is from where the prayer was
//  marked. Two hosts share the pieces here (`CenterPin`, `SpotPickerTitle`, `SpotPickerCard`):
//  - `PrayerLocationPicker`: its own SwiftUI map, as a sheet over the time editor (Salah list).
//  - The prayer map itself (LocationMapView2): "Change location" on a prayer's page turns the big
//    map into the picker — no extra sheet (`LocationViewModel.beginMove`, `MapPickOverlay`).
//  Saving goes through `PrayerViewModel.movePrayer`, which re-checks the masjid and rescores.
//

import SwiftUI
import MapKit

/// The picking map's centre and whether it's moving, for the overlay only (per-frame values: kept
/// off the map's view model so nothing else re-renders while the map pans).
@Observable final class SpotPickState {
    var centre: CLLocationCoordinate2D?
    var moving = false
    /// Where the prayer was pinned before.
    var original: CLLocationCoordinate2D?
}

/// The pin in the middle of the map; its tip is the spot. Lifts while the map moves.
struct CenterPin: View {
    let moving: Bool
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(moving ? 0.12 : 0.25))
                .frame(width: moving ? 8 : 12, height: moving ? 3 : 5)
            Image(systemName: "mappin")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Color.green)
                .shadow(color: .black.opacity(0.25), radius: moving ? 6 : 2, y: moving ? 6 : 1)
                .offset(y: moving ? -30 : -20)
        }
        .animation(.spring(duration: 0.3, bounce: 0.45), value: moving)
        .allowsHitTesting(false)
    }
}

/// The "Where did you pray Asr?" capsule over the picking map.
struct SpotPickerTitle: View {
    let prayerName: String
    var body: some View {
        Text("Where did you pray \(prayerName)?")
            .font(.headline)
            .fontDesign(.rounded)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .mapGlass(Capsule())
    }
}

/// The card under the picking map: where the pin is (tap to type an address), how far it is from
/// where the prayer was marked, Cancel / Set location.
struct SpotPickerCard: View {
    let original: CLLocationCoordinate2D?
    let centre: CLLocationCoordinate2D?
    let moving: Bool
    /// Fly the map to a searched place.
    var onJump: (CLLocationCoordinate2D) -> Void
    var onCancel: () -> Void
    var onSet: (CLLocationCoordinate2D) -> Void

    @State private var address: String?
    @State private var lookup: Task<Void, Never>?
    @State private var searching = false
    @State private var query = ""
    @State private var search = AddressSearch()
    /// The place picked from the search, shown by name while the pin stays on it.
    @State private var jumpedName: String?
    @State private var jumpedAt: CLLocationCoordinate2D?
    @FocusState private var fieldFocused: Bool

    private func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    private var changed: Bool {
        guard let centre else { return false }
        guard let original else { return true }
        return metres(centre, original) > 3
    }
    /// One of your masajid under the pin (the same 100 m the masjid check uses).
    private var masjid: String? { centre.flatMap { MasjidDetector.favoriteMasjid(near: $0) } }
    private var jumpedLabel: String? {
        guard let jumpedName, let jumpedAt, let centre, metres(centre, jumpedAt) < 30 else { return nil }
        return jumpedName
    }
    private var title: String {
        masjid ?? jumpedLabel ?? address ?? (centre == nil ? "Finding you…" : "Looking up the address…")
    }
    /// "0.3 mi from where you marked it" (miles / feet or km / m, per the phone's region).
    private var distanceLine: String? {
        guard let original, let centre else { return nil }
        let m = metres(centre, original)
        guard m > 3 else { return "Where you marked it" }
        let text = Measurement(value: m, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.significantDigits(1...2))))
        return "\(text) from where you marked it"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if searching {
                searchBox
            } else {
                addressButton
                if let distanceLine {
                    Label(distanceLine, systemImage: changed ? "arrow.left.and.right" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(changed ? Color.primary.opacity(0.75) : .secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: distanceLine)
                } else {
                    Text("Drag the map, or tap the address to type one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                buttons
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .padding(.horizontal, 12)
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.2), value: searching)
        .onAppear { if let spot = centre ?? original { lookUp(spot) } }
        .onChange(of: moving) { _, isMoving in
            if !isMoving, let centre { lookUp(centre) }
        }
    }

    /// Where the pin is; tap to type an address instead.
    private var addressButton: some View {
        Button {
            searching = true
            fieldFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: masjid != nil ? "building.columns" : "mappin.and.ellipse")
                    .foregroundStyle(masjid != nil ? Color.sage : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if masjid != nil || jumpedLabel != nil, let address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .opacity(moving ? 0.4 : 1)   // the last address, until the pin drops
                Spacer(minLength: 8)
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Type an address")
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.primary)
                    .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                    .contentShape(Capsule())
            }
            Button {
                if let centre { onSet(centre) }
            } label: {
                // Same Save look as the time editor: gray until there's a change.
                Text("Set location")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(changed ? Color.green : Color.secondary)
                    .background(Capsule().strokeBorder(changed ? Color.green : Color(.separator),
                                                       lineWidth: changed ? 1.5 : 1))
                    .contentShape(Capsule())
            }
            .disabled(!changed)
            .animation(.easeInOut(duration: 0.2), value: changed)
        }
        .buttonStyle(.plain)
    }

    // MARK: typing an address

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search an address or place", text: $query)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = search.results.first { choose(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))

            ForEach(Array(search.results.prefix(5).enumerated()), id: \.offset) { _, result in
                Button { choose(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).foregroundStyle(.primary).lineLimit(1)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                searching = false
                query = ""
                fieldFocused = false
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .onChange(of: query) { _, q in search.update(q, near: original ?? centre) }
    }

    private func choose(_ result: MKLocalSearchCompletion) {
        Task {
            guard let (coordinate, name) = await AddressSearch.place(for: result) else { return }
            jumpedName = name
            jumpedAt = coordinate
            searching = false
            query = ""
            fieldFocused = false
            onJump(coordinate)
        }
    }

    /// Street + city under the pin, once the map settles (a new drag cancels the last lookup).
    private func lookUp(_ c: CLLocationCoordinate2D) {
        lookup?.cancel()
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let place = await PrayerSpotAddress.lookUp(c)
            guard !Task.isCancelled else { return }
            address = place
        }
    }
}

/// Address / place suggestions as you type (MKLocalSearchCompleter), near the prayer's spot.
@Observable final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ query: String, near centre: CLLocationCoordinate2D?) {
        if let centre {
            completer.region = MKCoordinateRegion(center: centre, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
            completer.cancel()
        } else {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    /// Where a suggestion is, and its name.
    static func place(for completion: MKLocalSearchCompletion) async -> (CLLocationCoordinate2D, String)? {
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response?.mapItems.first else { return nil }
        return (item.placemark.coordinate, item.name ?? completion.title)
    }
}

/// The picker with its own map — a sheet over the time editor.
struct PrayerLocationPicker: View {
    let prayerName: String
    /// Where the prayer is pinned now (nil = nowhere yet: the map opens on you).
    let original: CLLocationCoordinate2D?
    var onCancel: () -> Void
    var onPick: (CLLocationCoordinate2D) -> Void

    @State private var camera: MapCameraPosition
    @State private var centre: CLLocationCoordinate2D?
    @State private var moving = false

    init(prayerName: String, original: CLLocationCoordinate2D?,
         onCancel: @escaping () -> Void, onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.prayerName = prayerName
        self.original = original
        self.onCancel = onCancel
        self.onPick = onPick
        _camera = State(initialValue: original.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 350, longitudinalMeters: 350))
        } ?? .userLocation(fallback: .automatic))
        _centre = State(initialValue: original)
    }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
                if let original {
                    // Where it was pinned before.
                    Annotation("", coordinate: original, anchor: .center) {
                        Circle().fill(Color.gray.opacity(0.7)).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                ForEach(MosqueFavorites.all, id: \.id) { m in
                    Marker(m.name, systemImage: "star.fill",
                           coordinate: CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                        .tint(.green)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                centre = ctx.region.center
                if !moving { moving = true }
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                centre = ctx.region.center
                moving = false
            }

            CenterPin(moving: moving)
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top) {
            SpotPickerTitle(prayerName: prayerName).padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            SpotPickerCard(original: original, centre: centre, moving: moving,
                           onJump: { c in
                               withAnimation(.easeInOut(duration: 0.8)) {
                                   camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 350, longitudinalMeters: 350))
                               }
                           },
                           onCancel: onCancel, onSet: onPick)
                .padding(.bottom, 28)
        }
    }
}

/// "123 Main St, Cary" for a spot (cached per ~10 m).
enum PrayerSpotAddress {
    private static var cache: [String: String] = [:]
    static func lookUp(_ c: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        if let hit = cache[key] { return hit }
        let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let place = [street.isEmpty ? placemark?.name : street, placemark?.locality]
            .compactMap { $0 }.joined(separator: ", ")
        guard !place.isEmpty else { return nil }
        cache[key] = place
        return place
    }
}
