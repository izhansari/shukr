//
//  CircleMotion.swift
//  shukr
//
//  The circle system's motion vocabulary (rule 8, shukrGit/board/circle-system.md; decision circle-system A,
//  2026-10-02): three speeds, one ease, one spring. A moment that needs something new changes this file, not one
//  screen. Motion never depends on the theme (CircleTheme.swift). Also how prayer rows come and go (RowMotion).
//
//  How a transition is written here (the transitions cleanup, decision transitions-cleanup A, 2026-10-03; audit in
//  shukrGit/board/audits/transitions-2026-10-03/):
//  - Every duration and curve is named below. A literal duration in a transition is a bug in review.
//  - A sequence awaits its steps: `await CircleMotion.animate(.x) { … }` returns when the animation is done (Apple's
//    `withAnimation(_:completionCriteria:_:completion:)`), so nothing is timed by `asyncAfter` guesses.
//  - Waiting for something to be true (the circle on screen, a cover gone) is `await CircleStage.shared.until { … }`
//    (CircleMoments.swift): it wakes when what it read changes, never polls.
//  - Never `.delay` on a spring that may be retargeted (a delayed spring doesn't carry its speed); wait, then animate.
//  - Reduce Motion is answered here (`reduced`, `movement`): a move becomes a short fade, in place.
//

import SwiftUI

enum CircleMotion {
    /// A small thing changing: a chevron, a label's last word.
    static let quick: Double = 0.2
    /// Most changes: a row, the list, a text out or in.
    static let standard: Double = 0.35
    /// The circle's own changes: a ring filling, a state handing over.
    static let slow: Double = 0.6

    /// The one ease.
    static func ease(_ duration: Double = standard) -> Animation { .easeInOut(duration: duration) }
    /// The one spring: settles without a bounce you'd notice.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// The ring changing place (the session's ring rising for the pause screen, coming down for the results; decision
    /// session-flow-build A): a spring with no bounce, so a change of mind mid-move (Resume while it rises) carries its
    /// speed into the way back instead of stopping and starting again (WWDC23 "Animate with springs").
    static let ringMove = Animation.smooth(duration: 0.5)
    /// Coming down to finish or close, the ring waits this long for the cards below it to go first (out, then in).
    static let ringMoveDownDelay: Double = 0.1

    // MARK: Named motions (each written once; the call sites that typed them are moved here step by step)

    /// A page arriving: the pager's programmatic scroll, the salah sheet popping up and down, the bottom bar's moves
    /// (it was typed 10 times as `.spring(response: 0.35, dampingFraction: 0.85)`).
    static let page = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// The page round the circle (the chrome, the list) coming back after the opening or the lost page; the welcome's
    /// own morph runs the same length so the two meet.
    static let pageReveal: Double = 0.45

    // MARK: Reduce Motion

    /// Reduce Motion, for code outside a view (a runner, a sequence). Views read `\.accessibilityReduceMotion`.
    @MainActor static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The animation for a change that moves something (an offset, a scale, a slide): under Reduce Motion a short fade
    /// instead — the view itself shows the move as a fade in place (it checks `reduced`), so nothing travels.
    static func movement(_ animation: Animation, reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: quick) : animation
    }

    // MARK: Sequences

    /// Makes the change in `body` under `animation` and returns once it's done — "logically complete": a spring counts
    /// as done when it's close enough to be seen as settled, not after its long tail. A cancelled task returns at once
    /// (the change has still been made, so a newer sequence starts from where things are). nil: the change at once.
    @MainActor static func animate(_ animation: Animation?, _ body: () -> Void) async {
        guard let animation, !Task.isCancelled else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet, body)
            return
        }
        let done = ResumeOnce()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                done.set(continuation)
                withAnimation(animation, completionCriteria: .logicallyComplete, body) { done.resume() }
            }
        } onCancel: {
            Task { @MainActor in done.resume() }
        }
    }
}

/// A continuation resumed exactly once, whoever gets there first (an animation's completion, a change, a deadline, a
/// cancellation). Main actor only.
@MainActor final class ResumeOnce {
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false
    func set(_ continuation: CheckedContinuation<Void, Never>) {
        if resumed { continuation.resume() } else { self.continuation = continuation }
    }
    func resume() {
        guard !resumed else { return }
        resumed = true
        continuation?.resume()
        continuation = nil
    }
}

/// A circle moment's words out and in (Frank, step 2; moved here from CircleMoments.swift).
/// The moments' timings: words out quick, in a little slower.
enum CircleMomentTiming {
    static let out: Double = 0.2
    static let `in`: Double = 0.35
    /// How long a moment waits for the words to be gone before it changes the face: the fade starts a frame or two
    /// after it's asked for, and swapping at exactly `out` cut it at ~60 % (the morning's count popped off).
    static let outDone: Double = out + 0.08
}

/// How prayer rows come and go in the list (a done one folding away, "N done" opening and closing). Tried
/// from the same palette menu (owner, 2026-10-01: "fix the transitions of show hiding the prayer items").
enum RowMotion: String, CaseIterable, Identifiable {
    /// The others move first, then the new row fades in; a leaving row fades out quickly before they close
    /// up. With a plain fade a row came in at its final place while its neighbours were still sliding, so
    /// two names sat on top of each other for a few frames (owner's recording, 2026-10-01: "still no good").
    case room
    /// The motion before: in sliding down from the top, out shrinking to the left, on a spring.
    case today
    /// Opacity only, a short ease.
    case fade
    /// A small drop: fading in from a few points above, out the same way.
    case drop
    /// The system's blur-replace: soft focus in and out.
    case blur
    /// Instant: rows appear and go with no motion.
    case none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .room: "Make room, then fade"
        case .today: "Today's motion"
        case .fade: "Fade"
        case .drop: "Drop"
        case .blur: "Blur"
        case .none: "No motion"
        }
    }

    static let key = "salahLook.rowMotion"

    var transition: AnyTransition {
        switch self {
        case .room:
            // Sami's audit timings: in after 0.15 s (0.24 read as a lag, the empty well growing first), out over
            // 0.12 s (0.08 read as a blink).
            .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.15)),
                        removal: .opacity.animation(.easeOut(duration: 0.12)))
        case .today:
            .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
        case .fade: .opacity
        case .drop: .opacity.combined(with: .offset(y: -10))
        case .blur: AnyTransition(.blurReplace)
        case .none: .identity
        }
    }

    /// The animation for a row change; `springy` is what today's motion used at that spot.
    func animation(springy: Animation) -> Animation? {
        switch self {
        case .today: springy
        case .room, .fade, .drop, .blur: .easeInOut(duration: 0.3)
        case .none: nil
        }
    }
}

extension RowMotion {
    static var current: RowMotion { RowMotion(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .today }
}
