//
//  YourJourney.swift
//  shukr
//
//  Journey's first screen (Journey v6, owner 2026-10-16) and its pieces: Your journey's card, the three rows, the months,
//  the milestones and their celebration. Rules in board/mocks/journey/spec.md (Data rules, Milestones): active days only,
//  rates only over days shukr was used, a break of 7+ days folds into one "Away" line, excused prayers are never missed.
//

import SwiftUI
import SwiftData

/// Journey's first screen (Journey v6, owner 2026-10-16: "yeah this is it … this is gonna tie the knot on this page";
/// board/mocks/journey-v6): Your journey's card leads, then Prayer scores · To make up · Moments as three flat rows, the
/// months (a break folded into one "Away" line) and the milestones. Every piece is one we had, in a gentler order.

/// The card (Journey on one screen, D's card — owner, 2026-10-16, board/mocks/journey-v6/build-plan.md "A"): days you
/// marked a prayer; the grid a week a row (seven rounded bars, the card's colors), today's week at the bottom, scrolling up
/// to the first day with a fade at its top; month names in sage beside the week holding the 1st open that month; the
/// label says what's in view ("THE LAST 18 WEEKS", or the months once scrolled back). A tile's tap puts its day in the
/// three numbers' place; again, the numbers. Before the first mark: "0 days so far" and the line that says what will fill it.
struct JourneyHomeCard: View {
    let stats: YourJourneyStats
    /// A small phone: the number at 42 pt (the canvas's SE).
    var compact = false
    var onDay: (Date) -> Void = { _ in }
    var opens: (Date) -> Bool = { _ in false }
    var onMonth: (Date) -> Void = { _ in }
    @State private var picked: Date?
    /// What the grid shows: the first week row in view, how many fit, and whether it rests at today.
    @State private var view = (first: 0, count: 12, atEnd: true)
    @Environment(\.colorScheme) private var scheme

    /// A week row's pitch: an 11 pt bar and 3 pt between (the canvas).
    static let pitch: CGFloat = 14
    /// The grid's least height: 12 weeks and its top room.
    static let minGrid: CGFloat = 12 * pitch + 12

    var body: some View {
        let empty = stats.activeDays == 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(stats.activeDays)").font(.system(size: compact ? 42 : 54, weight: .thin, design: .rounded))
                    .foregroundStyle(empty ? .secondary : .primary)
                Text(empty ? "days so far" : stats.activeDays == 1 ? "day you marked a prayer" : "days you marked a prayer")
                    .font(.system(size: compact ? 15 : 17, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(rangeLabel)
                Spacer()
                Text("a week a row")
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            grid.padding(.top, 6)
            foot
        }
        .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 14)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
    }

