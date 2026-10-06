import SwiftUI
import SwiftData

// The end-of-day page (decision day-score-end, Izhan: "they dont get the same reward out as the effort they put in"):
// the ring shows the day — five fifths in their prayers' colours, a dot where in each window it was prayed — round
// the score and "4 of 5 in time"; a tap on a fifth tells that prayer; under the circle one line from `DayInsight`
// (with the Fajr alarm when it helps); a full day glows once. Mockups: board/mocks/day-score-mocks/v3.

extension DayPrayer {
    init(_ row: PrayerModel) {
        self.init(name: row.name, start: row.startTime, end: row.endTime,
                  markedAt: row.isCompleted ? row.timeAtComplete : nil,
                  score: row.isCompleted ? row.numberScore : nil)
    }
}

/// Whether the circle is showing the day's page (summaryCircle is up): the list's card rises with it, not at the mark
/// (Izhan: "have it rise together with the page").
@MainActor @Observable final class DayPageState {
    static let shared = DayPageState()
    var up = false
}

/// The day's five prayers round the circle (Fajr at the top, clockwise), on the ring's own band.
struct DayRing: View {
    let day: [DayPrayer]
    let picked: Int?
    let onPick: (Int) -> Void
    @Environment(\.circleTheme) private var theme

    static let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private static let gap = 0.014

    var body: some View {
        let style = StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap)
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let from = Double(i) / 5 + Self.gap, to = Double(i + 1) / 5 - Self.gap
                let p = Self.order.indices.contains(i) ? day.first { $0.name == Self.order[i] } : nil
                let on = picked == nil || picked == i
                ZStack {
                    if let p, p.done {
                        let color = PrayerScoring.color(for: p.score)
                        Circle().trim(from: from, to: to)
                            .stroke(color.opacity(picked == i ? 1 : 0.72), style: style)
                        if let share = p.share {
                            // When in its window it was prayed.
                            Circle().fill(color)
                                .frame(width: picked == i ? 13 : 9, height: picked == i ? 13 : 9)
                                .overlay(Circle().stroke(theme.backdrop, lineWidth: 2.5))
                                .offset(x: 100)
                                .rotationEffect(.degrees(360 * (from + (to - from) * share)))
                        }
                    } else {
                        // Not marked: the fifth stays a faint track.
                        Circle().trim(from: from, to: to)
                            .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: theme.arc.width, lineCap: .round, dash: [1, 7]))
                    }
                }
                .opacity(on ? 1 : 0.25)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 200, height: 200)
        // Only the band takes a tap (the centre keeps the circle's own).
        .contentShape(Circle().stroke(lineWidth: 46))
        .gesture(SpatialTapGesture().onEnded { tap in
            let dx = tap.location.x - 100, dy = tap.location.y - 100
            var turn = atan2(dx, -dy) / (2 * .pi)   // 0 at the top, clockwise
            if turn < 0 { turn += 1 }
            onPick(min(Int(turn * 5), 4))
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        Self.order.map { name in
            guard let p = day.first(where: { $0.name == name }), p.done, let s = p.score else { return "\(name): not marked" }
            return "\(name): \(PrayerScoring.grade(for: s).rawValue)"
        }.joined(separator: ", ")
    }
}

/// The centre: the score and "4 of 5 in time", or the tapped prayer.
struct DayCentre: View {
    let day: [DayPrayer]
    let score: Double
    let picked: Int?
    let yesterday: Bool

    var body: some View {
        if let i = picked, DayRing.order.indices.contains(i) {
            let name = DayRing.order[i]
            let p = day.first { $0.name == name }
            VStack(spacing: 3) {
                Text(name).font(.system(size: 30, weight: .light, design: .rounded))
                Text(p?.markedAt.map { "prayed \($0.formatted(date: .omitted, time: .shortened))" } ?? "not marked")
                    .font(.footnote).fontWeight(.thin).fontDesign(.rounded).foregroundStyle(.secondary)
                if let s = p?.score {
                    Text(PrayerScoring.summary(for: s))
                        .font(.caption).fontDesign(.rounded)
                        .foregroundStyle(PrayerScoring.color(for: s).opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 3) {
                Text("\(Int((score * 100).rounded()))")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .contentTransition(.numericText(value: score))
                Text(caption)
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private var caption: String {
        let inTime = day.filter(\.inTime).count
        let words: String
        if inTime == 5 { words = day.allSatisfy(\.perfect) ? "all five early" : "all five in time" }
        else { words = "\(inTime) of 5 in time" }
        return yesterday ? "yesterday · \(words)" : words
    }
}

/// The day's prayers, before today's: one list per prayer day, newest first (yesterday at 0), `days` of them; an
/// empty list for a day with no rows (it breaks a run, as it should).
enum DayHistory {
    @MainActor static func load(_ context: ModelContext, days: Int = 35) -> [[DayPrayer]] {
        let today = PrayerDay.date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days + 2), to: Calendar.current.startOfDay(for: today)) ?? today
        let descriptor = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.startTime >= cutoff })
        guard let rows = try? context.fetch(descriptor) else { return [] }
        // One row per name per day (a completed row wins), grouped by the row's own prayer day.
        var byDay: [String: [String: PrayerModel]] = [:]
        for row in rows {
            let key = row.dayKey
            if let kept = byDay[key]?[row.name], kept.isCompleted, !row.isCompleted { continue }
            byDay[key, default: [:]][row.name] = row
        }
        return (1...days).map { back in
            let date = Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
            return (byDay[PrayerNotificationID.dayKey(date)] ?? [:]).values.map(DayPrayer.init)
        }
    }
}
