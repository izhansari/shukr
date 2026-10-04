import SwiftUI

/// The Salah sheet following the finger (queue salah-sheet-drag; Ben's brief, board/brief-frank-salah-drag.md). The owner:
/// "the ring moves up as we pull the page up and prayer list comes in right too". Built like the horizontal pager he
/// likes: a native vertical ScrollView with two rests (closed, open) that UIKit tracks, flings and bounces; the list
/// rides in the scroll content (1:1 with the finger), the circle is pinned to the page and lerps between its two resting
/// places by the progress. `navPosition` is only the resting state, set when the scroll settles.
///
/// Behind a dev switch (My Dev Stuff → "Salah sheet: follows the finger"; DEBUG on) so the owner can compare it with
/// the pop on his phone. The pop path goes once he picks.
enum SalahSheetDrag {
    static let key = "salahSheetFollows"
    #if DEBUG
    static let defaultOn = true
    #else
    static let defaultOn = false
    #endif
    /// Pull-to-refresh from closed: a release this far past the closed rest (decision salah-drag-tradeoffs B).
    static let refreshPull: CGFloat = 60
    /// The scroll between the rests, as a share of the page's height: the list moves exactly this far with the finger,
    /// from under the page's bottom edge (a full list; a short one starts a little higher, faded out) to its open place.
    /// Fixed per page, so the range never changes under a finger or when "N done" folds.
    static let travelShare: CGFloat = 0.5
    /// Dead scroll room past each rest, as a share of the page's height (round 2, owner: "it bounces way too much at
    /// the ends … I can push the whole ring out of the page"): the rests sit inside the content, so a push past one
    /// scrolls into this room — no rubber band — and `SheetPin` / `SheetWall` hold everything still there.
    static let deadShare: CGFloat = 0.35
    static let space = "salahSheet"

    /// A close nobody should see (behind the sleep curtain, before the morning card, under the lost page): the sheet
    /// goes to closed at once instead of scrolling there. Like the pager's `go(to:animated: false)`.
    @MainActor static func closeQuietly(_ state: SharedStateClass) {
        guard state.navPosition != .main else { return }
        quietNext = true
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { state.navPosition = .main }
    }
    @MainActor private static var quietNext = false
    /// Whether the move the sheet is about to make was asked for quietly (once).
    @MainActor static func takeQuiet() -> Bool {
        defer { quietNext = false }
        return quietNext
    }
}

/// The let-go (round 2, owner: "a slow flick … moves really, really slow … a fast one goes really fast"): the scroll
/// view's coast is cut off — the target is where the finger let go — and `pick` records which rest the release goes
/// to; the page then drives there on its own spring (`CircleMotion.sheetSnap`), so every let-go lands in the same time.
/// Still moving (≥ 0.15 pt/ms) → the way it was going (a short swipe opens or closes, as the pop's did); stopped → the
/// nearer rest; past a rest → that rest. Code's scrolls (the chevron's) pass through untouched.
struct SheetSnap: ScrollTargetBehavior {
    let travel: CGFloat
    /// The closed rest's place in the content (the dead room above it).
    let dead: CGFloat
    let live: PagerLiveState
    /// Points per millisecond: slower than this at the let-go counts as stopped.
    static let flick: CGFloat = 0.15
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard live.sheetPhase == .interacting else { return }
        let now = live.sheetOffset
        let v = context.velocity.dy
        let open: Bool
        if now <= 0 { open = false }
        else if now >= travel { open = true }
        else if abs(v) >= Self.flick { open = v > 0 }
        else { open = now > travel / 2 }
        live.sheetPick = open
        target.rect.origin.y = now + dead   // no coast: the spring takes it from here
    }
}

/// The page round the circle, pinned to the viewport while the sheet's content scrolls under it, and moved from the
/// closed rest toward the open one by the progress (`delta` = open − closed). Worked out in the render pass from the
/// scroll position itself, so the circle never lags the finger by a frame. Past either rest the counter-move equals
/// the scroll: the ring stays on its rest, a solid wall (round 2).
///
/// Animatable on `delta`: when the open rest moves ("N done" folding, the list changing), the circle glides there.
struct SheetPin: ViewModifier, Animatable {
    let travel: CGFloat
    var delta: CGFloat
    var animatableData: CGFloat {
        get { delta }
        set { delta = newValue }
    }
    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let s = -proxy.frame(in: .scrollView(axis: .vertical)).minY
            let p = min(max(s / travel, 0), 1)
            return content.offset(y: s + delta * p)
        }
    }
}

/// The list's layer (one page tall, laid at the closed rest): it scrolls with the finger between the rests and is held
/// still past them, so the list never passes its open place or comes back up after closing.
struct SheetWall: ViewModifier {
    let travel: CGFloat
    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let s = -proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content.offset(y: min(s, 0) + max(s - travel, 0))
        }
    }
}

/// The list fading in with the progress (it moves with the scroll content itself); it takes taps once it's mostly in.
struct SheetListFade: ViewModifier {
    let live: PagerLiveState
    func body(content: Content) -> some View {
        content
            .opacity(Double(live.sheetProgress))
            .allowsHitTesting(live.sheetProgress > 0.5)
    }
}

/// The sheet's ScrollView stays still while the pager is turning a page, and on the lost page.
struct SheetLock: ViewModifier {
    let live: PagerLiveState
    let lost: Bool
    func body(content: Content) -> some View {
        content.scrollDisabled(lost || live.pagerPhase == .interacting || live.pagerPhase == .decelerating)
    }
}

/// The two resting layouts, measured from invisible copies of the old Spacer layout (the circle's and the list's boxes
/// at their real sizes), so open and closed sit exactly where the pop put them.
struct SheetRests: Equatable {
    var closedCircleY: CGFloat = 0
    var openCircleY: CGFloat = 0
    var openListTop: CGFloat = 0
}
