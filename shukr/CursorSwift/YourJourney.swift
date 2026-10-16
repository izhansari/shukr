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

/// The card: days you marked a prayer, the last 12 weeks, three figures. Before the first mark: "0 days so far", the weeks
/// empty, and the line that says what will fill it.
struct JourneyHomeCard: View {
    let stats: YourJourneyStats

    var body: some View {
        let empty = stats.activeDays == 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(stats.activeDays)").font(.system(size: 54, weight: .thin, design: .rounded))
                    .foregroundStyle(empty ? .secondary : .primary)
                Text(empty ? "days so far" : stats.activeDays == 1 ? "day you marked a prayer" : "days you marked a prayer")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            weeks
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            if empty {
                Text("Every prayer you mark shows up here.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    figure("\(stats.prayersMarked)", "prayers marked")
                    figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days")
                    figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days", "best streak")
                }
            }
        }
        .padding(.top, 20).padding(.horizontal, 18).padding(.bottom, 16)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption)
                .font(.system(size: 11.5, weight: .light, design: .rounded))
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
            HStack(spacing: 7) {
                ForEach(0..<12, id: \.self) { col in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(stats.grid[col * 7 + row], today: col == 11 && row == 6)
                        }
                    }
                }
            }
            if stats.activeDays > 0 {
                HStack {
                    Text(stats.gridStart.formatted(.dateTime.month(.abbreviated).day()))
                    Spacer()
                    Text("Today")
                }
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The last 12 weeks: \(stats.grid.filter { $0 == .allInTime }.count) days all five in time, \(stats.grid.filter { $0 == .allFive }.count) days all five")
    }

    /// The canvas's colours (owner, 2026-10-16: "make colors of the 12 week grid match your mockup"): monochrome by how much
    /// was prayed, green only for all five in time — the month calendar's idea. Light from the canvas, dark from Frank's
    /// first draft of it.
    @Environment(\.colorScheme) private var scheme
    private func color(_ kind: YourJourneyStats.Kind) -> Color {
        let dark = scheme == .dark
        switch kind {
        case .none: return dark ? Color(red: 0x2E / 255, green: 0x30 / 255, blue: 0x35 / 255)
                                : Color(red: 126 / 255, green: 132 / 255, blue: 143 / 255).opacity(0.25 * 0.55)
        case .some: return dark ? Color(red: 0x55 / 255, green: 0x57 / 255, blue: 0x5D / 255)
                                : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.30)
        case .allFive: return dark ? Color(red: 0xA9 / 255, green: 0xAB / 255, blue: 0xB1 / 255)
                                   : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.62)
        case .allInTime: return dark ? Color(red: 0x4C / 255, green: 0x8E / 255, blue: 0x62 / 255)
                                     : Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255).opacity(0.55)
        }
    }

    /// A day: 15 pt tall, corner 4 (the canvas).
    private func cell(_ kind: YourJourneyStats.Kind, today: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color(kind))
            .frame(maxWidth: .infinity)
            .frame(height: 15)
    }
}

/// A plain row (the canvas's list row): a symbol, a title over a grey line, a value, and a sage ›.
struct JourneyHomeRow<Symbol: View, Value: View>: View {
    let title: String
    let line: String
    var last = false
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
            .padding(.vertical, 13)
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

/// Every month, newest first, a break folded into one "Away" line (spec: "every month (a break folds into one 'Away ·
/// dates' row)"); the latest five months, then "All N months ›" opens the rest in place.
struct JourneyMonthsList: View {
    let rows: [YourJourneyStats.MonthRow]
    let onMonth: (Date) -> Void
    @State private var all = false
    static let shown = 5

