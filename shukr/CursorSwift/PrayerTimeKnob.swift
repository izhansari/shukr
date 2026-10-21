//
//  PrayerTimeKnob.swift
//  shukr
//
//  The editor sheet's ring box as a knob (owner 2026-10-20: "i often slide the thing to choose my time. it's annoying to
//  slide the wheel by hour and min… i guess i imagine just scrolling up and down to change a wheel like turning a knob";
//  then "I want the dial on the left-hand side so that it matches the look of our actual ring"). Specs:
//  board/mocks/prayer-editor/spec-knob.md, spec-knob-v2.md. A slice of a big ring down the box's left side with a fixed
//  hollow dot, the time and score beside it; drag up / down anywhere in the box and the window turns under the dot. Under
//  them, "Originally marked …" whenever the time differs from the mark. The map's prayer page keeps PrayerTimeEditor.
//

import SwiftUI
import UIKit

struct PrayerTimeKnob: View {
    let prayer: PrayerModel
    @Binding var draft: Date
    /// From the prayer's start to now or the next Fajr (the day's rollover).
    let range: ClosedRange<Date>
    /// The knob came to rest after a turn: the sheet saves then (never per minute).
    var onRelease: () -> Void = {}
    /// Write `draft` every minute while it turns (the tour reads it live). Otherwise only at rest: a write re-renders the
    /// whole sheet (map, photo, note), which a flick would do every frame.
    var liveDraft = false
    /// When he marked it (`recordedTimeAtComplete`); nil hides the bar (the tour).
    var marked: Date? = nil
    /// The bar was tapped: back to the marked time.
    var onMarked: () -> Void = {}

