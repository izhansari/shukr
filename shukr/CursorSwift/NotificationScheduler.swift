//
//  NotificationScheduler.swift
//  shukr
//
//  Every scheduled local notification goes through here (2026-09-27, notes #10). iOS keeps at
//  most 64 pending per app, so this owns that budget (plan v2, owner 2026-10-12, decisions notif-plan-review A /
//  notif-plan-tradeoff C; board/brief-notif-plan-v2.md). Every request costs one slot, so filling them in order of
//  value is the best use of the 64 (no packing puzzle) — the order is the algorithm (`Tier`):
//  - today's and tomorrow's starts and today's zikr reminders, then a week of starts (the runway's floor),
//  - the 30-minutes-left, then the halfway, for the next 3 prayer days ("full days"),
//  - tomorrow's zikr reminders (zikr reminders never go further: they'd crowd out the prayers),
//  - starts out to the runway — 2 × the longest gap between opening shukr lately, 7 to 14 days — then more full
//    days within it, then starts as far as the slots go (30 days).
//  Then the warnings, each moved on by every re-plan, so someone who opens shukr never sees them: easing off
//  (the evening of the last full day), the heads-up (two days before the last start) and the last one.
//  Completed prayers are skipped.
//  - Ids carry the day ("2026-09-27.FajrStart", `PrayerNotificationID`), and only ids this
//    scheduler owns are removed — never `removeAllPending…` — so "nudge me in 10 min" snoozes
//    (and anything else) survive a reschedule.
//  - Earlier days' *delivered* prayer notifications are cleared, which keeps Notification Center
//    as before, when each day's "AsrStart" replaced yesterday's.
//  - A background app refresh (`refreshTaskID`) tops the days up while the app isn't opened.
//
//  Why: since the prayer day turns at Fajr, only "today" was scheduled — before Fajr that's
//  yesterday (all past), after Fajr its Start is already past — so "Fajr Time" never went out
//  (confirmed 2026-09-27 in the sim: at 7:27 PM only tonight's Maghrib / Isha were pending).
//
//  The notifications themselves look exactly as they did (owner): same titles, subtitles, sound,
//  time-sensitive level, "Round1_Snooze" actions and userInfo.
//
//  Zikr reminders (notes #11) add their items to `plan(…)` and share the budget.
//

import Foundation
import UIKit
import UserNotifications
import SwiftData
import BackgroundTasks
import Adhan

@MainActor
enum NotificationScheduler {
    static let refreshTaskID = "com.betternorms.shukr.refresh"
    /// iOS's cap on pending requests per app.
    static let limit = 64
    /// Slots left for things scheduled outside the scheduler (snoozes).
    static let spare = 4
    /// The runway's floor: every prayer start of the next week comes before any later nudge.
    static let daysAhead = 7
    /// The runway's ceiling, for someone who opens shukr rarely (`runwayDays`).
    static let runwayMax = 14
    /// Before shukr knows how often it's opened (owner, notif-plan-tradeoff C: 3 full days, starts to about day 10).
    static let runwayNew = 10
    /// Starts as far as the 64 allow (owner, reminders-runway A: fewer a day = a longer runway).
    static let maxDaysAhead = 30

    /// One pending notification the scheduler wants. Lower `priority` wins when the budget is tight.
    struct Item {
        let id: String
        let date: Date
        let priority: Int
        let content: UNNotificationContent
    }

    /// Does the scheduler own this id (so a reschedule may replace / remove it)?
    static func owns(_ id: String) -> Bool {
        PrayerNotificationID.parse(id) != nil || ZikrReminders.owns(id) || id.hasPrefix(keepAlivePrefix)
    }

