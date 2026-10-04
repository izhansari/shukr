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

/// The dashed track of a prayer that hasn't started — the main circle, the summary's next Fajr, the
/// welcome / lost page landing on it, the NEXT playground. One style so they stay alike. Owner,
/// 2026-09-28: "hard to see … still subtle, but not that invisible" (was secondary 0.35 at 1 pt).
enum UpcomingTrack {
    static let opacity = 0.58
    /// The circle's ring (200 pt: the circle, the welcome's landing, the NEXT playground).
    static let style = style(diameter: CircleTrack.size)

    /// The dashes (3 on, 5 off) fitted to a ring of this diameter: a whole number of them round it, so the last one
    /// doesn't run into the first where the stroke starts, at 3 o'clock (owner: "on the right side, there's a small
    /// overlap where the pattern doesn't match"). 200 pt: 79 of 7.95 pt instead of 78.5 of 8.
    static func style(diameter: CGFloat) -> StrokeStyle {
        let period: CGFloat = 8
        let dashShare: CGFloat = 3 / 8
        let circumference = CGFloat.pi * diameter
        let fitted = circumference / max((circumference / period).rounded(), 1)
        return StrokeStyle(lineWidth: 1.3, dash: [fitted * dashShare, fitted * (1 - dashShare)])
    }
}
import CoreHaptics
import UIKit

struct PrayerCompletionEvent {
    let name: String
    let score: Double
    /// How far through its window the prayer was when marked, 0…1 (1 = at or past the end).
    let progress: Double
    /// The line under the name; nil = "On time · 88" from the score. A Jumu'ah says "Jumu'ah at …".
    var summary: String? = nil
    /// The row's own name ("Dhuhr" for a Jumu'ah): the circle holds that prayer while the flourish plays.
    var prayerName: String? = nil
    /// The same mark, corrected (it turned out to be Jumu'ah): not a new moment. A flourish still up takes the new
    /// words in place; once it's over, nothing replays — it swept from empty and brought the folded row back (audit A).
    var isCorrection = false
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

/// Drawn over the main circle for `duration` after a completion. Underneath, `MainCircleView` keeps showing the face it
/// had (the prayer just marked) and fades its words out as this comes in — the arcs are the same size and colour, so the
/// sweep carries on from where the prayer's arc was. The next face comes in as this fades (the runner, `playMarking`).
/// One keyframe animation from its appearance (the sweep, the words, the glow): it was three delayed animations and a
/// timer, with look-dependent timings (audit A).
struct CompletionFlourish: View {
    let event: PrayerCompletionEvent
    static let duration: Double = 1.8

    /// The arc's width is the theme's (`theme.arc`: the soft ring's 6 pt, Today's 4) — a look, not a timing.
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { PrayerScoring.color(for: event.score) }

    private struct Frame {
        var sweep: Double
        var glow: Double = 0
        var words: Double = 0
    }
    /// Flipped as it appears: the keyframes play from it (`KeyframeAnimator(repeating: false)` drew their end at once).
    @State private var started = false

