//
//  GoalHero.swift
//  shukr
//
//  Your goal's hero (owner, 2026-10-21, pick K of round 2 — "use the time dial that we have in the prayer editor"; spec
//  board/mocks/your-goal-v2/spec.md, drawn by Zoe): the editor's time dial with no clock — the window's thirds down the
//  left, the hollow dot parked where your goal stops counting — and the four steps as a quiet row under it.
//

import SwiftUI

/// Where each goal stops counting, in windows (0 the start, 1 the end; Prayed reaches past it, into made-up time).
extension PrayerGoal {
    var edge: Double {
        switch self {
        case .perfect: PrayerScoring.openingShare
        case .onTime: 2 * PrayerScoring.openingShare
        case .inWindow: 1
        case .prayed: 1.28
        }
    }
    /// The dot's colour at the edge: the last third it takes in, grey past the window.
    var edgeColor: Color {
        switch self {
        case .perfect: GoalHero.colors[0]
        case .onTime: GoalHero.colors[1]
        case .inWindow: GoalHero.colors[2]
        case .prayed: .gray
        }
    }
    /// The step row's short name (owner, 2026-10-21: "change the tab switcher to say In Window"; the dial keeps the title).
    var stepLabel: String { self == .inWindow ? "In Window" : title }
    static func nearest(to edge: Double) -> PrayerGoal {
        PrayerGoal.allCases.min { abs($0.edge - edge) < abs($1.edge - edge) } ?? .inWindow
    }
}

enum GoalHero {
    /// The Sunday sheet's thirds (GoalThirdsRing): Opening green · Middle yellow · Closing red.
    static let colors = [PrayerScoring.color(for: 1), PrayerScoring.color(for: 0.9), PrayerScoring.color(for: 0.7)]
}

// MARK: - The knob

/// The editor's dial with no clock: a slice of a big ring down the box's left, the window in its thirds, made-up time grey
/// after it. The dot never moves; the arc turns so your goal's edge sits under it. Above the dot (what counts) is lit, below
/// it dim. `labels` writes the steps' names beside their edges (the drag look, where the arc is the picker).
struct GoalKnobArc: View, Animatable {
    var value: Double
    var labels = false
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    @Environment(\.colorScheme) private var scheme

