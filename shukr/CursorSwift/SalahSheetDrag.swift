import SwiftUI
import QuartzCore

/// The Salah sheet following the finger — the owner's "vertical live dragging" (vs "gesture completion drag", the pop).
///
/// Round 5 (owner, 2026-10-14), from the sandbox he tuned on his phone (ListDragSandbox.swift, My Dev Stuff → Prayer
/// list drag): no nested scroll view any more (rounds 1–4, 2026-10-04: stalls on quick up-and-downs, a let-go cut off).
/// The pager's own vertical drag (PrayerTimesView.abstractedDragGesture) moves the list and the ring with the finger,
/// and on release `SheetSpring` lands them from where they are with the finger's speed — a display link integrating a
/// spring, catchable mid-flight. The list runs from under the page's bottom edge to its open place; the circle moves
/// between its two rests (`SheetRests`, measured from the pop's own Spacer layout). `navPosition` is only the resting
/// state, set once the spring lands.
///
/// Behind the palette menu's "Salah list drag" (off by default until the owner has lived with it).
enum SalahSheetDrag {
    /// Off by default (owner, 2026-10-04: "go back to gesture completion drag"); round 5 is tried from the palette menu
    /// first. A new key, so an "on" saved by the 2026-10-04 builds doesn't carry over.
    static let key = "salahSheetFollows.v3"
    static let defaultOn = false
    /// Pull-down from closed: a release this far past the closed rest opens the ☰ menu (decision salah-drag-tradeoffs B).
    static let refreshPull: CGFloat = 60
    /// Posted by the pull-down; the top bar's ☰ opens.
    static let openMenu = Notification.Name("SalahSheetDrag.openMenu")
    static let space = "salahSheet"

    /// A close nobody should see (behind the sleep curtain, before the morning card, under the lost page): the sheet
    /// goes to closed at once instead of springing there. Like the pager's `go(to:animated: false)`.
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

/// The two resting layouts, measured from invisible copies of the old Spacer layout (the circle's and the list's boxes
/// at their real sizes), so open and closed sit exactly where the pop put them.
struct SheetRests: Equatable {
    var closedCircleY: CGFloat = 0
    var openCircleY: CGFloat = 0
    var openListTop: CGFloat = 0
}

/// The sheet's position and its spring. Writes `live.sheetOffset` (points the list has come up, 0 … `sheetRun`); the
/// chrome and the page's two movers read it, nothing else. Its tuning is the owner's sandbox pick (2026-10-14: "it makes
/// it interactive while being calm and not too hyper").
final class SheetSpring: NSObject {
    /// List points per finger point (sandbox 1.13; on the real page "a little fast" — owner, 2026-10-14: with the finger).
    static let ratio = 1.0
    /// The landing: a 0.2 s spring with no bounce.
    static let response = 0.20
    static let damping = 1.0
    /// How far a slow let-go's speed carries before deciding where it lands (seconds of travel).
    static let throwTime = 0.03
    /// Past the closed rest (the ☰ pull) the list gives this much (a share of its run), less and less.
    static let stretch = 0.16
    /// Past the open rest only a few points (owner: it rode up over the day page's Memories link).
    static let openStretchPoints = 10.0
    /// A flick faster than this (pt/s) opens or closes by its direction, whatever the distance.
    static let flick: CGFloat = 500

    weak var live: PagerLiveState?
    /// Landed: true = open. The page sets navPosition from it.
    var onRest: ((Bool) -> Void)?
    private(set) var dragging = false
    private var start = 0.0
    private var velocity = 0.0
    private var target = 0.0
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    init(live: PagerLiveState) { self.live = live }

    private var run: Double { Double(max(live?.sheetRun ?? 1, 1)) }
    /// 0 closed … 1 open; past either end while stretched.
    var progress: Double {
        get { Double(live?.sheetOffset ?? 0) / run }
        set {
            let points = CGFloat(newValue * run)
            if let live, abs(live.sheetOffset - points) > 0.01 { live.sheetOffset = points }
        }
    }
    var isMoving: Bool { link != nil }
    /// Where it's going (or resting): true = open.
    var heading: Bool { target >= 0.5 }
    /// The drag began on the closed page.
    var startedClosed: Bool { start < 0.5 }

    /// A finger took it (mid-spring or at rest).
    func begin() {
        dragging = true
        start = progress
        velocity = 0
        live?.sheetPhase = .interacting
        startLink()
        #if DEBUG
        meterBegin("salah drag")
        #endif
    }

    func drag(_ dy: CGFloat) {
        guard dragging else { return }
        progress = Self.rubber(start - Double(dy) * Self.ratio / run, openGive: Self.openStretchPoints / run)
    }

