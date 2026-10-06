//
//  WatchTasbeehPort.swift
//  shukr Watch
//
//  The phone's active tasbeeh counter, ported to the watch as-is and scaled (owner, 2026-09-27:
//  "the code is already there, just copy it"):
//  - `WatchNeuProgressRing` = NeuCircularProgressView (shukr/Utils.swift) in the "fine" style:
//    the NeuRing band with its two shadows, and AliveRingFill (AliveRingTuning.fine) masked to
//    the progress arc, with its glow.
//  - `WatchTasbeehCountView` = TasbeehCountView (shukr/Utils.swift): the count within the hundred
//    in the middle, 100 neumorphic beads round the outside, grey dots for the hundreds done —
//    BELOW the number, clock positions from 6 o'clock, turning 18° per hundred with the phone's
//    animation — and green dots for the thousands.
//  Same geometry as the phone's 200 pt ring, times `scale`. The phone's colours are its asset
//  catalogue's dark-mode values (the watch is always dark). Watch economy (owner, 2026-09-27): no
//  grain (its ~600 specks were the costly part of every frame); the gradient turn and the drifting
//  light / shade redraw at 10 fps (the phone: 30), which still reads smooth for a soft gradient
//  turning 23°/s; it stops with the wrist down and while paused. The 100 beads are one Canvas.
//

import SwiftUI

/// The phone's dark-mode asset colours (bgColor / NeuRing / NeuDarkShad / NeuLightShad).
enum WatchNeu {
    static let bg = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let ring = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let darkShadow = Color.black.opacity(0.5)
    static let lightShadow = Color(red: 0.239, green: 0.239, blue: 0.239).opacity(0.3)

    /// The phone's geometry fits a 280 pt circle (the beads, radius 140); scaled so that circle
    /// fills ~94 % of the watch's width.
    static var scale: CGFloat { WatchScreen.width * 0.94 / 280 }
}

/// NeuCircularProgressView, "fine" style.
struct WatchNeuProgressRing: View {
    let progress: CGFloat
    /// False while the pause screen covers it: the fill holds still.
    var animating = true
    @Environment(\.isLuminanceReduced) private var dim
    @Environment(\.colorScheme) private var scheme

    // AliveRingTuning.fine (its grain left out on the watch)
    private let band: CGFloat = 6, sweepSpeed = 23.0, lightStrength = 0.03, lightSpeed = 0.63
    private let shadeStrength = 0.32, glow = 0.45

    var body: some View {
        let s = WatchNeu.scale
        ZStack {
            Circle()
                .stroke(lineWidth: band)
                .frame(width: 200 * s, height: 200 * s)
                .foregroundColor(WatchNeu.bg(scheme))   // NeuRing = the page's colour, either look
                .shadow(color: WatchNeu.darkShadow(scheme), radius: 4 * s, x: 2 * s, y: 2 * s)
                .shadow(color: WatchNeu.lightShadow(scheme), radius: 6 * s, x: -2 * s, y: -2 * s)
            fill
                .frame(width: 230 * s, height: 230 * s)
                .mask {
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(style: StrokeStyle(lineWidth: band, lineCap: .round))
                        .frame(width: 200 * s, height: 200 * s)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: progress)
                }
                .shadow(color: .green.opacity(dim ? 0 : glow), radius: 6 * s)
                .allowsHitTesting(false)
        }
    }

    /// AliveRingFill without its grain: a slow colour sweep turning round the ring, and a pool of
    /// light and one of shade drifting through it.
    private var fill: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: dim || !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                AngularGradient(colors: [Color(red: 0.12, green: 0.62, blue: 0.32),
                                         Color(red: 0.45, green: 0.85, blue: 0.55),
                                         Color(red: 0.05, green: 0.38, blue: 0.20),
                                         Color(red: 0.30, green: 0.75, blue: 0.45),
                                         Color(red: 0.12, green: 0.62, blue: 0.32)],
                                center: .center,
                                angle: .degrees((t * sweepSpeed).truncatingRemainder(dividingBy: 360)))
                RadialGradient(colors: [Color.white.opacity(lightStrength * 0.8), .clear],
                               center: UnitPoint(x: 0.5 + 0.38 * cos(t * lightSpeed), y: 0.5 + 0.38 * sin(t * lightSpeed * 1.3)),
                               startRadius: 0, endRadius: 80 * WatchNeu.scale)
                RadialGradient(colors: [Color.black.opacity(shadeStrength), .clear],
                               center: UnitPoint(x: 0.5 + 0.38 * cos(t * lightSpeed * 0.65 + 2), y: 0.5 + 0.38 * sin(t * lightSpeed * 0.8 + 1)),
                               startRadius: 0, endRadius: 90 * WatchNeu.scale)
            }
        }
    }
}

/// TasbeehCountView, scaled.
struct WatchTasbeehCountView: View {
    let tasbeeh: Int
    @Environment(\.colorScheme) private var scheme
    private var s: CGFloat { WatchNeu.scale }
    private var circleSize: CGFloat { 10 * s }
    private var arcRadius: CGFloat { 60 * s }
    private var purpleArcRadius: CGFloat { 40 * s }

