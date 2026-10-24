import SwiftUI
import UIKit

/// The counting session's surface: follows ONE finger (owner, 2026-10-24: "i hate when the phone thinks i put two fingers
/// on the screen. cuz it ruins my dragging and cancels out my hold to drag flow … i just want it fixed without breaking it
/// and still having it act the same way i know it to"). It was a SwiftUI DragGesture(minimumDistance: 0) + onTapGesture:
/// with a second finger down SwiftUI runs neither, and a drag it drops gets no onEnded, so the stroke died and its state
/// (highest / lowest point, "drag to count") was left mid-stroke. Here UIKit delivers only the first touch
/// (`isMultipleTouchEnabled = false`): other fingers are ignored and never cancel it. Tried and dropped: a pan recognizer
/// with one touch (its ~10 pt slop before it begins would change the first stroke's feel — Frank).
///
/// What it reports is what the SwiftUI gesture did: `onChanged(dy)` from the first touch-down (dy = 0 at touch-down, the
/// translation's height after), and `onEnded(tap:)` on lift or cancel — `tap` true only for a lift after under
/// `tapTravel` of travel (a tap, however long it was held, as onTapGesture counted it).
struct CounterTouchSurface: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ tap: Bool) -> Void

    /// onTapGesture's own allowance: a touch that wandered less than this is still a tap.
    static let tapTravel: CGFloat = 10

    func makeUIView(context: Context) -> CounterTouchView {
        let view = CounterTouchView()
        view.isMultipleTouchEnabled = false
        view.backgroundColor = .clear
        return view
    }

    /// Every update, so the closures always see the current session (post-salah phase, Tasbih Fatimah, pause).
    func updateUIView(_ view: CounterTouchView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

final class CounterTouchView: UIView {
    var onChanged: (CGFloat) -> Void = { _ in }
    var onEnded: (_ tap: Bool) -> Void = { _ in }
    private var start: CGPoint?
    private var travel: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard start == nil, let touch = touches.first else { return }
        start = touch.location(in: self)
        travel = 0
        onChanged(0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start, let touch = touches.first else { return }
        let p = touch.location(in: self)
        travel = max(travel, hypot(p.x - start.x, p.y - start.y))
        onChanged(p.y - start.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard start != nil else { return }
        start = nil
        onEnded(travel < CounterTouchSurface.tapTravel)
    }

    /// A cancel (Control Center, a call, the system taking the touch) resets like a lift, never counts as a tap.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard start != nil else { return }
        start = nil
        onEnded(false)
    }
}