    /// The last-resort reminder (owner, 2026-09-28): one notification just after the last start that
    /// fits, "Open shukr to keep your prayer reminders coming". Every re-plan moves it later (a new id,
    /// the old one removed), so it only ever fires if shukr wasn't opened or refreshed in time.
    static let keepAlivePrefix = "keepalive."
    /// The two earlier warnings share the prefix (owned, cleared once delivered, kept out of "scheduled through").
    static let headsUpPrefix = keepAlivePrefix + "ahead."
    static let easeOffPrefix = keepAlivePrefix + "ease."
    /// The last one (not the heads-up or easing off): the Settings row's "reminder to open shukr" date.
    static func isLastKeepAlive(_ id: String) -> Bool {
        id.hasPrefix(keepAlivePrefix) && !id.hasPrefix(headsUpPrefix) && !id.hasPrefix(easeOffPrefix)
    }
    static func keepAliveItem(after last: Date) -> Item {
        let date = last.addingTimeInterval(20 * 60)
        let content = warning(title: "Open shukr to keep your prayer reminders coming",
                              body: "Your scheduled reminders end here. Opening shukr lines up the next days.")
        return Item(id: keepAlivePrefix + PrayerNotificationID.dayKey(date), date: date, priority: 0, content: content)
    }
    /// Two days before the last start (owner: one warning at the very end was "kind of risky").
    static func headsUpItem(at date: Date, lastStart: Date) -> Item {
        let day = lastStart.formatted(.dateTime.weekday(.wide))
        let content = warning(title: "Your prayer reminders run until \(day)",
                              body: "Open shukr any time before then to keep them coming.")
        return Item(id: headsUpPrefix + PrayerNotificationID.dayKey(date), date: date, priority: 0, content: content)
    }
    /// The evening of the last full day (owner: "let the user know … we don't wanna bombard you").
    static func easeOffItem(at date: Date) -> Item {
        let content = warning(title: "Easing off your reminders",
                              body: "You haven't opened shukr in a few days, so from tomorrow we'll just remind you when each prayer starts. Open shukr to bring back your halfway and 30-minute reminders.")
        return Item(id: easeOffPrefix + PrayerNotificationID.dayKey(date), date: date, priority: 0, content: content)
    }
    /// The warnings come through a Focus and the Scheduled Summary like the prayers (they're what keeps them coming).
    private static func warning(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        return content
    }

    // MARK: The runway: how often shukr is opened

    /// When shukr was last opened (brought to the front), newest last; at most `opensKept`.
    static let opensKey = "notifications.appOpens"
    static let opensKept = 12
    /// Opening shukr (the app's didBecomeActive): kept once an hour at most.
    static func noteOpen(now: Date = Date()) {
        var opens = UserDefaults.standard.array(forKey: opensKey) as? [Double] ?? []
        if let last = opens.last, now.timeIntervalSince1970 - last < 3600 { return }
        opens.append(now.timeIntervalSince1970)
        UserDefaults.standard.set(Array(opens.suffix(opensKept)), forKey: opensKey)
    }
    /// How many days of starts to make sure of: twice the longest gap between opens in the last 30 days (now counts
    /// as an open), 7 to 14. Someone who opens shukr daily gets 7 and the rest goes to full days; someone who comes back
    /// weekly gets 14 before any extra full day. Until there are three opens: `runwayNew`.
    static func runwayDays(now: Date = Date()) -> Int {
        #if DEBUG
        let forced = UserDefaults.standard.integer(forKey: "runwayDays")   // `-runwayDays N`
        if forced > 0 { return forced }
        #endif
        let monthAgo = now.timeIntervalSince1970 - 30 * 86_400
        let opens = (UserDefaults.standard.array(forKey: opensKey) as? [Double] ?? []).filter { $0 > monthAgo }
            + [now.timeIntervalSince1970]
        guard opens.count >= 3 else { return runwayNew }
        let longest = zip(opens.dropFirst(), opens).map { $0 - $1 }.max() ?? 0
        return min(max(daysAhead, Int((2 * longest / 86_400).rounded(.up))), runwayMax)
    }

    /// From outside the app's own views (a notification action woke it in the background): re-plans with the app's
    /// store. Set by shukrApp's init.
    static var appContainer: ModelContainer?
    static func topUp(reason: String) {
        guard let container = appContainer else { return }
        reschedule(context: container.mainContext, reason: reason)
    }

    // MARK: Rescheduling

    private static var chain: Task<Void, Never>?

