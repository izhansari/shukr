//
//  ShortcutIntents.swift
//  shukr (app and widget extension)
//
//  Shortcuts, Siri and Control Center: the prayer-time questions, the Fajr alarm, Zikr Tasks, their snippets.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 4).
//

import Foundation
import SwiftUI
import AppIntents
import WidgetKit
import SwiftData
import CoreLocation
#if canImport(AlarmKit)
import AlarmKit
#endif

// MARK: - From TasbeehView

/// AppEnum for Prayer Selection

/// AppEnum for Reference Point
enum ReferencePoint: String, AppEnum {
    case after = "after"
    case before = "before"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Before or After"
    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
        .before: "before",
        .after: "after"
    ]
}

/// Intent: Get Time of Chosen Prayer
struct GetSomePrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time of Chosen Prayer"
    /// Folded into "Get Prayer Time" (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description: LocalizedStringResource = "The next start time of the prayer you pick (today's, or tomorrow's once it has passed)."
    
    @Parameter(title: "Prayer", description: "Select which prayer time you want.")
    var prayer: enumPrayer
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get start time for \(\.$prayer)")
    }
    
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayerTime = PrayerUtils.getTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        return .result(value: nextPrayerTime, dialog: IntentDialog(stringLiteral: "\(prayer.rawValue.capitalized) is at \(shortTimePM(nextPrayerTime))."))
    }
}

/// Intent: Get Next Fajr Time
struct GetNextFajrIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Fajr Time"
    /// Folded into "Get Prayer Time" → Fajr (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description: LocalizedStringResource = "When Fajr next starts, with your method and madhab."
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let nextFajr = Date() > todayTimes.fajr ? tomorrowTimes.fajr : todayTimes.fajr
        return .result(value: nextFajr, dialog: IntentDialog(stringLiteral: "Fajr is at \(shortTimePM(nextFajr))."))
    }
}

/// Intent: Get Offset Time Relative to Any Prayer
struct GetOffsetTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Offset Time Relative to Prayer"
    /// Folded into "Get Prayer Time" with minutes before / after (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "A time a set number of minutes before or after a prayer starts — e.g. 15 minutes before Maghrib to start cooking, or 10 minutes after Fajr for the lights. Uses the prayer's next start (today's, or tomorrow's once it has passed).",
        categoryName: "Prayer Times")

    // Same parameter names as before, so shortcuts already built keep their values.
    @Parameter(title: "Minutes", description: "How many minutes away from the prayer's start, 0 to 600.",
               default: 15, controlStyle: .field, inclusiveRange: (0, 600))
    var offsetMinutes: Int

    @Parameter(title: "Before or after", description: "Before or after the prayer starts.", default: .before)
    var referencePoint: ReferencePoint

    @Parameter(title: "Prayer", description: "The prayer to count from. Sunrise works too.", default: .maghrib)
    var prayer: enumPrayer

    static var parameterSummary: some ParameterSummary {
        Summary("Get the time \(\.$offsetMinutes) minutes \(\.$referencePoint) \(\.$prayer) starts")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        let prayerTime = PrayerUtils.getTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getTime(for: prayer, in: tomorrowTimes) : prayerTime
        let offset = TimeInterval(offsetMinutes * 60)
        let resultTime = referencePoint == .after ? nextPrayerTime.addingTimeInterval(offset) : nextPrayerTime.addingTimeInterval(-offset)
        let name = prayer.rawValue
        let line = offsetMinutes == 0 ? "\(name) starts at \(shortTimePM(resultTime))."
            : "\(offsetMinutes) minutes \(referencePoint.rawValue) \(name) is \(shortTimePM(resultTime)) (\(name) at \(shortTimePM(nextPrayerTime)))."
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: line))
    }
}




/// Intent: Get Offset Time Relative to Fajr or Sunrise
/// The Fajr alarm's record (owner, 2026-10-10: "it doesn't tell us how many it schedules … i got an alarm going off at
/// midnight one time"): every plan, alarm set or cancelled, stop, "I'm up", ring seen and Shortcut call, with what it was
/// worked out from — in the app group, so the app and the Shortcut's intent both write it. Settings → Fajr alarm →
/// Alarm check shows it (beta installs); `devicectl … --domain-type appGroupDataContainer` pulls it.
enum FajrAlarmLog {
    private static let queue = DispatchQueue(label: "shukr.fajrAlarmLog")
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/fajr-alarm.log", isDirectory: false)
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm:ss zzz"
        return f
    }()
    /// "Fri Oct 10 5:12 AM" — every date in the log reads the same way.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    static func add(_ line: String) {
        let text = "\(stamp.string(from: Date()))  \(line)\n"
        print("⏰ \(line)")
        // Written before returning: the alarm's Stop runs shukr for a moment in the background, and a write left for later
        // was lost when iOS suspended it straight after (his first morning had no Stop line at all).
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? Data(text.utf8).write(to: url)
            }
            // Kept to the last ~1500 lines.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 400_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                let kept = all.split(separator: "\n").suffix(1500).joined(separator: "\n") + "\n"
                try? kept.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Newest first.
    static func lines() -> [String] {
        queue.sync {
            guard let url, let all = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return all.split(separator: "\n").map(String.init).reversed()
        }
    }

    static var text: String { queue.sync { url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" } }
}

/// The first Shortcut's step, kept for automations already made from it: it still stops them when the alarm is off or
/// shukr sets it itself, so they never make a second alarm. Hidden from the actions list: new shortcuts use
/// `FajrAlarmTimeIntent` (never blocks) and `FajrAlarmShortcutCheckIntent` (owner, 2026-10-12).
struct SetFajrAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Autopilot Fajr Alarm Time (legacy)"
    static var description: LocalizedStringResource = "Used by the first version of shukr's Fajr alarm Shortcut. New shortcuts: use Get Fajr Alarm Time."
    static var isDiscoverable: Bool = false

//    private let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
    
    /// Custom Error for Disabled Alarm
    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Your Fajr alarm is off. Turn it on in shukr’s Settings."
        }
    }

    /// shukr sets the Fajr alarm itself (AlarmKit, iOS 26.1+): this Shortcut step fails on purpose,
    /// so the shared Shortcut stops here and its next step ("Create Alarm") never runs — no second
    /// alarm, and nobody has to delete their automation.
    struct SetByShukrError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "shukr sets your Fajr alarm itself now, so this automation doesn't need to. You can turn it off in Shortcuts."
        }
    }

    /// Excused (Excused.swift): no alarm, said neutrally.
    struct NoAlarmNeededError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource { "No Fajr alarm is needed right now." }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        if Excused.isActive {
            FajrAlarmLog.add("Shortcut asked: excused — no alarm")
            throw NoAlarmNeededError()
        }
        if let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"), group.bool(forKey: "alarmKitActive") {
            // AlarmKit's permission taken away while the app wasn't running (audit B13): the Shortcut takes over
            // again, instead of neither setting an alarm.
            var permissionGone = false
            var permission = "?"
            #if canImport(AlarmKit)
            if #available(iOS 26.1, *) {
                permission = String(describing: AlarmManager.shared.authorizationState)
                // Only a real refusal: outside the app the state can read otherwise (the owner's phone went to the
                // Shortcut with AlarmKit allowed, 56 alarms left unplanned — 2026-10-10).
                if AlarmManager.shared.authorizationState == .denied { permissionGone = true }
            }
            #endif
            if permissionGone {
                FajrAlarmLog.add("Shortcut asked: AlarmKit permission reads \(permission) in \(Bundle.main.bundleIdentifier ?? "?") — AlarmKit mode off, the Shortcut takes over (AlarmKit's alarms stay set)")
                group.set(false, forKey: "alarmKitActive")
            } else {
                // A Shortcut that carries on past this error makes its "Create Alarm" with no time: 12:00 AM.
                FajrAlarmLog.add("Shortcut asked: AlarmKit sets the alarm — refused (an automation that carries on past this error makes a 12:00 AM alarm)")
                throw SetByShukrError()
            }
        }
        let calculatedAlarm: (description: String, time: Date)
        do { calculatedAlarm = try PrayerUtils.calculateAlarmDescription() } catch {
            FajrAlarmLog.add("Shortcut asked: no time worked out — \(error)")
            throw error
        }
        let resultTime = calculatedAlarm.time
        FajrAlarmLog.add("Shortcut asked: gave \(FajrAlarmLog.day(resultTime)) (\(calculatedAlarm.description))")