    @State private var knob = KnobModel()
    @State private var side: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    /// The tour's practice clock (0 for a real prayer): the time reads on it, the bands don't move.
    private var shift: TimeInterval { PracticeClock.shift(for: prayer) }
    private var start: Date { prayer.startTime }
    private var end: Date { prayer.endTime }
    /// The knob's value in minutes from the prayer's start; its soft stops are the range's ends.
    private var lowMin: Double { range.lowerBound.timeIntervalSince(start) / 60 }
    private var highMin: Double { range.upperBound.timeIntervalSince(start) / 60 }
    private func date(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
    private func minutes(_ d: Date) -> Double { d.timeIntervalSince(start) / 60 }

    /// The minute under the dot (inside the stops, while a rubber band pulls past them): the readout follows the knob
    /// frame by frame, not the draft.
    private var shownDate: Date { date(min(max(knob.value.rounded(), lowMin.rounded(.up)), highMin.rounded(.down))) }
    private var score: Double {
        prayer.isJumuah ? 1 : PrayerScoring.score(start: start, end: end, markedAt: shownDate)
    }

    // The geometry (S = the box side; spec v2: R ≈ 0.9 S, the dot's centre (46/211 S, S/2), the ring's centre off the box to
    // the left, 1.2° a minute).
    private static let degPerMin = 1.2
    private var radius: CGFloat { side * 0.9 }
    private var dot: CGPoint { CGPoint(x: side * 46 / 211, y: side / 2) }
    private var ptPerMin: CGFloat { radius * CGFloat(Self.degPerMin * .pi / 180) }

    /// "Originally marked …" shows while the time on the knob isn't the marked one (live, as it turns).
    private var barShown: Bool {
        guard let marked else { return false }
        return abs(shownDate.timeIntervalSince(marked)) >= 30
    }

    var body: some View {
        // Read here, in body, so every frame of a drag or a coast redraws the arc: read only inside Canvas's closure it went
        // untracked and the arc stepped a whole minute (~4 pt) at a time (Zoe's check, 2026-10-20).
        let value = knob.value
        ZStack {
            ZStack {
                // The arc runs the box's full height; with the bar up it fades out above the bar (animated, never behind it).
                KnobArcLayer(value: value, tail: barShown ? 1 : 0) { ctx, size, v, tail in draw(&ctx, size: size, value: v, tail: tail) }
                    .animation(.easeOut(duration: 0.25), value: barShown)
                readout
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time you prayed")
            .accessibilityValue("\(shortTimePM(shownDate.addingTimeInterval(shift))), \(MetricsLook.on ? "" : "\(PrayerScoring.points(for: score)) ")\(gradeWord)")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 1 : -1
                let next = min(max(knob.value.rounded() + step, lowMin), highMin)
                knob.value = next
                draft = date(next)
                onRelease()
            }
            markedBar
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { min($0.size.width, $0.size.height) } action: { side = $0 }
        .gesture(KnobPan(onBegan: began, onChanged: moved, onEnded: ended))
        .onAppear {
            knob.value = minutes(draft)
            knob.bounds = lowMin...highMin
            knob.live = liveDraft
            knob.onMinute = { m in
                let d = date(Double(m))
                if d != draft { draft = d }
            }
            knob.onRest = { onRelease() }
            knob.boundaries = PrayerScoring.gradeChanges(start: start, end: end).map(minutes) + [minutes(end)]
        }
        .onChange(of: draft) { _, d in
            // Moved from outside (the ↺, an invalid time springing back): the knob turns to it.
            if !knob.busy, abs(minutes(d) - knob.value) >= 0.5 { knob.animate(to: minutes(d)) }
        }
        .onChange(of: range) { _, _ in knob.bounds = lowMin...highMin }
    }

    /// "Originally marked 6:59 PM" across the bottom of the box (owner, 2026-10-20: "maybe the original marked time, we show it
    /// at the bottom of the bento box. That way they know that whatever time is being shown in the bento box is actually
    /// different from when they marked it"; "the pill takes up the whole bottom and centered nicely"; "change it to originally
    /// marked 6:59 p.m."). Its own slot: hidden = clear, nothing moves. Tap = back to the marked time.
    @ViewBuilder private var markedBar: some View {
        if let marked {
            Button(action: onMarked) {
                Text("Originally marked \(shortTimePM(marked.addingTimeInterval(shift)))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(barShown ? 1 : 0)
            .allowsHitTesting(barShown)
            .accessibilityHidden(!barShown)
            .accessibilityLabel("Originally marked \(shortTimePM(marked.addingTimeInterval(shift)))")
            .accessibilityHint("Goes back to the time you marked")
            .animation(.easeOut(duration: 0.2), value: barShown)
        }
    }

    /// "6:59" and "PM" (the locale's own symbols).
    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()
    private static let meridiem: DateFormatter = { let f = DateFormatter(); f.dateFormat = "a"; return f }()

    private var gradeWord: String {
        prayer.isJumuah ? "Jumu'ah" : PrayerScoring.grade(for: score).rawValue
    }

    /// The time ("6:59" + "PM", always: a Qaza can cross noon or midnight) and the score line, centred.
    private var readout: some View {
        let shown = shownDate.addingTimeInterval(shift)
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.clock.string(from: shown))
                    .font(.system(size: side * 44 / 211, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(Self.meridiem.string(from: shown))
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // No roll or fade: a turn changes it every frame or two, and an animation behind the finger showed half-rolled
                // digits and the old word in the new colour (Zoe's check, 2026-10-20). It keeps pace with the time above it.
                // No 0–100 with the rethink (MetricsLook; owner, 2026-10-21, row 12: "get rid of it"): the word alone.
                if !MetricsLook.on {
                    Text("\(PrayerScoring.points(for: score))")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
                Text(gradeWord)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PrayerScoring.color(for: score))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Right of the arc, the time level with the dot (spec v2: x from 66/211 S; time top S/2 − 34, score top S/2 + 22).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.leading, side * 66 / 211)
        .offset(y: side * 8 / 211)
    }

    // MARK: The arc

    /// `tail`: 0 = the arc runs the box's full height; 1 = it fades out above the "Originally marked" bar.
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, value: Double, tail: Double) {
        guard side > 0 else { return }
        // The right-hand edge of a big ring whose centre is off the box to the left; later minutes lie below the dot
        // (clockwise, as the rings run).
        let centre = CGPoint(x: dot.x - radius, y: dot.y)
        // Minutes from the dot either way that fit in the box (and a little past, faded by the mask).
        let span = Double((size.height / 2) / ptPerMin) + 2
        let from = max(lowMin, value - span), to = min(highMin, value + span)
        func angle(_ m: Double) -> Angle { .degrees((m - value) * Self.degPerMin) }
        func point(_ m: Double, _ r: CGFloat) -> CGPoint {
            let a = angle(m).radians
            return CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
        }

        // The ends fade over the top and bottom of the box (drawn into a layer, masked by a vertical gradient).
        ctx.drawLayer { layer in
            // Bands: green → yellow → red → grey (Qaza) after the end; dim, then bright from the start up to the dot.
            for band in bands() where band.to > from && band.from < to {
                let a = max(band.from, from), b = min(band.to, to)
                var dim = Path(); dim.addArc(center: centre, radius: radius, startAngle: angle(a), endAngle: angle(b), clockwise: false)
                layer.stroke(dim, with: .color(band.color.opacity(0.3)), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                let lit = min(b, value)
                if lit > a {
                    var p = Path(); p.addArc(center: centre, radius: radius, startAngle: angle(a), endAngle: angle(lit), clockwise: false)
                    layer.stroke(p, with: .color(band.color), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                }
            }
            // Ticks every 5 min (quarter hours longer), on the box side of the arc, only between the start and now.
            let tickColor: Color = scheme == .dark ? .white : .black
            var m = (from / 5).rounded(.up) * 5
            while m <= to {
                let quarter = Int(m.rounded()) % 15 == 0
                var t = Path()
                t.move(to: point(m, radius + 8)); t.addLine(to: point(m, radius + (quarter ? 15 : 11)))
                layer.stroke(t, with: .color(tickColor.opacity(quarter ? 0.5 : 0.25)), lineWidth: 1.4)
                m += 5
            }
            // The labels at the window's start, its end and now, beside the arc: only above the time or between the score
            // and the bottom (the bar's top when it's up), never on the text.
            let marks: [(Double, String)] = [
                (0, "starts \(shortTimePM(start.addingTimeInterval(shift)))"),
                (minutes(end), "ends \(shortTimePM(end.addingTimeInterval(shift)))"),
                (highMin, "now")]
            let floor = size.height - (tail > 0.5 ? 50 : 14)
            for (at, words) in marks where abs(at - value) >= 7 && abs(at - value) <= 26 && at >= lowMin - 0.5 && at <= highMin + 0.5 {
                let p = point(at, radius + 16)
                guard p.y > 12, p.y < side / 2 - 42 || (p.y > side / 2 + 54 && p.y < floor) else { continue }
                let text = layer.resolve(Text(words).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary))
                layer.draw(text, at: p, anchor: .leading)
            }
            // Top: fades over the first 20 %. Bottom: over the last 20 %, or, with the bar up, gone ~46 pt above the box's
            // bottom (the bar's top) — `tail` animates between the two.
            let h = max(size.height, 1)
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(tail) }
            let fade = Gradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                        .init(color: .black, location: mix(0.8, (h - 70) / h)),
                                        .init(color: .clear, location: mix(1, (h - 46) / h))])
            layer.blendMode = .destinationIn
            layer.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }

        // The dot never moves: hollow, in the score's colour, the arc cut out under it (the box shows through).
        let dot = CGRect(x: self.dot.x - 8.5, y: self.dot.y - 8.5, width: 17, height: 17)
        ctx.blendMode = .clear
        ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1, dy: -1)), with: .color(.black))
        ctx.blendMode = .normal
        let dotScore = PrayerScoring.score(start: start, end: end, markedAt: date(value.rounded()))
        let dotColor = date(value.rounded()) > end ? Color.gray : PrayerScoring.color(for: dotScore)
        ctx.stroke(Path(ellipseIn: dot.insetBy(dx: 1.6, dy: 1.6)), with: .color(dotColor), lineWidth: 3.2)
    }

    /// The window's colour stretches in minutes from the start: green to 30 min, yellow to the middle of the rest, red to the
    /// end, then grey (Qaza) to now.
    private func bands() -> [(from: Double, to: Double, color: Color)] {
        let changes = PrayerScoring.gradeChanges(start: start, end: end).map(minutes)
        let endM = minutes(end)
        var out: [(Double, Double, Color)] = []
        if changes.count == 2 {
            out = [(0, changes[0], .green), (changes[0], changes[1], .yellow), (changes[1], endM, .red)]
        } else {
            out = [(0, endM, .green)]
        }
        if highMin > endM { out.append((endM, highMin, .gray)) }
        return out.map { (from: $0.0, to: $0.1, color: $0.2) }
    }

    // MARK: The gesture

    private func began() { knob.grab() }
    private func moved(_ dy: CGFloat) {
        // Finger up → later times come up from below (clockwise, as the rings).
        knob.drag(to: -Double(dy / ptPerMin))
    }
    private func ended(_ vy: CGFloat, _ resting: Bool) {
        let minPerMs = resting ? 0 : -Double(vy / ptPerMin) / 1000
        knob.release(velocity: minPerMs)
    }
}

