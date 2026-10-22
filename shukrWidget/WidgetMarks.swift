//
//  WidgetMarks.swift
//  shukr (app and widget extension)
//
//  Marking from the Prayers widget: its ✓ and list rows, the store's marking side, the list toggles.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 3).
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData
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
        await MarkLog.$source.withValue("widget ✓") {
            if let hook = PrayerWindowHooks.widgetMark {
                _ = await hook(prayerName, prayerStart, prayerEnd)
            } else {
                SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
            }
        }
        WidgetPerf.log("mark \(prayerName) done \(WidgetPerf.ms(since: t0)) ms")
        return .result()
    }
}

extension SharedStore {
    /// Marks the prayer `name` on the day of `start` complete, scored at the tap. The widget's ✓
    /// (`MarkCompleteIntent`) runs in shukr through `PrayerWindowHooks.widgetMark`; this is the store
    /// path for a background launch (the hook isn't set yet) and the notification action "I already
    /// prayed" (`NotificationDelegate`). Writes through its own container and sets
    /// `widgetWroteStoreKey`, so the app re-reads on its next activation. Returns false when
    /// the prayer hasn't started, is already complete, or the store can't be opened.
    @discardableResult
    static func markPrayerComplete(named name: String, start: Date, end: Date) -> Bool {
        // Same rule as the app: a prayer that hasn't started can't be completed; nor one she's excused from.
        guard start <= Date() else { MarkLog.mark("not marked: hasn't started", name: name, start: start, end: end); return false }
        guard !Excused.covers(start: start, end: end) else { MarkLog.mark("not marked: excused", name: name, start: start, end: end); return false }
        guard let container = widgetContainer else {
            MarkLog.mark("NOT marked: the store couldn't open", name: name, start: start, end: end); return false
        }
        let context = ModelContext(container)
        var made = false

        // The app creates today's rows when it opens; if it hasn't opened today, make this one.
        let prayer = fetchPrayer(named: name, on: start, in: context) ?? {
            made = true
            let row = PrayerModel(name: name, startTime: start, endTime: end, dateAtMake: start)
            context.insert(row)
            return row
        }()
        guard !prayer.isCompleted else {
            MarkLog.mark("not marked: already marked", name: name, start: start, end: end, row: prayer); return false
        }
        // The row's own start, not the caller's: a widget or banner drawn at another place (or before a times change)
        // could mark a prayer that hasn't started here yet — scored Perfect before its time (mark audit #7).
        guard prayer.startTime <= Date() else {
            MarkLog.mark("not marked: this row starts \(prayer.startTime.formatted(date: .omitted, time: .shortened)) (the caller's times differ)",
                         name: name, start: start, end: end); return false
        }

        prayer.isCompleted = true
        prayer.setPrayerScore()                                        // scored now, at the tap
        let place = lastKnownLocation()
        prayer.setPrayerLocation(with: place)
        // A spot coarser than 100 m never decides a masjid (the toggle's rule, audit B10): "checked, no search". Within it,
        // nil — the app's catch-up decides (your own masajid first).
        if let place, place.horizontalAccuracy > 100 { prayer.mosqueName = "" }
        prayer.cancelUpcomingNudges()                                  // app repeats this on next open in case extensions can't
        do { try context.save() } catch {
            print("❌ markPrayerComplete(\(name)) save failed: \(error)")
            MarkLog.mark("NOT marked: save failed (\(error.localizedDescription))", name: name, start: start, end: end); return false
        }
        MarkLog.mark("marked (store)", name: name, start: start, end: end, row: prayer, location: MarkLog.lastAppFix(),
                     note: made ? "row made here (the app hadn't opened today)" : nil)

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
        let marked: Bool = await MarkLog.$source.withValue("widget list") {
            if let hook = PrayerWindowHooks.widgetMark { return await hook(prayerName, prayerStart, prayerEnd) }
            return SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
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

// MARK: - The mark log

/// Every prayer mark and unmark, wherever it came from (owner, 2026-10-22: "can we tell from when something is marked what
/// source it came from … are we able to get the time properly? Are we able to get the location properly? … put some logging
/// on my phone, and then I'll go ahead and test it out throughout the week"): one line each in the app group's
/// Library/Application Support/marks.log, from the app and the widget extension alike, the last ~3000 lines. DEBUG builds
/// (his phones). Read in My Dev Stuff → Mark log; scripts/pull-feedback.sh pulls it.
/// A line: when · process · where it came from · the prayer, its prayer day and window → what happened · the time stored
/// (and how far from the tap) · its word · where the location came from.
enum MarkLog {
    /// Where the mark came from. Each entry point sets it around its mark (a task-local, so the shared paths underneath —
    /// the app's toggle, the store's mark — know it); "app" when nothing did (the list, the circle, Journey).
    @TaskLocal static var source = "app"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Library/Application Support/marks.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.markLog")

    /// One mark's line. `tap` is when the person tapped (the watch's own time; else now); `location` says where the saved
    /// location came from (`fix(_:raw:)` / `lastAppFix()`).
    static func mark(_ result: String, name: String, start: Date, end: Date, row: PrayerModel? = nil, tap: Date = Date(),
                     location: String? = nil, note: String? = nil) {
        var parts = ["\(source) · \(name) (day \(PrayerDay.key(forRow: name, startingAt: start)), \(clock(start))–\(clock(end))) → \(result)"]
        if let row, row.isCompleted {
            let stored = row.timeAtComplete.map { at -> String in
                let off = Int(at.timeIntervalSince(tap).rounded())
                return "stored \(clock(at, seconds: true))" + (abs(off) < 2 ? "" : " (\(off > 0 ? "+" : "")\(off) s from the tap)")
            } ?? "no time stored"
            parts.append(stored)
            parts.append(row.gradeWord ?? "no grade")
            if let kind = row.markKind { parts.append("kind \(kind)") }
            if row.dayKey != PrayerDay.key(forRow: name, startingAt: start) { parts.append("⚠︎ row's day \(row.dayKey)") }
        }
        if let location { parts.append("location: \(location)") }
        if let note { parts.append(note) }
        add(parts.joined(separator: " · "))
    }

    /// A line of its own (a fresh location landing after the mark, an unmark).
    static func add(_ line: String) {
        #if DEBUG
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss"
        let text = "\(f.string(from: Date()))  [\(Bundle.main.bundleURL.pathExtension == "appex" ? "ext" : "app")] \(line)\n"
        print("📍 \(line)")
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? Data(text.utf8).write(to: url) }
            // Weeks of it, never too big: the last ~3000 lines once it passes 600 KB.
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 600_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? (all.split(separator: "\n").suffix(3000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }

    /// The app's own fix as saved (`raw` = what the location manager had, used or not).
    static func fix(_ used: CLLocation?, raw: CLLocation?) -> String {
        if let used { return "this phone's fix ±\(Int(used.horizontalAccuracy)) m, \(age(used.timestamp)) old" }
        guard let raw else { return "none (no fix yet)" }
        return "none (the fix was ±\(Int(raw.horizontalAccuracy)) m, \(age(raw.timestamp)) old — too rough or too old)"
    }
    /// The store path's location: the app's last good fix, shared through the app group, if under 30 min old.
    static func lastAppFix() -> String {
        guard let fix = SharedStore.lastKnownLocation() else {
            let store = UserDefaults(suiteName: SharedStore.appGroup)
            if let f = store?.array(forKey: SharedStore.lastFixKey) as? [Double], f.count == 4 {
                return "none (the app's last fix is \(age(Date(timeIntervalSince1970: f[3]))) old)"
            }
            let at = store?.double(forKey: SharedStore.lastFixAtKey) ?? 0
            return at > 0 ? "none (the app's last fix is \(age(Date(timeIntervalSince1970: at))) old)" : "none (the app has no fix saved)"
        }
        return fix.horizontalAccuracy > 0 ? "the app's last fix ±\(Int(fix.horizontalAccuracy)) m, \(age(fix.timestamp)) old"
            : "the app's last fix, \(age(fix.timestamp)) old (from before this build: no accuracy kept)"
    }

    private static func age(_ d: Date) -> String {
        let s = max(Int(Date().timeIntervalSince(d)), 0)
        return s < 90 ? "\(s) s" : s < 5400 ? "\(s / 60) min" : "\(s / 3600) h"
    }
    private static func clock(_ d: Date, seconds: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
        return f.string(from: d)
    }
}