//        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
//            store.setValue(shortTimePM(resultTime), forKey: "alarmTimeSetFor")
//            store.setValue(calculatedAlarm.description, forKey: "alarmDescription")
//            
//            print("SetFajrAlarmIntent: Alarm Description: \(store.string(forKey: "alarmDescription") ?? "")")
//        }
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        store.setValue(shortTimePM(resultTime), forKey: "alarmTimeSetFor")
        store.setValue(calculatedAlarm.description, forKey: "alarmDescription")
        print("SetFajrAlarmIntent: Alarm Description: \(store.string(forKey: "alarmDescription") ?? "")")
        
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: calculatedAlarm.description))
    }
}





// MARK: - Prayer times, asked for in Shortcuts

/// Which prayer "Get Prayer Time" means, from now.
enum PrayerPick: String, AppEnum {
    case relevant, current, previous, next, fajr, dhuhr, asr, maghrib, isha
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Which prayer"
    static var caseDisplayRepresentations: [PrayerPick: DisplayRepresentation] = [
        .relevant: DisplayRepresentation(title: "Relevant", subtitle: "What shukr's circle shows: the one to pray now, next, or one you missed",
                                         image: .init(systemName: "scope")),
        .current: DisplayRepresentation(title: "Current", subtitle: "The prayer whose time it is now, prayed or not", image: .init(systemName: "clock"),
                                        synonyms: ["current prayer", "the current prayer", "this prayer"]),
        .previous: DisplayRepresentation(title: "Previous", subtitle: "The one before the current prayer", image: .init(systemName: "arrow.backward"),
                                         synonyms: ["previous prayer", "the previous prayer", "the last prayer"]),
        .next: DisplayRepresentation(title: "Next", subtitle: "The next to start", image: .init(systemName: "arrow.forward"),
                                     synonyms: ["next prayer", "the next prayer"]),
        // The five by name (owner: one Prayer Time in place of Fajr Time / Chosen Prayer): today's, or the next once over.
        .fajr: DisplayRepresentation(title: "Fajr", image: .init(systemName: prayerIcon(for: "Fajr").replacingOccurrences(of: ".fill", with: ""))),
        .dhuhr: DisplayRepresentation(title: "Dhuhr", image: .init(systemName: prayerIcon(for: "Dhuhr").replacingOccurrences(of: ".fill", with: ""))),
        .asr: DisplayRepresentation(title: "Asr", image: .init(systemName: prayerIcon(for: "Asr").replacingOccurrences(of: ".fill", with: ""))),
        .maghrib: DisplayRepresentation(title: "Maghrib", image: .init(systemName: prayerIcon(for: "Maghrib").replacingOccurrences(of: ".fill", with: ""))),
        .isha: DisplayRepresentation(title: "Isha", image: .init(systemName: prayerIcon(for: "Isha").replacingOccurrences(of: ".fill", with: ""))),
    ]
    /// The prayer's name for the five; nil for relevant / current / previous / next.
    var prayerName: String? {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        default: nil
        }
    }
}

/// The Shortcuts app's options for Prayer Time's tile, grouped (a phrase with a choice in it makes a tile per option —
/// these fold them into two collections under the one tile).
struct PrayerPickRelativeOptions: DynamicOptionsProvider {
    func results() async throws -> [PrayerPick] { [.relevant, .current, .next, .previous] }
}
struct PrayerPickByNameOptions: DynamicOptionsProvider {
    func results() async throws -> [PrayerPick] { [.fajr, .dhuhr, .asr, .maghrib, .isha] }
}

/// The five prayers' windows from yesterday to tomorrow, in order (Isha to 11:59 PM; Sunrise is never a prayer).
enum PrayerWindows {
    struct Window { let name: String; let start: Date; let end: Date }

