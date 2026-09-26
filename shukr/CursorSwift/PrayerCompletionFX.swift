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

// MARK: - Post-salah offer

/// Where the post-salah tasbih is offered after a prayer is marked (owner, 2026-09-25, comparing):
/// in the main circle (hold to mark, lift, tap again — no reaching for a pill) or the old pill.
enum PostSalahPromptStyle: String, CaseIterable, Identifiable {
    case nudge, circle, pill
    static let key = "postSalahPromptStyle"
    static var current: PostSalahPromptStyle {
        PostSalahPromptStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .nudge
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nudge: "Pill at the bottom"
        case .circle: "In the circle"
        case .pill: "Pill at the top"
        }
    }
}

/// The post-salah prompt at the bottom of the Salah page (owner, 2026-09-25, after trying an arc
/// and the circle: "let's just stay with the initial — move it to the bottom"): the glass pill,
/// bead icon + "Post-salah tasbih?", with a small ✕ on its corner so it's plainly dismissable.
/// Tap → the 33 · 33 · 34. Flick it any way to put it away. It's drawn by the pager's
/// chrome, above the pages, so dragging it never moves a page (it did when it lived in the page).
struct PostSalahNudge: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    /// The finger's pull, eased to at most ~70 pt in the same direction.
    private func pulled(_ d: CGSize) -> CGSize {
        let length = hypot(d.width, d.height)
        guard length > 0 else { return .zero }
        let eased = 70 * (1 - exp(-length / 70))
        return CGSize(width: d.width / length * eased, height: d.height / length * eased)
    }
    @State private var drag: CGSize = .zero
    @State private var pressed = false
    @State private var gone = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagonpath")   // the zikr beads (hands = prayer-spot pins)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.green)
            Text("Post-salah tasbih?")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .mapGlass(Capsule())
        .overlay(alignment: .topTrailing) {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(.easeInOut(duration: 0.25)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(.systemBackground)))
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .padding(10)                       // a thumb-sized target around the badge
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 16, y: -16)
            .accessibilityLabel("Dismiss")
        }
        .scaleEffect(pressed ? 0.96 : 1)
        .padding(.horizontal, 20)                      // a bigger target than the pill
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // Pulls a short way toward the finger — resisting, at most ~70 pt — and fades as it
        // goes (it used to follow the finger across the screen: owner). Let go far enough (or
        // flick) and it finishes fading where it is; otherwise it springs back.
        .offset(pulled(drag))
        .opacity(gone ? 0 : 1 - 0.85 * min(Double(hypot(drag.width, drag.height)) / 140, 1))
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pressed = true }
            triggerSomeVibration(type: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pressed = false
                onOpen()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { if !gone { drag = $0.translation } }
                .onEnded { value in
                    let t = value.predictedEndTranslation
                    if hypot(value.translation.width, value.translation.height) > 60 || hypot(t.width, t.height) > 120 {
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeOut(duration: 0.18)) { gone = true }
                        // Removed once invisible, with no animation of its own (resetting it here
                        // made it pop back to the start and fade a second time).
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            var quiet = Transaction()
                            quiet.disablesAnimations = true
                            withTransaction(quiet) { onDismiss() }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero }
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Post-salah tasbih")
    }
}

/// The main circle while it offers the post-salah tasbih: the Zikr circle's glowing green ring,
/// "post-salah / Tasbih? / tap to begin" in the circle's light type. A tap on the circle starts it
/// (`MainCircleView.handleTap`); "not now" sits under the circle.
struct PostSalahCircleOffer: View {
    // Laid out like a prayer on the circle: the icon left of the name ("Tasbih Fatimah", the
    // circle's big light type), a thin caption under it. The ring stays the circle's plain gray —
    // a calm rest after the score moment (score-coloured red read as demotivating; all-green
    // shouted — owner). The beads (`circle.hexagonpath`, the app's zikr symbol) are the one green
    // touch; the hands are the prayer-spot pins. "not now" sits inside the circle (MainCircleView).
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "circle.hexagonpath")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.green)
                    .symbolEffect(.breathe, options: .repeating)
                Text("Tasbih Fatimah")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("after salah?")
                .font(.subheadline)
                .fontWeight(.thin)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 176)
        .offset(y: -6)
    }
}
