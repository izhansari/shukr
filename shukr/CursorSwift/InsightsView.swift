//
//  InsightsView.swift
//  shukr
//
//  Hamburger → Insights (2026-09-25): streaks, day score trend, per-prayer averages, how the
//  prayers split across grades, and a 14-day prayer trends grid, on one page. Everything is computed
//  from the prayer rows with PrayerScoring, so it always matches the current rules.
//  Days with no rows (app not opened) aren't counted; today is left out of day averages
//  until it's over.
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    /// `.sections` is the page. `.old` is the flat version from 2026-09-25 (progress, ring +
    /// range, streaks + grid, no headers), kept under the DEBUG hamburger as "Old Insights" in
    /// case we want it back.
    enum Layout { case sections, old }
    var layout: Layout = .sections

    @Query(sort: \PrayerModel.startTime) private var prayers: [PrayerModel]
    @AppStorage("prayerStreak") private var streak: Int = 0
    @AppStorage("maxPrayerStreak") private var maxStreak: Int = 0
    @AppStorage("onTimeStreak") private var onTimeStreak: Int = 0
    @AppStorage("maxOnTimeStreak") private var maxOnTimeStreak: Int = 0

    @State private var range: InsightsRange = .month
    /// Flips on appear and on every range change; the numbers and rings animate from zero.
    @State private var revealed = false
    /// Tapped hero circle: the caption under it shows how the prayers split instead of the trend.
    @State private var showSplit = false
    /// The Insights page in view (0 progress, 1 score, 2 consistency).
    @State private var pageIndex: Int? = 0
    /// Tapped prayer ring: its average and how often it was prayed show under the rings.
    @State private var selectedPrayer: String?


    var body: some View {
        let stats = InsightsStats(prayers: prayers, range: range)
        Group {
            if layout == .old {
                // The flat version (2026-09-25): progress, the score ring with its range switch,
                // then streaks and the 14-day grid. Felt flat — no hierarchy. Scrolls only if it
                // doesn't fit.
                ScrollView {
                    VStack(spacing: 26) {
                        PrayerProgressList(prayers: prayers)
                        VStack(spacing: 12) {
                            hero(stats)
                            rangePicker
                        }
                        VStack(spacing: 16) {
                            streaks
                            PrayerTrendsGrid(prayers: prayers, revealed: revealed)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                // One page per question, swiped sideways (owner, 2026-09-25). The question sits at
                // the top and blurs over to the next one; each page's content is centred; paging
                // revolves — the leaving page fades, shrinks and turns away while the next grows
                // in. Drags on the sparklines and the grid scrub them; swipe elsewhere to page.
                VStack(spacing: 0) {
                    ZStack {
                        Text(Self.questions[pageIndex ?? 0])
                            .font(.title3.weight(.light))
                            .id(pageIndex ?? 0)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 6)),
                                removal: .opacity.combined(with: .scale(scale: 1.08)).combined(with: .offset(y: -6))))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pageIndex)

                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(Self.questions.indices, id: \.self) { i in
                                VStack {
                                    Spacer(minLength: 0)
                                    pageContent(i, stats: stats)
                                        .padding(.horizontal, 24)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxHeight: .infinity)
                                .containerRelativeFrame(.horizontal)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .opacity(1 - min(abs(phase.value), 1))
                                        .scaleEffect(1 - min(abs(phase.value), 1) * 0.4)
                                        // Pages on the outside of a drum in front of you: a page
                                        // leaving to the left turns its face left (its outer edge
                                        // recedes), like a wheel revolving. The negative-angle
                                        // version felt like standing inside the wheel.
                                        .rotation3DEffect(.degrees(phase.value * 65), axis: (x: 0, y: 1, z: 0),
                                                          anchor: .center, perspective: 0.45)
                                }
                                .id(i)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .frame(maxHeight: .infinity)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $pageIndex)
                    .scrollIndicators(.hidden)
                    .sensoryFeedback(.selection, trigger: pageIndex)

                    // Page dots.
                    HStack(spacing: 7) {
                        ForEach(Self.questions.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == (pageIndex ?? 0) ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                                .frame(width: i == (pageIndex ?? 0) ? 18 : 6, height: 6)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pageIndex)
                    .padding(.vertical, 14)
                }
            }
        }
        .fontDesign(.rounded)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)

        .sensoryFeedback(.selection, trigger: range)
        .onAppear { reveal() }
        .onChange(of: range) { _, _ in
            revealed = false
            selectedPrayer = nil
            reveal()
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .controlSize(.small)
    }

    static let questions = ["am I getting better?", "how am I scoring?", "how consistent am I?"]

    @ViewBuilder private func pageContent(_ i: Int, stats: InsightsStats) -> some View {
        switch i {
        case 0:
            PrayerProgressList(prayers: prayers)
        case 1:
            // The range switch only changes this page, so it sits at its bottom.
            VStack(spacing: 22) {
                hero(stats)
                prayerRings(stats)
                rangePicker
                    .padding(.top, 6)
            }
        default:
            VStack(spacing: 20) {
                streaks
                PrayerTrendsGrid(prayers: prayers, revealed: revealed)
            }
        }
    }

    // MARK: Prayer rings — tap one for its numbers (back by request, 2026-09-25)

    private func prayerRings(_ stats: InsightsStats) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(Array(stats.perPrayer.enumerated()), id: \.element.id) { index, stat in
                    let selected = selectedPrayer == stat.name
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(Color(.secondarySystemFill), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: revealed ? (stat.average ?? 0) : 0)
                                .stroke(PrayerScoring.color(for: stat.average), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.08 * Double(index)), value: revealed)
                            Image(systemName: prayerIcon(for: stat.name))
                                .font(.caption)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(width: 40, height: 40)
                        .scaleEffect(selected ? 1.12 : 1)
                        Text(stat.name)
                            .font(.caption2)
                            .fontWeight(selected ? .medium : .light)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerSomeVibration(type: .light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedPrayer = selected ? nil : stat.name
                        }
                    }
                }
            }
            Group {
                if let name = selectedPrayer, let stat = stats.perPrayer.first(where: { $0.name == name }) {
                    VStack(spacing: 2) {
                        Text("\(name) · avg \(stat.average.map { "\(Int(($0 * 100).rounded()))" } ?? "–") · prayed \(stat.prayedRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")")
                        Text("\(stat.prayed) prayed of \(stat.recorded) recorded")
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    // Best / worst is the progress section's job now.
                    Text("tap a prayer for its average and how often you prayed it")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
            .transition(.blurReplace)
            .id(selectedPrayer ?? "")
        }
    }


    private func reveal() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { revealed = true }
        }
    }

    // MARK: Hero — the average day score, in a circle like the main page's

    /// Tap the circle: the ring becomes the makeup of the range's prayers — the filled part is
    /// the share prayed, split into Early / On time / Late / Qaza; the empty track is Missed.
    private func hero(_ stats: InsightsStats) -> some View {
        let avg = stats.average ?? 0
        let total = max(stats.grades.map(\.count).reduce(0, +), 1)
        let prayedShare = Double(total - (stats.grades.first { $0.grade == .missed }?.count ?? 0)) / Double(total)
        let number = showSplit ? Int((prayedShare * 100).rounded()) : (revealed ? Int((avg * 100).rounded()) : 0)
        return VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color(.secondarySystemFill), lineWidth: 12)
                if showSplit {
                    ForEach(Array(segments(stats, total: total).enumerated()), id: \.offset) { index, seg in
                        // Same thin, round-capped line as the day-score arc, just in pieces.
                        Circle()
                            .trim(from: seg.from, to: seg.to)
                            .stroke(seg.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .transition(.opacity.animation(.easeOut(duration: 0.3).delay(0.06 * Double(index))))
                    }
                } else {
                    Circle()
                        .trim(from: 0, to: revealed ? avg : 0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .transition(.opacity)
                }
                VStack(spacing: 2) {
                    Text(stats.average == nil ? "–" : "\(number)\(showSplit ? "%" : "")")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .contentTransition(.numericText(value: Double(number)))
                    Text(showSplit ? "prayed" : "avg score")
                        .font(.footnote)
                        .fontWeight(.thin)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: 160, height: 160)
            .contentShape(Circle())
            .onTapGesture {
                triggerSomeVibration(type: .light)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showSplit.toggle() }
            }

            Group {
                if showSplit {
                    // Legend for the coloured ring.
                    HStack(spacing: 10) {
                        ForEach(stats.grades.filter { $0.count > 0 }, id: \.grade) { item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(item.grade == .missed ? Color(.secondarySystemFill) : item.grade.color)
                                    .frame(width: 7, height: 7)
                                Text("\(item.grade.rawValue.lowercased()) \(Int((Double(item.count) / Double(total) * 100).rounded()))%")
                            }
                        }
                    }
                } else if let prev = stats.previousAverage, stats.average != nil {
                    let delta = Int(((avg - prev) * 100).rounded())
                    Text("\(delta >= 0 ? "↑" : "↓") \(abs(delta)) vs the \(range.previousPhrase)")
                } else if range == .all, let first = stats.dayScores.first?.day {
                    // No "before" for all time: say what it covers.
                    Text("since \(first.formatted(.dateTime.month(.abbreviated).day().year())) · \(stats.dayScores.count) days")
                } else {
                    // No data for the period before (days the app wasn't used have no rows).
                    Text("\(range.phrase) · nothing before to compare")
                }
            }
            .font(.caption)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .transition(.blurReplace)
            .id(showSplit)
        }
    }

    /// Consecutive arcs for Early, On time, Late, Qaza (Missed is the bare track), with a small
    /// gap between them.
    private func segments(_ stats: InsightsStats, total: Int) -> [(from: Double, to: Double, color: Color)] {
        var start = 0.0
        var result: [(Double, Double, Color)] = []
        for item in stats.grades where item.grade != .missed && item.count > 0 {
            let length = Double(item.count) / Double(total)
            // Leave room for the round caps so neighbouring pieces read as separate.
            result.append((start + 0.006, start + max(length - 0.006, 0.007), item.grade.color))
            start += length
        }
        return result
    }

    // MARK: Streaks — one quiet line

    private var streaks: some View {
        HStack(spacing: 22) {
            streakItem("heart.fill", value: max(streak, 0), label: "day streak", best: maxStreak)
            streakItem("sparkles", value: onTimeStreak, label: "in-time days", best: maxOnTimeStreak)
        }
    }

    private func streakItem(_ symbol: String, value: Int, label: String, best: Int) -> some View {
        let shown = revealed ? value : 0
        return HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.green)
            Text("\(shown)")
                .fontWeight(.medium)
                .contentTransition(.numericText(value: Double(shown)))
            Text(label).foregroundStyle(.secondary)
            Text("· best \(best)").foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .fontWeight(.light)
    }

}

