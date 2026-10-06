//
//  CompassWidget.swift
//  shukr
//
//  Created on 1/22/25.
//


// MARK: - perplexity compass widget

import WidgetKit
import SwiftUI
import CoreLocation
import Adhan
import AppIntents
import Combine
import SwiftData


struct PrayersWidget: Widget {
    let kind: String = "PrayersWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, provider: PrayersWidgetTimelineProvider()) { entry in
            PrayersWidgetView(entry: entry)
                .containerBackground(entry.background, for: .widget)
//                .containerBackground(Color("bgColor")/*Color.white*/, for: .widget)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Prayers")
        .description("See todays prayers & how much time is left")
        // + the Lock Screen (2026-09-26): a ring by the clock, a card under it, a line above it.
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

//moved PrayersWidgetLocationManager to locMan file

struct PrayersWidgetEntry: TimelineEntry {
    let date: Date
    let heading: Double
    let latitude: Double
    let longitude: Double
    let toggleShowAllTImes: Bool
    let prayerDict: [String: (start: Date, end: Date, window: TimeInterval)]
    let todayPrayerTimes: PrayerTimes
    let locationName: String // New property
    let textToggle: Bool
    /// Prayers already prayed today → their score (0...1), read from the shared store.
    var completedScores: [String: Double] = [:]
    var completedToday: Set<String> { Set(completedScores.keys) }
    /// Tomorrow's Fajr, for the circle once the day's prayers are over.
    var nextFajr: Date? = nil
    /// Tomorrow's sunrise: tomorrow's Fajr window, so the circle is live from its start (audit B11) until a reload
    /// builds the new day.
    var nextSunrise: Date? = nil
    /// The bottom corners (Edit Widget; notes #1).
    var leftCorner: WidgetCornerAction = .qibla
    var rightCorner: WidgetCornerAction = .tasbeeh
    /// Prayed dots in their score colours (Edit Widget); off = one plain colour.
    var scoreColors = true
    /// The share of the free space above the ring: 60 / 40 reads centred (owner picked it from 50 /
    /// 55 / 60, feedback D3DC914D / 43D36031; the setting is gone, its stored key ignored).
    var ringAbove = 0.6
    /// Edit Widget → Style (the home-screen widget only).
    var style: WidgetStyle = .system

    /// "Follows the sun" (`auto`) night: from Maghrib until the next sunrise (the app's auto rule — `isDaytime` is
    /// after Fajr's window, before Maghrib), and before this prayer day's sunrise.
    var isNight: Bool {
        guard let sunrise = prayerDict["Sunrise"]?.start, let maghrib = prayerDict["Maghrib"]?.start else { return false }
        return date < sunrise || (date >= maghrib && date < sunrise.addingTimeInterval(86_400))
    }
    /// The scheme Style forces on the home-screen widget; nil = follow the phone.
    var forcedScheme: ColorScheme? {
        switch style {
        case .system: nil
        case .light: .light
        case .dark: .dark
        case .auto: isNight ? .dark : .light
        }
    }
    /// The container's colour, matching `forcedScheme`: the app's soft surface (decision widget-soft-ring B) —
    /// grey-blue light, charcoal dark; following the phone when the Style does.
    var background: Color {
        switch forcedScheme {
        case .dark?: WidgetSoft.surface(.dark)
        case .light?: WidgetSoft.surface(.light)
        default: Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.10, alpha: 1)
                                                                 : UIColor(red: 0.890, green: 0.898, blue: 0.933, alpha: 1) })
        }
    }

    /// The same data, shown from `date` on (a later timeline entry); `list` overrides whether the
    /// times list shows (the ring comes back `WidgetListState.openFor` after it opened).
    func at(_ date: Date, list: Bool? = nil) -> PrayersWidgetEntry {
        PrayersWidgetEntry(date: date, heading: heading, latitude: latitude, longitude: longitude,
                           toggleShowAllTImes: list ?? toggleShowAllTImes, prayerDict: prayerDict,
                           todayPrayerTimes: todayPrayerTimes, locationName: locationName, textToggle: textToggle,
                           completedScores: completedScores, nextFajr: nextFajr, nextSunrise: nextSunrise,
                           leftCorner: leftCorner, rightCorner: rightCorner, scoreColors: scoreColors,
                           ringAbove: ringAbove, style: style)
    }
}


import WidgetKit
import SwiftUI
import CoreLocation
import Adhan

struct PrayersWidgetTimelineProvider: AppIntentTimelineProvider {
    // No location manager in the widget: the app stores lastLatitude / lastLongitude /
    // lastCityName in the app group and the widget reads those. The widget's own GPS + compass
    // manager rewrote lastCityName on every fix, and cross-process defaults changes invalidate
    // every @AppStorage in the app — the Settings pickers flickered because of it (2026-09-25).

