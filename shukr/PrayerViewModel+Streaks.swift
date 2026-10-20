//
//  PrayerViewModel+Streaks.swift
//  shukr
//
//  The streaks: today's part (calculatePrayerStreak), the days before it recounted from the rows
//  (refreshStreaksFromHistory), the best run (recountBestStreak / bestRun) and a rule change (rulesChanged).
//  Moved out of PrayerViewModel.swift (cleanup-map tangle 2, step 4).
//

import SwiftUI
import SwiftData
import QuartzCore

extension PrayerViewModel {

    func calculatePrayerStreak() {
        guard !StoreFallback.active else { return }   // in-memory store (WF56): keep the saved streaks as they are
        let now = Date()
        let todayStart = PrayerDay.start(for: now)
        let lastStreakDateStart = PrayerDay.start(for: lastStreakDate)
        
        checkToResetStreak()
        // The old unmark path could subtract on every call and left some streaks negative.
        if prayerStreak < 0 { prayerStreak = 0 }

        guard let todayPrayers = getTodaysPrayersFromContext() else{ return }
        // Today counts once every prayer she isn't excused from is prayed (Excused.streakDay): all five, or the ones
        // before / after an excused stretch. A day excused in full adds nothing; an unmark still takes a counted day back.
        let ranges = Excused.ranges
        let todayCounts = Excused.streakDay(todayPrayers, ok: gradingCriteria, ranges: ranges,
                                            touched: Excused.Days(ranges).excludes(todayStart)) == .counts
        let decrementStreak = !todayCounts && lastStreakDateStart == todayStart

        if todayCounts {
            // A day continues the streak once. This runs on every mark, time edit and widget
            // reconcile, and used to add 1 each time once all five were in (2026-09-24).
            if lastStreakDateStart != todayStart {
                prayerStreak += 1
                lastStreakDate = now
                NotificationCenter.default.post(name: .prayerStreakContinued, object: nil)
            }
        } else if decrementStreak { // today had counted and a prayer was unmarked
            prayerStreak = max(prayerStreak - 1, 0)
            // Today no longer counts: back to "counted through yesterday", so this can't
            // decrement again on the next call and re-completing today counts it again.
            lastStreakDate = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        }

        // Update max streak if necessary
        if prayerStreak > maxPrayerStreak {
            maxPrayerStreak = prayerStreak
            dateOfMaxPrayerStreak = now
        }

        updateDayMilestones(todayPrayers: todayPrayers, todayStart: todayStart, now: now, ranges: ranges)
        
        func getTodaysPrayersFromContext() -> [PrayerModel]? {
            // Fetch prayers for today (2.8.0: by prayer day key)
            let todayPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: PrayerDay.rowsPredicate(forDayStarting: PrayerDay.start(for: now))
            )
            guard let todayPrayers = try? context.fetch(todayPrayersFetchDescriptor) else {
                print("❌ Failed to fetch today's prayers")
                return nil
            }
            return todayPrayers
        }
    }
    
    /// A prayer that keeps the streak: the user's goal (PrayerGoal — the one rule; Journey asks it too).
    func gradingCriteria(for prayer: PrayerModel) -> Bool {
        prayer.isCompleted && PrayerGoal.current.meets(score: prayer.numberScore ?? 0)
    }
    
    /// The in-time days streak (all five within their windows: no Qaza, none missed) and the
    /// perfect day (all five Early), each counted once a day like the main streak. Posted after the main
    /// streak's notification so the top bar can play them in order.
    private func updateDayMilestones(todayPrayers: [PrayerModel], todayStart: Date, now: Date, ranges: [ExcusedRange]) {
        func doneNames(minScore: Double) -> Set<String> {
            Set(todayPrayers.filter { $0.isCompleted && ($0.numberScore ?? 0) >= minScore - 0.0001 }.map(\.name))
        }
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        // In-time days (owner, 2026-09-25: "days where there was no qaza"). The days before today
        // were just recounted from the rows (refreshStreaksFromHistory, via checkToResetStreak);
        // only today is added / taken back here, which is also where its celebration fires.
        // Excused prayers count as done here too (Excused.streakDay), like the day streak.
        let lastOnTime = PrayerDay.start(for: Date(timeIntervalSince1970: lastOnTimeStreakDate_TI))
        let inTimeToday = Excused.streakDay(todayPrayers, ok: { ($0.numberScore ?? 0) >= PrayerScoring.inWindowFloor - 0.0001 },
                                            ranges: ranges, touched: Excused.Days(ranges).excludes(todayStart)) == .counts
        if inTimeToday {
            if lastOnTime != todayStart {
                onTimeStreak += 1
                lastOnTimeStreakDate_TI = now.timeIntervalSince1970
                maxOnTimeStreak = max(maxOnTimeStreak, onTimeStreak)
                // No sparkles any more: one streak, at the goal (owner, 2026-10-18); the count stays for Your Data's bests.
            }
        } else if lastOnTime == todayStart {   // today had counted; a prayer was unmarked or re-timed
            onTimeStreak = max(onTimeStreak - 1, 0)
            lastOnTimeStreakDate_TI = yesterdayStart.timeIntervalSince1970
        }

        // Perfect day: all five Early (owner, 2026-09-25 — "only when everything is green")
        if doneNames(minScore: 1).count == 5,
           PrayerDay.start(for: Date(timeIntervalSince1970: lastPerfectDay_TI)) != todayStart {
            lastPerfectDay_TI = now.timeIntervalSince1970
            NotificationCenter.default.post(name: .perfectDay, object: nil)
        }
    }

    /// The goal or the fresh start changed (PrayerStats): the streak and its best recounted from the rows at the new rules,
    /// and today's "counted once" flag set to what today is now — silently: a setting never plays hearts (inventory risk 1;
    /// otherwise the next mark would celebrate a day that already counted).
    func rulesChanged() {
        guard !StoreFallback.active else { return }
        // Its cost on the main thread, measured (owner, 2026-10-18: "measure a goal flip"): journey-perf.log's "goal flip".
        MainActor.assumeIsolated { JourneyPerf.began("goal flip") }
        let start = CACurrentMediaTime()
        defer { MainActor.assumeIsolated { JourneyPerf.took("rules: recount, total", since: start) } }
        let now = Date()
        let todayStart = PrayerDay.start(for: now)
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        if let rows = try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: todayStart))) {
            let ranges = Excused.ranges
            let counts = Excused.streakDay(rows, ok: gradingCriteria, ranges: ranges,
                                           touched: Excused.Days(ranges).excludes(todayStart)) == .counts
            let wasCounted = PrayerDay.start(for: lastStreakDate) == todayStart
            if counts != wasCounted { lastStreakDate = counts ? now : yesterdayStart }
        }
        let t1 = CACurrentMediaTime()
        refreshStreaksFromHistory()
        MainActor.assumeIsolated { JourneyPerf.took("rules: streak recount", since: t1) }
        recountBestStreak(now: now)   // off the main thread
        let container = context.container
        Task { @MainActor in MilestoneCelebration.shared.recordSilently(container: container) }
    }

    /// "Max N Days" from the rows: the longest run at the goal since the fresh start. It's otherwise only ever raised (a
    /// flip down or a reset left a best never reached at the new rules — inventory §8). Reads every prayer day once: only on
    /// a rule change or a restore.
    /// Read off the main thread (on his history a whole pass took 71 ms on the main thread in the sim — a hitch on every
    /// goal flip without a fresh start, 2026-10-18); the result is kept on the main thread. `save: false` (the DEBUG flip
    /// run) only times a whole-history pass.
    func recountBestStreak(now: Date = Date(), from: Date? = PrayerStats.countsFrom, save: Bool = true) {
        guard !StoreFallback.active else { return }
        let container = context.container
        let ranges = Excused.ranges
        let goal = PrayerGoal.current
        let todayStart = PrayerDay.start(for: now)   // here: PrayerDay's Fajr cache isn't for other threads
        let start = CACurrentMediaTime()
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.bestRun(in: ModelContext(container), from: from ?? .distantPast, todayStart: todayStart,
                                     ranges: ranges, goal: goal)
            await MainActor.run {
                JourneyPerf.took(save ? "rules: best recount (off main)" : "rules: best recount, every day (off main)", since: start)
                guard save, let self else { return }
                let best = max(found?.best ?? 0, self.prayerStreak)
                if self.maxPrayerStreak != best { self.maxPrayerStreak = best }
                if let end = found?.end, self.dateOfMaxPrayerStreak != end { self.dateOfMaxPrayerStreak = end }
            }
        }
    }

    /// The longest run at the goal from `from` to today (today before its last prayer never breaks it), and its last day.
    nonisolated static func bestRun(in context: ModelContext, from: Date, todayStart: Date, ranges: [ExcusedRange],
                                    goal: PrayerGoal) -> (best: Int, end: Date)? {
        let all = !ranges.isEmpty
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime >= from && (all || $0.isCompleted) }
        )
        guard let rows = try? context.fetch(descriptor) else { return nil }
        var byDay: [Date: [PrayerModel]] = [:]
        for row in rows { byDay[row.dayStart, default: []].append(row) }
        guard let first = byDay.keys.filter({ $0 >= from }).min() else { return nil }
        let excused = Excused.Days(ranges)
        let calendar = Calendar.current
        let ok = { (p: PrayerModel) in p.isCompleted && goal.meets(score: p.numberScore ?? 0) }
        var walk = StreakWalk.Forward(today: todayStart)
        var day = first
        while day <= todayStart {
            walk.add(day, Excused.streakDay(byDay[day] ?? [], ok: ok, ranges: ranges, touched: excused.excludes(day)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (walk.best, walk.bestDays?.upperBound ?? todayStart)
    }

    /// Runs on app activation and at the start of every streak update. It used to only zero the
    /// streak on a gap in `lastStreakDate`; now it recounts the days before today from the rows.
    func checkToResetStreak() {
        refreshStreaksFromHistory()
    }

    /// Streaks from the stored prayers, not incrementally from today (owner-approved fix,
    /// 2026-09-27): a prayer of an earlier prayer day marked late — a watch mark delivered after
    /// Fajr, the widget or "I already prayed" around Fajr, a time edit on an old prayer — completed
    /// that day but the streak never counted it, and the next day's gap check reset it to 0.
    ///
    /// The days BEFORE today are recounted from the rows (the run of consecutive complete days
    /// ending yesterday). Today is left to `calculatePrayerStreak` / `updateDayMilestones`, which add
    /// it once — and post its celebration — or take it back on an unmark: if today had already been
    /// counted it stays counted (run + 1), else the streak is the run and "counted through" is
    /// yesterday. Idempotent (a second call changes nothing) and silent: a past day never plays a
    /// celebration. Perfect day has no streak (its date only stops today's celebration repeating),
    /// so there's nothing to recount for it. Entry point for marks made elsewhere (the watch):
    /// `recomputeStreaks()`.
    func refreshStreaksFromHistory() {
        guard !StoreFallback.active else { return }   // an empty in-memory store would recount them to 0
        let now = Date()
        let todayStart = PrayerDay.start(for: now)
        let calendar = Calendar.current
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let five: Set<String> = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let inWindow = { (p: PrayerModel) in (p.numberScore ?? 0) >= PrayerScoring.inWindowFloor - 0.0001 }

        // Walk back from yesterday a week at a time and stop at the first day that breaks both runs
        // (a typical call reads one or two weeks of rows, not 1000 days — it runs on every Salah
        // page appear and every mark). Rows are keyed by the calendar day their prayers start on.
        var streak = StreakWalk.Backward(), inTime = StreakWalk.Backward()
        var batchEnd = todayStart                     // exclusive
        var day = yesterdayStart
        // Excused days by Excused.streakDay: a partly excused day with the rest prayed adds to a run, a fully excused one is
        // stepped over, a miss breaks it (owner, 2026-10-16).
        let ranges = Excused.ranges
        let excused = Excused.Days(ranges)
        // Nothing before the fresh start counts (PrayerStats): the runs end there.
        let countsFrom = PrayerStats.countsFrom
        batches: for _ in 0..<150 {                   // ≤ ~1000 days
            guard let batchStart = calendar.date(byAdding: .day, value: -7, to: batchEnd) else { break }
            // 2.8.0: a day's Isha can start after midnight, so fetch 6 h past the batch and group rows by their own
            // prayer day; rows whose day lies before this batch wait for the next one (it fetches them).
            // Unmarked rows too when Excused is in use: they say which prayers were excused (their windows).
            let fetchEnd = batchEnd.addingTimeInterval(6 * 3600)
            let all = !ranges.isEmpty
            let descriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate<PrayerModel> { $0.startTime >= batchStart && $0.startTime < fetchEnd && (all || $0.isCompleted) }
            )
            guard let rows = try? context.fetch(descriptor) else { return }
            var byDay: [Date: [PrayerModel]] = [:]
            for row in rows {
                let d = row.dayStart
                if d >= batchStart && d < batchEnd { byDay[d, default: []].append(row) }
            }
            while day >= batchStart {
                if let countsFrom, day < countsFrom { break batches }
                let dayRows = byDay[day] ?? []
                let touched = excused.excludes(day)
                if streak.alive {
                    streak.add(Excused.streakDay(dayRows, ok: { self.gradingCriteria(for: $0) }, ranges: ranges, touched: touched))
                }
                if inTime.alive {
                    inTime.add(Excused.streakDay(dayRows, ok: inWindow, ranges: ranges, touched: touched))
                }
                if !streak.alive && !inTime.alive { break batches }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break batches }
                day = previous
            }
            batchEnd = batchStart
        }

        let before = (streak: prayerStreak, inTime: onTimeStreak, maxStreak: maxPrayerStreak, maxInTime: maxOnTimeStreak)

        // The day streak (by the chosen streak mode). Only changed values are written: each write
        // re-renders the views bound to these keys.
        let todayCounted = PrayerDay.start(for: lastStreakDate) == todayStart
        let newStreak = todayCounted ? streak.run + 1 : streak.run
        if prayerStreak != newStreak { prayerStreak = newStreak }
        if !todayCounted && PrayerDay.start(for: lastStreakDate) != yesterdayStart { lastStreakDate = yesterdayStart }
        if prayerStreak > maxPrayerStreak {
            maxPrayerStreak = prayerStreak
            dateOfMaxPrayerStreak = todayCounted ? now : yesterdayStart   // the day that ended the run
        }

        // In-time days (all five within their windows).
        let inTimeTodayCounted = PrayerDay.start(for: Date(timeIntervalSince1970: lastOnTimeStreakDate_TI)) == todayStart
        let newInTime = inTimeTodayCounted ? inTime.run + 1 : inTime.run
        if onTimeStreak != newInTime { onTimeStreak = newInTime }
        if !inTimeTodayCounted && lastOnTimeStreakDate_TI != yesterdayStart.timeIntervalSince1970 {
            lastOnTimeStreakDate_TI = yesterdayStart.timeIntervalSince1970
        }
        if onTimeStreak > maxOnTimeStreak { maxOnTimeStreak = onTimeStreak }

        logFirstRecount(before: before)
    }

    /// Once per install: what the first history recount changed (streak, in-time days, their
    /// maxes), so the owner can be told exactly — the log in DEBUG, one line in the app group
    /// ("streakRecount.firstRun") on any build.
    private func logFirstRecount(before: (streak: Int, inTime: Int, maxStreak: Int, maxInTime: Int)) {
        let key = "streakRecount.firstRun"
        guard let group = UserDefaults(suiteName: SharedStore.appGroup), group.string(forKey: key) == nil else { return }
        let line = "\(Date().formatted(.iso8601)) streak \(before.streak)→\(prayerStreak), in-time \(before.inTime)→\(onTimeStreak), max streak \(before.maxStreak)→\(maxPrayerStreak), max in-time \(before.maxInTime)→\(maxOnTimeStreak)"
        group.set(line, forKey: key)
        print("📊 first streak recount: \(line)")
    }

    /// For a prayer marked somewhere else, possibly on an earlier prayer day (the watch): recount
    /// the streaks from the rows, then today's part.
    func recomputeStreaks() {
        try? context.save()
        calculatePrayerStreak()
    }
}