// MARK: - Range & stats

enum InsightsRange: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", all = "All time"
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }
    var phrase: String {
        switch self {
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .all: "all time"
        }
    }
    var previousPhrase: String {
        switch self {
        case .week: "week before"
        case .month: "month before"
        case .all: "before"
        }
    }
}

enum InsightsGrade: String, CaseIterable {
    case early = "Early", onTime = "On time", late = "Late", qaza = "Qaza", missed = "Missed"
    var color: Color {
        switch self {
        case .early: .green
        case .onTime: .yellow
        case .late: .red
        case .qaza: .gray
        case .missed: Color(.tertiarySystemFill)
        }
    }
}

struct InsightsStats {
    struct DayPoint: Identifiable { let day: Date; let score: Double; var id: Date { day } }
    struct PrayerStat: Identifiable {
        let name: String
        let average: Double?     // points of the prayed ones, 0…1
        let prayedRate: Double?  // prayed / (prayed + missed)
        var prayed = 0           // marked in the range
        var recorded = 0         // marked + missed (window over) in the range
        var id: String { name }
    }

    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    let dayScores: [DayPoint]          // in range, finished days, chronological
    let average: Double?
    let previousAverage: Double?       // the period before, same length
    let perPrayer: [PrayerStat]
    let grades: [(grade: InsightsGrade, count: Int)]

