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
                .containerBackground(Color("widgetBgColor"), for: .widget)
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
    /// The bottom corners (Edit Widget; notes #1).
    var leftCorner: WidgetCornerAction = .qibla
    var rightCorner: WidgetCornerAction = .tasbeeh
    /// Prayed dots in their score colours (Edit Widget); off = one plain colour.
    var scoreColors = true

    /// The same data, shown from `date` on (a later timeline entry); `list` overrides whether the
    /// times list shows (the ring comes back `WidgetListState.openFor` after it opened).
    func at(_ date: Date, list: Bool? = nil) -> PrayersWidgetEntry {
        PrayersWidgetEntry(date: date, heading: heading, latitude: latitude, longitude: longitude,
                           toggleShowAllTImes: list ?? toggleShowAllTImes, prayerDict: prayerDict,
                           todayPrayerTimes: todayPrayerTimes, locationName: locationName, textToggle: textToggle,
                           completedScores: completedScores, nextFajr: nextFajr,
                           leftCorner: leftCorner, rightCorner: rightCorner, scoreColors: scoreColors)
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
        let dummyDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        
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
        let entry = await makeEntry(configuration)
        var entries = [entry]
        // The times list doesn't stick: the ring again `openFor` after it was opened (one entry).
        var base = entry
        if entry.toggleShowAllTImes, let openedAt = WidgetListState.openedAt {
            base = entry.at(max(openedAt.addingTimeInterval(WidgetListState.openFor), entry.date.addingTimeInterval(1)), list: false)
            entries.append(base)
        }
        // Plus an entry when the shown prayer starts (and when it ends), so the Lock Screen's dashed
        // "next" ring turns into the live ring on time rather than at the next (throttled) reload.
        // A few entries at most — a long timeline was "not performant" (owner). No per-minute ones.
        let shown = PrayersWidgetView.WidgetPrayerCircleView(entry: base).relevantPrayer
        var moments: [Date] = []
        if !shown.current, shown.start > base.date, shown.end > shown.start {
            moments = [shown.start, shown.end]
        } else if shown.current, shown.end > base.date {
            moments = [shown.end]
        }
        entries += moments.map { base.at($0, list: false) }
        let nextRefresh = Date().addingTimeInterval(60)
        return Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(nextRefresh))
    }

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
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: prayerDate)
        var windows = PrayerUtils.createDummyWindows()
        var nextFajr: Date?
        do {
            let params = PrayerUtils.getCalculationParameters()
            prayerTimes = try PrayerUtils.getPrayerTimes(for: prayerDate, coordinates: coordinates, params: params)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: prayerDate) ?? prayerDate
            nextFajr = try? PrayerUtils.getPrayerTimes(for: tomorrow, coordinates: coordinates, params: params).fajr
            windows = PrayerUtils.createWindowsFromTimes(prayerTimes, on: prayerDate, nextFajr: nextFajr)
        } catch {
            // If there's an error, either throw or use a fallback
            // For example, you could use dummy times or just return some default
            let fallbackCalcParams = CalculationMethod.northAmerica.params
            print("ran catch block fallback for PrayerUtils")
            prayerTimes = PrayerTimes(
                coordinates: coordinates,
                date: dateComponents,
                calculationParameters: fallbackCalcParams
            )!
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
            nextFajr: nextFajr,
            leftCorner: configuration?.corners.left ?? .qibla,
            rightCorner: configuration?.corners.right ?? .tasbeeh,
            scoreColors: configuration?.scoreColors ?? true
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
                                      completedScores: scores, nextFajr: nextFajr,
                                      leftCorner: corners.first ?? entry.leftCorner,
                                      rightCorner: corners.count > 1 ? corners[1] : entry.rightCorner,
                                      scoreColors: store.bool(forKey: "demoWidget.plain") ? false : entry.scoreColors)
        }
        #endif
        return entry
    }
}



