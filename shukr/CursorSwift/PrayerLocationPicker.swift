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
    /// Where the prayer is pinned now.
    var original: CLLocationCoordinate2D?
    /// Where the app recorded it when it was marked (differs from `original` once edited).
    var recorded: CLLocationCoordinate2D?
    /// Where the pin stands on the map view (screen points) — the middle of the map above the sheet.
    var pinPoint: CGPoint = .zero
}

/// The picking pin: the "stick" (owner, 2026-09-28, D5818BB9 — "that green little stick thing … was sleek"; the
/// SF-symbol teardrop options were turned down): a 24 pt green head with a 3 pt white edge on a thin darker-green
/// needle whose tip is the spot, a small shadow at the tip. Lifts while the map moves, drops when it stops.
/// Drawn in a fixed `size` frame with the tip at `tip` (the map's `PickPinView` hosts it at its point;
/// `CenterPin` centres it). It replaced the time editor's thin SF `mappin` too ("just a shadow" — 723D0745).
struct PickPin: View {
    let lifted: Bool
    static let size = CGSize(width: 48, height: 78)
    /// Where the needle's tip sits in that frame (the shadow's centre).
    static let tip = CGPoint(x: 24, y: 74)
    static let head: CGFloat = 24
    static let needle: CGFloat = 28          // from the head's bottom edge to the tip

    var body: some View {
        let t = Self.tip
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 14, height: 6)
                .scaleEffect(lifted ? 0.6 : 1)
                .opacity(lifted ? 0.5 : 1)
                .position(x: t.x, y: t.y)
            ZStack {
                Capsule()
                    .fill(Color(red: 0.14, green: 0.55, blue: 0.24))
                    .frame(width: 2, height: Self.needle + 2)
                    .position(x: t.x, y: t.y - (Self.needle + 2) / 2)
                Circle()
                    .fill(Color.green)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: Self.head, height: Self.head)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .position(x: t.x, y: t.y - Self.needle - Self.head / 2)
            }
            .offset(y: lifted ? -12 : 0)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(lifted ? .easeOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.45), value: lifted)
        .allowsHitTesting(false)
    }
}

/// The pin in the middle of the map; its tip is the spot. Lifts while the map moves.
struct CenterPin: View {
    let moving: Bool
    var body: some View {
        // The tip sits on the view's centre (the map's centre, where the spot is read).
        PickPin(lifted: moving)
            .offset(y: PickPin.size.height / 2 - PickPin.tip.y)
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
    /// Where the prayer is pinned now: Set location lights up once the pin is somewhere else.
    let original: CLLocationCoordinate2D?
    /// Where the app recorded it when it was marked: the distance is measured from here, and
    /// there's a way back to it (owner, 2026-09-26: "so I can always revert it").
    let recorded: CLLocationCoordinate2D?
    let centre: CLLocationCoordinate2D?
    let moving: Bool
    /// Fly the map to a searched place.
    var onJump: (CLLocationCoordinate2D) -> Void
    var onCancel: () -> Void
    var onSet: (CLLocationCoordinate2D) -> Void
    /// Inside a sheet (the map's prayer page): no card of its own.
    var embedded = false
    var setTitle = "Set location"
    /// The address search opened / closed (the sheet grows for the suggestions and keyboard).
    var onSearching: (Bool) -> Void = { _ in }

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
    private var markedSpot: CLLocationCoordinate2D? { recorded ?? original }
    /// The pin is away from where it was marked (offer the way back).
    private var awayFromMarked: Bool {
        guard let markedSpot, let centre else { return false }
        return metres(centre, markedSpot) > 3
    }
    /// "0.3 mi from where you marked it" (miles / feet or km / m, per the phone's region).
    private var distanceLine: String? {
        guard let markedSpot, let centre else { return nil }
        let m = metres(centre, markedSpot)
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
                    HStack(spacing: 8) {
                        Label(distanceLine, systemImage: awayFromMarked ? "arrow.left.and.right" : "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(awayFromMarked ? Color.primary.opacity(0.75) : .secondary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: distanceLine)
                        Spacer(minLength: 4)
                        if awayFromMarked, let markedSpot {
                            Button {
                                jumpedName = nil
                                onJump(markedSpot)
                            } label: {
                                Label("Back", systemImage: "arrow.uturn.backward")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.green)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back to where you marked it")
                        }
                    }
                } else {
                    Text("Drag the map, or tap the address to type one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                buttons
            }
        }
        .padding(embedded ? 0 : 18)
        .background(embedded ? Color.clear : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(embedded ? 0 : 0.12), radius: 16, y: 4)
        .padding(.horizontal, embedded ? 0 : 12)
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.2), value: searching)
        .onChange(of: searching) { _, on in onSearching(on) }
        .onAppear {
            guard let spot = centre ?? original else { return }
            // Known already (the page looked it up): no "Looking up…" flash.
            if let known = PrayerSpotAddress.cached(spot) { address = known } else { lookUp(spot) }
        }
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
        SaveCancelButtons(canSave: changed, saveTitle: setTitle, onCancel: onCancel) {
            if let centre { onSet(centre) }
        }
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
        .onChange(of: query) { _, q in search.update(q, near: markedSpot ?? centre) }
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
    /// Where the app recorded it when marked (same as `original` until it's edited).
    var recorded: CLLocationCoordinate2D?
    var onCancel: () -> Void
    var onPick: (CLLocationCoordinate2D) -> Void