    static func around(_ now: Date = Date()) -> [Window] {
        guard let coords = try? PrayerUtils.getUserCoordinates() else { return [] }
        let params = PrayerUtils.getCalculationParameters()
        let cal = Calendar.current
        let today = PrayerDay.date(for: now)
        var all: [Window] = []
        for offset in -1...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let times = try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params) else { continue }
            let nextFajr = cal.date(byAdding: .day, value: 1, to: day)
                .flatMap { try? PrayerUtils.getPrayerTimes(for: $0, coordinates: coords, params: params).fajr }
            let w = PrayerUtils.createWindowsFromTimes(times, on: day, nextFajr: nextFajr)
            for name in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
                if let (a, b, _) = w[name] { all.append(Window(name: name, start: a, end: b)) }
            }
        }
        return all.sorted { $0.start < $1.start }
    }

    /// The prayer day's five.
    static func today(_ now: Date = Date()) -> [Window] {
        // By the prayer day's key, not the calendar date: an Isha after midnight (high latitudes in summer) belongs to the
        // day before (review).
        let key = PrayerDay.key(for: now)
        return Array(around(now).filter { PrayerDay.key(forRow: $0.name, startingAt: $0.start) == key }.prefix(5))
    }

    static func pick(_ which: PrayerPick, now: Date = Date()) -> Window? {
        let all = around(now)
        let current = all.last { $0.start <= now && now < $0.end }
        switch which {
        case .current: return current
        case .next: return all.first { $0.start > now }
        case .previous:
            if let current, let i = all.firstIndex(where: { $0.start == current.start }), i > 0 { return all[i - 1] }
            return all.last { $0.end <= now }
        case .fajr, .dhuhr, .asr, .maghrib, .isha:
            // Today's while it isn't over (on now counts), else the next one.
            return all.first { $0.name == which.prayerName && now < $0.end }
        case .relevant:
            // As the Salah circle (PrayerViewModel.relevantPrayer): on and unmarked, else the next unmarked today, else
            // a missed one today; all five done → tomorrow's Fajr.
            let done = SharedStore.completedPrayerNamesToday()
            let day = today(now)
            return day.first { !done.contains($0.name) && $0.start <= now && now < $0.end }
                ?? day.first { !done.contains($0.name) && now < $0.start }
                ?? day.first { !done.contains($0.name) && $0.end <= now }
                ?? all.first { $0.start > now && $0.name == "Fajr" }
        }
    }

    /// "1 hour 5 minutes".
    static func span(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "under a minute" }   // as the cards (review: Siri said "1 minute", the card "under a minute")
        let m = Int((seconds / 60).rounded(.down))   // down, as the cards say it (review: Siri said a minute more)
        let h = m / 60, r = m % 60
        let hours = h == 0 ? "" : h == 1 ? "1 hour" : "\(h) hours"
        let mins = r == 0 ? "" : r == 1 ? "1 minute" : "\(r) minutes"
        return [hours, mins].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// "Get Prayer Time": the relevant, current, previous or next prayer — its start, and what it is.
struct GetPrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Prayer Time"
    static var description = IntentDescription(
        "The relevant, current, previous or next prayer — or Fajr, Dhuhr, Asr, Maghrib or Isha — and its start time, or a time some minutes before or after it (Show More). Relevant is what shukr's circle shows: the prayer to pray now, the next one, or one you missed.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "fajr", "dhuhr", "asr", "maghrib", "isha", "offset", "next prayer"],
        resultValueName: "Prayer Time")

    @Parameter(title: "Which prayer", description: "Relevant, current, previous, next, or one of the five.", default: .relevant) var which: PrayerPick
    /// Under Show More (was its own "Offset" action): a time some minutes before or after the prayer starts.
    @Parameter(title: "Minutes", description: "Minutes before or after the prayer starts (0 = its own time).", default: 0,
               inclusiveRange: (0, 600)) var minutes: Int
    @Parameter(title: "Before or after", description: "Before or after the prayer starts.", default: .before) var side: ReferencePoint

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$which) prayer time") {
            \.$minutes
            \.$side
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        ShortcutTopUp.request()
        let now = Date()
        let shift = TimeInterval(minutes * 60) * (side == .before ? -1 : 1)
        if minutes > 0 {
            // A time some minutes before / after the prayer: the next one that's still ahead (as the Offset action did —
            // "15 min before Maghrib" asked during Maghrib is tomorrow's), else the picked one as it is.
            let all = PrayerWindows.around(now)
            let w = which.prayerName.flatMap { name in all.first { $0.name == name && $0.start.addingTimeInterval(shift) > now } }
                ?? PrayerWindows.pick(which) ?? PrayerWindows.pick(.next)
            guard let w else { throw PrayerTimeUnavailable() }
            let t = w.start.addingTimeInterval(shift)
            return .result(value: t, dialog: "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(side == .before ? "before" : "after") \(w.name) is \(shortTimePM(t))\(Self.day(t)) (\(w.name) at \(shortTimePM(w.start))).")
        }
        guard let w = PrayerWindows.pick(which) else {
            if which == .current, let n = PrayerWindows.pick(.next) {
                return .result(value: n.start, dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).")
            }
            throw PrayerTimeUnavailable()
        }
        let on = w.start <= now && now < w.end
        let line: IntentDialog = switch which {
        case .current: "\(w.name) is on until \(shortTimePM(w.end))."   // one wording for "on" everywhere (review)
        case .previous: "The previous prayer was \(w.name), at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .next: "The next prayer is \(w.name), at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .fajr, .dhuhr, .asr, .maghrib, .isha:
            on ? "\(w.name) is on until \(shortTimePM(w.end))." : "\(w.name) is at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .relevant:
            IntentDialog(stringLiteral: Self.prayedFirst(now: now, moving: w)
                + (on ? "\(w.name) is on until \(shortTimePM(w.end))."
                   : w.end <= now ? "\(w.name) isn’t marked yet. Its window ended at \(shortTimePM(w.end))."
                   : "\(w.name) is next, at \(shortTimePM(w.start))\(Self.day(w.start))."))
        }
        return .result(value: w.start, dialog: line)
    }

    /// Relevant moved past a prayer that's on but already prayed: say so first (owner: "You've prayed Asr. Maghrib is
    /// next, at 6:48 PM."); all five prayed: "You've prayed all five today."
    static func prayedFirst(now: Date, moving w: PrayerWindows.Window) -> String {
        let done = SharedStore.completedPrayerNamesToday()
        if PrayerWindows.today(now).allSatisfy({ done.contains($0.name) }) { return "You’ve prayed all five today. " }
        guard let current = PrayerWindows.pick(.current, now: now), current.start != w.start, done.contains(current.name)
        else { return "" }
        return "You’ve prayed \(current.name). "
    }

    /// " tomorrow" / " yesterday" when the prayer isn't on today's prayer day (Fajr tomorrow, Isha last night).
    static func day(_ start: Date, now: Date = Date()) -> String {
        // The calendar day, as people say it: after midnight this morning's Fajr is "next", not "tomorrow" (review).
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: now) { return "" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(start, inSameDayAs: t) { return " tomorrow" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(start, inSameDayAs: y) { return " yesterday" }
        return ""
    }
}

