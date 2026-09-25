//
//  InsightsView.swift
//  shukr
//
//  Hamburger → Insights (2026-09-25): streaks, day score trend, per-prayer averages, how the
//  prayers split across grades, and a 12-week heatmap, on one page. Everything is computed
//  from the prayer rows with PrayerScoring, so it always matches the current rules.
//  Days with no rows (app not opened) aren't counted; today is left out of day averages
//  until it's over.
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query(sort: \PrayerModel.startTime) private var prayers: [PrayerModel]
    @AppStorage("prayerStreak") private var streak: Int = 0
    @AppStorage("maxPrayerStreak") private var maxStreak: Int = 0
    @AppStorage("onTimeStreak") private var onTimeStreak: Int = 0
    @AppStorage("maxOnTimeStreak") private var maxOnTimeStreak: Int = 0

    @State private var range: InsightsRange = .month
    /// Flips on appear and on every range change; the numbers and rings animate from zero.
    @State private var revealed = false
    /// Tapped prayer ring: its numbers show in the caption under the rings.
    @State private var selectedPrayer: String?
    /// Tapped hero circle: the caption under it shows how the prayers split instead of the trend.
    @State private var showSplit = false
    @State private var hideSplit: DispatchWorkItem?

    var body: some View {
        let stats = InsightsStats(prayers: prayers, range: range)
        VStack(spacing: 28) {
            Picker("Range", selection: $range) {
                ForEach(InsightsRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            hero(stats)
            streaks
            prayerRings(stats)
            HeatmapGrid(days: stats.heatmap, revealed: revealed)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
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

    private func reveal() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { revealed = true }
        }
    }

    // MARK: Hero — the average day score, in a circle like the main page's

    private func hero(_ stats: InsightsStats) -> some View {
        let avg = stats.average ?? 0
        let shown = revealed ? Int((avg * 100).rounded()) : 0
        return VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color(.secondarySystemFill), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: revealed ? avg : 0)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(stats.average == nil ? "–" : "\(shown)")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .contentTransition(.numericText(value: Double(shown)))
                    Text("day score")
                        .font(.footnote)
                        .fontWeight(.thin)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .contentShape(Circle())
            .onTapGesture { toggleSplit() }

            Group {
                if showSplit {
                    Text(splitLine(stats))
                } else if let prev = stats.previousAverage, stats.average != nil {
                    let delta = Int(((avg - prev) * 100).rounded())
                    Text("\(delta >= 0 ? "↑" : "↓") \(abs(delta)) vs the \(range.previousPhrase)")
                } else {
                    Text(range.phrase)
                }
            }
            .font(.caption)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
            .transition(.blurReplace)
            .id(showSplit)
        }
    }

    private func toggleSplit() {
        triggerSomeVibration(type: .light)
        hideSplit?.cancel()
        withAnimation { showSplit.toggle() }
        guard showSplit else { return }
        let work = DispatchWorkItem { withAnimation { showSplit = false } }
        hideSplit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func splitLine(_ stats: InsightsStats) -> String {
        let total = max(stats.grades.map(\.count).reduce(0, +), 1)
        return stats.grades
            .filter { $0.count > 0 }
            .map { "\($0.grade.rawValue.lowercased()) \(Int((Double($0.count) / Double(total) * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    // MARK: Streaks — one quiet line

    private var streaks: some View {
        HStack(spacing: 22) {
            streakItem("heart.fill", value: max(streak, 0), label: "day streak", best: maxStreak)
            streakItem("sparkles", value: onTimeStreak, label: "on time", best: maxOnTimeStreak)
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

    // MARK: Prayer rings — tap one for its numbers

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
                    Text("\(name) · avg \(stat.average.map { "\(Int(($0 * 100).rounded()))" } ?? "–") · prayed \(stat.prayedRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")")
                } else if let best = stats.bestPrayer, let weakest = stats.weakestPrayer, best.name != weakest.name {
                    Text("\(best.name) is your strongest · \(weakest.name) needs the most love")
                } else {
                    Text("tap a prayer")
                }
            }
            .font(.caption)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
            .transition(.blurReplace)
            .id(selectedPrayer ?? "")
        }
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
        var id: String { name }
    }

    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    let dayScores: [DayPoint]          // in range, finished days, chronological
    let average: Double?
    let previousAverage: Double?       // the period before, same length
    let perPrayer: [PrayerStat]
    let grades: [(grade: InsightsGrade, count: Int)]
    let heatmap: [(day: Date, score: Double?)]   // last 12 weeks, week-aligned

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
            return PrayerStat(name: name, average: avg, prayedRate: rows.isEmpty ? nil : Double(prayed.count) / Double(rows.count))
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

        // Heatmap: 12 full weeks ending with this week, starting on the locale's first weekday.
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let gridStart = cal.date(byAdding: .day, value: -7 * 11, to: weekStart) ?? weekStart
        heatmap = (0..<84).map { i in
            let day = cal.date(byAdding: .day, value: i, to: gridStart) ?? gridStart
            let score: Double? = (day < today) ? byDay[day].map { PrayerScoring.dayScore(for: $0) } : nil
            return (day, score)
        }
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

// MARK: - Heatmap

/// 12 weeks, columns = weeks, rows = weekdays; darker green = higher day score. Outline = no
/// data (app not opened); gray = opened but nothing marked. Fades in as a diagonal wave.
private struct HeatmapGrid: View {
    let days: [(day: Date, score: Double?)]
    let revealed: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let entry = days[week * 7 + weekday]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(entry.score.map { $0 > 0 ? Color.green.opacity(0.15 + 0.85 * $0) : Color(.secondarySystemFill) } ?? .clear)
                                .overlay {
                                    if entry.score == nil {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(Color(.secondarySystemFill), lineWidth: 1)
                                    }
                                }
                                .frame(width: 17, height: 17)
                                .opacity(revealed ? 1 : 0)
                                .scaleEffect(revealed ? 1 : 0.4)
                                .animation(.spring(response: 0.5, dampingFraction: 0.75)
                                            .delay(0.012 * Double(week + weekday) + 0.15), value: revealed)
                        }
                    }
                }
            }
            Text("last 12 weeks")
                .font(.caption2)
                .fontWeight(.light)
                .foregroundStyle(.tertiary)
        }
    }
}