    var body: some View {
        let monthCount = rows.filter { $0.rate != nil }.count
        let visible: [YourJourneyStats.MonthRow] = {
            guard !all, monthCount > Self.shown else { return rows }
            var out: [YourJourneyStats.MonthRow] = [], months = 0
            for r in rows {
                if r.rate != nil { if months == Self.shown { break }; months += 1 }
                out.append(r)
            }
            while out.last?.rate == nil, !out.isEmpty { out.removeLast() }   // never end on an Away line
            return out
        }()
        VStack(alignment: .leading, spacing: 4) {
            JourneySectionLabel(title: "MONTHS", trailing: "% in time")
            VStack(spacing: 0) {
                ForEach(visible) { row in
                    if row.rate == nil { away(row) } else { month(row) }
                }
                if !all, monthCount > Self.shown {
                    Button {
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeOut(duration: CircleMotion.quick)) { all = true }
                    } label: {
                        Text("All \(monthCount) months ›")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(Color.sage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12).padding(.horizontal, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func away(_ row: YourJourneyStats.MonthRow) -> some View {
        HStack {
            Text("Away")
            Spacer()
            Text(row.note ?? "")
        }
        .font(.system(size: 13, weight: .light, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func month(_ row: YourJourneyStats.MonthRow) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            onMonth(row.month)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 16, weight: .light, design: .rounded))
                    if let note = row.note {
                        Text(note).font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 122, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(Color.primary.opacity(0.55)).frame(width: geo.size.width * CGFloat(row.rate ?? 0) / 100)
                    }
                }
                .frame(height: 4)
                Text("\(row.rate ?? 0)%")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Text("›").font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(Color.sage)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(row.rate ?? 0) percent in time")
    }
}

/// Earned once, dated, newest first; a hollow dot each (the canvas).
struct JourneyMilestonesList: View {
    let milestones: [JourneyMilestone]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JourneySectionLabel(title: "MILESTONES")
            VStack(spacing: 0) {
                ForEach(milestones) { m in
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
                    .accessibilityElement(children: .combine)
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
    /// Every milestone earned, newest first.
    var milestones: [JourneyMilestone] = []

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
            let excusedAll = d.marks.allSatisfy { $0 == .excused }
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

        milestones = JourneyMilestone.earned(log: log, today: today)
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

// MARK: - Milestones

/// Earned once, dated (spec "Milestones", owner 2026-10-16: "a milestone for each one" — every prayer, not only Fajr).
/// One walk over the log from day one; the same rules as the page (prayer days, excused never missed, a run skips a fully
/// excused day and waits on an unfinished today).
struct JourneyMilestone: Identifiable, Equatable {
    enum Tone { case count, inTime, quiet }   // the mockup's dots: dark, green, grey
    let id: String
    let text: String
    let date: Date
    let tone: Tone
    /// The line under it in place of the date ("Jan 5 – Feb 17, 2025" for the best streak).
    var detail: String? = nil
    /// Within a day, the later-earned one sits higher (newest first).
    var order = 0

    /// Days all in time in a row worth a milestone (DayInsight's own list).
    static let runs: [Int] = [7, 14, 21, 30, 40, 50, 60, 90, 100, 150, 200, 250, 300, 365]
    static let totals: [Int] = [100, 500, 1000]
    static let perPrayer: [Int] = [100, 500]

    static func earned(log: JourneyLog, today: Date) -> [JourneyMilestone] {
        guard let firstDay = log.firstDay else { return [] }
        let cal = Calendar.current
        var out: [JourneyMilestone] = []
        func add(_ id: String, _ text: String, _ date: Date, _ tone: Tone) {
            guard !out.contains(where: { $0.id == id }) else { return }
            out.append(JourneyMilestone(id: id, text: text, date: date, tone: tone, order: out.count))
        }
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
                add("best.\(PrayerNotificationID.dayKey(firstOfRun))", "\(run) days in a row, all in time", last, .inTime)
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
            let excusedAll = d.marks.allSatisfy { $0 == .excused }
            let unfinishedToday = date == today && d.marks.contains(.toCome)

            if d.active {
                if gap >= 7 { add("back.\(d.key)", "Welcome back", date, .quiet) }
                gap = 0
                // Day one: the first prayer marked, by when it was marked.
                if out.isEmpty {
                    let first = (0..<5).filter { d.marks[$0].done }
                        .min { (d.slots[$0]?.markedAt ?? .distantFuture) < (d.slots[$1]?.markedAt ?? .distantFuture) }
                    if first != nil { add("dayOne", "Day one", date, .quiet) }
                }
                for i in 0..<5 where d.marks[i].done {
                    total += 1
                    perName[i] += 1
                    if Self.totals.contains(total) { add("total.\(total)", "\(ordinal(total)) prayer", date, .count) }
                    if Self.perPrayer.contains(perName[i]) {
                        add("\(JourneyLog.names[i]).\(perName[i])", "\(ordinal(perName[i])) \(JourneyLog.names[i])", date, .count)
                    }
                    let slot = d.slots[i]
                    if !jumuahDone, slot?.jumuah == true {
                        jumuahDone = true
                        masjidDone = true   // the first Jumu'ah is also the first prayer at a masjid: once is enough
                        add("jumuah", "First Jumu'ah at a masjid", date, .count)
                    } else if !masjidDone, let m = slot?.masjid {
                        masjidDone = true
                        add("masjid", "First prayer at a masjid: \(m)", date, .count)
                    }
                }
                if !perfectDone, d.marks.allSatisfy({ ($0.score ?? 0) >= 0.9999 }) {
                    perfectDone = true
                    add("perfect", "A perfect day: all five Perfect", date, .inTime)
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
                    add("run.\(run)", run == 7 ? "A full week, all in time" : "\(run) days in a row, all in time", date, .inTime)
                }
            } else if !unfinishedToday {
                closeRun()
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        closeRun()

        // Years since day one.
        var years = 1
        while let anniversary = cal.date(byAdding: .year, value: years, to: cal.startOfDay(for: firstDay)), anniversary <= today {
            add("year.\(years)", years == 1 ? "One year since day one" : "\(years) years since day one", anniversary, .quiet)
            years += 1
        }

        // The latest best is "Your best streak: N days" over its dates (the canvas); the ones it beat stay as they were.
        if let i = out.lastIndex(where: { $0.id.hasPrefix("best.") }) {
            let n = out[i].text.split(separator: " ").first.map(String.init) ?? ""
            out[i] = JourneyMilestone(id: out[i].id, text: "Your best streak: \(n) days", date: out[i].date, tone: .inTime,
                                      detail: out[i].detail, order: out[i].order)
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
            }
            #endif
            guard let seen = defaults.stringArray(forKey: Self.seenKey) else {
                defaults.set(ids, forKey: Self.seenKey)
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
