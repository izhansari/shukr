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

/// Rounds where the scroll would come to rest to the nearer of the two rests, like `.paging`: a flick coasts on its own
/// speed and lands wherever it was heading. `ScrollTarget` is measured from the rest (insets applied).
struct SheetSnap: ScrollTargetBehavior {
    let travel: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.y = target.rect.origin.y > travel / 2 ? travel : 0
    }
}

/// The page round the circle, pinned to the viewport while the sheet's content scrolls under it, and moved from the
/// closed rest toward the open one by the progress (`delta` = open − closed). Worked out in the render pass from the
/// scroll position itself, so the circle never lags the finger by a frame. Past the closed rest (pulling down) it goes
/// down with the bounce; past the open rest it goes up with the list.
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
            return content.offset(y: min(max(s, 0), travel) + delta * p)
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
