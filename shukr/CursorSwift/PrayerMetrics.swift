import Foundation
import SwiftData

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
        /// The step the day is judged by (Your goal; owner, 2026-10-21: the step sets the bar for everything).
        var goal: PrayerGoal = .inWindow
        var noRecord: Bool { states == nil }
        func count(_ test: (PrayerState) -> Bool) -> Int { states?.filter(test).count ?? 0 }
        var inTime: Int { count(\.inTime) }
        /// Prayers that met the step.
        var met: Int { count(goal.meets) }
        /// Every due prayer met the step (an excused one isn't due): a complete day. Not before its last prayer is due.
        var complete: Bool {
            guard let states, !states.contains(.toCome) else { return false }
            let due = states.filter { $0 != .excused }
            return !due.isEmpty && due.allSatisfy(goal.meets)
        }
    }

    struct Week: Equatable {
        /// The week's first day (the calendar's first weekday).
        let start: Date
        /// Seven days, first to last; days after today are `.toCome` throughout.
        let days: [Day]
        let isCurrent: Bool
        /// The step the week is judged by (Your goal): "N of 35" counts prayers that met it, in its words.
        var goal: PrayerGoal = .inWindow

        private func count(_ test: (PrayerState) -> Bool) -> Int { days.reduce(0) { $0 + $1.count(test) } }
        /// Prayers that met the step ("12 of 35 in their windows" — `goal.countWords`).
        var met: Int { count(goal.meets) }
        /// Prayed, but below the step (made up, or under the step's third): what the strong week's slack covers.
        var belowStep: Int { prayed - met }
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

        /// Nothing missing so far: no prayer left unmarked, no day without a record, at most the slack below the step.
        /// A finished week that is on track is strong. (On Prayed every prayed one meets the step, so it's all prayed.)
        var onTrack: Bool { notMarked == 0 && noRecordDays == 0 && belowStep <= strongWeekSlack && asked > 0 }
        var finished: Bool { !isCurrent && toCome == 0 }
        var strong: Bool { finished && onTrack }
        var complete: Bool { strong && met == asked }
        /// Can this week still be strong? A prayer unmarked now can only be made up, which meets Prayed but no higher step,
        /// so above Prayed it already counts against the slack. A day without a record can still be filled in. The mid-week
        /// line reads this (owner, 2026-10-21: "they missed 5 already by wednesday … hey dont get upset").
        var stillPossible: Bool {
            // A day with no record can only be filled in as "in its window, no time" (NoRecordDays.fill), which is below
            // the Middle and the Opening: there each of its prayers counts against the slack too.
            let unrecorded = goal.meets(.inTimeNoClock) ? 0 : noRecordDays * 5
            let lost = belowStep + (goal == .prayed ? 0 : notMarked) + unrecorded
            return asked > 0 && lost <= strongWeekSlack
        }
        /// The current week's words (Koo & Fishbach, plan-v3 §9): "12 done" early in the week, "4 left" late in it — done
        /// is what met the step; left is every prayer still to pray, an unmarked one included (it's made up to count).
        var done: Int { met }
        var left: Int { toCome + notMarked }
        /// A week the streak steps over: every prayer excused (or no record on a fully excused stretch).
        var excusedWeek: Bool { excused == days.count * 5 }
    }

    /// The prayer-day key of `now` and the day it's on.
    private static func today(_ now: Date) -> (key: String, start: Date) {
        let d = PrayerDay.date(for: now)
        return (PrayerNotificationID.dayKey(d), Calendar.current.startOfDay(for: d))
    }

    /// A day from the log: no record when nothing was marked and it isn't today. A day before the fresh start, before the
    /// first mark ever (the app wasn't in use: a new user's first week can still be strong), or inside an excused range
    /// with no rows, asks nothing (all excused) — it never blocks a week.
    static func day(_ date: Date, in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date) -> Day {
        let d = log.day(date)
        let (todayKey, todayStart) = today(now)
        if d.date > todayStart { return Day(key: d.key, date: d.date, states: Array(repeating: .toCome, count: 5), goal: log.goal) }
        let beforeFirst = log.firstDay.map { d.date < Calendar.current.startOfDay(for: $0) } ?? false
        if !d.counted || beforeFirst || (!d.active && excused.excludes(d.date)) {
            return Day(key: d.key, date: d.date, states: Array(repeating: .excused, count: 5), goal: log.goal)
        }
        let states = (0..<5).map { i -> PrayerState? in d.marks[i].state(end: d.slots[i]?.end, now: now, noTime: d.slots[i]?.noTime ?? false) }
        let recorded = d.active || d.key == todayKey || d.marks.contains(.excused)
        guard recorded else { return Day(key: d.key, date: d.date, states: nil, goal: log.goal) }
        // A recorded day with a row missing (the app never made it): unmarked and over, or still to come today.
        return Day(key: d.key, date: d.date, states: states.map { $0 ?? (d.key == todayKey ? .toCome : .notMarked) }, goal: log.goal)
    }

    /// The week holding `date`.
    static func week(containing date: Date, in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> Week {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .map { day($0, in: log, excused: excused, now: now) }
        let current = cal.isDate(start, equalTo: today(now).start, toGranularity: .weekOfYear)
        return Week(start: start, days: days, isCurrent: current, goal: log.goal)
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
        let r = strongRun(in: weeks(in: log, excused: excused, now: now))
        return (r.current, r.best)
    }

    /// The strong-week streak from the weeks (oldest first): the run going now, the best, and the best run's first day to
    /// its last week's last day (the latest of equal ones), for lighting it on Your weeks.
    struct StrongRun: Equatable {
        var current = 0, best = 0
        var bestDays: ClosedRange<Date>?
    }
    static func strongRun(in all: [Week]) -> StrongRun {
        var r = StrongRun()
        var start: Date?
        for w in all where !w.isCurrent {
            if w.excusedWeek { continue }
            guard w.strong else { r.current = 0; start = nil; continue }
            if r.current == 0 { start = w.start }
            r.current += 1
            if r.current >= r.best, let start, let last = w.days.last?.date {
                r.best = r.current
                r.bestDays = start...last
            }
        }
        return r
    }

    /// Your usual week: the median of your last 8 finished weeks' counts at your step, weeks without a gap in the record only
    /// (nil before there are 3). The comparison Journey shows instead of last week (Strava's card made normal weeks feel bad).
    static func usualWeek(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> Int? {
        let list = weeks(in: log, excused: excused, now: now).filter { !$0.isCurrent && $0.noRecordDays == 0 && !$0.excusedWeek }.suffix(8)
        guard list.count >= 3 else { return nil }
        let sorted = list.map(\.met).sorted()
        return sorted[sorted.count / 2]
    }

    /// "Your typical week": the median week at your step of your first 8 recorded weeks, and of your last 8 (nil until 16).
    static func typicalWeek(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> (then: Int, now: Int)? {
        typicalWeek(in: weeks(in: log, excused: excused, now: now))
    }
    static func typicalWeek(in all: [Week]) -> (then: Int, now: Int)? {
        let list = all.filter { !$0.isCurrent && $0.noRecordDays == 0 && !$0.excusedWeek }
        guard list.count >= 16 else { return nil }
        func median(_ w: ArraySlice<Week>) -> Int { let s = w.map(\.met).sorted(); return s[s.count / 2] }
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
        /// The step the counts are at (Your goal).
        var goal: PrayerGoal = .inWindow
        /// Met the step, of the days it was asked ("before Closing 4 of 6" — `goal.countWords`).
        var met: Int { last7.compactMap { $0 }.filter(goal.meets).count }
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
            return PrayerRecent(name: name, last7: [], goal: log.goal, usualShare: nil, bestMonth: nil, window: nil)
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
        return PrayerRecent(name: name, last7: last7, goal: log.goal, usualShare: usual, bestMonth: best, window: window)
    }
}

// MARK: - Nudges along the ladder (plan-v3 §16; owner, 2026-10-21)

extension PrayerMetrics {
    /// The Sunday card's offer: one step up after 3 strong weeks running at your step, one step down after 2 fully logged
    /// weeks running that weren't (owner: "B but instead of 3 weeks make it two weeks maybe"). A week with a gap in its
    /// record or fully excused says nothing either way (no record isn't missed). Never two steps, never on its own.
    enum GoalOffer: Equatable {
        case up(PrayerGoal), down(PrayerGoal)
        var goal: PrayerGoal { switch self { case .up(let g), .down(let g): g } }
    }
    static let stepUpWeeks = 3
    static let stepDownWeeks = 2

    /// The offer for this week, if any: only on the week's first day, once per week (`GoalOffers.answered`).
    static func goalOffer(in log: JourneyLog, excused: Excused.Days = Excused.Days(), now: Date = Date()) -> GoalOffer? {
        let cal = Calendar.current
        let todayStart = today(now).start
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start,
              cal.isDate(weekStart, inSameDayAs: todayStart),
              !GoalOffers.answered(weekStart) else { return nil }
        return offer(after: weeks(in: log, excused: excused, now: now), goal: log.goal)
    }

    /// The rule itself, from the weeks (any day of the week — the Sunday gate is `goalOffer`'s).
    static func offer(after all: [Week], goal: PrayerGoal) -> GoalOffer? {
        let finished = all.filter(\.finished).filter { !$0.excusedWeek }
        if let up = goal.up, finished.count >= stepUpWeeks, finished.suffix(stepUpWeeks).allSatisfy(\.strong) {
            return .up(up)
        }
        if let down = goal.down, finished.count >= stepDownWeeks,
           finished.suffix(stepDownWeeks).allSatisfy({ !$0.strong && $0.noRecordDays == 0 }) {
            return .down(down)
        }
        return nil
    }

    /// The card's words for an offer (the look and the placement are Zoe's).
    static func offerWords(_ offer: GoalOffer, from goal: PrayerGoal) -> (line: String, yes: String) {
        switch offer {
        case .up(let next):
            // The aims, not the bare names: "aim for the Middle" read like praying in the Middle (owner, 2026-10-21, on "by the
            // Middle"). Was "You've met In its window 3 weeks running. Want to aim for the Middle?"
            ("You've met your goal, \(goal.aim), \(stepUpWeeks == 3 ? "three" : "\(stepUpWeeks)") weeks running. Want to aim for \(next.aim)?", "Try it")
        case .down(let next):
            // Their goal said whole, so the step down doesn't read as arbitrary (owner, 2026-10-21; was "In its window has
            // been a stretch lately").
            ("Your goal is \(goal.aim). The last \(stepDownWeeks == 2 ? "two" : "\(stepDownWeeks)") weeks fell short of it. For now, want to aim for \(next.aim), and work back up?",
             "Make it \(next.stepName)")
        }
    }

    /// The mid-week line, when this week can't be a strong one any more (encouragement only — the step never moves
    /// mid-week; owner picked B). nil while it still can, and on a week that's over. It names their goal (owner,
    /// 2026-10-21: "explain in regards to their goal"; was "This week won't be a strong one").
    static func midweekLine(_ week: Week) -> String? {
        guard week.isCurrent, !week.stillPossible, week.toCome > 0 else { return nil }
        let n = week.toCome
        return "Your goal this week, \(week.goal.aim), is out of reach now. You've still got \(n) \(n == 1 ? "prayer" : "prayers") left, so make \(n == 1 ? "it" : "them") count."
    }

    /// The line the morning after a missed prayer: yesterday's unmarked prayers — one by name, more as a count (owner,
    /// 2026-10-21, B: "it spans 3 lines at times. Maybe say the count"; was every name, "Fajr, Dhuhr, Asr and Maghrib"),
    /// then today's next one. nil when yesterday had none, or had no record (that's the fill-in question, not a miss).
    static func morningLine(in log: JourneyLog, excused: Excused.Days = Excused.Days(), next: (name: String, at: Date)?,
                            now: Date = Date()) -> String? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today(now).start),
              let states = day(yesterday, in: log, excused: excused, now: now).states else { return nil }
        let missed = (0..<5).filter { states[$0] == .notMarked }.map { JourneyLog.names[$0] }
        guard !missed.isEmpty else { return nil }
        let what = missed.count == 1 ? missed[0] : "\(missed.count) prayers"
        var line = "You missed \(what) yesterday. You can still make \(missed.count == 1 ? "it" : "them") up."
        if let next { line += " Today's \(next.name) is at \(next.at.formatted(date: .omitted, time: .shortened))." }
        return line
    }
}