    init(prayers: [PrayerModel], range: InsightsRange, now: Date = Date()) {
        let cal = Calendar.current
        let today = PrayerDay.start(for: now)
        var byDay: [Date: [PrayerModel]] = [:]
        for p in prayers { byDay[cal.startOfDay(for: p.startTime), default: []].append(p) }

        let firstDay = byDay.keys.min() ?? today
        let start = range.days.map { cal.date(byAdding: .day, value: -$0, to: today) ?? today } ?? firstDay

        // Day scores: finished days in range.
        let finished = byDay.keys.filter { $0 < today }.sorted()
        dayScores = finished.filter { $0 >= start }.map { DayPoint(day: $0, score: PrayerScoring.dayScore(for: byDay[$0] ?? [])) }
        average = dayScores.isEmpty ? nil : dayScores.map(\.score).reduce(0, +) / Double(dayScores.count)
        if let days = range.days, let prevStart = cal.date(byAdding: .day, value: -days, to: start) {
            let prev = finished.filter { $0 >= prevStart && $0 < start }.map { PrayerScoring.dayScore(for: byDay[$0] ?? []) }
            previousAverage = prev.isEmpty ? nil : prev.reduce(0, +) / Double(prev.count)
        } else {
            previousAverage = nil
        }

        // Prayers in range whose outcome is known: marked, or window over and unmarked.
        let inRange = prayers.filter { $0.startTime >= start && ($0.isCompleted || $0.endTime < now) }
        perPrayer = Self.names.map { name in
            let rows = inRange.filter { $0.name == name }
            let prayed = rows.filter(\.isCompleted)
            let avg = prayed.isEmpty ? nil : prayed.compactMap(\.numberScore).reduce(0, +) / Double(prayed.count)
            return PrayerStat(name: name, average: avg, prayedRate: rows.isEmpty ? nil : Double(prayed.count) / Double(rows.count),
                              prayed: prayed.count, recorded: rows.count)
        }
        var counts: [InsightsGrade: Int] = [:]
        for p in inRange {
            if p.isCompleted, let s = p.numberScore {
                switch PrayerScoring.grade(for: s) {
                case .early: counts[.early, default: 0] += 1
                case .onTime: counts[.onTime, default: 0] += 1
                case .late: counts[.late, default: 0] += 1
                case .qaza: counts[.qaza, default: 0] += 1
                }
            } else if !p.isCompleted {
                counts[.missed, default: 0] += 1
            }
        }
        grades = InsightsGrade.allCases.map { ($0, counts[$0] ?? 0) }

    }