    /// Re-plan everything. Calls queue up behind each other (the app calls this on open, on a
    /// location / settings change and from the refresh timer).
    /// `todayOverride`: the dev "test prayer times" for the current prayer day.
    static func reschedule(context: ModelContext,
                           todayOverride: [String: (start: Date, end: Date, window: TimeInterval)]? = nil,
                           reason: String = "") {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await run(context: context, todayOverride: todayOverride, reason: reason)
        }
    }

    /// Awaitable, for the background refresh.
    static func rescheduleNow(context: ModelContext, reason: String) async {
        reschedule(context: context, reason: reason)
        await chain?.value
    }

    private static func run(context: ModelContext,
                            todayOverride: [String: (start: Date, end: Date, window: TimeInterval)]?,
                            reason: String) async {
        // Finishes even if the app is sent to the background mid-plan (audit B12): a plan cut off between its
        // removes and its adds left a gap in the week.
        let assertion = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "shukr.notifications") }
        await runPlan(context: context, todayOverride: todayOverride, reason: reason)
        if assertion != .invalid { await MainActor.run { UIApplication.shared.endBackgroundTask(assertion) } }
    }

    private static func runPlan(context: ModelContext,
                                todayOverride: [String: (start: Date, end: Date, window: TimeInterval)]?,
                                reason: String) async {
        let center = UNUserNotificationCenter.current()
        let items = plan(context: context, todayOverride: todayOverride)

        let pending = await center.pendingNotificationRequests()
        let ownedPending = pending.filter { owns($0.identifier) }
        let others = pending.count - ownedPending.count
        let budget = max(limit - others - spare, 0)
        let chosen = choose(items, budget: budget)

        // Only what changed (2026-09-27 review): while moving, the app re-plans every 500 m / 30 s,
        // and removing + re-adding ~55 requests each time was wasted work. A request is "the same"
        // when its id, minute and wording match.
        let have = Dictionary(ownedPending.map { ($0.identifier, signature($0.content, trigger: $0.trigger)) },
                              uniquingKeysWith: { a, _ in a })
        let want = Dictionary(chosen.map { ($0.id, (item: $0, sig: signature($0.content, date: $0.date))) },
                              uniquingKeysWith: { a, _ in a })
        let stalePending = have.filter { id, sig in want[id]?.sig != sig }.map(\.key)
        let toAdd = want.values.filter { have[$0.item.id] != $0.sig }.map(\.item)
        // What's gone for good is removed first — it isn't re-added, so no gap, and the pending count never passes 64
        // (iOS keeps the soonest 64 and drops the rest silently; Bradley's review). A changed id is never removed:
        // its add replaces it, so a suspend mid-plan can't leave that reminder missing (audit B12).
        let gone = stalePending.filter { want[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }
        for item in toAdd {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: item.id, content: item.content, trigger: trigger))
            } catch {
                print("❌ notification \(item.id): \(error.localizedDescription)")
            }
        }

        // Earlier days' delivered prayer notifications (and the undated ones of older builds).
        let todayKey = PrayerNotificationID.dayKey(PrayerDay.date())
        let delivered = await center.deliveredNotifications()
        let dayStart = PrayerDay.start()
        let stale = delivered.map(\.request.identifier).filter { id in
            // A delivered last-resort reminder has done its job: this plan has just replaced it.
            if id.hasPrefix(keepAlivePrefix) { return true }
            // Zikr reminders (and their "later" ones) from earlier days too (2026-09-27 review).
            if ZikrReminders.isStaleDelivered(id, todayKey: todayKey, dayStart: dayStart) { return true }
            guard let parsed = PrayerNotificationID.parse(id) else { return false }
            return (parsed.dayKey ?? "") < todayKey
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }

        scheduleBackgroundRefresh()
        // Settings' status row and Your reminders read what's scheduled: tell them it just changed
        // (a refresh on activation can run before this re-plan finishes).
        // The AlarmKit Fajr alarm tops up with every run (launch, coming back, background refresh,
        // notification actions, settings) — a diff, so nothing changes when nothing's due.
        await MainActor.run { FajrAlarms.watch() }   // a log line when one starts ringing while shukr runs
        await FajrAlarms.plan(reason: reason.isEmpty ? "reschedule" : reason)
        await NotificationHealth.shared.refresh()
        if !stalePending.isEmpty || !toAdd.isEmpty || !stale.isEmpty {
            print("🔔 notifications (\(reason)): \(chosen.count) of \(items.count) planned\(chosen.contains { $0.id.hasPrefix(keepAlivePrefix) } ? " (incl. the last-resort reminder)" : "") — removed \(stalePending.count), added \(toAdd.count), \(others) other pending, cleared \(stale.count) delivered")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-logPendingNotifs") {
            // The plan by prayer day, whether or not iOS took it (the simulator often isn't allowed notifications).
            var byDay: [String: [String]] = [:]
            for item in chosen {
                let key = PrayerNotificationID.parse(item.id)?.dayKey ?? PrayerNotificationID.dayKey(PrayerDay.date(for: item.date))
                let p = PrayerNotificationID.parse(item.id)
                byDay[key, default: []].append(p.map { "\($0.prayer.prefix(2))\($0.kind.prefix(1))" } ?? (item.id.hasPrefix(headsUpPrefix) ? "HEADSUP" : item.id.hasPrefix(easeOffPrefix) ? "EASEOFF" : item.id.hasPrefix(keepAlivePrefix) ? "LAST" : "zikr"))
            }
            print("PLAN runway \(runwayDays()) · \(chosen.count) chosen of \(items.count) · budget \(budget)\n" + byDay.keys.sorted().map { "  \($0): " + byDay[$0]!.joined(separator: " ") }.joined(separator: "\n"))
            let deliveredKeepAlives = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(keepAlivePrefix) }.count
            print("🔔 last-resort reminders: cleared \(stale.filter { $0.hasPrefix(keepAlivePrefix) }.count) delivered this run, \(deliveredKeepAlives) left")
            let now = await center.pendingNotificationRequests()
            let lines = now.compactMap { r -> (Date, String)? in
                if let d = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() { return (d, r.identifier) }
                if let t = r.trigger as? UNTimeIntervalNotificationTrigger, let d = t.nextTriggerDate() { return (d, r.identifier) }
                return nil
            }.sorted { $0.0 < $1.0 }.map { "  \($0.0.formatted(date: .abbreviated, time: .shortened))  \($0.1)" }
            print("PENDINGNOTIFS \(now.count)\n" + lines.joined(separator: "\n"))
        }
        #endif
    }

    /// The best `budget` requests: the plan's items in their tiers' order, then the warnings for where that leaves the
    /// prayers. Room is kept for the three warnings first; whatever they don't need goes back to the next items.
    static func choose(_ items: [Item], budget: Int) -> [Item] {
        let sorted = items.sorted { ($0.priority, $0.date) < ($1.priority, $1.date) }
        let held = budget >= 6 ? 3 : budget >= 2 ? 1 : 0
        var chosen = Array(sorted.prefix(max(budget - held, 0)))
        var warn = warnings(for: chosen, room: held)
        let more = budget - chosen.count - warn.count
        if more > 0 {
            chosen += sorted.dropFirst(chosen.count).prefix(more)
            warn = Array(warnings(for: chosen, room: held).prefix(max(budget - chosen.count, 0)))
        }
        return chosen + warn
    }

    /// The warnings for a chosen plan (prayer starts only: zikr reminders alone get none). The last one always; the
    /// heads-up when the last start is more than two days out; easing off when a later day is starts-only although
    /// some prayer is set to nudge. `room` caps them, most important first.
    static func warnings(for chosen: [Item], room: Int) -> [Item] {
        guard room > 0 else { return [] }
        let parsed = chosen.compactMap { item in PrayerNotificationID.parse(item.id).map { (item, $0) } }
        guard let lastStart = parsed.filter({ $0.1.kind == "Start" }).map(\.0.date).max() else { return [] }
        var list = [keepAliveItem(after: lastStart)]
        let now = Date(), cal = Calendar.current
        // Heads-up: two days before the last start's day, 20 min after that day's Dhuhr (12:30 without times).
        var headsUp: Item?
        if let day = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: PrayerDay.date(for: lastStart))) {
            let noon = cal.date(bySettingHour: 12, minute: 30, second: 0, of: day) ?? day
            let at = windows(for: day)?["Dhuhr"]?.start.addingTimeInterval(20 * 60) ?? noon
            if at > now.addingTimeInterval(3600) { headsUp = headsUpItem(at: at, lastStart: lastStart) }
        }
        // Easing off: the last day with any nudge, if a starts-only day follows it and some prayer is set to nudge.
        var easeOff: Item?
        let anyNudges = PrayerNotificationID.prayers.contains { settings($0).notify && settings($0).nudges }
        let nudges = parsed.filter { $0.1.kind != "Start" }
        if anyNudges, let last = nudges.max(by: { $0.0.date < $1.0.date }), let lastKey = last.1.dayKey,
           parsed.contains(where: { $0.1.kind == "Start" && ($0.1.dayKey ?? "") > lastKey }) {
            let late = cal.date(bySettingHour: 21, minute: 30, second: 0, of: last.0.date) ?? last.0.date
            let at = max(min(last.0.date.addingTimeInterval(20 * 60), late), now.addingTimeInterval(60))
            // Within a day of the heads-up, the heads-up says it (one warning, not two).
            if abs(at.timeIntervalSince(headsUp?.date ?? .distantPast)) > 30 * 3600 { easeOff = easeOffItem(at: at) }
        }
        list += [easeOff, headsUp].compactMap { $0 }
        return Array(list.prefix(room))
    }

    /// "yyyy-MM-dd HH:mm|title|subtitle|body" — what makes two requests the same.
    private static func signature(_ c: UNNotificationContent, date: Date?) -> String {
        let minute = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        let when = minute.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0) \($0.hour ?? 0):\($0.minute ?? 0)" } ?? "?"
        return "\(when)|\(c.title)|\(c.subtitle)|\(c.body)"
    }
    private static func signature(_ c: UNNotificationContent, trigger: UNNotificationTrigger?) -> String {
        signature(c, date: (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
    }

    // MARK: The plan

    /// Everything the scheduler would like pending, before the budget.
    static func plan(context: ModelContext,
                     todayOverride: [String: (start: Date, end: Date, window: TimeInterval)]? = nil) -> [Item] {
        let now = Date()
        // Zikr reminders for today and tomorrow only (owner: four tasks a day for a week would be half the 64); later
        // days are added as they come closer.
        let todayKey = PrayerNotificationID.dayKey(PrayerDay.date(for: now))
        let zikr = ZikrReminders.items(context: context, now: now, horizon: now.addingTimeInterval(48 * 3600)) { prayer, day in
            windows(for: day)?[prayer]?.start
        }.map { item in
            Item(id: item.id, date: item.date,
                 priority: PrayerNotificationID.dayKey(PrayerDay.date(for: item.date)) == todayKey ? Tier.now : Tier.zikrTomorrow,
                 content: item.content)
        }
        return prayerItems(context: context, todayOverride: todayOverride) + zikr
    }

    /// The plan's order (lower first). Within a tier, sooner first — so full days and the runway grow without gaps.
    enum Tier {
        static let now = 0            // today's and tomorrow's starts, today's zikr reminders
        static let week = 1           // the week's other starts (the runway's floor)
        static let fullEnd = 2        // 30 minutes left, the next `nudgeDaysAhead` prayer days
        static let fullMid = 3        // halfway, the same days
        static let zikrTomorrow = 4
        static let runway = 5         // starts out to `runwayDays`
        static let moreEnd = 6        // more full days, within the runway
        static let moreMid = 7
        static let further = 8        // starts as far as the slots go
    }

    private static let defaults = UserDefaults.standard
    /// How many prayer days still ahead are sure of their nudges (halfway, 30 min left; owner, notif-plan-tradeoff C:
    /// "what if we made it 3 full days"); later days get them only with slots to spare within the runway.
    static let nudgeDaysAhead = 3
    /// Settings → Notifications (standard defaults; unset → `NotificationDefaults`, like every view).
    static func settings(_ prayer: String) -> (notify: Bool, nudges: Bool) {
        let key = prayer.lowercased()
        let notify = defaults.object(forKey: "\(key)Notif") as? Bool ?? NotificationDefaults.notify(prayer)
        let nudges = defaults.object(forKey: "\(key)Nudges") as? Bool ?? NotificationDefaults.nudges(prayer)
        return (notify, nudges)
    }

    /// Prayer windows for the prayer day starting on `day`'s calendar date.
    /// A day's prayer windows from the saved location (also the reminders page's "next" times).
    static func windows(for day: Date) -> [String: (start: Date, end: Date, window: TimeInterval)]? {
        guard let coordinates = try? PrayerUtils.getUserCoordinates() else { return nil }
        let params = PrayerUtils.getCalculationParameters()
        guard let times = try? PrayerUtils.getPrayerTimes(for: day, coordinates: coordinates, params: params) else { return nil }
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day)
        let nextFajr = next.flatMap { try? PrayerUtils.getPrayerTimes(for: $0, coordinates: coordinates, params: params).fajr }
        let ishaEnd = PrayerDay.ishaEnd(on: day, ishaStart: times.isha, nextFajr: nextFajr)
        func w(_ a: Date, _ b: Date) -> (start: Date, end: Date, window: TimeInterval) { (a, b, b.timeIntervalSince(a)) }
        return ["Fajr": w(times.fajr, times.sunrise), "Dhuhr": w(times.dhuhr, times.asr),
                "Asr": w(times.asr, times.maghrib), "Maghrib": w(times.maghrib, times.isha),
                "Isha": w(times.isha, ishaEnd)]
    }

    private static func prayerItems(context: ModelContext,
                                    todayOverride: [String: (start: Date, end: Date, window: TimeInterval)]?) -> [Item] {
        let now = Date()
        let cal = Calendar.current
        let firstDay = cal.startOfDay(for: PrayerDay.date(for: now))
        let horizon = now.addingTimeInterval(TimeInterval(maxDaysAhead) * 86_400)
        let runway = runwayDays(now: now)

        // Which prayers are already prayed, over the days covered.
        let lastDay = cal.date(byAdding: .day, value: maxDaysAhead + 1, to: firstDay) ?? firstDay
        let rangeStart = firstDay, rangeEnd = lastDay.addingTimeInterval(6 * 3600)   // + a post-midnight Isha (2.8.0)
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted && $0.startTime >= rangeStart && $0.startTime < rangeEnd })
        let done = Set(((try? context.fetch(descriptor)) ?? []).map { $0.dayKey + $0.name })   // by prayer day

        var items: [Item] = []
        var index = 0   // prayer days still ahead, counted: 0 = the current one
        for offset in 0...(maxDaysAhead + 1) {
            guard let day = cal.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let dayWindows = offset == 0 ? (todayOverride ?? windows(for: day)) : windows(for: day)
            guard let dayWindows, let fajr = dayWindows["Fajr"]?.start, fajr < horizon else { continue }
            let stillAhead = dayWindows.values.contains { $0.end > now }
            guard stillAhead else { continue }
            let i = index
            index += 1
            let full = i < nudgeDaysAhead
            for name in PrayerNotificationID.prayers {
                guard let window = dayWindows[name], !done.contains(PrayerNotificationID.dayKey(day) + name) else { continue }
                let s = settings(name)
                guard s.notify else { continue }
                // Nudges only on days whose starts the runway is sure of (a nudge without its start would be odd).
                let kinds = s.nudges && i < runway ? ["Start", "Mid", "End"] : ["Start"]
                for kind in kinds {
                    guard let (date, content) = prayerNotification(kind, prayer: name, window: window),
                          date > now, date < horizon else { continue }
                    let priority = switch kind {
                    case "Start": i < 2 ? Tier.now : i < daysAhead ? Tier.week : i < runway ? Tier.runway : Tier.further
                    case "End": full ? Tier.fullEnd : Tier.moreEnd
                    default: full ? Tier.fullMid : Tier.moreMid
                    }
                    items.append(Item(id: PrayerNotificationID.make(day: day, prayer: name, kind: kind),
                                      date: date, priority: priority, content: content))
                }
            }
        }
        return items
    }

    /// The prayer notifications (owner, 2026-10-01, decision prayer-notif-wording — don't change the wording
    /// without him): the prayer and its colour, "Pray by 6:48 PM" always first, a second line that changes.
    /// 🟢 at the start · 🟡 halfway through the window (owner, 2026-10-03: "i liked it better with the halfway
    /// notifications instead of 30 min in" — it was 30 min in for a day) · 🔴 with 30 min left (owner: kept there,
    /// though the ring turns red earlier). A window under 90 min gets no 🟡 (halfway would land within 15 min of the 🔴).
    static func prayerNotification(_ kind: String, prayer: String,
                                   window: (start: Date, end: Date, window: TimeInterval)) -> (Date, UNNotificationContent)? {
        let endTime = window.end
        let date: Date
        let content = UNMutableNotificationContent()
        content.subtitle = "Pray by \(shortTimePM(endTime))"
        switch kind {
        case "Start":
            date = window.start
            content.title = "\(prayer) 🟢"
            content.body = "\(prayer) has started"
        case "Mid":   // halfway through the window
            let length = endTime.timeIntervalSince(window.start)
            // At least 15 min before the 🔴 (30 min before the end): length / 2 ≤ length − 45 min, a window of 90 min+.
            guard length >= Self.halfwayMinimumWindow else { return nil }
            date = window.start.addingTimeInterval(length / 2)
            content.title = "\(prayer) 🟡"
            content.body = "Halfway through \(prayer)"
        case "End":
            date = endTime.addingTimeInterval(-30 * 60)
            content.title = "\(prayer) 🔴"
            content.body = "Only 30 minutes left"
        default:
            return nil
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "Round1_Snooze"
        // "I already prayed" (NotificationDelegate) needs to know which prayer this is.
        content.userInfo = [
            "prayerName": prayer,
            "prayerStart": window.start.timeIntervalSince1970,
            "prayerEnd": window.end.timeIntervalSince1970,
        ]
        return (date, content)
    }

    /// The shortest window that gets a halfway 🟡: halfway lands at least 15 min before the 🔴 (30 min before the end).
    static let halfwayMinimumWindow: TimeInterval = 90 * 60

    // MARK: Background top-up

    /// Ask iOS to wake the app in a few hours to top the days up (best effort; the days already
    /// scheduled cover the gaps). Handled by `.backgroundTask(.appRefresh(refreshTaskID))`.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if !targetEnvironment(simulator)
            print("❌ background refresh: \(error.localizedDescription)")
            #endif
        }
    }
}