    /// "THE LAST 18 WEEKS" at rest; once scrolled back, the months in view ("JUN – SEP 2026").
    private var rangeLabel: String {
        if view.atEnd || stats.weeks.isEmpty { return "THE LAST \(min(view.count, max(stats.weeks.count, 1))) WEEKS" }
        let rows = stats.weeks
        let a = rows[min(max(view.first, 0), rows.count - 1)].start
        let lastRow = min(rows.count - 1, view.first + view.count - 1)
        let b = Calendar.current.date(byAdding: .day, value: 6, to: rows[max(lastRow, 0)].start) ?? a
        let cal = Calendar.current
        let from = a.formatted(.dateTime.month(.abbreviated)).uppercased()
            + (cal.component(.year, from: a) != cal.component(.year, from: b) ? " \(cal.component(.year, from: a))" : "")
        return "\(from) – \(b.formatted(.dateTime.month(.abbreviated)).uppercased()) \(cal.component(.year, from: b))"
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(stats.weeks) { week in row(week) }
            }
            .padding(.top, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: [Int].self) { geo in
            let count = max(1, Int((geo.containerSize.height - 12) / Self.pitch))
            let first = max(0, Int(((geo.contentOffset.y + geo.contentInsets.top) - 12) / Self.pitch))
            let atEnd = geo.contentSize.height - (geo.contentOffset.y + geo.contentInsets.top) - geo.containerSize.height < 4
            return [first, count, atEnd ? 1 : 0]
        } action: { _, v in
            view = (v[0], v[1], v[2] == 1)
        }
        // A fade at the top: there are earlier weeks up there.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
                Color.black
            }
        }
        // 12 weeks is its natural height (what Journey's fit test measures), and it grows into any room that's left.
        .frame(minHeight: Self.minGrid, idealHeight: Self.minGrid, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your weeks, a week a row")
    }

    private func row(_ week: YourJourneyStats.Week) -> some View {
        HStack(spacing: 6) {
            Group {
                if let m = week.month {
                    Button {
                        triggerSomeVibration(type: .light)
                        onMonth(m.start)
                    } label: {
                        Text(m.label).font(.system(size: 12.5, weight: .regular, design: .rounded)).foregroundStyle(Color.sage)
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(m.start.formatted(.dateTime.month(.wide).year()))")
                } else {
                    Color.clear
                }
            }
            .frame(width: 34, height: 11, alignment: .leading)
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                bar(day)
            }
        }
    }

    @ViewBuilder private func bar(_ day: YourJourneyStats.GridDay?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if let day {
            let on = picked == day.date
            shape.fill(color(day.kind))
                .frame(maxWidth: .infinity)
                .frame(height: 11)
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                            .padding(-3)
                    }
                }
                .contentShape(Rectangle().inset(by: -2))
                .onTapGesture {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = on ? nil : day.date }
                }
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 11)   // before the first day, or still to come
        }
    }

    /// Under the grid: the three numbers, or the picked day's line in their place (the card never grows).
    private var foot: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            ZStack {
                if stats.activeDays == 0 {
                    Text("Every prayer you mark shows up here.")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else if let date = picked, let day = stats.day(on: date) {
                    dayLine(day).transition(.opacity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        figure("\(stats.prayersMarked)", "prayers marked")
                        figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days")
                        figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days", "best streak")
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 46, alignment: .top)
            .padding(.top, 12)
        }
        .padding(.top, 12)
    }

    /// "Fri, Sep 25 · 5 of 5 · all in time · Open ›": a tap opens the day (when it can open).
    private func dayLine(_ d: YourJourneyStats.GridDay) -> some View {
        let date = d.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let what: String = d.prayed == 0 ? (d.excused ? "Excused" : "No prayers marked")
            : d.prayed == 5 && d.inTime == 5 ? "5 of 5 · all in time"
            : "\(d.prayed) of 5 · \(d.inTime) in time"
        let canOpen = d.prayed > 0 && opens(d.date)
        return Button {
            guard canOpen else { return }
            triggerSomeVibration(type: .light)
            onDay(d.date)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(date) · \(what)").foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if canOpen { Text("Open ›").foregroundStyle(Color.sage) }
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date), \(what)")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption)
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    /// The canvas's colours (owner, 2026-10-16: "make colors of the 12 week grid match your mockup"): monochrome by amount,
    /// green only for all five in time. Light from the canvas, dark from Frank's first draft of it.
    private func color(_ kind: YourJourneyStats.Kind) -> Color {
        let dark = scheme == .dark
        switch kind {
        case .none: return dark ? Color(red: 0x2E / 255, green: 0x30 / 255, blue: 0x35 / 255)
                                : Color(red: 126 / 255, green: 132 / 255, blue: 143 / 255).opacity(0.14)
        case .some: return dark ? Color(red: 0x55 / 255, green: 0x57 / 255, blue: 0x5D / 255)
                                : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.30)
        case .allFive: return dark ? Color(red: 0xA9 / 255, green: 0xAB / 255, blue: 0xB1 / 255)
                                   : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.62)
        case .allInTime: return dark ? Color(red: 0x4C / 255, green: 0x8E / 255, blue: 0x62 / 255)
                                     : Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255).opacity(0.55)
        }
    }
}

