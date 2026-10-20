
// MARK: - Intents

import AppIntents
import ActivityKit
import WidgetKit
#if canImport(AlarmKit)
import AlarmKit
#endif
import SwiftData
import CoreData
import CoreLocation


/// A LiveActivityIntent so it runs in shukr's process (owner, 2026-10-11): the prayer's Live Activity card goes at once,
/// and the app can take a fresh location for it (S9FJ) — from the widget's own process it could do neither.
struct MarkCompleteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer Complete"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false   // the widget's button; Shortcuts gets "Mark Prayer as Prayed"

    @Parameter(title: "Prayer") var prayerName: String
    @Parameter(title: "Start") var prayerStart: Date
    @Parameter(title: "End") var prayerEnd: Date

    init() {}
    init(prayerName: String, prayerStart: Date, prayerEnd: Date) {
        self.prayerName = prayerName
        self.prayerStart = prayerStart
        self.prayerEnd = prayerEnd
    }

    func perform() async throws -> some IntentResult {
        let t0 = ContinuousClock.now
        WidgetPerf.log("mark \(prayerName) start")
        if let hook = PrayerWindowHooks.widgetMark {
            _ = await hook(prayerName, prayerStart, prayerEnd)
        } else {
            SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
        }
        WidgetPerf.log("mark \(prayerName) done \(WidgetPerf.ms(since: t0)) ms")
        return .result()
    }
}

extension SharedStore {
    /// Marks the prayer `name` on the day of `start` complete, scored at the tap. The widget's
    /// checkmark (`MarkCompleteIntent`) and the notification action "I already prayed"
    /// (`NotificationDelegate`) both come here. Writes through its own container and sets
    /// `widgetWroteStoreKey`, so the app re-reads on its next activation. Returns false when
    /// the prayer hasn't started, is already complete, or the store can't be opened.
    @discardableResult
    static func markPrayerComplete(named name: String, start: Date, end: Date) -> Bool {
        // Same rule as the app: a prayer that hasn't started can't be completed; nor one she's excused from.
        guard start <= Date(), !Excused.covers(start: start, end: end), let container = widgetContainer else { return false }
        let context = ModelContext(container)

        // The app creates today's rows when it opens; if it hasn't opened today, make this one.
        let prayer = fetchPrayer(named: name, on: start, in: context) ?? {
            let made = PrayerModel(name: name, startTime: start, endTime: end, dateAtMake: start)
            context.insert(made)
            return made
        }()
        guard !prayer.isCompleted else { return false }
        // The row's own start, not the caller's: a widget or banner drawn at another place (or before a times change)
        // could mark a prayer that hasn't started here yet — scored Perfect before its time (mark audit #7).
        guard prayer.startTime <= Date() else { return false }

        prayer.isCompleted = true
        prayer.setPrayerScore()                                        // scored now, at the tap
        prayer.setPrayerLocation(with: lastKnownLocation())
        prayer.cancelUpcomingNudges()                                  // app repeats this on next open in case extensions can't
        do { try context.save() } catch {
            print("❌ markPrayerComplete(\(name)) save failed: \(error)")
            return false
        }

        let group = UserDefaults(suiteName: appGroup)
        group?.set(true, forKey: widgetWroteStoreKey)
        // The app rescores that day and its streaks (audit B5: every mark made outside the app, not only the list's —
        // a late mark of yesterday's Isha from a notification left yesterday's score stale).
        group?.set(PrayerDay.start(forRow: name, startingAt: start).timeIntervalSince1970, forKey: WidgetListMarks.markedDayKey)   // the prayer day (mark audit #1)
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
        ControlCenter.shared.reloadAllControls()   // its "ends …" moves on
        return true
    }

    /// Posted by the app's own notification handler after "I already prayed" lands while the app is in front
    /// (audit B7): the page reconciles at once instead of at the next activation.
    static let markedElsewhere = Notification.Name("shukr.markedElsewhere")
}

struct OpenTasbeehIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbeeh"
    /// Folded into "Open shukr" → Zikr; the Tasbeeh control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's Zikr page.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
    
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetTasbeeh")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTasbeeh: \(store.bool(forKey: "widgetTasbeeh"))")
        }
        return .result()
    }
}

struct OpenCompassIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Qibla"
    /// Folded into "Open shukr" → Qibla; the Qibla control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's qibla map, turned so the qibla points up.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetCompass")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetCompass: \(store.bool(forKey: "widgetCompass"))")
        }
        return .result()
    }
}

/// A widget / control open's flags have just been written (widget-open-chrome). These intents run in the app
/// (`openAppWhenRun`), so on a cold launch they write after the app has started — after the welcome decided to play
/// and after the first look at the flags. The app opens the page as soon as this arrives, and the welcome steps aside.
/// In the widget's own process nobody listens.
enum DeepLinkSignal {
    static let arrived = Notification.Name("shukr.deepLinkArrived")
    static func post() {
        Task { @MainActor in NotificationCenter.default.post(name: arrived, object: nil) }
    }
}

/// Widget → one zikr task: the Zikr page with that task's circle in the middle, ready to tap.
struct OpenZikrTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Zikr Task"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        store?.set(taskID, forKey: "widgetZikrTask")
        store?.set(true, forKey: "widgetTasbeeh")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Widget → the Daily Ayah page (one-shot flag read on activation, like the compass one).
struct OpenDailyAyahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Daily Ayah"
    /// Folded into "Open shukr" → Daily Ayah; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens today's ayah in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetDailyAyah")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Widget times list (`WidgetListMarks`): a started row marks its prayer,
/// scored at the tap like the corner check, and the list stays up another `openFor` so the filled
/// circle is seen (the mark reloads the timeline).
struct MarkFromListIntent: LiveActivityIntent {   // in shukr's process, like MarkCompleteIntent
    static var title: LocalizedStringResource = "Mark Prayer Complete from the List"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Prayer") var prayerName: String
    @Parameter(title: "Start") var prayerStart: Date
    @Parameter(title: "End") var prayerEnd: Date

    init() {}
    init(prayerName: String, prayerStart: Date, prayerEnd: Date) {
        self.prayerName = prayerName
        self.prayerStart = prayerStart
        self.prayerEnd = prayerEnd
    }

    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        store?.set(true, forKey: WidgetListState.openKey)
        store?.set(Date().timeIntervalSince1970, forKey: WidgetListState.openedAtKey)
        let marked: Bool
        if let hook = PrayerWindowHooks.widgetMark {
            marked = await hook(prayerName, prayerStart, prayerEnd)
        } else {
            marked = SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
        }
        if !marked {
            WidgetCenter.shared.reloadAllTimelines()   // nothing marked: still keep the list up
        }
        return .result()
    }
}

/// Widget times list (`WidgetListMarks`): a done row opens the app to
/// "Unmark Asr?" — the widget never unmarks by itself.
struct AskUnmarkPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Unmark a Prayer"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "Prayer") var prayerName: String
    @Parameter(title: "Start") var prayerStart: Date

    init() {}
    init(prayerName: String, prayerStart: Date) {
        self.prayerName = prayerName
        self.prayerStart = prayerStart
    }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?
            .set("\(prayerName)|\(prayerStart.timeIntervalSince1970)", forKey: WidgetListMarks.unmarkKey)
        DeepLinkSignal.post()   // a running app asks at once (a Shortcuts card's Undo)
        return .result()
    }
}

/// Widget → the 99 Names page.
struct OpenNamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 99 Names"
    /// Folded into "Open shukr" → 99 Names; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens the 99 Names in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetNames")
        DeepLinkSignal.post()
        return .result()
    }
}

/// The Prayers widget's times list doesn't stick (2026-09-27, notes #1): opening it stores when,
/// and the timeline shows the list now plus the ring again `openFor` seconds later.
enum WidgetListState {
    static let openKey = "toggleShowAllTImes"
    static let openedAtKey = "widgetListOpenedAt"
    static let openFor: TimeInterval = 30

    static var openedAt: Date? {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        guard store?.bool(forKey: openKey) == true else { return nil }
        let t = store?.double(forKey: openedAtKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    /// Showing at `date` (opened less than `openFor` ago).
    static func isOpen(at date: Date) -> Bool {
        guard let openedAt else { return false }
        return date >= openedAt && date.timeIntervalSince(openedAt) < openFor
    }
}

struct showListToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetPerf.log("list toggle")
        if let store = UserDefaults(suiteName: SharedStore.appGroup) {
            // Showing → back to the ring at once; otherwise open it (again) from now.
            if WidgetListState.isOpen(at: Date()) {
                store.set(false, forKey: WidgetListState.openKey)
            } else {
                store.set(true, forKey: WidgetListState.openKey)
                store.set(Date().timeIntervalSince1970, forKey: WidgetListState.openedAtKey)
            }
        }
        return .result()
    }
}

struct textToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        
        WidgetPerf.log("ring tap (text toggle)")
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(!store.bool(forKey: "widgetTextToggle"), forKey: "widgetTextToggle")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTextToggle: \(store.bool(forKey: "widgetTextToggle"))")
        }
        return .result()
    }
}











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
                   : w.end <= now ? "\(w.name) isn’t marked yet. Its time ended at \(shortTimePM(w.end))."
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
            return "\(state.label), prayed \(shortTimePM(m)) \(PrayerScoring.grade(for: score).spokenWhen). Score: \(PrayerScoring.points(for: score))."
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
    static var isOn: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoLockAlarm") { return true }   // `-demoLockAlarm YES` (in the app)
        #endif
        guard #available(iOS 26.1, *) else { return false }
        guard let g = UserDefaults(suiteName: SharedStore.appGroup),
              g.bool(forKey: "alarmEnabled"), g.bool(forKey: "alarmKitActive"), !Excused.isActive else { return false }
        #if canImport(AlarmKit)
        guard AlarmManager.shared.authorizationState == .authorized else { return false }
        #endif
        return true
    }

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