// MARK: - The knob's physics

/// The value under the dot (minutes from the start) and its motion: a drag, then a coast with momentum, a settle on a whole
/// minute, soft stops at the range's ends. Ticks a haptic per minute, a light one when a colour boundary crosses the dot.
@Observable
final class KnobModel {
    var value: Double = 0
    @ObservationIgnored var bounds: ClosedRange<Double> = 0...1
    @ObservationIgnored var boundaries: [Double] = []
    @ObservationIgnored var onMinute: (Int) -> Void = { _ in }
    @ObservationIgnored var onRest: () -> Void = {}
    @ObservationIgnored private(set) var busy = false
    @ObservationIgnored var live = false

    @ObservationIgnored private var grabbedAt: Double = 0
    @ObservationIgnored private var velocity: Double = 0          // minutes per ms
    @ObservationIgnored private var target: Double?               // a spring's end
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private var lastMinute = Int.min
    @ObservationIgnored private var lastTick: CFTimeInterval = 0
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    private static let cap = 0.6            // min / ms
    private static let decay = 0.9945       // per ms
    private static let resistance = 0.3

    func grab() {
        stop()
        busy = true
        grabbedAt = value
        lastMinute = Int(value.rounded())
        selection.prepare()
    }

    /// `delta`: minutes the finger has turned it since the grab.
    func drag(to delta: Double) {
        var v = grabbedAt + delta
        if v < bounds.lowerBound { v = bounds.lowerBound - (bounds.lowerBound - v) * Self.resistance }
        if v > bounds.upperBound { v = bounds.upperBound + (v - bounds.upperBound) * Self.resistance }
        set(v)
    }