struct PrayersWidgetView: View {
    var entry: PrayersWidgetEntry
    let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            PrayerLockScreenView(entry: entry, family: family)
        default:
            homeScreen
        }
    }

    private var homeScreen: some View {
        ZStack {
            if entry.toggleShowAllTImes {
                TimesListView(entry: entry)
            } else {
                WidgetPrayerCircleView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Today's times in the app's look (2026-09-27, notes #1): a back button and the city as a tiny
    /// caption; the five prayers + Sunrise (dimmed); the current prayer in sage, done ones with
    /// their score dot, the next one tagged. Rounded light type like the ring. It goes back to the
    /// ring by itself after `WidgetListState.openFor` (the timeline's next entry).
    struct TimesListView: View {
        let entry: PrayersWidgetEntry
        private let order = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

        /// The first prayer that hasn't started (not Sunrise).
        private var nextName: String? {
            order.first { $0 != "Sunrise" && (entry.prayerDict[$0]?.start ?? .distantPast) > entry.date }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button(intent: showListToggleIntent()) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to the ring")
                    Text(entry.locationName.lowercased())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 3)

                // The rows share what's left, so Isha fits on the smallest widget (~158 pt on a
                // 6.1" phone; the fixed layout needed ~168 — review, 2026-09-27).
                ForEach(order, id: \.self) { name in
                    if let p = entry.prayerDict[name] {
                        row(name, p.start, p.end)
                            .frame(maxHeight: 22)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func row(_ name: String, _ start: Date, _ end: Date) -> some View {
            let sunrise = name == "Sunrise"
            let current = !sunrise && start <= entry.date && entry.date < end
            let score = entry.completedScores[name]
            return HStack(spacing: 6) {
                PrayerDot(score: score, started: start <= entry.date, current: current, colored: entry.scoreColors)
                    .opacity(sunrise ? 0 : 1)
                Text(name)
                    .font(.system(size: 12, weight: current ? .regular : .light, design: .rounded))
                if name == nextName {
                    Text("next")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Text(start, style: .time)
                    .font(.system(size: 11, weight: current ? .regular : .light, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(current ? Brand.sage : (sunrise ? Color.secondary.opacity(0.7) : Color.primary))
            .padding(.vertical, 1.5)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(current ? Brand.sage.opacity(0.14) : Color.clear))
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
                    Circle().fill(Color.primary.opacity(0.12))
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// The day's five prayers as dots (no Sunrise), same prayer day as the app.
    struct PrayerDotsRow: View {
        let entry: PrayersWidgetEntry
        var spacing: CGFloat = 5
        var body: some View {
            HStack(spacing: spacing) {
                ForEach(["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"], id: \.self) { name in
                    let p = entry.prayerDict[name]
                    PrayerDot(score: entry.completedScores[name],
                              started: (p?.start ?? .distantFuture) <= entry.date,
                              current: p.map { $0.start <= entry.date && entry.date < $0.end } ?? false,
                              colored: entry.scoreColors)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.completedScores.count) of 5 prayers done")
        }
    }

    struct WidgetPrayerCircleView: View {
        let entry: PrayersWidgetEntry
        
        let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        

        var relevantPrayer: (name: String, current: Bool, start: Date, end: Date, window: TimeInterval) {
            // The entry's time, not the clock: WidgetKit can render a future entry ahead of time.
            let now = entry.date
            
            /// Check if indexed prayer is a current prayer -- else check if indexed prayer is the next one.
            /// Prayers already completed today are skipped so the circle moves on after a tap; the
            /// top-left check shows the current one was prayed.
            for name in prayerOrder where !entry.completedToday.contains(name) {
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

        private var progressColor: Color {
            if progress < 0.5 { return .green }
            else if progress < 0.75 { return .yellow }
            else if progress < 1 { return .red }
            else {return .gray}
        }


        
        var body: some View {
            ZStack {
//                Color.black
//                    .ignoresSafeArea()
                
                VStack{
                    Spacer()
                    
                    // Circular Timer with Text Button
                    Button(intent: textToggleIntent()){
                        ZStack {
                            // The track, like the app's (CircleTrack): the solid band for a prayer
                            // that's on, the thin dashed ring for one that hasn't started (with
                            // "NEXT" over a dimmed name below).
                            if relevantPrayer.current {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                            } else {
                                // Stronger than the app's (0.35 / 0.75 pt): at widget size, in dark
                                // mode especially, the ring was hard to see (owner, 2026-09-27).
                                Circle()
                                    .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3.5]))
                            }

                            Circle()
                                .trim(from: 0, to: progress) // Adjust progress value (0 to 1)
                                .stroke(
                                    progressColor,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .butt)
                                )
                                .rotationEffect(.degrees(-90))
                            
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
                                    if entry.textToggle {
                                        Text(relevantPrayer.current ? relevantPrayer.end : relevantPrayer.start, style: .relative)
                                    } else {
                                        Text(relevantPrayer.current ? "ends " : "at ")
                                            + Text(relevantPrayer.current ? relevantPrayer.end : relevantPrayer.start, style: .time)
                                    }
                                }
                                .font(.system(size: 10, weight: .thin, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            }
                        }
                        .frame(width: 90, height: 90) // Scaled for widget size
                        
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                // Centred between the widget's top edge and the dots, not in the whole widget: the
                // full-width dots row weighs the bottom down, so the true centre read low (owner,
                // 2026-09-27). The full row height (36) put it too close to the top; 24 splits the
                // gaps evenly (checked in the simulator).
                .padding(.bottom, Self.ringLift)

                // A button in each corner (2026-09-25): today's times · mark prayed on top; the
                // bottom two are chosen in Edit Widget (Qibla / Tasbeeh by default, or Daily Ayah,
                // 99 Names, None). The day's five prayers sit between them as dots (display only).
                VStack {
                    HStack {
                        CornerButton(intent: showListToggleIntent(), systemImage: "list.bullet")
                        Spacer()
                        checkButton
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        corner(entry.leftCorner)
                        Spacer(minLength: 2)
                        PrayerDotsRow(entry: entry, spacing: bothCornersEmpty ? 9 : 5)
                        Spacer(minLength: 2)
                        corner(entry.rightCorner)
                    }
                }
                .padding(6)
            }
        }

        static let ringLift: CGFloat = 24

        private var bothCornersEmpty: Bool { entry.leftCorner == .none && entry.rightCorner == .none }

        /// A chosen corner, or an empty 30 pt slot for None (so the dots stay centred).
        @ViewBuilder private func corner(_ action: WidgetCornerAction) -> some View {
            if let intent = action.intent, let symbol = action.symbol {
                CornerButton(intent: intent, systemImage: symbol)
            } else {
                Color.clear.frame(width: bothCornersEmpty ? 0 : 30, height: 30)
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
    let dummyDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
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
        guard let container = widgetContainer else { return [:] }
        let context = ModelContext(container)
        let (dayStart, dayEnd) = PrayerDay.rowRange(forDayStarting: PrayerDay.start())
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.isCompleted && $0.startTime >= dayStart && $0.startTime <= dayEnd }
        )
        let done = (try? context.fetch(descriptor)) ?? []
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
                // Fills as the window passes, like the app's ring (it used to drain). The stock
                // timer-driven view is what keeps updating on a widget; custom drawing goes stale.
                ProgressView(timerInterval: prayer.start...prayer.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Image(systemName: prayerIcon(for: prayer.name))
                            .font(.system(size: 9.5, weight: .medium))   // smaller: room for the name (owner, 2026-09-27)
                        Text(prayer.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .progressViewStyle(.circular)
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

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: prayerIcon(for: prayer.name))
                Text(prayer.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                if live {
                    Text(prayer.end, style: .relative)
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
