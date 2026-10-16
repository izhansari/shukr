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
        var allFive: Bool { prayed == 5 }
        var allInTime: Bool { inTime == 5 }
        /// Every prayer not prayed was excused (the pause badge instead of dots).
        var excusedDay: Bool { marks.contains(.excused) && marks.allSatisfy { $0 == .excused || $0.done } && !allFive }
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

    func month(_ start: Date) -> Month {
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
    /// The month's best day (a tap on the average score — owner).
    case bestDay(Date)
    func matches(_ d: JourneyLog.Day) -> Bool {
        switch self {
        case .allInTime: d.allInTime
        case .allFive: d.allFive
        case .bestDay(let date): Calendar.current.isDate(d.date, inSameDayAs: date)
        }
    }
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
    /// The title moves into the bar once it has scrolled under it (as the Zikr pages' `titleInBar`).
    @State private var titleShown = false

    private var today: Date { PrayerDay.start() }

    var body: some View {
        ScrollView {
            home
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, under in
            withAnimation(.easeOut(duration: 0.15)) { titleShown = under }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationTitle(titleShown ? "Journey" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
        .navigationDestination(item: $openMonth) { JourneyMonthPage(log: log, start: $0.month) }
        .navigationDestination(isPresented: $showMoments) { MemoriesPage() }
        .navigationDestination(isPresented: $showMakeUp) { JourneyMakeUpPage(month: JourneyLog.monthStart(today)) }
        .navigationDestination(isPresented: $showScores) { PrayerScoresPage() }
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

    /// Your journey's card leads; Prayer scores, To make up and Moments as three flat rows under it; the months; the
    /// milestones (Journey v6). Before the first mark: the card says what will fill it, the rows are there, quiet.
    private var home: some View {
        let s = stats ?? YourJourneyStats(log: JourneyLog(), today: today)
        let started = log.firstDay != nil
        return VStack(alignment: .leading, spacing: 0) {
            header
            JourneyHomeCard(stats: s).padding(.top, 18)
            rows(started: started).padding(.top, 14)
            if !s.monthRows.isEmpty {
                JourneyMonthsList(rows: s.monthRows) { m in openMonth = JourneyMonthRoute(month: m) }.padding(.top, 26)
            }
            if !s.milestones.isEmpty { JourneyMilestonesList(milestones: s.milestones).padding(.top, 26) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Journey").font(.system(size: 38, weight: .regular, design: .rounded))
            Text(log.firstDay.map { "Since \($0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))" }
                 ?? "It starts with your first prayer")
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func rows(started: Bool) -> some View {
        let photos = PrayerPhotos.all().count
        let owed = makeUpTotal ?? 0
        return VStack(spacing: 0) {
            JourneyHomeRow(title: "Prayer scores",
                           line: scores?.strongest.map { "\($0) is your strongest" } ?? "After a few prayers",
                           quiet: scores?.strongest == nil) {
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
                           quiet: owed == 0) {
                Image(systemName: "clock").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary)
            } value: {
                Text("\(owed)")
            } action: { showMakeUp = true }
            JourneyHomeRow(title: "Moments",
                           line: photos == 0 ? "Your prayer photos will be here" : "Your prayer photos",
                           last: true, quiet: photos == 0) {
                MomentsTileStack().scaleEffect(0.6, anchor: .leading).frame(width: 30, height: 26, alignment: .leading)
            } value: {
                Text("\(photos)")
            } action: { showMoments = true }
        }
    }
}

struct JourneyMonthRoute: Hashable, Identifiable {
    let month: Date
    var id: Date { month }
}

// MARK: - A month

/// A month (Journey v6): its name with ‹ › to the next month with prayers, "N days you marked a prayer", its three numbers in
/// one flat row between hairlines, and the five-dot calendar with its discs and key; a day opens the day page. Grade
/// colours behind the ··· in the bar (the canvas's pick: they moved here with the calendar).
struct JourneyMonthPage: View {
    let log: JourneyLog
    @State var start: Date
    @Environment(\.circleTheme) private var theme
    /// Grade colours on the calendar's dots. Off by default (decision journey-day-look B).
    @AppStorage("journey.grades") private var grades = false
    @State private var openDay: JourneyDayRoute?

    init(log: JourneyLog, start: Date) {
        self.log = log
        _start = State(initialValue: start)
    }

    private var today: Date { PrayerDay.start() }
    /// The months with a marked day, oldest first (‹ › skip the empty ones — a break's months).
    private var months: [Date] {
        guard let first = log.firstDay else { return [] }
        var out: [Date] = []
        var m = JourneyLog.monthStart(first)
        let last = JourneyLog.monthStart(today)
        while m <= last {
            if log.month(m).activeDays > 0 { out.append(m) }
            guard let next = Calendar.current.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return out
    }

    var body: some View {
        let numbers = log.month(start)
        let list = months
        let at = list.firstIndex(of: start)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(start.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 30, weight: .regular, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    step("chevron.left", to: at.flatMap { $0 > 0 ? list[$0 - 1] : nil }, label: "Previous month")
                    step("chevron.right", to: at.flatMap { $0 + 1 < list.count ? list[$0 + 1] : nil }, label: "Next month")
                }
                Text(numbers.activeDays == 1 ? "1 day you marked a prayer" : "\(numbers.activeDays) days you marked a prayer")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                HStack(alignment: .top, spacing: 0) {
                    fact("\(numbers.allInTimeDays)", "days all in time")
                    fact("\(numbers.allFiveDays)", "days with all five")
                    fact(numbers.averageScore.map { "\($0)" } ?? "–", "average score")
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .padding(.top, 22)
                JourneyCalendar(log: log, month: start, today: today, grades: grades, highlight: nil, compact: false) { open($0) }
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.3), value: grades)
                Text("Tap a day to open it.")
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .id(start)
            .transition(.opacity)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Grade colors", isOn: $grades)
                } label: {
                    Image(systemName: "ellipsis").accessibilityLabel("More")
                }
            }
        }
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
    }

    private func fact(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .thin, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A small raised disc with a plain chevron (owner: not the sage arrows); flat and faint when there's no month that way.
    private func step(_ symbol: String, to month: Date?, label: String) -> some View {
        Button {
            guard let month else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: CircleMotion.quick)) { start = month }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(month != nil ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.3))
                .frame(width: 34, height: 34)
                .background { if month != nil { NeuRaised(shape: Circle(), radius: 2.5, offset: 1.2) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(month == nil)
        .accessibilityLabel(label)
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        // Today opens only once it's over — all five marked (owner, 2026-10-15: the day page "doesn't show up in journey
        // unless the day is over or all 5 have been marked, so it never shows current prayers").
        guard date < today || log.day(date).allFive else { return }
        triggerSomeVibration(type: .light)
        openDay = JourneyDayRoute(date: date)
    }
}

struct JourneyDayRoute: Hashable, Identifiable {
    let date: Date
    var id: Date { date }
}

/// Calendar | Grid (and To make up's <month> | All): a pressed capsule with the picked side raised (the soft look's switch).
struct JourneySwitch: View {
    let options: [(title: String, id: String)]
    @Binding var selection: String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { side($0.title, $0.id) }
        }
        .padding(3)
        .background(NeuPressed(shape: Capsule(), radius: 3, offset: 2))
        .frame(height: 34)
    }

    private func side(_ title: String, _ id: String) -> some View {
        Button {
            guard selection != id else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: 0.22)) { selection = id }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: selection == id ? .regular : .light, design: .rounded))
                .foregroundStyle(selection == id ? .primary : .secondary)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background {
                    if selection == id { NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The calendar

/// The month as a calendar: each day five dots (Fajr … Isha), monochrome unless grade colours are on; a soft green disc
/// behind a day with all five in time, a grey one behind all five with a Qaza (decision journey-day-look B).
private struct JourneyCalendar: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    let grades: Bool
    let highlight: JourneyHighlight?
    let compact: Bool
    let onDay: (Date) -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    var body: some View {
        let cal = Calendar.current
        let days = JourneyLog.daysOf(month: month)
        let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
        let hasExcused = log.usesExcused && days.contains { log.day($0).marks.contains(.excused) }
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: compact ? 34 : 40) }
                ForEach(days, id: \.self) { date in
                    let day = log.day(date)
                    // A day the card lights up shows its grade colours whatever the switch (owner, as Insights did).
                    JourneyDayCell(day: day, date: date, today: today, first: log.firstDay,
                                   grades: grades || highlight?.matches(day) == true, usesExcused: log.usesExcused)
                        .opacity(highlight.map { $0.matches(day) ? 1 : 0.22 } ?? 1)
                        .frame(height: compact ? 34 : 40)
                        .contentShape(Rectangle())
                        .onTapGesture { onDay(date) }
                }
            }
            HStack(spacing: 16) {
                key(Circle().fill(Color.green.opacity(0.22)), "All five in time")
                key(Circle().fill(Color.primary.opacity(0.09)), "All five")
                if hasExcused { key(ExcusedDayBadge(size: 10), "Excused") }
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var weekdayLetters: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func key<V: View>(_ swatch: V, _ title: String) -> some View {
        HStack(spacing: 5) { swatch.frame(width: 12, height: 12); Text(title) }
    }
}

