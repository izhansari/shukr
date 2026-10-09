//
//  GestureHint.swift
//  shukr
//
//  A ghost finger for the counting lessons (owner, 2026-10-08: "add graphics of touches and drags and continuous drags
//  to our zikr tour"): a soft touch dot that shows the move — a tap, a drag down then lift, or down and up without
//  lifting — looping in the counter's empty space above the ring. Never takes a touch; gone once they've done it once.
//

import SwiftUI

struct GestureHint: View {
    enum Kind { case tap, drag, stroke }
    let kind: Kind
    /// The room it has (between the top bar and the ring); the finger travels most of it.
    var height: CGFloat = 200
    /// Held on its still frame (the practice page's boxes that aren't the one to try now).
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var frozen: Bool { reduceMotion || still }

    private static let dot: CGFloat = 22        // the touch's radius
    private static let top: CGFloat = 32        // the dot's centre, clear of the room's edge
    private var travel: CGFloat { max(40, height - Self.top * 2) }

    private var loop: Double {
        switch kind { case .tap: 1.5; case .drag: 1.9; case .stroke: 3.2 }
    }

    var body: some View {
        TimelineView(.animation(paused: frozen)) { ctx in
            // Reduce Motion (or held still): one frame mid-move (the dot, its trail).
            let t = frozen ? stillFrame : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
            Canvas { gc, size in draw(&gc, size: size, t: t) }
        }
        .frame(width: 120, height: max(height, Self.top * 2 + 40))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stillFrame: Double {
        switch kind { case .tap: 0.2; case .drag: 0.7; case .stroke: 1.2 }
    }

    // MARK: the move, as (where the dot is, how pressed / shown it is) over the loop

    /// The finger's height at time `t`, nil while it's up.
    private func y(at t: Double) -> CGFloat? {
        let top = Self.top, bottom = Self.top + travel
        switch kind {
        case .tap:
            return t < 0.55 ? top + travel / 2 : nil
        case .drag:
            // Down, then lifted at the bottom.
            guard t >= 0, t < 1.05 else { return nil }
            let p = smooth(clamp((t - 0.15) / 0.7))
            return top + (bottom - top) * p
        case .stroke:
            // Down, up, down, up, down — the finger never lifts.
            guard t >= 0, t < 2.75 else { return nil }
            let p = clamp((t - 0.15) / 2.4)
            let wave = (1 - cos(p * .pi * 5)) / 2      // 0 → 1 → 0 → 1 → 0 → 1
            return top + (bottom - top) * wave
        }
    }

    /// 0…1: fades in as it lands, out as it lifts.
    private func shown(at t: Double) -> Double {
        let up: Double = switch kind { case .tap: 0.55; case .drag: 1.05; case .stroke: 2.75 }
        let inn = clamp(t / 0.12)
        let out = clamp((up - t) / 0.18)
        return min(inn, out)
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let x = size.width / 2
        let ink = Color.primary

        // The trail behind a moving finger: the last ~0.35 s of its path, fading.
        if kind != .tap {
            var path = Path()
            var started = false
            let steps = 14
            for i in 0...steps {
                let back = t - 0.35 * Double(steps - i) / Double(steps)
                guard back >= 0.15, let y = y(at: back) else { continue }
                if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
            }
            if started {
                gc.stroke(path, with: .color(ink.opacity(0.10 * shown(at: t))),
                          style: StrokeStyle(lineWidth: Self.dot * 1.3, lineCap: .round, lineJoin: .round))
            }
        }

        // A tap's ripple, out from where it pressed.
        if kind == .tap, t > 0.1, t < 0.9 {
            let p = (t - 0.1) / 0.8
            let r = Self.dot + 30 * p
            let c = CGPoint(x: x, y: Self.top + travel / 2)
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                      with: .color(ink.opacity(0.28 * (1 - p))), lineWidth: 2)
        }

        guard let y = y(at: t) else { return }
        let a = shown(at: t)
        // Pressed: a little smaller while down, a touch bigger as it lands and lifts.
        let r = Self.dot * (1 + 0.15 * (1 - a))
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        gc.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.16 * a)))
        gc.stroke(Path(ellipseIn: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(ink.opacity(0.38 * a)), lineWidth: 1.5)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }
}

#Preview {
    HStack(spacing: 20) {
        GestureHint(kind: .tap)
        GestureHint(kind: .drag)
        GestureHint(kind: .stroke)
    }
}

/// The hint's place on the counter: centred in the room between the top bar and the ring, as tall as that room (a
/// small phone gets a shorter drag). Nothing when there's no room for one.
struct CounterGestureHint: View {
    let kind: GestureHint.Kind?

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let targets = TourTargets.shared
            let top = (targets.frame("ct.finish").map { $0.maxY - origin.y } ?? 100) + 12
            let bottom = (targets.frame("ct.ring").map { $0.minY - origin.y } ?? proxy.size.height * 0.38) - 12
            ZStack {
                if let kind, bottom - top > 100 {
                    GestureHint(kind: kind, height: bottom - top)
                        .id(kind)
                        .position(x: proxy.size.width / 2, y: (top + bottom) / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: kind)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