    func release(velocity v: Double) {
        velocity = min(max(v, -Self.cap), Self.cap)
        target = nil
        if value < bounds.lowerBound || value > bounds.upperBound { springTo(min(max(value, bounds.lowerBound), bounds.upperBound)) }
        else if abs(velocity) < 0.002 { springTo(value.rounded()) }
        start()
    }

    /// Turned from outside (the ↺): spring there, no save.
    func animate(to m: Double) {
        stop()
        busy = true
        velocity = 0
        springTo(m)
        silentRest = true
        start()
    }
    @ObservationIgnored private var silentRest = false

    private func springTo(_ m: Double) { target = m; velocity = 0 }

    private func start() {
        lastFrame = CACurrentMediaTime()
        let l = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)   // ProMotion: coast at 120
        l.add(to: .main, forMode: .common)
        link = l
    }
    private func stop() { link?.invalidate(); link = nil; target = nil; velocity = 0 }

    fileprivate func frame() {
        let now = CACurrentMediaTime()
        let ms = min((now - lastFrame) * 1000, 50)
        lastFrame = now
        if let t = target {
            // A critically damped ease to the target.
            let k = 1 - pow(0.985, ms)
            let next = value + (t - value) * k
            if abs(t - next) < 0.01 { set(t); finish(); return }
            set(next)
            return
        }
        var next = value + velocity * ms
        velocity *= pow(Self.decay, ms)
        if next <= bounds.lowerBound || next >= bounds.upperBound {
            next = min(max(next, bounds.lowerBound), bounds.upperBound)
            soft.impactOccurred(intensity: 0.6)
            set(next)
            springTo(next)
            return
        }
        set(next)
        if abs(velocity) < 0.002 { springTo(next.rounded()) }
    }

    private func finish() {
        link?.invalidate(); link = nil
        busy = false
        let m = Int(value.rounded())
        value = Double(m)
        onMinute(m)
        if silentRest { silentRest = false } else { onRest() }
    }

    private func set(_ v: Double) {
        let old = value
        value = v
        let m = Int(v.rounded())
        guard m != lastMinute else { return }
        lastMinute = m
        if live, v >= bounds.lowerBound - 0.5, v <= bounds.upperBound + 0.5 { onMinute(min(max(m, Int(bounds.lowerBound.rounded(.up))), Int(bounds.upperBound.rounded(.down)))) }
        let now = CACurrentMediaTime()
        if boundaries.contains(where: { (old - $0) * (v - $0) < 0 }) {
            light.impactOccurred()
        } else if now - lastTick > 0.03 {
            selection.selectionChanged()
            lastTick = now
        }
    }
}

