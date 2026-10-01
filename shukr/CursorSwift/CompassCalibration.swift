//
//  CompassCalibration.swift
//  shukr
//
//  When iOS says the compass can't be trusted (calibration, a magnet nearby), the qibla arrow is
//  dashed and the user is told what to do (owner, 2026-09-30: a faint arrow alone "looks broken and
//  gives them no action"). iOS's own calibration screen can't be opened by an app, so this is ours:
//  the line under the Salah circle, a red dot on ☰ with a "Calibrate compass" row, and this sheet,
//  which watches the compass and closes by itself once it's good. All of it follows
//  `CompassHealth`, which only publishes when "needs calibrating" flips — never with each heading.
//

import SwiftUI

/// "Compass needs a moment · tap", under the Salah circle while the compass needs calibrating.
/// Laid out at zero size by its parent, so the circle never moves.
struct CompassHintLine: View {
    @EnvironmentObject private var health: CompassHealth
    /// The prayer list is open under the circle: the line would sit on it.
    let hidden: Bool

    var body: some View {
        let show = health.needsCalibration && !hidden
        Button {
            triggerSomeVibration(type: .light)
            NotificationCenter.default.post(name: CompassHealth.openSheet, object: nil)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Compass needs a moment · tap")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(show ? 1 : 0)
        .allowsHitTesting(show)
        .animation(.easeInOut(duration: 0.3), value: show)
        .accessibilityHidden(!show)
    }
}

/// The red dot on the ☰ button while the compass needs calibrating.
struct CompassMenuBadge: View {
    @EnvironmentObject private var health: CompassHealth
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(health.needsCalibration ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: health.needsCalibration)
            .allowsHitTesting(false)
    }
}

/// "Calibrate compass" in the ☰ menu, only while it's needed.
struct CompassMenuRow: View {
    @EnvironmentObject private var health: CompassHealth
    let action: () -> Void

    var body: some View {
        if health.needsCalibration {
            Button(action: action) {
                Label {
                    Text("Calibrate compass")
                } icon: {
                    Image(systemName: "location.north.circle")
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(Color.red).frame(width: 7, height: 7).offset(x: 2, y: -2)
                        }
                }
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Ours, in place of iOS's calibration screen (which apps can't open): what to do, a phone drawing
/// a figure 8, and the compass's state live — "All set" closes it by itself.
struct CompassCalibrationSheet: View {
    @EnvironmentObject private var health: CompassHealth
    @Environment(\.dismiss) private var dismiss
    /// It needed calibrating at some point while open (so "good" now means it just got fixed).
    @State private var wasNeeded = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Calibrate your compass")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .padding(.top, 30)
            FigureEightPhone()
                .frame(height: 110)
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Hold your phone and draw a big figure 8 in the air, a few times.")
                step(2, "Keep it away from magnets: car mounts, magnetic cases, speakers.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            status
                .frame(height: 24)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sage)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Color.sage.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .fontDesign(.rounded)
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
        .onAppear { wasNeeded = health.needsCalibration }
        .onChange(of: health.needsCalibration) { _, needed in
            if needed {
                wasNeeded = true
            } else if wasNeeded {
                triggerSomeVibration(type: .success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.sage)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.sage.opacity(0.14)))
            Text(text)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var status: some View {
        if health.needsCalibration {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Keep going…")
            }
            .font(.system(size: 15, design: .rounded))
            .foregroundStyle(.secondary)
            .transition(.opacity)
        } else {
            Label(wasNeeded ? "All set — your compass is good" : "Your compass looks good", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.sage)
                .transition(.opacity)
        }
    }
}

/// A phone tracing a figure 8 over a faint dashed one (still with Reduce Motion).
private struct FigureEightPhone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func point(_ t: Double, in size: CGSize) -> CGPoint {
        let a = min(size.width * 0.36, 90), b = size.height * 0.3
        return CGPoint(x: size.width / 2 + a * sin(t), y: size.height / 2 + b * sin(2 * t))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Path { path in
                    for i in 0...120 {
                        let p = Self.point(Double(i) / 120 * 2 * .pi, in: size)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 5]))
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = reduceMotion ? 0.6 : context.date.timeIntervalSinceReferenceDate * 1.4
                    let p = Self.point(t, in: size)
                    let next = Self.point(t + 0.05, in: size)
                    let tilt = atan2(next.y - p.y, next.x - p.x) * 180 / .pi
                    Image(systemName: "iphone")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.sage)
                        .rotationEffect(.degrees(tilt * 0.25))
                        .position(p)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
