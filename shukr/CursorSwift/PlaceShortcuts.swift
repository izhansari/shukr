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

/// A map picture for a card: `here` as a blue dot, numbered sage pins (`pins`), or one pin on `here` itself.
@MainActor func placeSnapshot(here: CLLocationCoordinate2D, pins: [CLLocationCoordinate2D], hereIsPin: Bool,
                                      size: CGSize, dark: Bool) async -> UIImage? {
    let all = [here] + pins
    let lats = all.map(\.latitude), lons = all.map(\.longitude)
    let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    let least = hereIsPin ? 0.0025 : 0.006   // one spot: down to its streets
    let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, least),
                                longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, least))
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(center: center, span: span)
    options.size = size
    options.pointOfInterestFilter = .excludingAll
    options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    guard let shot = try? await MKMapSnapshotter(options: options).start() else { return nil }
    return UIGraphicsImageRenderer(size: size).image { _ in
        shot.image.draw(at: .zero)
        let sage = UIColor(red: 0.40, green: 0.64, blue: 0.50, alpha: 1)
        if hereIsPin {
            let p = shot.point(for: here)
            let r = CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)
            UIColor.white.setFill(); UIBezierPath(ovalIn: r.insetBy(dx: -2.5, dy: -2.5)).fill()
            sage.setFill(); UIBezierPath(ovalIn: r).fill()
            if let glyph = UIImage(systemName: "hands.and.sparkles.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(in: r.insetBy(dx: 4.5, dy: 4.5))
            }
            return
        }
        // The pins, farthest first so the nearest sits on top.
        for (i, c) in pins.enumerated().reversed() {
            let p = shot.point(for: c)
            let r = CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
            UIColor.white.setFill(); UIBezierPath(ovalIn: r.insetBy(dx: -2, dy: -2)).fill()
            sage.setFill(); UIBezierPath(ovalIn: r).fill()
            let label = "\(i + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.white]
            let s = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: attrs)
        }
        let p = shot.point(for: here)
        UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)).fill()
        UIColor.systemBlue.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)).fill()
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
        return .found(here: here, Array(list.sorted { $0.meters < $1.meters }.prefix(5)))
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

struct NearbyMosquesSnippet: View {
    let outcome: NearbyMosquesSearch.Outcome
    let map: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let map {
                Image(uiImage: map)
                    .resizable().scaledToFill()
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.bottom, 4)
            }
            if case .found(_, let list) = outcome, !list.isEmpty {
                ForEach(Array(list.enumerated()), id: \.element) { i, m in
                    Button(intent: OpenURLIntent(m.directions)) { row(i + 1, m) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Directions to \(m.name), \(distanceText(m.meters, spoken: true))")
                }
            }
            Button(intent: FindNearbyMosquesIntent()) {
                Text("Open in shukr")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(placeSage)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Capsule().fill(placeSage.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(14)
    }

    private func row(_ n: Int, _ m: NearbyMosque) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(placeSage))
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(.body, design: .rounded)).lineLimit(1)
                if let a = m.address {
                    Text(a).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(distanceText(m.meters))
                .font(.system(.subheadline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(placeSage)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
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
            map = await placeSnapshot(here: here.coordinate, pins: list.map(\.coordinate), hereIsPin: false,
                                      size: CGSize(width: 360, height: 150), dark: scheme == .dark)
        }
        return .result(view: AnyView(NearbyMosquesSnippet(outcome: outcome, map: map).environment(\.colorScheme, scheme)))
    }
}

/// "Find Nearby Mosques": the nearest five on a map, each a tap away from directions.
@available(iOS 26.0, *)
struct NearbyMosquesNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Nearby Mosques"
    static var description = IntentDescription(
        "The five mosques nearest you on a map, with how far each is. Tap one for directions, or open shukr's map for more.",
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

struct PrayedHereSnippet: View {
    let summary: PrayedHere?
    let map: UIImage?
    private static let five = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = summary {
                HStack(spacing: 12) {
                    if let map {
                        Image(uiImage: map).resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(s.place ?? "Where you are", systemImage: s.atMasjid ? "building.columns.fill" : "mappin.and.ellipse")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(s.count)")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(s.count == 1 ? "prayer here" : "prayers here")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let last = s.last {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last prayed here")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Text("\(last.name), \(PrayedHere.when(last.at))")
                            .font(.system(.body, design: .rounded))
                    }
                    HStack(spacing: 0) {
                        ForEach(Self.five, id: \.self) { name in
                            let n = s.perPrayer[name, default: 0]
                            VStack(spacing: 4) {
                                Image(systemName: prayerIcon(for: name).replacingOccurrences(of: ".fill", with: ""))
                                    .font(.system(size: 15))
                                    .foregroundStyle(n > 0 ? placeSage : Color.secondary.opacity(0.5))
                                Text("\(n)")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(n > 0 ? Color.primary : Color.secondary.opacity(0.6))
                                Text(name)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.08)))
                    if let first = s.first, s.count > 1 {
                        Text("Since \(first.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Mark a prayer here and it will count here.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Couldn’t tell where you are right now.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Button(intent: OpenPrayerSpotsIntent()) {
                Text("See your prayers on the map")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(placeSage)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Capsule().fill(placeSage.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
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
        var map: UIImage?
        if let s {
            map = await placeSnapshot(here: s.here.coordinate, pins: [], hereIsPin: true,
                                      size: CGSize(width: 64, height: 64), dark: scheme == .dark)
        }
        return .result(view: AnyView(PrayedHereSnippet(summary: s, map: map).environment(\.colorScheme, scheme)))
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
    @MainActor static func snapshot(here: CLLocationCoordinate2D, pins: [CLLocationCoordinate2D], hereIsPin: Bool,
                                    size: CGSize, dark: Bool) async -> UIImage? {
        await placeSnapshot(here: here, pins: pins, hereIsPin: hereIsPin, size: size, dark: dark)
    }
}
#endif
