import SwiftUI
import SwiftData

// Journey (owner, 2026-10-15; spec board/mocks/journey/spec.md, mock-ups v5): one true prayer log. Moments and Insights
// become one place — the month as a calendar of five dots a day (or the grid of grades), the card with the month's ring and
// the streaks, each day's own page. Phase 1 = the log: this screen, the day page, the entry points; Insights retired.
// Rules: a day counts once it has a mark (an "active day"); rates count active days only; excused prayers are never due.

/// ☰ → Journey and the day page's "Journey ›" (pushed on the root stack, as Moments).
@MainActor @Observable final class JourneyPresenter {
    static let shared = JourneyPresenter()
    var open = false
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

        var prayed: Int { marks.filter(\.done).count }
        /// A day counts once anything was marked (spec: active day).
        var active: Bool { prayed > 0 }
        /// Due = prayed or missed; to come and excused never are.
        var due: Int { marks.filter { $0.done || $0 == .missed }.count }
        var inTime: Int { marks.filter(\.inTime).count }
        var excused: Int { marks.filter { $0 == .excused }.count }
        /// Everything due was prayed: an excused prayer counts as done, on a day something was marked (the card's rule,
        /// `YourJourneyStats.kind`; spec month-fifths). Without `active` a fully excused day would count and lose its badge.
        var allFive: Bool { active && prayed + excused == 5 }
        var allInTime: Bool { active && inTime + excused == 5 }
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
        /// The kind a tile draws: a finished day's own; today, before its last prayer, by what's been due so far — one
        /// still to come is neither missed nor late (owner, 2026-10-16: "make it so that the current day tile doesn't look
        /// gray").
        var tileKind: YourJourneyStats.Kind {
            guard unfinished, active else { return YourJourneyStats.kind(self) }
            let open = marks.filter { $0 == .toCome }.count
            if inTime + excused + open == 5 { return .allInTime }
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
    }

    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    var days: [String: Day] = [:]
    /// The first day with a mark: Journey starts there.
    var firstDay: Date?
    /// Someone who has used Excused Mode sees its key and badges (spec: only for users of it).
    var usesExcused = false

    func day(_ date: Date) -> Day {
        let key = PrayerNotificationID.dayKey(date)
        return days[key] ?? Day(key: key, date: Calendar.current.startOfDay(for: date))
    }

