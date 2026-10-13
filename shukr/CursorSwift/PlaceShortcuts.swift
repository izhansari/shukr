//
//  PlaceShortcuts.swift
//  shukr
//
//  Two Shortcuts / Siri answers about where you are (owner, 2026-10-13), each with a card: Nearby Mosques (a map with
//  the nearest five, a tap = directions — decision nearby-mosques-card A) and Prayed Here ("how many times have I prayed
//  here … and the last time I have prayed in that location"). App target only: they search MapKit, draw a map snapshot
//  and read the prayers, all in shukr's process. iOS 26 (cards with buttons, decision shortcut-buttons-ios26 A).
//

import AppIntents
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: - Where the phone is

/// Where the phone is for a place shortcut: a fresh fix within `wait` s, else the app's last real fix (30 min).
enum ShortcutLocation {
    @MainActor static func current(wait: Double = 6) async -> CLLocation? {
        let t0 = Date()
        // While Using covers a shortcut the person just ran; the session says so to iOS for the length of the call.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let fix: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await u in CLLocationUpdate.liveUpdates() {
                        if u.authorizationDenied || u.authorizationDeniedGlobally { return nil }
                        if let l = u.location, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 150,
                           l.timestamp > t0.addingTimeInterval(-60) { return l }
                    }
                } catch {}
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(wait)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return fix ?? SharedStore.lastKnownLocation()
    }

    /// The app's saved spot whatever its age (a picked city too): near enough to find mosques.
    static func saved() -> CLLocation? {
        guard let store = UserDefaults(suiteName: SharedStore.appGroup) else { return nil }
        let lat = store.double(forKey: "lastLatitude"), lon = store.double(forKey: "lastLongitude")
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }
}

private let placeSage = Color(red: 0.40, green: 0.64, blue: 0.50)

private func distanceText(_ meters: Double, spoken: Bool = false) -> String {
    let f = MKDistanceFormatter()
    f.unitStyle = spoken ? .full : .abbreviated
    return f.string(fromDistance: meters)
}

/// The Nearby Mosques card's map strip: `here` as the blue dot, the mosques as plain sage pins, the nearest larger.
@MainActor func placeSnapshot(here: CLLocationCoordinate2D, pins: [CLLocationCoordinate2D],
                              size: CGSize, dark: Bool) async -> UIImage? {
    let all = [here] + pins
    let lats = all.map(\.latitude), lons = all.map(\.longitude)
    let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    // Room round the pins; wide enough for the strip's shape (it's far wider than tall).
    let latSpan = max((lats.max()! - lats.min()!) * 1.6, 0.006)
    let lonSpan = max((lons.max()! - lons.min()!) * 1.3, latSpan * Double(size.width / size.height) * 0.8)
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    options.size = size
    options.pointOfInterestFilter = .excludingAll
    options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
    options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    guard let shot = try? await MKMapSnapshotter(options: options).start() else { return nil }
    return UIGraphicsImageRenderer(size: size).image { _ in
        shot.image.draw(at: .zero)
        let sage = UIColor(red: 0.40, green: 0.64, blue: 0.50, alpha: 1)
        func dot(_ p: CGPoint, _ r: CGFloat, _ fill: UIColor, ring: CGFloat) {
            UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - r - ring, y: p.y - r - ring, width: 2 * (r + ring), height: 2 * (r + ring))).fill()
            fill.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
        }
        for (i, c) in pins.enumerated().reversed() { dot(shot.point(for: c), i == 0 ? 7 : 5, sage, ring: 2) }
        dot(shot.point(for: here), 5, .systemBlue, ring: 2.5)
    }
}

// MARK: - Nearby Mosques

struct NearbyMosque: Hashable {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let meters: Double
    let address: String?

    static func == (a: Self, b: Self) -> Bool { a.name == b.name && a.meters == b.meters }
    func hash(into h: inout Hasher) { h.combine(name); h.combine(meters) }

    /// Directions in Apple Maps.
    var directions: URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [.init(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"), .init(name: "q", value: name)]
        return c.url!
    }
}

/// A mosque row in the card: directions in Maps. Our own intent handing on `OpenURLIntent` — the system intent used
/// as the button itself did nothing ("Failed to fetch metadata for OpenURLIntent", the sim 2026-10-13).
struct MosqueDirectionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Directions to a Mosque"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Name") var name: String
    @Parameter(title: "Latitude") var latitude: Double
    @Parameter(title: "Longitude") var longitude: Double
    init() {}
    init(_ m: NearbyMosque) { name = m.name; latitude = m.coordinate.latitude; longitude = m.coordinate.longitude }
    func perform() async throws -> some IntentResult & OpensIntent {
        let m = NearbyMosque(name: name, coordinate: .init(latitude: latitude, longitude: longitude), meters: 0, address: nil)
        return .result(opensIntent: OpenURLIntent(m.directions))
    }
}