// MARK: - iOS 26: cards with buttons (decision shortcut-buttons-ios26 A)

/// What a mark from Shortcuts marks: the prayer whose time it is, else today's last one still unmarked (a late Isha).
enum PrayerMarkNow {
    static func target(now: Date = Date()) -> PrayerWindows.Window? {
        // Excused: nothing to mark, and every answer stays neutral ("No prayer is on right now"), so a question asked
        // out loud never says why (owner).
        if Excused.isActive { return nil }
        if let c = PrayerWindows.pick(.current, now: now) { return c }
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.pick(.previous, now: now).flatMap { p in
            PrayerWindows.today(now).contains { $0.start == p.start } && !done.contains(p.name) ? p : nil }
    }
    static func mark(_ c: PrayerWindows.Window) async -> Bool {
        if Excused.covers(start: c.start, end: c.end) { return false }
        if let hook = PrayerWindowHooks.widgetMark { return await hook(c.name, c.start, c.end) }
        return SharedStore.markPrayerComplete(named: c.name, start: c.start, end: c.end)
    }
    static func grade(_ c: PrayerWindows.Window, at: Date) -> String {
        PrayerScoring.grade(for: PrayerScoring.score(start: c.start, end: c.end, markedAt: at)).rawValue
    }
    /// What Siri says once it's marked: "Asr marked as prayed during the Closing window. Score: 66." (a bare "Closing."
    /// out loud sounded like something shutting down).
    static func spoken(_ c: PrayerWindows.Window, at: Date) -> String {
        PrayerScoring.spokenMark(c.name, score: PrayerScoring.score(start: c.start, end: c.end, markedAt: at))
    }
    /// The prayer's card now: running (with a ✓), or marked (with an Undo when asked for).
    static func card(_ c: PrayerWindows.Window, undo: Bool, scheme: ColorScheme) -> AnyView {
        // Its own row, not today's names: a late Isha redrawn after Fajr still reads as marked (review).
        let marked = SharedStore.markedTime(of: c.name, start: c.start)
        let state = PrayerWindowAttributes.ContentState(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                        markedAt: marked, dark: scheme == .dark)
        // Excused (Excused.swift): no ✓ that would do nothing.
        let mark: PrayerCardSnippet.Action = Excused.covers(start: c.start, end: c.end) ? .none : .mark
        return AnyView(PrayerCardSnippet(state: state, action: marked == nil ? mark : undo ? .undo : .none)
            .environment(\.colorScheme, scheme))
    }
}

/// A card's ✓ (Time Left, Today's Times): marks the prayer the card shows (review: re-working it out at the tap, a card
/// showing Asr tapped after Maghrib began marked Maghrib); the card redraws itself after.
struct MarkPrayerFromCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer from a Card"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult {
        let w: PrayerWindows.Window? = if let name, let start, let end { .init(name: name, start: start, end: end) } else { PrayerMarkNow.target() }
        if let w, SharedStore.markedTime(of: w.name, start: w.start) == nil { _ = await PrayerMarkNow.mark(w) }
        return .result()
    }
}

/// The Time Left card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TimeLeftCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Time Left Card"
    static var isDiscoverable: Bool = false
    /// The prayer it was asked about (redrawn after its ✓ it stays that prayer, even once the next one has begun).
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        if let name, let start, let end {
            return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: false, scheme: scheme))
        }
        if let c = PrayerWindows.pick(.current) { return .result(view: PrayerMarkNow.card(c, undo: false, scheme: scheme)) }
        if let n = PrayerWindows.pick(.next) {
            return .result(view: AnyView(NextPrayerSnippet(name: n.name, start: n.start).environment(\.colorScheme, scheme)))
        }
        return .result(view: AnyView(EmptyView()))
    }
}

/// A Shortcuts answer: what's said, its card, and the value it passes on. Each action builds its own, and shukr's grouped
/// tiles (Ask shukr, ShukrAppShortcuts.swift) give the same one (iOS 27 hides an app's tiles outside a section).
@available(iOS 26.0, *)
struct ShortcutAnswer<Value> {
    let value: Value
    let dialog: IntentDialog
    let card: any SnippetIntent
}

/// "Get Time Left" on iOS 26: the same answer, its card with a ✓.
@available(iOS 26.0, *)
struct TimeLeftNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Left"
    static var description = IntentDescription(
        "Minutes left in the prayer whose time it is now — whether or not you've prayed it. Between Sunrise and Dhuhr, minutes until Dhuhr. Passes the minutes on; its card can mark the prayer.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "how long", "remaining", "ends"], resultValueName: "Minutes Left")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<Int> {
        ShortcutTopUp.request()
        let now = Date()
        if let c = PrayerWindows.pick(.current) {
            let mins = max(1, Int((c.end.timeIntervalSince(now) / 60).rounded(.down)))
            return .init(value: mins, dialog: "\(PrayerWindows.span(c.end.timeIntervalSince(now))) left for \(c.name). It ends at \(shortTimePM(c.end)).",
                         card: TimeLeftCardIntent(c))
        }
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let mins = max(1, Int((n.start.timeIntervalSince(now) / 60).rounded(.down)))
        return .init(value: mins, dialog: "\(noPrayerOnLine) \(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))).",
                     card: TimeLeftCardIntent())
    }
}

/// Today's Times card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TodaysTimesCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Today's Times Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let now = Date()
        return .result(view: AnyView(TodaysTimesSnippet(rows: TodaysTimesSnippet.rows(now: now), markable: !Excused.isActive, now: now)
            .environment(\.colorScheme, scheme)))
    }
}

/// "Get Today's Prayer Times" on iOS 26: the list, its current prayer markable.
@available(iOS 26.0, *)
struct TodaysTimesNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today’s Prayer Times"
    static var description = IntentDescription(
        "Today's five prayer times with your method and madhab, as a list: what's passed (✓ when you marked it), what's on now (tap to mark it), what's to come.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "schedule", "timetable", "today"], resultValueName: "Prayer Times")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<[String]> {
        ShortcutTopUp.request()
        let now = Date()
        let five = PrayerWindows.today(now)
        guard !five.isEmpty else { throw PrayerTimeUnavailable() }
        let spoken = TodaysTimesSnippet.spoken(now: now)
        return .init(value: five.map { "\($0.name) \(shortTimePM($0.start))" }, dialog: IntentDialog(stringLiteral: spoken),
                     card: TodaysTimesCardIntent())
    }
}

/// I Prayed's card: the marked prayer with an Undo that asks in shukr (owner: never an easy undo).
@available(iOS 26.0, *)
struct PrayedCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Prayed Card"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Prayer") var name: String
    @Parameter(title: "Start") var start: Date
    @Parameter(title: "End") var end: Date
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: true, scheme: scheme))
    }
}

/// "Mark Prayer as Prayed" on iOS 26: marks it, shows its card with Undo.
@available(iOS 26.0, *)
struct MarkPrayedNowIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    static var description = IntentDescription("Marks the prayer whose time it is now as prayed, scored like in shukr. Passes the grade on (Perfect, Middle, Closing, Qaza). Undo asks in shukr.",
                                               categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "prayed", "mark", "done"],
                                               resultValueName: "Grade")
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<String> {
        ShortcutTopUp.request()
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) {
                return .init(value: "", dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).", card: TimeLeftCardIntent())
            }
            throw PrayerTimeUnavailable()
        }
        if SharedStore.completedPrayerNamesToday().contains(c.name) {
            let at = SharedStore.markedTime(of: c.name, start: c.start) ?? Date()
            return .init(value: PrayerMarkNow.grade(c, at: at), dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
        }
        let now = Date()
        let marked = await PrayerMarkNow.mark(c)
        let at = SharedStore.markedTime(of: c.name, start: c.start) ?? now
        let grade = PrayerMarkNow.grade(c, at: at)
        guard marked else {   // review: it said "marked" even when nothing was
            if SharedStore.markedTime(of: c.name, start: c.start) != nil {
                return .init(value: grade, dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
            }
            throw PrayerTimeUnavailable()
        }
        return .init(value: grade, dialog: "\(PrayerMarkNow.spoken(c, at: at))", card: PrayedCardIntent(c))
    }
}

/// "Start Tasbih Fatimah" — shukr opens into the 33 · 33 · 34 session (as the post-salah pill does).
struct StartTasbihFatimahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbih Fatimah"   // every action that opens shukr says "Open" (owner)
    static var description = IntentDescription("Opens shukr into Tasbih Fatimah: 33 · 33 · 34.", categoryName: "Open shukr",
                                               searchKeywords: ["tasbih", "tasbeeh", "zikr", "dhikr", "subhanallah"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "liveActivity.openTasbih")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens Memories (a control, a shortcut).
struct OpenMemoriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Moments"
    /// Folded into "Open shukr" → Memories; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens your prayer photos in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetMemories")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens the Salah page (the prayer control).
struct OpenSalahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Prayers"
    /// Folded into "Open shukr" → Salah (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr on today's prayers.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "alarmOpenSalah")
        DeepLinkSignal.post()
        return .result()
    }
}