/// "Get Today's Prayer Times": the five as a list — earlier / now / still to come.
struct GetTodaysPrayerTimesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today’s Prayer Times"
    /// Replaced by TodaysTimesNowIntent (iOS 26); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "Today's five prayer times with your method and madhab, as a list: what's passed (✓ when you marked it), what's on now, what's to come.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "schedule", "timetable", "today"], resultValueName: "Prayer Times")

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let now = Date()
        let five = PrayerWindows.today(now)
        guard !five.isEmpty else { throw PrayerTimeUnavailable() }
        let rows = TodaysTimesSnippet.rows(now: now)
        let spoken = TodaysTimesSnippet.spoken(now: now)
        let lines = five.map { "\($0.name) \(shortTimePM($0.start))" }   // the output, as before: automations keep working
        let scheme = await ShortcutLook.scheme()
        return .result(value: lines, dialog: IntentDialog(stringLiteral: spoken),
                       view: TodaysTimesSnippet(rows: rows, now: now).environment(\.colorScheme, scheme))
    }
}

/// Today's Times as a list (owner: "a real list … three headings, one row per prayer with its symbol, name and time, the
/// current one highlighted, in shukr's look"): Earlier (dimmed, ✓ when marked) · Now (a soft sage card, "until …") ·
/// Still to come. Siri and Shortcuts show it under the spoken line; it follows the phone's light or dark.
struct TodaysTimesSnippet: View {
    enum When: Int { case earlier, now, coming }
    struct Row: Identifiable {
        let name: String, start: Date, end: Date, marked: Bool, when: When
        var id: String { name }
    }
    let rows: [Row]
    /// iOS 26: the current prayer's tick slot is a circle that marks it.
    var markable = false
    /// The moment it was asked (its "… left").
    var now = Date()
    /// shukr's sage (Color.sage lives in the app target only; this file is the widget's too).
    static let sage = Color(red: 0.40, green: 0.64, blue: 0.50)