/// Which weeks' Sunday offer was answered (either way), so it shows once.
enum GoalOffers {
    static let key = "goalOffers.answered"
    static func answered(_ weekStart: Date) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(PrayerNotificationID.dayKey(weekStart))
    }
    static func answer(_ weekStart: Date) {
        var keys = UserDefaults.standard.stringArray(forKey: key) ?? []
        keys.append(PrayerNotificationID.dayKey(weekStart))
        UserDefaults.standard.set(Array(keys.suffix(26)), forKey: key)
    }
}

/// The Salah bar's streak with the rethink (MetricsLook; outstanding.md row 1): strong weeks in a row and the best, from
/// `PrayerMetrics.strongWeeks` on the whole log at your goal — so the bar, Your goal and Journey can't disagree. Kept in
/// UserDefaults so the bar reads them at once; recounted off the main thread after a mark, an edit or the day turning, and
/// written only on change (each write re-renders the bar).
enum StrongWeekStreak {
    static let key = "strongWeeks"
    static let bestKey = "strongWeeks.best"
    /// The rules the kept count was made under (the goal and the fresh start): a count under other rules is recounted
    /// silently, never celebrated.
    static let rulesKey = "strongWeeks.rules"
    /// This week's count at your goal: what the bar says while there's no streak (owner, 2026-10-21, B: a bar reading
    /// "0 Strong Weeks" most nights puts a broken streak in front of people, which lowers repeat behaviour — Silverman &
    /// Barasch 2023; progress toward a near target is what moves people — Koo & Fishbach).
    static let thisWeekKey = "strongWeeks.thisWeek"
    /// Posted when the run grows past what was kept (a week finished strong, or a make-up made last week strong): the bar
    /// celebrates it. Never on the first count, a goal change or a fresh start.
    static let grew = Notification.Name("strongWeeks.grew")

