//
//  YourJourney.swift
//  shukr
//
//  Journey phase 4 — Your journey (owner, 2026-10-16: "follow this mockup", board/mocks/journey-phase4; rules in
//  board/mocks/journey/spec.md, Screens 5, Data rules, Milestones). Reached from Journey's "Day N · since …" line.
//  Active days only: days before the first mark don't exist, rates count only the days shukr was used, a break of 7+
//  days folds into one "Away" row, excused prayers are never missed.
//

import SwiftUI
import SwiftData

struct YourJourneyPage: View {
    @Environment(\.circleTheme) private var theme
    let log: JourneyLog
    /// A month row: back to Journey on that month (owner, 2026-10-16).
    var onMonth: (Date) -> Void = { _ in }
    private let stats: YourJourneyStats
    /// The title moves into the bar once it has scrolled under it (as the Zikr pages' `titleInBar`).
    @State private var titleShown = false

    init(log: JourneyLog, onMonth: @escaping (Date) -> Void = { _ in }) {
        self.log = log
        self.onMonth = onMonth
        self.stats = YourJourneyStats(log: log, today: PrayerDay.start())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                card.padding(.top, 18)
                if !stats.monthRows.isEmpty { months.padding(.top, 26) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, under in
            withAnimation(.easeOut(duration: 0.15)) { titleShown = under }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationTitle(titleShown ? "Your journey" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your journey").font(.system(size: 32, weight: .light, design: .rounded))
            if let first = log.firstDay {
                Text("Since \(first.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: The card

    /// The one raised block (the mockup's card): days you marked a prayer, the last 12 weeks, three figures.
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(stats.activeDays)").font(.system(size: 52, weight: .ultraLight, design: .rounded))
                Text(stats.activeDays == 1 ? "day you marked a prayer" : "days you marked a prayer")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            weeks
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                figure("\(stats.prayersMarked)", "prayers marked")
                figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days")
                figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days", "best streak")
            }
        }
        .padding(.top, 22).padding(.horizontal, 18).padding(.bottom, 18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)))
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 19, weight: .light, design: .rounded))
            Text(caption)
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// The last 12 weeks, a week a column, oldest top left, today bottom right (spec: "no unbounded heat map").
    private var weeks: some View {
        VStack(spacing: 6) {
            HStack {
                Text("THE LAST 12 WEEKS")
                Spacer()
                Text("a week a column")
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { col in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(stats.grid[col * 7 + row], today: col == 11 && row == 6)
                        }
                    }
                }
            }
            HStack {
                Text(stats.gridStart.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text("Today")
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The last 12 weeks: \(stats.grid.filter { $0 == .allInTime }.count) days all five in time, \(stats.grid.filter { $0 == .allFive }.count) days all five")
    }

    // MARK: Months

    /// Every month, newest first, a break folded into one "Away" row (spec: "every month (a break folds into one
    /// 'Away · dates' row)").
    private var months: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("MONTHS")
                Spacer()
                if let since = stats.betterSince {
                    Text("Better each month since \(since.formatted(.dateTime.month(.wide)))")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(stats.monthRows) { row in monthRow(row) }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }

    private func monthRow(_ row: YourJourneyStats.MonthRow) -> some View {
        Button { onMonth(row.month) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 17, weight: .light, design: .rounded))
                    if let note = row.note {
                        Text(note)
                            .font(.system(size: 11, weight: .light, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 96, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        if let rate = row.rate {
                            Capsule().fill(Color.primary.opacity(0.75)).frame(width: geo.size.width * CGFloat(rate) / 100)
                        }
                    }
                }
                .frame(height: 4)
                Text(row.rate.map { "\($0)%" } ?? "")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.rate.map { "\(row.title), \($0) percent in time" } ?? "\(row.title), \(row.note ?? "")")
    }

    /// The mockup's green (rgb 52 184 100): softer than the system green, which shouted from 84 cells.
    static let green = Color(red: 52 / 255, green: 184 / 255, blue: 100 / 255)

    /// Green = all five in time, grey = all five, hollow = some missed, faint = no shukr that day; today lighter.
    @ViewBuilder private func cell(_ kind: YourJourneyStats.Kind, today: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            switch kind {
            case .allInTime: shape.fill(Self.green.opacity(today ? 0.4 : 0.75))
            case .allFive: shape.fill(Color.primary.opacity(today ? 0.16 : 0.3))
            case .some: today ? AnyView(shape.fill(Color.primary.opacity(0.14))) : AnyView(shape.strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.2))
            case .none: today ? AnyView(shape.fill(Color.primary.opacity(0.14))) : AnyView(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
    }
}

/// Everything Your journey shows, from Journey's log (prayer days; excused prayers never missed, never in a rate).
struct YourJourneyStats {
    enum Kind { case allInTime, allFive, some, none }

    var activeDays = 0
    var prayersMarked = 0
    /// In time over due, on active days only; nil before any prayer was due.
    var inTimeRate: Int?
    /// The longest run of days with every prayer in time (excused days skip, today waits until it's over).
    var bestStreak = 0
    /// The last 84 prayer days, oldest first, today last.
    var grid: [Kind] = Array(repeating: .none, count: 84)
    var gridStart = Date()

