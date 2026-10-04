import SwiftUI

/// The Salah sheet following the finger (queue salah-sheet-drag; Ben's brief, board/brief-frank-salah-drag.md). The owner:
/// "the ring moves up as we pull the page up and prayer list comes in right too". Built like the horizontal pager he
/// likes: a native vertical ScrollView with two rests (closed, open) that UIKit tracks, flings and bounces; the list
/// rides in the scroll content (1:1 with the finger), the circle is pinned to the page and lerps between its two resting
/// places by the progress. `navPosition` is only the resting state, set when the scroll settles.
///
/// The owner's names: "vertical live dragging" (this) vs "gesture completion drag" (the pop). He went back to the pop
/// (2026-10-04); this stays behind the palette menu's "Salah list drag" and My Dev Stuff, off.
enum SalahSheetDrag {
    /// Off by default everywhere (owner, 2026-10-04, after round 3: "go back to gesture completion drag … it doesn't
    /// feel right"). A new key, so an "on" saved by the test builds doesn't carry over. The palette menu still switches it.
    static let key = "salahSheetFollows.v2"
    static let defaultOn = false
    /// Pull-to-refresh from closed: a release this far past the closed rest (decision salah-drag-tradeoffs B).
    static let refreshPull: CGFloat = 60
    /// The scroll between the rests, as a share of the page's height: the list moves exactly this far with the finger,
    /// from under the page's bottom edge (a full list; a short one starts a little higher, faded out) to its open place.
    /// Fixed per page, so the range never changes under a finger or when "N done" folds.
    static let travelShare: CGFloat = 0.5
    /// How far the list and the ring move for each point of finger (owner, 2026-10-04: "moving one to one with my finger
    /// … I'd be better off if … the prayer list drags up by 1.5 units or maybe two"). The finger's scroll between the
    /// rests is the list's run ÷ this; the palette menu picks it (1×, 1.5×, 2×).
    static let speedKey = "salahSheetSpeed"
    static let defaultSpeed: Double = 1.5
    static let speeds: [Double] = [1, 1.5, 2]
    /// Dead scroll room past each rest (round 2, owner: "it bounces way too much at the ends … I can push the whole ring
    /// out of the page"): the rests sit inside the content, so a push past one scrolls into this room — no rubber band —
    /// and `SheetPin` / `SheetWall` hold everything still there. Fixed, not a share of the page: the page's height
    /// changes during launch, and a dead room that moved with it moved every measured offset.
    static let dead: CGFloat = 400
    /// Past a rest the page still gives a little, so the push registers (owner, round 3: "allow a little bit of that,
    /// like very, very little"): a resisted move that never passes `giveMax` points.
    static let giveMax: CGFloat = 14
    static func give(_ excess: CGFloat) -> CGFloat {
        guard excess > 0 else { return 0 }
        return giveMax * (1 - 1 / (1 + excess / 80))
    }
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

/// Where a let-go goes (round 3): still moving (≥ 0.15 pt/ms) → the way it was going (a short swipe opens or closes, as
/// the pop's did); stopped → the nearer rest; past a rest → that rest. No ScrollTargetBehavior: SwiftUI's own snap to a
/// target cut off (or crawled to) every let-go — owner: "it just stops", "a slow flick moves really, really slow" — so
/// the page reads the speed from the scroll view's pan and moves there itself with UIKit's animated scroll.
enum SheetRelease {
    /// Points per millisecond: slower than this at the let-go counts as stopped.
    static let flick: CGFloat = 0.15
    static func open(at now: CGFloat, velocity v: CGFloat, travel: CGFloat) -> Bool {
        if now <= 0 { return false }
        if now >= travel { return true }
        if abs(v) >= flick { return v > 0 }
        return now > travel / 2
    }
}

/// The page round the circle, pinned to the viewport while the sheet's content scrolls under it, and moved from the
/// closed rest toward the open one by the progress (`delta` = open − closed). Worked out in the render pass from the
/// scroll position itself, so the circle never lags the finger by a frame. Past either rest the counter-move equals
/// the scroll, but for a little give: the ring stays by its rest (round 2; the give, round 3).
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
            // Past a rest: held, but for a little give (SalahSheetDrag.give).
            let give = SalahSheetDrag.give(-s) - SalahSheetDrag.give(s - travel)
            return content.offset(y: s + delta * p + give)
        }
    }
}

