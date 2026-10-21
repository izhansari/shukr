//
//  YourPrayers.swift
//  shukr
//
//  Prayer scores as "Your prayers" (prayer-metrics rethink, behind MetricsLook): the five prayers' last 7 days for Journey's
//  row (PrayerMetrics.recent, Fable's data layer) and the page's ring — each prayer's usual place in its window, a prayer's
//  fifth unfolding into its whole window. The page's motion (the row rising into the header, the
//  back dial) is PrayerScoresPage's.
//

import SwiftUI

/// The five prayers' last 7 days (PrayerMetrics.recent), read off the main thread when the log changes.
@MainActor @Observable final class YourPrayersRecent {
    static let shared = YourPrayersRecent()
    private(set) var byName: [String: PrayerMetrics.PrayerRecent] = [:]
    @ObservationIgnored private var readFor: UUID?
    /// The latest read: an older one landing after it is dropped (Frank's check: a version change, then Excused.changed).
    @ObservationIgnored private var token = 0

    /// Reads them for `log` once per version (a reload under the same log costs nothing).
    func read(_ log: JourneyLog?, force: Bool = false) {
        guard let log, force || readFor != log.version else { return }
        readFor = log.version
        token += 1
        let mine = token, excused = Excused.Days(), now = Date()
        Task.detached(priority: .userInitiated) {
            var out: [String: PrayerMetrics.PrayerRecent] = [:]
            for name in JourneyLog.names { out[name] = PrayerMetrics.recent(name, in: log, excused: excused, now: now) }
            await MainActor.run { if mine == self.token, out != self.byName { self.byName = out } }
        }
    }

    var inTime: Int { byName.values.reduce(0) { $0 + $1.inTime } }
    var asked: Int { byName.values.reduce(0) { $0 + $1.asked } }

    /// "usually by 6:00 · 4 min from your best month" (nil before there's a usual).
    func usualWords(_ name: String) -> String? {
        guard let r = byName[name], let clock = r.usualClock else { return nil }
        var words = "Usually by \(clock.formatted(date: .omitted, time: .shortened))"
        if let m = r.minutesFromBestMonth, let best = r.bestMonth {
            words += m == 0 ? " · as in your best month" : " · \(m) min from your best month (\(best.start.formatted(.dateTime.month(.abbreviated))))"
        }
        return words
    }
}

/// Your prayers' ring (owner, 2026-10-20). All five: the day ring's fifths, each prayer's hollow dot at its usual place in its
/// window over the span, the fifth in that third's colour; a tap on a fifth opens it. A prayer open, its fifth unfolds into
/// its whole window — the thirds come apart into their colours and the dot turns round to the same place on the full ring
/// ("transition the fifth to its ring dividing it into colors and turning the dot smoothly"), the other fifths gone first.
/// No tap open (tried: a tap swapped in the latest mark's clock time — owner: "That means nothing to me because I don't even
/// know the window"). The way back folds it on the page's dial (ScoresBack): the fold with the rows, the others in last.
struct YourPrayersRing: View {
    /// Each prayer's usual place (DayRing.order), nil before there's one.
    let usual: [Double?]
    /// The prayer unfolding or unfolded (kept through the fold back).
    let open: Int?
    /// At rest: unfolded, the other fifths shown.
    let unfolded: Bool
    let othersShown: Bool
    let dial: JourneyMonthDial?
    let onPick: (Int) -> Void

    var body: some View {
        // On the dial (the way back), read here so only the ring redraws a frame: the fold with the rows, the others last.
        let c = dial.map { 1 - $0.dial }
        let unfold = c.map { 1 - ScoresBack.unfold($0) } ?? (unfolded ? 1 : 0)
        let others = c.map { ScoresBack.fadeIn($0) } ?? (othersShown ? 1 : 0)
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let mine = i == open
                YourPrayersFifth(index: i, usual: usual[i], unfold: mine ? unfold : 0)
                    .opacity(mine ? 1 : others)
            }
        }
        // The Salah ring's own move for the unfold (CircleMotion.ringMove); the dial drives it frame by frame.
        .animation(dial == nil ? CircleMotion.ringMove : nil, value: unfolded)
        .frame(width: 200, height: 200)
        .contentShape(Circle().stroke(lineWidth: 46))
        .gesture(SpatialTapGesture().onEnded { tap in
            guard !unfolded else { return }
            let dx = tap.location.x - 100, dy = tap.location.y - 100
            var turn = atan2(dx, -dy) / (2 * .pi)   // 0 at the top, clockwise
            if turn < 0 { turn += 1 }
            onPick(min(Int(turn * 5), 4))
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if let open, unfolded {
            let name = DayRing.order[open]
            return usual[open].map { "\(name): usually \(Int(($0 * 100).rounded())) percent into its window" } ?? "\(name): not enough times yet"
        }
        return DayRing.order.indices.map { i in
            usual[i].map { "\(DayRing.order[i]): usually \(Int(($0 * 100).rounded())) percent into its window" } ?? "\(DayRing.order[i]): not enough times yet"
        }.joined(separator: ", ")
    }
}