/// The pages "Open shukr" goes to (owner: one tile, pick the page; the Control Center buttons stay separate). Each
/// sets the flag its own control / widget sets, so the app opens it the same way (PrayerTimesView).
enum ShukrPage: String, AppEnum, CaseIterable {
    case salah, qibla, zikr, dailyAyah, names, memories, tasbihFatimah
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static var caseDisplayRepresentations: [ShukrPage: DisplayRepresentation] = [
        .salah: DisplayRepresentation(title: "Salah", subtitle: "Today's prayers", image: .init(systemName: "sun.horizon"),
                                      synonyms: ["prayers", "prayer times", "salat", "namaz"]),
        .qibla: DisplayRepresentation(title: "Qibla", subtitle: "The qibla map", image: .init(systemName: "location.north.line"),
                                      synonyms: ["compass", "the qibla", "direction of Mecca"]),
        .zikr: DisplayRepresentation(title: "Zikr", subtitle: "Your zikr and tasks", image: .init(systemName: "hands.and.sparkles"),
                                     synonyms: ["dhikr", "tasbeeh", "tasbih", "azkar"]),
        .dailyAyah: DisplayRepresentation(title: "Daily Ayah", subtitle: "Today's ayah", image: .init(systemName: "book"),
                                          synonyms: ["ayah", "the ayah", "verse of the day", "Quran"]),
        .names: DisplayRepresentation(title: "99 Names", subtitle: "The names of Allah", image: .init(systemName: "moon.stars"),
                                      synonyms: ["names", "names of Allah", "Asma ul Husna"]),
        .memories: DisplayRepresentation(title: "Moments", subtitle: "Your prayer photos", image: .init(systemName: "photo.stack"),
                                         synonyms: ["photos", "prayer photos", "memories"]),   // its old name (owner renamed it Moments, 2026-10-15)
        // Its own tile until iOS 27 hid every tile outside a section (2026-10-14): a page here, so it stays on the page.
        .tasbihFatimah: DisplayRepresentation(title: "Tasbih Fatimah", subtitle: "33 · 33 · 34", image: .init(systemName: "circle.hexagonpath"),
                                              synonyms: ["Tasbih Fatimah", "tasbeeh Fatimah", "33 33 34"]),
    ]
    /// The app group flag its control / widget sets.
    var flag: String {
        switch self {
        case .salah: "alarmOpenSalah"
        case .qibla: "widgetCompass"
        case .zikr: "widgetTasbeeh"
        case .dailyAyah: "widgetDailyAyah"
        case .names: "widgetNames"
        case .memories: "widgetMemories"
        case .tasbihFatimah: "liveActivity.openTasbih"
        }
    }
}

/// Open shukr's pages as one collection under its tile (see PrayerPickRelativeOptions).
struct ShukrPageOptions: DynamicOptionsProvider {
    func results() async throws -> [ShukrPage] { ShukrPage.allCases }
}

/// "Open shukr": one tile for every page (owner, 2026-10-12) — "Open qibla in shukr", "Open moments in shukr".
struct OpenShukrIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shukr"
    static var description = IntentDescription("Opens shukr on the page you pick: Salah, Qibla, Zikr, Daily Ayah, 99 Names or Moments.",
                                               categoryName: "Open shukr", searchKeywords: ["open", "go to", "show", "qibla", "zikr", "ayah", "names", "moments", "memories"])
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Page", default: .salah) var page: ShukrPage
    static var parameterSummary: some ParameterSummary { Summary("Open shukr on \(\.$page)") }

    init() {}
    init(page: ShukrPage) { self.page = page }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: page.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// "Find Nearby Mosques" (owner: "a quick way to ask for nearby mosques and see a map with the pins and a list"): shukr
/// opens on the map with its mosques — the pins and the list in the sheet.
struct FindNearbyMosquesIntent: AppIntent {
    static let flag = "widgetMosques"
    static var title: LocalizedStringResource = "Open Nearby Mosques"   // it opens shukr, so it says Open (owner)
    /// Replaced on iOS 26 by Find Nearby Mosques' card (decision nearby-mosques-card A); still the card's "Open in shukr"
    /// and saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's map on the mosques near you: their pins, and the nearest in a list.",
                                               categoryName: "Open shukr", searchKeywords: ["masjid", "mosque", "near me", "find", "jumuah", "map"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

// (The App Shortcuts list lives in the app only: shukr/CursorSwift/ShukrAppShortcuts.swift.)




/// DEBUG: the widget's tap → redraw path timed, one line per step, in the app group's
/// Library/Caches/widget-perf.log (last ~200 KB). Pull it with `xcrun devicectl device copy from --device <udid>
/// --domain-type appGroupDataContainer --domain-identifier group.betternorms.shukr.shukrWidget
/// --source Library/Caches/widget-perf.log --destination <file>`.
enum WidgetPerf {
    static func log(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appending(path: "Library/Caches", directoryHint: .isDirectory) else { return }
        let url = dir.appending(path: "widget-perf.log")
        let stamp = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .secondFraction(.fractional(3)))
        let data = Data("\(stamp) [\(ProcessInfo.processInfo.processName)] \(line())\n".utf8)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            if let size = try? h.seekToEnd(), size > 200_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    /// Milliseconds since `start`.
    static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

#if DEBUG
/// DEBUG switches (Settings → My Dev Stuff) to find what makes a Prayers widget tap slow to redraw.
enum WidgetSpeedTest {
    static let stillRingKey = "debugWidget.stillRing"
    static let fewestEntriesKey = "debugWidget.fewestEntries"
    static var stillRing: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: stillRingKey) == true }
    static var fewestEntries: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: fewestEntriesKey) == true }
}
#endif


/// Which prayers get a Live Activity for their window (owner, 2026-10-11: its own setting, not the notifications' —
/// "two very different features"). App group, on by default for all five.
enum LiveActivityPrefs {
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static func key(_ prayer: String) -> String { "liveActivity.\(prayer)" }
    /// All five by default (owner, 2026-10-12; was Dhuhr, Asr and Maghrib): iOS's five at a time are topped up whenever
    /// shukr opens, and setup / Settings say so.
    static let onByDefault: Set<String> = Set(prayers)
    static func isOn(_ prayer: String) -> Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: key(prayer)) as? Bool ?? onByDefault.contains(prayer)
    }
}

/// The Live Activity card's own look, apart from the app's (owner, 2026-10-12: "the same way … their widgets"): System
/// (the phone's — the default, as the widgets), Light, Dark, Follows the sun (a window's card can't switch mid-way, so
/// Dhuhr and Asr light, Fajr, Maghrib and Isha dark). Settings → Live Activities → Card look. App group.
enum LiveActivityLook: String, CaseIterable, Identifiable {
    case system, light, dark, sun
    static let key = "liveActivity.look"
    var id: String { rawValue }
    static var current: LiveActivityLook {
        UserDefaults(suiteName: SharedStore.appGroup)?.string(forKey: key).flatMap(LiveActivityLook.init(rawValue:)) ?? .system
    }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .sun: "Sun"
        }
    }
    var detail: String {
        switch self {
        case .system: "Light or dark with your iPhone."
        case .light: "Always light."
        case .dark: "Always dark."
        case .sun: "Light after Fajr, dark at Maghrib."
        }
    }
    /// A prayer's card: dark or not; nil = the phone's.
    func dark(for prayer: String) -> Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        case .sun: !(prayer == "Dhuhr" || prayer == "Asr")
        }
    }
}

/// A prayer window as a Live Activity (PrayerLiveActivities.swift plans them; the card is `PrayerWindowLiveActivity`).
struct PrayerWindowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
        var symbol: String = "sun.max.fill"
        var markedAt: Date? = nil
        /// The Lock Screen card's look (`LiveActivityLook`): nil = the phone's.
        var dark: Bool? = nil
        /// The last card shukr has queued (owner): nothing comes after it until shukr opens, so it says so at its foot.
        /// Optional, so cards already held decode.
        var last: Bool? = nil
        /// After the last card's ↻ added more (owner: "you're all good"): how many cards it added, said on the card that
        /// was tapped; the card says "Live Activity cards topped up" (owner, 2026-10-14: no count — it only worried
        /// people). Optional, so cards already held decode.
        var toppedUp: String? = nil
    }
    /// The window's id: its start in whole minutes since 1970 (so a window is never scheduled twice).
    var n: Int
}

/// The card's ✓ (runs in shukr's process, as every LiveActivityIntent does): marks the real prayer and turns the card.
struct PrayerWindowMarkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark prayer prayed"
    static var isDiscoverable = false
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Mark prayed tapped on #\(n)")
        if let mark = PrayerWindowHooks.mark {
            await mark(n)
        } else if let a = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n }) {
            // The app's hooks weren't set yet (Frank): the store's own mark, and the card goes — never a silent no-op.
            let st = a.content.state
            let done = SharedStore.markPrayerComplete(named: st.label, start: st.start, end: st.end)
            await a.end(nil, dismissalPolicy: .immediate)
            PrayerWindowLog.add("Mark prayed #\(n) without the app's hooks: store mark \(done ? "done" : "not needed / failed"), card ended")
        }
        return .result()
    }
}

/// The last card's ↻ (owner, 2026-10-14: "a refresh button on that last card"): runs in shukr without opening it — a
/// card button's run is when iOS lets shukr add cards from the background (the alarm's Stop can't) — and adds the next ones.
struct PrayerWindowRefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Get more prayer cards"
    static var isDiscoverable = false
    /// Opens shukr (decision last-card-refresh B): in front it fills all five; from the Lock Screen a tap adds only one.
    static var openAppWhenRun = true
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Refresh tapped on the last card (#\(n))")
        if let refresh = PrayerWindowHooks.refresh { _ = await refresh(n) }
        else { PrayerWindowLog.add("Refresh: the app's hooks weren't set") }
        // Without opening, iOS let a tap add one card only (the allowance is the tap's, not the run's — a chained second
        // intent was refused too, his phone 2026-10-14), so this opens shukr, which fills all five in front.
        return .result()
    }
}

/// After marking: Photo (the prayer's camera) or Tasbih (Tasbih Fatimah) — opens shukr.
struct PrayerWindowOpenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open after a prayer"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "What") var what: String
    @Parameter(title: "Window") var n: Int
    init() {}
    init(what: String, n: Int) { self.what = what; self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("\(what) tapped on #\(n) (opens shukr)")
        await PrayerWindowHooks.open?(n, what)
        return .result()
    }
}