    var body: some View {
        let start = min(max(event.progress, 0.02), 1)
        ZStack {}
        .keyframeAnimator(initialValue: Frame(sweep: start), trigger: started) { _, f in
            ZStack {
                // The arc closes from where the prayer was to a full ring.
                Circle()
                    .trim(from: 0, to: f.sweep)
                    .stroke(color, style: StrokeStyle(lineWidth: theme.arc.width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 200, height: 200)
                    .shadow(color: color.opacity(0.6 * f.glow), radius: 12 * f.glow)
                    .shadow(color: color.opacity(0.35 * f.glow), radius: 24 * f.glow)

                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .light))
                        Text(event.name)
                            .font(.system(size: 32, weight: .light, design: .rounded))
                    }
                    Text(event.summary ?? PrayerScoring.summary(for: event.score))
                        .font(.subheadline)
                        .fontDesign(.rounded)
                        .fontWeight(.thin)
                        .foregroundStyle(color)
                        // Inside the ring: "Jumu'ah at Islamic Center of Morrisville" ran out past both sides of it
                        // (owner, 2026-10-02). Two centred lines at most, a touch smaller if it must.
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: 150)
                }
                .opacity(f.words)
                .blur(radius: reduceMotion ? 0 : 4 * (1 - f.words))
            }
        } keyframes: { _ in
            KeyframeTrack(\.sweep) {
                CubicKeyframe(1, duration: Self.sweepDuration)
            }
            // In just after the sweep starts; out so it's gone just as the next face starts in (at `duration`):
            // earlier, the circle sat empty for a beat between "✓ Maghrib" and "NEXT Isha" (owner, 2026-10-02).
            KeyframeTrack(\.words) {
                LinearKeyframe(0, duration: Self.wordsInDelay)
                CubicKeyframe(1, duration: Self.wordsInDuration)
                LinearKeyframe(1, duration: Self.duration - Self.wordsInDelay - Self.wordsInDuration - Self.wordsOutLead)
                CubicKeyframe(0, duration: Self.wordsOutDuration)
            }
            KeyframeTrack(\.glow) {
                LinearKeyframe(0, duration: Self.glowDelay)
                CubicKeyframe(1, duration: Self.glowInDuration)
                LinearKeyframe(1, duration: Self.glowHold)
                CubicKeyframe(0, duration: Self.glowOutDuration)
            }
        }
        .onAppear { started = true }
        .allowsHitTesting(false)
    }

    // Its phases (the same in every look).
    private static let sweepDuration: Double = 0.55
    /// In once the circle's own words have gone (CircleMotion.flourishCoverDuration): never two texts at once (rule 3).
    private static let wordsInDelay: Double = CircleMotion.flourishCoverDuration
    private static let wordsInDuration: Double = 0.3
    /// The words start going this long before `duration`, over `wordsOutDuration`.
    private static let wordsOutLead: Double = 0.24
    private static let wordsOutDuration: Double = 0.26
    private static let glowDelay: Double = 0.5
    private static let glowInDuration: Double = 0.3
    private static let glowHold: Double = 0.05
    private static let glowOutDuration: Double = 0.8
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

// MARK: - The circle's track

/// The main circle's track (2026-09-27, owner). A prayer that hasn't started yet — including the
/// summary circle's next Fajr — draws it as the thin dashed ring (1 pt, 3 / 5 dashes, faint gray);
/// a prayer that's on, a missed one, or the day's score draws the solid 12 pt band. `solid` runs
/// 0…1: the band grows from a hairline to 12 pt as the dashes fade — "the dashed ring expands into
/// the ring", like the welcome's ring thickening into the track — and shrinks back the same way.
/// With Reduce Motion the band stays 12 pt and just fades.
struct CircleTrack: View {
    var solid: CGFloat
    var reduceMotion = false
    /// False under the Salah look prototype's soft ring (SalahLook.swift): its raised band is the track, and
    /// this grey band showed through as a dark ring under the arc (owner, 2026-10-01).
    var band = true
    static let size: CGFloat = 200

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(UpcomingTrack.opacity), style: UpcomingTrack.style)
                .opacity(Double(1 - solid))
            TrackBand(width: reduceMotion ? 12 : max(12 * solid, 0.001))
                .fill(Color(.secondarySystemFill))
                .opacity(band ? (reduceMotion ? Double(solid) : (solid > 0.001 ? 1 : 0)) : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .allowsHitTesting(false)
    }
}

/// A ring drawn as a filled annulus centred on the circle, so its thickness animates.
private struct TrackBand: Shape {
    var width: CGFloat
    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect).strokedPath(StrokeStyle(lineWidth: width))
    }
}

// MARK: - Row status indicator styles