/// One search per run: the answer and its card share it (the card intent is drawn again after the answer).
@MainActor enum NearbyMosquesSearch {
    enum Outcome { case found(here: CLLocation, [NearbyMosque]), noLocation, failed }
    private static var last: (at: Date, outcome: Outcome)?

    static func run() async -> Outcome {
        if let last, Date().timeIntervalSince(last.at) < 120 { return last.outcome }
        let outcome = await search()
        last = (Date(), outcome)
        return outcome
    }

    private static func search() async -> Outcome {
        guard let here = await ShortcutLocation.current() ?? ShortcutLocation.saved() else { return .noLocation }
        let region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        let found = await MosqueSearch.find(in: region)
        if found.isEmpty && MosqueSearch.lastSearchFailed { return .failed }
        let items = MosqueFavorites.merged(found, in: region).filter { !MosqueHiding.isHidden($0) }
        let list = items.map { item -> NearbyMosque in
            let c = item.placemark.coordinate
            return NearbyMosque(name: item.name ?? "Mosque", coordinate: c,
                                meters: CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: here),
                                address: item.placemark.thoroughfare.map { street in
                                    [item.placemark.subThoroughfare, street].compactMap { $0 }.joined(separator: " ")
                                } ?? item.placemark.locality)
        }
        return .found(here: here, Array(list.sorted { $0.meters < $1.meters }.prefix(NearbyMosquesSnippet.shown)))
    }

    /// The line said with the card.
    nonisolated static func spoken(_ outcome: Outcome) -> String {
        switch outcome {
        case .noLocation: return "I couldn’t tell where you are. Open shukr once so it knows your location, then try again."
        case .failed: return "I couldn’t search for mosques right now. Check your connection and try again."
        case .found(_, let list):
            guard let first = list.first else { return "I couldn’t find a mosque within about 15 miles." }
            return "The nearest mosque is \(first.name), \(distanceText(first.meters, spoken: true)) away."
        }
    }
}