    func placeholder(in context: Context) -> PrayersWidgetEntry {
        // Provide a placeholder with *dummy* prayer times so SwiftUI can render a preview
        let dummyCoordinates = Coordinates(latitude: 0, longitude: 0)
        let dummyParams = CalculationMethod.northAmerica.params
        let dummyDateComponents = PrayerUtils.gregorian.dateComponents([.year, .month, .day], from: Date())
        
        // Safe to force-unwrap for placeholder if you want
        let dummyTimes = PrayerTimes(coordinates: dummyCoordinates,
                                     date: dummyDateComponents,
                                     calculationParameters: dummyParams)!
        let dummyWindow = PrayerUtils.createDummyWindows()
        let dummyLocation = "Dummy Location"
        
        return PrayersWidgetEntry(
            date: Date(),
            heading: 0,
            latitude: 0,
            longitude: 0,
            toggleShowAllTImes: false, prayerDict: dummyWindow,
            todayPrayerTimes: dummyTimes, locationName: dummyLocation, textToggle: false
        )
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> PrayersWidgetEntry {
        // The gallery / Edit Widget preview always shows the ring (what people get by default).
        let entry = await makeEntry(configuration)
        return context.isPreview ? entry.at(entry.date, list: false) : entry
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<PrayersWidgetEntry> {
        let t0 = ContinuousClock.now
        WidgetPerf.log("timeline \(context.family) start")
        let entry = await makeEntry(configuration)
        WidgetPerf.log("timeline \(context.family) entry made \(WidgetPerf.ms(since: t0)) ms")
        #if DEBUG
        // `-demoWidgetShots` (the app sets the flag): the small widget drawn at exact sizes, for
        // checking the layout on phones the simulator doesn't have at hand.
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        if group?.bool(forKey: "demoWidget.renderShots") == true {
            group?.set(false, forKey: "demoWidget.renderShots")
            await MainActor.run { Self.renderDebugShots(entry) }
        }
        #endif
        var entries = [entry]
        // The times list doesn't stick: the ring again `openFor` after it was opened (one entry).
        var base = entry
        if entry.toggleShowAllTImes, let openedAt = WidgetListState.openedAt {
            base = entry.at(max(openedAt.addingTimeInterval(WidgetListState.openFor), entry.date.addingTimeInterval(1)), list: false)
            entries.append(base)
        }
        // The moments the circle changes, for the prayer it shows now AND the one after it (owner,
        // 2026-09-30: the next one's colour changes and last hour used to wait on iOS's next reload).
        // Per prayer: its start and end (the Lock Screen's dashed "next" ring turns live on time), the
        // colour changes (Perfect → On time → Late; the fill itself runs live), an hour before the end
        // (the time left), and with "27m" / "27min" an entry each minute of that last hour — iOS can't
        // tick those itself; the countdown style ("27:13") needs none. Only the Lock Screen circle shows
        // those: every other family gets a few entries — the home widget's ~120 per-minute entries made
        // each tap (ring, chevron, mark) slow to redraw (owner, 2026-10-01; a long timeline was "not performant").
        let perMinute = context.family == .accessoryCircular
        let shown = PrayersWidgetView.WidgetPrayerCircleView(entry: base).relevantPrayer
        var moments = Self.moments(for: shown, after: base.date, perMinute: perMinute)
        #if DEBUG
        // Speed test (My Dev Stuff → Widget: fewest updates): the entry (and the list's return) only.
        if WidgetSpeedTest.fewestEntries && context.family == .systemSmall {
            WidgetPerf.log("timeline \(context.family) speed test: \(entries.count) entries")
            return Timeline(entries: entries, policy: .after(Date().addingTimeInterval(60)))
        }
        #endif
        if shown.end > base.date {
            let following = PrayersWidgetView.WidgetPrayerCircleView(entry: base.at(shown.end.addingTimeInterval(1), list: false)).relevantPrayer
            if following.start >= shown.end, following.name != shown.name || following.start != shown.start {
                moments += Self.moments(for: following, after: base.date, perMinute: perMinute)
            }
        }
        // Style "Follows the sun" flips at Maghrib and at sunrise: an entry at each still ahead.
        if entry.style == .auto, let sunrise = entry.prayerDict["Sunrise"]?.start,
           let maghrib = entry.prayerDict["Maghrib"]?.start {
            moments += [sunrise, maghrib, sunrise.addingTimeInterval(86_400)].filter { $0 > base.date }
        }
        // one prayer's end is often the next one's start
        var ahead = Set(moments).sorted()
        // The home widget: only the next two moments. iOS renders every entry of a timeline before it shows
        // the first, and each carries the live ring and text — ~10 of them made every tap (ring, chevron,
        // mark) take ~3 s to redraw, where main's single entry was instant (owner, 2026-10-01). The 60 s
        // refresh below asks for the rest; a colour change can land late if iOS is slow to grant it.
        if context.family == .systemSmall { ahead = Array(ahead.prefix(2)) }
        entries += ahead.map { base.at($0, list: false) }
        let nextRefresh = Date().addingTimeInterval(60)
        WidgetPerf.log("timeline \(context.family) done \(entries.count) entries \(WidgetPerf.ms(since: t0)) ms")
        return Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(nextRefresh))
    }

    /// When one prayer's circle changes (see the timeline above), after `now`.
    static func moments(for prayer: (name: String, current: Bool, start: Date, end: Date, window: TimeInterval),
                        after now: Date, perMinute: Bool) -> [Date] {
        guard prayer.end > prayer.start, prayer.end > now else { return [] }
        var moments = [prayer.start, prayer.end]
        let lastHour = prayer.end.addingTimeInterval(-PrayerLockScreenView.timeLeftFrom)
        if lastHour > prayer.start { moments.append(lastHour) }
        if perMinute {   // "27m" is written per entry (LockTimeLeft)
            var minute = prayer.end.addingTimeInterval(-60)
            while minute > now, minute >= max(lastHour, prayer.start) {
                moments.append(minute)
                minute = minute.addingTimeInterval(-60)
            }
        }
        moments += PrayerScoring.gradeChanges(start: prayer.start, end: prayer.end)
        return moments.filter { $0 > now }
    }

    #if DEBUG
    /// Ring and list, light and dark, score colours on and off (the list), at 158 pt (6.1" phones)
    /// and 170 pt, into the app group's Library/Caches/widget-shots.
    @MainActor static func renderDebugShots(_ entry: PrayersWidgetEntry) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Caches/widget-shots", isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { PrayersWidgetView.LiveArc.snapshotAt = nil }
        /// Drawn as the home screen would: `phoneDark` is the phone's appearance, the container
        /// colour is the entry's (Style can force it).
        func render(_ shown: PrayersWidgetEntry, size: Double, phoneDark: Bool, _ name: String) {
            PrayersWidgetView.LiveArc.snapshotAt = shown.date
            let view = PrayersWidgetView(entry: shown)
                .frame(width: size, height: size)
                .background(shown.background)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, phoneDark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() { try? data.write(to: dir.appendingPathComponent(name + ".png")) }
        }
        for size in [158.0, 170.0] {
            let px = "w\(Int(size))"
            for phoneDark in [false, true] {
                let phone = phoneDark ? "phoneDark" : "phoneLight"
                // Each Style on the ring.
                for style in [WidgetStyle.system, .light, .dark] {
                    var shown = entry.at(entry.date, list: false)
                    shown.style = style
                    render(shown, size: size, phoneDark: phoneDark, "\(px)-style-\(style.rawValue)-\(phone)")
                }
                // The soft ring on the soft surface, whatever the entry's Style.
                PrayersWidgetView.LiveArc.snapshotAt = entry.date
                let soft = PrayersWidgetView(entry: entry.at(entry.date, list: false))
                    .frame(width: size, height: size)
                    .background(WidgetSoft.surface(phoneDark ? .dark : .light))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .environment(\.colorScheme, phoneDark ? .dark : .light)
                let r = ImageRenderer(content: soft)
                r.scale = 3
                if let data = r.uiImage?.pngData() { try? data.write(to: dir.appendingPathComponent("\(px)-soft-\(phone).png")) }
                // The times list, and with only the first prayer marked (the others that started
                // show as empty circles to tap).
                render(entry.at(entry.date, list: true), size: size, phoneDark: phoneDark, "\(px)-list-\(phone)")
                var open = entry.at(entry.date, list: true)
                open.completedScores = entry.completedScores.filter { $0.key == "Fajr" }
                render(open, size: size, phoneDark: phoneDark, "\(px)-list-open-\(phone)")
            }
            // The ring's colour through a prayer's window (Asr, not marked): its start, +31 min
            // (Perfect → On time), the On time → Late point, and after its end.
            if let asr = entry.prayerDict["Asr"] {
                var open = entry
                open.completedScores = entry.completedScores.filter { $0.key != "Asr" }
                let changes = PrayerScoring.gradeChanges(start: asr.start, end: asr.end)
                let points: [(String, Date)] = [("start", asr.start.addingTimeInterval(60)),
                                                ("31min", asr.start.addingTimeInterval(31 * 60)),
                                                ("late", (changes.last ?? asr.end).addingTimeInterval(60)),
                                                ("ended", asr.end.addingTimeInterval(60))]
                for (label, date) in points {
                    for phoneDark in [false, true] {
                        render(open.at(date, list: false), size: size, phoneDark: phoneDark,
                               "\(px)-asr-\(label)-\(phoneDark ? "phoneDark" : "phoneLight")")
                    }
                }
            }
            // The Lock Screen circle through Asr (not marked): more than an hour left, then the last hour.
            if size == 158, let asr = entry.prayerDict["Asr"] {
                var open = entry
                open.completedScores = entry.completedScores.filter { $0.key != "Asr" }
                for (label, date) in [("early", asr.start.addingTimeInterval(20 * 60)),
                                      ("lastHour", asr.end.addingTimeInterval(-42 * 60)),
                                      ("last5", asr.end.addingTimeInterval(-5 * 60))] {
                    let shown = open.at(date, list: false)
                    for (look, bg, fg) in [("vibrant", Color.black, Color.white), ("wallpaper", Color(red: 0.23, green: 0.35, blue: 0.5), Color.white)] {
                        let view = PrayerLockScreenView(entry: shown, family: .accessoryCircular)
                            .frame(width: 76, height: 76)
                            .foregroundStyle(fg)
                            .padding(10)
                            .background(bg)
                            .environment(\.colorScheme, .dark)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 3
                        if let data = renderer.uiImage?.pngData() { try? data.write(to: dir.appendingPathComponent("lock-circular-\(label)-\(look).png")) }
                    }
                }
            }
            // "Follows the sun" either side of Maghrib and of sunrise (the phone in light mode).
            if let maghrib = entry.prayerDict["Maghrib"]?.start, let sunrise = entry.prayerDict["Sunrise"]?.start {
                for (label, date) in [("beforeMaghrib", maghrib.addingTimeInterval(-60)), ("afterMaghrib", maghrib.addingTimeInterval(60)),
                                      ("beforeSunrise", sunrise.addingTimeInterval(-60)), ("afterSunrise", sunrise.addingTimeInterval(60))] {
                    var shown = entry.at(date, list: false)
                    shown.style = .auto
                    render(shown, size: size, phoneDark: false, "\(px)-auto-\(label)")
                }
            }
        }
    }
    #endif