/// How the Salah list marks a prayed prayer (owner, 2026-09-25: the score-coloured dots are "too
/// much color" — compared these in Settings → My Dev Stuff → Prayer list dot and picked "faded").
/// The score itself is
/// still one tap away (tap the row's time: "On time · 88").
enum PrayerDotStyle: String, CaseIterable, Identifiable {
    case color, muted, ring, mono, check, sage
    static let key = "prayerDotStyle"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: "Score colour, full"
        case .muted: "Score colour, faded (default)"
        case .ring: "Score colour, ring only"
        case .mono: "Gray dot"
        case .check: "Checkmark"
        case .sage: "Sage dot"
        }
    }
}

/// The row's status indicator in the chosen `PrayerDotStyle`; pops when `pulse` bumps.
struct PrayerStatusDot: View {
    let style: PrayerDotStyle
    let done: Bool
    let future: Bool
    let scoreColor: Color
    let pulse: Int
    @Environment(\.colorScheme) private var colorScheme

    private var edge: Color { Color.secondary.opacity(future ? 0.2 : 0.5) }

    var body: some View {
        indicator
            .frame(width: 14, height: 14)
            .animation(.easeInOut(duration: CircleMotion.quick), value: done)
    }

    @ViewBuilder private var indicator: some View {
        switch style {
        case .color, .muted:
            // The original: gray ring, score-coloured fill (the faded one at a third strength).
            let fill = scoreColor.opacity(style == .muted ? 0.35
                : scoreColor == .red && colorScheme == .dark ? 0.5
                : scoreColor == .yellow && colorScheme == .light ? 1 : 0.7)
            ZStack {
                Circle().strokeBorder(edge, lineWidth: 1)
                Circle().fill(done ? fill : .clear).padding(1)
                    .modifier(CompletionDotPop(pulse: pulse, color: scoreColor))
            }
        case .ring:
            // Only the outline carries the score; no fill.
            Circle().strokeBorder(done ? scoreColor.opacity(0.85) : edge, lineWidth: done ? 2 : 1)
                .modifier(CompletionDotPop(pulse: pulse, color: scoreColor))
        case .mono, .sage:
            let fill = style == .sage ? Color.sage : Color.primary.opacity(0.45)
            ZStack {
                Circle().strokeBorder(edge, lineWidth: 1)
                Circle().fill(done ? fill : .clear).padding(1)
                    .modifier(CompletionDotPop(pulse: pulse, color: fill))
            }
        case .check:
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(done ? Color.primary.opacity(0.5) : edge)
                .contentTransition(.symbolEffect(.replace))
                .modifier(CompletionDotPop(pulse: pulse, color: Color.primary.opacity(0.5)))
        }
    }
}

// MARK: - Prayer begins

/// Settings → My Dev Stuff → Preview prayer begins: asks the main circle to show the moment
/// (DEBUG; visual only — see MainCircleView). The moment is the track expanding (`CircleTrack`)
/// with a soft haptic; the three trial looks (fade / draw / glow) were dropped (owner, 2026-09-27).
enum PrayerStartPreview {
    static let request = Notification.Name("prayerStartPreview")
}

// MARK: - Post-salah offer

/// Drag-to-dismiss for the post-salah pill (the one prompt since 2026-09-27; the in-circle offer,
/// the top pill and their dev picker were deleted): it pulls a resisting ~70 pt toward the
/// finger in any direction and fades as it goes; let go past 60 pt (or flick) and it finishes
/// fading where it is, then `onDismiss` runs with no animation (resetting its offset while it was
/// being removed made it pop back — owner). A short pull springs back. While the finger is on it
/// the pager is held (inside a page, a sideways drag would otherwise turn it).
struct FlickAway: ViewModifier {
    let onDismiss: () -> Void
    /// The finger is on it (true) / let go (false): the pill's countdown waits meanwhile.
    var onHold: (Bool) -> Void = { _ in }
    @State private var drag: CGSize = .zero
    @State private var gone = false
    /// A finger on it; SwiftUI resets it when the drag ends or is cancelled (audit B14: a cancelled drag kept the pager
    /// locked and the pill's countdown held).
    @GestureState private var touching = false
    /// A flick took: it's on its way out (set at once — `gone` waits for the fade).
    @State private var leaving = false
    @Environment(PagerLiveState.self) private var live: PagerLiveState?