/// The This month row's measure (build-plan "B", canvas v6): touch and hold the row to choose; the choice sticks
/// (`journey.thisMonth`). Owner: "on time or better" is his pick, so it's the default.
enum ThisMonthMeasure: String, CaseIterable, Identifiable {
    case inWindow, onTime, perfect, average
    static let key = "journey.thisMonth"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inWindow: "In their window"
        case .onTime: "On time or better"
        case .perfect: "Perfect"
        case .average: "Average score"
        }
    }
    /// What it counts, in the menu.
    var counts: String {
        switch self {
        case .inWindow: "Perfect, On time and Late"
        case .onTime: "Perfect and On time"
        case .perfect: "Perfect only"
        case .average: "Every prayer by its score; a missed one is 0"
        }
    }
    func value(_ m: YourJourneyStats.ThisMonth) -> String {
        switch self {
        case .inWindow: "\(m.inWindow)%"
        case .onTime: "\(m.onTime)%"
        case .perfect: "\(m.perfect)%"
        case .average: "\(m.average)"
        }
    }
}

/// A plain row (the canvas's list row): a symbol, a title over a grey line, a value, and a sage ›.
struct JourneyHomeRow<Symbol: View, Value: View>: View {
    let title: String
    let line: String
    var last = false
    /// The row's height (the canvas: 58, 52 on a small phone); nil: its padding.
    var height: CGFloat? = nil
    var quiet = false
    @ViewBuilder let symbol: () -> Symbol
    @ViewBuilder let value: () -> Value
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 13) {
                symbol().frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .light, design: .rounded))
                    Text(line)
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .opacity(quiet ? 0.8 : 1)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                value()
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("›").font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(Color.sage)
            }
            .padding(.vertical, height == nil ? 13 : 0)
            .frame(height: height)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Prayer scores' row value: its lifetime score in a small pressed ring (PrayerScores.prayedScore — the page's own number).
struct JourneyMiniRing: View {
    let score: Int
    var body: some View {
        ZStack {
            NeuPressed(shape: Circle(), radius: 2.5, offset: 1.5)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.primary.opacity(0.65), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Text("\(score)").font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.primary)
        }
        .frame(width: 38, height: 38)
    }
}

/// The section labels: "MONTHS" with "% in time" on the right, "MILESTONES".
struct JourneySectionLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .light, design: .rounded)).tracking(1).foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Milestones, from Journey's row (one screen: the list left the page — build-plan "A"): every one earned, newest first;
/// a tap opens its frosted card, and its day.
struct JourneyMilestonesPage: View {
    let milestones: [JourneyMilestone]
    let firstDay: Date?
    let opens: (Date?) -> Bool
    @Environment(\.circleTheme) private var theme
    @State private var card: JourneyMilestone?
    @State private var openDay: JourneyDayRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Milestones").font(.system(size: 38, weight: .regular, design: .rounded))
                    Text(milestones.count == 1 ? "1 earned" : "\(milestones.count) earned")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                JourneyMilestonesList(milestones: milestones, title: nil) { card = $0 }.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .infoModal(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } }),
                   title: card?.text ?? "", symbol: card?.symbol ?? "flag", tint: .secondary) {
            if let m = card {
                JourneyMilestoneCard(milestone: m, onDay: opens(m.day) ? {
                    let day = m.day
                    card = nil
                    if let day { openDay = JourneyDayRoute(date: day) }
                } : nil)
            }
        }
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: firstDay) }
    }
}

