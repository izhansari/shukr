import SwiftUI
import SwiftData

// Journey (owner, 2026-10-15; spec board/mocks/journey/spec.md, mock-ups v5): one true prayer log. Moments and Insights
// become one place — the month as a calendar of five dots a day (or the grid of grades), the card with the month's ring and
// the streaks, each day's own page. Phase 1 = the log: this screen, the day page, the entry points; Insights retired.
// Rules: a day counts once it has a mark (an "active day"); rates count active days only; excused prayers are never due.

extension Notification.Name {
    /// A prayer was marked, unmarked or edited (anywhere: the Salah page, Journey, a widget / watch mark reconciled): its
    /// pages read their rows again. Post it through `JourneyChange.post()`.
    static let journeyChanged = Notification.Name("journeyChanged")
}

/// One `.journeyChanged` per change: every mark, unmark and time edit posts here, and the posts of one turn of the main
/// thread go out as one (a mark from Journey runs the view model's path, which posts, and then Journey's own).
/// A mark on the Salah page posted nothing, and Journey in the pager kept its old numbers until a relaunch (sim,
/// 2026-10-18). Journey reads it only while it's on screen; under another page it marks itself dirty for the way back.
enum JourneyChange {
    /// Main thread only (every mark path runs there).
    nonisolated(unsafe) private static var pending = false
    static func post() {
        assert(Thread.isMainThread)
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async {
            pending = false
            NotificationCenter.default.post(name: .journeyChanged, object: nil)
        }
    }
}

/// ☰ → Journey and the day page's "Journey ›" (pushed on the root stack, as Moments).
/// Who writes it: `open` — ☰'s Journey row, the day page's "Journey ›" (SalahLook), What's new's "Open in shukr"
/// ("insights", "journey"), `-demoLand journey`, `-demoJourney` / `-demoJourneyFlightRun`; `makeUpAsked` — the ring's
/// make-up pill, the missed face's "See all ›" (mainCircle.swift) and the morning line: To make up pushed straight from the
/// Salah page, one push, back to where you were (owner, 2026-10-21, on Journey then To make up sliding in one after the other:
/// "it double hops pages. fix that"); `open` + `makeUp` was that double hop and stays only for a caller not yet moved. Who
/// reads them: PrayerTimesView's `navigationDestination`s (the pushes) and its `somethingCovers` / `clearCovers` (a widget
/// open closes them first); `makeUp` only JourneyPage, which clears it once it has opened To make up (`takeMakeUp`).
@MainActor @Observable final class JourneyPresenter {
    static let shared = JourneyPresenter()
    var open = false
    /// Asked for To make up on its own (the callers set this): the Salah page reads its list first, then pushes it
    /// (`makeUpOnly`), so the page arrives full — pushed empty it read "0 · All caught up" and counted up.
    var makeUpAsked = false
    /// To make up on its own, pushed from the Salah page (no Journey under it).
    var makeUpOnly = false
    /// Open and go straight on to To make up (the day page's "N to make up ›" pill, DayMakeUpPill).
    var makeUp = false
}

/// Every prayer day's five marks, read once from the rows (`build`). Days are keyed "YYYY-MM-DD" (the prayer day).
struct JourneyLog {
    enum Mark: Equatable {
        case done(Double)
        /// Its window ended unmarked.
        case missed
        /// Not over yet (today).
        case toCome
        /// Excused Mode covered it: never due.
        case excused
        /// No row (the app wasn't opened that day).
        case none

        var done: Bool { if case .done = self { true } else { false } }
        var score: Double? { if case .done(let s) = self { s } else { nil } }
        var inTime: Bool { (score ?? 0) >= PrayerScoring.inWindowFloor - 0.0001 && done }
    }

    struct Day {
        let key: String
        let date: Date
        /// Fajr … Isha.
        var marks: [Mark] = Array(repeating: .none, count: 5)
        /// Each prayer's window and when it was marked (the grid's one line).
        var slots: [Slot?] = Array(repeating: nil, count: 5)

        /// The goal it's judged by and whether it's on or after the fresh start (PrayerGoal.swift), set as the log is built.
        var goal: PrayerGoal = .prayed
        var counted = true

        var prayed: Int { marks.filter(\.done).count }
        /// Prayers that met the goal.
        var metCount: Int { marks.filter { if case .done(let s) = $0 { goal.meets(score: s) } else { false } }.count }
        /// A day counts once anything was marked (spec: active day).
        var active: Bool { prayed > 0 }
        /// Due = prayed or missed; to come and excused never are.
        var due: Int { marks.filter { $0.done || $0 == .missed }.count }
        var inTime: Int { marks.filter(\.inTime).count }
        var excused: Int { marks.filter { $0 == .excused }.count }
        /// Everything due was prayed: an excused prayer counts as done, on a day something was marked (the card's rule,
        /// `YourJourneyStats.kind`; spec month-fifths). Without `active` a fully excused day would count and lose its badge.
        var allFive: Bool { active && prayed + excused == 5 }
        /// Every prayer met the goal (an excused one counts): Journey's green day (it was all five in time).
        var metGoal: Bool { active && metCount + excused == 5 }
        /// Every prayer not prayed was excused (the pause badge instead of dots).
        var excusedDay: Bool { marks.contains(.excused) && marks.allSatisfy { $0 == .excused || $0.done } && !allFive }

