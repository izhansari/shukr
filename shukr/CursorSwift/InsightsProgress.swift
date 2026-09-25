//
//  InsightsProgress.swift
//  shukr
//
//  Insights → "am I getting better, which prayers am I best / worst at?" (2026-09-25). The owner
//  tried four prototypes and picked a mix of A (verdict + ranked list) and B (sparklines): a
//  verdict line, then the five prayers best → worst, each with an 8-week line, its score for
//  the last 4 weeks and the change against the 4 before. Drag along a line to read any week.
//  A prayer's score counts a missed prayer as 0, so "better" = more consistent *and* on time.
//

import SwiftUI
import Charts

// MARK: - Data

struct ProgressData {
    struct PrayerProgress: Identifiable {
        let name: String
        let recent: Double?     // last 4 weeks, 0…1
        let previous: Double?   // the 4 weeks before
        let weekly: [Double?]   // last 8 weeks, oldest first
        var id: String { name }
        var delta: Double? { recent.flatMap { r in previous.map { r - $0 } } }
    }

    let prayers: [PrayerProgress]
    let overallRecent: Double?
    let overallPrevious: Double?
    let overallWeekly: [(week: Date, score: Double?)]   // last 12 weeks

    var overallDelta: Double? { overallRecent.flatMap { r in overallPrevious.map { r - $0 } } }

    init(prayers rows: [PrayerModel], now: Date = Date()) {
        let cal = Calendar.current
        let today = PrayerDay.start(for: now)
        // Only prayers whose outcome is known: marked, or window over.
        let known = rows.filter { $0.startTime < today.addingTimeInterval(86_400) && ($0.isCompleted || $0.endTime < now) }
        func points(_ p: PrayerModel) -> Double { p.isCompleted ? (p.numberScore ?? 0) : 0 }
        func average(_ list: [PrayerModel]) -> Double? {
            list.isEmpty ? nil : list.map(points).reduce(0, +) / Double(list.count)
        }
        func between(_ fromDays: Int, _ toDays: Int) -> [PrayerModel] {
            let from = cal.date(byAdding: .day, value: -fromDays, to: today) ?? today
            let to = cal.date(byAdding: .day, value: -toDays, to: today) ?? today
            return known.filter { $0.startTime >= from && $0.startTime < to }
        }
        let recentRows = between(28, -1)
        let previousRows = between(56, 28)

        prayers = InsightsStats.names.map { name in
            let weekly: [Double?] = (0..<8).reversed().map { w in
                average(between(7 * (w + 1), 7 * w - (w == 0 ? 1 : 0)).filter { $0.name == name })
            }
            return PrayerProgress(name: name,
                                  recent: average(recentRows.filter { $0.name == name }),
                                  previous: average(previousRows.filter { $0.name == name }),
                                  weekly: weekly)
        }
        overallRecent = average(recentRows)
        overallPrevious = average(previousRows)
        overallWeekly = (0..<12).reversed().map { w in
            let start = cal.date(byAdding: .day, value: -7 * (w + 1) + 1, to: today) ?? today
            return (start, average(between(7 * (w + 1) - 1, 7 * w - 1)))
        }
    }

    var ranked: [PrayerProgress] { prayers.filter { $0.recent != nil }.sorted { ($0.recent ?? 0) > ($1.recent ?? 0) } }
}

private func pts(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))" } ?? "–" }

private func deltaLabel(_ d: Double?) -> some View {
    let value = Int(((d ?? 0) * 100).rounded())
    return Text(d == nil ? "new" : value == 0 ? "±0" : "\(value > 0 ? "↑" : "↓") \(abs(value))")
        .font(.caption.weight(.medium))
        .foregroundStyle(d == nil || value == 0 ? .secondary : value > 0 ? Color.green : Color.red)
        .monospacedDigit()
}

private func verdict(_ d: Double?) -> (title: String, symbol: String) {
    guard let d else { return ("Not enough history yet", "hourglass") }
    if d >= 0.03 { return ("You're getting better", "arrow.up.right") }
    if d <= -0.03 { return ("Slipping a little", "arrow.down.right") }
    return ("Holding steady", "equal")
}


// MARK: - Progress list

struct PrayerProgressList: View {
    let prayers: [PrayerModel]

    var body: some View {
        let data = ProgressData(prayers: prayers)
        let v = verdict(data.overallDelta)
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: v.symbol).foregroundStyle(.green)
                    Text(v.title).font(.title3.weight(.light))
                }
                if let d = data.overallDelta {
                    Text("\(d >= 0 ? "+" : "−")\(abs(Int((d * 100).rounded()))) points over the last 4 weeks")
                        .font(.caption.weight(.light))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                let rows = data.ranked + data.prayers.filter { $0.recent == nil }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, p in
                    ProgressRow(rank: index + 1, progress: p)
                    if index < rows.count - 1 { Divider().opacity(0.4) }
                }
            }
            Text("best at the top · last 4 weeks · drag a line to see any week")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ProgressRow: View {
    let rank: Int
    let progress: ProgressData.PrayerProgress
    /// Week index under the finger while scrubbing the line.
    @State private var scrubbed: Int?

    var body: some View {
        let weeks = progress.weekly
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Image(systemName: prayerIcon(for: progress.name))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(progress.name)
                .font(.subheadline.weight(.light))
                .frame(width: 62, alignment: .leading)
            Chart {
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, value in
                    if let value {
                        LineMark(x: .value("Week", i), y: .value("Score", value * 100))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(Color.green)
                    }
                }
                if let i = scrubbed, let value = weeks[i] {
                    RuleMark(x: .value("Week", i))
                        .foregroundStyle(Color.primary.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Week", i), y: .value("Score", value * 100))
                        .symbolSize(40)
                        .foregroundStyle(Color.green)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...(weeks.count - 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    guard let frame = proxy.plotFrame.map({ geo[$0] }) else { return }
                                    let x = drag.location.x - frame.origin.x
                                    guard let raw: Double = proxy.value(atX: x) else { return }
                                    let i = min(max(Int(raw.rounded()), 0), weeks.count - 1)
                                    if i != scrubbed {
                                        triggerSomeVibration(type: .light)
                                        scrubbed = i
                                    }
                                }
                                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrubbed = nil } }
                        )
                }
            }
            .frame(height: 30)

            // Score + change, or the scrubbed week's score + date.
            Group {
                if let i = scrubbed {
                    Text(pts(weeks[i]))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.green)
                    Text(weekLabel(i, of: weeks.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(pts(progress.recent)).font(.subheadline.weight(.medium))
                    deltaLabel(progress.delta)
                }
            }
            .monospacedDigit()
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    /// "Sep 1" for the week `i` of `count` (the last one is this week).
    private func weekLabel(_ i: Int, of count: Int) -> String {
        let today = PrayerDay.start()
        let start = Calendar.current.date(byAdding: .day, value: -7 * (count - i) + 1, to: today) ?? today
        return start.formatted(.dateTime.month(.abbreviated).day())
    }
}
