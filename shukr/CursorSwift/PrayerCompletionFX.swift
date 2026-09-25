//
//  PrayerCompletionFX.swift
//  shukr
//
//  The moment a prayer is marked done (2026-09-25; owner: "something subtle, but still
//  magical" instead of the circle abruptly switching to the next prayer).
//  - `PrayerViewModel.togglePrayerCompletion` posts `.prayerCompleted` with a
//    `PrayerCompletionEvent` and plays `PrayerCompletionHaptics`.
//  - The main circle (`MainCircleView`) overlays `CompletionFlourish`: the progress arc sweeps
//    closed in the score's colour, the ring glows, "Asr · On time · 88" shows, then the next
//    prayer blurs in.
//  - The prayer list (`TodaysPrayerListView`) pops the row's dot with a ripple
//    (`CompletionDotPop`), then folds the row away; done prayers come back when all five are.
//  - Perfect day = all five Early: the dots pop in turn and "✦ perfect day" shows.
//

import SwiftUI
import CoreHaptics
import UIKit

struct PrayerCompletionEvent {
    let name: String
    let score: Double
    /// How far through its window the prayer was when marked, 0…1 (1 = at or past the end).
    let progress: Double
}

extension Notification.Name {
    /// Posted by the view model when a prayer is marked done in the app (object: PrayerCompletionEvent).
    static let prayerCompleted = Notification.Name("prayerCompleted")
}

// MARK: - Haptics

/// Three quick soft taps, rising, like a drop landing, then a short warm hum.
enum PrayerCompletionHaptics {
    private static var engine: CHHapticEngine?

    static func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
            }
            try engine?.start()
            func tap(_ t: Double, _ i: Float, _ s: Float) -> CHHapticEvent {
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: s)
                ], relativeTime: t)
            }
            let hum = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
                CHHapticEventParameter(parameterID: .decayTime, value: 0.3),
                CHHapticEventParameter(parameterID: .sustained, value: 0)
            ], relativeTime: 0.2, duration: 0.35)
            let pattern = try CHHapticPattern(events: [
                tap(0.00, 0.40, 0.5),
                tap(0.08, 0.55, 0.45),
                tap(0.16, 0.75, 0.4),
                hum
            ], parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Main circle flourish

/// Drawn over the main circle for ~1.8 s after a completion. The circle's own content (already
/// showing the next prayer underneath) is hidden meanwhile by `MainCircleView`.
struct CompletionFlourish: View {
    let event: PrayerCompletionEvent
    static let duration: Double = 1.8

    @State private var sweep: Double = 0
    @State private var glow: Double = 0
    @State private var showText = false

    private var color: Color { PrayerScoring.color(for: event.score) }

    var body: some View {
        ZStack {
            // The arc closes from where the prayer was to a full ring.
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
                .shadow(color: color.opacity(0.6 * glow), radius: 12 * glow)
                .shadow(color: color.opacity(0.35 * glow), radius: 24 * glow)

            if showText {
                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .light))
                        Text(event.name)
                            .font(.system(size: 32, weight: .light, design: .rounded))
                    }
                    Text(PrayerScoring.summary(for: event.score))
                        .font(.subheadline)
                        .fontDesign(.rounded)
                        .fontWeight(.thin)
                        .foregroundStyle(color)
                }
                .transition(.blurReplace)
            }
        }
        .onAppear {
            sweep = min(max(event.progress, 0.02), 1)
            withAnimation(.easeInOut(duration: 0.55)) { sweep = 1 }
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) { showText = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) { glow = 1 }
            withAnimation(.easeInOut(duration: 0.8).delay(0.85)) { glow = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration - 0.45) {
                withAnimation(.easeIn(duration: 0.4)) { showText = false }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Row dot pop

/// The list row's status dot, popping with a ripple each time `pulse` bumps.
struct CompletionDotPop: ViewModifier {
    let pulse: Int
    let color: Color

    private struct Frame { var scale: Double = 1; var ring: Double = 1; var ringOpacity: Double = 0 }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Frame(), trigger: pulse) { view, f in
                view
                    .scaleEffect(f.scale)
                    .background {
                        Circle()
                            .stroke(color, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                            .scaleEffect(f.ring)
                            .opacity(f.ringOpacity)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.3, duration: 0.05)
                    SpringKeyframe(1.35, duration: 0.2, spring: .snappy)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                }
                KeyframeTrack(\.ring) {
                    LinearKeyframe(1, duration: 0.1)
                    CubicKeyframe(2.8, duration: 0.6)
                }
                KeyframeTrack(\.ringOpacity) {
                    LinearKeyframe(0, duration: 0.1)
                    LinearKeyframe(0.8, duration: 0.05)
                    CubicKeyframe(0, duration: 0.55)
                }
            }
    }
}