        /// Today before its last prayer (its tile's shade can still move, so it never sets anyone's range).
        var unfinished: Bool { marks.contains(.toCome) }
        /// A tile's strength, 0…100: the mean score of the prayers that were due — a missed one 0, an excused one or one
        /// still to come not counted. Not the day page's number (that's `dayScore`, the five ÷ 5).
        var tileScore: Int {
            guard due > 0 else { return 0 }
            return Int((marks.reduce(0) { $0 + ($1.score ?? 0) } / Double(due) * 100).rounded())
        }
        /// With the rethink (MetricsLook) a tile's strength is its place in the day order instead (`rankKey`: prayed, then
        /// in its window, then fewest in Closing — no score), 0…215; a prayer still to come counts as at its best, as
        /// `tileKind` reads it.
        var tileOrder: Int {
            let open = marks.filter { $0 == .toCome }.count
            let k = rankKey
            return (k.prayed + open) * 36 + (k.inTime + open) * 6 + k.notClosing
        }
        /// What a tile is shaded by: `tileOrder` with MetricsLook, else `tileScore`.
        var tileStrength: Int { MetricsLook.on ? tileOrder : tileScore }
        /// The kind a tile draws: a finished day's own; today, before its last prayer, by what's been due so far — one
        /// still to come is neither missed nor late (owner, 2026-10-16: "make it so that the current day tile doesn't look
        /// gray").
        var tileKind: YourJourneyStats.Kind {
            guard unfinished, active else { return YourJourneyStats.kind(self) }
            let open = marks.filter { $0 == .toCome }.count
            if metCount + excused + open == 5 { return .metGoal }
            if prayed + excused + open == 5 { return .allFive }
            return .some
        }
    }

    struct Slot {
        let start: Date
        let end: Date
        let markedAt: Date?
        let jumuah: Bool
        /// The masjid it was marked at, if any (Your journey's "First prayer at a masjid").
        var masjid: String? = nil
        /// Prayed in its time with no clock recorded (MarkKind.timeUnknown): drawn in its own colour, never placed in its
        /// window.
        var noTime = false
    }

    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    var days: [String: Day] = [:]
    /// Which build this is (each load makes a new one): views that draw from the log compare this, not its days.
    var version = UUID()
    /// The first day with a mark: Journey starts there.
    var firstDay: Date?
    /// Someone who has used Excused Mode sees its key and badges (spec: only for users of it).
    var usesExcused = false
    /// The fresh start's day when the log was built (nil: none): days before it are drawn dimmed and count for nothing.
    var countsFrom: Date?
    /// The goal its days were judged by. An empty log (a page's placeholder before the real one is built) is at your goal
    /// too: it read Prayed, and anything reading `goal` early counted at Prayed for those first frames (Zoe, 2026-10-21).
    var goal: PrayerGoal = PrayerGoal.current

    func day(_ date: Date) -> Day {
        let key = PrayerNotificationID.dayKey(date)
        let start = Calendar.current.startOfDay(for: date)
        // A day with no row is judged at the log's goal like the rest (its own default is Prayed).
        return days[key] ?? Day(key: key, date: start, goal: goal, counted: countsFrom.map { start >= $0 } ?? true)
    }


    /// The log built off the main thread, from its own context on the store (Frank's trace, 2026-10-15: `build` took
    /// 71–80 ms on the main thread on every open of Journey — the whole fetch of the prayer rows). Plain values come back.
    static func load(container: ModelContainer, ranges: [ExcusedRange], now: Date = Date()) async -> JourneyLog {
        await Task.detached(priority: .userInitiated) {
            build(in: ModelContext(container), ranges: ranges, now: now)
        }.value
    }

    @MainActor static func build(_ context: ModelContext, now: Date = Date()) -> JourneyLog {
        build(in: context, ranges: Excused.ranges, now: now)
    }

    static func build(in context: ModelContext, ranges: [ExcusedRange], now: Date = Date()) -> JourneyLog {
        var log = JourneyLog()
        let goal = PrayerGoal.current
        log.goal = goal
        log.countsFrom = PrayerStats.countsFrom
        log.usesExcused = !ranges.isEmpty
        guard let rows = try? context.fetch(FetchDescriptor<PrayerModel>()) else { return log }
        // One row per prayer per day, a completed row winning (onePerPrayer's rule).
        var kept: [String: PrayerModel] = [:]
        for row in rows {
            guard names.contains(row.name) else { continue }
            let id = row.dayKey + row.name
            if let k = kept[id], k.isCompleted, !row.isCompleted { continue }
            kept[id] = row
        }
        for row in kept.values {
            let key = row.dayKey
            guard let slot = names.firstIndex(of: row.name) else { continue }
            // The fresh start read once (log.countsFrom), not per row: a change mid-build gave a mixed log (audit #8).
            let dayStart = row.dayStart
            var day = log.days[key] ?? Day(key: key, date: dayStart, goal: goal, counted: log.countsFrom.map { dayStart >= $0 } ?? true)
            switch row.state(excusedRanges: ranges, now: now) {   // PrayerState: the one place that decides it
            case .excused: day.marks[slot] = .excused
            case .toCome: day.marks[slot] = .toCome
            case .notMarked: day.marks[slot] = .missed
            case .opening, .middle, .closing, .inTimeNoClock, .madeUp: day.marks[slot] = .done(row.numberScore ?? 0)
            }
            day.slots[slot] = Slot(start: row.startTime, end: row.endTime,
                                   markedAt: row.isCompleted ? row.markedTime : nil, jumuah: row.isJumuah,
                                   masjid: row.isCompleted && row.atMasjid ? row.mosqueName : nil,
                                   noTime: row.isCompleted && row.timeUnknown)
            log.days[key] = day
        }
        log.firstDay = log.days.values.filter(\.active).map(\.date).min()
        var m = log.firstDay.map(monthStart)
        let last = monthStart(now)
        while let start = m, start <= last {
            log.months[start] = log.monthFromDays(start)
            m = Calendar.current.date(byAdding: .month, value: 1, to: start)
        }
        log.tileRanks = ranks(log.days.values)
        // Day N and the rank both ways: since the fresh start (owner's pick, 2026-10-18: "#3 of 12 since your fresh
        // start") and over every day, for the card's lifetime view (Fable's audit #5: "Day 281 · 3rd of 12" read one each).
        let active = log.days.values.filter(\.active).sorted(by: { $0.date < $1.date })
        for (n, d) in active.enumerated() { log.dayNumbers[d.key] = n + 1 }
        for (n, d) in active.filter(\.counted).enumerated() { log.freshDayNumbers[d.key] = n + 1 }
        // Ordered prayed → in its time → fewest in Closing (prayer-metrics phase 3, plan-v3 §5b): no weights, so a day
        // with a missed prayer never outranks a complete one (the old ÷5 score put his Jul 16, Fajr missed, above Apr 1,
        // all five in time). Equal keys share a place.
        func rank(_ days: [Day]) -> [String: Int] {
            let ranked = days.filter { !$0.unfinished }.map { ($0.key, $0.rankKey) }.sorted { $0.1 > $1.1 }
            var out: [String: Int] = [:]
            for (i, r) in ranked.enumerated() { out[r.0] = i > 0 && ranked[i - 1].1 == r.1 ? out[ranked[i - 1].0] : i + 1 }
            return out
        }
        log.dayRanks = rank(active.filter(\.counted))
        log.rankedDays = log.dayRanks.count
        log.lifetimeDayRanks = log.countsFrom == nil ? log.dayRanks : rank(active)
        return log
    }