    struct MonthRow: Identifiable {
        let id: String
        /// The month it opens (an Away row: the month it began in).
        let month: Date
        let title: String
        let note: String?
        /// % in time on that month's active days; nil for an Away row.
        let rate: Int?
        /// Where it sorts (newest first): the month's start, or the break's first day.
        let at: Date
    }
    var monthRows: [MonthRow] = []
    /// "Better each month since <month>": the first of 3+ months in a row, up to this one, each better than the last.
    var betterSince: Date?

    static func kind(_ d: JourneyLog.Day) -> Kind {
        guard d.active else { return .none }
        let excused = d.marks.filter { $0 == .excused }.count
        if d.inTime + excused == 5 { return .allInTime }
        if d.prayed + excused == 5 { return .allFive }
        return .some
    }

    /// The months with a marked day, and every break (≥ 7 days in a row with no mark; a fully excused day isn't away).
    private mutating func buildMonths(log: JourneyLog, first: Date, today: Date) {
        let cal = Calendar.current
        var perMonth: [Date: (inTime: Int, due: Int)] = [:]
        var rows: [MonthRow] = []
        var gapStart: Date?
        var gapLength = 0
        func closeGap(endingBefore day: Date) {
            defer { gapStart = nil; gapLength = 0 }
            guard let start = gapStart, gapLength >= 7, let end = cal.date(byAdding: .day, value: -1, to: day) else { return }
            let fmt = Date.FormatStyle.dateTime.month(.abbreviated).day()
            rows.append(MonthRow(id: "away-\(PrayerNotificationID.dayKey(start))", month: JourneyLog.monthStart(start), title: "Away",
                                 note: "\(start.formatted(fmt)) – \(end.formatted(fmt))", rate: nil, at: start))
        }
        var date = first
        while date <= today {
            let d = log.day(date)
            let excusedAll = d.marks.allSatisfy { $0 == .excused }
            if d.active {
                closeGap(endingBefore: date)
                let m = JourneyLog.monthStart(date)
                perMonth[m, default: (0, 0)].inTime += d.inTime
                perMonth[m, default: (0, 0)].due += d.due
            } else if excusedAll {
                closeGap(endingBefore: date)
            } else if date < today || !d.marks.contains(.toCome) {
                if gapStart == nil { gapStart = date }
                gapLength += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        if let next = cal.date(byAdding: .day, value: 1, to: today) { closeGap(endingBefore: next) }

        let thisMonth = JourneyLog.monthStart(today), firstMonth = JourneyLog.monthStart(first)
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        var chrono: [(Date, Int)] = []
        for (m, t) in perMonth.sorted(by: { $0.key < $1.key }) where t.due > 0 {
            let rate = Int((Double(t.inTime) / Double(t.due) * 100).rounded())
            chrono.append((m, rate))
            let note: String? = m == thisMonth ? "so far"
                : m == firstMonth && cal.component(.day, from: first) > 1
                    ? "from the \(ordinal.string(from: NSNumber(value: cal.component(.day, from: first))) ?? "")" : nil
            rows.append(MonthRow(id: "month-\(PrayerNotificationID.dayKey(m))", month: m,
                                 title: m.formatted(.dateTime.month(.wide)) + (cal.component(.year, from: m) == cal.component(.year, from: today) ? "" : " \(cal.component(.year, from: m))"),
                                 note: note, rate: rate, at: m))
        }
        monthRows = rows.sorted { $0.at > $1.at }

        // Each month better than the one before, up to this one: from where the climb began (3 months at least).
        if let last = chrono.last, last.0 == thisMonth {
            var start = chrono.count - 1
            while start > 0, chrono[start - 1].1 < chrono[start].1 { start -= 1 }
            if chrono.count - start >= 3 { betterSince = chrono[start].0 }
        }
    }

    init(log: JourneyLog, today: Date) {
        let cal = Calendar.current
        var inTime = 0, due = 0
        for d in log.days.values where d.active {
            activeDays += 1
            prayersMarked += d.prayed
            inTime += d.inTime
            due += d.due
        }
        if due > 0 { inTimeRate = Int((Double(inTime) / Double(due) * 100).rounded()) }

        gridStart = cal.date(byAdding: .day, value: -83, to: today) ?? today
        for i in 0..<84 {
            guard let date = cal.date(byAdding: .day, value: i, to: gridStart) else { continue }
            grid[i] = Self.kind(log.day(date))
        }

        if let first = log.firstDay {
            buildMonths(log: log, first: cal.startOfDay(for: first), today: today)
            var run = 0
            var date = cal.startOfDay(for: first)
            while date <= today {
                let d = log.day(date)
                let excused = d.marks.filter { $0 == .excused }.count
                if excused == 5 {
                    // An excused day neither counts nor breaks.
                } else if Self.kind(d) == .allInTime {
                    run += 1
                    bestStreak = max(bestStreak, run)
                } else if !(date == today && d.marks.contains(.toCome)) {
                    run = 0
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
        }
    }
}
