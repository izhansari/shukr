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

    @MainActor static func build(_ context: ModelContext, now: Date = Date()) -> JourneyLog {
        var log = JourneyLog()
        let ranges = Excused.ranges
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
            log.days[key] = day
        }
        log.firstDay = log.days.values.filter(\.active).map(\.date).min()
        return log
    }

    /// The month's numbers over its active days (spec: rates over active days only).
    struct Month {
        var prayed = 0, due = 0, inTime = 0, allInTimeDays = 0, toMakeUp = 0, activeDays = 0
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
            for (i, mark) in d.marks.enumerated() {
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

struct JourneyPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @AppStorage("prayerStreak") private var streak = 0
    @AppStorage("onTimeStreak") private var inTimeStreak = 0
    /// The grades switch (Journey's ⚙): the calendar's dots in grade colours. Off by default (decision journey-day-look B).
    @AppStorage("journey.grades") private var grades = false
    @AppStorage("journey.view") private var view = "calendar"
    @State private var log = JourneyLog()
    @State private var month = JourneyLog.monthStart(PrayerDay.start())
    @State private var openDay: JourneyDayRoute?
    @State private var showMoments = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Color the dots by grade", isOn: $grades)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Journey settings")
            }
        }
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
        .navigationDestination(isPresented: $showMoments) { MemoriesPage() }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in reload() }
        #if DEBUG
        .task {
            guard !Self.demoDone else { return }   // once per launch, not on every return to the page
            Self.demoDone = true
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoJourneyView"), args.indices.contains(i + 1) { view = args[i + 1] }
            if let i = args.firstIndex(of: "-demoJourneyDay"), args.indices.contains(i + 1), let back = Int(args[i + 1]) {
                try? await Task.sleep(for: .seconds(0.6))
                openDay = JourneyDayRoute(date: Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today)
            }
        }
        #endif
    }

    private func reload() { log = JourneyLog.build(context) }
    #if DEBUG
    @MainActor private static var demoDone = false
    #endif

    private func content(compact: Bool) -> some View {
        let m = log.month(month)
        return VStack(alignment: .leading, spacing: 0) {
            header
            JourneyCard(month: month, numbers: m, streak: streak, inTimeStreak: inTimeStreak, compact: compact)
                .padding(.top, compact ? 10 : 14)
            monthRow.padding(.top, compact ? 12 : 18)
            Group {
                if view == "grid" {
                    JourneyGrid(log: log, month: month, today: today, numbers: m) { open($0) }
                } else {
                    JourneyCalendar(log: log, month: month, today: today, grades: grades, compact: compact) { open($0) }
                }
            }
            .padding(.top, compact ? 6 : 10)
            tiles(m, compact: compact).padding(.top, compact ? 10 : 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        triggerSomeVibration(type: .light)
        openDay = JourneyDayRoute(date: date)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Journey").font(.system(size: 32, weight: .light, design: .rounded))
            Group {
                if let first = log.firstDay {
                    let n = (Calendar.current.dateComponents([.day], from: first, to: today).day ?? 0) + 1
                    Text("Day \(n) · since \(first.formatted(.dateTime.month(.abbreviated).day().year()))")
                } else {
                    Text("Every prayer you mark shows up here.")
                }
            }
            .font(.system(size: 15, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: The month row

    private var firstMonth: Date { JourneyLog.monthStart(log.firstDay ?? today) }
    private var thisMonth: Date { JourneyLog.monthStart(today) }

    private var monthRow: some View {
        HStack(spacing: 2) {
            stepButton("chevron.left", enabled: month > firstMonth, label: "Previous month") { step(-1) }
            Text(month.formatted(.dateTime.month(.wide).year(Calendar.current.isDate(month, equalTo: thisMonth, toGranularity: .year) ? .omitted : .defaultDigits)))
                .font(.system(size: 18, weight: .light, design: .rounded))
                .contentTransition(.opacity)
            stepButton("chevron.right", enabled: month < thisMonth, label: "Next month") { step(1) }
            Spacer(minLength: 8)
            JourneyViewSwitch(view: $view)
        }
        .frame(height: 34)
    }

    private func step(_ by: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: by, to: month) else { return }
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: 0.2)) { month = next }
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.sage : Color.secondary.opacity(0.35))
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
            // Prayers (phase 3) and To make up (phase 2) aren't built yet: shown quiet, not tappable.
            JourneyTile(title: "Prayers", ready: false, compact: compact) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        let p = m.perPrayer[i]
                        let share = p.due == 0 ? 0 : Double(p.prayed) / Double(p.due)
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.3))
                            .frame(width: 7, height: 8 + share * 20)
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } action: {}
            JourneyTile(title: "To make up", ready: false, compact: compact) {
                Text("\(m.toMakeUp)").font(.system(size: 26, weight: .thin, design: .rounded)).frame(height: 28)
            } action: {}
            JourneyTile(title: momentsTitle, ready: true, compact: compact) {
                MomentsTileStack().frame(height: 28)
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

/// Calendar | Grid: a pressed capsule with the picked side raised (the soft look's switch).
private struct JourneyViewSwitch: View {
    @Binding var view: String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            side("Calendar", "calendar")
            side("Grid", "grid")
        }
        .padding(3)
        .background(NeuPressed(shape: Capsule(), radius: 3, offset: 2))
        .frame(height: 34)
    }

    private func side(_ title: String, _ id: String) -> some View {
        Button {
            guard view != id else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: 0.22)) { view = id }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: view == id ? .regular : .light, design: .rounded))
                .foregroundStyle(view == id ? .primary : .secondary)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background {
                    if view == id { NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The card

/// The raised card: the month's ring (prayed of due), the month in words, then the streaks and the days all in time.
private struct JourneyCard: View {
    let month: Date
    let numbers: JourneyLog.Month
    let streak: Int
    let inTimeStreak: Int
    let compact: Bool

    var body: some View {
        let ring: CGFloat = compact ? 78 : 92
        VStack(spacing: compact ? 10 : 12) {
            HStack(spacing: 16) {
                ZStack {
                    NeuPressed(shape: Circle(), radius: 4, offset: 3)
                    Circle().trim(from: 0, to: numbers.due == 0 ? 0 : CGFloat(numbers.prayed) / CGFloat(numbers.due))
                        .stroke(Color.primary.opacity(0.72), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                    VStack(spacing: 0) {
                        Text("\(numbers.prayed)").font(.system(size: compact ? 23 : 26, weight: .thin, design: .rounded)).monospacedDigit()
                        Text("of \(numbers.due)").font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: ring, height: ring)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(numbers.prayed) of \(numbers.due) prayers prayed")
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthWords)
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                    if numbers.due > 0 {
                        Text("\(Int((Double(numbers.inTime) / Double(numbers.due) * 100).rounded()))% in time")
                            .font(.system(size: 14, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                figure(days(streak), "streak")
                figure(days(inTimeStreak), "in-time streak")
                figure("\(numbers.allInTimeDays)", "days all in time")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
    }

    private var monthWords: String {
        guard numbers.activeDays > 0 else { return "Nothing marked in \(month.formatted(.dateTime.month(.wide))) yet." }
        let n = numbers.prayed
        return "\(n) prayer\(n == 1 ? "" : "s") in \(month.formatted(.dateTime.month(.wide)))"
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The calendar

/// The month as a calendar: each day five dots (Fajr … Isha), monochrome unless the grades switch is on; a soft green disc
/// behind a day with all five in time, a grey one behind all five with a Qaza (decision journey-day-look B).
private struct JourneyCalendar: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    let grades: Bool
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
                    JourneyDayCell(day: log.day(date), date: date, today: today, first: log.firstDay, grades: grades,
                                   usesExcused: log.usesExcused)
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

/// The month as a grid of grades (always in colour): a row per prayer, a column per day, then "All five".
private struct JourneyGrid: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    let numbers: JourneyLog.Month
    let onDay: (Date) -> Void

    var body: some View {
        let days = JourneyLog.daysOf(month: month)
        VStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { p in
                row(JourneyLog.names[p], count: "\(numbers.perPrayer[p].prayed)/\(numbers.perPrayer[p].due)") {
                    ForEach(days, id: \.self) { cell(log.day($0).marks[p], date: $0) }
                }
            }
            row("All five", count: "\(numbers.allInTimeDays)", muted: true) {
                ForEach(days, id: \.self) { date in
                    let d = log.day(date)
                    Circle().fill(d.allInTime ? Color.green : d.allFive ? Color.secondary.opacity(0.6) : .clear)
                        .frame(width: 6, height: 6)
                        .frame(maxWidth: .infinity)
                }
            }
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
            legend.padding(.top, 4)
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in pick(tap.location.x, days: days) })
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @State private var width: CGFloat = 0
    private static let label: CGFloat = 54, countWidth: CGFloat = 40, gap: CGFloat = 6

    /// The tapped column → its day (the whole grid takes the tap: its cells are 7 pt wide).
    private func pick(_ x: CGFloat, days: [Date]) {
        let left = Self.label + Self.gap, cells = width - left - Self.gap - Self.countWidth
        guard cells > 0, x >= left, x <= left + cells else { return }
        let i = min(Int((x - left) / cells * CGFloat(days.count)), days.count - 1)
        onDay(days[i])
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
        .frame(height: 24)
    }

    @ViewBuilder private func cell(_ mark: JourneyLog.Mark, date: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        Group {
            switch mark {
            case .done(let s): shape.fill(PrayerScoring.color(for: s))
            case .missed: shape.strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.1)
            case .excused: shape.fill(Color(.systemGray4))
            case .toCome: shape.fill(Color.primary.opacity(0.1))
            case .none: shape.fill(Color.primary.opacity(date > today ? 0.04 : 0.06))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
    }

    private var legend: some View {
        let hasExcused = log.usesExcused && JourneyLog.daysOf(month: month).contains { log.day($0).marks.contains(.excused) }
        return HStack(spacing: 10) {
            swatch(PrayerScoring.color(for: 1), "Perfect")
            swatch(PrayerScoring.color(for: 0.9), "On time")
            swatch(PrayerScoring.color(for: 0.7), "Late")
            swatch(PrayerScoring.color(for: PrayerScoring.qaza), "Qaza")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.1).frame(width: 8, height: 8)
                Text("Missed")
            }
            if hasExcused { swatch(Color(.systemGray4), "Excused") }
        }
        .font(.system(size: 11, weight: .light, design: .rounded))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); Text(title) }
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

/// The two newest photos, one tilted over the other (Moments' pile in small).
private struct MomentsTileStack: View {
    @State private var images: [UIImage] = []
    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(images.enumerated().reversed()), id: \.offset) { i, image in
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: .black.opacity(i == 0 ? 0.2 : 0), radius: 2.5, y: 2)
                    .rotationEffect(.degrees(i == 0 ? -6 : 8))
                    .offset(x: i == 0 ? 0 : 10)
            }
            if images.isEmpty {
                Image(systemName: "photo.stack").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            let keys = PrayerPhotos.all().suffix(2).reversed().map(\.key)
            var loaded: [UIImage] = []
            for key in keys { if let image = await PrayerPhotos.thumbnail(key) { loaded.append(image) } }
            images = loaded
        }
    }
}

// MARK: - DEBUG: a seeded history

#if DEBUG
enum JourneySeed {
    /// `-demoJourneySeed`: ~100 earlier days of rows where there are none — mostly in time, Fajr often late, a few missed,
    /// one Qaza a week, Jumu'ah at a masjid on most Fridays, a 10-day break 60 days back (no rows at all). Sim only.
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
            if taken.contains(key) || (58...67).contains(back) { continue }
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
                if slot == 1 && friday && back % 14 != 0 { row.mosqueName = "Masjid Al-Noor" }
                if slot != 0 { row.latPrayedAt = 35.79 + Double(h) * 0.0005; row.longPrayedAt = -78.78 }
                if let at {
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