/// The list's layer (one page tall, laid at the closed rest): between the rests it runs `run` points while the finger
/// scrolls `travel` (the speed, SalahSheetDrag.speedKey), and it's held past them (but for the same little give), so
/// the list never runs past its open place or back up after closing.
struct SheetWall: ViewModifier {
    let travel: CGFloat
    let run: CGFloat
    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let s = -proxy.frame(in: .scrollView(axis: .vertical)).minY
            let p = min(max(s / travel, 0), 1)
            let give = SalahSheetDrag.give(-s) - SalahSheetDrag.give(s - travel)
            return content.offset(y: s - run * p + give)
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

/// The sheet's own UIScrollView, for the let-go (round 3, owner: "I can't move up and down very fast. Sometimes it just
/// stops"): a SwiftUI-animated `scrollTo` started at the let-go was cut off ~35 ms later by the scroll view's own
/// zero-length coast finishing, and the sheet stopped between the rests. UIKit's animated `setContentOffset` is one
/// fixed time whatever the flick, and a new finger stops it where it is.
final class SheetScrollHandle: NSObject {
    weak var view: UIScrollView?
    /// The finger's speed, from the scroll's own samples while it's down (the pan's velocity had already reset by the
    /// time the let-go reached the page): content points per millisecond, positive = toward open.
    private var lastOffset: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0
    func sample(_ offset: CGFloat) {
        let now = CACurrentMediaTime()
        let dt = (now - lastTime) * 1000
        if lastTime > 0, dt > 0, dt < 100 {
            let v = (offset - lastOffset) / CGFloat(dt)
            velocity = velocity * 0.4 + v * 0.6
        } else { velocity = 0 }
        lastOffset = offset
        lastTime = now
    }
    /// The speed at the let-go: nothing if the finger had stopped (no sample for 50 ms).
    var releaseVelocity: CGFloat {
        (CACurrentMediaTime() - lastTime) * 1000 > 50 ? 0 : velocity
    }
    /// Put on its first rest (the scroll starts at 0, in the dead room above the closed rest).
    var placed = false
    /// Moves the scroll by `delta` points — worked out from the page's own measure (SwiftUI's insets and UIKit's
    /// `adjustedContentInset` disagreed by 53 pt, which left the closed page in the dead room).
    func scroll(by delta: CGFloat, animated: Bool) {
        guard let view, abs(delta) > 0.25 else { return }
        if animated { spring(by: delta, velocity: 0); return }
        stop()
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: view.contentOffset.y + delta), animated: false)
    }

    // MARK: the landing spring (owner's recording, 2026-10-04: "it like hits a snag")
    // UIKit's animated setContentOffset starts from a standstill (ease in): after a fast flick the list stopped dead for
    // ~4 frames, then eased off. This spring starts at the finger's speed and runs the page's spring (CircleMotion.page:
    // response 0.35, damping 0.85), stepped each frame on the scroll view itself, so a finger can take it at any frame.

    private var link: CADisplayLink?
    private var target: CGFloat = 0     // contentOffset.y
    private var position: CGFloat = 0   // contentOffset.y, kept here (the view rounds it to pixels: read back, the
                                        // spring never got within 0.3 pt and crept on)
    private var speed: CGFloat = 0      // points per second
    private var started: CFTimeInterval = 0
    private var onRest: (() -> Void)?
    static let response: CGFloat = 0.35
    static let damping: CGFloat = 0.85
    var springing: Bool { link != nil }

    /// Springs the scroll by `delta` points, starting at `velocity` (points per millisecond, as `releaseVelocity`).
    func spring(by delta: CGFloat, velocity: CGFloat, onRest: (() -> Void)? = nil) {
        guard let view else { return }
        stop()
        // Stop UIKit's own coast where it is.
        view.setContentOffset(view.contentOffset, animated: false)
        position = view.contentOffset.y
        target = position + delta
        speed = velocity * 1000
        started = CACurrentMediaTime()
        self.onRest = onRest
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// A finger took it (or code moved it): no more spring.
    func stop() {
        link?.invalidate()
        link = nil
        onRest = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let view else { stop(); return }
        let dt = CGFloat(min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 30))
        let omega = 2 * .pi / Self.response
        let k = omega * omega, c = 2 * Self.damping * omega
        var x = position - target
        for _ in 0..<4 {   // four small steps a frame: steady at any refresh rate
            let h = dt / 4
            speed += (-k * x - c * speed) * h
            x += speed * h
        }
        position = target + x
        if (abs(x) < 1 && abs(speed) < 30) || CACurrentMediaTime() - started > 1.5 {
            view.contentOffset.y = target
            let done = onRest
            stop()
            done?()
        } else {
            view.contentOffset.y = position
        }
    }
}

/// Finds the nearest UIScrollView above it (the sheet's vertical one: it sits in the sheet's content).
struct SheetScrollFinder: UIViewRepresentable {
    let handle: SheetScrollHandle
    func makeUIView(context: Context) -> Finder { Finder(handle: handle) }
    func updateUIView(_ view: Finder, context: Context) {}

    final class Finder: UIView {
        let handle: SheetScrollHandle
        init(handle: SheetScrollHandle) {
            self.handle = handle
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            handle.view = v as? UIScrollView

        }
    }
}