    var bestPrayer: PrayerStat? {
        perPrayer.filter { $0.average != nil }.max { ($0.average ?? 0) < ($1.average ?? 0) }
    }
    /// The one that most needs attention: least often prayed, then lowest average.
    var weakestPrayer: PrayerStat? {
        perPrayer.filter { $0.prayedRate != nil }.min {
            let a = ($0.prayedRate ?? 1, $0.average ?? 0), b = ($1.prayedRate ?? 1, $1.average ?? 0)
            return a < b
        }
    }
}

// MARK: - Prayer trends

/// Five rows (Fajr … Isha) × the last 14 days. A prayed one is a quiet filled square, a missed
/// one an outline, a day without data a faint dot — so it reads as "how many did I pray" at a
/// glance. Tap one to reveal its colour (the score) and its details underneath; colours stay
/// hidden otherwise (owner: "I don't want all the colors seen right away"). Today is the last
/// column; its upcoming prayers are faint.
private struct PrayerTrendsGrid: View {
    let prayers: [PrayerModel]
    let revealed: Bool

    private static let dayCount = 14
    private struct Cell: Hashable { let name: String; let day: Int }
    @State private var selected: Cell?
    @State private var gridWidth: CGFloat = 0
    /// What was selected when the finger went down: lifting on that same square without moving
    /// to another one deselects it (tap again to hide).
    @State private var selectionAtTouch: Cell??
    @State private var movedToOther = false

    private static let labelWidth: CGFloat = 50
    private static let spacing: CGFloat = 5
    private var cellSize: CGFloat {
        max((gridWidth - Self.labelWidth - Self.spacing * CGFloat(Self.dayCount)) / CGFloat(Self.dayCount), 1)
    }

