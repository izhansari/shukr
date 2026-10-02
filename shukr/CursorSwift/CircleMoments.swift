import SwiftUI

// The circle system, step 2 (board/circle-system.md; decision circle-system A, owner 2026-10-02: "organize with frank and
// get this bulletproof so moving forward is easier and reliable"). MainCircleView owns what the Salah circle shows:
//
// - `CircleFace` — what it shows at rest — is derived from the data and never stored by anyone else. The circle keeps
//   the face it is *displaying* separately, and only a moment changes it.
// - A moment is a change from one face (or look) to another, run by one cancellable task the circle owns
//   (`MainCircleView.run`): the words go out, the ring changes, the new words come in. Never two texts at once.
// - A new moment cancels the running one, which snaps to its end state first (no half-faded ring).
// - Every moment waits for `canPlay` (the circle can be seen and is settled) for up to `CircleGate.deadline`; if the
//   circle can't be seen by then, its end state is shown at once — a mark from the widget or the watch never replays later.
// - ▶︎ Play and the real events go through the same moments, so what's played is what he sees.

/// What the Salah circle shows at rest.
enum CircleFace: Equatable {
    /// A prayer: next (dashed, "NEXT") or now (the band and its arc).
    case prayer(PrayerModel)
    /// The day: today's score with the list open, the next Fajr with it closed (`summaryCircle`).
    case summary
    /// The morning after a sleep finish (step 3): the session's count and zikr in the ring (`MorningFace`), the page
    /// round it the morning card's (`MorningCurtain`).
    case morning(SessionDataModel)
    /// "shukr lost your location" (step 3b): the crossed-out symbol in the ring (`LostFace`), its words round it.
    case lost
}

/// What the Salah page asks its circle to show beyond the prayers (step 3). Set by PrayerTimesView, read by the circle.
@MainActor @Observable final class CircleStage {
    static let shared = CircleStage()
    /// The morning after a sleep finish, while its card is up.
    var morning: SessionDataModel?
    /// The opening (the welcome) on a Salah landing (step 4): the circle draws its ring and word, its own track and words
    /// wait until it lands, and the page round it (the chrome, the list) waits too. Set and cleared by the welcome.
    var opening: WelcomeMarkState?
    /// The page round the circle waits for the opening to land.
    var openingHidesPage: Bool {
        guard let opening, opening.inCircle else { return false }
        return !opening.landed
    }
    /// Location lost (step 3b), until the ring has landed back on the Salah track (LostPageLayer runs it).
    var lost: LostStage?
    /// The page round the circle — the chrome, the list — is hidden (the opening, the lost page); the pager stays put.
    var pageHidden: Bool { openingHidesPage || (lost.map { !$0.landed } ?? false) }
}

/// The moments the circle plays.
enum CircleMomentKind: Equatable {
    /// A prayer was marked: the flourish, then the next face (`.prayerCompleted`).
    case marking
    /// The face changed (unmarking, a prayer's window ending, Fajr starting from the summary…): out, then in.
    case swap
    /// ▶︎ Prayer begins: the prayer as next, then it begins, then back.
    case begins
}

// CircleMomentTiming lives in CircleMotion.swift (one motion vocabulary, rule 8).


@MainActor enum CircleGate {
    /// How long a moment waits for the circle to be seen before it just shows where it ends.
    static let deadline: Double = 2

    /// Waits until `canPlay` is true (true: play it) or the deadline passes (false: show its end at once).
    static func wait(_ canPlay: () -> Bool) async -> Bool {
        let end = Uptime.now + deadline
        while !Task.isCancelled {
            if canPlay() { return true }
            if Uptime.now >= end { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// One frame: a change set quietly (the new face) is drawn before the next animation starts — in the same update the
    /// quiet transaction swallowed the fade-in (the words sat half faded, then popped on).
    static func nextFrame() async -> Bool { await pause(1.0 / 60) }

    /// A moment's pause; false once it has been cancelled (a newer moment took over: stop here).
    static func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// Seconds since boot, for the circle's own timing (how long since it appeared, a moment's deadline): never the wall
/// clock — circle-check.sh pins that (and the user can change it), which froze both.
enum Uptime {
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// The circle's words going out and coming back: a fade (CircleMotion's "fade" entrance). A scale or offset here, even
/// at rest (1 and 0), moved the words' edges by a fraction of a pixel — Today's look must stay pixel-identical
/// (circle-check.sh shots). Also right for Reduce Motion.
struct CircleWordsAway: ViewModifier {
    let away: Bool

    func body(content: Content) -> some View {
        content
            .opacity(away ? 0 : 1)
            // The animation lives with the change (rule 6): out quick, in a little slower; ease-out both ways, so the fade
            // shows from its first frame (an ease-in out sat still, then hurried). A withAnimation from the
            // runner was swallowed when the face had just been swapped quietly (the words popped back on).
            .animation(.easeOut(duration: away ? CircleMomentTiming.out : CircleMomentTiming.in), value: away)
    }
}