private struct JourneyDayCell: View {
    let day: JourneyLog.Day
    let date: Date
    let today: Date
    let first: Date?
    let grades: Bool
    let usesExcused: Bool

    var body: some View {
        let future = date > today
        let before = first.map { date < $0 } ?? true
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 14, weight: date == today ? .semibold : .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(future || before || !day.active ? Color.secondary.opacity(future ? 0.5 : 0.8) : Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(disc))
            if usesExcused && day.excusedDay && !day.active {
                ExcusedDayBadge(size: 9).offset(y: -2)
            } else if !future && !before && day.active {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in dot(day.marks[i]) }
                }
                .frame(height: 4)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var disc: Color {
        guard day.allFive else { return .clear }
        return day.allInTime ? Color.green.opacity(0.22) : Color.primary.opacity(0.09)
    }

    @ViewBuilder private func dot(_ mark: JourneyLog.Mark) -> some View {
        switch mark {
        case .done(let s):
            Circle().fill(grades ? PrayerScoring.color(for: s) : Color.primary.opacity(0.72)).frame(width: 4, height: 4)
        case .missed:
            Circle().strokeBorder(Color.secondary.opacity(0.75), lineWidth: 0.9).frame(width: 4, height: 4)
        case .toCome:
            Circle().fill(Color.primary.opacity(0.13)).frame(width: 4, height: 4)
        case .excused:
            Circle().fill(Color.secondary.opacity(0.3)).frame(width: 4, height: 4)
        case .none:
            Color.clear.frame(width: 4, height: 4)
        }
    }

    private var accessibility: String {
        let d = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard day.active else { return d }
        return "\(d): \(day.prayed) of 5 prayed" + (day.allInTime ? ", all in time" : "")
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