/// The Prayers widget's camera (decision widget-camera A): once the prayer that's on is marked, it opens shukr on the
/// prayer photo's camera for it — as the Live Activity card's Photo does.
struct OpenPrayerPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Take a prayer photo"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "Prayer") var prayerName: String
    init() {}
    init(prayerName: String) { self.prayerName = prayerName }
    func perform() async throws -> some IntentResult {
        await PrayerWindowHooks.openPhoto?(prayerName)
        return .result()
    }
}

/// Set by the app at launch (an intent's run is always in the app's process).
enum PrayerWindowHooks {
    /// The widget's camera: the prayer's photo camera, once shukr is in front.
    nonisolated(unsafe) static var openPhoto: ((String) async -> Void)?
    nonisolated(unsafe) static var mark: ((Int) async -> Void)?
    nonisolated(unsafe) static var open: ((Int, String) async -> Void)?
    /// The last card's refresh: as many next cards as iOS lets this run add.
    nonisolated(unsafe) static var refresh: ((Int) async -> Int)?
    /// A widget's mark, run in the app (owner: the card goes at once; and a fresh location — S9FJ). Returns whether it marked.
    nonisolated(unsafe) static var widgetMark: ((String, Date, Date) async -> Bool)?
}

/// What the Live Activities did, both processes — app group Library/Application Support/live-activities.log (1 MB cap).
enum PrayerWindowLog {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/live-activities.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.liveActivityLog")
    static func add(_ line: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss.SSS"
        let text = "\(f.string(from: Date()))  [\(Bundle.main.bundleURL.pathExtension == "appex" ? "ext" : "app")] \(line)\n"
        #if DEBUG
        print("🟣 \(line)")
        #endif
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? Data(text.utf8).write(to: url) }
            // Days of it, never too big: the last ~4000 lines once it passes 1 MB.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? (all.split(separator: "\n").suffix(4000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

import SwiftUI

// MARK: - Prayer Live Activity card (MY4R), shared by the widget extension (the real card) and the app (the tuner's
// preview). Look D's layout in the app's soft look, dark. Every size / gap / glow comes from `LATuning` (owner: "give me
// a tuner … then I can send you the config"), kept in the app group so the real card reads what the tuner set.

/// The card's adjustable numbers. Defaults = what's on his phone now. Stored as JSON in the app group (`la.tuning`).
struct LATuning: Codable, Equatable {
    // Card
    var cardPaddingSides: Double = 15
    var cardPaddingTopBottom: Double = 12
    var cardMinHeight: Double = 88
    var gapRingToText: Double = 12
    var cardSurfaceGrey: Double = 0.12
    // Ring
    var ringSize: Double = 73   // his phone's tuner, 2026-10-14 (and the nine below)
    var ringArcDiameter: Double = 0.82      // of the ring size
    var ringBandWidth: Double = 5.5          // at the 90 pt design size
    var ringArcWidth: Double = 3.5          // at the 90 pt design size
    var ringSymbolSize: Double = 17
    var ringBandLift: Double = 0.1
    // Text
    var titleSize: Double = 20
    var timeLeftSize: Double = 14   // 12 read too small on his phone (owner, 2026-10-12)
    var endsSize: Double = 12
    var lineSpacing: Double = 1.5
    var textOffsetY: Double = 0
    // Glow
    var glowStrength: Double = 0.16
    var glowReach: Double = 0.51
    var glowCentreX: Double = 0.19
    var glowCentreY: Double = 0.5
    // Buttons
    var buttonSize: Double = 44
    var buttonSymbolSize: Double = 18
    var buttonStackGap: Double = 7
    var buttonOffsetX: Double = 0
    var buttonSymbolOpacity: Double? = nil   // nil = 0.65: the symbols a little dull, not stark white (owner)
    var symbolOpacity: Double { get { buttonSymbolOpacity ?? 0.65 } set { buttonSymbolOpacity = newValue } }
    // 15 s bar
    var barSideInset: Double = 5
    var barBottomInset: Double = 0
    var barThickness: Double = 0.8
    // Dynamic Island (opened up)
    var islandRingSize: Double = 66
    var islandTitleSize: Double = 20
    var islandLineSize: Double = 13
    var islandButtonSize: Double = 38
    var islandTimeSizeOpt: Double? = nil        // nil = 17: the folded island's "24m"
    /// The prayer name's weight: 0 light · 1 regular · 2 medium (nil — owner) · 3 semibold · 4 bold — the card and the island apart.
    var titleWeight: Int? = 1   // regular (his tuner, 2026-10-14; was medium)
    var islandTitleWeight: Int? = nil
    static let weights: [Font.Weight] = [.light, .regular, .medium, .semibold, .bold]
    static let weightNames = ["Light", "Regular", "Medium", "Semibold", "Bold"]
    var islandTimeSize: Double { get { islandTimeSizeOpt ?? 17 } set { islandTimeSizeOpt = newValue } }
    /// The opened island's row: the button's height (the time sits beside it now); the ring's side takes the same.
    var islandRowHeight: Double { islandButtonSize }
    /// The ended ring's dashes (owner: tunable): how many, how much of each step is dash, how bright, how thick (nil =
    /// the arc's width).
    var endedDashCountOpt: Double? = nil
    var endedDashShareOpt: Double? = nil
    var endedDashOpacityOpt: Double? = nil
    var endedDashWidthOpt: Double? = 2.5
    var endedDashCount: Double { get { endedDashCountOpt ?? 16 } set { endedDashCountOpt = newValue } }
    var endedDashShare: Double { get { endedDashShareOpt ?? 0.5 } set { endedDashShareOpt = newValue } }
    var endedDashOpacity: Double { get { endedDashOpacityOpt ?? 0.5 } set { endedDashOpacityOpt = newValue } }
    var endedDashWidth: Double { get { endedDashWidthOpt ?? ringArcWidth } set { endedDashWidthOpt = newValue } }
    // How the time left is written — iOS's self-updating formats only (a Live Activity has no timeline): 0 "1 hour,
    // 39 minutes" (offset) · 1 "1 hr, 39 min" (relative; under an hour it ticks seconds) · 2 "1:39" · 3 "1:39:12" ·
    // 4 (nil, the default — owner: no seconds) relative over an hour, then "59 minutes", then "under a minute", switched
    // by timer gates. Optional so a saved tuning without it still decodes (renamed from timeLeftStyle so earlier picks drop).
    var timeLeftFormat: Int? = 4

    /// Only what differs from the defaults is saved, laid over the defaults on reading — so a new default reaches every
    /// value nobody tuned (a full save kept the old ones). 3: earlier full saves are left behind.
    static let key = "la.tuning3"
    private static func dict(_ t: LATuning) -> [String: Any] {
        (try? JSONEncoder().encode(t)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    static var current: LATuning {
        guard let data = UserDefaults(suiteName: SharedStore.appGroup)?.data(forKey: key),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return LATuning() }
        let merged = dict(LATuning()).merging(saved) { _, new in new }
        return (try? JSONSerialization.data(withJSONObject: merged)).flatMap { try? JSONDecoder().decode(LATuning.self, from: $0) } ?? LATuning()
    }
    func save() {
        let base = Self.dict(LATuning())
        let changed = Self.dict(self).filter { k, v in !(base[k].map { "\($0)" == "\(v)" } ?? false) }
        if let data = try? JSONSerialization.data(withJSONObject: changed) { UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: Self.key) }
    }
    var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// The app's soft look, dark (the card is always dark — owner).
enum LASoft {
    /// The card's surface: the dark grey (tunable), or the app's light soft surface (asset NeuRing, light).
    static func surface(_ t: LATuning, _ scheme: ColorScheme = .dark) -> Color {
        scheme == .dark ? Color(white: t.cardSurfaceGrey) : Color(red: 0.890, green: 0.898, blue: 0.933)
    }
    /// The soft look's two shadows (assets NeuDarkShad / NeuLightShad in light; deeper in dark).
    static func shade(_ scheme: ColorScheme = .dark) -> Color { scheme == .dark ? .black.opacity(0.75) : .black.opacity(0.22) }
    static func light(_ scheme: ColorScheme = .dark) -> Color { scheme == .dark ? .white.opacity(0.06) : .white }
    /// The island is black: its soft pieces are a dark grey raised off it.
    static let island = Color(white: 0.11)
}

/// The running look until the window ends, the ended look from then on — by itself (timer gates), because iOS's stale
/// flag didn't flip at the stale date. Marked, or already stale: just that one look.
struct LAEnds<Content: View>: View {
    let state: PrayerWindowAttributes.ContentState
    let stale: Bool
    @ViewBuilder let content: (_ ended: Bool) -> Content
    var body: some View {
        // ONE structure in every state (owner: "the shared elements stay … just the new stuff animates in"): when the
        // card is marked or goes stale only the masks change, so iOS keeps the name, the ring, the card itself, and fades
        // just what's new or gone (an if / else here swapped the whole card in a cross-fade).
        // Marked: the SAME gates as while running, their switch set far off — a different mask (Color.white) still made
        // iOS fade the whole piece, so "Asr" ghosted as it was marked (the sim's island).
        let marked = state.markedAt != nil
        let edge = marked ? Date.distantFuture : state.end
        ZStack {
            content(false).mask {
                if stale && !marked { Color.clear } else { LAGate(from: nil, until: edge) }
            }
            content(true).mask {
                if stale && !marked { Color.white } else { LAGate(from: edge, until: nil) }
            }
        }
    }
}

/// The Lock Screen card (always dark).
extension EnvironmentValues {
    /// A picture of the card (the setup page and Settings' Card look play a window in seconds): its "ends" line keeps
    /// this time instead of the moving window's (owner: "the end time would stay fixed"). Never set on the real card.
    @Entry var laShownEnd: Date? = nil
    /// The Dynamic Island's views: their timed changes flip instead of fading (LAGate). On an island iPhone iOS archives
    /// them with the Lock Screen card, under one ~2 MB limit, and they were half of it (2026-10-16); the card keeps its fade.
    @Entry var laInstantGates = false
}

struct LALockCard: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let stale: Bool
    var t = LATuning.current
    @Environment(\.colorScheme) private var system
    var body: some View {
        // The buttons are drawn ONCE, over both looks: inside LAEnds the ended copy sat on top and took the touch, so the
        // visible button never showed its press (owner). The one button switches its own symbol at the end.
        let unmarkedEnded = stale && state.markedAt == nil
        LAEnds(state: state, stale: stale) { e in LALockCardBody(state: state, n: n, ended: e, t: t, liveButtons: true) }
            .overlay(alignment: .trailing) {
                LAGlyphs(state: state, n: n, ended: unmarkedEnded, size: t.buttonSize, onIsland: false, t: t, live: true)
                    .offset(x: t.buttonOffsetX)
                    .padding(.trailing, t.cardPaddingSides)
                    // Level with the ring's row, not the middle of a card grown by the last card's note.
                    .padding(.bottom, LALastNote.shows(state) ? LALastNote.room : 0)
            }
            .overlay(alignment: .bottom) {
                if LALastNote.shows(state) { LALastNote(state: state, n: n, live: true).padding(.bottom, 8) }
            }
            .environment(\.colorScheme, state.dark.map { $0 ? .dark : .light } ?? system)
    }
}

/// Look D's layout in the soft look: the soft ring with the prayer's symbol on the left, the name and two lines beside
/// it, the soft round buttons on the right, the score colour glowing out from the ring; once prayed, the 15 s bar.
struct LALockCardBody: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    /// The card draws its buttons itself, once (LALockCard): here they only hold their place.
    var liveButtons = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: t.gapRingToText) {
            LASideRing(state: state, ended: ended, size: t.ringSize, symbolSize: t.ringSymbolSize, onIsland: false, t: t)
            LANameLines(state: state, ended: ended, big: true, t: t).offset(y: t.textOffsetY)
            Spacer(minLength: 0)
            LAGlyphs(state: state, n: n, ended: ended, size: t.buttonSize, onIsland: false, t: t).offset(x: t.buttonOffsetX)
                .opacity(liveButtons ? 0 : 1).allowsHitTesting(!liveButtons)
        }
        .padding(.horizontal, t.cardPaddingSides).padding(.vertical, t.cardPaddingTopBottom)
        .frame(minHeight: t.cardMinHeight)
        // The last card queued: a line at its foot, centred (owner) — the row above keeps its size.
        .padding(.bottom, LALastNote.shows(state) ? LALastNote.room : 0)
        // Our own solid surface under the glow: iOS draws `activityBackgroundTint` see-through (the wallpaper turned a red
        // glow pink on his phone).
        .background {
            ZStack {
                LASoft.surface(t, scheme)
                LAWash(state: state, ended: ended, t: t)
            }
        }
        .overlay(alignment: .bottom) {
            LADismissBar(state: state).scaleEffect(x: 1, y: t.barThickness)
                .padding(.horizontal, t.barSideInset).padding(.bottom, t.barBottomInset)
        }
        .overlay(alignment: .bottom) {
            if LALastNote.shows(state) {
                LALastNote(state: state).padding(.bottom, 8)
                    .opacity(liveButtons ? 0 : 1).allowsHitTesting(false)   // the real card draws its button once (LALockCard)
            }
        }
        .activityBackgroundTint(LASoft.surface(t, scheme))
        .activitySystemActionForegroundColor(.primary)
    }
}