    /// The month's numbers over its active days (spec: rates over active days only).
    struct Month {
        var prayed = 0, due = 0, inTime = 0, metGoalDays = 0, allFiveDays = 0, toMakeUp = 0, activeDays = 0
        /// The scores of the prayers due (a missed one adds 0).
        var scoreSum = 0.0
        /// The average score of the prayers due, 0…100 (nil before anything's due).
        var averageScore: Int? { due == 0 ? nil : Int((scoreSum / Double(due) * 100).rounded()) }
        /// Per prayer (Fajr … Isha): prayed and due.
        var perPrayer = Array(repeating: (prayed: 0, due: 0), count: 5)
    }

    /// Each month's numbers, worked out once as the log is built (off the main thread): the month page and the year read
    /// them on every body pass (his 13 Pro Max, 2026-10-16: ~450 ms over a test's three passes, 30 ms of each year open).
    private var months: [Date: Month] = [:]

    func month(_ start: Date) -> Month { months[start] ?? monthFromDays(start) }

    /// Per tile kind, each score 0…100's place among this user's own finished days of that kind (0 their lowest, 1 their
    /// best; equal scores share it) — the heat map's scale, over the whole history so a day has one shade on the card and
    /// in the year (owner, 2026-10-17, his tuner: "Your ranks"; "It shouldn't be a totalitarian, everyone, whoever gets an
    /// 80 gets this color shade"). Built once with the log; a tile reads one entry.
    private var tileRanks: [YourJourneyStats.Kind: [Double]] = [:]

    /// Which day of the journey it was: the nth day with a mark (nil: nothing marked that day).
    private var dayNumbers: [String: Int] = [:]
    /// The same, from the fresh start (no number for a day before it).
    private var freshDayNumbers: [String: Int] = [:]
    /// From the fresh start (the card's default), or over every day (its lifetime view; the map).
    func dayNumber(_ date: Date, lifetime: Bool = false) -> Int? {
        (lifetime || countsFrom == nil ? dayNumbers : freshDayNumbers)[PrayerNotificationID.dayKey(date)]
    }

    /// Where a day ranks among the finished days with a mark, by the day page's score (owner, 2026-10-17: "the rank of that
    /// day across all of our days … rank number 105 out of 280"): equal scores share a rank (two 100s are both 1st). Today
    /// before its last prayer isn't ranked (its score is still climbing).
    private var dayRanks: [String: Int] = [:]
    private(set) var rankedDays = 0
    /// Over every day (the card's lifetime view).
    private var lifetimeDayRanks: [String: Int] = [:]
    func dayRank(_ date: Date, lifetime: Bool = false) -> Int? {
        (lifetime ? lifetimeDayRanks : dayRanks)[PrayerNotificationID.dayKey(date)]
    }
    func rankedCount(lifetime: Bool) -> Int { lifetime ? lifetimeDayRanks.count : rankedDays }

    /// A tile's place on its kind's scale, 0…1 (1 with nothing to compare against yet).
    func tileRank(_ d: Day) -> Double {
        tileRanks[d.tileKind]?[min(max(d.tileStrength, 0), Self.tileScale)] ?? 1
    }

    /// The top of `tileStrength` (`tileOrder`'s; a score's is 100).
    private static let tileScale = 215

    private static func ranks(_ days: Dictionary<String, Day>.Values) -> [YourJourneyStats.Kind: [Double]] {
        var scores: [YourJourneyStats.Kind: [Int]] = [:]
        for d in days where d.active && !d.unfinished { scores[YourJourneyStats.kind(d), default: []].append(d.tileStrength) }
        return scores.mapValues { list in
            let mine = list.sorted()
            var table = [Double](repeating: 1, count: tileScale + 1)
            // Your days below this score out of every day below your best: not a mid-rank (that put a best day many
            // share at ~70 %).
            let top = mine.last ?? 0
            let underTop = mine.prefix { $0 < top }.count
            guard underTop > 0 else { return table }
            var i = 0
            for s in 0...tileScale {
                while i < mine.count, mine[i] < s { i += 1 }
                table[s] = min(1, Double(i) / Double(underTop))
            }
            return table
        }
    }