/// One prayer's fifth, `unfold` of the way to its whole window (0 its fifth … 1 the full ring, its start at the top). Every
/// place in the window maps to an angle between the two, so the thirds, the lit part and the dot all travel together.
private struct YourPrayersFifth: View, Animatable {
    let index: Int
    var usual: Double?
    var unfold: CGFloat

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(unfold, usual ?? 0) }
        set {
            unfold = newValue.first
            if usual != nil { usual = newValue.second }
        }
    }

    @Environment(\.circleTheme) private var theme
    private static let r: CGFloat = 100
    /// The thirds' gap on the full ring, degrees.
    private static let gap = 2.4

    /// A place in the window (0…1) as an angle from the top, degrees.
    private func angle(_ f: Double) -> Double {
        let u = Double(unfold)
        let a0 = 360 * (Double(index) / 5 + DayRing.gap), a1 = 360 * (Double(index + 1) / 5 - DayRing.gap)
        let b0 = Self.gap / 2, b1 = 360 - Self.gap / 2
        return (a0 + f * (a1 - a0)) * (1 - u) + (b0 + f * (b1 - b0)) * u
    }

    /// The grade colour a mark at `share` of the window gets (past 1: made up).
    private static func color(at share: Double) -> Color {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return PrayerScoring.color(for: PrayerScoring.score(start: start, end: start.addingTimeInterval(1_000),
                                                            markedAt: start.addingTimeInterval(1_000 * share)))
    }

    var body: some View {
        let u = Double(unfold)
        let w = theme.arc.width * (0.5 + 0.6 * unfold)
        let style = StrokeStyle(lineWidth: w, lineCap: theme.arc.cap)
        let o = PrayerScoring.openingShare, m = o + (1 - o) / 2
        let zones: [(Double, Double)] = [(0, o), (o, m), (m, 1)]
        ZStack {
            if usual == nil {
                // No usual yet: the day ring's faint dotted track, the thirds faint as it unfolds.
                arc(angle(0), angle(1))
                    .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: w, lineCap: .round, dash: [1, 7]))
                    .opacity(1 - u)
            }
            ForEach(0..<3, id: \.self) { k in
                let (f0, f1) = zones[k]
                let a0 = angle(f0) + (k > 0 ? Self.gap / 2 * u : 0), a1 = angle(f1) - (k < 2 ? Self.gap / 2 * u : 0)
                arc(a0, a1).stroke(Self.color(at: (f0 + f1) / 2).opacity(0.16), style: style).opacity(u)
            }
            if let usual { mark(usual, zones: zones, style: style) }
        }
        .frame(width: 200, height: 200)
    }

    /// Lit up to your usual place and its hollow dot: one colour as a fifth (the dot's third), coming apart into the thirds'
    /// as it unfolds.
    @ViewBuilder private func mark(_ share: Double, zones: [(Double, Double)], style: StrokeStyle) -> some View {
        let u = Double(unfold)
        let dot = min(max(share, 0), 1)
        let dotColor = Self.color(at: share)
        let litTo = 1 * (1 - u) + dot * u
        ZStack {
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    let (f0, f1) = zones[k]
                    let a0 = angle(f0) + (k > 0 ? Self.gap / 2 * u : 0), a1 = min(angle(f1) - (k < 2 ? Self.gap / 2 * u : 0), angle(litTo))
                    if a1 > a0 + 0.5 {
                        arc(a0, a1).stroke(dotColor.mix(with: Self.color(at: (f0 + f1) / 2), by: u), style: style)
                    }
                }
            }
            .compositingGroup()   // as a fifth, one colour: its pieces' caps never double up
            .opacity(0.72 + 0.28 * u)
            let size = 12 + 4.6 * unfold
            Circle().fill(theme.surface)
                .overlay(Circle().strokeBorder(dotColor, lineWidth: 2.4 + 0.7 * unfold))
                .frame(width: size, height: size)
                .position(point(angle(dot) * .pi / 180, Self.r))
        }
    }

    /// A point at `radians` from the top, clockwise, `radius` from the centre.
    private func point(_ radians: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: 100 + radius * sin(radians), y: 100 - radius * cos(radians))
    }

    private func arc(_ from: Double, _ to: Double) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: 100, y: 100), radius: Self.r, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}