    private func pulled(_ d: CGSize) -> CGSize {
        let length = hypot(d.width, d.height)
        guard length > 0 else { return .zero }
        let eased = 70 * (1 - exp(-length / 70))
        return CGSize(width: d.width / length * eased, height: d.height / length * eased)
    }

    func body(content: Content) -> some View {
        content
            .offset(pulled(drag))
            .opacity(gone ? 0 : 1 - 0.85 * min(Double(hypot(drag.width, drag.height)) / 140, 1))
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .updating($touching) { _, on, _ in on = true }
                    .onChanged { value in
                        guard !gone else { return }
                        if drag == .zero { onHold(true) }
                        if live?.pagerLocked == false { live?.pagerLocked = true }
                        drag = value.translation
                    }
                    .onEnded { value in
                        live?.pagerLocked = false
                        onHold(false)
                        let t = value.predictedEndTranslation
                        if hypot(value.translation.width, value.translation.height) > 60 || hypot(t.width, t.height) > 120 {
                            triggerSomeVibration(type: .light)
                            leaving = true
                            // Fades where it is, then goes with no animation of its own (when the fade is done).
                            Task { @MainActor in
                                await CircleMotion.animate(.easeOut(duration: CircleMotion.flickAwayDuration)) { gone = true }
                                await CircleMotion.animate(nil) { onDismiss() }
                            }
                        } else {
                            withAnimation(CircleMotion.flickBack) { drag = .zero }
                        }
                    }
            )
            // Let go without an end (cancelled): unlock the pager, the pill's countdown runs again, it slides back.
            .onChange(of: touching) { _, on in
                guard !on, !gone, !leaving else { return }
                if live?.pagerLocked == true { live?.pagerLocked = false }
                onHold(false)
                if drag != .zero { withAnimation(CircleMotion.flickBack) { drag = .zero } }
            }
    }
}

extension View {
    func flickAway(onHold: @escaping (Bool) -> Void = { _ in }, onDismiss: @escaping () -> Void) -> some View {
        modifier(FlickAway(onDismiss: onDismiss, onHold: onHold))
    }
}