    /// The last log built, shown at once while a fresh one is read (the page never opens blank).
    @MainActor static var last: JourneyLog?

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
            var day = log.days[key] ?? Day(key: key, date: row.dayStart)
            if row.isCompleted {
                day.marks[slot] = .done(row.numberScore ?? 0)
            } else if Excused.covers(start: row.startTime, end: row.endTime, in: ranges) {
                day.marks[slot] = .excused
            } else {
                day.marks[slot] = row.endTime > now ? .toCome : .missed
            }
            day.slots[slot] = Slot(start: row.startTime, end: row.endTime,
                                   markedAt: row.isCompleted ? row.timeAtComplete : nil, jumuah: row.isJumuah,
                                   masjid: row.isCompleted && row.atMasjid ? row.mosqueName : nil)
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
        for (n, d) in log.days.values.filter(\.active).sorted(by: { $0.date < $1.date }).enumerated() { log.dayNumbers[d.key] = n + 1 }
        let ranked = log.days.values.filter { $0.active && !$0.unfinished }.map { ($0.key, $0.dayScore) }.sorted { $0.1 > $1.1 }
        log.rankedDays = ranked.count
        for (i, r) in ranked.enumerated() { log.dayRanks[r.0] = i > 0 && ranked[i - 1].1 == r.1 ? log.dayRanks[ranked[i - 1].0] : i + 1 }
        return log
    }

    /// The month's numbers over its active days (spec: rates over active days only).
    struct Month {
        var prayed = 0, due = 0, inTime = 0, allInTimeDays = 0, allFiveDays = 0, toMakeUp = 0, activeDays = 0
        /// The scores of the prayers due (a missed one adds 0).
        var scoreSum = 0.0
        /// The average score of the prayers due, 0…100 (nil before anything's due).
        var averageScore: Int? { due == 0 ? nil : Int((scoreSum / Double(due) * 100).rounded()) }
        /// The day with the best score (the mean of its five, an unprayed one 0; the latest of a tie), 0…100.
        var bestDay: (date: Date, score: Int)?
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
    func dayNumber(_ date: Date) -> Int? { dayNumbers[PrayerNotificationID.dayKey(date)] }

    /// Where a day ranks among the finished days with a mark, by the day page's score (owner, 2026-10-17: "the rank of that
    /// day across all of our days … rank number 105 out of 280"): equal scores share a rank (two 100s are both 1st). Today
    /// before its last prayer isn't ranked (its score is still climbing).
    private var dayRanks: [String: Int] = [:]
    private(set) var rankedDays = 0
    func dayRank(_ date: Date) -> Int? { dayRanks[PrayerNotificationID.dayKey(date)] }

    /// A tile's place on its kind's scale, 0…1 (1 with nothing to compare against yet).
    func tileRank(_ d: Day) -> Double {
        tileRanks[d.tileKind]?[min(max(d.tileScore, 0), 100)] ?? 1
    }

    private static func ranks(_ days: Dictionary<String, Day>.Values) -> [YourJourneyStats.Kind: [Double]] {
        var scores: [YourJourneyStats.Kind: [Int]] = [:]
        for d in days where d.active && !d.unfinished { scores[YourJourneyStats.kind(d), default: []].append(d.tileScore) }
        return scores.mapValues { list in
            let mine = list.sorted()
            var table = [Double](repeating: 1, count: 101)
            // Your days below this score out of every day below your best: not a mid-rank (that put a best day many
            // share at ~70 %).
            let top = mine.last ?? 0
            let underTop = mine.prefix { $0 < top }.count
            guard underTop > 0 else { return table }
            var i = 0
            for s in 0...100 {
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
            if d.allInTime { m.allInTimeDays += 1 }
            if d.allFive { m.allFiveDays += 1 }
            let dayScore = Int((d.marks.reduce(0) { $0 + ($1.score ?? 0) } / 5 * 100).rounded())
            if dayScore >= (m.bestDay?.score ?? -1) { m.bestDay = (date, dayScore) }
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
    case allInTime, allFive
    /// The month's legend (owner, 2026-10-16: "In time · With Qaza · Incomplete … tapping any one focuses those rings"):
    /// all five with a Qaza among them; a day with prayers that isn't finished.
    case withQaza, incomplete
    /// The month's best-scored day(s): every day with that score, a tie lighting each (a tap on the average score — owner).
    case bestScore(Int)
    func matches(_ d: JourneyLog.Day) -> Bool {
        switch self {
        case .allInTime: d.allInTime
        case .allFive: d.allFive
        case .withQaza: d.allFive && !d.allInTime
        case .incomplete: d.active && !d.allFive
        case .bestScore(let score): d.active && d.dayScore == score
        }
    }
}

extension JourneyLog.Day {
    /// The mean of its five scores, an unprayed one 0, 0…100 (JourneyLog.Month.bestDay's measure).
    var dayScore: Int { Int((marks.reduce(0) { $0 + ($1.score ?? 0) } / 5 * 100).rounded()) }
}

struct JourneyPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @State private var log = JourneyLog.last ?? JourneyLog()
    /// Your journey's numbers (YourJourney.swift), worked out once per log, not per redraw.
    @State private var stats: YourJourneyStats?
    /// Prayer scores' row: the page's lifetime score and its strongest prayer (PrayerScores, read off the main thread).
    @State private var scores: (score: Int?, strongest: String?)?
    /// To make up's row: every unmarked prayer on a day shukr was used (the page's own count).
    @State private var makeUpTotal: Int?
    /// The log is read off the main thread (JourneyLog.load); a newer request drops an older result, and a change while
    /// another page is over this one waits for its return (`dirty`) — no rebuild under To make up on every Made up.
    @State private var loadToken = 0
    @State private var onScreen = false
    @State private var dirty = false
    @State private var openDay: JourneyDayRoute?
    @State private var openMonth: JourneyMonthRoute?
    @State private var showMoments = false
    @State private var showMakeUp = false
    @State private var showScores = false
    @State private var showMilestones = false
    /// The picked day's notes, photos, map and zikr, opened from the card's bottom — where the day page's back card opens
    /// them (owner, 2026-10-17: "we can use the same tap destinations as we do in the day ring's page for the flipped card").
    @State private var dayNotes: [DayFacts.Note]?
    @State private var dayPile: DayPileRoute?
    @State private var mapDay: Date?
    @State private var zikrDay: Date?
    /// The rows scroll (no room for five) and there's more below: the fade shows.
    @State private var rowsMore = true
    /// The This month row's measure (a hold on the row chooses it).
    @AppStorage(ThisMonthMeasure.key) private var measureRaw = ThisMonthMeasure.onTime.rawValue

    private var today: Date { PrayerDay.start() }

    /// A day page opens only for a day that's over or has all five marked (it never shows live rows).
    private func opens(_ day: Date?) -> Bool {
        guard let day, let first = log.firstDay, day >= first, day <= today else { return false }
        return day < today || log.day(day).allFive
    }

    /// A small phone (the SE's 667 pt): the card's number at 42 pt, the rows 52 pt tall.
    private var small: Bool { UIScreen.main.bounds.height < 700 }

    var body: some View {
        // One screen (owner, 2026-10-16: "ideally, the journey page is a one-page item that doesn't move"): nothing scrolls
        // but the card's grid, which takes the room that's left. Where the rows don't fit under a 12-week card (an SE,
        // larger text), they scroll in their own area under it.
        ViewThatFits(in: .vertical) {
            // All five rows under a growing card; then the same a little tighter (Frank's mock fit five 56 pt rows and 13
            // weeks at 402 × 874 — Bradley's check: a 17 Pro showed four); then the SE's 52 pt rows; only then rows that
            // scroll under a 12-week card.
            home(rowHeight: small ? 52 : 58, tight: false, rowsScroll: false)
            home(rowHeight: 56, tight: true, rowsScroll: false)
            home(rowHeight: 52, tight: true, rowsScroll: false)
            home(rowHeight: 52, tight: true, rowsScroll: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
        // A month opens in place from the card (or This month), its days grow into the day page (JourneyTransitions.swift).
        .journeyMonthHost(month: $openMonth, log: log)
        .navigationDestination(isPresented: $showMoments) { MemoriesPage() }
        .navigationDestination(isPresented: $showMakeUp) { JourneyMakeUpPage(month: JourneyLog.monthStart(today)) }
        .navigationDestination(isPresented: $showScores) { PrayerScoresPage() }
        .infoModal(isPresented: Binding(get: { dayNotes != nil }, set: { if !$0 { dayNotes = nil } }),
                   title: dayNotes?.count == 1 ? "Note" : "Notes", symbol: "text.quote", tint: .secondary) {
            DayNotesInfo(notes: dayNotes ?? [])
        }
        .fullScreenCover(item: $dayPile) { route in
            PrayerPhotoViewer(key: route.keys[0], pile: route.keys, rise: true) {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { dayPile = nil }
            }
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: Binding(get: { mapDay != nil }, set: { if !$0 { mapDay = nil } })) {
            LocationMapContentView(dayOnly: mapDay ?? today)
        }
        .navigationDestination(item: $zikrDay) { ZikrAreaPage(start: .dayOnly($0)) }
        .navigationDestination(isPresented: $showMilestones) {
            JourneyMilestonesPage(milestones: stats?.milestones ?? [], firstDay: log.firstDay, opens: { opens($0) })
        }
        .onAppear {
            onScreen = true
            if stats == nil { stats = YourJourneyStats(log: log, today: today) }
            if dirty { reload() }
        }
        .onDisappear { onScreen = false }
        .task {
            onScreen = true
            reload()
            // Asked for To make up straight away (the day page's pill): on, once the page is there to push from.
            if JourneyPresenter.shared.makeUp {
                JourneyPresenter.shared.makeUp = false
                try? await Task.sleep(for: .seconds(0.05))
                showMakeUp = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in reload() }
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

    private func reload() {
        guard onScreen else { dirty = true; return }   // under another page: read it on the way back
        dirty = false
        loadToken += 1
        let token = loadToken
        let container = context.container
        let ranges = Excused.ranges
        let day = today
        Task {
            let built = await JourneyLog.load(container: container, ranges: ranges)
            guard token == loadToken else { return }
            log = built
            JourneyLog.last = built
            stats = YourJourneyStats(log: built, today: day)
        }
        Task {
            let s = await PrayerScores.load(container: container, ranges: ranges)
            let open = await JourneyMakeUpPage.openCount(container: container)
            guard token == loadToken else { return }
            scores = (s.prayedScore, s.prayed > 0 ? s.ranked.first : nil)
            makeUpTotal = open
        }
    }
    #if DEBUG
    @MainActor private static var demoDone = false
    #endif

    // MARK: Home

    /// The title, Your journey's card (D's: a week a row), then five rows: This month, Prayer scores, To make up, Moments,
    /// Milestones (Journey on one screen, board/mocks/journey-v6/build-plan.md "A"). Before the first mark: the card says
    /// what will fill it, the rows are there, quiet.
    private func home(rowHeight: CGFloat, tight: Bool, rowsScroll: Bool) -> some View {
        let s = stats ?? YourJourneyStats(log: JourneyLog(), today: today)
        let card = JourneyHomeCard(stats: s, log: log, compact: small, tight: tight,
                                   onDay: { openDay = JourneyDayRoute(date: $0) }, opens: { opens($0) },
                                   onMonth: { openMonth = JourneyMonthRoute(month: $0) },
                                   onExtra: { tap in
                                       switch tap {
                                       case .notes(let n): dayNotes = n
                                       case .photos(let keys, let from):
                                           // No system slide: the pile rises on its own, the page behind fading in place.
                                           var quiet = Transaction()
                                           quiet.disablesAnimations = true
                                           withTransaction(quiet) { dayPile = DayPileRoute(keys: keys, from: from) }
                                       case .map(let d): mapDay = d
                                       case .zikr(let d): zikrDay = d
                                       }
                                   })
        return VStack(alignment: .leading, spacing: 0) {
            header
            if rowsScroll {
                card.fixedSize(horizontal: false, vertical: true).padding(.top, 10)
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
                card.padding(.top, tight ? 10 : 16)
                rows(s, height: rowHeight).fixedSize(horizontal: false, vertical: true).padding(.top, tight ? 6 : 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, tight ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Journey").font(.system(size: 38, weight: .regular, design: .rounded))
            Text(log.firstDay.map { "Since \($0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))" }
                 ?? "It starts with your first prayer")
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .journeyFlightWords(.page)   // lifts away as a month opens (JourneyTransitions.swift)
    }

    private func rows(_ s: YourJourneyStats, height rowHeight: CGFloat) -> some View {
        let photos = PrayerPhotos.all().count
        let owed = makeUpTotal ?? 0
        let latest = s.milestones.first
        return VStack(spacing: 0) {
            let measure = ThisMonthMeasure(rawValue: measureRaw) ?? .onTime
            JourneyHomeRow(title: "This month", line: "\(measure.title), so far", height: rowHeight,
                           quiet: s.thisMonth == nil) {
                Image(systemName: "calendar").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary)
            } value: {
                if let m = s.thisMonth { Text(measure.value(m)) }
            } action: { openMonth = JourneyMonthRoute(month: JourneyLog.monthStart(today)) }
            // Touch and hold: the four measures, each with its value and what it counts; the check sticks.
            .contextMenu {
                // A toggle per measure: its check, its value, and what it counts as the menu's second line.
                ForEach(ThisMonthMeasure.allCases) { m in
                    Toggle(isOn: Binding(get: { measureRaw == m.rawValue },
                                         set: { on in if on { withAnimation(.easeOut(duration: CircleMotion.quick)) { measureRaw = m.rawValue } } })) {
                        Text(s.thisMonth.map { "\(m.title) · \(m.value($0))" } ?? m.title)
                        Text(m.counts)
                    }
                }
            }
            JourneyHomeRow(title: "Prayer scores",
                           line: scores?.strongest.map { "\($0) is your strongest" } ?? "After a few prayers",
                           height: rowHeight, quiet: scores?.strongest == nil) {
                HStack(alignment: .bottom, spacing: 3.1) {
                    ForEach(Array([12.0, 17, 14, 19].enumerated()), id: \.offset) { _, h in
                        Capsule().fill(Color.primary.opacity(0.55)).frame(width: 3.4, height: h)
                    }
                }
                .frame(height: 22, alignment: .bottom)
            } value: {
                if let score = scores?.score, scores?.strongest != nil { JourneyMiniRing(score: score) }
            } action: { showScores = true }
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