    @MainActor static func refresh(container: ModelContainer) async {
        let ranges = Excused.ranges
        let log = await JourneyLog.load(container: container, ranges: ranges)
        guard !Task.isCancelled else { return }   // a newer count is on its way
        let counted = PrayerMetrics.strongWeeks(in: log, excused: Excused.Days(ranges))
        let now = Date()
        let thisWeek = PrayerMetrics.week(containing: PrayerDay.date(for: now), in: log, excused: Excused.Days(ranges), now: now).met
        let rules = "\(log.goal.rawValue)|\(log.countsFrom.map(PrayerNotificationID.dayKey) ?? "")"
        let d = UserDefaults.standard
        let kept = d.string(forKey: rulesKey) == rules ? d.object(forKey: key) as? Int : nil
        if d.object(forKey: key) as? Int != counted.current { d.set(counted.current, forKey: key) }
        if d.object(forKey: bestKey) as? Int != counted.best { d.set(counted.best, forKey: bestKey) }
        if d.string(forKey: rulesKey) != rules { d.set(rules, forKey: rulesKey) }
        if d.object(forKey: thisWeekKey) as? Int != thisWeek { d.set(thisWeek, forKey: thisWeekKey) }
        if let kept, counted.current > kept { NotificationCenter.default.post(name: grew, object: nil) }
    }
}