    @State private var camera: MapCameraPosition
    @State private var centre: CLLocationCoordinate2D?
    @State private var moving = false

    init(prayerName: String, original: CLLocationCoordinate2D?, recorded: CLLocationCoordinate2D? = nil,
         onCancel: @escaping () -> Void, onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.prayerName = prayerName
        self.original = original
        self.recorded = recorded
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
                    // Where it's pinned now.
                    Annotation("", coordinate: original, anchor: .center) {
                        Circle().fill(Color.gray.opacity(0.7)).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let recorded, let original,
                   CLLocation(latitude: recorded.latitude, longitude: recorded.longitude)
                    .distance(from: CLLocation(latitude: original.latitude, longitude: original.longitude)) > 3 {
                    // Edited before: where the app recorded it.
                    Annotation("Marked here", coordinate: recorded, anchor: .center) {
                        Circle().strokeBorder(Color.green, lineWidth: 2).frame(width: 14, height: 14)
                            .background(Circle().fill(.white))
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
            SpotPickerCard(original: original, recorded: recorded ?? original, centre: centre, moving: moving,
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
    static func cached(_ c: CLLocationCoordinate2D) -> String? {
        cache[String(format: "%.4f,%.4f", c.latitude, c.longitude)]
    }
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

#if DEBUG
/// `-demoPinRender`: the picking pin (resting and lifted) over real map tiles — standard and satellite, light and
/// dark — written to <app data>/tmp/pin-<look>.png (the simulators won't open the map; feedback 723D0745).
enum PickPinRender {
    @MainActor static func run() async {
        let centre = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        for (name, satellite, dark) in [("standard-light", false, false), ("satellite-dark", true, true)] {
            let o = MKMapSnapshotter.Options()
            o.region = MKCoordinateRegion(center: centre, latitudinalMeters: 300, longitudinalMeters: 300)
            o.size = CGSize(width: 200, height: 160)
            o.scale = 3
            o.mapType = satellite ? .hybrid : .standard
            o.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            guard let snap = try? await MKMapSnapshotter(options: o).start() else { continue }
            let pins = HStack(spacing: 30) {
                PickPin(lifted: false)
                PickPin(lifted: true)
            }
            let renderer = ImageRenderer(content: pins)
            renderer.scale = 3
            guard let pinImage = renderer.uiImage else { continue }
            let out = UIGraphicsImageRenderer(size: o.size, format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f
            }()).image { _ in
                snap.image.draw(at: .zero)
                let s = pinImage.size
                pinImage.draw(at: CGPoint(x: (o.size.width - s.width) / 2, y: o.size.height / 2 - PickPin.tip.y + 20))
            }
            try? out.pngData()?.write(to: FileManager.default.temporaryDirectory.appending(path: "pin-\(name).png"))
        }
        print("PINRENDER done")
    }
}
#endif
