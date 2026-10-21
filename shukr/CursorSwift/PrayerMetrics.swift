import Foundation

// The counts every metrics screen reads (prayer-metrics rethink: board/scoring-rethink/plan-v3.md §2c, §10, §11; build plan
// phase 4's logic, landed early so Journey's hero, Your prayers and the Salah bar can be built against it). Built on
// JourneyLog (JourneyStore loads it off the main thread) and PrayerState — no screen decides a week on its own.
// Rules, in his words where they define them:
// - The bar is the obligation, all five each in its time ("muslims should pray every day and make every prayer").
// - A day with nothing logged is "no record", never missed (most of his quiet days were the app, not him); today is
//   always on record (you're here).
// - A strong week: every due prayer prayed (a missed one holds the week until it's made up), at most 3 of them below the
//   bar (made up after its time), and no day without a record. A complete week: every due prayer in its time.
// - Excused prayers are never due; a fully excused week is neither strong nor complete and never breaks the streak.

extension JourneyLog.Mark {
    /// This mark as a PrayerState; nil = no row (the app wasn't opened that day).
    func state(end: Date?, now: Date, noTime: Bool = false) -> PrayerState? {
        switch self {
        case .done(let score): PrayerState.of(isCompleted: true, score: score, end: end ?? now, excused: false, now: now,
                                              timeUnknown: noTime)
        case .missed: .notMarked
        case .toCome: .toCome
        case .excused: .excused
        case .none: nil
        }
    }
}

enum PrayerMetrics {
    /// Below the bar (made up after its time) a strong week can still hold (plan-v3 §10: 32 of 35).
    static let strongWeekSlack = 3

    /// One prayer day as a week reads it.
    struct Day: Equatable {
        let key: String
        let date: Date
        /// Fajr … Isha; nil when the day has no record.
        let states: [PrayerState]?
        var noRecord: Bool { states == nil }
        func count(_ test: (PrayerState) -> Bool) -> Int { states?.filter(test).count ?? 0 }
        var inTime: Int { count(\.inTime) }
        /// Every due prayer in its time (an excused one isn't due): a complete day. Not before its last prayer is due.
        var complete: Bool {
            guard let states, !states.contains(.toCome) else { return false }
            let due = states.filter { $0 != .excused }
            return !due.isEmpty && due.allSatisfy(\.inTime)
        }
    }

    struct Week: Equatable {
        /// The week's first day (the calendar's first weekday).
        let start: Date
        /// Seven days, first to last; days after today are `.toCome` throughout.
        let days: [Day]
        let isCurrent: Bool

        private func count(_ test: (PrayerState) -> Bool) -> Int { days.reduce(0) { $0 + $1.count(test) } }
        var inTime: Int { count(\.inTime) }
        var madeUp: Int { count { $0 == .madeUp } }
        var notMarked: Int { count { $0 == .notMarked } }
        var excused: Int { count { $0 == .excused } }
        var toCome: Int { count { $0 == .toCome } }
        var noRecordDays: Int { days.filter(\.noRecord).count }
        /// Prayed, in its time or made up.
        var prayed: Int { inTime + madeUp }
        /// What the week asks: every prayer not excused (35 in a week with no excused prayers).
        var asked: Int { days.count * 5 - excused }
        /// Prayers due so far on days with a record.
        var due: Int { prayed + notMarked }

        /// Nothing missing so far: no prayer left unmarked, no day without a record, at most the slack below the bar.
        /// A finished week that is on track is strong.
        var onTrack: Bool { notMarked == 0 && noRecordDays == 0 && madeUp <= strongWeekSlack && asked > 0 }
        var finished: Bool { !isCurrent && toCome == 0 }
        var strong: Bool { finished && onTrack }
        var complete: Bool { strong && madeUp == 0 && inTime == asked }
        /// The current week's words (Koo & Fishbach, plan-v3 §9): "12 done" early in the week, "4 left" late in it — what's
        /// left is every prayer still to pray, an unmarked one included (it's made up to count).
        var done: Int { prayed }
        var left: Int { toCome + notMarked }
        /// A week the streak steps over: every prayer excused (or no record on a fully excused stretch).
        var excusedWeek: Bool { excused == days.count * 5 }
    }