    /// The let-go: where it lands (true = open), springing there with the finger's speed.
    @discardableResult func release(velocityY vy: CGFloat) -> Bool {
        guard dragging else { return heading }
        dragging = false
        let speed = -Double(vy) * Self.ratio / run
        let open: Bool = abs(vy) > Self.flick ? vy < 0 : progress + speed * Self.throwTime > 0.5
        go(open: open, velocity: speed)
        return open
    }

    /// To a rest by code (the chevron, a widget, the tour) or after a let-go.
    func go(open: Bool, velocity v: Double = 0, animated: Bool = true) {
        target = open ? 1 : 0
        velocity = v
        if !animated || UIAccessibility.isReduceMotionEnabled {
            stopLink()
            progress = target
            land()
            return
        }
        live?.sheetPhase = .animating
        startLink()
        #if DEBUG
        meterBegin("salah spring")
        #endif
    }

    /// At a rest without a move or a landing call (the page's first layout).
    func place(open: Bool) {
        stopLink()
        dragging = false
        target = open ? 1 : 0
        progress = target
        live?.sheetPhase = .idle
    }

    private static func rubber(_ x: Double, openGive: Double) -> Double {
        func give(_ d: Double, _ most: Double) -> Double { most * d / (d + most) }
        if x < 0 { return -give(-x, stretch) }
        if x > 1 { return 1 + give(x - 1, openGive) }
        return x
    }

    private func startLink() {
        guard link == nil else { return }
        last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }
    private func stopLink() { link?.invalidate(); link = nil }

    @objc private func tick(_ l: CADisplayLink) {
        let dt = last == 0 ? 1.0 / 120 : min(l.timestamp - last, 1.0 / 30)
        #if DEBUG
        meterFrame(l, dt: last == 0 ? nil : l.timestamp - last)
        #endif
        last = l.timestamp
        guard !dragging else { return }
        // A damped spring (mass 1): stiffness from the response, damping from the ratio; small steps keep it stable.
        let k = pow(2 * .pi / Self.response, 2), c = 4 * .pi * Self.damping / Self.response
        var x = progress, v = velocity
        let n = 4, h = dt / Double(n)
        for _ in 0..<n {
            v += (-k * (x - target) - c * v) * h
            x += v * h
        }
        velocity = v
        if abs(x - target) < 0.0008 && abs(v) < 0.02 {
            stopLink()
            progress = target
            land()
        } else {
            progress = x
        }
    }

    private func land() {
        #if DEBUG
        meterEnd()
        #endif
        live?.sheetPhase = .idle
        onRest?(target >= 0.5)
    }

    // MARK: Frame timing (DEBUG; owner 2026-10-14: "put something on my phone so you can measure")

    #if DEBUG
    private var meterPhase: String?
    private var meterFrames = 0
    private var meterLate = 0
    private var meterWorst = 0.0
    private var meterBegan = Date()
    private func meterBegin(_ phase: String) {
        meterEnd()
        meterPhase = phase; meterFrames = 0; meterLate = 0; meterWorst = 0; meterBegan = Date()
    }
    private func meterFrame(_ l: CADisplayLink, dt: Double?) {
        guard meterPhase != nil, let dt else { return }
        meterFrames += 1
        if dt > (l.targetTimestamp - l.timestamp) * 1.5 { meterLate += 1 }
        meterWorst = max(meterWorst, dt)
    }
    /// One line per drag and per landing in Library/Caches/listdrag-frames.log (the sandbox's file).
    private func meterEnd() {
        guard let phase = meterPhase else { return }
        meterPhase = nil
        guard meterFrames > 2 else { return }
        let line = String(format: "%@ %4.0f ms · %3d frames · %2d late · worst %.1f ms\n", phase,
                          Date().timeIntervalSince(meterBegan) * 1000, meterFrames, meterLate, meterWorst * 1000)
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "listdrag-frames.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
    #endif
}

/// The list's place: from under the page's bottom edge (closed) to its open top, by the sheet's progress. Its own
/// modifier, so a frame re-renders only this, never the list (the sandbox's lost frames).
struct SheetListRide: ViewModifier {
    let live: PagerLiveState
    let openTop: CGFloat
    func body(content: Content) -> some View {
        content.offset(y: openTop + live.sheetRun - live.sheetOffset)
    }
}

/// The circle's place: between its closed and open rests by the sheet's progress (it only moves, never scales).
struct SheetCircleRide: ViewModifier {
    let live: PagerLiveState
    let delta: CGFloat
    func body(content: Content) -> some View {
        content.offset(y: delta * live.sheetOffset / max(live.sheetRun, 1))
    }
}