    /// Helper function that calculates the data you want in the widget entry.
    private func makeEntry(_ configuration: ConfigurationAppIntent? = nil) async -> PrayersWidgetEntry {
        // Grab the values from your location manager
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let showLocation = WidgetListState.isOpen(at: Date())
        let latitude = store.double(forKey: "lastLatitude")
        let longitude = store.double(forKey: "lastLongitude")
        let locationName = store.string(forKey: "lastCityName") ?? "Wonderland"
        let textToggle = store.bool(forKey: "widgetTextToggle")
//        let latitude = locationManager.latitude
//        let longitude = locationManager.longitude
//        let locationName = locationManager.locationName // Fetch updated location name
        let heading: Double = 0   // a widget is a snapshot; no live compass

        // Attempt to get real prayer times from your utility
        // Fallback if there's an error (e.g. location not yet available).
        var prayerTimes: PrayerTimes
        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
        // The prayer day (before the rollover hour it's still yesterday's date), like the app.
        let prayerDate = PrayerDay.date()
        let dateComponents = PrayerUtils.gregorian.dateComponents([.year, .month, .day], from: prayerDate)
        var windows = PrayerUtils.createDummyWindows()
        var nextFajr: Date?, nextSunrise: Date?
        do {
            let params = PrayerUtils.getCalculationParameters()
            prayerTimes = try PrayerUtils.getPrayerTimes(for: prayerDate, coordinates: coordinates, params: params)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: prayerDate) ?? prayerDate
            let tomorrowTimes = try? PrayerUtils.getPrayerTimes(for: tomorrow, coordinates: coordinates, params: params)
            nextFajr = tomorrowTimes?.fajr
            nextSunrise = tomorrowTimes?.sunrise
            windows = PrayerUtils.createWindowsFromTimes(prayerTimes, on: prayerDate, nextFajr: nextFajr)
        } catch {
            // adhan gives no times for this place and day (polar latitudes in midnight sun / polar night).
            // The old fallback force-unwrapped a second attempt with the same coordinates — nil again, and
            // the extension crashed on every timeline (audit A5). Try ISNA once, optionally; else a dummy
            // day that renders as "open shukr" rather than crashing.
            print("widget: no prayer times for \(coordinates) on \(dateComponents): \(error)")
            if let fallback = PrayerTimes(coordinates: coordinates, date: dateComponents,
                                          calculationParameters: CalculationMethod.northAmerica.params) {
                prayerTimes = fallback
            } else {
                prayerTimes = PrayerUtils.dummyPrayerTimes()   // the gallery's 0°,0° day; the windows stay dummy
            }
        }
        
        // Finally, create our entry
        let entry = PrayersWidgetEntry(
            date: Date(),
            heading: heading,
            latitude: latitude,
            longitude: longitude,
            toggleShowAllTImes: showLocation, prayerDict: windows,
            todayPrayerTimes: prayerTimes, locationName: locationName, textToggle: textToggle,
            completedScores: SharedStore.completedPrayerScoresToday(),
            nextFajr: nextFajr, nextSunrise: nextSunrise,
            leftCorner: configuration?.corners.left ?? .qibla,
            rightCorner: configuration?.corners.right ?? .tasbeeh,
            scoreColors: configuration?.scoreColors ?? true,
            ringAbove: 0.6,
            style: configuration?.style ?? .system
        )
        #if DEBUG
        // Screenshots (`-demoWidget` in the app): fixed scores / corners instead of the store's.
        if let demo = store.string(forKey: "demoWidget.scores") {
            var scores: [String: Double] = [:]
            for pair in demo.split(separator: ",") {
                let kv = pair.split(separator: "=")
                if kv.count == 2, let v = Double(kv[1]) { scores[String(kv[0])] = v }
            }
            let corners = (store.string(forKey: "demoWidget.corners") ?? "").split(separator: ",").compactMap { WidgetCornerAction(rawValue: String($0)) }
            return PrayersWidgetEntry(date: entry.date, heading: 0, latitude: latitude, longitude: longitude,
                                      toggleShowAllTImes: showLocation, prayerDict: windows,
                                      todayPrayerTimes: prayerTimes, locationName: locationName, textToggle: textToggle,
                                      completedScores: scores, nextFajr: nextFajr, nextSunrise: nextSunrise,
                                      leftCorner: corners.first ?? entry.leftCorner,
                                      rightCorner: corners.count > 1 ? corners[1] : entry.rightCorner,
                                      scoreColors: store.bool(forKey: "demoWidget.plain") ? false : entry.scoreColors,
                                      ringAbove: entry.ringAbove, style: entry.style)
        }
        #endif
        return entry
    }
}



struct PrayersWidgetView: View {
    var entry: PrayersWidgetEntry
    let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    @Environment(\.widgetFamily) private var family