    private func monthFromDays(_ start: Date) -> Month {
        var m = Month()
        for date in Self.daysOf(month: start) {
            let d = day(date)
            guard d.active else { continue }
            m.activeDays += 1
            m.prayed += d.prayed
            m.due += d.due
            m.inTime += d.inTime
            if d.metGoal { m.metGoalDays += 1 }
            if d.allFive { m.allFiveDays += 1 }
            for (i, mark) in d.marks.enumerated() {
                m.scoreSum += mark.score ?? 0
                if mark.done { m.perPrayer[i].prayed += 1 }
                if mark.done || mark == .missed { m.perPrayer[i].due += 1 }
                if mark == .missed { m.toMakeUp += 1 }
            }
        }
        return m
    }

    static func daysOf(month start: Date) -> [Date] {
        let cal = Calendar.current
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    static func monthStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }
}

// MARK: - The page

/// The card's two day counts light their days up and dim the rest (as Insights did — owner: it helps most in the grid).
enum JourneyHighlight: Equatable {
    case metGoal, allFive
    /// The month's legend (owner, 2026-10-16: "In time · With Qaza · Incomplete … tapping any one focuses those rings";
    /// the goal's words since 2026-10-18): all five prayed but under the goal; a day with prayers that isn't finished.
    case belowGoal, incomplete
    func matches(_ d: JourneyLog.Day) -> Bool {
        switch self {
        case .metGoal: d.metGoal
        case .allFive: d.allFive
        case .belowGoal: d.allFive && !d.metGoal
        case .incomplete: d.active && !d.allFive
        }
    }
}

extension JourneyLog.Day {
    /// The mean of its five scores, an unprayed one 0, 0…100.
    var dayScore: Int { Int((marks.reduce(0) { $0 + ($1.score ?? 0) } / 5 * 100).rounded()) }
    /// How it ranks against other days: prayed, then in its time, then fewest in Closing (an excused prayer counts as
    /// done, as `allFive` does). Compared as a tuple, largest first.
    var rankKey: RankKey {
        let closing = (0..<5).filter { i in
            slots[i]?.noTime != true && (marks[i].score.map { PrayerScoring.grade(for: $0) == .late } ?? false)
        }.count   // a no-time mark claims no third
        return RankKey(prayed: prayed + excused, inTime: inTime + excused, notClosing: 5 - closing)
    }
    struct RankKey: Comparable {
        let prayed: Int, inTime: Int, notClosing: Int
        static func < (a: RankKey, b: RankKey) -> Bool { (a.prayed, a.inTime, a.notClosing) < (b.prayed, b.inTime, b.notClosing) }
    }
}

struct JourneyPage: View {
    /// In the pager (JourneyPagerPage): whether it's the page showing. It stays built there, so appearing doesn't say it; nil
    /// when pushed.
    var visible: Bool? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    /// Journey's numbers live in JourneyStore (the log, the card's stats, the header ring, To make up's count).
    private var store: JourneyStore { .shared }
    private var log: JourneyLog { store.log ?? JourneyLog() }
    private var stats: YourJourneyStats? { store.stats }
    private var scores: (score: Int?, strongest: String?)? { store.headerScores }
    /// The same over every day, while a fresh start is on: the ring follows the header's ⇄ (Fable's audit #5).
    private var lifetimeScores: (score: Int?, strongest: String?)? { store.lifetimeHeaderScores }
    private var makeUpTotal: Int? { store.makeUpTotal }
    /// The store reads off the main thread; a change while another page is over this one waits for its return (`dirty`) —
    /// no rebuild under To make up on every Made up.
    @State private var onScreen = false
    @State private var appeared = false
    @State private var dirty = false
    @State private var openDay: JourneyDayRoute?
    @State private var openMonth: JourneyMonthRoute?
    /// The week card's ↗: Your weeks pushed (owner, 2026-10-22: "make expanding the top right button of the card just be a
    /// push page instead, so that the pager works easier" — it grew out of the card in place).
    @State private var expanded: JourneyMonthRoute?
    @State private var showMoments = false
    @State private var showMakeUp = false
    /// To make up opens on This week (the week ring's "Make up ›"); every other way in opens on All weeks.
    @State private var makeUpWeek = false
    @State private var showScores = false
    /// Prayer scores zooms out of the header's ring and back into it (iOS's zoom transition: the way back follows the finger).
    @Namespace private var scoresZoom
    @State private var showMilestones = false
    /// Your goal, pushed from its row (owner, 2026-10-21: "bring the your goal page into journey somewhere so its not tucked
    /// away in settings" → "Make it a list item for now"); Settings keeps its row too.
    @State private var showGoal = false
    @State private var goal = PrayerGoal.current
    /// The picked day's notes, photos, map and zikr, opened from the card's bottom — where the day page's back card opens
    /// them (owner, 2026-10-17: "we can use the same tap destinations as we do in the day ring's page for the flipped card").
    @State private var extraTap: JourneyExtraTap?
    /// The rows scroll (no room for five) and there's more below: the fade shows.
    @State private var rowsMore = true
    /// The This month row's measure (a hold on the row chooses it).
    /// Which of the page's four layouts is shown (`Self.fits`), and the room it was chosen for: the loosest whose content
    /// fits, found by stepping from the loosest while the shown one's content is taller than the room — one page built, not
    /// the four ViewThatFits built and measured on every update (perf #2). Kept per room, so a return to Journey (and the
    /// next one in this launch) opens on it at once.
    @State private var fit = 0
    @State private var fitRoom: CGFloat = 0
    @State private var fitted = false
    /// The shown layout's content height, last measured.
    @State private var needed: CGFloat = 0
    @MainActor private static var fitFor: [String: Int] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var today: Date { PrayerDay.start() }