/// Today's Times' look (owner: "match that same aesthetic … sleek and straightforward"): a short map strip, then the
/// nearest eight as rows — the nearest in the sage "now" fill — a tap on one = directions in Maps.
struct NearbyMosquesSnippet: View {
    let outcome: NearbyMosquesSearch.Outcome
    let map: UIImage?
    /// More than fit; the card scrolls in Shortcuts / Siri (owner: "I was expecting it to show more than three").
    static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The map strip is the way into shukr (a separate link fell below the fold of Shortcuts' sheet). The picture
            // fills a strip the card sizes — never the other way round (it widened the card past what iOS shows,
            // clipping both edges).
            Button(intent: FindNearbyMosquesIntent()) {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 100)
                    .overlay { if let map { Image(uiImage: map).resizable().scaledToFill() } else { placeSage.opacity(0.12) } }
                    .overlay(alignment: .bottomTrailing) {
                        Label("Open in shukr", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(placeSage)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(7)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the mosques map in shukr")
            if case .found(_, let list) = outcome, !list.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(list.prefix(Self.shown).enumerated()), id: \.element) { i, m in
                        Button(intent: MosqueDirectionsIntent(m)) { row(m, nearest: i == 0) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Directions to \(m.name), \(distanceText(m.meters, spoken: true))")
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    private func row(_ m: NearbyMosque, nearest: Bool) -> some View {
        // Small fixed type, and a long name wraps to a second line (owner: "Islamic Center of…" didn't say which one;
        // iOS draws a card's text styles larger than in the app, and shrinking to fit left the names in different sizes).
        HStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.system(size: 14))
                .foregroundStyle(nearest ? placeSage : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name)
                    .font(.system(size: 14, weight: nearest ? .semibold : .regular, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let a = m.address {
                    Text(a).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(distanceText(m.meters))
                .font(.system(size: 13, weight: nearest ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .fixedSize()
            Image(systemName: "arrow.triangle.turn.up.right.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(placeSage)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, nearest ? 9 : 6)
        .background {
            if nearest { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(placeSage.opacity(0.16)) }
        }
        .contentShape(Rectangle())
    }
}

/// The one way into shukr under a place card: a quiet sage line, not a big button.
struct PlaceCardLink<I: AppIntent>: View {
    let title: String
    let intent: I
    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: "arrow.up.forward.app")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(placeSage)
                .frame(maxWidth: .infinity).frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 26.0, *)
struct NearbyMosquesCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Nearby Mosques Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let outcome = await NearbyMosquesSearch.run()
        var map: UIImage?
        if case .found(let here, let list) = outcome, !list.isEmpty {
            map = await placeSnapshot(here: here.coordinate, pins: list.prefix(NearbyMosquesSnippet.shown).map(\.coordinate),
                                      size: CGSize(width: 360, height: 110), dark: scheme == .dark)
        }
        return .result(view: AnyView(NearbyMosquesSnippet(outcome: outcome, map: map).environment(\.colorScheme, scheme)))
    }
}

/// "Find Nearby Mosques": the nearest five on a map, each a tap away from directions.
@available(iOS 26.0, *)
struct NearbyMosquesNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Nearby Mosques"
    static var description = IntentDescription(
        "The mosques nearest you on a map, with how far each is. Tap one for directions, or open shukr's map for more.",
        categoryName: "Places", searchKeywords: ["masjid", "mosque", "near me", "nearest", "jumuah", "directions"],
        resultValueName: "Mosques")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let outcome = await NearbyMosquesSearch.run()
        var names: [String] = []
        if case .found(_, let list) = outcome { names = list.map(\.name) }
        return .result(value: names, dialog: IntentDialog(stringLiteral: NearbyMosquesSearch.spoken(outcome)),
                       snippetIntent: NearbyMosquesCardIntent())
    }
}

// MARK: - Prayed Here

/// What you've prayed where you are: within 100 m, or anywhere at the masjid you're at.
struct PrayedHere {
    var here: CLLocation
    var place: String?
    var atMasjid = false
    var count = 0
    var last: (name: String, at: Date)?
    var first: Date?
    var perPrayer: [String: Int] = [:]

    static let radius: Double = 100

    @MainActor static func load() async -> PrayedHere? {
        guard let here = await ShortcutLocation.current(wait: 8) else { return nil }
        var result = PrayedHere(here: here)
        #if DEBUG
        // `-demoPrayedHere YES`: a stand-in history at a masjid (the card's look in the simulator).
        if UserDefaults.standard.bool(forKey: "demoPrayedHere") {
            result.place = "Cary Masjid"; result.atMasjid = true; result.count = 23
            result.last = ("Asr", Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            result.first = Calendar.current.date(byAdding: .month, value: -5, to: Date())
            result.perPrayer = ["Fajr": 2, "Dhuhr": 9, "Asr": 6, "Maghrib": 4, "Isha": 2]
            return result
        }
        #endif
        guard let container = SharedStore.widgetContainer else { return result }
        let rows = (try? ModelContext(container).fetch(FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted == true }))) ?? []
        func distance(_ r: PrayerModel) -> Double? {
            guard let lat = r.latPrayedAt, let lon = r.longPrayedAt else { return nil }
            return CLLocation(latitude: lat, longitude: lon).distance(from: here)
        }
        var near = rows.filter { (distance($0) ?? .infinity) <= radius }
        // At a masjid: its name, and every prayer saved there (a big masjid's car park is more than 100 m across).
        let masjids = near.compactMap(\.mosqueName).filter { !$0.isEmpty }
        if let masjid = Dictionary(grouping: masjids, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            result.place = masjid
            result.atMasjid = true
            near += rows.filter { $0.mosqueName == masjid && (distance($0) ?? .infinity) <= 1_000 }
        }
        // One per prayer per day (a day can hold duplicates; a marked row wins either way).
        var seen = Set<String>()
        let unique = near.filter { seen.insert("\($0.dayKey)|\($0.name)").inserted }
        result.count = unique.count
        let when = { (r: PrayerModel) in r.timeAtComplete ?? r.startTime }
        if let newest = unique.max(by: { when($0) < when($1) }) { result.last = (newest.name, when(newest)) }
        result.first = unique.map(when).min()
        for r in unique { result.perPrayer[r.name, default: 0] += 1 }
        if result.place == nil {
            if let named = PrayerPlaceNames.name(here.coordinate) { result.place = named } else { result.place = await streetName(here) }
        }
        return result
    }

    /// "123 Main St" / the place's name, within 3 s (it's only the card's title).
    private static func streetName(_ here: CLLocation) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let p = try? await CLGeocoder().reverseGeocodeLocation(here).first else { return nil }
                if let street = p.thoroughfare { return [p.subThoroughfare, street].compactMap { $0 }.joined(separator: " ") }
                return p.name ?? p.locality
            }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// "today at 4:32 PM" / "yesterday at …" / "on Mon, Oct 6 at …" / "on Mar 4, 2025 at …".
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let time = shortTimePM(d)
        if cal.isDateInToday(d) { return "today at \(time)" }
        if cal.isDateInYesterday(d) { return "yesterday at \(time)" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEE MMM d" : "MMM d y")
        return "on \(f.string(from: d)) at \(time)"
    }

    var spoken: String {
        guard count > 0, let last else { return "You haven’t marked a prayer here yet." }
        if count == 1 { return "You’ve prayed here once: \(last.name), \(Self.when(last.at))." }
        return "You’ve prayed here \(count) times. The last was \(last.name), \(Self.when(last.at))."
    }
}

/// Next Prayer's look (owner: "match that same aesthetic"): one row on the Live Activity's soft surface — the place
/// and when you last prayed there on the left, the count where Next Prayer keeps its time — then the five, slim.
struct PrayedHereSnippet: View {
    let summary: PrayedHere?
    @Environment(\.colorScheme) private var scheme
    private static let five = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: summary?.atMasjid == true ? "building.columns" : "mappin.and.ellipse")
                        .font(.system(size: 18))
                        .foregroundStyle(placeSage)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary?.place ?? "Where you are")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let s = summary {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(s.count)")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(s.count == 1 ? "prayer" : "prayers")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize()
                    }
                }
                if let s = summary, s.count > 0 {
                    HStack(spacing: 0) {
                        ForEach(Self.five, id: \.self) { name in
                            let n = s.perPrayer[name, default: 0]
                            HStack(spacing: 4) {
                                Image(systemName: prayerIcon(for: name).replacingOccurrences(of: ".fill", with: ""))
                                    .font(.system(size: 10))
                                Text("\(n)")
                                    .font(.system(size: 13, design: .rounded))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(n > 0 ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(name) \(n)")
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LASoft.surface(LATuning.current, scheme)))
            PlaceCardLink(title: "See your prayers on the map", intent: OpenPrayerSpotsIntent())
        }
        .padding(10)   // the prayer cards' margin
    }

    private var subtitle: String {
        guard let s = summary else { return "Couldn’t tell where you are right now." }
        guard let last = s.last else { return "No prayers marked here yet." }
        return "Last: \(last.name), \(PrayedHere.when(last.at))"
    }
}