    /// The home screen widget crossfades, simply (owner, 2026-10-02: "put the simple crossfade transition on our main
    /// prayer widget btw. i miss that"): ring ⇄ times list and changed text fade one into the other — no number
    /// morphing, nothing fancier (owner, 2026-10-01: "we dont need any fancy transitions"). The live ring's arc keeps
    /// its own identity (LiveArc: crossfaded, it dipped). The Lock Screen still swaps at once.
    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            PrayerLockScreenView(entry: entry, family: family)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .contentTransition(.identity)
        default:
            homeScreen
                .contentTransition(.opacity)
        }
    }

    private var homeScreen: some View {
        ZStack {
            if entry.toggleShowAllTImes {
                TimesListView(entry: entry).transition(.opacity)
            } else {
                WidgetPrayerCircleView(entry: entry).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ForcedScheme(scheme: entry.forcedScheme))
    }

    /// Edit Widget → Style: Light / Dark / Follows the sun win over the phone's appearance; System leaves it.
    struct ForcedScheme: ViewModifier {
        let scheme: ColorScheme?
        func body(content: Content) -> some View {
            if let scheme { content.environment(\.colorScheme, scheme) } else { content }
        }
    }

    /// Today's times in the app's look (2026-09-27, notes #1): the city as a tiny caption; the five
    /// prayers + Sunrise (dimmed); the current prayer in sage, done ones with their score dot (Score
    /// colours applies), the next one tagged. Rounded light type like the ring. A down chevron at the
    /// bottom centre — the spot where the ring's up chevron opened it — goes back to the ring
    /// (owner, 2026-09-28, feedback D56CB3C2); it also goes back by itself after
    /// `WidgetListState.openFor` (the timeline's next entry).
    struct TimesListView: View {
        let entry: PrayersWidgetEntry
        private let order = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

        var body: some View {
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.locationName.lowercased())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 5)
                        .padding(.bottom, 2)

                    // The rows share what's left above the chevron, so Isha fits on the smallest
                    // widget (~158 pt on a 6.1" phone).
                    ForEach(order, id: \.self) { name in
                        if let p = entry.prayerDict[name] {
                            row(name, p.start, p.end)
                                .frame(maxHeight: 22)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, WidgetChevronButton.reserved)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                WidgetChevronButton(up: false)
                    .padding(.bottom, 6)
            }
        }

        private func nameText(_ name: String, _ current: Bool) -> some View {
            Text(name)
                .font(.system(size: 12, weight: current ? .regular : .light, design: .rounded))
                .fixedSize()
        }

        /// A row. A prayer that has started is a button over the whole row: not marked → marked here, scored at the tap like the corner check (an earlier
        /// prayer may come out Late / Qaza); marked → the app opens to "Unmark Asr?" (the widget never
        /// unmarks). Upcoming prayers and Sunrise never are.
        @ViewBuilder private func row(_ name: String, _ start: Date, _ end: Date) -> some View {
            let content = rowContent(name, start, end)
            if name != "Sunrise", start <= entry.date {
                if entry.completedScores[name] != nil {
                    Button(intent: AskUnmarkPrayerIntent(prayerName: name, prayerStart: start)) { content }
                        .buttonStyle(.plain)
                } else {
                    Button(intent: MarkFromListIntent(prayerName: name, prayerStart: start, prayerEnd: end)) { content }
                        .buttonStyle(.plain)
                }
            } else {
                content
            }
        }

        private func rowContent(_ name: String, _ start: Date, _ end: Date) -> some View {
            let sunrise = name == "Sunrise"
            let current = !sunrise && start <= entry.date && entry.date < end
            let score = entry.completedScores[name]
            return HStack(spacing: 6) {
                // A tappable row's dot is a bigger circle to tap: empty = not marked
                // yet, filled = marked. Upcoming prayers keep the small dot (nothing to tap).
                let tappable = !sunrise && start <= entry.date
                // A prayer still to come: the app's dashed ring, as big as the others (dashes need the room).
                PrayerDot(score: score, started: start <= entry.date, current: current, colored: entry.scoreColors,
                          size: tappable || !sunrise ? 11 : 7)
                    .frame(width: 11)
                    .opacity(sunrise ? 0 : 1)
                // No NEXT tag in the list (owner, 2026-10-06: "get rid of the word NEXT in widgets prayer list"); the
                // dashed dot says a prayer is still to come.
                nameText(name, current)
                Spacer(minLength: 4)
                Text(start, style: .time)
                    .font(.system(size: 11, weight: current ? .regular : .light, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
            }
            .foregroundStyle(current ? Brand.sage : (sunrise ? Color.secondary.opacity(0.7) : Color.primary))
            .padding(.vertical, 1)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(current ? Brand.sage.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
    }

    /// One prayer at a glance (display only): done = filled in its score colour, faded like the
    /// app's list dots; started but not marked = outlined; not started = dim.
    struct PrayerDot: View {
        let score: Double?
        let started: Bool
        var current = false
        /// Off: a prayed dot is plain grey, whatever the score (owner, 2026-09-27: not green).
        var colored = true
        var size: CGFloat = 7

        var body: some View {
            ZStack {
                if let score {
                    let tint = colored ? PrayerScoring.color(for: score) : Color.gray
                    Circle().fill(tint.opacity(0.6))
                    Circle().strokeBorder(tint.opacity(0.9), lineWidth: 0.75)
                } else if started {
                    Circle().strokeBorder(current ? Brand.sage : Color.secondary.opacity(0.7), lineWidth: 1)
                } else {
                    // The app's future ring (decision list-future-ring H): 8 short dashes, each 18 % of its period, in
                    // the row's grey, fitted so the last doesn't run into the first.
                    Circle()
                        .inset(by: 0.6)
                        .stroke(Color.secondary.opacity(0.6), style: Self.futureDashes(size))
                }
            }
            .frame(width: size, height: size)
        }

        static func futureDashes(_ size: CGFloat) -> StrokeStyle {
            let period = CGFloat.pi * (size - 1.2) / 8
            return StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [period * 0.18, period * 0.82])
        }
    }

    struct WidgetPrayerCircleView: View {
        let entry: PrayersWidgetEntry
        /// An unmarked prayer's last hour (an entry lands at end − 60 min: `moments`).
        private var lastHour: Bool { relevantPrayer.current && relevantPrayer.end.timeIntervalSince(entry.date) <= 60 * 60 }
        private var lastHourLeftShown: Bool { lastHour && !entry.textToggle }
        
        let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        

        var relevantPrayer: (name: String, current: Bool, start: Date, end: Date, window: TimeInterval) {
            // The entry's time, not the clock: WidgetKit can render a future entry ahead of time.
            let now = entry.date
            
            /// Check if indexed prayer is a current prayer -- else check if indexed prayer is the next one.
            /// Prayers already completed today are skipped so the circle moves on after a tap; the
            /// top-left check shows the current one was prayed.
            // Sunrise isn't a prayer: between sunrise and Dhuhr the ring shows Dhuhr as NEXT, as the
            // app's circle does (its day has no Sunrise row). It showed "Sunrise" with a moon and the
            // time to Dhuhr (owner, 2026-09-28, feedback 99D47ABE). The list still shows Sunrise.
            for name in prayerOrder where name != "Sunrise" && !entry.completedToday.contains(name) {
                if let prayer = entry.prayerDict[name] {
                    //if prayer.start <= now  && now < prayer.end && name != "Sunrise" { // current prayer
                    if prayer.start <= now  && now < prayer.end { // current prayer

                        return (name, true, prayer.start, prayer.end, prayer.window)
                    }
                    else if now < prayer.start { // next prayer
                        return (name, false, prayer.start, prayer.end, prayer.window)
                    }
                }
            }
            
            /// If we've gone through all prayers and none are current or next up then it means we've passed the last prayer of the day.
            /// So lets display tomorrow's first prayer — its real time. (This used to return `Date()`,
            /// which read "Fajr at <now>" once Isha was marked, 2026-09-25.)
            let fajr = entry.nextFajr ?? now
            // With its window (audit B11): the timeline gets an entry at tomorrow's Fajr, live from its start — the day's
            // turn used to wait on iOS's next reload, and Fajr kept reading "next" after it had started.
            if let sunrise = entry.nextSunrise, sunrise > fajr {
                return ("Fajr", fajr <= now && now < sunrise, fajr, sunrise, sunrise.timeIntervalSince(fajr))
            }
            return ("Fajr", false, fajr, fajr, 0)
            
        }
                
        var progress: Double {
            let now = entry.date
            let startDate = relevantPrayer.start
            let endDate = relevantPrayer.end
            
            // Ensure `now` is within the range of startDate and endDate
            guard now >= startDate && now <= endDate else {
                return now < startDate ? 0.0 : 1.0
            }
            let totalDuration = endDate.timeIntervalSince(startDate)
            let elapsedDuration = now.timeIntervalSince(startDate)

            return elapsedDuration / totalDuration
        }
        
        /// The prayer whose window is open right now (Sunrise isn't one), marked or not.
        private var prayerInWindow: String? {
            let now = entry.date
            return prayerOrder.first { name in
                guard name != "Sunrise", let p = entry.prayerDict[name] else { return false }
                return p.start <= now && now < p.end
            }
        }

        /// The app's rule (`PrayerScoring`), the colour the prayer would score if marked now:
        /// Perfect green for the first 30 min, On time yellow for the first half of the rest, Late
        /// red for the second half, grey once the window has ended. The timeline has an entry at
        /// each change (`PrayerScoring.gradeChanges`). It used to be a fraction-of-the-window rule
        /// (green to half, yellow to ¾), so it read green while the app's circle was yellow (owner).
        private var progressColor: Color {
            let p = relevantPrayer
            guard p.current, entry.date <= p.end else { return .gray }
            return PrayerScoring.color(for: PrayerScoring.score(start: p.start, end: p.end, markedAt: entry.date))
        }


        
        var body: some View {
            ZStack {
//                Color.black
//                    .ignoresSafeArea()
                
                // Between the widget's top edge and the chevron's circle, the free space splits
                // `entry.ringAbove` above the ring (60 % by default): dead centre read a touch high
                // (owner, 2026-09-28, feedback D3DC914D; before that, centred in the whole widget it
                // nearly touched the chevron — 99D47ABE).
                GeometryReader { geo in
                let free = max(0, geo.size.height - WidgetChevronButton.clearance - 90)
                VStack(spacing: 0) {
                    Color.clear.frame(height: free * entry.ringAbove)

                    // Circular Timer with Text Button
                    Button(intent: textToggleIntent()){
                        ZStack {
                            // The track, like the app's (CircleTrack): the solid band for a prayer
                            // that's on, the thin dashed ring for one that hasn't started (with
                            // "NEXT" over a dimmed name below).
                            if PrayersWidgetView.softRing {
                                // The app's soft ring (its public look): the raised band in the page's surface; a prayer
                                // still to come draws its dashes inside the band.
                                WidgetSoftBand(width: 4.5)
                                if !relevantPrayer.current {
                                    Circle().stroke(Color.secondary.opacity(0.5), style: PrayersWidgetView.upcomingDashes(diameter: 90))
                                }
                            } else if relevantPrayer.current {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                            } else {
                                // Stronger than the app's (0.35 / 0.75 pt): at widget size, in dark
                                // mode especially, the ring was hard to see (owner, 2026-09-27).
                                // The app's dashes (UpcomingTrack.style(diameter:): 3 on, 5 off, a whole number of them
                                // round the ring, so the last doesn't run into the first at 3 o'clock).
                                Circle()
                                    .stroke(Color.secondary.opacity(0.75), style: PrayersWidgetView.upcomingDashes(diameter: 90))   // a touch stronger, like the app (2026-09-28)
                            }

                            if relevantPrayer.current {
                                LiveArc(start: relevantPrayer.start, end: relevantPrayer.end, color: progressColor,
                                        soft: PrayersWidgetView.softRing)
                            }
                            
                            // Same type as the app's main circle and Insights ring (light, rounded,
                            // thin secondary caption), scaled from the 200 pt ring to this 90 pt one.
                            VStack(spacing: 2) {
                                HStack(alignment: .center, spacing: 4){
                                    Image(systemName: prayerIcon(for: relevantPrayer.name))
                                        .font(.system(size: 11, weight: .light))
                                    Text(relevantPrayer.name)
                                        .font(.system(size: 15, weight: .light, design: .rounded))
                                }
                                .foregroundStyle(relevantPrayer.current ? Color.primary : Color.primary.opacity(0.55))
                                // "NEXT" over the name without taking space, so the name stays put.
                                .overlay(alignment: .top) {
                                    if !relevantPrayer.current && NextLabel.shown {
                                        Text("next")
                                            .font(.system(size: 6, weight: .medium, design: .rounded))
                                            .tracking(1.4)
                                            .textCase(.uppercase)
                                            .foregroundStyle(.tertiary)
                                            .fixedSize()
                                            .offset(y: -15)   // the app's tag, scaled: set apart from the name
                                    }
                                }
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                Group {
                                    if entry.textToggle != lastHour {
                                        Text(relevantPrayer.current ? relevantPrayer.end : relevantPrayer.start, style: .relative)
                                    } else {
                                        Text(relevantPrayer.current ? "ends " : "at ")
                                            + Text(relevantPrayer.current ? relevantPrayer.end : relevantPrayer.start, style: .time)
                                    }
                                }
                                // The app's last hour (PrayerTimeLine `lastHourLeft`): time left is the default, in the
                                // name's colour and weight; the tap shows when it ends (owner: "the 60 min rule … like
                                // we have in watch and ios").
                                .font(.system(size: 10, weight: lastHourLeftShown ? .light : .thin, design: .rounded))
                                .foregroundStyle(lastHourLeftShown ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            }
                        }
                        .frame(width: 90, height: 90) // Scaled for widget size
                        
                    }
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                }

                // The mark-prayed check top left (it was top right, beside a list button — owner,
                // 2026-09-28, feedback D56CB3C2), the top right empty; along the bottom the two
                // corners chosen in Edit Widget (Qibla / Tasbeeh by default, or Daily Ayah, 99 Names,
                // None) with an up chevron between them that opens today's times. The ring sits in
                // the true centre: the top and bottom rows are the same height.
                VStack {
                    HStack {
                        checkButton
                        Spacer()
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        corner(entry.leftCorner)
                        Spacer(minLength: 2)
                        WidgetChevronButton(up: true)
                        Spacer(minLength: 2)
                        corner(entry.rightCorner)
                    }
                }
                .padding(6)
            }
        }

        /// A chosen corner, or an empty 30 pt slot for None (so the chevron stays centred).
        @ViewBuilder private func corner(_ action: WidgetCornerAction) -> some View {
            if let intent = action.intent, let symbol = action.symbol {
                CornerButton(intent: intent, systemImage: symbol)
            } else {
                Color.clear.frame(width: 30, height: 30)
            }
        }

        /// Filled once the prayer whose window is open has been prayed (the circle has moved on
        /// to the next one); otherwise it marks the shown prayer, once it has started.
        @ViewBuilder private var checkButton: some View {
            let shown = relevantPrayer
            if let current = prayerInWindow, entry.completedToday.contains(current) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
            } else {
                let canComplete = shown.start <= entry.date && !entry.completedToday.contains(shown.name) && shown.name != "Sunrise"   // sunrise isn't a prayer
                Button(intent: MarkCompleteIntent(prayerName: shown.name, prayerStart: shown.start, prayerEnd: shown.end)) {
                    Image(systemName: "circle")
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(canComplete ? 1 : 0.35)
                .disabled(!canComplete)
            }
        }
        
    }

    /// Ring ⇄ today's times, from the same spot at the bottom centre: an up chevron in a faint
    /// circle on the ring, a down chevron on the list (owner, 2026-09-28, feedback D56CB3C2).
    struct WidgetChevronButton: View {
        let up: Bool
        /// Height the list keeps free above the bottom edge for it (6 pt inset + its 30 pt target,
        /// less the target's slack round the 22 pt circle).
        static let reserved: CGFloat = 30
        /// From the bottom edge to the top of its visible circle (6 inset + 4 slack + 22).
        static let clearance: CGFloat = 32

        var body: some View {
            Button(intent: showListToggleIntent()) {
                Image(systemName: up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(up ? "Today's prayer times" : "Back to the ring")
        }
    }

    /// The app's ring — a thin butt-cap arc in the score colour on the pale band — filling live
    /// between timeline reloads. A widget can't animate its own drawing; the stock timer-driven
    /// `ProgressView(timerInterval:)` is what the system keeps updating, but it draws a thick,
    /// round-capped ring with a tinted track. So it's used only as a mask for the app's own thin
    /// arc, sized so its ~8.7 pt stroke covers the arc's radius. Its track (about 30 % alpha) is
    /// thresholded away: drawn white on black, pushed down and through a steep contrast, then
    /// luminance → alpha, so the unfilled track lets nothing through and the fill all of it
    /// (owner, BB277A98: "we never had the background ring colored"). Masking twice (fa63e22) only
    /// squared the tint to ~9 % and made a reload dim the arc; one plain mask (8a6f160) showed it
    /// at ~30 %.
    /// The soft ring (the app's public look) instead of the grey band (owner, decision widget-soft-ring B: "i like it").
    static let softRing = true

    static func upcomingDashes(diameter: CGFloat) -> StrokeStyle {
        let period: CGFloat = 8, dashShare: CGFloat = 3 / 8
        let circumference = CGFloat.pi * diameter
        let fitted = circumference / max((circumference / period).rounded(), 1)
        return StrokeStyle(lineWidth: 1.3, dash: [fitted * dashShare, fitted * (1 - dashShare)])
    }

    struct LiveArc: View {
        let start: Date
        let end: Date
        let color: Color
        /// The soft ring's arc: as wide as its band, round ends, a glow (the app's public look).
        var soft = false
        private var stroke: StrokeStyle { soft ? StrokeStyle(lineWidth: 4.5, lineCap: .round) : StrokeStyle(lineWidth: 2.5, lineCap: .butt) }
        #if DEBUG
        /// The DEBUG renders draw a static arc at this time (ImageRenderer can't run the timer).
        static var snapshotAt: Date?
        #endif

        /// One stable view with no per-render inputs (no AnyView, no entry time), and no
        /// animation or content transition: a reload (the ring's tap flips its time text) used to
        /// crossfade the masked live arc, and with the alpha squared by the double mask the arc
        /// visibly dipped to ~70 % for half a second (owner, 2026-09-28). One mask: the dip is
        /// ~10 % mid-crossfade (sim frames). The stock ring dips the same and is fat; a static arc
        /// doesn't dip but doesn't move.
        var body: some View {
            arc
                .transaction { $0.animation = nil }
                .contentTransition(.identity)
                .transition(.identity)
        }

        @ViewBuilder private var arc: some View {
            #if DEBUG
            if let at = Self.snapshotAt {
                let f = end > start ? min(max(at.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1) : 1
                Circle().trim(from: 0, to: f)
                    .stroke(color, style: stroke)
                    .rotationEffect(.degrees(-90))
            } else {
                live
            }
            #else
            live
            #endif
        }

        @ViewBuilder private var live: some View {
            #if DEBUG
            // Speed test (My Dev Stuff → Widget: still ring): a static arc, no timer view or mask.
            if WidgetSpeedTest.stillRing {
                let f = end > start ? min(max(Date().timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1) : 1
                Circle().trim(from: 0, to: f)
                    .stroke(color, style: stroke)
                    .rotationEffect(.degrees(-90))
            } else {
                masked
            }
            #else
            masked
            #endif
        }

        private var masked: some View {
            Circle()
                .stroke(color, style: stroke)
                .mask { liveRing }
                .shadow(color: soft ? color.opacity(0.45) : .clear, radius: 3)
        }

        private var liveRing: some View {
            ZStack {
                Color.black
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.white)
                .labelsHidden()
            }
            .frame(width: 98, height: 98)
            // Track ≈ 0.3 grey → below 0; fill 1 → ~1 (brightness −0.35, then contrast ×3 round 0.5).
            .compositingGroup()
            .brightness(-0.35)
            .contrast(3)
            .luminanceToAlpha()
        }
    }

    struct CornerButton: View {
        let intent: any AppIntent
        let systemImage: String

        var body: some View {
            Button(intent: intent) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    struct BottomRowButtonStyle: View {
        let intent: any AppIntent
        let systemImage: String
        
        var body: some View {
            Button(intent: intent) {
                Image(systemName: systemImage)
                    .font(.system(size: 12)) // Adjust font size as needed
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.primary/*.white*/)
            }
            .buttonStyle(.plain)
        }
        
    }
    
    struct debugDetailsView: View {
        let entry: PrayersWidgetEntry
        var body: some View {
            HStack{
                Text("meth:")
                Text("\(entry.todayPrayerTimes.calculationParameters.method)")
            }
            HStack{
                Text("mad:")
                Text("\(entry.todayPrayerTimes.calculationParameters.madhab)")
            }
            Text("Lat: \(entry.latitude, specifier: "%.4f")")
            Text("Long: \(entry.longitude, specifier: "%.4f")")
        }
    }
    
}





#if DEBUG
import SwiftUI
import WidgetKit
import Adhan

#Preview(as: .systemSmall) {
    PrayersWidget()
} timeline: {
    // 1. Create some dummy coordinates and parameters
    let dummyCoordinates = Coordinates(latitude: 40.7128, longitude: -74.0060)
    let dummyDateComponents = PrayerUtils.gregorian.dateComponents([.year, .month, .day], from: Date())
    let dummyParams = CalculationMethod.northAmerica.params
    let dummyWindows = PrayerUtils.createDummyWindows()
    let dummyLocationName = "dummy location"

    // 2. Force-unwrap a dummy PrayerTimes. Safe enough for preview purposes.
    let dummyPrayerTimes = PrayerTimes(
        coordinates: dummyCoordinates,
        date: dummyDateComponents,
        calculationParameters: dummyParams
    )!

    // 3. Pass that to your custom widget entry
    PrayersWidgetEntry(
        date: .now,
        heading: 10,
        latitude: 33,
        longitude: 43,
        toggleShowAllTImes: false, prayerDict: dummyWindows,
        todayPrayerTimes: dummyPrayerTimes, locationName: dummyLocationName, textToggle: false
    )
}
#endif


//struct WidgetPrayerCircleView: View {
//
//    var body: some View {
//        ZStack {
//            Color.black
//                .ignoresSafeArea()
//
//            VStack{
//                Spacer()
//
//                // Circular Timer with Text Button
//                Button(action: {
//                    // Add action here
//                }) {
//                    ZStack {
//                        Circle()
//                            .stroke(Color.gray.opacity(0.2), lineWidth: 6)
//
//                        Circle()
//                            .trim(from: 0, to: 0.75) // Adjust progress value (0 to 1)
//                            .stroke(
//                                AngularGradient(
//                                    gradient: Gradient(colors: [Color.green, Color.gray]),
//                                    center: .center
//                                )
//                                ,
//                                style: StrokeStyle(lineWidth: 2, lineCap: .butt)
//                            )
//                            .rotationEffect(.degrees(-90))
//
//                        VStack(spacing: 4) {
//                            HStack(alignment: .center, spacing: 0){
//                                Image(systemName: "sun.and.horizon.fill")
//                                    .font(.system(size: 15))
//                                    .foregroundColor(.white)
//                                Text("Asr")
//                                    .font(.system(size: 12, weight: .bold))
//                                    .foregroundColor(.white)
//                            }
//                            Text("3h 22m left")
//                                .font(.system(size: 10))
//                                .foregroundColor(.white.opacity(0.7))
//                        }
//                    }
//                    .frame(width: 90, height: 90) // Scaled for widget size
//
//                }
//                .buttonStyle(.plain)
//                .padding(.top, 3)
//
//                Spacer()
//                Spacer()
//            }
//            VStack(spacing: 0) {
//                Spacer()
//                // Bottom Button Row
//                HStack(spacing: 0) {
//                    BottomRowButtonStyle(action: {}, systemImage: "location.fill")
//                    Divider().background(Color.gray)
//                    BottomRowButtonStyle(action: {}, systemImage: "checkmark")
//                    Divider().background(Color.gray)
//                    BottomRowButtonStyle(action: {}, systemImage: "list.bullet")
//
//                }
//                .frame(height: 20)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 7)
//                        .stroke(Color.gray, lineWidth: 0.75) // Border
//                )
//                .clipShape(RoundedRectangle(cornerRadius: 7))
//                .padding(.horizontal)
//                .padding(.bottom, 10)
//            }
//        }
//    }
//
//    struct BottomRowButtonStyle: View {
//        let action: () -> Void
//        let systemImage: String
//        var body: some View {
//            Button(action: {
//                action()
//            }) {
//                Image(systemName: systemImage)
//                    .font(.system(size: 10))
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .foregroundColor(.white)
//            }
//            .buttonStyle(.plain)
//        }
//    }
//
//
//}



//struct WidgetRingStyle: View {
//    let prayerName: String
//    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
//
//    private var progress: Double {
//        0.3
//    }
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .gray}
//    }
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 2 }
//        else { return 1 }
//    }
//    private var frameSize: CGFloat { 120 }
//    private var outerRingSize: CGFloat { 14 }
//    private var innerRingSize: CGFloat { 6 }
//    private var offset: CGFloat { 1 }
//    private var dummyTimeLeft: TimeInterval{ 10403 } //this should be calculated from now to prayer's endTime using endTime.timeIntervalSinceNow
//
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sun.haze.fill"
//        case "maghrib":
//            return "sunset.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    func timeLeftString(from timeInterval: TimeInterval) -> String {
//        let totalSeconds = Int(timeInterval)
//        let hours = totalSeconds / 3600
//        let minutes = (totalSeconds % 3600) / 60
//        let seconds = totalSeconds % 60
//
//        // Building the formatted string
//        var components: [String] = []
//        if hours > 0 { components.append("\(hours)h") }
//        if minutes > 0 { components.append("\(minutes)m") }
//        if totalSeconds < 60 { components.append("\(seconds)s") } // Only show seconds if less than a minute
//        if components.isEmpty { return "0s left" } // If no time left, return "0s left"
//        return components.joined(separator: " ") + " left"
//    }
//
//
//    
//    var body: some View {
//        ZStack {
//            
//            // inner content
//            VStack(spacing: 5){
//                HStack (spacing: 2){
//                    Image(systemName: iconName(for: prayerName))
//                        .foregroundColor(.secondary)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .font(.callout)
//                    Text(prayerName)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .foregroundStyle(.secondary)
//                        .font(.callout)
//                }
////                    Text(timeLeftString(from: dummyTimeLeft)) // replace with real prayer
////                        .font(.system(size: 12))
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                        .foregroundStyle(.secondary)
//            }
//            
//            // Outer Circle with Dynamic Shadow
//            Circle()
//                .stroke(lineWidth: outerRingSize)
//                .frame(width: frameSize, height: frameSize)
//                .foregroundColor(Color("NeuRing"))
//                .shadow(
//                    color: Color("NeuDarkShad"), // shadow top lighter
//                    radius: 4,
//                    x: 2,
//                    y: 2
//                )
//                .shadow(
//                    color: Color("NeuLightShad"), // shadow top lighter
//                    radius: 6,
//                    x: -2,
//                    y: -2
//                )
//            
//            
//            // progress ring
//            Circle()
//                .trim(from: 0, to: clockwiseProgress)
//                .stroke(style: StrokeStyle(
//                    lineWidth: innerRingSize,
//                    lineCap: .round
//                ))
//                .fill(
//                    Color("bgColor")
//                    //indent shadow
//                        .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 0.5, x: -1, y: 1))
//
//                )
//            //outdented shadow
//                .shadow(color: Color("NeuDarkShad").opacity(0.5), radius: 0.5, x: -1, y: 1)
//
//                .frame(width: frameSize, height: frameSize)
//                .rotationEffect(.degrees(-90))
//            
//            // Ring tip with shadow
//            Circle()
//                .trim(from: clockwiseProgress - 0.001,
//                      to:   clockwiseProgress)
//                .stroke(style: StrokeStyle(
//                    lineWidth: innerRingSize,
//                    lineCap: .round
//                ))
//                .frame(width: frameSize, height: frameSize)
//                .rotationEffect(.degrees(-90))
//                .foregroundStyle(progressColor)
//            
//
//        }
//    }
//}




extension SharedStore {
    /// Today's marked prayers with their scores (the widget's done state needs the score).
    static func completedPrayerScoresToday() -> [String: Double] {
        let t0 = ContinuousClock.now
        defer { WidgetPerf.log("scores read \(WidgetPerf.ms(since: t0)) ms") }
        guard let container = widgetContainer else { return [:] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: PrayerDay.start()))   // 2.8.0
        let done = ((try? context.fetch(descriptor)) ?? []).filter(\.isCompleted)
        return Dictionary(done.map { ($0.name, $0.numberScore ?? 0) }, uniquingKeysWith: { a, _ in a })
    }
}


// MARK: - Lock Screen

/// The Prayers widget on the Lock Screen (2026-09-26). Same prayer as the home-screen circle
/// (`WidgetPrayerCircleView.relevantPrayer`: the prayer that's on, else the next, done ones
/// skipped).
/// - Circular: the ring fills live as the window passes (`ProgressView(timerInterval:)`,
///   `countsDown: false`), the prayer's symbol and name inside; before it starts, a thin dashed
///   ring with the symbol, name and start time (no NEXT here). The timeline carries an entry at
///   the start / end, so it switches on time.
/// - Rectangular: name, "ends 6:48 PM" / "at 4:10 PM", and a bar that fills, or a countdown.
/// - Inline (above the clock): "Asr · ends 6:48 PM".
struct PrayerLockScreenView: View {
    let entry: PrayersWidgetEntry
    let family: WidgetFamily

    private var prayer: (name: String, current: Bool, start: Date, end: Date, window: TimeInterval) {
        PrayersWidgetView.WidgetPrayerCircleView(entry: entry).relevantPrayer
    }
    private var live: Bool { prayer.current && prayer.end > prayer.start }
    /// On, not marked (a marked prayer isn't shown — the circle moves on), under an hour left at
    /// this entry's time. The timeline has an entry at end − 60 min, so it switches on time.
    private var lastHour: Bool {
        live && prayer.end > entry.date && prayer.end.timeIntervalSince(entry.date) <= PrayerLockScreenView.timeLeftFrom
    }
    static let timeLeftFrom: TimeInterval = 60 * 60
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if live {
                // A thin ring (owner, 2026-09-30, note C522C78E: "less thick to let the content
                // inside breathe"): the stock timer-driven ring is what keeps moving on a widget but
                // its band is fat, so it only masks a thin arc (as the home widget's `LiveArc`).
                Circle()
                    .inset(by: Self.ringInset)
                    .stroke(lineWidth: Self.ringWidth)
                    .opacity(0.25)
                Circle()
                    .inset(by: Self.ringInset)
                    .stroke(style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .butt))
                    .mask { liveMask }
                VStack(spacing: 0) {
                    Image(systemName: prayerIcon(for: prayer.name))
                        .font(.system(size: 9.5, weight: .medium))   // smaller: room for the name (owner, 2026-09-27)
                    if lastHour {
                        // The last hour (owner, 2026-09-29, ask lockscreen-time-left): the time left in
                        // place of the name — the symbol says which prayer. "27m" from this entry (the
                        // timeline steps it each minute; LockTimeLeft).
                        Text(LockTimeLeft.text(left: prayer.end.timeIntervalSince(entry.date)))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        // A quiet caption under it (owner, 2026-09-30: "the word left below the countdown").
                        Text("left")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .opacity(0.8)
                    } else {
                        Text(prayer.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(.horizontal, 7)
            } else {
                // Not started (most of the time once the current one is marked): just the app's
                // dashed ring — no NEXT here (owner, 2026-09-27: it didn't look good).
                Circle()
                    .inset(by: 2.5)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                    .opacity(0.55)
                VStack(spacing: 1) {
                    Image(systemName: prayerIcon(for: prayer.name))
                        .font(.system(size: 9.5, weight: .medium))       // same as the live state
                    Text(prayer.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(Self.clock.string(from: prayer.start))   // "5:32", no zero, no AM
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 6)
            }
        }
        .widgetAccentable()
    }

    static let ringWidth: CGFloat = 2.5
    /// The arc's middle sits in the stock ring's band, so the mask shows all of it.
    static let ringInset: CGFloat = 3

    /// The stock ring as a mask: its track (≈ 0.3 grey) to nothing, its fill to everything.
    private var liveMask: some View {
        ZStack {
            Color.black
            ProgressView(timerInterval: prayer.start...prayer.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(.white)
            .labelsHidden()
        }
        .compositingGroup()
        .brightness(-0.35)
        .contrast(3)
        .luminanceToAlpha()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: prayerIcon(for: prayer.name))
                Text(prayer.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                if live {
                    // A short live timer ("26:53", "1:26:53"): the relative style ("26 min, 53 sec")
                    // truncated the prayer's name to "Mag…".
                    Text(timerInterval: entry.date...max(prayer.end, entry.date), countsDown: true, showsHours: true)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                }
            }
            .widgetAccentable()
            (Text(live ? "ends " : "at ") + Text(live ? prayer.end : prayer.start, style: .time))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            if live {
                // Fills left → right as the window passes (it used to empty).
                ProgressView(timerInterval: prayer.start...prayer.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
            } else {
                (Text("in ") + Text(prayer.start, style: .relative))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var inline: some View {
        Label {
            Text(prayer.name + (live ? " · ends " : " · ")) + Text(live ? prayer.end : prayer.start, style: .time)
        } icon: {
            Image(systemName: prayerIcon(for: prayer.name))
        }
    }
}

/// The app's soft surfaces (CircleTheme.publicLook, greyBlue): grey-blue in light, charcoal in dark.
enum WidgetSoft {
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.10) : Color(red: 0.890, green: 0.898, blue: 0.933)
    }
    static func shade(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black.opacity(0.75) : .black.opacity(0.25) }
    static func light(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.06) : .white }
}

/// The soft ring's raised band: the surface, lifted — shade down-right, light up-left.
struct WidgetSoftBand: View {
    var width: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Circle()
            .stroke(WidgetSoft.surface(scheme), lineWidth: width)
            .shadow(color: WidgetSoft.shade(scheme), radius: width * 0.6, x: width * 0.3, y: width * 0.3)
            .shadow(color: WidgetSoft.light(scheme), radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
    }
}