    @State private var rotationAngle: Double = 0
    @State private var purpleRotationAngle: Double = 0

    private var justReachedToA1000: Bool { tasbeeh % 1000 == 0 }
    private var showPurpleCircle: Bool { tasbeeh >= 1000 }

    var body: some View {
        ZStack {
            Text("\(tasbeeh % 100)")
                .font(.system(size: 34 * s / 0.75, weight: .thin, design: .rounded))
                .monospacedDigit()

            // The phone's 100 NeumorphicBeads (its page colour, pressed in by two inner shadows),
            // drawn in one Canvas big enough for the bead circle (radius 140). The phone turns the
            // bead group 183.6°, which also turns each bead's shadows; `beadShadow` does the same.
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let bead = 7 * s
                let turn = Angle.degrees(180 + 360 / 100).radians
                let dark = beadShadow(-1, -1, turn), light = beadShadow(1, 1, turn)
                let shading = GraphicsContext.Shading.style(WatchNeu.bg(scheme)
                    .shadow(.inner(color: WatchNeu.darkShadow(scheme), radius: 1, x: dark.x, y: dark.y))
                    .shadow(.inner(color: WatchNeu.lightShadow(scheme), radius: 1, x: light.x, y: light.y)))
                for index in 0..<(tasbeeh % 100) {
                    let p = beadPosition(for: index, center: center, turn: turn)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - bead / 2, y: p.y - bead / 2, width: bead, height: bead)), with: shading)
                }
            }
            .frame(width: 300 * s, height: 300 * s)
            .allowsHitTesting(false)

            GeometryReader { geometry in
                let circlesCount = tasbeeh / 100
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ZStack {
                    ForEach(0..<min(circlesCount / 10, 10), id: \.self) { index in
                        Circle()
                            .fill(Color.green.opacity(0.6))
                            .frame(width: circleSize, height: circleSize)
                            .position(purpleClockPosition(for: index, center: center))
                    }
                }
                .rotationEffect(.degrees(purpleRotationAngle))
                .opacity(showPurpleCircle ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: showPurpleCircle)

                ZStack {
                    ForEach(0..<max(circlesCount % 10, justReachedToA1000 ? 9 : 0), id: \.self) { index in
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: circleSize, height: circleSize)
                            .position(clockPosition(for: index, center: center))
                            .opacity(justReachedToA1000 ? 0 : 1)
                            .animation(.easeInOut(duration: 0.5), value: justReachedToA1000)
                    }
                }
                .rotationEffect(.degrees(rotationAngle))
                .onChange(of: circlesCount % 10) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        if newValue > 1 && newValue % 10 != 0 {
                            rotationAngle = Double(18 * (newValue - 1))
                        } else if newValue == 1 {
                            rotationAngle = 0
                        }
                    }
                }
                .onChange(of: circlesCount / 10) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        if newValue > 1 && newValue % 10 != 0 {
                            purpleRotationAngle = Double(18 * (newValue - 1))
                        } else if newValue == 1 {
                            purpleRotationAngle = 0
                        }
                    }
                }
            }
            .frame(height: 100 * s)
        }
        .frame(width: 200 * s, height: 200 * s)
        // A session reopened past a hundred starts with its dots already turned, as the phone's
        // would have been after counting there.
        .onAppear {
            let n = (tasbeeh / 100) % 10
            if n > 1 { rotationAngle = Double(18 * (n - 1)) }
            let m = tasbeeh / 1000
            if m > 1 && m % 10 != 0 { purpleRotationAngle = Double(18 * (m - 1)) }
        }
    }

    /// The phone's bead position, plus the group's turn (its `.rotationEffect` about the centre).
    func beadPosition(for index: Int, center: CGPoint, turn: Double) -> CGPoint {
        let stepAngle: CGFloat = 2 * .pi / 100
        let startAngle: CGFloat = .pi / 2
        let angle = startAngle + stepAngle * CGFloat(index) + turn
        return CGPoint(x: center.x + 140 * s * cos(angle), y: center.y + 140 * s * sin(angle))
    }

    /// A bead's shadow offset, turned with the group as on the phone.
    private func beadShadow(_ x: CGFloat, _ y: CGFloat, _ turn: Double) -> CGPoint {
        CGPoint(x: x * cos(turn) - y * sin(turn), y: x * sin(turn) + y * cos(turn))
    }

    func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
        let angle = angleForClockPosition(at: index)
        return CGPoint(x: center.x + arcRadius * cos(angle), y: center.y + arcRadius * sin(angle))
    }

    func purpleClockPosition(for index: Int, center: CGPoint) -> CGPoint {
        let angle = angleForClockPosition(at: index)
        return CGPoint(x: center.x + purpleArcRadius * cos(angle), y: center.y + purpleArcRadius * sin(angle))
    }

    /// From 6 o'clock (below the number), going backward, 10 even spots.
    func angleForClockPosition(at index: Int) -> CGFloat {
        let stepAngle: CGFloat = 2 * .pi / 10
        let startAngle: CGFloat = .pi / 2
        return startAngle - stepAngle * CGFloat(index)
    }
}