    /// A day page opens only for a day that's over or has all five marked (it never shows live rows).
    private func opens(_ day: Date?) -> Bool {
        guard let day, let first = log.firstDay, day >= first, day <= today else { return false }
        return day < today || log.day(day).allFive
    }

    /// A small phone (the SE's 667 pt): the card's number at 42 pt, the rows 52 pt tall.
    private var small: Bool { UIScreen.main.bounds.height < 700 }

    var body: some View {
        let _ = JourneyPerf.body("page")
        // One screen (owner, 2026-10-16: "ideally, the journey page is a one-page item that doesn't move"): nothing scrolls
        // but the card's grid, which takes the room that's left. Where the rows don't fit under a 12-week card (an SE,
        // larger text), they scroll in their own area under it.
        let f = Self.fits[min(fit, Self.fits.count - 1)]
        // The room is read from what can't grow (an empty view takes exactly what it's offered; the page's own flexible frame
        // took its content's height when that was taller, so nothing ever looked too tall — the helper's check). The page
        // is offered the whole room, as ViewThatFits offered the one it chose: the card's grid grows into what's left.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room in
                guard abs(room - fitRoom) > 0.5 else { return }
                fitRoom = room
                refit()
            }
            .overlay(alignment: .top) {
                home(rowHeight: f.row ?? (small ? 52 : 58), tight: f.tight, rowsScroll: f.scroll)
                    .opacity(fitted ? 1 : 0)   // the first time for this room, until the one that fits is found (a frame or two)
            }
            .onChange(of: typeSize) { _, _ in refit() }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
        // A month opens in place from the card (or This month), its days grow into the day page (JourneyTransitions.swift).
        .journeyMonthHost(month: $openMonth, log: log, stats: stats)
        .navigationDestination(isPresented: $showMoments) { MemoriesPage() }
        .navigationDestination(isPresented: $showMakeUp) {
            JourneyMakeUpPage(month: JourneyLog.monthStart(today), startWeek: makeUpWeek)
        }
        .onChange(of: showMakeUp) { _, open in if !open { makeUpWeek = false } }
        .navigationDestination(isPresented: $showScores) {
            PrayerScoresPage().navigationTransition(.zoom(sourceID: "scores", in: scoresZoom))
        }
        .modifier(JourneyExtrasPresenter(tap: $extraTap))
        .navigationDestination(isPresented: $showGoal) { PrayerGoalPage() }
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in goal = PrayerGoal.current }
        .navigationDestination(isPresented: $showMilestones) {
            JourneyMilestonesPage(milestones: stats?.milestones ?? [], firstDay: log.firstDay, opens: { opens($0) })
        }
        .onAppear {
            appeared = true
            store.fillStats(today: today)
            arrive()
        }
        .onDisappear { appeared = false; onScreen = false }
        .onChange(of: visible) { _, _ in arrive() }
        .navigationDestination(item: $expanded) { route in
            JourneyExpandedPushed(log: log, stats: stats ?? YourJourneyStats(log: JourneyLog(), today: today), month: route.month)
        }
        .task {
            reload(first: true)   // read at once, even built ahead of a swipe, so it's ready when it's shown
            takeMakeUp()
        }
        .onChange(of: JourneyPresenter.shared.makeUp) { _, _ in takeMakeUp() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in reload() }
        .task(id: store.log?.version) { if MetricsLook.on { YourPrayersRecent.shared.read(store.log) } }
        #if DEBUG
        .task {
            guard !Self.demoDone else { return }   // once per launch, not on every return to the page
            Self.demoDone = true
            let args = ProcessInfo.processInfo.arguments
            // `-demoPrayerScores [Fajr]`: Prayer scores, a prayer opened when one is named.
            if let i = args.firstIndex(of: "-demoPrayerScores") {
                if args.indices.contains(i + 1), JourneyLog.names.contains(args[i + 1]) { PrayerScoresPage.demoPick = args[i + 1] }
                try? await Task.sleep(for: .seconds(0.6))
                showScores = true
            }
            if args.contains("-demoJourneyMakeUp") {
                try? await Task.sleep(for: .seconds(0.6))
                showMakeUp = true
            }
            // `-demoJourneyMonth N`: the month N back (0 = this one).
            if let i = args.firstIndex(of: "-demoJourneyMonth"), args.indices.contains(i + 1), let back = Int(args[i + 1]) {
                try? await Task.sleep(for: .seconds(0.6))
                let m = Calendar.current.date(byAdding: .month, value: -back, to: JourneyLog.monthStart(today)) ?? today
                openMonth = JourneyMonthRoute(month: JourneyLog.monthStart(m))
            }
            if let i = args.firstIndex(of: "-demoJourneyDay"), args.indices.contains(i + 1), let back = Int(args[i + 1]) {
                try? await Task.sleep(for: .seconds(0.6))
                openDay = JourneyDayRoute(date: Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today)
            }
        }
        #endif
    }

    /// All five rows under a growing card; then the same a little tighter (Frank's mock fit five 56 pt rows and 13 weeks at
    /// 402 × 874 — Bradley's check: a 17 Pro showed four); then the SE's 52 pt rows; only then rows that scroll under a
    /// 12-week card. (`row` nil: 58 pt, 52 on a small phone.)
    private static let fits: [(row: CGFloat?, tight: Bool, scroll: Bool)] = [(nil, false, false), (56, true, false), (52, true, false), (52, true, true)]
    private var fitKey: String { "\(Int(fitRoom))·\(typeSize)" }

    /// The shown layout's content is `height` tall in the page's `fitRoom`: taller, the next tighter one; fitting, that's the
    /// one (remembered for this room). Never back to a looser one but on a new room — no flip-flopping.
    private func checkFit(_ height: CGFloat) {
        needed = height
        guard fitRoom > 0, height > 0 else { return }
        if height > fitRoom + 0.5, fit < Self.fits.count - 1, Self.fitFor[fitKey] == nil {
            fit += 1
        } else if !fitted || Self.fitFor[fitKey] == nil {
            Self.fitFor[fitKey] = fit
            fitted = true
        }
    }

    /// A new room (or text size): the one remembered for it, else from the loosest again. The content's height only reports
    /// when it changes, so an unchanged layout is checked here against the last one.
    private func refit() {
        let known = Self.fitFor[fitKey]
        let next = known ?? 0
        fitted = known != nil
        if next != fit { fit = next } else { checkFit(needed) }
    }

    /// On screen now (appeared): what waited reloads.
    private func arrive() {
        onScreen = appeared && visible != false
        guard onScreen else { return }
        JourneyPerf.began("journey appears")
        if dirty { reload() }
    }

    /// Asked for To make up straight away (the day page's pill): on, once the page is shown to push from.
    private func takeMakeUp() {
        guard JourneyPresenter.shared.makeUp else { return }
        JourneyPresenter.shared.makeUp = false
        Task { @MainActor in
            for _ in 0..<30 where !onScreen { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .seconds(0.05))
            showMakeUp = true
        }
    }

    private func reload(first: Bool = false) {
        guard onScreen || first else { dirty = true; return }   // under another page, or paged away: read it on the way back
        dirty = false
        store.load(container: context.container, today: today)
    }
    #if DEBUG
    @MainActor private static var demoDone = false
    #endif

    // MARK: Home

    /// The title (Prayer scores' ring on its right), Your journey's card (D's: a week a row), then four rows: This month,
    /// To make up, Moments, Milestones (Journey on one screen, board/mocks/journey-v6/build-plan.md "A"). Before the first mark: the card says
    /// what will fill it, the rows are there, quiet.
    private func home(rowHeight: CGFloat, tight: Bool, rowsScroll: Bool) -> some View {
        JourneyPerf.body("home")
        let s = stats ?? YourJourneyStats(log: JourneyLog(), today: today)
        return VStack(alignment: .leading, spacing: 0) {
            header
            if rowsScroll {
                card(s, tight: tight).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                ScrollView(.vertical, showsIndicators: false) { rows(s, height: rowHeight) }
                    .scrollBounceBehavior(.basedOnSize)
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        geo.contentSize.height - (geo.contentOffset.y + geo.contentInsets.top) - geo.containerSize.height > 4
                    } action: { _, more in rowsMore = more }
                    // A fade over the last rows while there's more under them (the canvas's `.rows.more`); gone at the end.
                    // It used to fade only the empty padding below the last row, so nothing showed (Bradley's check).
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, rowsMore ? .clear : .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 34)
                        }
                    }
                    .padding(.top, 6)
            } else {
                card(s, tight: tight).padding(.top, tight ? 10 : 16)
                rows(s, height: rowHeight).fixedSize(horizontal: false, vertical: true).padding(.top, tight ? 6 : 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, tight ? 0 : 6)
        // Its content's own height, before the frame that would take it: the grid never shrinks below 12 weeks, so a
        // layout that doesn't fit is taller than the room (ViewThatFits' test); one that fits fills it exactly.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { checkFit($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The card: this week's ring (the prayer-metrics rethink, MetricsLook — owner's pick B, 2026-10-20: the calendar one tap
    /// down behind its ↗), else the weeks grid as built.
    @ViewBuilder private func card(_ s: YourJourneyStats, tight: Bool) -> some View {
        if MetricsLook.on {
            JourneyWeekCard(log: log, compact: small, tight: tight,
                            onExpand: { expanded = JourneyMonthRoute(month: $0, focus: false) },
                            onDay: { openDay = JourneyDayRoute(date: $0) }, opens: { opens($0) },
                            onMakeUp: { makeUpWeek = true; showMakeUp = true })
        } else {
            JourneyHomeCard(stats: s, log: log, compact: small, tight: tight,
                            onDay: { openDay = JourneyDayRoute(date: $0) }, opens: { opens($0) },
                            onMonth: { openMonth = JourneyMonthRoute(month: $0) },
                            onExpand: { openMonth = JourneyMonthRoute(month: $0, focus: false) },
                            onExtra: { extraTap = $0 })
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Journey").font(.system(size: 38, weight: .regular, design: .rounded))
                if let from = log.countsFrom, let first = log.firstDay {
                    // After a fresh start the card counts from it; a tap here shows lifetime instead, and back (owner,
                    // 2026-10-18: "i still want it to show lifetime maybe off a toggle somewhere"). Ink, no sage (Journey).
                    Button {
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeOut(duration: CircleMotion.quick)) { store.lifetime.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.lifetime
                                 ? "Lifetime, since \(first.formatted(.dateTime.month(.abbreviated).day().year()))"
                                 : "Since your fresh start, \(from.formatted(.dateTime.month(.abbreviated).day()))")
                                .contentTransition(.opacity)
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .regular))
                        }
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(store.lifetime ? "Shows since your fresh start" : "Shows lifetime")
                } else {
                    Text(log.firstDay.map { "Since \($0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))" }
                         ?? "It starts with your first prayer")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if !MetricsLook.on {
            // Prayer scores' way in (owner, 2026-10-18: "on the Journey page, just move the prayer score ring to the top right,
            // next to where it says Journey on the trailing side. Just leave that ring there, and that's our entrance into
            // the prayer scores") — its row is gone.
            Button {
                triggerSomeVibration(type: .light)
                showScores = true
            } label: {
                let ring = store.lifetime ? lifetimeScores ?? scores : scores
                JourneyMiniRing(score: ring?.strongest != nil ? ring?.score : nil, size: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "scores", in: scoresZoom)
            .accessibilityLabel(scores?.score.map { "Prayer scores, \($0)" } ?? "Prayer scores")
            }
        }
        .journeyFlightWords(.page)   // lifts away as a month opens (JourneyTransitions.swift)
    }

    private func rows(_ s: YourJourneyStats, height rowHeight: CGFloat) -> some View {
        let photos = PrayerPhotos.all().count
        let owed = makeUpTotal ?? 0
        let latest = s.milestones.first
        let recent = YourPrayersRecent.shared
        return VStack(spacing: 0) {
            if MetricsLook.on {
                JourneyHomeRow(title: "Your goal", line: "How early you aim to pray", height: rowHeight) {
                    Image(systemName: "target").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
                } value: {
                    Text(goal.title)
                } action: { showGoal = true }
                // Your prayers as a row with the others (owner, 2026-10-20: "looks weird to have the upper right ring so busy
                // on journey … you can get rid of it and make it a list item"); the page still zooms out of it.
                JourneyHomeRow(title: "Your prayers",
                               line: recent.asked > 0 ? "\(recent.inTime) of \(recent.asked) in their windows · last 7 days"
                                   : "Each prayer, lately",
                               height: rowHeight, quiet: recent.asked == 0) {
                    Image(systemName: "chart.bar").font(.system(size: 19, weight: .light)).foregroundStyle(.secondary)
                } value: {
                    EmptyView()
                } action: { showScores = true }
                .matchedTransitionSource(id: "scores", in: scoresZoom)
            }
            // The This month row went with the goal (owner, 2026-10-18: "I only kept it so i could toggle to see my stats.
            // I never used it for actually opening the month ever since we fixed the compact card").
            JourneyHomeRow(title: "To make up",
                           line: owed == 0 ? "Nothing to make up" : "Unmarked on days you used shukr",
                           height: rowHeight, quiet: owed == 0) {
                Image(systemName: "clock").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary)
            } value: {
                Text("\(owed)")
            } action: { showMakeUp = true }
            JourneyHomeRow(title: "Moments",
                           line: photos == 0 ? "Your prayer photos will be here" : "Your prayer photos",
                           height: rowHeight, quiet: photos == 0) {
                MomentsTileStack().scaleEffect(0.6, anchor: .leading).frame(width: 30, height: 26, alignment: .leading)
            } value: {
                Text("\(photos)")
            } action: { showMoments = true }
            JourneyHomeRow(title: "Milestones",
                           line: latest.map { "Latest: \($0.text), \($0.date.formatted(.dateTime.month(.abbreviated).day()))" }
                               ?? "Your first comes with your first prayer",
                           last: true, height: rowHeight, quiet: latest == nil) {
                Image(systemName: "star").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
            } value: {
                EmptyView()
            } action: { showMilestones = true }
        }
        .journeyFlightWords(.page)
    }
}