/// The last card shukr has queued says so (owner: "the last one … open the app if you want to keep receiving them"): one
/// quiet line at the card's foot, centred. Not once marked (the card is going), never on the island. Marking from the
/// card also adds the next ones (iOS lets a card's ✓ add cards; the alarm's Stop can't) — decision last-card-note B.
struct LALastNote: View {
    static let room: CGFloat = 22
    static let text = "Last card · tap to add more"
    static let toppedUpText = "Live Activity cards topped up"
    static func shows(_ s: PrayerWindowAttributes.ContentState) -> Bool {
        s.markedAt == nil && (s.last == true || s.toppedUp != nil)
    }
    let state: PrayerWindowAttributes.ContentState
    var n = 0
    /// The real card's button (drawn once, in LALockCard's overlay); elsewhere the same pill as a picture.
    var live = false
    var body: some View {
        if state.toppedUp != nil, state.last != true {
            // After a tap added more: a plain line with a green check, not a pill (owner) — it isn't a button. No count
            // (owner: "not worth worrying them, esp if they're non-power users").
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                Text(Self.toppedUpText)
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 3)
        } else if live {
            Button(intent: PrayerWindowRefreshIntent(n: n)) { pill(symbol: "arrow.clockwise", text: Self.text) }.buttonStyle(.plain)
        } else {
            pill(symbol: "arrow.clockwise", text: Self.text)
        }
    }
    private func pill(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text)
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// The soft ring with the prayer's symbol inside (a ✓ in its score colour once prayed).
struct LASideRing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let size: Double
    let symbolSize: Double
    let onIsland: Bool
    let t: LATuning
    var body: some View {
        ZStack {
            LARing(state: state, ended: ended, size: size * t.ringArcDiameter, onIsland: onIsland, t: t)
            if let at = state.markedAt {
                Image(systemName: "checkmark")
                    .font(.system(size: symbolSize * 0.9, weight: .medium))
                    .foregroundStyle(PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at)))
                    .transition(LATransitions.swap)
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .transition(LATransitions.swap)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The name, then: the time left (red in the last half hour) + "ends 6:48 PM"; prayed: "Prayed 4:31 PM" +
/// "Perfect · 100"; ended: "Asr ended" + "6:48 PM · not marked".
struct LANameLines: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let big: Bool
    let t: LATuning
    @Environment(\.laShownEnd) private var shownEnd
    var body: some View {
        let title = big ? t.titleSize : t.islandTitleSize
        let line = big ? t.timeLeftSize : t.islandLineSize
        let small = big ? t.endsSize : t.islandLineSize
        VStack(alignment: .leading, spacing: t.lineSpacing) {
            Text(ended ? "\(state.label) ended" : state.label)
                .font(.system(size: title, weight: LATuning.weights[min(max((big ? t.titleWeight : t.islandTitleWeight) ?? 2, 0), 4)]))
                .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if let at = state.markedAt {
                let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                Group {
                    Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: line)).foregroundStyle(.primary)
                    Text(PrayerScoring.summary(for: score))
                        .font(.system(size: small)).foregroundStyle(.secondary)
                }
                .transition(LATransitions.line)
            } else if ended {
                Text("\(state.end.formatted(date: .omitted, time: .shortened)) · not marked")
                    .font(.system(size: line)).foregroundStyle(.secondary)
            } else {
                let lastHalf = LAGate.lastHalf(of: state.end)
                Group {
                ZStack(alignment: .leading) {
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard, part: .early).foregroundStyle(.primary)
                        .mask { LAGate(from: nil, until: lastHalf) }
                    // Real semibold (owner: "rather have it bold in red than avoid the doubling"; the fade is short enough).
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard, part: .late).foregroundStyle(.red).fontWeight(.semibold)
                        .mask { LAGate(from: lastHalf, until: nil) }
                }
                .font(.system(size: line))
                // The island too (owner: the time between the two lines, as on the card; "24m" only folded).
                Text("ends \((shownEnd ?? state.end).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: small)).foregroundStyle(.secondary)
                }
                .transition(LATransitions.line)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// The time left, ticking by itself in a format iOS draws (`LATuning.timeLeftFormat`).
struct LATimeLeft: View {
    let end: Date
    var style = 0
    var suffix = true
    /// Which stretch this copy is ever seen in (the card's white copy is hidden from the last half hour, its red copy
    /// before it): a layer it can never show isn't drawn (`shown(…, never:)`).
    var part = LATimePart.all
    private var left: String { suffix ? " left" : "" }
    static let styles = ["1 hour, 39 minutes", "1 hr, 39 min · 19 min, 56 sec", "timer to the minute (iOS writes it in words)", "1:39:12", "1 hr, 39 min · 59 minutes"]
    /// What the tuner offers: 2 reads the same as 0 (iOS writes a minute-precision timer in words).
    static let offered = [4, 1, 0, 3]
    static let standard = 4
    var body: some View {
        switch style {
        case 4:
            // Relative drops to "19 min, 56 sec" under an hour and ticks; offset, minutes only, floors to "0 minutes" in the
            // last one — so three layers, each shown only in its own stretch (the sim: 1 hr, 0 min → 59 minutes on time).
            let hour = end.addingTimeInterval(-3600), minute = end.addingTimeInterval(-60)
            // Before the last half hour: over an hour, or 31–59 minutes. In it: under 31 minutes.
            ZStack(alignment: .leading) {
                Text("\(Text(end, style: .relative))\(left)").shown(from: nil, until: hour, never: part == .late)
                LAMinuteWords(end: end, left: left, part: part)
                    .shown(from: part == .late ? nil : hour, until: part == .early ? nil : minute)
                Text("under a minute\(left)").shown(from: minute, until: nil, never: part == .early)
            }
        case 1: Text("\(Text(end, style: .relative))\(left)")
        case 2: Text("\(Text(.currentDate, format: .timer(countingDownIn: Date.now..<max(end, .now), maxPrecision: .seconds(60))))\(left)")
        case 3: Text("\(Text(timerInterval: Date.now...max(end, .now), countsDown: true))\(left)")
        default: Text("\(Text(.currentDate, format: .offset(to: end, allowedFields: [.hour, .minute], maxFieldCount: 2, sign: .never)))\(left)")
        }
    }
}

/// After Mark prayed: how long until the card goes (15 s) — a thin grey bar, full at the tap, emptying right to left.
struct LADismissBar: View {
    let state: PrayerWindowAttributes.ContentState
    static let seconds: TimeInterval = 15
    var body: some View {
        if let at = state.markedAt {
            ProgressView(timerInterval: at...at.addingTimeInterval(Self.seconds), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(Color(white: 0.55))   // neutral: sage clashed with a yellow / red ring (owner)
                .labelsHidden()
        }
    }
}

/// The island's small right side: empty — the ring says enough — until the last half hour: "27m" in red (owner).
struct LACompactTrailing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    var body: some View {
        if state.markedAt == nil && !ended {
            LAIslandTime(end: state.end)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: 64)
        }
    }
}

