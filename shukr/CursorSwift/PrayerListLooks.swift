import SwiftUI

// Three trial looks for the prayer list (owner, 2026-10-14: "one of the most high-touched items in our app … I just
// kind of gave up on trying to make it pretty early on"), picked from the palette menu's List picker beside the others
// (SalahLook.rings / .timeline / .now). They change only how a row looks: the row's one gesture, the "N done" fold, the
// day page's lift and the tour's targets are PrayerButton's, untouched. The well round the rows is the public look's.
// Built from docs/design-language.md: the ring holds the state, one thing leads, sage = tap, grey hierarchy.

/// A · Rings — the row's status as a small ring (the ring holds the state): still to come = dashed, on now = the window
/// filling in the colour you'd score now (as the main circle does), prayed = a full ring in its grade colour with a
/// small check, missed = a faint plain ring.
struct PrayerRingGlyph: View {
    enum Kind {
        case future
        case current(start: Date, end: Date)
        case done(Color)
        case missed
        case excused
    }
    let kind: Kind
    let pulse: Int
    static let size: CGFloat = 20
    private static let line: CGFloat = 2.2

    var body: some View {
        Group {
            switch kind {
            case .future:
                Circle().inset(by: 0.8).stroke(Color.secondary.opacity(0.55), style: Self.dashes)
            case .current(let start, let end):
                // The window's fill moves slowly: once every 30 s is plenty (a 20 pt ring).
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let total = max(end.timeIntervalSince(start), 1)
                    let p = min(max(context.date.timeIntervalSince(start) / total, 0.03), 1)
                    let color = PrayerScoring.color(for: PrayerScoring.score(start: start, end: end, markedAt: context.date))
                    ZStack {
                        Circle().inset(by: Self.line / 2).stroke(Color.secondary.opacity(0.2), lineWidth: Self.line)
                        Circle().inset(by: Self.line / 2).trim(from: 0, to: p)
                            .stroke(color, style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            case .done(let color):
                ZStack {
                    Circle().inset(by: Self.line / 2).stroke(color.opacity(0.7), lineWidth: Self.line)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(color.opacity(0.85))
                }
                .modifier(CompletionDotPop(pulse: pulse, color: color))
            case .missed:
                Circle().inset(by: 0.7).stroke(Color.secondary.opacity(0.35), lineWidth: 1.4)
            case .excused:
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.35))
                    Image(systemName: "pause.fill").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color(.systemBackground))
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// Ten short dashes round the ring, as the dot's eight are round its 14 pt.
    private static let dashes: StrokeStyle = {
        let period = CGFloat.pi * (size - 1.6) / 10
        return StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [period * 0.2, period * 0.8])
    }()
}

/// B · Timeline — the day as one thin line through the five dots: lit (sage) where the day has been, faint dashes where
/// it hasn't. Each row draws the piece above its dot and the piece below it down through the gap to the next row, so
/// the rows join; folded "N done" rows leave the first visible row's line running up out of the card, as if from them.
struct TimelineSpine: View {
    /// The dot's centre in the row (PrayerButton's `dotCenter`).
    let dot: CGPoint
    /// How far the line runs past the row's bottom (the gap to the next row).
    let gapBelow: CGFloat
    let showsAbove: Bool
    let showsBelow: Bool
    let litAbove: Bool
    let litBelow: Bool
    /// Room left round the dot (the dot is 14 pt; a little air either side).
    static let clearance: CGFloat = 11

    var body: some View {
        Canvas { ctx, size in
            func piece(from y0: CGFloat, to y1: CGFloat, lit: Bool) {
                guard y1 > y0 else { return }
                var p = Path()
                p.move(to: CGPoint(x: dot.x, y: y0))
                p.addLine(to: CGPoint(x: dot.x, y: y1))
                ctx.stroke(p, with: .color(lit ? Color.sage.opacity(0.75) : Color.secondary.opacity(0.32)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: lit ? [] : [2, 4]))
            }
            if showsAbove { piece(from: 0, to: dot.y - Self.clearance, lit: litAbove) }
            if showsBelow { piece(from: dot.y + Self.clearance, to: size.height, lit: litBelow) }
        }
        .padding(.bottom, -gapBelow)
        .allowsHitTesting(false)
    }
}

/// C · Now — the prayer on now, as a raised block inside the well: its time left where its start time sat, and a slim
/// line under the row filling with the window in the colour you'd score now.
struct NowTimeLeft: View {
    let start: Date
    let end: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.left(until: end, from: context.date))
                .font(.footnote).fontDesign(.rounded).fontWeight(.regular)
                .foregroundStyle(PrayerScoring.color(for: PrayerScoring.score(start: start, end: end, markedAt: context.date)) == .red
                                 ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(Color.secondary))
                .monospacedDigit()
        }
    }
    /// "1 hr 39 min left" · "24 min left" · "under a minute" (minutes only, as the Live Activity card says it).
    static func left(until end: Date, from now: Date) -> String {
        let minutes = Int(end.timeIntervalSince(now) / 60)
        if minutes < 1 { return "under a minute" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? (m > 0 ? "\(h) hr \(m) min left" : "\(h) hr left") : "\(m) min left"
    }
}

struct NowProgressLine: View {
    let start: Date
    let end: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let total = max(end.timeIntervalSince(start), 1)
            let p = min(max(context.date.timeIntervalSince(start) / total, 0.02), 1)
            let color = PrayerScoring.color(for: PrayerScoring.score(start: start, end: end, markedAt: context.date))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule().fill(color.opacity(0.8)).frame(width: max(geo.size.width * p, 3))
                }
            }
            .frame(height: 3)
        }
        .allowsHitTesting(false)
    }
}
