//
//  PrayerViewModel+Demos.swift
//  shukr
//
//  The DEBUG seeds (-demoStreakExcused, -demoStreakBackfill, -demoPrayerDayKeyTest), simulator tests that write rows.
//  Moved out of PrayerViewModel.swift (cleanup-map tangle 2, step 7).
//

import SwiftUI
import SwiftData

#if DEBUG
extension PrayerViewModel {
    /// `-demoStreakBackfill` (simulator only; writes rows): the two prayer days before today get all
    /// five marked on time, the streak is set as if the last counted day was three days ago (what a
    /// late mark left behind), then the recount runs twice. Logs STREAKBACKFILL before / after.
    #if DEBUG
    /// `-demoStreakExcused` (simulator only; writes, then removes, its own rows and ranges): the owner's case, 2026-10-16.
    /// 12 days back: four days in full, the 5th excused from Maghrib, the 6th–9th excused, the 10th back at Asr, then two
    /// in full. Expected run 8 (the 5th and 10th count, the 6th–9th are stepped over); with Dhuhr missed on the 5th, 3.
    func demoStreakExcused() {
        #if targetEnvironment(simulator)
        let calendar = Calendar.current
        let todayStart = PrayerDay.start(for: Date())
        let savedRanges = Excused.ranges
        let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        func run(dhuhrMissedOnFifth: Bool) -> (Int, Int) {
            var made: [PrayerModel] = []
            var maghribOfFifth = Date(), asrOfTenth = Date()
            // Clear the 13 days first (a day's row range reaches into the next morning: clearing as we go took the
            // newer day's Fajr with it).
            if let oldest = calendar.date(byAdding: .day, value: -13, to: todayStart) {
                let from = PrayerDay.rowRange(forDayStarting: oldest).start, to = todayStart
                let old = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.startTime >= from && $0.startTime < to }))) ?? []
                old.forEach { context.delete($0) }
            }
            for back in 1...12 {   // the 13th stays empty: a break before the run
                guard let day = calendar.date(byAdding: .day, value: -back, to: todayStart) else { continue }
                let n = 13 - back                     // 1 … 12, oldest first
                for (i, name) in names.enumerated() {
                    let s = day.addingTimeInterval(Double(5 + i * 3) * 3600)
                    let r = PrayerModel(name: name, startTime: s, endTime: s.addingTimeInterval(7200))
                    if n == 5 && name == "Maghrib" { maghribOfFifth = s }
                    if n == 10 && name == "Asr" { asrOfTenth = s }
                    let prayed: Bool
                    switch n {
                    case 5: prayed = i < 3 && !(dhuhrMissedOnFifth && name == "Dhuhr")
                    case 6...9: prayed = false
                    case 10: prayed = i >= 2
                    default: prayed = true
                    }
                    if prayed { r.isCompleted = true; r.timeAtComplete = s.addingTimeInterval(600); r.numberScore = 1 }
                    context.insert(r); made.append(r)
                }
            }
            try? context.save()
            Excused.save([ExcusedRange(kind: .haid, start: maghribOfFifth.addingTimeInterval(-60), expectedEnd: asrOfTenth,
                                       end: asrOfTenth.addingTimeInterval(-60), pauseZikr: false)])
            let ranges = Excused.ranges, days = Excused.Days(ranges)
            let all = (try? context.fetch(FetchDescriptor<PrayerModel>())) ?? []
            for back in 1...13 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: todayStart) else { continue }
                let rows = all.filter { $0.dayStart == day }
                print("STREAKEXCUSED day -\(back): \(rows.count) rows, \(rows.filter(\.isCompleted).count) prayed → \(Excused.streakDay(rows, ok: { self.gradingCriteria(for: $0) }, ranges: ranges, touched: days.excludes(day)))")
            }
            refreshStreaksFromHistory()
            let out = (prayerStreak, onTimeStreak)
            made.forEach { context.delete($0) }
            try? context.save()
            return out
        }
        let a = run(dhuhrMissedOnFifth: false)
        print("STREAKEXCUSED owner's case: streak=\(a.0) inTime=\(a.1) (expected 8 / 8, today not counted)")
        let b = run(dhuhrMissedOnFifth: true)
        print("STREAKEXCUSED Dhuhr missed before the excuse: streak=\(b.0) inTime=\(b.1) (expected 3 / 3)")
        Excused.save(savedRanges)
        refreshStreaksFromHistory()
        #endif
    }
    #endif

    func demoStreakBackfill() {
        let calendar = Calendar.current
        let todayStart = PrayerDay.start(for: Date())
        for back in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: todayStart) else { continue }
            let (start, end) = PrayerDay.rowRange(forDayStarting: day)
            let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.startTime >= start && $0.startTime <= end }))) ?? []
            for (i, name) in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].enumerated() {
                let row = rows.first { $0.name == name } ?? {
                    let s = day.addingTimeInterval(Double(5 + i * 3) * 3600)
                    let r = PrayerModel(name: name, startTime: s, endTime: s.addingTimeInterval(7200))
                    context.insert(r); return r
                }()
                row.isCompleted = true
                row.timeAtComplete = row.startTime.addingTimeInterval(600)
                row.numberScore = 1
            }
        }
        try? context.save()
        prayerStreak = 1
        lastStreakDate = calendar.date(byAdding: .day, value: -3, to: todayStart) ?? todayStart
        onTimeStreak = 1
        lastOnTimeStreakDate_TI = lastStreakDate.timeIntervalSince1970
        print("STREAKBACKFILL before: streak=\(prayerStreak) inTime=\(onTimeStreak)")
        checkToResetStreak()
        print("STREAKBACKFILL after 1: streak=\(prayerStreak) inTime=\(onTimeStreak) last=\(lastStreakDate)")
        checkToResetStreak()
        print("STREAKBACKFILL after 2: streak=\(prayerStreak) inTime=\(onTimeStreak)")
    }

    /// `-demoPrayerDayKeyTest` (simulator only; writes then removes rows): schema 2.8.0's reason. Today's Isha is
    /// given a start after midnight (tomorrow 00:30) and yesterday's Isha a start this morning (00:30): the day's
    /// rows must still be exactly today's — the late Isha found (not re-inserted by a refresh), yesterday's not
    /// adopted. Logs PRAYERDAYKEY ✅ / ❌ and cleans up.
    func demoPrayerDayKeyTest() {
        let calendar = Calendar.current
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        if (store?.double(forKey: "lastLatitude") ?? 0) == 0 {   // times need a place: New York
            store?.set(40.7128, forKey: "lastLatitude"); store?.set(-74.0060, forKey: "lastLongitude")
        }
        let todayKey = PrayerDay.key()
        let todayStart = PrayerDay.start()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let yesterdayKey = PrayerNotificationID.dayKey(yesterday)
        let marker = "PRAYERDAYKEYTEST"
        // Clear today's existing Isha rows so the late one is the day's only Isha.
        let existing = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: todayStart)))) ?? []
        for r in existing where r.name == "Isha" { context.delete(r) }
        let late = PrayerModel(name: "Isha", startTime: tomorrow.addingTimeInterval(30 * 60), endTime: tomorrow.addingTimeInterval(90 * 60))
        late.prayerDayKey = todayKey; late.isCompleted = true; late.numberScore = 0.9; late.timeAtComplete = late.startTime.addingTimeInterval(300); late.mosqueName = marker
        let stale = PrayerModel(name: "Isha", startTime: todayStart.addingTimeInterval(30 * 60), endTime: todayStart.addingTimeInterval(90 * 60))
        stale.prayerDayKey = yesterdayKey; stale.isCompleted = true; stale.numberScore = 0.4; stale.mosqueName = marker
        context.insert(late); context.insert(stale)
        try? context.save()
        var ok = true
        func check(_ cond: Bool, _ what: String) { print("PRAYERDAYKEY \(cond ? "✅" : "❌") \(what)"); ok = ok && cond }
        let rows1 = loadPrayerObjects(for: PrayerDay.date())
        check(rows1.contains { $0 === late }, "today's rows include the Isha that starts after midnight")
        check(!rows1.contains { $0 === stale }, "yesterday's late Isha (this morning) is not adopted by today")
        fetchPrayerTimes(cameFrom: "PRAYERDAYKEYTEST")
        let ishas = ((try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: todayStart)))) ?? []).filter { $0.name == "Isha" }
        check(ishas.count == 1, "a refresh leaves one Isha for today (found \(ishas.count))")
        check(ishas.first === late && late.isCompleted, "and it's the marked late one, untouched")
        let rows2 = Self.onePerPrayer(loadPrayerObjects(for: PrayerDay.date()))
        check(rows2.count == 5, "the day still has five prayers (found \(rows2.count))")
        print("PRAYERDAYKEY \(ok ? "✅ ALL PASSED" : "❌ FAILED")")
        // Clean up the fakes; a normal refresh restores today's Isha from the times.
        for r in (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.mosqueName == marker }))) ?? [] { context.delete(r) }
        try? context.save()
        fetchPrayerTimes(cameFrom: "PRAYERDAYKEYTEST cleanup")
    }
}
#endif