/// "27m": the minutes left, by itself, for the last half hour. iOS has no such format (its minute-precision countdowns
/// are words), so this is the stock "27:08" countdown set flush right, its ":08" hidden under a mask the width of ":00",
/// and an "m" in that place. (Clipping it to the width of "00" from the left worked in the app but drew only the "m" on the
/// island: iOS lays a timer text out at its widest.) Under a minute: "<1m".
/// "30 minutes left" from the per-second countdown, so the number turns exactly on time (iOS's own minute text turned
/// 1–4 s late, and the red last half hour has to start just after "30" — owner): the stock "30:08" set so its digits
/// land on a hidden "00", the rest masked off, then " minutes left". "0" room under ten minutes; "1 minute left"; the
/// last minute is the caller's. Never fixedSize on the timer (an unbounded ideal width crashed the widget).
struct LAMinuteWords: View {
    let end: Date
    var left = " left"
    var part = LATimePart.all
    var body: some View {
        let ten = end.addingTimeInterval(-10 * 60), two = end.addingTimeInterval(-2 * 60)
        ZStack(alignment: .leading) {
            words(room: "00").shown(from: nil, until: part == .early ? nil : ten)
            words(room: "0").shown(from: ten, until: two, never: part == .early)
            Text("1 minute\(left)").shown(from: two, until: nil, never: part == .early)
        }
        .monospacedDigit()
    }
    private func words(room: String) -> some View {
        HStack(spacing: 0) {
            Text(room).hidden()
            Text(" minutes\(left)")
        }
        .overlay(alignment: .leading) {
            // "00:00" laid out (hidden), the timer flush right over it: its digits fall on the "00".
            HStack(spacing: 0) { Text(room).hidden(); Text(":00").hidden() }
                .overlay(alignment: .trailing) {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 400, alignment: .trailing)
                }
                .mask {
                    HStack(spacing: 0) {
                        Text(room).hidden().overlay(Color.black)
                        Text(":00").hidden()
                    }
                }
        }
    }
}

struct LAMinutesLeft: View {
    let end: Date
    /// The font size it's drawn at: its width is set from it (≈ "00m"), since the timer text claims room for far more
    /// (that widened the folded island; a hidden "00m" as the frame garbled the digits on the island).
    var size: Double = 14
    var body: some View {
        let one = end.addingTimeInterval(-60)
        // Never fixedSize here: in a widget a timer text's ideal width is unbounded, and the gates' GeometryReaders then
        // crashed the extension (the card vanished). A fixed room instead, the time flush right in it, clipped below.
        ZStack(alignment: .trailing) {
            // The "m" sits in the ":00"'s room, which is wider: pulled right by the difference so "24m" ends at the edge.
            minutes.padding(.trailing, -size * 0.62).frame(width: size * 4, alignment: .trailing).mask { LAGate(from: nil, until: one) }
            Text("<1m").lineLimit(1).frame(width: size * 4, alignment: .trailing).mask { LAGate(from: one, until: nil) }
        }
        .monospacedDigit()
        .frame(width: size * 2.8, alignment: .trailing)
        .clipped()
    }
    private var minutes: some View {
        ZStack(alignment: .trailing) {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
                .mask {
                    HStack(spacing: 0) {
                        Color.black
                        Text(":00").hidden()   // the seconds' room: masked away
                    }
                }
            Text(":00").hidden().overlay(alignment: .leading) { Text("m") }   // the "m" where ":08" was
        }
    }
}

/// The island's time left over its button: only in the last half hour, "27m" in red (owner: the ring says enough before).
struct LAIslandTime: View {
    let end: Date
    var size: Double = 14
    var body: some View {
        LAMinutesLeft(end: end, size: size).foregroundStyle(.red).fontWeight(.semibold)
            .mask { LAGate(from: LAGate.lastHalf(of: end), until: end) }
    }
}

/// The folded island's left side: the small ring (its right side is `LACompactTrailing`).
struct LACompactLeading: View {
    let state: PrayerWindowAttributes.ContentState
    let stale: Bool
    let t: LATuning
    var body: some View {
        // Room round the ring inside LAEnds' masks (each is exactly its content's box): the band, the arc and the glow are
        // stroked on the ring's edge and half of them was cut off (owner: "looks broken in bottom and left side"). The
        // negative padding gives the room back, so the island lays it out at 22 pt as before.
        // The ring alone, no prayer symbol inside (owner, 2026-10-16: "get rid of the symbol when it's in the collapsed
        // dynamic island"; it didn't draw on her 15 Pro at the smaller ring).
        LAEnds(state: state, stale: stale) { e in LAFoldedRing(state: state, ended: e, t: t).padding(6) }
            .padding(-6)
    }
}

/// The folded island's ring (and the minimal one beside another app's): smaller than its 22 pt slot and drawn thicker
/// (owner, 2026-10-16: it was clipped against the pill's rounded end on her 15 Pro — "make the radius smaller and the
/// ring / progress a little thicker"). The slot stays 22 pt so the island keeps its width; the band is plain (no shadows).
struct LAFoldedRing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    static let slot = 22.0, ring = 18.0, lineScale = 2.9   // band ≈ 3.1 pt, arc ≈ 2 pt (were 1.3 / 0.9)
    var body: some View {
        LARing(state: state, ended: ended, size: Self.ring, onIsland: true, lineScale: Self.lineScale, t: t)
            .frame(width: Self.slot, height: Self.slot)
    }
}

/// The island's left side: the soft ring.
struct LAIslandLeading: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        // No glow: the island is always black and each region clips to its own box (the glow came out a square).
        LASideRing(state: state, ended: ended, size: t.islandRingSize, symbolSize: t.islandRingSize * 0.26, onIsland: true, t: t)
    }
}

/// The island's ring with the name beside it (layouts 1 and 2 — Frank's mock).
struct LAIslandRingAndName: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        HStack(spacing: 12) {
            LAIslandLeading(state: state, ended: ended, t: t)
            LANameLines(state: state, ended: ended, big: false, t: t)
        }
        .frame(minHeight: t.islandRowHeight + 8)   // the button side's height (+ its 4 pt padding), centred alike
    }
}

/// The island's right side: the mark button (Frank's mock); prayed → camera over tasbih.
struct LAIslandTrailing: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    /// Drawn once (not inside LAEnds — a hidden copy on top took the touch): the button switches at the end itself.
    var live = false
    var body: some View {
        // A plain ✓ that never changes layout (a button whose contents switched by time took no tap on the island); the
        // time left is the name's middle line, as on the card — "24m" only on the folded island (owner).
        LAGlyphs(state: state, n: n, ended: ended, size: t.islandButtonSize, onIsland: true, t: t, live: live)
            .frame(minHeight: t.islandRowHeight)
            .padding(.vertical, 2)
    }
}

/// The right side: the soft round buttons — a ✓ marks it (owner: the circle looked odd); prayed → camera over the zikr beads;
/// ended → a grey dashed circle (Qaza; never red — owner).
struct LAGlyphs: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let size: Double
    let onIsland: Bool
    let t: LATuning
    /// Drawn once over both looks: the mark button turns from ✓ to the dim dashed circle by itself at the window's end.
    var live = false
    var body: some View {
        if state.markedAt != nil {
            // On the Lock Screen the pair fits the running card's row (the ring or the one button, whichever is taller), so
            // marking never makes the card taller (owner).
            // The island too: the pair fits the ring's height, so marking never resizes the island (a resize cross-faded
            // the whole island instead of swapping only what changed — owner).
            let row = onIsland ? max(t.islandRingSize, t.islandButtonSize) : max(t.ringSize, t.buttonSize)
            let pair = min(size * 0.82, (row - t.buttonStackGap) / 2)
            VStack(spacing: t.buttonStackGap) {
                LARoundButton(intent: PrayerWindowOpenIntent(what: "Photo", n: n), symbol: "camera", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
                LARoundButton(intent: PrayerWindowOpenIntent(what: "Tasbih", n: n), symbol: "circle.hexagonpath", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
            }
            .transition(LATransitions.swap)
        } else {
            HStack(spacing: t.buttonStackGap) {
                // The last card's ↻ beside the ✓ (owner: "more in your face"), as well as its pill; never on the island.
                if state.last == true && !onIsland {
                    LARoundButton(intent: PrayerWindowRefreshIntent(n: n), symbol: "arrow.clockwise", size: size,
                                  symbolSize: t.buttonSymbolSize * 0.9, t: t)
                        .transition(LATransitions.swap)
                }
                if ended {
                    LARoundButton(intent: PrayerWindowMarkIntent(n: n), symbol: "circle.dashed", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland, dim: true, t: t)
                        .transition(LATransitions.swap)
                } else {
                    LARoundButton(intent: PrayerWindowMarkIntent(n: n), symbol: "checkmark", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland,
                                  endsAt: live ? state.end : nil, t: t)
                        .transition(LATransitions.swap)
                }
            }
        }
    }
}

/// What changes when the card is updated (marked): what stays keeps its place, the new grows / rises in and the old
/// fades out (owner: "feels like one living card"). iOS plays transitions with its own timing (animation modifiers are
/// ignored), up to 2 s.
enum LATransitions {
    // Each with its own timing (Live Activities honour a transition's .animation): the old out fast, the new in just
    // after — at iOS's default the two overlapped for ~0.6 s and the old lingered (owner: "only brings in new items").
    private static let into = Animation.easeOut(duration: 0.25)
    // The old goes at once (a fading-out old under the fading-in new still overlapped for ~0.3 s), the new comes in.
    static let swap = AnyTransition.asymmetric(insertion: AnyTransition.scale(scale: 0.6).combined(with: .opacity).animation(into),
                                               removal: .identity)
    static let line = AnyTransition.asymmetric(insertion: AnyTransition.offset(y: 5).combined(with: .opacity).animation(into),
                                               removal: .identity)
}

/// Pressed: a touch darker and smaller.
struct LAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
    }
}