/// CADisplayLink holds its target strongly: a weak hop so the model can go.
private final class DisplayLinkProxy: NSObject {
    weak var model: KnobModel?
    init(_ model: KnobModel) { self.model = model }
    @objc func tick() { model?.frame() }
}

// MARK: - The knob's pan (vertical)

/// Takes a drag only when it starts up / down (the axis locks at ~6 pt, as the pager does). The sheet's own swipe-down waits
/// for it to fail, so a drag that starts in the ring box turns the knob and never closes the sheet (owner, 2026-10-20:
/// "account for the drag gesture on the bento box versus the sheet, so we don't accidentally dismiss it from here"); a
/// sideways drag fails it and is left alone.
struct KnobPan: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    /// The finger's speed (pt / s) and whether it rested > 80 ms before lifting (no coast then).
    var onEnded: (CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let y = pan.translation(in: pan.view).y
        switch pan.state {
        case .began:
            // The ~10 pt the finger moved before the pan was recognised would jump the arc 2–3 min at once: start from here.
            pan.setTranslation(.zero, in: pan.view)
            context.coordinator.lastMove = CACurrentMediaTime()
            context.coordinator.lastY = 0
            onBegan()
        case .changed:
            if abs(y - context.coordinator.lastY) > 0.5 { context.coordinator.lastMove = CACurrentMediaTime() }
            context.coordinator.lastY = y
            onChanged(y)
        case .ended, .cancelled, .failed:
            let resting = CACurrentMediaTime() - context.coordinator.lastMove > 0.08
            context.coordinator.lastY = 0
            onEnded(pan.state == .ended ? pan.velocity(in: pan.view).y : 0, resting || pan.state != .ended)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastMove: CFTimeInterval = 0
        var lastY: CGFloat = 0
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x)
        }
        /// Any other pan (the sheet's swipe-down above all) waits until this one fails.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other !== g
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }
}

/// The arc's Canvas, with the bottom fade (`tail`) animatable: the arc shortens smoothly when the bar comes up.
private struct KnobArcLayer: View, Animatable {
    var value: Double
    var tail: Double
    let render: (inout GraphicsContext, CGSize, Double, Double) -> Void
    var animatableData: Double {
        get { tail }
        set { tail = newValue }
    }
    var body: some View {
        let value = value, tail = tail
        return Canvas { ctx, size in render(&ctx, size, value, tail) }
    }
}