    var body: some View {
        // One plain list (owner: the Earlier / Now / Still to come headers were clutter); the marks and the current
        // row's sage fill say where the day is.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row($0) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    /// As the Live Activity card says it (review: three spellings of the same thing): "2 hr, 29 min left",
    /// "59 minutes left", "under a minute left".
    static func left(until end: Date, now: Date = Date()) -> String {
        let m = Int((end.timeIntervalSince(now) / 60).rounded(.down))
        if m < 1 { return "under a minute left" }
        let h = m / 60, r = m % 60
        return h == 0 ? "\(r) \(r == 1 ? "minute" : "minutes") left" : r == 0 ? "\(h) hr left" : "\(h) hr, \(r) min left"
    }

    /// Today's five as rows (one source for every card and the preview).
    static func rows(now: Date = Date()) -> [Row] {
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.today(now).map { w in
            Row(name: w.name, start: w.start, end: w.end, marked: done.contains(w.name),
                when: w.end <= now ? .earlier : w.start <= now ? .now : .coming)
        }
    }

    @ViewBuilder private func mark(_ r: Row) -> some View {
        if r.marked && markable {
            // Undo, never in one tap (owner): the ✓ opens shukr, which asks "Unmark Asr?" — as I Prayed's Undo.
            Button(intent: AskUnmarkPrayerIntent(prayerName: r.name, prayerStart: r.start)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Self.sage)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.name), prayed. Unmark in shukr")
        } else if r.marked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Self.sage)
                .accessibilityLabel("\(r.name), prayed")
        } else if r.when == .coming {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .padding(2)
                .accessibilityLabel("\(r.name), still to come")
        } else if r.when == .now && markable {
            Button(intent: MarkPrayerFromCardIntent(.init(name: r.name, start: r.start, end: r.end))) {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Self.sage)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(r.name) as prayed")
        } else {
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(r.when == .now ? Self.sage : Color.secondary)
                .accessibilityLabel(r.when == .now ? "\(r.name), now" : "\(r.name), not marked")
        }
    }

    /// The line said with the list: what's on, else what's next, else Fajr.
    static func spoken(now: Date = Date()) -> String {
        let five = PrayerWindows.today(now)
        if let on = five.first(where: { $0.start <= now && now < $0.end }) { return "\(on.name) is on until \(shortTimePM(on.end))." }
        if let next = five.first(where: { $0.start > now }) { return "\(noPrayerOnLine) \(next.name) starts at \(shortTimePM(next.start))." }
        if let fajr = PrayerWindows.pick(.fajr, now: now) { return "That’s all five for today. Fajr is at \(shortTimePM(fajr.start))." }
        return "That’s all five for today."
    }

    private func row(_ r: Row) -> some View {
        let now = r.when == .now
        return HStack(spacing: 12) {
            // The app's own marks in place of the prayer symbols (owner): ✓ = prayed, a circle = on now (on iOS 26 the
            // tap that marks it) or missed, dashed = still to come. One column, so the time keeps its room.
            mark(r)
                .frame(width: 26, height: 26)
            Text(r.name)
                .font(.system(.body, design: .rounded, weight: now ? .semibold : .regular))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(shortTimePM(r.start))
                    .font(.system(.body, design: .rounded, weight: now ? .semibold : .regular))
                    .monospacedDigit()
                if now {
                    Text(Self.left(until: r.end, now: self.now))   // time left, as the Live Activity says it (owner: not "until")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, now ? 9 : 6)
        .background {
            if now { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.sage.opacity(0.16)) }
        }
        .opacity(r.when == .earlier ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The look Shortcuts / Siri cards are drawn in: the phone's light or dark. Run in the background the app's views came
/// out light, unreadable on a dark sheet (his phone).
enum ShortcutLook {
    static func scheme() async -> ColorScheme {
        await MainActor.run { UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light }
    }
}

/// Shortcuts that only answer top the reminders up too (owner: "make them top up too … many people will use these as
/// recipes in bigger chained shortcuts"): the answer returns at once, the top-up runs after it in the app (notifications,
/// then Fajr alarms, then the Live Activity plan), and at most every 3 h — a chain asking ten times pays for it once.
enum ShortcutTopUp {
    nonisolated(unsafe) static var run: (() -> Void)?
    static let key = "shortcutTopUpAt"
    static let every: TimeInterval = 3 * 3600
    static func request() {
        guard run != nil, let g = UserDefaults(suiteName: SharedStore.appGroup) else { return }   // the widget's process: no hook
        let now = Date().timeIntervalSince1970
        guard now - g.double(forKey: key) > every else { return }
        g.set(now, forKey: key)
        Task { @MainActor in run?() }   // not awaited: the shortcut never waits on it
    }
}

/// Cards drawn with app-only views (the app sets them at launch; the widget never runs these actions).
enum ShortcutCards {
    /// Setup's alarm picture for Get Fajr Alarm Time; true = the alarm is off (frosted).
    nonisolated(unsafe) static var fajrAlarm: ((Bool, Date) -> AnyView)?
}

/// Time Left and I Prayed: the prayer's own Live Activity card (owner: "reuse the live activity view") — running, or
/// once marked its ✓ in the grade's colour; no 15 s bar. On iOS 26 its `action` puts a ✓ or an Undo in the button's place.
struct PrayerCardSnippet: View {
    let state: PrayerWindowAttributes.ContentState
    /// iOS 26's interactive cards: a ✓ that marks it, or an Undo that asks in shukr (never undone here — owner).
    enum Action { case none, mark, undo }
    var action: Action = .none
    var body: some View {
        var t = LATuning.current
        t.barThickness = 0
        return LALockCardBody(state: state, n: 0, ended: false, t: t, liveButtons: true)
            // One line for VoiceOver, before the buttons go on, so ✓ / Undo stay reachable (review).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .overlay(alignment: .trailing) {
                switch action {
                case .none: EmptyView()
                case .mark:
                    LARoundButton(intent: MarkPrayerFromCardIntent(.init(name: state.label, start: state.start, end: state.end)),
                                  symbol: "checkmark", size: t.buttonSize,
                                  symbolSize: t.buttonSymbolSize, t: t)
                        .padding(.trailing, t.cardPaddingSides)
                case .undo:
                    Button(intent: AskUnmarkPrayerIntent(prayerName: state.label, prayerStart: state.start)) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, t.cardPaddingSides)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)
    }
    /// One line for VoiceOver (the card stacks timer layers that would each be read).
    private var spoken: String {
        if let m = state.markedAt {
            let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: m)
            return "\(state.label), prayed \(shortTimePM(m)) \(PrayerScoring.grade(for: score).spokenWhen)."   // no "Score: N" (prayer-metrics phase 3)
        }
        return "\(state.label), \(TodaysTimesSnippet.left(until: state.end)), ends \(shortTimePM(state.end))"
    }
}

private extension String {
    func prefixed(_ p: String) -> String { p + self }
}

/// No prayer on (Sunrise to Dhuhr): the next one, its symbol, when it starts.
struct NextPrayerSnippet: View {
    let name: String
    let start: Date
    var now = Date()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: prayerIcon(for: name).replacingOccurrences(of: ".fill", with: ""))
                .font(.system(size: 22))
                .foregroundStyle(TodaysTimesSnippet.sage)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(.title3, design: .rounded, weight: .medium))
                Text(TodaysTimesSnippet.left(until: start, now: now).replacingOccurrences(of: " left", with: "").replacingOccurrences(of: "under a minute", with: "a moment").prefixed("starts in "))
                    .lineLimit(1)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortTimePM(start)).font(.system(.title3, design: .rounded)).monospacedDigit()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LASoft.surface(LATuning.current, scheme)))
        .padding(10)   // as the prayer's card: its surface, radius and margin (Time Left kept its look between Sunrise and Dhuhr)
        .accessibilityElement(children: .combine)
    }
}

/// The same words wherever no prayer's time is on (Sunrise to Dhuhr).
let noPrayerOnLine = "No prayer is on right now."

struct PrayerTimeUnavailable: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Open shukr once so it knows where you are." }
}

// MARK: - The Fajr alarm on the Lock Screen

/// The Lock Screen's Fajr (owner, 2026-10-15): once Isha is done the Prayers widget shows when the Fajr alarm rings, not
/// when Fajr starts — by default, whenever shukr rings it (iOS 26.1+ AlarmKit, the alarm on and allowed, not excused);
/// otherwise Fajr's start, as before. The alarm rule from Settings → Reminders → Fajr Alarm, as the scheduler reads it.
enum FajrAlarmShown {
    /// shukr rings the Fajr alarm: iOS 26.1+, on, allowed, not excused (Explore only talks about it then — owner).
    /// "Allowed" is the app's `alarmKitActive`: its plan turns that off whenever AlarmKit permission isn't granted. Never
    /// ask AlarmManager here: the widget extension has no AlarmKit permission of its own, so it never reads .authorized,
    /// and the Lock Screen showed Fajr's start in place of the alarm (owner, 2026-10-20: "My phone is showing that Fajr is
    /// 6:17 on the lock screen widget, even though it should say 6:07 for the alarm").
    static var isOn: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoLockAlarm") { return true }   // `-demoLockAlarm YES` (in the app)
        #endif
        guard #available(iOS 26.1, *) else { return false }
        guard let g = UserDefaults(suiteName: SharedStore.appGroup),
              g.bool(forKey: "alarmEnabled"), g.bool(forKey: "alarmKitActive"), !Excused.isActive else { return false }
        return true
    }

    #if DEBUG
    /// What the extension itself reads, for widget-perf.log (the 2026-10-20 check: AlarmKit's state from the widget).
    static var debugLine: String {
        var s = "Fajr alarm: on \(isOn)"
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) { s += ", AlarmKit here \(String(describing: AlarmManager.shared.authorizationState))" }
        #endif
        return s
    }
    #endif

    static func time(fajrStart: Date, sunrise: Date) -> Date? {
        guard isOn, let g = UserDefaults(suiteName: SharedStore.appGroup) else { return nil }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoLockAlarm") { return fajrStart.addingTimeInterval(-20 * 60) }
        #endif
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
        let raw = g.integer(forKey: "alarmOffsetMinutes")
        let minutes = isFajr ? raw : max(10, raw)   // FajrAlarmRule.clamp: before the end of Fajr, at least 10
        return (isFajr ? fajrStart : sunrise).addingTimeInterval(TimeInterval(minutes * 60) * (before ? -1 : 1))
    }
}