/// The one source of the per-prayer notification defaults (`<prayer>Notif` = at the start,
/// `<prayer>Nudges` = also halfway + 30 min left), read by the scheduler, Settings, the first-run
/// setup and PrayerViewModel. Owner, 2026-09-28: Fajr off (the Fajr alarm covers it), Dhuhr / Asr /
/// Maghrib nudge, Isha start — fewer nudges also spare iOS's 64-notification budget.
/// `migrate` writes every unset key at launch: existing users get what they effectively had before
/// (the scheduler read unset Notif as "not Dhuhr" and Nudges as on), so nothing changes for them.
enum NotificationDefaults {
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static func notify(_ prayer: String) -> Bool { prayer != "Fajr" }
    static func nudges(_ prayer: String) -> Bool { ["Dhuhr", "Asr", "Maghrib"].contains(prayer) }

    static func migrate(existingUser: Bool) {
        let d = UserDefaults.standard
        for prayer in prayers {
            let key = prayer.lowercased()
            if d.object(forKey: "\(key)Notif") == nil {
                d.set(existingUser ? prayer != "Dhuhr" : notify(prayer), forKey: "\(key)Notif")
            }
            if d.object(forKey: "\(key)Nudges") == nil {
                d.set(existingUser ? true : nudges(prayer), forKey: "\(key)Nudges")
            }
        }
    }
}
