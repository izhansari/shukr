//
//  NotificationScheduler.swift
//  shukr
//
//  Every scheduled local notification goes through here (2026-09-27, notes #10). iOS keeps at
//  most 64 pending per app, so this owns that budget:
//  - Prayers ~7 days ahead: the next two prayer days get Start / Mid / End (nudges per Settings),
//    days 3–7 Start only. Completed prayers are skipped.
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
    static let daysAhead = 7

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
    static func keepAliveItem(after last: Date) -> Item {
        let date = last.addingTimeInterval(20 * 60)
        let content = UNMutableNotificationContent()
        content.title = "Open shukr to keep your prayer reminders coming"
        content.body = "Your scheduled reminders end here. Opening shukr lines up the next week."
        content.sound = .default
        return Item(id: keepAlivePrefix + PrayerNotificationID.dayKey(date), date: date, priority: 0, content: content)
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
        let center = UNUserNotificationCenter.current()
        let items = plan(context: context, todayOverride: todayOverride)

        let pending = await center.pendingNotificationRequests()
        let ownedPending = pending.filter { owns($0.identifier) }
        let others = pending.count - ownedPending.count
        let budget = max(limit - others - spare, 0)
        // One slot is the last-resort reminder's, after the last prayer start that made it in — only
        // with room for at least one start besides it, and only when prayer starts are scheduled at all
        // (zikr reminders alone get no "keep your prayer reminders coming").
        let sorted = items.sorted { ($0.priority, $0.date) < ($1.priority, $1.date) }
        let reserve = budget >= 2 ? 1 : 0
        var chosen = Array(sorted.prefix(max(budget - reserve, 0)))
        let lastStart = chosen.filter { PrayerNotificationID.parse($0.id)?.kind == "Start" }.map(\.date).max()
        if reserve == 1, let lastStart { chosen.append(keepAliveItem(after: lastStart)) }

        // Only what changed (2026-09-27 review): while moving, the app re-plans every 500 m / 30 s,
        // and removing + re-adding ~55 requests each time was wasted work. A request is "the same"
        // when its id, minute and wording match.
        let have = Dictionary(ownedPending.map { ($0.identifier, signature($0.content, trigger: $0.trigger)) },
                              uniquingKeysWith: { a, _ in a })
        let want = Dictionary(chosen.map { ($0.id, (item: $0, sig: signature($0.content, date: $0.date))) },
                              uniquingKeysWith: { a, _ in a })
        let stalePending = have.filter { id, sig in want[id]?.sig != sig }.map(\.key)
        let toAdd = want.values.filter { have[$0.item.id] != $0.sig }.map(\.item)
        if !stalePending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stalePending) }
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
        await FajrAlarms.plan(reason: reason.isEmpty ? "reschedule" : reason)
        await NotificationHealth.shared.refresh()
        if !stalePending.isEmpty || !toAdd.isEmpty || !stale.isEmpty {
            print("🔔 notifications (\(reason)): \(chosen.count) of \(items.count) planned\(chosen.contains { $0.id.hasPrefix(keepAlivePrefix) } ? " (incl. the last-resort reminder)" : "") — removed \(stalePending.count), added \(toAdd.count), \(others) other pending, cleared \(stale.count) delivered")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-logPendingNotifs") {
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
        let horizon = now.addingTimeInterval(TimeInterval(daysAhead) * 86_400)
        return prayerItems(context: context, todayOverride: todayOverride)
            + ZikrReminders.items(context: context, now: now, horizon: horizon) { prayer, day in
                windows(for: day)?[prayer]?.start
            }
    }

    private static let defaults = UserDefaults.standard
    /// How many prayer days still ahead get their nudges (halfway, 30 min left); later days get only
    /// the start until they come this close (Upcoming reminders explains it from this).
    static let nudgeDaysAhead = 2
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
        let horizon = now.addingTimeInterval(TimeInterval(daysAhead) * 86_400)

        // Which prayers are already prayed, over the days covered.
        let lastDay = cal.date(byAdding: .day, value: daysAhead + 1, to: firstDay) ?? firstDay
        let rangeStart = firstDay, rangeEnd = lastDay
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted && $0.startTime >= rangeStart && $0.startTime < rangeEnd })
        let done = Set(((try? context.fetch(descriptor)) ?? []).map { PrayerNotificationID.dayKey($0.startTime) + $0.name })

        var items: [Item] = []
        var fullDays = 0   // prayer days with nudges: the next two that are still ahead
        for offset in 0...(daysAhead + 1) {
            guard let day = cal.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let dayWindows = offset == 0 ? (todayOverride ?? windows(for: day)) : windows(for: day)
            guard let dayWindows, let fajr = dayWindows["Fajr"]?.start, fajr < horizon else { continue }
            let stillAhead = dayWindows.values.contains { $0.end > now }
            guard stillAhead else { continue }
            let withNudges = fullDays < nudgeDaysAhead
            fullDays += 1
            for name in PrayerNotificationID.prayers {
                guard let window = dayWindows[name], !done.contains(PrayerNotificationID.dayKey(day) + name) else { continue }
                let s = settings(name)
                guard s.notify else { continue }
                let kinds = withNudges && s.nudges ? ["Start", "Mid", "End"] : ["Start"]
                for kind in kinds {
                    guard let (date, content) = prayerNotification(kind, prayer: name, window: window),
                          date > now, date < horizon else { continue }
                    // Near days: starts, then their nudges; far days' starts after.
                    let priority = withNudges ? (kind == "Start" ? 0 : 1) : 2
                    items.append(Item(id: PrayerNotificationID.make(day: day, prayer: name, kind: kind),
                                      date: date, priority: priority, content: content))
                }
            }
        }
        return items
    }

    /// The notification exactly as the app has always sent it (moved from PrayerViewModel's
    /// `scheduleThisPrayerNotifAt`, 2026-09-27 — don't change the wording without the owner).
    static func prayerNotification(_ kind: String, prayer: String,
                                   window: (start: Date, end: Date, window: TimeInterval)) -> (Date, UNNotificationContent)? {
        let endTime = window.end
        let date: Date
        let content = UNMutableNotificationContent()
        switch kind {
        case "Start":
            date = window.start
            content.title = "\(prayer) Time 🟢"
            content.subtitle = "Pray by \(shortTimePM(endTime))"
        case "Mid":
            let timeUntilEnd = window.window * 0.5
            date = endTime.addingTimeInterval(-timeUntilEnd)
            content.title = "\(prayer) At Midpoint 🟡"
            content.subtitle = "There's \(timeLeftString(from: timeUntilEnd))"
        case "End":
            let timeUntilEnd = 30.0 * 60
            date = endTime.addingTimeInterval(-timeUntilEnd)
            content.title = "\(prayer) Almost Over! 🔴"
            content.subtitle = "There's only \(timeLeftString(from: timeUntilEnd))"
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