    /// The prayer-day key of `now` and the day it's on.
    private static func today(_ now: Date) -> (key: String, start: Date) {
        let d = PrayerDay.date(for: now)
        return (PrayerNotificationID.dayKey(d), Calendar.current.startOfDay(for: d))
    }

    /// A day from the log: no record when nothing was marked and it isn't today. A day before the fresh start, or inside
    /// an excused range with no rows, asks nothing (all excused) — it never blocks a week.
    static func day(_ date: Date, in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date) -> Day {
        let d = log.day(date)
        let (todayKey, todayStart) = today(now)
        if d.date > todayStart { return Day(key: d.key, date: d.date, states: Array(repeating: .toCome, count: 5)) }
        if !d.counted || (!d.active && excused.excludes(d.date)) {
            return Day(key: d.key, date: d.date, states: Array(repeating: .excused, count: 5))
        }
        let states = (0..<5).map { i -> PrayerState? in d.marks[i].state(end: d.slots[i]?.end, now: now, noTime: d.slots[i]?.noTime ?? false) }
        let recorded = d.active || d.key == todayKey || d.marks.contains(.excused)
        guard recorded else { return Day(key: d.key, date: d.date, states: nil) }
        // A recorded day with a row missing (the app never made it): unmarked and over, or still to come today.
        return Day(key: d.key, date: d.date, states: states.map { $0 ?? (d.key == todayKey ? .toCome : .notMarked) })
    }