// MARK: - The Fajr alarm's time, for any shortcut

/// "Get Fajr Alarm Time" (owner: usable in any shortcut — lights on at that time): the next time your Fajr alarm
/// rule gives (Settings → Reminders → Fajr Alarm), whether or not the alarm is on. Never stops a shortcut.
struct FajrAlarmTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Fajr Alarm Time"   // was "Autopilot …" (owner: verb first, no jargon)
    static var description = IntentDescription("The next time your Fajr alarm rule gives — e.g. 20 minutes before Fajr starts — from Settings → Reminders → Fajr Alarm, whether or not the alarm is on. Use it in any shortcut: lights, music, a Focus. With the alarm on, it's also what shukr's Lock Screen widget shows after Isha.",
                                               categoryName: "Fajr Alarm", searchKeywords: ["wake", "alarm", "fajr", "morning"],
                                               resultValueName: "Fajr Alarm Time")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog & ShowsSnippetView {
        let (time, on) = try Self.next()
        // Setup's alarm picture (the app's view, through ShortcutCards), frosted when the alarm is off.
        let scheme = await ShortcutLook.scheme()
        let view = await MainActor.run { ShortcutCards.fajrAlarm?(!on, time) } ?? AnyView(EmptyView())
        return .result(value: time, dialog: IntentDialog(stringLiteral: Self.spoken(time, on: on)),
                       view: AnyView(view.environment(\.colorScheme, scheme)))
    }
    static func spoken(_ time: Date, on: Bool) -> String {
        on ? "Your Fajr alarm is at \(shortTimePM(time))." : "Your Fajr alarm is off. When it’s on, it rings at \(shortTimePM(time))."
    }
    /// When the rule next rings, and whether the alarm is on.
    static func next() throws -> (time: Date, on: Bool) {
        ShortcutTopUp.request()
        // The rule on today's Fajr (or sunrise); tomorrow's only once that has passed (review: worked out from the
        // alarm's own time, an offset across midnight or an "after sunrise" rule landed on the wrong day).
        guard let g = UserDefaults(suiteName: SharedStore.appGroup), let coords = try? PrayerUtils.getUserCoordinates()
        else { throw PrayerTimeUnavailable() }
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let shift = TimeInterval(g.integer(forKey: "alarmOffsetMinutes") * 60) * ((g.object(forKey: "alarmIsBefore") as? Bool ?? true) ? -1 : 1)
        let params = PrayerUtils.getCalculationParameters()
        let now = Date()
        func rule(_ day: Date) -> Date? {
            (try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params))
                .map { PrayerUtils.getTime(for: isFajr ? .fajr : .sunrise, in: $0).addingTimeInterval(shift) }
        }
        guard let today = rule(now) else { throw PrayerTimeUnavailable() }
        let time = today > now ? today : (Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap(rule) ?? today)
        FajrAlarmLog.add("Shortcut asked the rule's time: \(FajrAlarmLog.day(time))")
        // Say when it's off: the time is the rule's either way (an automation can still use it).
        // Excused (Excused.swift): it won't ring, so it reads as off.
        let on = UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: "alarmEnabled") == true && !Excused.isActive
        return (time, on)
    }
}

/// "Should a Shortcut Set the Fajr Alarm?": true only when the Daily alarm is on and shukr isn't setting it itself
/// (iOS 26.1+). shukr's Clock-alarm Shortcut checks this first, so there's never a second alarm.
struct FajrAlarmShortcutCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Fajr Alarm Shortcut"   // verb first (was a question)
    static var description = IntentDescription("Yes when your Fajr alarm is on and shukr isn’t already setting it itself. Check it before making a Clock alarm, so you never get two.",
                                               categoryName: "Fajr Alarm", searchKeywords: ["alarm", "clock", "fajr"], resultValueName: "Should Set")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let g = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let on = g?.bool(forKey: "alarmEnabled") == true
        var shukrSetsIt = g?.bool(forKey: "alarmKitActive") == true
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *), AlarmManager.shared.authorizationState == .denied { shukrSetsIt = false }
        #endif
        let excused = Excused.isActive   // no alarm while excused (Excused.swift)
        let answer = on && !shukrSetsIt && !excused
        FajrAlarmLog.add("Shortcut asked whether to set the alarm: \(answer) (switch \(on), shukr sets it \(shukrSetsIt)\(excused ? ", excused" : ""))")
        return .result(value: answer)
    }
}

// MARK: - Siri and Shortcuts: asked in plain words (owner: "natural questions")

/// What Siri's "the prayer that's on" means: the window you're in, prayed or not (owner: "I prayed just says no prayer
/// is on. not true. its maghrib"). Between Sunrise and Dhuhr none is.
enum RelevantPrayer {
    struct Info { let name: String; let start: Date; let end: Date; let isOn: Bool }

    static func now(_ now: Date = Date()) -> Info? {
        if let c = PrayerWindows.pick(.current, now: now) { return Info(name: c.name, start: c.start, end: c.end, isOn: true) }
        if let n = PrayerWindows.pick(.next, now: now) { return Info(name: n.name, start: n.start, end: n.end, isOn: false) }
        return nil
    }
}

/// "What's the next prayer?" — the next to start, answered at once. Gives its start time to the next action.
struct NextPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Prayer"
    /// Folded into "Get Prayer Time" (Relevant / Next) (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("The next prayer to start and how long until it does. Passes its start time on.",
                                               categoryName: "Prayer Times")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let now = Date()
        var line = "\(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))), at \(shortTimePM(n.start))."
        if let c = PrayerWindows.pick(.current) { line = "\(c.name) is on until \(shortTimePM(c.end)). " + line }
        return .result(value: n.start, dialog: IntentDialog(stringLiteral: line))
    }
}

