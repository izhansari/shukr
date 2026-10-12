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
        guard #available(iOS 26.0, *) else { return }
        let state = UIApplication.shared.applicationState
        var line = "launch · " + (state == .background ? "background" : state == .active ? "active" : "inactive")
        line += " · enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)"
        if !UIApplication.shared.isProtectedDataAvailable { line += " · LOCKED" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { line += " · LOW POWER" }
        PrayerWindowLog.add(line)
        PrayerWindowHooks.mark = { n in await mark(n) }
        PrayerWindowHooks.open = { n, what in await open(n, what) }
        PrayerWindowHooks.widgetMark = { name, start, end in await widgetMark(name, start, end) }
        for activity in Activity<PrayerWindowAttributes>.activities { observe(activity) }
        Task { @MainActor in
            for await activity in Activity<PrayerWindowAttributes>.activityUpdates { observe(activity) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in plan(reason: "background") }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in plan(reason: "foreground") }
        }
        #if DEBUG
        if debugLaunch() { return }
        #endif
        Task { @MainActor in plan(reason: "launch") }
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
                if st == .active { plan(reason: "\(activity.content.state.label) started") }
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
        return out.filter { $0.end > now && LiveActivityPrefs.isOn($0.name) }.sorted { $0.start < $1.start }
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
                    Task { await a.update(ActivityContent(state: fixed, staleDate: w.end)) }
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
        var failed: String?
        for w in want where !held.contains(w.id) && !live.contains(where: { matches($0.content.state, w) }) {
            guard held.count < 5 else { break }
            if w.start <= now && done(w) { continue }   // under way but already prayed
            let state = PrayerWindowAttributes.ContentState(label: w.name, start: w.start, end: w.end, symbol: prayerIcon(for: w.name),
                                                            dark: dark(for: w.name))
            do {
                if w.start > now {
                    _ = try Activity.request(attributes: PrayerWindowAttributes(n: w.id), content: .init(state: state, staleDate: w.end),
                                             pushType: nil, style: .standard,
                                             alertConfiguration: AlertConfiguration(title: "\(w.name) has started",
                                                                                    body: "ends \(w.end.formatted(date: .omitted, time: .shortened))", sound: .default),
                                             start: w.start)
                } else {
                    _ = try Activity.request(attributes: PrayerWindowAttributes(n: w.id), content: .init(state: state, staleDate: w.end), pushType: nil)
                }
                held.insert(w.id)
                added.append("\(w.name) \(w.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
            } catch {
                failed = "\(w.name): \(error)"
                break
            }
        }
        var line = "plan (\(reason)\(bg ? ", bg" : "")): holding \(held.count)"
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
    @MainActor static func status() -> (held: Int, next: Date?) {
        guard #available(iOS 26.0, *) else { return (0, nil) }
        let held = Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active || $0.activityState == .stale }
        return (held.count, held.map(\.content.state.start).filter { $0 > Date() }.min())
    }

    #if DEBUG
    /// `-laEndAll` ends every card; `-laNowAgo N [-laLength M]` puts up a stand-in window that began N min ago (left alone
    /// by the planner; testIslandLook); `-laMarkNow` marks it; `-laMarkLive` marks whatever window is live. True = handled.
    @MainActor private static func debugLaunch() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ k: String) -> Double? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } }
        if let g = arg("-laGate") { UserDefaults(suiteName: SharedStore.appGroup)?.set(Int(g), forKey: LAGate.styleKey) }   // 0 wipe · 1 flip · 2 soft
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
                                          content: .init(state: .init(label: "Asr", start: start, end: end, symbol: prayerIcon(for: "Asr")), staleDate: end),
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