    /// The square under a point in the grid's own coordinates.
    private func cell(at point: CGPoint) -> Cell? {
        let step = cellSize + Self.spacing
        let col = Int(floor((point.x - Self.labelWidth - Self.spacing) / step))
        let row = Int(floor(point.y / step))
        guard (0..<Self.dayCount).contains(col), InsightsStats.names.indices.contains(row) else { return nil }
        return Cell(name: InsightsStats.names[row], day: col)
    }

    /// Touch down anywhere on the grid and slide: the square under the finger is selected, with a
    /// light tick on each new one. A tap is the same gesture without the slide.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if selectionAtTouch == nil { selectionAtTouch = .some(selected); movedToOther = false }
                guard let hit = cell(at: value.location), hit != selected else { return }
                movedToOther = true
                triggerSomeVibration(type: .light)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { selected = hit }
            }
            .onEnded { value in
                // Tapped the square that was already showing: hide it.
                if case .some(let start) = selectionAtTouch, let start, !movedToOther,
                   cell(at: value.location) == start, abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selected = nil }
                }
                selectionAtTouch = nil
            }
    }

    var body: some View {
        let cal = Calendar.current
        let today = PrayerDay.start()
        let days = (0..<Self.dayCount).map { cal.date(byAdding: .day, value: $0 - (Self.dayCount - 1), to: today) ?? today }
        var rows: [Date: [String: PrayerModel]] = [:]
        let first = days.first ?? today
        for p in prayers where p.startTime >= first {
            rows[cal.startOfDay(for: p.startTime), default: [:]][p.name] = p
        }
        let selectedPrayer = selected.flatMap { rows[days[$0.day]]?[$0.name] }

        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: Self.spacing) {
                ForEach(InsightsStats.names, id: \.self) { name in
                    HStack(spacing: Self.spacing) {
                        Text(name.lowercased())
                            .font(.caption2)
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                            .frame(width: Self.labelWidth, alignment: .trailing)
                        ForEach(days.indices, id: \.self) { i in
                            let cell = Cell(name: name, day: i)
                            square(for: rows[days[i]]?[name], selected: selected == cell)
                                .opacity(revealed ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.015 * Double(i) + 0.1), value: revealed)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .gesture(scrub)

            Group {
                if let cell = selected {
                    detail(name: cell.name, day: days[cell.day], prayer: selectedPrayer)
                } else {
                    Text("last 14 days · tap a square to see it")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .fontWeight(.light)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .transition(.blurReplace)
            .id(selected)
        }
    }

    private func square(for prayer: PrayerModel?, selected: Bool) -> some View {
        let prayed = prayer?.isCompleted == true
        let over = prayer.map { $0.isCompleted || $0.endTime < Date() } ?? false
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(selected && prayed ? PrayerScoring.color(for: prayer?.numberScore)
                  : prayed ? Color.primary.opacity(0.28)
                  : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.6)
                                  : over ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06),
                                  lineWidth: selected ? 1.5 : 1)
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(selected ? 1.18 : 1)
            .shadow(color: selected && prayed ? PrayerScoring.color(for: prayer?.numberScore).opacity(0.5) : .clear, radius: 4)
            .contentShape(Rectangle())
    }

    private func detail(name: String, day: Date, prayer: PrayerModel?) -> some View {
        VStack(spacing: 3) {
            Text("\(name) · \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            if let prayer {
                if prayer.isCompleted, let score = prayer.numberScore {
                    let prayedAt = prayer.timeAtComplete.map { " · prayed \(shortTimePM($0))" } ?? ""
                    Text("\(PrayerScoring.summary(for: score))\(prayedAt)")
                        .foregroundStyle(PrayerScoring.color(for: score))
                } else if prayer.endTime < Date() {
                    Text("Missed").foregroundStyle(.secondary)
                } else {
                    Text("Not yet").foregroundStyle(.secondary)
                }
                Text("window \(shortTime(prayer.startTime)) – \(shortTimePM(prayer.endTime))")
                    .foregroundStyle(.secondary)
            } else {
                Text("no data for this day").foregroundStyle(.secondary)
            }
        }
    }
}