/// "How long is left?" — time left in the prayer you're in, marked or not; between Sunrise and Dhuhr, time until Dhuhr.
/// Gives the minutes to the next action.
struct PrayerTimeLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Left"
    /// Replaced by TimeLeftNowIntent (iOS 26, a card with a ✓ — decision shortcut-buttons-ios26 A); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "Minutes left in the prayer whose time it is now — whether or not you've prayed it. Between Sunrise and Dhuhr, minutes until Dhuhr. Passes the minutes on.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "how long", "remaining", "ends"], resultValueName: "Minutes Left")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let now = Date()
        let scheme = await ShortcutLook.scheme()
        if let c = PrayerWindows.pick(.current) {
            let mins = max(1, Int((c.end.timeIntervalSince(now) / 60).rounded(.down)))
            // The card as it runs on the Lock Screen: the ring filling in its colour, the time left, when it ends.
            let state = PrayerWindowAttributes.ContentState(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                            dark: scheme == .dark)
            return .result(value: mins, dialog: "\(PrayerWindows.span(c.end.timeIntervalSince(now))) left for \(c.name). It ends at \(shortTimePM(c.end)).",
                           view: AnyView(PrayerCardSnippet(state: state).environment(\.colorScheme, scheme)))
        }
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let mins = max(1, Int((n.start.timeIntervalSince(now) / 60).rounded(.down)))
        return .result(value: mins, dialog: "\(noPrayerOnLine) \(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))).",
                       view: AnyView(NextPrayerSnippet(name: n.name, start: n.start, now: now).environment(\.colorScheme, scheme)))
    }
}

/// "I prayed" — marks the prayer whose time it is, scored now, without opening shukr; tells you if it was already marked.
/// Gives the grade to the next action.
struct MarkCurrentPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    /// Replaced by MarkPrayedNowIntent (iOS 26, with Undo); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Marks the prayer whose time it is now as prayed, scored like in shukr. Passes the grade on (Perfect, Middle, Closing, Qaza).",
                                               categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "prayed", "mark", "done"],
                                               resultValueName: "Grade")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let scheme = await ShortcutLook.scheme()
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) {
                return .result(value: "", dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).",
                               view: AnyView(NextPrayerSnippet(name: n.name, start: n.start).environment(\.colorScheme, scheme)))
            }
            throw PrayerTimeUnavailable()
        }
        /// The prayer's card in its marked look: the ✓ in its grade's colour, "Prayed 4:31 PM", the grade and score.
        func card(_ at: Date) -> AnyView {
            AnyView(PrayerCardSnippet(state: .init(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                   markedAt: at, dark: scheme == .dark))
                .environment(\.colorScheme, scheme))
        }
        if let at = SharedStore.markedTime(of: c.name, start: c.start) {
            return .result(value: PrayerMarkNow.grade(c, at: at), dialog: "\(c.name) is already marked as prayed.", view: card(at))
        }
        let now = Date()
        guard await PrayerMarkNow.mark(c) else { throw PrayerTimeUnavailable() }
        let at = SharedStore.markedTime(of: c.name, start: c.start) ?? now
        let grade = PrayerMarkNow.grade(c, at: at)   // graded at the stored time, as the iOS 26 one
        return .result(value: grade, dialog: "\(PrayerMarkNow.spoken(c, at: at))", view: card(at))
    }
}

struct ZikrTaskSnapshot: Identifiable {
    let id: String
    /// The task's title: its own name ("After Fajr"), else the mantra.
    let name: String
    /// The mantra, when `name` is the task's own name.
    var mantra: String? = nil
    let isCountMode: Bool
    let goal: Int
    let count: Int
    let minutes: Int
    let done: Bool
    /// Roughly how long what's left takes at your pace (nil: no history yet).
    var secondsLeft: TimeInterval? = nil
    /// The row's estimate: time for a count goal, counts for a timed one (`TaskModel.estimateNote`).
    var note: String? = nil

    var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(isCountMode ? count : minutes) / Double(goal), 1)
    }
    var valueText: String { isCountMode ? "\(count)" : "\(minutes)m" }
    var progressText: String { isCountMode ? "\(count)/\(goal)" : "\(minutes)/\(goal) min" }
}