/// The app's soft raised disc.
struct LARoundButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: Double
    let symbolSize: Double
    var onIsland = false
    var dim = false
    /// The ✓ gives way to the dim dashed circle (Qaza) here, by itself.
    var endsAt: Date? = nil
    let t: LATuning
    var body: some View {
        Button(intent: intent) {
            LADisc(symbol: symbol, size: size, symbolSize: symbolSize, onIsland: onIsland, dim: dim, endsAt: endsAt, t: t)
        }
        .buttonStyle(LAPressStyle())
    }
}

/// A soft round button's face: the symbol on the raised disc.
struct LADisc: View {
    let symbol: String
    let size: Double
    let symbolSize: Double
    var onIsland = false
    var dim = false
    var endsAt: Date? = nil
    let t: LATuning
    private func glyph(_ name: String, dim: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: symbolSize, weight: .light))
            .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(t.symbolOpacity)))
    }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if let endsAt {
                glyph(symbol, dim: dim).mask { LAGate(from: nil, until: endsAt) }
                glyph("circle.dashed", dim: true).mask { LAGate(from: endsAt, until: nil) }
            } else {
                glyph(symbol, dim: dim)
            }
        }
        .frame(width: size, height: size)
        .background {
            if onIsland {
                // On the island's black a plain grey disc (owner): the soft shadows only showed as clipped corners.
                Circle().fill(Color(white: 0.19))
            } else {
                Circle().fill(LASoft.surface(t, scheme))
                    .shadow(color: LASoft.shade(scheme), radius: 3, x: 1.5, y: 1.5)
                    .shadow(color: LASoft.light(scheme), radius: 3, x: -1.5, y: -1.5)
            }
        }
    }
}

/// The score colour glowing out from the ring (Look D's halo), in the colour of the grade now (changes by itself);
/// prayed: its score's colour; ended: none.
struct LAWash: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    /// The island: a round glow this wide, centred on the ring (the island has no background of ours to fill).
    var islandRadius: Double? = nil
    var body: some View {
        // Only a prayer marked Perfect glows (owner, 2026-10-11): none while the window runs, nor for a lower grade.
        if let at = state.markedAt {
            let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
            if PrayerScoring.grade(for: score) == .perfect { wash(PrayerScoring.color(for: score)) }
        }
    }
    /// An ellipse centred on the ring (Look D: 120 % × 140 % of the card), the colour at `glowStrength`, gone by `glowReach`.
    @ViewBuilder private func wash(_ c: Color) -> some View {
        if let r = islandRadius {
            RadialGradient(colors: [c.opacity(t.glowStrength * 1.4), c.opacity(0)], center: .center, startRadius: 0, endRadius: r)
                .frame(width: r * 2, height: r * 2)
                .allowsHitTesting(false)
        } else {
            card(c)
        }
    }
    private func card(_ c: Color) -> some View {
        GeometryReader { g in
            let rx = g.size.width * 1.2 * t.glowReach, ry = g.size.height * 1.4 * t.glowReach
            EllipticalGradient(colors: [c.opacity(t.glowStrength), c.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: rx * 2, height: ry * 2)
                .position(x: g.size.width * t.glowCentreX, y: g.size.height * t.glowCentreY)
        }
    }
}

/// The window's grades in order, each with when it applies (its colour taken mid-stretch: 1 s after a change a long
/// window's score is still 0.99999…, which counts as Perfect).
enum LAGrades {
    struct Span { let grade: PrayerScoring.Grade; let color: Color; let from: Date?; let until: Date? }
    static func spans(_ s: PrayerWindowAttributes.ContentState) -> [Span] {
        let changes = PrayerScoring.gradeChanges(start: s.start, end: s.end)
        let starts: [Date?] = [nil] + changes.map { Optional($0) }
        return starts.enumerated().map { i, from in
            let a = from ?? s.start
            let b = i + 1 < starts.count ? (starts[i + 1] ?? s.end) : s.end
            let at = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let score = PrayerScoring.score(start: s.start, end: s.end, markedAt: at)
            return Span(grade: PrayerScoring.grade(for: score), color: PrayerScoring.color(for: score),
                        from: from, until: i + 1 < starts.count ? starts[i + 1] : s.end)
        }
    }
}

/// The soft raised band (the app's / widget's): the surface, lifted — shade down-right, light up-left.
struct LASoftBand: View {
    let width: Double
    let t: LATuning
    var surface: Color? = nil
    /// The lifted band (owner, 2026-10-14: "more apparent on the lock screen"); the island keeps the flat one (each of
    /// its regions clips, so no drop or glow there — island-rules.md).
    var lifted = true
    /// No shadows at all: the folded island's thick band (its shadows grew with it into a grey halo at the region's edge).
    var plain = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if plain {
            Circle().stroke(surface ?? LASoft.surface(t, scheme), lineWidth: width)
        } else if lifted && surface == nil {
            LiftedSoftBand(width: width, surface: LASoft.surface(t, scheme), shade: LASoft.shade(scheme), light: LASoft.light(scheme))
        } else {
            Circle()
                .stroke(surface ?? LASoft.surface(t, scheme), lineWidth: width)
                .shadow(color: LASoft.shade(surface == nil ? scheme : .dark), radius: width * 0.6, x: width * 0.3, y: width * 0.3)
                .shadow(color: LASoft.light(surface == nil ? scheme : .dark), radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
                .shadow(color: .white.opacity(t.ringBandLift), radius: width * 0.5, x: -width * 0.25, y: -width * 0.25)
        }
    }
}

/// The soft ring's band, lifted off its surface (the app icon's idea, decision app-icon-depth D, on the soft ring's own
/// radii — the edges stay soft, owner): today's shade and light, each stacked again wider and further; a long blurred
/// drop under the ring; a blurred glow along the band's top-left. Dark reads as raised, not a black outline. Mocked in
/// Settings → My Dev Stuff → Ring depth (RingDepthMocks.swift); used by the Live Activity card and the Prayers widget.
struct LiftedSoftBand: View {
    let width: Double
    let surface: Color
    let shade: Color
    let light: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let w = width, dark = scheme == .dark
        ZStack {
            Circle().stroke(lineWidth: w * 1.4)
                .foregroundStyle(Color.black.opacity(dark ? 0.5 : 0.14))
                .blur(radius: w * 1.6)
                .offset(x: w * 0.6, y: w * 0.9)
            Circle().stroke(surface, lineWidth: w)
                .shadow(color: shade, radius: w * 0.6, x: w * 0.3, y: w * 0.3)
                .shadow(color: shade.opacity(0.8), radius: w * 1.02, x: w * 0.54, y: w * 0.54)
                .shadow(color: light, radius: w * 0.9, x: -w * 0.3, y: -w * 0.3)
                .shadow(color: light, radius: w * 1.35, x: -w * 0.48, y: -w * 0.48)
            Circle().stroke(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.9), .white.opacity(0)],
                                           startPoint: .topLeading, endPoint: .center), lineWidth: w * 0.6)
                .blur(radius: w * 0.35)
        }
    }
}

/// A still picture of a card (Explore's pictures): its live arcs drawn once, at this moment, not redrawn 30 times a
/// second — a list of them sat at ~37 % CPU idle on the owner's 13 Pro Max (perf-recheck, 2026-10-14). nil = live.
private struct LAStillMomentKey: EnvironmentKey { static let defaultValue: Date? = nil }
extension EnvironmentValues {
    var laStillMoment: Date? {
        get { self[LAStillMomentKey.self] }
        set { self[LAStillMomentKey.self] = newValue }
    }
}

/// The live arc (the widget's `LiveArc`): a round arc with a glow, shown up to now by the stock timer ring used as a mask.
struct LALiveArc: View {
    let start: Date
    let end: Date
    let color: Color
    let width: Double
    @Environment(\.laStillMoment) private var stillMoment
    /// In the app (the tuner's preview) the stock timer ring is a spinner, not a gauge: there the arc is drawn up to now
    /// (once a second); on the Lock Screen it's the system's own, self-updating mask.
    private static let inApp = Bundle.main.bundleURL.pathExtension != "appex"
    var body: some View {
        if Self.inApp, let stillMoment {
            arc(upTo: stillMoment)
        } else if Self.inApp {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in   // smooth: the setup / Card look demo plays a window in seconds
                arc(upTo: ctx.date)
            }
        } else {
            systemArc
        }
    }

    private func arc(upTo now: Date) -> some View {
        let f = min(max(now.timeIntervalSince(start) / max(end.timeIntervalSince(start), 1), 0), 1)
        return Circle().trim(from: 0, to: f)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: color.opacity(0.45), radius: 3)
    }

    private var systemArc: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .mask {
                ZStack {
                    Color.black
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .labelsHidden()
                }
                .frame(width: 98, height: 98)
                .environment(\.colorScheme, .light)
                .compositingGroup()
                .brightness(-0.35)
                .contrast(3)
                .luminanceToAlpha()
            }
            .shadow(color: color.opacity(0.45), radius: 3)
    }
}