/// One look-up per run: the answer and its card share it.
@MainActor enum PrayedHereLookup {
    private static var last: (at: Date, summary: PrayedHere?)?
    static func run() async -> PrayedHere? {
        if let last, Date().timeIntervalSince(last.at) < 60 { return last.summary }
        let s = await PrayedHere.load()
        last = (Date(), s)
        return s
    }
}

@available(iOS 26.0, *)
struct PrayedHereCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Prayed Here Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let s = await PrayedHereLookup.run()
        return .result(view: AnyView(PrayedHereSnippet(summary: s).environment(\.colorScheme, scheme)))
    }
}

/// "How many times have I prayed here": the count where you are and when you last prayed there.
@available(iOS 26.0, *)
struct PrayedHereIntent: AppIntent {
    static var title: LocalizedStringResource = "Count My Prayers Here"
    static var description = IntentDescription(
        "How many prayers you've marked where you are now (or at the masjid you're at), and when you last prayed there.",
        categoryName: "Places", searchKeywords: ["prayed here", "how many times", "last time", "masjid", "location"],
        resultValueName: "Prayers Here")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetIntent {
        let s = await PrayedHereLookup.run()
        let line = s?.spoken ?? "I couldn’t tell where you are right now. Try again in a moment."
        return .result(value: s?.count ?? 0, dialog: IntentDialog(stringLiteral: line), snippetIntent: PrayedHereCardIntent())
    }
}

/// The card's "See your prayers on the map": shukr's map with the prayer spots up.
struct OpenPrayerSpotsIntent: AppIntent {
    static let flag = "widgetPrayerSpots"
    static var title: LocalizedStringResource = "Open My Prayers on the Map"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

#if DEBUG
/// The cards' map picture, for `SnippetPreviewHost`.
enum PlaceShortcutPreview {
    @MainActor static func snapshot(here: CLLocationCoordinate2D, pins: [CLLocationCoordinate2D],
                                    size: CGSize, dark: Bool) async -> UIImage? {
        await placeSnapshot(here: here, pins: pins, size: size, dark: dark)
    }
}
#endif