    /// The week holding `date`.
    static func week(containing date: Date, in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> Week {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .map { day($0, in: log, excused: excused, now: now) }
        let current = cal.isDate(start, equalTo: today(now).start, toGranularity: .weekOfYear)
        return Week(start: start, days: days, isCurrent: current)
    }

    /// Every week from the log's first (or the fresh start's) to this one, oldest first.
    static func weeks(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> [Week] {
        guard let first = [log.firstDay, log.countsFrom].compactMap({ $0 }).max() else { return [] }
        var out: [Week] = []
        var date = first
        let end = today(now).start
        while date <= end {
            let w = week(containing: date, in: log, excused: excused, now: now)
            out.append(w)
            guard let next = Calendar.current.date(byAdding: .day, value: 7, to: w.start) else { break }
            date = next
        }
        return out
    }

    /// Strong weeks in a row: the run ending with the last finished week (the current week never breaks it), and the best.
    /// A fully excused week is stepped over.
    static func strongWeeks(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> (current: Int, best: Int) {
        var run = 0, best = 0
        for w in weeks(in: log, excused: excused, now: now) where !w.isCurrent {
            if w.excusedWeek { continue }
            if w.strong { run += 1; best = max(best, run) } else { run = 0 }
        }
        return (run, best)
    }

    /// Your usual week: the median of your last 8 finished weeks' in-time counts, weeks without a gap in the record only
    /// (nil before there are 3). The comparison Journey shows instead of last week (Strava's card made normal weeks feel bad).
    static func usualWeek(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> Int? {
        let list = weeks(in: log, excused: excused, now: now).filter { !$0.isCurrent && $0.noRecordDays == 0 && !$0.excusedWeek }.suffix(8)
        guard list.count >= 3 else { return nil }
        let sorted = list.map(\.inTime).sorted()
        return sorted[sorted.count / 2]
    }

    /// "Your typical week": the median in-time week of your first 8 recorded weeks, and of your last 8 (nil until 16).
    static func typicalWeek(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> (then: Int, now: Int)? {
        let list = weeks(in: log, excused: excused, now: now).filter { !$0.isCurrent && $0.noRecordDays == 0 && !$0.excusedWeek }
        guard list.count >= 16 else { return nil }
        func median(_ w: ArraySlice<Week>) -> Int { let s = w.map(\.inTime).sorted(); return s[s.count / 2] }
        return (median(list.prefix(8)), median(list.suffix(8)))
    }
}

// MARK: - One prayer, lately (Your prayers; plan-v3 §2d, §10.4)

extension PrayerMetrics {
    /// Your best month: the calendar month with the earliest usual place in the window (median), from months with at least
    /// this many timed in-time marks of the prayer.
    static let bestMonthMinimum = 8
    /// How many recent in-time marks make "your usual".
    static let usualSample = 30

    struct BestMonth: Equatable {
        let start: Date
        let share: Double
    }

    struct PrayerRecent: Equatable {
        let name: String
        /// The last 7 prayer days, oldest first, today last; nil = no record.
        let last7: [PrayerState?]
        /// "in its time 4 of the last 7": in time, of the days it was asked (not excused, not still to come, on record).
        var inTime: Int { last7.compactMap { $0 }.filter(\.inTime).count }
        var asked: Int { last7.compactMap { $0 }.filter { $0 != .excused && $0 != .toCome }.count }
        /// Your usual place in its window (0 = as it begins, 1 = as it ends): the median of your last 30 timed in-time marks;
        /// nil under 5. Fair across seasons: it's the place, not the minutes.
        let usualShare: Double?
        let bestMonth: BestMonth?
        /// The window your usual is set on: today's, or the latest one there is.
        let window: DateInterval?

        /// "usually by 6:00": your usual place, as a clock on today's window.
        var usualClock: Date? {
            guard let usualShare, let window else { return nil }
            return window.start.addingTimeInterval(usualShare * window.duration)
        }
        /// "4 min from your best month": minutes on today's window between your usual and your best month's (0 when this
        /// month is your best; nil without either).
        var minutesFromBestMonth: Int? {
            guard let usualShare, let best = bestMonth, let window else { return nil }
            return max(0, Int(((usualShare - best.share) * window.duration / 60).rounded()))
        }
        /// "10 min earlier than your usual": minutes on that prayer's own window, positive = earlier. nil without a usual.
        func minutesEarlier(markedAt: Date, start: Date, end: Date) -> Int? {
            guard let usualShare, end > start else { return nil }
            let share = markedAt.timeIntervalSince(start) / end.timeIntervalSince(start)
            return Int(((usualShare - share) * end.timeIntervalSince(start) / 60).rounded())
        }
    }

    static func recent(_ name: String, in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> PrayerRecent {
        guard let i = JourneyLog.names.firstIndex(of: name) else {
            return PrayerRecent(name: name, last7: [], usualShare: nil, bestMonth: nil, window: nil)
        }
        let cal = Calendar.current
        let todayStart = today(now).start
        let last7 = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: todayStart) }
            .map { day($0, in: log, excused: excused, now: now).states?[i] }
        // Every timed in-time mark of this prayer, newest first: its place in its window and its day.
        var marks: [(date: Date, share: Double)] = []
        var window: DateInterval?
        for d in log.days.values.sorted(by: { $0.date > $1.date }) where d.counted {
            guard let slot = d.slots[i] else { continue }
            if window == nil, d.date <= todayStart, slot.end > slot.start { window = DateInterval(start: slot.start, end: slot.end) }
            // A no-time mark has no place in its window (its markedAt is nil): it never moves "your usual".
            guard let at = slot.markedAt, !slot.noTime, d.marks[i].state(end: slot.end, now: now)?.inTime == true,
                  slot.end > slot.start else { continue }
            marks.append((d.date, min(max(at.timeIntervalSince(slot.start) / slot.end.timeIntervalSince(slot.start), 0), 1)))
        }
        func median(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.sorted()[v.count / 2] }
        let recent = marks.prefix(usualSample).map(\.share)
        let usual = recent.count >= 5 ? median(recent) : nil
        var byMonth: [Date: [Double]] = [:]
        for m in marks { byMonth[JourneyLog.monthStart(m.date), default: []].append(m.share) }
        let best = byMonth.filter { $0.value.count >= bestMonthMinimum }
            .compactMap { k, v in median(v).map { BestMonth(start: k, share: $0) } }
            .min { ($0.share, $1.start) < ($1.share, $0.start) }   // the earliest; a tie goes to the later month
        return PrayerRecent(name: name, last7: last7, usualShare: usual, bestMonth: best, window: window)
    }
}