/// The ring at its 90 pt design size, scaled: one colour at a time (an arc per grade, each shown only while its grade
/// lasts). Prayed: the whole ring in its score. Ended: 8 grey dashes.
struct LARing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let size: Double
    var onIsland = false
    /// The band, the arc and the ended dashes this many times their design width: at the folded island's size the card's
    /// widths scale to hairlines (owner, 2026-10-16: "make the radius smaller and the ring / progress a little thicker").
    var lineScale: Double = 1
    let t: LATuning
    var body: some View {
        let band = t.ringBandWidth * lineScale, arc = t.ringArcWidth * lineScale
        ZStack {
            LASoftBand(width: band, t: t, surface: onIsland ? LASoft.island : nil, plain: lineScale > 1)
            if let at = state.markedAt {
                let c = PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at))
                Circle().stroke(c, style: StrokeStyle(lineWidth: arc, lineCap: .round))
                    .shadow(color: c.opacity(0.45), radius: 3)
            } else if ended {
                let step = CGFloat.pi * 90 / max(t.endedDashCount.rounded(), 1)
                Circle().stroke(Color.secondary.opacity(t.endedDashOpacity),
                                style: StrokeStyle(lineWidth: t.endedDashWidth * lineScale, lineCap: .round, dash: [step * t.endedDashShare, step * (1 - t.endedDashShare)]))
                    .rotationEffect(.degrees(-90))
            } else {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    LALiveArc(start: state.start, end: state.end, color: span.color, width: arc)
                        // The window's end needs no edge of its own: every ring sits in LAEnds, whose live copy goes then.
                        .mask { LAGate(from: span.from, until: span.until == state.end ? nil : span.until).frame(width: 110, height: 110) }
                }
            }
        }
        .frame(width: 90, height: 90)
        .scaleEffect(size / 90)
        .frame(width: size, height: size)
    }
}

/// The stretch of a window a copy of the time left is ever seen in: before the last half hour, in it, or both.
enum LATimePart { case all, early, late }

extension View {
    /// Shown from `from` until `until` (LAGate) — or, `never`, not drawn at all (the other copy of the time left draws
    /// it, so the line's room is the same). iOS ends a card whose archive passes ~2 MB, and every edge still to come
    /// (five timer bars) adds to it; on an island iPhone the island's views count too: a fresh card was 2.3 MB and iOS
    /// removed it within 2 s (chronod: archiveTooLarge, 2026-10-16). Draw and gate only what can show.
    @ViewBuilder func shown(from: Date?, until: Date?, never: Bool = false) -> some View {
        if !never { mask { LAGate(from: from, until: until) } }
    }
}

/// Visible from `from` (nil = from the start) until `until` (nil = for good), by itself: each edge is a stock timer bar
/// over a 1 s interval stretched over the whole area, thresholded to all-or-nothing.
struct LAGate: View {
    let from: Date?
    let until: Date?
    /// How a look gives way to the next when its time comes (owner, 2026-10-12: show both): 0 a 1 s wipe left to right
    /// (the stock bar filling), 1 an instant flip, 2 a fade in 5 instant steps over 0.15 s (a blurred, soft-edged sweep
    /// froze on the Lock Screen: the blur stops the bar's live fill). App group `la.gateStyle`.
    static let styleKey = "la.gateStyle"
    /// Unset = the fade (owner: "I think I like fade").
    static var style: Int {
        let g = UserDefaults(suiteName: SharedStore.appGroup)
        return g?.object(forKey: styleKey) == nil ? 2 : g?.integer(forKey: styleKey) ?? 2
    }
    private static let steps = 5
    private static let fadeLength: TimeInterval = 0.15   // owner: 0.15 s (1.5, 0.5, 0.25 read as lag)
    /// The island's views flip (`laInstantGates`): fewer timer bars in the card's archive.
    @Environment(\.laInstantGates) private var instant

    /// When the last half hour's red begins: 1 s after the time left turns "30" (owner: white "30" fades to red "30").
    /// The words under an hour come from the per-second countdown (LAMinuteWords), which reads "30" from end − 30:59, so
    /// the red starts a second later (owner: "30 for 1 second"). iOS's own minute text turned 1–4 s late.
    static func lastHalf(of end: Date) -> Date { end.addingTimeInterval(-31 * 60 + 2) }

    var body: some View {
        // An edge already passed when this is drawn is drawn solid: its stock bar re-filled on every update, sweeping a
        // look across the card (owner). Only edges still to come are bars (empty until then, so nothing moves).
        let now = Date()
        let style = instant ? 1 : Self.style
        Group {
            if let from, from > now {
                if style == 2 { fadeIn(from, now: now) } else { edge(from, fill: .white, ground: .black, lift: -0.35, span: style == 1 ? 0.05 : 1) }
            } else { Color.white }
        }
        .mask {
            if let until {
                if until > now {
                    if style == 2 { fadeOut(until, now: now) } else { edge(until, fill: .black, ground: .white, lift: 0.2, span: style == 1 ? 0.05 : 1) }
                } else { Color.clear }
            } else { Color.white }
        }
    }

    /// Coverage rising k/N as the N layers switch on one by one (layer i at 1/(N−i+1) opacity — "over" adds up linearly).
    private func fadeIn(_ t: Date, now: Date) -> some View {
        let n = Self.steps, dt = Self.fadeLength / Double(n)
        return ZStack {
            ForEach(1...n, id: \.self) { i in
                let at = t.addingTimeInterval(Double(i - 1) * dt)
                Group {
                    if at > now { edge(at, fill: .white, ground: .black, lift: -0.35, span: 0.05) } else { Color.white }
                }
                .opacity(1 / Double(n - i + 1))
            }
        }
    }

    /// Coverage falling 1 − k/N: layer j (opacity 1/j) switches off j-th.
    private func fadeOut(_ t: Date, now: Date) -> some View {
        let n = Self.steps, dt = Self.fadeLength / Double(n)
        return ZStack {
            ForEach(1...n, id: \.self) { j in
                let at = t.addingTimeInterval(Double(j - 1) * dt)
                Group {
                    if at > now { edge(at, fill: .black, ground: .white, lift: 0.2, span: 0.05) } else { Color.clear }
                }
                .opacity(1 / Double(j))
            }
        }
    }

    private func edge(_ t: Date, fill: Color, ground: Color, lift: Double, span: TimeInterval) -> some View {
        GeometryReader { geo in
            ZStack {
                ground
                ProgressView(timerInterval: t...t.addingTimeInterval(span), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(fill)
                    .labelsHidden()
                    .frame(width: geo.size.width)
                    .scaleEffect(x: 1, y: max(geo.size.height, 4) * 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .environment(\.colorScheme, .light)   // in dark the stock bar's tint resolves differently
            .compositingGroup()
            .brightness(lift)
            .contrast(3)
            .luminanceToAlpha()
        }
    }
}


// MARK: - Excused from prayer (haid / after childbirth; owner, 2026-10-13, plan board/mocks/excused-days)

/// One stretch she was (or is) excused from prayer. A prayer whose window touches it can't be marked and isn't asked of
/// her; the app's "counted days" leave its prayer days out of streaks and stats (Excused.swift).
struct ExcusedRange: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case haid, nifas }
    var id = UUID()
    var kind: Kind
    var start: Date
    /// Her estimate: the check-ins are planned from it. Nothing ends by itself.
    var expectedEnd: Date
    /// Set when she ends it; nil while it runs.
    var end: Date?
    /// Zikr reminders pause too (her choice; zikr streaks never break on excused days either way).
    var pauseZikr: Bool

    /// A prayer window [from, to) she's excused from: it overlaps this stretch, and she was still excused when it ended.
    /// Ending it during a prayer's time makes that prayer due (it can be marked), as the fiqh has it.
    func covers(from: Date, to: Date) -> Bool { to > start && from < (end ?? .distantFuture) && (end.map { $0 >= to } ?? true) }
}

/// The one record (app group, JSON): every range, the running one last. Only the app writes it; the widget and the
/// intents read it. Read it once per loop (`ranges`) — each read decodes.
enum Excused {
    static let key = "excused.ranges"
    static let changed = Notification.Name("ExcusedChanged")

    /// Decoded once per change, not per call: every prayer row, the circle (≈10×/s while idle) and the widget's rows ask
    /// (perf-recheck, 2026-10-14). The stored bytes are compared — cheap — so a change from any process is seen at once.
    static var ranges: [ExcusedRange] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        rangesLock.lock(); defer { rangesLock.unlock() }
        if let cached = rangesCache, cached.data == data { return cached.list }
        let list = (try? JSONDecoder().decode([ExcusedRange].self, from: data)) ?? []
        rangesCache = (data, list)
        return list
    }
    private static let defaults = UserDefaults(suiteName: SharedStore.appGroup)
    private static let rangesLock = NSLock()
    nonisolated(unsafe) private static var rangesCache: (data: Data, list: [ExcusedRange])?
    static var current: ExcusedRange? { ranges.last(where: { $0.end == nil }) }
    static var isActive: Bool { current != nil }

    /// A prayer window she's excused from (marking it does nothing).
    static func covers(start: Date, end: Date, in list: [ExcusedRange] = ranges) -> Bool {
        list.contains { $0.covers(from: start, to: end) }
    }

    /// Written only when it changed: every app-group write invalidates bound @AppStorage (CLAUDE.md).
    static func save(_ list: [ExcusedRange]) {
        guard list != ranges, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: key)
    }
}

/// Excused, and someone tried to mark a prayer (she may be done and forgot): shukr opens and asks whether she's back,
/// never a silent no (owner). The flag is read by the Salah page (`openFromWidgetFlags`).
enum ExcusedResume {
    static let askKey = "excused.askResume"
    static func ask() {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: askKey)
        DeepLinkSignal.post()
    }
}

/// The Prayers widget's check and rows while excused: opens shukr to "Prayers are paused · I'm back".
struct ExcusedResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Prayers"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        ExcusedResume.ask()
        return .result()
    }
}