/// The post-salah prompt at the bottom of the Salah page (owner, 2026-09-25, after trying an arc
/// and the circle: "let's just stay with the initial — move it to the bottom"): the glass pill,
/// bead icon + "Post-salah tasbih?", with a small ✕ on its corner so it's plainly dismissable.
/// Tap → the 33 · 33 · 34. Flick it any way to put it away. It's drawn by the pager's
/// chrome, above the pages, so dragging it never moves a page (it did when it lived in the page).
///
/// It goes by itself after `lifetime` (owner, 2026-09-29: "it persists for way too long … a 15 second
/// timer … a little bar … depleting"): a sage ring round the beads starts full and empties toward
/// 12 o'clock (owner picked the ring over a line along the bottom: "depleting the ring … not progressing
/// the ring forward"), and at 0 the pill fades where it is, like a flick. The clock only runs while the pill can be seen and nobody's touching it — not in the
/// background, paged away, under a cover (`WelcomeTarget.canLand`, `CircleCover`) or mid-flick; after
/// being away it comes back with at least `comebackMinimum` left.
struct PostSalahNudge: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void
    /// The host's page is the one showing (not paged to Zikr / Settings).
    var shown = true

    static let lifetime: Double = 15
    static let comebackMinimum: Double = 5
    /// `CircleCover` keys that leave the pill in plain sight, so the clock keeps going and there's no
    /// comeback top-up: the ☰ popover (owner, 71800F94: "ignore 5second rule when clicking on the
    /// hamburger … the pill is still in users sight"). Sheets, alerts and full-screen pages still pause it.
    static let seeThroughCovers: Set<String> = ["menu"]

    @State private var pressed = false
    @State private var holding = false
    @State private var expiring = false
    @Environment(\.scenePhase) private var scenePhase
    /// The clock: seconds counted before the current run, and when (Uptime) the current run began — nil while it's
    /// stopped (not in sight, or held). The ring draws itself from these (a TimelineView); one task waits out what's
    /// left. It was a 33 ms loop writing state 30 times a second for 15 s, on the wall clock (audit A / F3).
    @State private var spent: Double = 0
    @State private var runningSince: TimeInterval?

    /// The pill can be seen: its page is showing, the app is up, nothing covers it but the ☰ (all observable).
    private var visible: Bool {
        shown && scenePhase == .active && WelcomeTarget.canLand
            && CircleCover.active.subtracting(Self.seeThroughCovers).isEmpty
    }
    private var running: Bool { visible && !holding && !expiring && !frozen }
    private func left(at now: TimeInterval) -> Double {
        let elapsed = spent + (runningSince.map { now - $0 } ?? 0)
        return max(0, 1 - elapsed / Self.lifetime)
    }
    #if DEBUG
    /// `-postSalahTimerFreeze <seconds>`: the bar stopped at that point (screenshots).
    private static let freezeAt = UserDefaults.standard.double(forKey: "postSalahTimerFreeze")
    private var frozen: Bool { Self.freezeAt > 0 }
    #else
    private var frozen: Bool { false }
    #endif

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagonpath")   // the zikr beads (hands = prayer-spot pins)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.green)
                .overlay {
                    // Time left: full at the start, its end running back to 12 o'clock as it empties. Redrawn every
                    // frame only while it runs.
                    // 30 frames a second is plenty for a 32 pt ring over 15 s (Sami's review of 1e8dc17).
                    TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                        let now = Uptime.now
                        ZStack {
                            Circle().stroke(Color.sage.opacity(0.18), lineWidth: 2)
                            Circle().trim(from: 0, to: left(at: now))
                                .stroke(Color.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 32, height: 32)   // redrawn each frame by the timeline; the clock is Uptime
                    }
                }
                .padding(.horizontal, 4)
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
                onDismiss()   // the host animates the pill's going
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
        .onTapGesture {
            triggerSomeVibration(type: .success)
            Task { @MainActor in
                await CircleMotion.animate(CircleMotion.pillPress) { pressed = true }   // the press is felt, then it opens
                pressed = false
                onOpen()
            }
        }
        .flickAway(onHold: { holding = $0 }, onDismiss: onDismiss)
        .opacity(expiring ? 0 : 1)
        // Back in sight after being away: a moment to see it (at least `comebackMinimum` left).
        .onChange(of: visible) { _, nowVisible in
            if nowVisible { spent = min(spent, Self.lifetime - Self.comebackMinimum) }
        }
        // The clock starts and stops with `running`; while it runs, one wait for what's left, then it goes.
        .task(id: running) {
            if running {
                runningSince = Uptime.now
                guard await CircleGate.pause(max(Self.lifetime - spent, 0)) else { return }
                expire()
            } else if let since = runningSince {
                spent += Uptime.now - since
                runningSince = nil
            }
        }
        #if DEBUG
        .onAppear { if frozen { spent = Self.freezeAt } }
        #endif
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Post-salah tasbih")
    }

    /// Time's up: fade where it is, then go without an animation of its own (as a flick does).
    private func expire() {
        Task { @MainActor in
            await CircleMotion.animate(.easeOut(duration: CircleMotion.pillDuration)) { expiring = true }
            await CircleMotion.animate(nil) { onDismiss() }
        }
    }
}

