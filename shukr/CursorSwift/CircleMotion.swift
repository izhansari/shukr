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
//  - Completions don't arrive while the app is in the background (no frames are drawn): a step that must happen there
//    (the sleep finish closing its cover, the curtain) uses `animate(nil)` or checks the scene first (Sami's review).
//  - Names: an `Animation` is named for what moves (`page`); a number of seconds ends in `Duration`.
//

import SwiftUI

enum CircleMotion {
    /// A small thing changing: a chevron, a label's last word.
    static let quick: Double = 0.2
    /// ⏸ becoming ‹ Resume and back (one button, PauseResumeButton): its size, corners, colour and symbol together.
    static let pauseMorph = Animation.snappy(duration: 0.3)
    /// A value flipping in place (the rate tile's number): the old one's fade, quick, and the new one's, gentler,
    /// so the two barely overlap.
    static let flipOut = Animation.easeOut(duration: 0.12)
    static let flipIn = Animation.easeIn(duration: 0.25)
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
    /// The soft list coming and going as the sheet pops: it travels this far (rising in, dropping out) while it fades —
    /// farther than the circle moves (~150 pt), so the ring and the fading rows never overlap either way (Izhan: "we
    /// want to avoid this ghosting between the ring and the prayer list always"; this replaces the 36 pt rise of
    /// decision list-reveal-rise A).
    static let listTravel: CGFloat = 200
    /// The day's page: the list's card lifts once its rows have unfolded, not while (Izhan: "let it expand first then
    /// raise the card"); the rows' make-room-then-fade takes ~0.3–0.6 s.
    static let dayCardLiftDelay: Double = 0.7
    static let dayCardLift = Animation.easeInOut(duration: 0.9)
    /// The Salah sheet that follows the finger, moved by code (the chevron, a widget, a demo): its scroll to a rest. A
    /// release is the scroll view's own coast.
    static let sheetSnap = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// The page round the circle (the chrome, the list) coming back after the opening or the lost page; the welcome's
    /// own morph runs the same length so the two meet.
    static let pageRevealDuration: Double = 0.45
    /// A label swapping in place: the top bar's city ⇄ streak, the Zikr page's title (SwiftUI's own `.spring`).
    static let label = Animation.spring
    /// A popover fading away (the ☰ menu): what a row it closed waits before it runs.
    static let popoverAwayDuration: Double = 0.25
    /// A SwiftUI Menu closing (the palette's ▶︎ Play): it reports nothing when it's gone.
    static let menuAwayDuration: Double = 0.35
    /// A done prayer's row folding out of the list once its mark's flourish has gone (Today's own; the soft looks pick a
    /// RowMotion in the palette).
    static let rowFold = Animation.spring(response: 0.5, dampingFraction: 0.85)
    /// The perfect day's cascade: a beat after the last row has folded back, then a dot every `perfectStep`.
    static let perfectBeatDuration: Double = 0.3
    static let perfectStepDuration: Double = 0.13
    /// The post-salah pill arriving under the top bar, or going.
    static let pillDuration: Double = 0.4
    /// A pill flicked away: it fades where the finger left it.
    static let flickAwayDuration: Double = 0.18
    /// A pill pulled short and let go: it springs back.
    static let flickBack = Animation.spring(response: 0.3, dampingFraction: 0.75)
    /// The pill pressed before it opens.
    static let pillPress = Animation.spring(response: 0.25, dampingFraction: 0.6)

    // MARK: The Zikr wheel and its session (audit E)

    /// The wheel centring a circle (a scrub, a start from elsewhere, landing after a session).
    static let wheelCentre = Animation.spring(response: 0.5, dampingFraction: 0.85)
    /// A tap on a circle that isn't centred: it comes to the middle.
    static let wheelStep = Animation.snappy
    /// The scrubber under a finger: each circle it passes, quickly.
    static let wheelScrub = Animation.snappy(duration: 0.18)
    /// Opening a session out of a ring: the other circles and the ring's label going.
    static let wheelOpenDuration: Double = 0.4
    /// A ring's arc rewinding to empty as its session opens, or the session's arc landing where the wheel's stands.
    static let arcMoveDuration: Double = 0.4
    /// A wheel ring's arc growing as its task's share changes (a session added to it).
    static let arcFill = Animation.spring(response: 0.6, dampingFraction: 0.85)
    /// Closing onto the wheel: the session's page going, then its ring fading over the wheel's identical one.
    static let sessionPageOutDuration: Double = 0.25
    /// Closing from the counter: its count and buttons going first.
    static let sessionCountOutDuration: Double = 0.25
    /// The results coming in once the counter's words have gone.
    static let resultsInDuration: Double = 0.25
    /// The results' ✓: a beat after the card, then a spring with a little bounce.
    static let resultsCheckBeat: Double = 0.15
    static let resultsCheck = Animation.spring(response: 0.45, dampingFraction: 0.6)
    /// The soft session cards' words going (out quick, so the next ones come in clean).
    static let cardsOutDuration: Double = 0.12
    static let sessionRingOverDuration: Double = 0.15

    // MARK: The circle's own (the same in every look — rule 9: motion never depends on the theme)

    /// The words under a mark's flourish going (quick) and coming back as it fades.
    static let flourishCoverDuration: Double = 0.25
    static let flourishUncoverDuration: Double = 0.4
    /// The flourish fading off the circle once the next face is in.
    static let flourishOutDuration: Double = 0.45
    /// The track: the dashes expanding into the band (a prayer begins), and narrowing back.
    static let trackExpand = Animation.spring(response: 0.75, dampingFraction: 0.9)
    static let trackNarrowDuration: Double = 0.5
    /// ▶︎ Opening over the page as it is: the track fading out first; the welcome's mark fading once it's landed.
    static let openingTrackOutDuration: Double = 0.2
    static let openingMarkOutDuration: Double = 0.25
    /// The qibla arrow snapping to straight up as it lines up.
    static let arrowSnap = Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1)

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
    /// The circle plays nothing for this long after it appears (a launch, coming back to the app): what changed while
    /// it was away is shown as it is.
    static let settleAfterAppear: Double = 0.6
    /// A swap from start to end: the words out, a frame, the words in.
    static let swapDuration: Double = outDone + 1.0 / 60 + `in`
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
    /// The public look's (decision public-style-lock A, owner: "rows come and go in make room then fade").
    static let standard: RowMotion = .room
    /// A stored pick in DEBUG builds; public builds are locked to `standard`.
    static func resolved(_ raw: String?) -> RowMotion {
        #if DEBUG
        RowMotion(rawValue: raw ?? "") ?? standard
        #else
        standard
        #endif
    }
    static var current: RowMotion { resolved(UserDefaults.standard.string(forKey: key)) }
}
