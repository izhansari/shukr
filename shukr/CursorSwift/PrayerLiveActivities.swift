//
//  PrayerLiveActivities.swift
//  shukr
//
//  Each prayer window as a Live Activity (owner, 2026-10-11; research and rules: board mocks/prayer-live-activities/).
//  iOS 26+: windows are scheduled ahead to start by themselves (`Activity.request(…, start:)`), up to iOS's 5 at a time.
//  Every time shukr gets to run — an open, going to the background, a window starting (iOS wakes shukr then, even killed
//  or locked), a card's ✓, a widget's mark, a mark in the app, a Settings toggle — `plan` ends what shouldn't show and
//  tops the schedule back up. iOS refuses new ones while shukr is in the background except during a LiveActivityIntent's
//  run (one per run, found on his phone), so the full refill comes with an open. Log: app group
//  Library/Application Support/live-activities.log (PrayerWindowLog).
//

import ActivityKit
import UserNotifications
import CoreLocation
import SwiftData
import SwiftUI
import WidgetKit

enum PrayerLiveActivities {
    /// A card's Photo: PrayerTimesView's page opens that prayer's camera (object: the prayer's name).
    static let openPhoto = Notification.Name("liveActivity.openPhoto")
    /// A card's Tasbih: Tasbih Fatimah, as the post-salah pill opens it (app-group flag, read with the widget's flags).
    static let openTasbihKey = "liveActivity.openTasbih"
    private static var g: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup)! }
    static var supported: Bool { if #available(iOS 26.0, *) { return true } else { return false } }

    // MARK: Launch

    @MainActor static func onLaunch() {
        // The Prayers widget's camera (any iOS): the same camera the card's Photo opens.
        PrayerWindowHooks.openPhoto = { name in
            try? await Task.sleep(for: .milliseconds(700))   // shukr in front first
            NotificationCenter.default.post(name: openPhoto, object: name)
        }
        // A widget / Siri / Control Center / card mark runs the app's path on every iOS (B, Frank-reviewed 2026-10-22): below
        // 26 it went straight to the store — no fresh location, and with the app alive the list stayed unmarked until the
        // next activation (nothing posted markedElsewhere). plan() and the card calls inside it guard themselves for < 26.
        PrayerWindowHooks.widgetMark = { name, start, end in await widgetMark(name, start, end) }
        guard #available(iOS 26.0, *) else { return }
        let state = UIApplication.shared.applicationState
        var line = "launch · " + (state == .background ? "background" : state == .active ? "active" : "inactive")
        line += " · enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)"
        if !UIApplication.shared.isProtectedDataAvailable { line += " · LOCKED" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { line += " · LOW POWER" }
        PrayerWindowLog.add(line)
        PrayerWindowHooks.mark = { n in await mark(n) }
        PrayerWindowHooks.open = { n, what in await open(n, what) }
        PrayerWindowHooks.refresh = { n in await refresh(n) }
        for activity in Activity<PrayerWindowAttributes>.activities { observe(activity) }
        Task { @MainActor in
            for await activity in Activity<PrayerWindowAttributes>.activityUpdates { observe(activity) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in plan(reason: "background") }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in planOnOpen(reason: "foreground") }
        }
        #if DEBUG
        if debugLaunch() { return }
        #endif
        Task { @MainActor in planOnOpen(reason: "launch") }
    }

    /// Cards held right now (waiting or on).
    @MainActor static var heldCount: Int {
        guard #available(iOS 26.0, *) else { return 0 }
        return Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active }.count
    }

    /// Opening shukr refills everything. The banner says so only after the warning that notifications are running out
    /// (owner, 2026-10-14: "I only want it to come up on the app on its own after the heads up notification that
    /// notifications are running out. The only other time … from pressing the refresh on the live activity card"): the
    /// heads-up (keepalive.ahead.*) or, if that was swiped away, the last one (plain keepalive.<day>) — not easing off,
    /// not cards running low (every install wiped them, so it showed on most opens), not "nothing pending". The ↻ path
    /// (`refresh`) shows it itself.
    @MainActor static func planOnOpen(reason: String) {
        plan(reason: reason)
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        if heldCount > 0, group?.bool(forKey: "la.everHeld") != true { group?.set(true, forKey: "la.everHeld") }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized,
                  UserDefaults.standard.bool(forKey: "firstRunSetup.v1") else { return }
            let warnings = await center.deliveredNotifications().map(\.request.identifier)
                .filter { $0.hasPrefix(NotificationScheduler.headsUpPrefix) || NotificationScheduler.isLastKeepAlive($0) }
            guard !warnings.isEmpty else { return }
            try? await Task.sleep(for: .seconds(2))   // the open's own notification re-plan first
            // Only on screen: a background wake (a card starting, the alarm's Stop) runs this too.
            guard UIApplication.shared.applicationState == .active else { return }
            await TopUpBanner.show()
            // Said once: the warnings are stale now (else every open would show it again).
            center.removeDeliveredNotifications(withIdentifiers: warnings)
            TopUpLog.add("open after the running-low warning · the banner shown")
        }
    }

    /// Each card's state changes: a window starting is shukr's chance to end the one before it and top up.
    @MainActor private static var observed = Set<String>()
    @MainActor private static func observe(_ activity: Activity<PrayerWindowAttributes>) {
        guard observed.insert(activity.id).inserted else { return }
        Task { @MainActor in
            for await st in activity.activityStateUpdates {
                let late = st == .active ? String(format: " · %+.0f s after its start", Date().timeIntervalSince(activity.content.state.start)) : ""
                PrayerWindowLog.add("#\(activity.attributes.n) \(activity.content.state.label) → \(st)\(late)"
                                    + (UIApplication.shared.applicationState == .background ? " · bg" : ""))
                if st == .active {
                    plan(reason: "\(activity.content.state.label) started")
                    AutoTopUp.request("\(activity.content.state.label) card started")   // a moment iOS gives shukr: top everything up
                }
            }
        }
    }

    // MARK: The card's buttons

    /// The card's ✓: the real prayer marked through the app's own toggle (the list's dot — location, masjid / Jumu'ah,
    /// score, streaks, widgets, the watch); the card turns to Photo / Tasbih for 15 s, then shukr ends it itself
    /// (`end(.after: 15)` was removed by iOS 28 ms later on his phone). Then as many new windows as iOS lets this run add.
    @MainActor static func mark(_ n: Int) async {
        guard #available(iOS 26.0, *) else { return }
        guard let a = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n }) else {
            PrayerWindowLog.add("mark #\(n): no such card"); return
        }
        var st = a.content.state
        marking.insert(n)   // the toggle re-plans at once: this card isn't "prayed, end it" — it turns
        defer { marking.remove(n) }
        _ = markPrayer(st.label, start: st.start, end: st.end, from: "card")
        st.markedAt = Date()
        let t0 = Date()
        await a.update(ActivityContent(state: st, staleDate: nil))
        // As many as this run may add (owner: "not just the next one but however many until we can't").
        var total = 0
        for attempt in 1...6 {
            let added = plan(reason: "card ✓, try \(attempt)")
            total += added
            if added == 0 { break }
            try? await Task.sleep(for: .milliseconds(400))
        }
        if total > 0 { PrayerWindowLog.add("card ✓ added \(total)") }
        let wait = 15 - Date().timeIntervalSince(t0)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if a.activityState == .active { await a.end(nil, dismissalPolicy: .immediate) }
        plan(reason: "card ✓, after its 15 s")   // its slot is free now (the 5 were full at the tap — Frank)
        AutoTopUp.request("card ✓")
    }

    /// The last card's ↻: as many as this run may add; the tapped card then says how far they go; everything else topped up.
    @discardableResult @MainActor static func refresh(_ n: Int) async -> Int {
        let heldAtTap = heldCount
        #if DEBUG
        holdPlans = false   // an explicit ask (a stand-in's hold would turn it away)
        #endif
        // The intent opens shukr: wait until it's in front (up to 5 s), where iOS lets it fill every free slot.
        for _ in 0..<50 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        PrayerWindowLog.add("refresh: shukr is \(UIApplication.shared.applicationState == .active ? "in front" : "still not in front")")
        for attempt in 1...6 {
            let added = plan(reason: "refresh, try \(attempt)")
            if added == 0 { break }
            try? await Task.sleep(for: .milliseconds(400))
        }
        // Counted from the tap, not this plan alone: the open's own plan may have added them a moment before.
        let total = max(heldCount - heldAtTap, 0)
        PrayerWindowLog.add("refresh added \(total)")
        // The tapped card says how far the cards now go (owner) — only when it's no longer the last.
        if total > 0, #available(iOS 26.0, *),
           let tapped = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n }),
           let newest = Activity<PrayerWindowAttributes>.activities
               .filter({ $0.activityState == .pending || $0.activityState == .active })
               .max(by: { $0.content.state.start < $1.content.state.start }) {
            var st = tapped.content.state
            st.last = nil
            st.toppedUp = "\(total)"
            await tapped.update(ActivityContent(state: st, staleDate: st.end))
        }
        // In front: notifications and Fajr alarms now too (not the 3 h limit), then the banner says what's set.
        if UIApplication.shared.applicationState == .active, let container = NotificationScheduler.appContainer {
            await NotificationScheduler.rescheduleNow(context: container.mainContext, reason: "last card's refresh")   // + Fajr alarms
            TopUpLog.add("last card's refresh · open · cards +\(total), notifications and alarms re-planned")
            await TopUpBanner.show()
        } else {
            AutoTopUp.request("last card's refresh", force: true)
        }
        return total
    }

    /// Cards turning to their marked look right now (`plan` leaves them be).
    @MainActor private static var marking = Set<Int>()

    /// Photo / Tasbih: the card goes, shukr opens the prayer's camera or Tasbih Fatimah in place.
    @MainActor static func open(_ n: Int, _ what: String) async {
        let a = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n })
        let name = a?.content.state.label
        if let a { await a.end(nil, dismissalPolicy: .immediate) }
        if what == "Photo", let name {
            try? await Task.sleep(for: .milliseconds(700))   // shukr in front first
            NotificationCenter.default.post(name: openPhoto, object: name)
        } else if what == "Tasbih" {
            g.set(true, forKey: openTasbihKey)
            DeepLinkSignal.post()
        }
    }

    // MARK: Marks from elsewhere

    /// Marks a prayer the way the list does when the app's list holds it, else through the shared store. Returns whether
    /// it's marked now, and the row's location state for the log.
    @MainActor @discardableResult
    private static func markPrayer(_ name: String, start: Date, end: Date, from: String) -> Bool {
        // The saved data couldn't open (StoreFallback): an outside ✓ does nothing, even with the list up — else the app
        // showed it marked (in memory, lost at the next launch) while the widget didn't (mark audit #4; owner, 2026-10-18).
        guard !StoreFallback.active else {
            PrayerWindowLog.add("\(from) mark \(name) → not marked (the store couldn't open)")
            MarkLog.mark("NOT marked: the saved data couldn't open (StoreFallback)", name: name, start: start, end: end)
            return false
        }
        if let vm = PrayerViewModel.current, let row = vm.todaysRow(named: name, startingAt: start) {
            if !row.isCompleted { vm.togglePrayerCompletion(for: row) }   // saves, pushes to widgets / watch, re-plans
            PrayerWindowLog.add("\(from) mark \(name) → \(row.isCompleted ? "marked" : "NOT marked") (the list's toggle)"
                                + " · location \(row.latPrayedAt == nil ? "none" : "saved")")
            return row.isCompleted
        }
        // The app's list isn't up (a background launch): the store's own path, as the widget did. The app re-reads it
        // on its next activation (widgetWroteStore).
        let done = SharedStore.markPrayerComplete(named: name, start: start, end: end)
        PrayerWindowLog.add("\(from) mark \(name) → \(done ? "marked" : "not marked (done already / not started)") (store)"
                            + " · last fix \(SharedStore.lastKnownLocation() == nil ? "too old" : "used")")
        return done
    }

    /// A widget's mark, now run in shukr (MarkCompleteIntent / MarkFromListIntent are LiveActivityIntents): marked as the
    /// list does, its card ended at once, and — when the row got no location — one fresh fix tried for it (S9FJ: whether
    /// a widget tap may use While Using location is what the log will tell).
    @MainActor static func widgetMark(_ name: String, _ start: Date, _ end: Date) async -> Bool {
        let marked = markPrayer(name, start: start, end: end, from: "widget")
        if PrayerViewModel.current == nil { plan(reason: "widget mark") }   // the VM's toggle re-plans by itself
        AutoTopUp.request("widget ✓")
        WidgetCenter.shared.reloadAllTimelines()
        if marked && rowLocation(name, start) == nil {
            // After this run returns (the widget redraws at once): kept alive by a background task, 10 s at most.
            var task: UIBackgroundTaskIdentifier = .invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "widget mark location") {
                UIApplication.shared.endBackgroundTask(task)
            }
            Task { @MainActor in
                await freshLocation(for: name, start: start)
                UIApplication.shared.endBackgroundTask(task)
            }
        }
        return marked
    }

    @MainActor private static func rowLocation(_ name: String, _ start: Date) -> (Double, Double)? {
        if let vm = PrayerViewModel.current, let row = vm.todaysRow(named: name, startingAt: start) {
            return row.latPrayedAt.flatMap { lat in row.longPrayedAt.map { (lat, $0) } }
        }
        guard let c = SharedStore.widgetContainer,
              let row = SharedStore.fetchPrayer(named: name, on: start, in: ModelContext(c)) else { return nil }
        return row.latPrayedAt.flatMap { lat in row.longPrayedAt.map { (lat, $0) } }
    }

    /// One fix within 8 s (≤ 100 m, fresh), saved on the prayer; what iOS said is logged either way.
    @MainActor private static func freshLocation(for name: String, start: Date) async {
        let t0 = Date()
        let auth = CLLocationManager().authorizationStatus
        let authText = auth == .authorizedAlways ? "Always" : auth == .authorizedWhenInUse ? "While Using" : "status \(auth.rawValue)"
        var note = ""
        let fix: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await u in CLLocationUpdate.liveUpdates() {
                        if u.insufficientlyInUse { await MainActor.run { note = " · iOS: not in use" } }
                        if u.authorizationDenied || u.authorizationDeniedGlobally { await MainActor.run { note = " · iOS: denied" } }
                        if let l = u.location, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 100,
                           l.timestamp > t0.addingTimeInterval(-5) { return l }
                    }
                } catch {}
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(8)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let fix else {
            PrayerWindowLog.add("widget mark \(name): no fresh location within 8 s · \(authText)\(note)")
            MarkLog.add("\(MarkLog.source) · \(name) → no fresh location within 8 s (\(authText)\(note)): it keeps none")
            return
        }
        if let vm = PrayerViewModel.current, let row = vm.todaysRow(named: name, startingAt: start) {
            vm.setLocation(fix, on: row)
        } else if let c = SharedStore.widgetContainer {
            let ctx = ModelContext(c)
            if let row = SharedStore.fetchPrayer(named: name, on: start, in: ctx) {
                row.setPrayerLocation(with: fix)
                try? ctx.save()
                g.set(true, forKey: SharedStore.widgetWroteStoreKey)
            }
        }
        PrayerWindowLog.add(String(format: "widget mark \(name): location ±%d m in %.1f s · \(authText)", Int(fix.horizontalAccuracy), Date().timeIntervalSince(t0)))
        MarkLog.add(String(format: "\(MarkLog.source) · \(name) → fresh location saved after the mark: ±%d m in %.1f s (\(authText))",
                           Int(fix.horizontalAccuracy), Date().timeIntervalSince(t0)))
    }

    // MARK: The plan

    struct Window { let name: String; let start: Date; let end: Date; var id: Int { Int(start.timeIntervalSince1970 / 60) } }

    /// Today's and tomorrow's windows still to come or under way, for the prayers that are on: Fajr → sunrise,
    /// Dhuhr → Asr, Asr → Maghrib, Maghrib → Isha, Isha → 11:59 PM.
    /// nil = unknown (no location yet, or the app group unreadable before the first unlock): then `plan` ends nothing.
    static func windows(now: Date = Date()) -> [Window]? {
        guard let coords = try? PrayerUtils.getUserCoordinates() else { return nil }
        let params = PrayerUtils.getCalculationParameters()
        let cal = Calendar.current
        var out: [Window] = []
        for d in 0...1 {
            guard let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)),
                  let t = try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params) else { continue }
            // 11:59 PM by the clock (minutes from midnight were an hour off on a DST day — Frank).
            let ishaEnd = cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? t.isha.addingTimeInterval(3 * 3600)
            out += [Window(name: "Fajr", start: t.fajr, end: t.sunrise), Window(name: "Dhuhr", start: t.dhuhr, end: t.asr),
                    Window(name: "Asr", start: t.asr, end: t.maghrib), Window(name: "Maghrib", start: t.maghrib, end: t.isha),
                    Window(name: "Isha", start: t.isha, end: ishaEnd)]
        }
        // Excused (Excused.swift): no card for a prayer she's excused from; a held one ends like one turned off.
        let excused = Excused.ranges
        return out.filter { $0.end > now && LiveActivityPrefs.isOn($0.name) && !Excused.covers(start: $0.start, end: $0.end, in: excused) }
            .sorted { $0.start < $1.start }
    }

    /// The card's look: its own setting (`LiveActivityLook`, Settings → Live Activities → Card look), apart from the app's.
    static func dark(for prayer: String) -> Bool? { LiveActivityLook.current.dark(for: prayer) }

    /// Prayed already? From the store (a card's or widget's mark goes there too; an unmark brings the card back).
    private static func done(_ w: Window) -> Bool {
        guard let c = SharedStore.widgetContainer else { return false }
        return SharedStore.fetchPrayer(named: w.name, on: w.start, in: ModelContext(c))?.isCompleted == true
    }

    /// End what shouldn't be showing, then add windows up to iOS's 5. Returns how many it added.
    /// A held card matching a wanted window: the same prayer on the same day, its start within 45 min — times that moved
    /// a little (a new place, method or madhab) keep their card rather than lose it from the background, where it can't be
    /// put back (Frank: a significant-change relaunch re-plans in the background within 10–25 s).
    private static func matches(_ st: PrayerWindowAttributes.ContentState, _ w: Window) -> Bool {
        // The same prayer of the same day: a prayer's next day is ~24 h on, so 6 h holds any move (a Hanafi Asr is ~1 h).
        st.label == w.name && abs(st.start.timeIntervalSince(w.start)) < 6 * 3600
    }
    /// Moved more than location jitter (a start crossing a minute boundary isn't a move — Frank).
    private static func moved(_ st: PrayerWindowAttributes.ContentState, _ w: Window) -> Bool {
        abs(st.start.timeIntervalSince(w.start)) > 120 || abs(st.end.timeIntervalSince(w.end)) > 120
    }

    #if DEBUG
    /// The Stop-adds-a-card test (Your Fajr Alarms → Testing): the furthest card ended, and plans held until `until`
    /// (the alarm) so nothing refills its slot before the Stop runs. Returns what it did, for the log.
    @MainActor static func freeOneSlotForTest(until: Date) async -> String {
        guard #available(iOS 26.0, *) else { return "needs iOS 26" }
        // holdPlans holds for 10 min from its stamp: stamp it so the hold ends as the alarm rings.
        UserDefaults.standard.set(until.timeIntervalSince1970 - 600, forKey: "la.debugHoldAt")
        let held = Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active }
        guard let last = held.max(by: { $0.content.state.start < $1.content.state.start }) else { return "no cards held" }
        let name = "\(last.content.state.label) \(last.content.state.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        await last.end(nil, dismissalPolicy: .immediate)
        PrayerWindowLog.add("Stop test: ended \(name) to free a slot; plans held until \(until.formatted(date: .omitted, time: .standard))")
        return "freed \(name) (\(held.count - 1) left)"
    }

    /// `-laNowAgo`: the stand-in alone — no planning for 10 min (the sim's real windows took the island; iOS relaunches
    /// shukr without the args, so it's kept in UserDefaults). `-laEndAll` alone lifts it.
    @MainActor static var holdPlans: Bool {
        get { Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "la.debugHoldAt") < 600 }
        set { UserDefaults.standard.set(newValue ? Date().timeIntervalSince1970 : 0, forKey: "la.debugHoldAt") }
    }
    #endif

    @MainActor @discardableResult static func plan(reason: String, retry: Bool = false) -> Int {
        guard #available(iOS 26.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return 0 }
        #if DEBUG
        if holdPlans { return 0 }
        #endif
        let now = Date()
        let bg = UIApplication.shared.applicationState == .background
        guard let want = windows(now: now) else {
            PrayerWindowLog.add("plan (\(reason)\(bg ? ", bg" : "")): no prayer times (no location / locked) — left as is")
            return 0
        }
        let all = Activity<PrayerWindowAttributes>.activities
        let liveStarts = all.filter { $0.activityState == .active && $0.content.state.markedAt == nil }.map(\.content.state.start)
        var ended: [String] = []
        var corrected: [String] = []
        /// One update per card, sent at the end: a correction and the last card's note together (two raced).
        var updates: [String: (Activity<PrayerWindowAttributes>, PrayerWindowAttributes.ContentState)] = [:]
        var endedIDs = Set<String>()
        var ending: [Task<Void, Never>] = []
        func end(_ a: Activity<PrayerWindowAttributes>, _ why: String) {
            ending.append(Task { await a.end(nil, dismissalPolicy: .immediate) })
            endedIDs.insert(a.id)
            ended.append("\(a.content.state.label) \(a.content.state.start.formatted(date: .omitted, time: .shortened)) (\(why))")
        }
        // iOS ends a card itself after 8 h (an Isha) but leaves it on the Lock Screen up to 4 h more: once its window is
        // over or another prayer began, clear it (it sat beside Fajr's — Frank).
        for a in all where a.activityState == .ended {
            let st = a.content.state
            if st.end <= now || liveStarts.contains(where: { $0 > st.start }) {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
        for a in all where a.activityState != .ended && a.activityState != .dismissed {
            let st = a.content.state
            if marking.contains(a.attributes.n) { continue }
            #if DEBUG
            if a.attributes.n < 1_000_000 { continue }   // a DEBUG stand-in (-laNowAgo): left alone
            #endif
            if let m = st.markedAt {
                // Marked: its 15 s with Photo / Tasbih; past that shukr was paused before it could end it.
                if now.timeIntervalSince(m) > 20 { end(a, "marked") }
                continue
            }
            if st.end <= now { end(a, "window over") }
            else if let latest = liveStarts.max(), st.start < latest, a.activityState != .pending { end(a, "next prayer began") }
            else if !LiveActivityPrefs.isOn(st.label) { end(a, "turned off") }
            else if !want.contains(where: { matches(st, $0) }) { end(a, "no such window now") }
            else if let w = want.first(where: { matches(st, $0) }), moved(st, w) || st.dark != dark(for: w.name) {
                if moved(st, w) && !bg && a.activityState == .pending {
                    end(a, "times moved")   // re-added below at the new time, its start alert with it
                } else {
                    // Live (or from the background, where a new one can't be asked for): corrected in place — the ring
                    // and the end time; a pending card's start alert keeps its old time until the next open (Frank).
                    var fixed = st
                    fixed.start = w.start; fixed.end = w.end; fixed.dark = dark(for: w.name)
                    updates[a.id] = (a, fixed)
                    corrected.append("\(st.label) to \(w.start.formatted(date: .omitted, time: .shortened))–\(w.end.formatted(date: .omitted, time: .shortened)) (kept)")
                }
            }
            else if a.activityState != .pending, done(Window(name: st.label, start: st.start, end: st.end)) { end(a, "prayed") }
        }
        var live = Activity<PrayerWindowAttributes>.activities.filter {
            !endedIDs.contains($0.id) && ($0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale)
        }
        // The earliest windows win: an unmarked prayer under way must show even when the 5 are full of later ones
        // (his unmark test). Only with shukr in front — from the background a freed slot would stay empty.
        let markedHeld = live.filter { $0.content.state.markedAt != nil }.count
        var shouldHold: [Int] = []
        for w in want where shouldHold.count < 5 - markedHeld {
            if w.start <= now && done(w) { continue }
            shouldHold.append(live.first(where: { matches($0.content.state, w) })?.attributes.n ?? w.id)
        }
        var room = bg ? 0 : shouldHold.filter { id in !live.contains { $0.attributes.n == id } }.count - (5 - live.count)
        for a in live.sorted(by: { $0.content.state.start > $1.content.state.start })
            where a.activityState == .pending && !shouldHold.contains(a.attributes.n) {
            guard room > 0 else { break }
            room -= 1
            end(a, "making room")
        }
        live = live.filter { !endedIDs.contains($0.id) }
        var held = Set(live.map(\.attributes.n))
        var added: [String] = []
        var requested: [Activity<PrayerWindowAttributes>] = []
        var failed: String?
        for w in want where !held.contains(w.id) && !live.contains(where: { matches($0.content.state, w) }) {
            guard held.count < 5 else { break }
            if w.start <= now && done(w) { continue }   // under way but already prayed
            let state = PrayerWindowAttributes.ContentState(label: w.name, start: w.start, end: w.end, symbol: prayerIcon(for: w.name),
                                                            dark: dark(for: w.name))
            do {
                if w.start > now {
                    requested.append(try Activity.request(attributes: PrayerWindowAttributes(n: w.id), content: .init(state: state, staleDate: w.end),
                                             pushType: nil, style: .standard,
                                             alertConfiguration: AlertConfiguration(title: "\(w.name) has started",
                                                                                    body: "ends \(w.end.formatted(date: .omitted, time: .shortened))", sound: .default),
                                             start: w.start))
                } else {
                    requested.append(try Activity.request(attributes: PrayerWindowAttributes(n: w.id), content: .init(state: state, staleDate: w.end), pushType: nil))
                }
                held.insert(w.id)
                added.append("\(w.name) \(w.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
            } catch {
                failed = "\(w.name): \(error)"
                break
            }
        }
        // The last card queued says so (owner): nothing follows it until shukr opens and plans again — then the note moves
        // to the new last one, corrected in place.
        var holding = Activity<PrayerWindowAttributes>.activities.filter {
            !endedIDs.contains($0.id) && $0.content.state.markedAt == nil
                && ($0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale)
        }
        for r in requested where !holding.contains(where: { $0.id == r.id }) { holding.append(r) }
        let lastStart = holding.map { (updates[$0.id]?.1 ?? $0.content.state).start }.max()
        var lastLabel: String?
        for a in holding {
            var st = updates[a.id]?.1 ?? a.content.state
            let isLast = st.start == lastStart
            if isLast { lastLabel = "\(st.label) \(st.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" }
            if (st.last ?? false) != isLast {
                st.last = isLast ? true : nil
                if isLast { st.toppedUp = nil }   // the last again: the ↻ comes back
                updates[a.id] = (a, st)
            }
        }
        for (_, u) in updates { Task { await u.0.update(ActivityContent(state: u.1, staleDate: u.1.end)) } }
        var line = "plan (\(reason)\(bg ? ", bg" : "")): holding \(held.count)"
        if let lastLabel { line += " · last \(lastLabel)" }
        if !ended.isEmpty { line += " · ended " + ended.joined(separator: ", ") }
        if !corrected.isEmpty { line += " · corrected " + corrected.joined(separator: ", ") }
        if !added.isEmpty { line += " · added " + added.joined(separator: ", ") }
        if let failed { line += " · couldn't add \(failed)" }
        if want.isEmpty { line += " · no windows (no location, or all off)" }
        PrayerWindowLog.add(line)
        // An end hadn't landed yet when it asked (iOS still counted 5 — his first unmark): once they have, once more.
        if let failed, failed.contains("targetMaximumExceeded"), !ending.isEmpty, !retry {
            Task { @MainActor in
                for e in ending { await e.value }
                plan(reason: "\(reason) · after the ends landed", retry: true)
            }
        }
        return added.count
    }

    /// Settings' status: how many windows are held and the next one.
    /// The cards iOS holds, the next to start, and the last one's start (Settings' "Scheduled through …").
    @MainActor static func status() -> (held: Int, next: Date?, through: Date?) {
        guard #available(iOS 26.0, *) else { return (0, nil, nil) }
        let held = Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale }
        let starts = held.map(\.content.state.start)
        return (held.count, starts.filter { $0 > Date() }.min(), starts.max())
    }

    #if DEBUG
    /// `-laEndAll` ends every card; `-laNowAgo N [-laLength M]` puts up a stand-in window that began N min ago (left alone
    /// by the planner; testIslandLook; `-laLast` gives it the last card's note); `-laMarkNow` marks it; `-laMarkLive` marks whatever window is live. True = handled.
    @MainActor private static func debugLaunch() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ k: String) -> Double? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } }
        if let g = arg("-laGate") { UserDefaults(suiteName: SharedStore.appGroup)?.set(Int(g), forKey: LAGate.styleKey) }   // 0 wipe · 1 flip · 2 soft
        // `-laStartIn N`: the wake test (AutoTopUp) — every card ended, plans held 10 min, the 3 h top-up limit cleared,
        // then one card scheduled the real way (`start:`) N s out. Background or quit shukr; live-activities.log and
        // topups.log say whether its start woke shukr and topped up.
        if let n = arg("-laStartIn") {
            holdPlans = true
            UserDefaults(suiteName: SharedStore.appGroup)?.set(0, forKey: AutoTopUp.key)
            UserDefaults.standard.set(Date().timeIntervalSince1970 + 600, forKey: "autoTopUp.noLimitUntil")
            Task { @MainActor in
                for a in Activity<PrayerWindowAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                let start = Date().addingTimeInterval(n), end = start.addingTimeInterval(3600)
                let state = PrayerWindowAttributes.ContentState(label: "Asr", start: start, end: end, symbol: prayerIcon(for: "Asr"))
                do {
                    if #available(iOS 26.0, *) {
                        _ = try Activity.request(attributes: PrayerWindowAttributes(n: 98), content: .init(state: state, staleDate: end),
                                                 pushType: nil, style: .standard,
                                                 alertConfiguration: AlertConfiguration(title: "Asr has started", body: "wake test", sound: .default),
                                                 start: start)
                    }
                    PrayerWindowLog.add("wake test: a card set to start \(start.formatted(date: .omitted, time: .standard))")
                } catch {
                    PrayerWindowLog.add("wake test: couldn't schedule — \(error)")
                }
            }
            return true
        }
        guard args.contains("-laEndAll") || args.contains("-laNowAgo") || args.contains("-laMarkLive") else { return false }
        if args.contains("-laNowAgo") || args.contains("-laEndAll") { holdPlans = args.contains("-laNowAgo") }   // at once: a plan from the first foreground beat it
        Task { @MainActor in
            if args.contains("-laEndAll") {
                for a in Activity<PrayerWindowAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                PrayerWindowLog.add("ended all")
            }
            if let ago = arg("-laNowAgo") {
                let start = Date().addingTimeInterval(-ago * 60), end = start.addingTimeInterval((arg("-laLength") ?? 90) * 60)
                _ = try? Activity.request(attributes: PrayerWindowAttributes(n: 99),
                                          content: .init(state: .init(label: "Asr", start: start, end: end, symbol: prayerIcon(for: "Asr"),
                                                                      dark: dark(for: "Asr"),   // the card look, as a real card's
                                                                      last: args.contains("-laLast") ? true : nil,
                                                                      toppedUp: args.contains("-laToppedUp") ? "4" : nil), staleDate: end),
                                          pushType: nil)
                if args.contains("-laMarkNow") { try? await Task.sleep(for: .seconds(1)); await mark(99) }
                return
            }
            plan(reason: "launch")
            if args.contains("-laMarkLive") {
                try? await Task.sleep(for: .seconds(2))
                if let live = Activity<PrayerWindowAttributes>.activities.first(where: { $0.activityState == .active && $0.content.state.markedAt == nil }) {
                    await mark(live.attributes.n)
                }
            }
        }
        return true
    }
    #endif
}
