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

/// A square picked in the grid: its one line shows under the grid; a tap on the line opens the day (owner: a tap on a square
/// shouldn't leave the page).
struct JourneyPick: Equatable {
    let prayer: Int
    let date: Date
}

struct JourneyPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @AppStorage("prayerStreak") private var streak = 0
    @AppStorage("onTimeStreak") private var inTimeStreak = 0
    /// Grade colours on the calendar's dots and the grid's squares (the palette button beside Calendar | Grid). Off by
    /// default (decision journey-day-look B).
    @AppStorage("journey.grades") private var grades = false
    @AppStorage("journey.view") private var view = "calendar"
    @State private var log = JourneyLog.last ?? JourneyLog()
    /// The log is read off the main thread (JourneyLog.load); a newer request drops an older result, and a change while
    /// another page is over this one waits for its return (`dirty`) — no rebuild under To make up on every Made up.
    @State private var loadToken = 0
    @State private var onScreen = false
    @State private var dirty = false
    @State private var month = JourneyLog.monthStart(PrayerDay.start())
    @State private var openDay: JourneyDayRoute?
    @State private var showMoments = false
    @State private var showMakeUp = false
    @State private var showScores = false
    @State private var showJourney = false
    @State private var highlight: JourneyHighlight?
    @State private var pick: JourneyPick?

    private var today: Date { PrayerDay.start() }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
            ScrollView { content(compact: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
        .navigationDestination(isPresented: $showMoments) { MemoriesPage() }
        .navigationDestination(isPresented: $showMakeUp) { JourneyMakeUpPage(month: month) }
        .navigationDestination(isPresented: $showScores) { PrayerScoresPage() }
        .navigationDestination(isPresented: $showJourney) {
            YourJourneyPage(log: log) { m in month = m; showJourney = false }
        }
        .onAppear {
            onScreen = true
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
        .onChange(of: month) {
            pick = nil
            if case .bestDay = highlight { highlight = nil }   // another month has its own best day
        }
        .onChange(of: view) { pick = nil }
        #if DEBUG
        .task {
            guard !Self.demoDone else { return }   // once per launch, not on every return to the page
            Self.demoDone = true
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoJourneyView"), args.indices.contains(i + 1) { view = args[i + 1] }
            if args.contains("-demoJourneyGrades") { grades = true }
            if args.contains("-demoJourneyHighlight") { highlight = .allInTime }
            if args.contains("-demoJourneyPick") {
                pick = JourneyPick(prayer: 0, date: Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today)
            }
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
        Task {
            let built = await JourneyLog.load(container: container, ranges: ranges)
            guard token == loadToken else { return }
            log = built
            JourneyLog.last = built
        }
    }
    #if DEBUG
    @MainActor private static var demoDone = false
    #endif

    private func content(compact: Bool) -> some View {
        let m = log.month(month)
        return VStack(alignment: .leading, spacing: 0) {
            header
            JourneyCard(month: month, numbers: m, streak: streak, inTimeStreak: inTimeStreak, compact: compact,
                        highlight: $highlight)
                .padding(.top, compact ? 10 : 14)
            monthRow.padding(.top, compact ? 12 : 18)
            Group {
                if view == "grid" {
                    JourneyGrid(log: log, month: month, today: today, numbers: m, grades: grades, highlight: highlight,
                                pick: $pick) { open($0) }
                } else {
                    JourneyCalendar(log: log, month: month, today: today, grades: grades, highlight: highlight,
                                    compact: compact) { open($0) }
                }
            }
            .padding(.top, compact ? 6 : 10)
            // The colours fade in and out as Insights' do (owner): the stored switch alone carried no animation.
            .animation(.easeInOut(duration: 0.3), value: grades)
            tiles(m, compact: compact).padding(.top, compact ? 10 : 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        // Today opens only once it's over — all five marked (owner, 2026-10-15: the day page "doesn't show up in journey
        // unless the day is over or all 5 have been marked, so it never shows current prayers"). Until then the Salah
        // tab is today's page.
        guard date < today || log.day(date).allFive else { return }
        triggerSomeVibration(type: .light)
        openDay = JourneyDayRoute(date: date)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Journey").font(.system(size: 32, weight: .light, design: .rounded))
            Group {
                if let first = log.firstDay {
                    let n = (Calendar.current.dateComponents([.day], from: first, to: today).day ?? 0) + 1
                    // The door to Your journey (spec, Screens 1: "Day N · since <first day> ›"); sage = tap.
                    Button { showJourney = true } label: {
                        Text("Day \(n) · since \(first.formatted(.dateTime.month(.abbreviated).day().year())) ›")
                            .foregroundStyle(Color.sage)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Every prayer you mark shows up here.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 15, weight: .light, design: .rounded))
        }
    }

    // MARK: The month row

    private var firstMonth: Date { JourneyLog.monthStart(log.firstDay ?? today) }
    private var thisMonth: Date { JourneyLog.monthStart(today) }

    private var monthRow: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", enabled: month > firstMonth, label: "Previous month") { step(-1) }
            // A fixed width, so › stays under the finger as the months change (owner): this year's months by name, earlier
            // years' as "Sep 2025".
            Text(Calendar.current.isDate(month, equalTo: thisMonth, toGranularity: .year)
                 ? month.formatted(.dateTime.month(.wide)) : month.formatted(.dateTime.month(.abbreviated).year()))
                .font(.system(size: 17, weight: .light, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 88, alignment: .leading)
            stepButton("chevron.right", enabled: month < thisMonth, label: "Next month") { step(1) }
            Spacer(minLength: 6)
            gradesButton
            JourneySwitch(options: [("Calendar", "calendar"), ("Grid", "grid")], selection: $view)
        }
        .frame(height: 34)
    }

    /// Grade colours on / off, for the calendar and the grid (owner: a toggle beside the switch, not in a menu; the palette
    /// symbol was "not on brand"): the calendar's own dots — grey on a raised disc while off, the grade colours pressed in
    /// while on.
    private var gradesButton: some View {
        Button {
            triggerSomeVibration(type: .light)
            grades.toggle()
        } label: {
            HStack(spacing: 3) {
                ForEach([1.0, 0.9, 0.7], id: \.self) { score in
                    Circle().fill(grades ? PrayerScoring.color(for: score) : Color.secondary.opacity(0.45))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 28, height: 28)   // the month arrows' size (owner)
            .background {
                if grades { NeuPressed(shape: Circle(), radius: 3, offset: 2) } else { NeuRaised(shape: Circle(), radius: 2.5, offset: 1.2) }
            }
            .animation(.easeInOut(duration: 0.3), value: grades)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grades ? "Hide grade colors" : "Show grade colors")
    }

    private func step(_ by: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: by, to: month) else { return }
        triggerSomeVibration(type: .light)
        month = next
    }

    /// A small raised disc with a plain chevron (owner: not the sage arrows); flat and faint when there's no month that way.
    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.3))
                .frame(width: 28, height: 28)
                .background { if enabled { NeuRaised(shape: Circle(), radius: 2.5, offset: 1.2) } }
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: The tiles

    private func tiles(_ m: JourneyLog.Month, compact: Bool) -> some View {
        HStack(spacing: 10) {
            // Prayers → Prayer scores (phase 3): every prayer you've marked, by prayer.
            JourneyTile(title: "Prayers", ready: true, compact: compact) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        let p = m.perPrayer[i]
                        let share = p.due == 0 ? 0 : Double(p.prayed) / Double(p.due)
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.3))
                            .frame(width: 7, height: 8 + share * 20)
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } action: {
                triggerSomeVibration(type: .light)
                showScores = true
            }
            JourneyTile(title: "To make up", ready: true, compact: compact) {
                Text("\(m.toMakeUp)").font(.system(size: 26, weight: .thin, design: .rounded)).frame(height: 28)
            } action: {
                triggerSomeVibration(type: .light)
                showMakeUp = true
            }
            JourneyTile(title: momentsTitle, ready: true, compact: compact) {
                MomentsTileStack().frame(height: 30)
            } action: {
                triggerSomeVibration(type: .light)
                showMoments = true
            }
        }
    }

    private var momentsTitle: String {
        let n = PrayerPhotos.all().count
        return n == 0 ? "Moments" : n == 1 ? "1 moment" : "\(n) moments"
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

// MARK: - The card

/// The raised card: the month's ring (prayed of due; a tap shows in time of due), the month in words with the streaks as
/// grey lines, then days all in time · days with all five (a tap lights those days up) · the average score.
private struct JourneyCard: View {
    let month: Date
    let numbers: JourneyLog.Month
    let streak: Int
    let inTimeStreak: Int
    let compact: Bool
    @Binding var highlight: JourneyHighlight?
    @State private var showInTime = false
    @State private var flipToken = 0

    var body: some View {
        let ring: CGFloat = compact ? 78 : 92
        let shown = showInTime ? numbers.inTime : numbers.prayed
        VStack(spacing: compact ? 10 : 12) {
            HStack(spacing: 16) {
                ZStack {
                    NeuPressed(shape: Circle(), radius: 4, offset: 3)
                    Circle().trim(from: 0, to: numbers.due == 0 ? 0 : CGFloat(shown) / CGFloat(numbers.due))
                        .stroke(showInTime ? Color.green.opacity(0.8) : Color.primary.opacity(0.72),
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                    VStack(spacing: 0) {
                        Text("\(shown)").font(.system(size: compact ? 23 : 26, weight: .thin, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(showInTime ? "in time" : "of \(numbers.due)")
                            .font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: ring, height: ring)
                .contentShape(Circle())
                .onTapGesture { flip() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(showInTime ? "\(numbers.inTime) of \(numbers.due) prayers in time" : "\(numbers.prayed) of \(numbers.due) prayers prayed")
                .accessibilityAddTraits(.isButton)
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthWords)
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                    if numbers.due > 0 {
                        grey("\(Int((Double(numbers.inTime) / Double(numbers.due) * 100).rounded()))% in time")
                    }
                    grey("Streak \(days(streak)) · \(inTimeStreak) in time")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack(spacing: 4) {
                figure("\(numbers.allInTimeDays)", "days all in time", .allInTime)
                figure("\(numbers.allFiveDays)", "days with all five", .allFive)
                bestDayFigure
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
    }

    /// The average score; a tap lights up the month's best day and shows its score and date instead (owner); again, back.
    @ViewBuilder private var bestDayFigure: some View {
        let best = numbers.bestDay
        let on: Bool = { if case .bestDay = highlight { true } else { false } }()
        Button {
            guard let best else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: 0.2)) { highlight = on ? nil : .bestDay(best.date) }
        } label: {
            VStack(spacing: 1) {
                Text(on ? "\(best?.score ?? 0)" : numbers.averageScore.map { "\($0)" } ?? "–")
                    .font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(on ? "best · \(best?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")" : "average score")
                    .font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background { if on { NeuPressed(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), radius: 3, offset: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(best == nil)
        .accessibilityHint(on ? "Shows every day again" : "Lights up the month's best day")
    }

    /// Prayed ⇄ in time, back by itself after 4 s (the Salah ring's flip).
    private func flip() {
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: 0.3)) { showInTime.toggle() }
        flipToken += 1
        let mine = flipToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if flipToken == mine && showInTime { withAnimation(.easeOut(duration: 0.3)) { showInTime = false } }
        }
    }

    private var monthWords: String {
        guard numbers.activeDays > 0 else { return "Nothing marked in \(month.formatted(.dateTime.month(.wide))) yet." }
        let n = numbers.prayed
        return "\(n) prayer\(n == 1 ? "" : "s") in \(month.formatted(.dateTime.month(.wide)))"
    }

    private func grey(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    @ViewBuilder private func figure(_ value: String, _ caption: String, _ kind: JourneyHighlight?) -> some View {
        let on = kind != nil && highlight == kind
        let content = VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background { if on { NeuPressed(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), radius: 3, offset: 2) } }
        if let kind {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(.easeOut(duration: 0.2)) { highlight = on ? nil : kind }
            } label: { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint(on ? "Shows every day again" : "Lights up those days")
        } else {
            content
        }
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

// MARK: - The grid

/// The month as a grid: a row per prayer, a column per day, then "All five". A tap on a square picks it: its one line shows
/// under the grid (owner: like Insights' grid), and a tap on that line opens the day. Grade colours follow the palette
/// button; off, a prayed square is filled and a missed one hollow.
private struct JourneyGrid: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    let numbers: JourneyLog.Month
    let grades: Bool
    let highlight: JourneyHighlight?
    @Binding var pick: JourneyPick?
    let onDay: (Date) -> Void

    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    /// What was picked when the finger went down (lifting on that same square without sliding puts it away).
    @State private var pickAtTouch: JourneyPick??
    @State private var movedToOther = false
    private static let label: CGFloat = 54, countWidth: CGFloat = 40, gap: CGFloat = 6, rowHeight: CGFloat = 16, rowGap: CGFloat = 5

    var body: some View {
        let days = JourneyLog.daysOf(month: month)
        VStack(spacing: 6) {
            VStack(spacing: Self.rowGap) {
                ForEach(0..<5, id: \.self) { p in
                    row(JourneyLog.names[p], count: "\(numbers.perPrayer[p].prayed)/\(numbers.perPrayer[p].due)") {
                        ForEach(days, id: \.self) { date in
                            cell(log.day(date).marks[p], date: date, picked: pick == JourneyPick(prayer: p, date: date),
                                 lit: highlight?.matches(log.day(date)) == true)
                                .opacity(dim(date))
                        }
                    }
                }
                row("All five", count: "\(numbers.allInTimeDays)", muted: true) {
                    ForEach(days, id: \.self) { date in
                        let d = log.day(date)
                        Circle().fill(d.allInTime ? (grades || highlight?.matches(d) == true ? Color.green : Color.primary.opacity(0.7))
                                      : d.allFive ? Color.secondary.opacity(0.5) : .clear)
                            .frame(width: 6, height: 6)
                            .frame(maxWidth: .infinity)
                            .opacity(dim(date))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(scrub(days))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { width = $0.width; height = $0.height }
            row("", count: "", muted: true) {
                ForEach(days, id: \.self) { date in
                    let n = Calendar.current.component(.day, from: date)
                    Text([1, 8, 15, 22, 29].contains(n) ? "\(n)" : "")
                        .font(.system(size: 9, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)
            pickLine.padding(.top, 4)
        }
    }

    private func dim(_ date: Date) -> Double {
        guard let highlight else { return 1 }
        return highlight.matches(log.day(date)) ? 1 : 0.18
    }

    /// The tapped square → its prayer and day (the cells are 7 pt wide: the whole grid takes the tap).
    /// The square under a point in the grid's own space (the cells are 7 pt wide: the whole grid takes the touch).
    private func square(at point: CGPoint, days: [Date]) -> JourneyPick? {
        let left = Self.label + Self.gap, cells = width - left - Self.gap - Self.countWidth
        guard cells > 0, point.x >= left, point.x <= left + cells, point.y >= 0 else { return nil }
        let i = min(Int((point.x - left) / cells * CGFloat(days.count)), days.count - 1)
        let p = Int(point.y / (Self.rowHeight + Self.rowGap))
        let date = days[i]
        guard p < 5, date <= today, let first = log.firstDay, date >= first else { return nil }
        return JourneyPick(prayer: p, date: date)
    }

    /// As Insights' grid: touch down and slide — the square under the finger is picked, a light tick on each new one; a tap
    /// is the same without the slide, and lifting on the square that was already picked (without moving) puts it away.
    private func scrub(_ days: [Date]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pickAtTouch == nil { pickAtTouch = .some(pick); movedToOther = false }
                guard let hit = square(at: value.location, days: days), hit != pick else { return }
                if pickAtTouch != .some(hit) { movedToOther = true }
                triggerSomeVibration(type: .light)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { pick = hit }
            }
            .onEnded { value in
                if !movedToOther, let atTouch = pickAtTouch, let was = atTouch, square(at: value.location, days: days) == was {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { pick = nil }
                }
                pickAtTouch = nil
            }
    }

    /// "Fajr · Wed, Oct 7 ›" over "Perfect · 100 · prayed 6:35 AM · window 6:05 – 7:15 AM"; before a pick, a quiet hint.
    @ViewBuilder private var pickLine: some View {
        Group {
            if let pick, let words = describe(pick) {
                Button {
                    onDay(pick.date)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(words.title).font(.system(size: 14, weight: .regular, design: .rounded))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        // Grey words, the grade's colour only as a dot before them (owner: coloured text was hard to read).
                        HStack(spacing: 5) {
                            if let color = words.color { Circle().fill(color).frame(width: 7, height: 7) }
                            Text(words.detail).font(.system(size: 12, weight: .light, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens that day")
            } else {
                Text("Tap a square to see that prayer")
                    .font(.system(size: 12, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 36)
    }

    private func describe(_ pick: JourneyPick) -> (title: String, detail: String, color: Color?)? {
        let day = log.day(pick.date)
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        let slot = day.slots[pick.prayer]
        let name = slot?.jumuah == true ? "Jumu'ah" : JourneyLog.names[pick.prayer]
        let title = "\(name) · \(pick.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        let window = slot.map { "window \(time($0.start)) – \(time($0.end))" }
        var parts: [String] = []
        switch day.marks[pick.prayer] {
        case .done(let s):
            parts.append(slot?.jumuah == true ? "Jumu'ah · 100" : PrayerScoring.grade(for: s) == .perfect ? "Perfect · 100" : PrayerScoring.summary(for: s))
            if let at = slot?.markedAt { parts.append("prayed \(time(at))") }
        case .missed: parts.append("Not marked")
        case .toCome: parts.append("Still to come")
        case .excused: parts.append("Excused")
        case .none: parts.append("No prayer times that day")
        }
        if let window { parts.append(window) }
        return (title, parts.joined(separator: " · "), day.marks[pick.prayer].score.map { PrayerScoring.color(for: $0) })
    }

    private func row<Cells: View>(_ name: String, count: String, muted: Bool = false, @ViewBuilder cells: () -> Cells) -> some View {
        HStack(spacing: Self.gap) {
            Text(name).font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(muted ? .secondary : .primary)
                .frame(width: Self.label, alignment: .leading)
            HStack(spacing: 2) { cells() }
            Text(count).font(.system(size: 12, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Self.countWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
    }

    /// Insights' squares: with colours off a prayed one is a soft grey, an unprayed one only an outline; the picked one
    /// always shows its grade colour, a little larger, glowing (owner: "the same way as it does in Insights").
    /// `lit`: a day the card lights up — its colours show whatever the switch (owner, as Insights did).
    @ViewBuilder private func cell(_ mark: JourneyLog.Mark, date: Date, picked: Bool, lit: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        let color: Color? = mark.score.map { PrayerScoring.color(for: $0) }
        Group {
            switch mark {
            case .done: shape.fill(grades || picked || lit ? color ?? .gray : Color.primary.opacity(0.28))
            case .missed: shape.fill(Color.clear)
            case .excused: shape.fill(Color(.systemGray4))
            case .toCome, .none: shape.fill(Color.clear)
            }
        }
        .overlay {
            // The picked one as on Insights' "How consistent am I?" page — a dark border, here a thin one (owner: the first was
            // too heavy, none was too hard to make out) — over its colour, 1.18× and a glow.
            shape.strokeBorder(picked ? Color.primary.opacity(0.6)
                               : mark == .missed ? Color.primary.opacity(0.3)
                               : mark.done || mark == .excused ? Color.clear
                               : Color.primary.opacity(date > today ? 0.06 : 0.12),
                               lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 11)   // nearer a rounded square than a tall bar (owner)
        .scaleEffect(picked ? 1.18 : 1)
        .shadow(color: picked ? (color ?? .clear).opacity(0.5) : .clear, radius: 4)
        .zIndex(picked ? 1 : 0)
    }
}

// MARK: - Tiles

/// A flat tile under the month (lists stay flat; the card is the one raised thing).
private struct JourneyTile<Top: View>: View {
    let title: String
    let ready: Bool
    let compact: Bool
    @ViewBuilder let top: Top
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                top
                Spacer(minLength: 6)
                Text(ready ? "\(title) ›" : title)
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 70 : 78)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .opacity(ready ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }
}

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