struct JourneyDayRoute: Hashable, Identifiable {
    let date: Date
    var id: Date { date }
}

/// Calendar | Grid (and To make up's <month> | All): a pressed capsule with the picked side raised (the soft look's switch).
struct JourneySwitch: View {
    let options: [(title: String, id: String)]
    /// The month and year's (owner, 2026-10-17: "the month and year switcher on this page looks really small").
    var large = false
    @Binding var selection: String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { side($0.title, $0.id) }
        }
        .padding(3)
        .background(NeuPressed(shape: Capsule(), radius: 3, offset: 2))
        .frame(height: large ? 44 : 34)
    }

    private func side(_ title: String, _ id: String) -> some View {
        Button {
            guard selection != id else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: 0.22)) { selection = id }
        } label: {
            Text(title)
                .font(.system(size: large ? 16 : 13, weight: selection == id ? .regular : .light, design: .rounded))
                .foregroundStyle(selection == id ? .primary : .secondary)
                .padding(.horizontal, large ? 22 : 12)
                .frame(maxHeight: .infinity)
                .background {
                    if selection == id { NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A grey disc with two white bars: the day was excused (only shown to someone who uses Excused Mode).
struct ExcusedDayBadge: View {
    var size: CGFloat = 9
    var body: some View {
        Circle().fill(Color(.systemGray3))
            .overlay {
                HStack(spacing: size * 0.13) {
                    Capsule().fill(.white).frame(width: size * 0.14, height: size * 0.42)
                    Capsule().fill(.white).frame(width: size * 0.14, height: size * 0.42)
                }
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Moments' symbol

/// Moments' pile in small (owner: as the mock-up and Explore's picture): three tilted squares — the newest photos, or
/// Explore's coloured stand-ins before there are any.
private struct MomentsTileStack: View {
    @State private var images: [UIImage] = []
    private static let standIns: [[Color]] = [
        [Color(red: 0.79, green: 0.64, blue: 0.42), Color(red: 0.42, green: 0.31, blue: 0.18)],
        [Color(red: 0.50, green: 0.66, blue: 0.79), Color(red: 0.18, green: 0.31, blue: 0.42)],
        [Color(red: 0.62, green: 0.78, blue: 0.66), Color(red: 0.24, green: 0.42, blue: 0.30)]
    ]
    private static let lies: [(angle: Double, x: CGFloat, y: CGFloat)] = [(-9, 0, 2), (6, 12, -1), (-2, 22, 1)]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<3, id: \.self) { i in
                square(i)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
                    .rotationEffect(.degrees(Self.lies[i].angle))
                    .offset(x: Self.lies[i].x, y: Self.lies[i].y)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            let keys = PrayerPhotos.all().suffix(3).map(\.key)
            var loaded: [UIImage] = []
            for key in keys { if let image = await PrayerPhotos.thumbnail(key) { loaded.append(image) } }
            images = loaded
        }
    }

    /// The newest photo on top (the last square drawn).
    @ViewBuilder private func square(_ i: Int) -> some View {
        let shift = 3 - images.count
        if i >= shift, images.indices.contains(i - shift) {
            Image(uiImage: images[i - shift]).resizable().scaledToFill()
        } else {
            LinearGradient(colors: Self.standIns[i], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - DEBUG: a seeded history

#if DEBUG
enum JourneySeed {
    /// `-demoJourneySeed`: ~100 earlier days of rows where there are none — mostly in time, Fajr often late, a few missed,
    /// one Qaza a week, Jumu'ah at a masjid on most Fridays, a 10-day break 60 days back (no rows, but four days opened and
    /// nothing marked — To make up must never list them). Sim only.
    @MainActor static func seedIfAsked(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoJourneySeed") else { return }
        let cal = Calendar.current
        let today = PrayerDay.start()
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>())) ?? []
        let taken = Set(rows.map(\.dayKey))
        // Start and end as hour, minute (Isha ends 11:59 PM).
        let windows: [(String, (Int, Int), (Int, Int))] = [
            ("Fajr", (5, 30), (6, 55)), ("Dhuhr", (13, 10), (16, 50)), ("Asr", (16, 50), (18, 45)),
            ("Maghrib", (18, 45), (20, 5)), ("Isha", (20, 5), (23, 59))
        ]
        var added = 0
        for back in 1...100 {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let key = PrayerNotificationID.dayKey(day)
            let opened = (60...63).contains(back)   // in the break: rows, nothing marked
            if taken.contains(key) || ((58...67).contains(back) && !opened) { continue }
            for (slot, w) in windows.enumerated() {
                guard let start = cal.date(bySettingHour: w.1.0, minute: w.1.1, second: 0, of: day),
                      let end = cal.date(bySettingHour: w.2.0, minute: w.2.1, second: 0, of: day) else { continue }
                let row = PrayerModel(name: w.0, startTime: start, endTime: end)
                row.prayerDayKey = key
                let length = end.timeIntervalSince(start)
                let h = (back * 7 + slot * 13) % 23   // a steady pseudo-random pattern
                let friday = cal.component(.weekday, from: day) == 6
                var at: Date?
                if slot == 0 {   // Fajr: often late, now and then missed
                    at = h < 3 ? nil : start.addingTimeInterval(length * (h < 12 ? 0.75 : 0.25))
                } else if h == 5 && slot == 2 {
                    at = end.addingTimeInterval(40 * 60)   // a Qaza Asr
                } else if h == 17 && slot == 4 && back % 3 == 0 {
                    at = nil   // a missed Isha
                } else {
                    at = start.addingTimeInterval(length * Double(h % 6) * 0.07)
                }
                if slot == 1 && friday && back % 14 != 0 && !opened { row.mosqueName = "Masjid Al-Noor" }
                if slot != 0 && !opened { row.latPrayedAt = 35.79 + Double(h) * 0.0005; row.longPrayedAt = -78.78 }
                if let at, !opened {
                    row.isCompleted = true
                    row.setPrayerScore(atDate: at)
                }
                context.insert(row)
                added += 1
            }
        }
        try? context.save()
        print("JOURNEY seeded \(added) rows")
    }
}
#endif

/// Your weeks pushed from the week card's ↗ (no flight): a day opens its page on top.
struct JourneyExpandedPushed: View {
    let log: JourneyLog
    let stats: YourJourneyStats
    let month: Date
    @State private var openDay: JourneyDayRoute?
    private static let openerID = UUID()

    var body: some View {
        JourneyExpandedPage(log: log, stats: stats, opened: month, focusOnOpen: false)
            .environment(\.journeyDayOpener, JourneyDayOpener(id: Self.openerID, open: { openDay = JourneyDayRoute(date: $0) }))
            .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
    }
}

/// Journey as the pager's right page (owner, 2026-10-22: "put this onto the right-hand side of the pager, and then put a door
/// into the settings page, into the top right of the journey page with a gear SF symbol"). Built once the Salah page has
/// rested after the opening, or at once when asked for, so the launch never pays for it; a 44 pt row on top, where a pushed
/// page's bar is, holds the gear (toolbar items don't draw on the root's hidden bar).
struct JourneyPagerPage: View {
    @Environment(SharedStateClass.self) private var sharedState
    @Environment(\.circleTheme) private var theme
    @State private var built = false

    var body: some View {
        Group {
            if built {
                JourneyPage(visible: sharedState.horizontalPage == .journey)
            } else {
                theme.surface.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    triggerSomeVibration(type: .light)
                    SettingsPresenter.shared.show()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .barGlass(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("journeyGear", $0) }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .task {
            _ = await CircleStage.shared.until(deadline: 8) { CircleStage.shared.restingPage != nil }
            try? await Task.sleep(for: .seconds(1.5))
            built = true
        }
        .onChange(of: sharedState.horizontalPage) { _, page in if page == .journey { built = true } }
    }
}
