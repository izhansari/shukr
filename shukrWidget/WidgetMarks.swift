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
    /// Marks the prayer `name` on the day of `start` complete, scored at the tap. The widget's ✓
    /// (`MarkCompleteIntent`) runs in shukr through `PrayerWindowHooks.widgetMark`; this is the store
    /// path for a background launch (the hook isn't set yet) and the notification action "I already
    /// prayed" (`NotificationDelegate`). Writes through its own container and sets
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
