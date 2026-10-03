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
    /// A prayer, in the state the circle shows it: next (dashed, "NEXT"), now (the band and its arc) or missed. The state
    /// is part of the face, so a prayer beginning or its window ending is a face change the circle plays — words out,
    /// the ring changes, words in — not a status read live that swapped its line in one frame (audit A, bug 2).
    /// `preview`: ▶︎ Prayer begins is drawing it (its "just begun" arc), so the preview ending is a face change too.
    case prayer(PrayerModel, PrayerModel.prayerStatus, preview: Bool = false)
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

    // MARK: The one stage (the transitions cleanup, step 1): what's on screen, observable, so a moment waits for it
    // instead of polling (circle rule 5). Moved here a piece at a time from the statics that held it.

    /// The app is in the foreground (MainCircleView keeps it from its scene phase). A moment's runner holds a copy of
    /// the view, whose `scenePhase` goes stale; this doesn't (audit A).
    var sceneActive = true
    /// The Salah circle has been on screen a moment (`CircleMomentTiming.settleAfterAppear` since it appeared or the app
    /// came back): what changed before then is shown as it is, not played. Kept by MainCircleView, observable, so the
    /// gate wakes when it turns true instead of polling the clock.
    var circleSettled = false

    /// The row the prayer list keeps while the circle's marking moment runs: set as the mark comes in, released when the
    /// flourish goes (or the moment isn't played). The list folds it then — it kept a copy of the flourish's length on
    /// its own timer, and a flourish held by the gate folded mid-sweep (audit A).
    private(set) var heldRow: String?
    /// Bumped when the perfect day's cascade starts (the rows' dots pop in turn, the sparkles bounce): once the marking
    /// moment that made the day perfect has ended, or at once for ▶︎ perfect day.
    private(set) var perfectCascade = 0
    @ObservationIgnored private var perfectWaiting = false

    func holdRow(_ name: String?) {
        heldRow = name
        if name == nil, perfectWaiting {
            perfectWaiting = false
            perfectCascade += 1
        }
    }

    /// The day just became perfect: the cascade once the mark's moment is over.
    func perfectDayReached() {
        if heldRow == nil { perfectCascade += 1 } else { perfectWaiting = true }
    }

    /// What's presented over the page, by name ("menu", "whatsNew", "tasbeeh", "morningCard"…). `CircleCover` writes
    /// it; anything that must wait for a clear screen reads it.
    private(set) var covers = Set<String>()
    /// How to close the covers that can close themselves (☰, What's new, calibration, a row's time edit — Sami's bug 4):
    /// a widget / alarm / control open closes them instead of pushing its page under them.
    @ObservationIgnored private var closers: [String: () -> Void] = [:]
    func cover(_ key: String, _ on: Bool, close: (() -> Void)? = nil) {
        closers[key] = on ? close : nil
        guard covers.contains(key) != on else { return }   // a write that changes nothing would still invalidate readers
        if on { covers.insert(key) } else { covers.remove(key) }
    }
    /// Some cover up can be closed from here.
    var closable: Bool { !closers.isEmpty }
    /// Closes every cover that can close itself (each then reports itself gone); returns their keys, so a caller can
    /// wait until they've gone (`clearCovers`).
    @discardableResult func closeAll() -> Set<String> {
        let all = closers
        closers = [:]
        all.values.forEach { $0() }
        return Set(all.keys)
    }

    /// The page the pager rests on; nil while it moves (written by the pager, only on change). `navigate(to:)` and the
    /// circle wait on it (tr-pager).
    var restingPage: SharedStateClass.HorizontalPage? = .main

    /// Waits until `condition` holds. It wakes when an observable value the condition read changes (this stage, any
    /// `@Observable` model) — no polling. A condition that still reads a plain static (one not moved here yet) passes
    /// `recheck` and is looked at that often as well: `grep "recheck:"` lists what's left to move (Sami's review of
    /// ac0fd16). true: it holds; false: `deadline` passed, or the task was cancelled.
    func until(deadline: Double? = nil, recheck: Double? = nil,
               _ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let end = deadline.map { Uptime.now + $0 }
        while !Task.isCancelled {
            if condition() { return true }
            if let end, Uptime.now >= end { return false }
            let left = end.map { max($0 - Uptime.now, 0) }
            let wait: Double? = switch (recheck, left) {
            case let (r?, l?): min(r, l)
            case let (r?, nil): r
            case let (nil, l?): l
            case (nil, nil): nil
            }
            await Self.change(in: condition, orAfter: wait)
        }
        return false
    }

    /// Returns when something `condition` reads changes, after `seconds` (nil: no timer), or on cancellation — whichever
    /// is first. The timer is cancelled when something else wakes it (they piled up at 10 Hz — Sami's review).
    private static func change(in condition: @escaping @MainActor () -> Bool, orAfter seconds: Double?) async {
        let woke = ResumeOnce()
        var timer: Task<Void, Never>?
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                woke.set(continuation)
                withObservationTracking { _ = condition() } onChange: { Task { @MainActor in woke.resume() } }
                if let seconds {
                    timer = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(seconds))
                        woke.resume()
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in woke.resume() }
        }
        timer?.cancel()
    }
}