    /// Degrees of arc per window: the whole window fits round the dot (a third is 14°).
    static let degPerWindow = 34.0

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size: size) }
            .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let h = size.height
        // A taller box draws a bigger ring (owner: "expand the graphics height so more of the ring can show"): the same
        // window, more of it in view. (Tried: a fixed curve in a taller box — it ran off the box's left edge.)
        let radius = h * 0.92
        let degPer = Self.degPerWindow
        let dot = CGPoint(x: h * 0.24, y: h * 0.6)
        let centre = CGPoint(x: dot.x - radius, y: dot.y)
        func angle(_ w: Double) -> Angle { .degrees((w - value) * degPer) }
        func point(_ w: Double, _ r: CGFloat) -> CGPoint {
            let a = angle(w).radians
            return CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
        }
        let third = PrayerScoring.openingShare
        let bands: [(Double, Double, Color)] = [(0, third, GoalHero.colors[0]), (third, 2 * third, GoalHero.colors[1]),
                                                (2 * third, 1, GoalHero.colors[2]), (1, 1.6, Color.gray)]
        let ink: Color = scheme == .dark ? .white : .black

        ctx.drawLayer { layer in
            for (a, b, color) in bands {
                var dim = Path(); dim.addArc(center: centre, radius: radius, startAngle: angle(a), endAngle: angle(b), clockwise: false)
                layer.stroke(dim, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                let lit = min(b, value)
                if lit > a {
                    var p = Path(); p.addArc(center: centre, radius: radius, startAngle: angle(a), endAngle: angle(lit), clockwise: false)
                    layer.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                }
            }
            // Ticks: twelve to a window, the thirds' edges and the window's end longer, on the box side.
            var w = 0.0
            while w <= 1.6 + 0.001 {
                let k = Int((w * 12).rounded())
                let major = k % 4 == 0 && w <= 1.001
                var t = Path()
                t.move(to: point(w, radius + 10)); t.addLine(to: point(w, radius + (major ? 19 : 14)))
                layer.stroke(t, with: .color(ink.opacity(major ? 0.45 : 0.18)), lineWidth: 1.4)
                w += 1.0 / 12
            }
            if !labels {
                // The thirds' names beside them, and "made up" past the end.
                let names: [(Double, String)] = [(third / 2, "Opening"), (1.5 * third, "Middle"), (2.5 * third, "Closing"), (1.18, "made up")]
                for (at, name) in names {
                    let text = layer.resolve(Text(name).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary))
                    layer.draw(text, at: point(at, radius + 25), anchor: .leading)
                }
            }
            if labels {
                for goal in PrayerGoal.strictestFirst {
                    let p = point(goal.edge, radius + 26)
                    let text = layer.resolve(Text(goal.title).font(.system(size: 11, weight: goal.edge == value ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(goal.edge == value ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
                    layer.draw(text, at: p, anchor: .leading)
                }
            }
            // The ends fade over the box's top and bottom, as the editor's do.
            let fade = Gradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                        .init(color: .black, location: 0.78), .init(color: .clear, location: 1)])
            layer.blendMode = .destinationIn
            layer.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }

        // The dot: hollow, in the colour of the third it closes, the arc cut out under it.
        let r = CGRect(x: dot.x - 9.5, y: dot.y - 9.5, width: 19, height: 19)
        ctx.blendMode = .clear
        ctx.fill(Path(ellipseIn: r.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black))
        ctx.blendMode = .normal
        let goal = PrayerGoal.nearest(to: value)
        ctx.stroke(Path(ellipseIn: r.insetBy(dx: 1.7, dy: 1.7)), with: .color(goal.edgeColor), lineWidth: 3.4)
    }
}

/// The knob's box: the arc on the left, the step's name and its one grey line on the right (the editor's ring box).
struct GoalKnobBox: View {
    private struct Words: Equatable { let title: String; let line: String }
    let goal: PrayerGoal
    var value: Double
    let line: String
    var labels = false
    var height: CGFloat = 250

    var body: some View {
        ZStack(alignment: .leading) {
            GoalKnobArc(value: value, labels: labels)
            // The step's name and line swap out, then in (a crossfade laid one name over the other).
            OutThenIn(value: Words(title: goal.title, line: line)) { w in
                VStack(alignment: .leading, spacing: 6) {
                    // The drag look names the step beside the dot already (show a fact once).
                    if !labels {
                        Text(w.title)
                            .font(.system(size: 31, weight: .thin, design: .rounded))
                    }
                    Text(w.line)
                        .font(.system(size: labels ? 17 : 14, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, height * 0.24 + (labels ? 108 : 78))
            .padding(.trailing, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - The steps

/// The four steps as one quiet row (no counts): the one tried in ink on a raised capsule, the rest grey.
struct GoalStepRow: View {
    let goal: PrayerGoal
    let current: PrayerGoal
    let pick: (PrayerGoal) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PrayerGoal.strictestFirst) { g in
                Button { pick(g) } label: {
                    Text(g.stepLabel)
                        .font(.system(size: 13.5, weight: g == goal ? .medium : .regular, design: .rounded))
                        .foregroundStyle(g == goal ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if g == goal {
                                Capsule().fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "step", in: ns)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            // Yours, as saved: a small dot under its name while you try others.
                            Circle().fill(Color.primary.opacity(0.35)).frame(width: 4, height: 4)
                                .offset(y: 7)
                                .opacity(g == current && g != goal ? 1 : 0)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(g == goal ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: goal)
    }
    @Namespace private var ns
}