extension ZikrTaskSnapshot {
    /// Today's tasks (the prayer day's sessions), what's left first, done ones at the end — like the Zikr page; nil
    /// while the shared store isn't there yet. The Zikr widget and the Zikr Tasks shortcut.
    static func today() -> [ZikrTaskSnapshot]? {
        guard let container = SharedStore.widgetContainer else { return nil }
        let context = ModelContext(container)
        // Paused goals are left out (TaskModel.pausedAt, decision zikr-pause A).
        let tasks = ((try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []).filter { $0.pausedAt == nil }
        let dayStart = PrayerDay.sessionDayStart()
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(
            predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
        let snaps = tasks.map { task -> ZikrTaskSnapshot in
            let p = task.progress(in: sessions)
            return ZikrTaskSnapshot(id: task.id.uuidString, name: task.title, mantra: task.mantraLine,
                                    isCountMode: task.isCountMode, goal: task.goal,
                                    count: p.count, minutes: Int(p.seconds / 60),
                                    done: task.isCompleted(with: p),
                                    secondsLeft: task.secondsLeft(p),
                                    note: task.estimateNote(p))
        }
        return snaps.filter { !$0.done } + snaps.filter(\.done)
    }
}

// MARK: - Zikr Tasks (Shortcuts / Siri; owner 2026-10-13: "here are your tasks, and then you click on one to start that one")

/// A task row in the Zikr Tasks card: shukr opens and starts that task's session (today's count carried on).
struct StartZikrTaskIntent: AppIntent {
    static let flag = "shortcutZikrStart", idKey = "shortcutZikrStartID"
    static var title: LocalizedStringResource = "Start Zikr Task"
    static var isDiscoverable: Bool = false   // the card's rows
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Task") var taskID: String
    init() {}
    init(taskID: String) { self.taskID = taskID }
    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        store?.set(taskID, forKey: Self.idKey)
        store?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// Today's zikr tasks: to do (a tap starts one), then done.
struct ZikrTasksSnippet: View {
    let tasks: [ZikrTaskSnapshot]
    private static let sage = TodaysTimesSnippet.sage
    private static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if tasks.isEmpty {
                Button(intent: OpenTasbeehIntent()) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle").font(.system(size: 20, weight: .light)).foregroundStyle(Self.sage)
                        Text("Add a task on the Zikr page").font(.system(.body, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            let todo = tasks.filter { !$0.done }, done = tasks.filter(\.done)
            let todoShown = Array(todo.prefix(Self.shown))
            let doneShown = Array(done.prefix(max(0, Self.shown - todoShown.count)))
            if !todoShown.isEmpty { section("To do", todoShown) }
            if !doneShown.isEmpty { section("Done today", doneShown) }
            let more = tasks.count - todoShown.count - doneShown.count
            if more > 0 {
                Text("\(more) more in shukr")
                    .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).padding(.leading, 10)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    private func section(_ title: String, _ rows: [ZikrTaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            ForEach(rows) { t in
                if t.done { row(t) } else {
                    Button(intent: StartZikrTaskIntent(taskID: t.id)) { row(t) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start \(t.name)")
                }
            }
        }
    }

    private func row(_ t: ZikrTaskSnapshot) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: t.done ? 1 : t.fraction)
                    .stroke(Self.sage, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if t.done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Self.sage)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(t.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(detail(t))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !t.done {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.sage)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Self.sage.opacity(0.16)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// "40 of 100 · ~4 min" / "12 of 20 min" / "Goal 100" / "100 · done".
    private func detail(_ t: ZikrTaskSnapshot) -> String {
        if t.done { return t.isCountMode ? "\(t.count) · done" : "\(t.minutes) min · done" }
        let base = t.isCountMode ? "\(t.count) of \(t.goal)" : "\(t.minutes) of \(t.goal) min"
        if t.count == 0 && t.minutes == 0 {
            return t.isCountMode ? "Goal \(t.goal)" + (t.secondsLeft.map { " · " + zikrEstimateString($0) } ?? "")
                                 : "Goal \(t.goal) min"
        }
        guard t.isCountMode, let s = t.secondsLeft, s > 0 else { return base }
        return base + " · " + zikrEstimateString(s)
    }

    /// The line said with the card.
    static func spoken(_ tasks: [ZikrTaskSnapshot]) -> String {
        if tasks.isEmpty { return "You have no zikr tasks yet." }
        let left = tasks.filter { !$0.done }
        if left.isEmpty { return tasks.count == 1 ? "Your zikr task is done for today." : "All \(tasks.count) zikr tasks are done for today." }
        let lead = tasks.count == 1 ? "Your zikr task is still to do today"
            : left.count == tasks.count ? "\(tasks.count) zikr tasks to do today"
            : "\(left.count) of \(tasks.count) zikr tasks left today"
        let known = left.compactMap(\.secondsLeft)
        guard !known.isEmpty else { return lead + "." }
        return lead + ", about " + zikrEstimateString(known.reduce(0, +)).replacingOccurrences(of: "~", with: "") + "."
    }
}

/// The card, drawn again when shown.
@available(iOS 26.0, *)
struct ZikrTasksCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Zikr Tasks Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        return .result(view: AnyView(ZikrTasksSnippet(tasks: ZikrTaskSnapshot.today() ?? []).environment(\.colorScheme, scheme)))
    }
}

/// "Get Zikr Tasks": today's tasks in a card; a tap on one starts it in shukr.
@available(iOS 26.0, *)
struct ZikrTasksNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Zikr Tasks"
    static var description = IntentDescription(
        "Today's zikr tasks and how far along each one is. Tap a task to start it in shukr.",
        categoryName: "Zikr", searchKeywords: ["zikr", "dhikr", "tasbeeh", "tasks", "to do"], resultValueName: "Zikr Tasks")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<[String]> {
        guard let tasks = ZikrTaskSnapshot.today() else { throw PrayerTimeUnavailable() }
        return .init(value: tasks.filter { !$0.done }.map(\.name),
                     dialog: IntentDialog(stringLiteral: ZikrTasksSnippet.spoken(tasks)),
                     card: ZikrTasksCardIntent())
    }
}


// MARK: - Control Center (owner, 2026-10-13)

/// Today's list in shukr: the Salah page with the list up (the Prayer control — a control can't show a card, Apple
/// forum 760793 — so it opens the list, which has every prayer, the time left and marking).
struct OpenPrayerListIntent: AppIntent {
    static let flag = "widgetPrayerList"
    static var title: LocalizedStringResource = "Open Today’s Prayers"
    static var isDiscoverable: Bool = false   // the control's; Shortcuts has Open shukr → Salah
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// The I Prayed control: marks the prayer whose time it is (or today's late one) without opening shukr, says so in a line.
/// Already marked: never unmarked here (owner: no easy undo) — shukr's list does that, and asks.
struct MarkPrayerFromControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    /// iOS 26: it can bring shukr forward when she's excused (owner: ask, never a silent no).
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        defer { ControlCenter.shared.reloadAllControls() }
        if Excused.isActive {
            if #available(iOS 26.0, *) {
                try await continueInForeground(alwaysConfirm: false)
                ExcusedResume.ask()
                return .result(dialog: "")
            }
            return .result(dialog: "Prayers are paused. Open shukr to turn them back on.")
        }
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) { return .result(dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).") }
            throw PrayerTimeUnavailable()
        }
        if SharedStore.markedTime(of: c.name, start: c.start) != nil {
            return .result(dialog: "\(c.name) is already marked. Change it in shukr.")
        }
        guard await PrayerMarkNow.mark(c) else { throw PrayerTimeUnavailable() }
        let spoken = PrayerMarkNow.spoken(c, at: SharedStore.markedTime(of: c.name, start: c.start) ?? Date())
        return .result(dialog: "\(spoken)")
    }
}

/// The Fajr alarm switch (Control Center): the same `alarmEnabled` as Settings → Reminders → Fajr Alarm; re-planned in
/// the app (a LiveActivityIntent runs there).
struct SetFajrAlarmEnabledIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Fajr Alarm On or Off"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "On") var value: Bool
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(value, forKey: "alarmEnabled")
        await FajrAlarmHooks.replan?()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// The app's Fajr alarm planner, for the control (set at launch; the widget never runs it).
enum FajrAlarmHooks {
    nonisolated(unsafe) static var replan: (() async -> Void)?
}