/// Earned once, dated, newest first; a hollow dot each (the canvas).
struct JourneyMilestonesList: View {
    let milestones: [JourneyMilestone]
    /// The section label (nil on the Milestones page, whose title says it).
    var title: String? = "MILESTONES"
    /// A tap: its card (JourneyMilestoneCard).
    var onTap: (JourneyMilestone) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { JourneySectionLabel(title: title) }
            VStack(spacing: 0) {
                ForEach(milestones) { m in
                    Button { triggerSomeVibration(type: .light); onTap(m) } label: {
                    HStack(spacing: 14) {
                        Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.text).font(.system(size: 15, weight: .light, design: .rounded))
                            Text(m.detail ?? m.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.system(size: 12, weight: .light, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Shows how it was earned")
                }
            }
        }
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
    /// A day on the card: its color and its line.
    struct GridDay { let date: Date; let kind: Kind; let prayed: Int; let inTime: Int; let excused: Bool }
    /// A week a row, from the week of the first day to today's (nil: before the first day, or still to come); the week
    /// holding a month's 1st (or the first day) carries that month's name — "Jan’26" on January and on the first month.
    struct Week: Identifiable {
        let start: Date
        let days: [GridDay?]
        let month: (start: Date, label: String)?
        var id: Date { start }
    }
    var weeks: [Week] = []
    func day(on date: Date) -> GridDay? {
        let cal = Calendar.current
        for w in weeks.reversed() where w.start <= date {
            let i = cal.dateComponents([.day], from: w.start, to: date).day ?? 0
            return w.days.indices.contains(i) ? w.days[i] : nil
        }
        return nil
    }
    /// This month so far, four ways (every prayer whose time has come; nil before any is due) — the This month row.
    struct ThisMonth { let inWindow: Int; let onTime: Int; let perfect: Int; let average: Int }
    var thisMonth: ThisMonth?

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
    /// Every milestone earned, newest first.
    var milestones: [JourneyMilestone] = []

    /// A day all excused: every prayer excused, or no rows at all on a day an excused range touches (the app wasn't opened —
    /// Bradley's Excused.streakDay steps over it too). Neither adds to a streak nor breaks it, and isn't "away".
    static func excusedAll(_ d: JourneyLog.Day, on date: Date, in log: JourneyLog, _ excused: Excused.Days) -> Bool {
        d.marks.allSatisfy { $0 == .excused } || (log.days[d.key] == nil && excused.excludes(date))
    }

    static func kind(_ d: JourneyLog.Day) -> Kind {
        guard d.active else { return .none }
        let excused = d.marks.filter { $0 == .excused }.count
        if d.inTime + excused == 5 { return .allInTime }
        if d.prayed + excused == 5 { return .allFive }
        return .some
    }

    /// The months with a marked day, and every break (≥ 7 days in a row with no mark; a fully excused day isn't away).
    private mutating func buildMonths(log: JourneyLog, first: Date, today: Date, excused: Excused.Days) {
        let cal = Calendar.current
        var perMonth: [Date: (inTime: Int, due: Int, days: Int)] = [:]
        var rows: [MonthRow] = []
        var gapStart: Date?
        var gapLength = 0
        func closeGap(endingBefore day: Date) {
            defer { gapStart = nil; gapLength = 0 }
            guard let start = gapStart, gapLength >= 7, let end = cal.date(byAdding: .day, value: -1, to: day) else { return }
            let fmt = Date.FormatStyle.dateTime.month(.abbreviated).day()
            let length = gapLength >= 14 ? "\(Int((Double(gapLength) / 7).rounded())) weeks" : "\(gapLength) days"
            rows.append(MonthRow(id: "away-\(PrayerNotificationID.dayKey(start))", month: JourneyLog.monthStart(start), title: "Away",
                                 note: "\(start.formatted(fmt)) – \(end.formatted(fmt)) · \(length)", rate: nil, at: start))
        }
        var date = first
        while date <= today {
            let d = log.day(date)
            let excusedAll = Self.excusedAll(d, on: date, in: log, excused)
            if d.active {
                closeGap(endingBefore: date)
                let m = JourneyLog.monthStart(date)
                perMonth[m, default: (0, 0, 0)].inTime += d.inTime
                perMonth[m, default: (0, 0, 0)].due += d.due
                perMonth[m, default: (0, 0, 0)].days += 1
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

        for (m, t) in perMonth where t.due > 0 {
            let rate = Int((Double(t.inTime) / Double(t.due) * 100).rounded())
            rows.append(MonthRow(id: "month-\(PrayerNotificationID.dayKey(m))", month: m,
                                 title: m.formatted(.dateTime.month(.wide).year()),
                                 note: t.days == 1 ? "1 day" : "\(t.days) days", rate: rate, at: m))
        }
        monthRows = rows.sorted { $0.at > $1.at }
    }

    init(log: JourneyLog, today: Date, excused: Excused.Days = Excused.Days()) {
        let cal = Calendar.current
        var inTime = 0, due = 0
        for d in log.days.values where d.active {
            activeDays += 1
            prayersMarked += d.prayed
            inTime += d.inTime
            due += d.due
        }
        if due > 0 { inTimeRate = Int((Double(inTime) / Double(due) * 100).rounded()) }

        if let first = log.firstDay {
            let firstDay = cal.startOfDay(for: first)
            var weekStart = cal.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
            var labelled = false
            while weekStart <= today {
                var days: [GridDay?] = []
                var month: (start: Date, label: String)?
                for k in 0..<7 {
                    guard let date = cal.date(byAdding: .day, value: k, to: weekStart) else { days.append(nil); continue }
                    if month == nil, cal.component(.day, from: date) == 1 || date == firstDay, date >= firstDay {
                        let short = date.formatted(.dateTime.month(.abbreviated))
                        let year = !labelled || cal.component(.month, from: date) == 1
                            ? "’" + String(cal.component(.year, from: date) % 100) : ""
                        month = (JourneyLog.monthStart(date), short + year)
                        labelled = true
                    }
                    guard date >= firstDay, date <= today else { days.append(nil); continue }
                    let d = log.day(date)
                    days.append(GridDay(date: date, kind: Self.kind(d), prayed: d.prayed, inTime: d.inTime,
                                        excused: d.marks.contains(.excused)))
                }
                weeks.append(Week(start: weekStart, days: days, month: month))
                guard let next = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
                weekStart = next
            }
        }
        // This month, on time or better (owner's This month row): every prayer whose time has come.
        var window = 0, onTime = 0, perfect = 0, owed = 0, scoreSum = 0.0
        for date in JourneyLog.daysOf(month: JourneyLog.monthStart(today)) where date <= today {
            for mark in log.day(date).marks {
                if case .done(let score) = mark {
                    owed += 1
                    scoreSum += score
                    switch PrayerScoring.grade(for: score) {
                    case .perfect: perfect += 1; onTime += 1; window += 1
                    case .onTime: onTime += 1; window += 1
                    case .late: window += 1
                    case .qaza: break
                    }
                } else if mark == .missed {
                    owed += 1
                }
            }
        }
        if owed > 0 {
            func pct(_ n: Int) -> Int { Int((Double(n) / Double(owed) * 100).rounded()) }
            thisMonth = ThisMonth(inWindow: pct(window), onTime: pct(onTime), perfect: pct(perfect),
                                  average: Int((scoreSum / Double(owed) * 100).rounded()))
        }

        milestones = JourneyMilestone.earned(log: log, today: today, excused: excused)
        if let first = log.firstDay {
            buildMonths(log: log, first: cal.startOfDay(for: first), today: today, excused: excused)
            var run = 0
            var date = cal.startOfDay(for: first)
            while date <= today {
                let d = log.day(date)
                if Self.excusedAll(d, on: date, in: log, excused) {
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

// MARK: - Milestones

/// A milestone's card, in the frosted ⓘ card (InfoModal): what it is, when, how it was earned, and its day.
struct JourneyMilestoneCard: View {
    let milestone: JourneyMilestone
    /// Its day page (nil: none to open — today's still going, or a year since day one).
    var onDay: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(milestone.about)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            InfoModalRow(symbol: "calendar", title: "When",
                         text: milestone.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            if let how = milestone.how {
                InfoModalRow(symbol: "checkmark.circle", title: "How", text: how)
            }
            if let onDay {
                Button { triggerSomeVibration(type: .light); onDay() } label: {
                    Text("See that day ›")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.sage)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Earned once, dated (spec "Milestones", owner 2026-10-16: "a milestone for each one" — every prayer, not only Fajr).
/// One walk over the log from day one; the same rules as the page (prayer days, excused never missed, a run skips a fully
/// excused day and waits on an unfinished today).
struct JourneyMilestone: Identifiable, Equatable {
    enum Tone { case count, inTime, quiet }   // the mockup's dots: dark, green, grey
    let id: String
    var text: String
    let date: Date
    let tone: Tone
    /// The line under it in place of the date ("Jan 5 – Feb 17, 2025" for the best streak).
    var detail: String? = nil
    /// Within a day, the later-earned one sits higher (newest first).
    var order = 0
    /// Its card (a tap — owner, 2026-10-16: "click on a milestone to learn more about it"): a symbol, what it is, how it was
    /// earned, and the day it opens (nil: none — a year since day one).
    var symbol = "flag"
    var about = ""
    var how: String? = nil
    var day: Date? = nil

    /// Days all in time in a row worth a milestone (DayInsight's own list).
    static let runs: [Int] = [7, 14, 21, 30, 40, 50, 60, 90, 100, 150, 200, 250, 300, 365]
    /// Every hundred prayers (owner, 2026-10-16: "yeah, sure, that's fine"); the list keeps the 100th, the 500th, every
    /// thousandth and only the latest of the rest, so it reads as achievements, not a counter.
    static func keepsTotal(_ n: Int) -> Bool { n == 100 || n == 500 || n % 1000 == 0 }
    static let perPrayer: [Int] = [100, 500]

    static func earned(log: JourneyLog, today: Date, excused: Excused.Days = Excused.Days()) -> [JourneyMilestone] {
        guard let firstDay = log.firstDay else { return [] }
        let cal = Calendar.current
        var out: [JourneyMilestone] = []
        func add(_ id: String, _ text: String, _ date: Date, _ tone: Tone,
                 symbol: String = "flag", about: String = "", how: String? = nil, day: Date? = nil) {
            guard !out.contains(where: { $0.id == id }) else { return }
            out.append(JourneyMilestone(id: id, text: text, date: date, tone: tone, order: out.count,
                                        symbol: symbol, about: about, how: how, day: day ?? date))
        }
        /// "Isha, prayed 8:18 PM" — the prayer that earned it.
        func prayed(_ d: JourneyLog.Day, _ i: Int) -> String {
            let name = d.slots[i]?.jumuah == true ? "Jumu'ah" : JourneyLog.names[i]
            return name + (d.slots[i]?.markedAt.map { ", prayed " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
        }
        let span = Date.FormatStyle.dateTime.month(.abbreviated).day()
        func ordinal(_ n: Int) -> String {
            let f = NumberFormatter(); f.numberStyle = .ordinal
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        }

        var total = 0
        var perName: [Int] = Array(repeating: 0, count: 5)
        var run = 0, best = 0, bestAtRunStart = 0
        var runLastDay: Date?
        var runFirstDay: Date?
        var gap = 0
        var masjidDone = false, jumuahDone = false, perfectDone = false

        func closeRun() {
            // A run that beat the best before it: "N days in a row, all in time" — "your best" while it still is.
            // Keyed by the run's first day: a best still growing is one milestone, celebrated once, not one a day.
            if run >= 3, run > bestAtRunStart, let last = runLastDay, let firstOfRun = runFirstDay {
                out.removeAll { $0.id == "run.\(run)" && cal.isDate($0.date, inSameDayAs: last) }   // the same news twice
                add("best.\(PrayerNotificationID.dayKey(firstOfRun))", "\(run) days in a row, all in time", last, .inTime,
                    symbol: "trophy", about: "A new best: more days in a row with all five prayed in time than ever before.",
                    how: "\(run) days, \(firstOfRun.formatted(span)) – \(last.formatted(span))")
                if let k = out.firstIndex(where: { $0.id == "best.\(PrayerNotificationID.dayKey(firstOfRun))" }) {
                    let sameYear = cal.component(.year, from: firstOfRun) == cal.component(.year, from: last)
                    let from = firstOfRun.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
                    out[k].detail = "\(from) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
                }
            }
            run = 0
            bestAtRunStart = best
            runLastDay = nil
            runFirstDay = nil
        }

        var date = cal.startOfDay(for: firstDay)
        while date <= today {
            let d = log.day(date)
            let excusedAll = YourJourneyStats.excusedAll(d, on: date, in: log, excused)
            let unfinishedToday = date == today && d.marks.contains(.toCome)

            if d.active {
                if gap >= 7, let left = cal.date(byAdding: .day, value: -gap, to: date),
                   let lastAway = cal.date(byAdding: .day, value: -1, to: date) {
                    add("back.\(d.key)", "Welcome back", date, .quiet, symbol: "arrow.uturn.left",
                        about: "Your first prayer marked after \(gap) days away.",
                        how: "Away \(left.formatted(span)) – \(lastAway.formatted(span))")
                }
                gap = 0
                // Day one: the first prayer marked, by when it was marked.
                if out.isEmpty {
                    let first = (0..<5).filter { d.marks[$0].done }
                        .min { (d.slots[$0]?.markedAt ?? .distantFuture) < (d.slots[$1]?.markedAt ?? .distantFuture) }
                    if let i = first {
                        add("dayOne", "Day one", date, .quiet, symbol: "sparkles",
                            about: "The first prayer you marked in shukr.", how: prayed(d, i))
                    }
                }
                for i in 0..<5 where d.marks[i].done {
                    total += 1
                    perName[i] += 1
                    if total % 100 == 0 {
                        add("total.\(total)", "\(ordinal(total)) prayer", date, .count, symbol: "number",
                            about: "\(total) prayers marked since day one.", how: prayed(d, i))
                    }
                    if Self.perPrayer.contains(perName[i]) {
                        add("\(JourneyLog.names[i]).\(perName[i])", "\(ordinal(perName[i])) \(JourneyLog.names[i])", date, .count,
                            symbol: "number", about: "\(perName[i]) \(JourneyLog.names[i]) prayers marked since day one.",
                            how: prayed(d, i))
                    }
                    let slot = d.slots[i]
                    if !jumuahDone, slot?.jumuah == true {
                        jumuahDone = true
                        masjidDone = true   // the first Jumu'ah is also the first prayer at a masjid: once is enough
                        add("jumuah", "First Jumu'ah at a masjid", date, .count, symbol: "building.columns",
                            about: "Your first Friday prayer marked at a masjid.",
                            how: slot?.masjid.map { "At \($0)" } ?? prayed(d, i))
                    } else if !masjidDone, let m = slot?.masjid {
                        masjidDone = true
                        add("masjid", "First prayer at a masjid: \(m)", date, .count, symbol: "building.columns",
                            about: "The first prayer you marked at a masjid.", how: "\(prayed(d, i)), at \(m)")
                    }
                }
                if !perfectDone, d.marks.allSatisfy({ ($0.score ?? 0) >= 0.9999 }) {
                    perfectDone = true
                    add("perfect", "A perfect day: all five Perfect", date, .inTime, symbol: "star",
                        about: "All five prayers prayed early in their windows on one day — each scored 100.")
                }
            } else if excusedAll {
                gap = 0
            } else if !unfinishedToday {
                gap += 1
            }

            // Days all in time in a row.
            if excusedAll {
                // neither counts nor breaks
            } else if YourJourneyStats.kind(d) == .allInTime {
                run += 1
                if run == 1 { runFirstDay = date }
                runLastDay = date
                best = max(best, run)
                if Self.runs.contains(run) {
                    add("run.\(run)", run == 7 ? "A full week, all in time" : "\(run) days in a row, all in time", date, .inTime,
                        symbol: "calendar", about: "\(run) days in a row with all five prayers prayed in time.",
                        how: runFirstDay.map { "\($0.formatted(span)) – \(date.formatted(span))" })
                }
            } else if !unfinishedToday {
                closeRun()
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        closeRun()

        // Every hundred prayers: the round ones stay, of the rest only the latest.
        let latestTotal = out.last(where: { $0.id.hasPrefix("total.") })?.id
        out.removeAll { m in
            guard m.id.hasPrefix("total."), m.id != latestTotal, let n = Int(m.id.dropFirst(6)) else { return false }
            return !Self.keepsTotal(n)
        }

        // One Welcome back, the latest return (Frank's check on the owner's data: one per break read as a log of breaks, not
        // achievements; spec: "earned once, dated"). Each return still gets its moment (its own id) when it happens.
        if let latest = out.last(where: { $0.id.hasPrefix("back.") })?.id {
            out.removeAll { $0.id.hasPrefix("back.") && $0.id != latest }
        }

        // Years since day one.
        var years = 1
        while let anniversary = cal.date(byAdding: .year, value: years, to: cal.startOfDay(for: firstDay)), anniversary <= today {
            add("year.\(years)", years == 1 ? "One year since day one" : "\(years) years since day one", anniversary, .quiet,
                symbol: "calendar.badge.clock", about: "Day one was \(firstDay.formatted(.dateTime.month(.wide).day().year())).")
            if let k = out.firstIndex(where: { $0.id == "year.\(years)" }) { out[k].day = nil }   // no day page for an anniversary
            years += 1
        }

        // The latest best is "Your best streak: N days" over its dates (the canvas); the ones it beat stay as they were.
        if let i = out.lastIndex(where: { $0.id.hasPrefix("best.") }) {
            let n = out[i].text.split(separator: " ").first.map(String.init) ?? ""
            out[i].text = "Your best streak: \(n) days"
            out[i].about = "Your longest streak of days with all five prayed in time." 
        }
        return out.sorted { ($0.date, $0.order) > ($1.date, $1.order) }
    }
}

// MARK: - The celebration

/// Milestones are celebrated as they happen, with the first prayer's own celebration (spec decisions: "celebrated as
/// they happen, reusing the first-prayer celebration"; owner 2026-10-16): the green edge glow and its card, in the
/// milestone's words. Checked after a mark on the Salah page and whenever the app comes to the front (a mark from the
/// widget, the watch or a past day). The first check ever records what's already earned without a word (no flood on
/// the update); each milestone is celebrated once, even if a prayer is unmarked and marked again.
@MainActor @Observable final class MilestoneCelebration {
    static let shared = MilestoneCelebration()
    static let seenKey = "journey.milestones.seen"
    static let seenVersionKey = "journey.milestones.seenVersion"
    /// Bumped when a kind of milestone is added (2: every hundred prayers): the first check after an update records what's
    /// already earned of it without a word — never a run of "200th … 800th" celebrations (Sami's trap, acceptance-2 2b).
    static let seenVersion = 2
    private(set) var showing: JourneyMilestone?
    @ObservationIgnored private var queue: [JourneyMilestone] = []
    @ObservationIgnored private var checking = false

    /// After a mark: wait out the mark's own flourish (as the first mark's card, 2.4 s).
    func check(container: ModelContainer, delay: Double = 2.4) {
        guard !checking else { return }
        checking = true
        let ranges = Excused.ranges
        Task {
            defer { checking = false }
            let log = await JourneyLog.load(container: container, ranges: ranges)
            let earned = JourneyMilestone.earned(log: log, today: PrayerDay.start())
            let defaults = UserDefaults.standard
            let ids = earned.map(\.id)
            #if DEBUG
            // `-demoMilestoneCelebration`: the newest milestone left unseen, so the next check celebrates it (the pictures).
            if ProcessInfo.processInfo.arguments.contains("-demoMilestoneCelebration") {
                defaults.set(Array(ids.dropFirst()), forKey: Self.seenKey)
                defaults.set(Self.seenVersion, forKey: Self.seenVersionKey)
            }
            #endif
            guard let seen = defaults.stringArray(forKey: Self.seenKey),
                  defaults.integer(forKey: Self.seenVersionKey) >= Self.seenVersion else {
                let before = defaults.stringArray(forKey: Self.seenKey) ?? []
                defaults.set(Array(Set(before + ids)), forKey: Self.seenKey)
                defaults.set(Self.seenVersion, forKey: Self.seenVersionKey)
                return
            }
            let new = earned.filter { !seen.contains($0.id) }
            guard !new.isEmpty else { return }
            defaults.set(Array(Set(seen + ids)), forKey: Self.seenKey)
            try? await Task.sleep(for: .seconds(delay))
            // Never over the tour or the first mark's own card (that one is Day one's celebration).
            guard TourRuntime.shared.step == nil, !TourRuntime.shared.active else { return }
            queue.append(contentsOf: new.reversed())   // oldest first
            if showing == nil { next() }
        }
    }

    /// Continue: the next one, if a mark earned two (the 100th prayer and the 100th Asr).
    func next() {
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            showing = queue.isEmpty ? nil : queue.removeFirst()
        }
    }
}

/// Over the Salah page, beside the tour's layer: the first mark's glow and card, in a milestone's words.
struct MilestoneCelebrationLayer: View {
    let covered: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var celebration: MilestoneCelebration { MilestoneCelebration.shared }

    var body: some View {
        ZStack {
            if let m = celebration.showing, !covered {
                TourOverlay(step: .celebrate,
                            page: TourPage(headline: m.text, subline: "Added to Your journey.", primary: TourCopy.continueButton),
                            onPrimary: { celebration.next() })
                    .id(m.id)
                    .transition(.opacity)
                    .onAppear { AccessibilityNotification.Announcement(m.text).post() }
                if !reduceMotion { FirstMarkGlow().id("glow-" + m.id).allowsHitTesting(false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            celebration.check(container: context.container, delay: 1.0)
        }
    }
}