/// The moments the circle plays.
enum CircleMomentKind: Equatable {
    /// A prayer was marked: the flourish, then the next face (`.prayerCompleted`).
    case marking
    /// The face changed (unmarking, a prayer's window ending, Fajr starting from the summary…): out, then in.
    case swap
    /// A prayer begins (next → now): a swap with the start's haptic, its ring expanding while the words are out. The
    /// real start and ▶︎ Prayer begins both play it.
    case begins
    /// The summary's two sides (the day's score with the sheet open ⇄ the next Fajr): out, the side and its track, in.
    case summaryFlip
}

// CircleMomentTiming lives in CircleMotion.swift (one motion vocabulary, rule 8).


@MainActor enum CircleGate {
    /// How long a moment waits for the circle to be seen before it just shows where it ends.
    static let deadline: Double = 2

    /// Waits until `canPlay` is true (true: play it) or the deadline passes (false: show its end at once). On the
    /// stage: it wakes when what `canPlay` reads changes.
    static func wait(_ canPlay: @escaping @MainActor () -> Bool) async -> Bool {
        // canPlay reads only observables now (the stage — `circleSettled` included —, WelcomeTarget.state,
        // PagerLiveState): it wakes on their changes, no re-check.
        await CircleStage.shared.until(deadline: deadline, canPlay)
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

#if DEBUG
/// `-selfTestStage`: the stage's waits measured, printed as "🧪 …" (the transitions cleanup's foundation check).
@MainActor enum StageSelfTest {
    @Observable final class Probe { var value = 0 }

    static func run() async {
        try? await Task.sleep(for: .seconds(2))   // after launch: it measured the busy launch, not the stage (Sami)
        let stage = CircleStage.shared
        // 1. A cover going wakes a waiter at once (observable), not on the next re-check.
        stage.cover("selfTest", true)
        Task { try? await Task.sleep(for: .seconds(0.3)); stage.cover("selfTest", false) }
        var t = Uptime.now
        let cleared = await stage.until(deadline: 2) { !stage.covers.contains("selfTest") }
        print("🧪 cover cleared: \(cleared) after \(String(format: "%.3f", Uptime.now - t)) s (≈0.30 expected)")
        // 2. An @Observable model elsewhere wakes it too.
        let probe = Probe()
        Task { try? await Task.sleep(for: .seconds(0.2)); probe.value = 1 }
        t = Uptime.now
        let changed = await stage.until(deadline: 2) { probe.value == 1 }
        print("🧪 observable change: \(changed) after \(String(format: "%.3f", Uptime.now - t)) s (≈0.20 expected)")
        // 3. The deadline.
        t = Uptime.now
        let timedOut = await stage.until(deadline: 0.4) { false }
        print("🧪 deadline: \(timedOut) after \(String(format: "%.3f", Uptime.now - t)) s (false, ≈0.40 expected)")
        // 4. Cancellation returns at once.
        t = Uptime.now
        let start = t
        let waiter = Task { await stage.until(deadline: 5) { false } }
        Task {
            try? await Task.sleep(for: .seconds(0.15))
            print("🧪   cancel sent at \(String(format: "%.3f", Uptime.now - start)) s")
            waiter.cancel()
        }
        let cancelled = await waiter.value
        print("🧪 cancelled: \(cancelled) after \(String(format: "%.3f", Uptime.now - t)) s (false, ≈0.15 expected)")
        // 5. animate with nothing on screen reading the change: Apple calls the completion at once (no animation).
        t = Uptime.now
        await CircleMotion.animate(.easeInOut(duration: 0.5)) { probe.value = 2 }
        print("🧪 animate, nothing reading it: returned after \(String(format: "%.3f", Uptime.now - t)) s (≈0 expected)")
    }
}
#endif
