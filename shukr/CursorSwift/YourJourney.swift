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
    private let stats: YourJourneyStats

    init(log: JourneyLog) {
        self.log = log
        self.stats = YourJourneyStats(log: log, today: PrayerDay.start())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                card.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
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

    static func kind(_ d: JourneyLog.Day) -> Kind {
        guard d.active else { return .none }
        let excused = d.marks.filter { $0 == .excused }.count
        if d.inTime + excused == 5 { return .allInTime }
        if d.prayed + excused == 5 { return .allFive }
        return .some
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
