//
//  Pager.swift
//  shukr
//
//  The Zikr · Salah · Settings pager's parts: PagerLiveState (every per-frame value — PrayerTimesView's body reads
//  none), the end-page resistance, the anchored Salah page, the backdrop, the long and the per-drag holds, and the
//  Settings page. Moved out of PrayerTimesAndTracker.swift (cleanup-map tangle 1, step 6).
//

import SwiftUI
import UIKit

// MARK: - Pager live state + salah page geometry

/// Per-frame values from the pager's gesture and scroll. @Observable so only the views that
/// read a given property re-render when it changes; PrayerTimesView's body reads none of them.
@Observable final class PagerLiveState {
    /// Just prayed (post-salah prompt style "nudge"): the prayer's name while the bottom nudge is
    /// up; nil hides it. Set by MainCircleView, cleared by the nudge or when the next prayer begins.
    var postSalahNudge: String?
    /// Pager scroll position in pages: 0 = Zikr, 1 = Salah, 2 = Settings.
    var scrollProgress: CGFloat = 1
    /// The Salah page's vertical drag nudge in points (resisted, ±20): the chevron follows it
    /// and the open sheet fades a little. Zero whenever no finger is down.
    var pull: CGFloat = 0
    /// The pager's scroll phase; programmatic page changes only scroll it when it's idle.
    var pagerPhase: ScrollPhase = .idle
    /// The pager is `.scrollDisabled` while this is set. Set by the pager's own drag gesture
    /// once a drag is decided vertical (so sideways drift can't turn into a page swipe) and by
    /// the post-salah pill while a finger is on it. Cleared on release.
    var pagerLocked = false
    /// The Salah sheet that follows the finger (SalahSheetDrag): its scroll from the closed rest in points (negative
    /// while pulled down, past `sheetTravel` while pushed up), the distance between the rests, and its scroll phase
    /// (the pager is locked while it moves).
    var sheetOffset: CGFloat = 0
    var sheetTravel: CGFloat = 1
    /// How far the list runs between the rests (the finger's travel × the speed).
    var sheetRun: CGFloat = 1
    var sheetPhase: ScrollPhase = .idle
    /// How far a pull-down on the closed page is toward refreshing, 1 = let go now (both drags). The chevron turns into
    /// "Keep pulling to refresh" (owner, round 3).
    var refreshReach: CGFloat = 0
    /// Where the last let-go goes (SheetRelease): true = open.
    @ObservationIgnored var sheetPick = false
    /// 0 closed … 1 open.
    var sheetProgress: CGFloat { min(max(sheetOffset / max(sheetTravel, 1), 0), 1) }
    /// The following sheet's finger and landing (SalahSheetDrag.swift, round 5).
    @ObservationIgnored lazy var sheetSpring = SheetSpring(live: self)
}


/// Behind the pager: one panel per page (Zikr, Salah plain; Settings grouped-gray in light mode)
/// offset by the live scroll position, so each page's colour — status-bar strip included —
/// moves with its page. Its own view so only it re-renders per scroll frame.
/// A pull past either end page meets heavy resistance (owner, 2026-10-19: "decrease rubber bandness. i want like a lot of
/// resistance"; a 1.8× stretch just before was "woah woah"): while the pager is past an end, the pages are drawn `extra`
/// of the overscroll back, so they give only part of the scroll view's own rubber-band; the spring back is the system's.
/// The scroll view can't be told its own stretch. PagerBackdrop's panels past each end cover the edge. A visual effect:
/// no body reads it.
struct PagerStretch: ViewModifier {
    /// Added to the system's give: −0.7 → the pages move 30 % as far.
    static let extra: CGFloat = -0.7

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            let f = proxy.frame(in: .scrollView(axis: .horizontal))
            let width = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? f.width / 3
            let over = f.minX > 0 ? f.minX : (f.maxX < width ? f.maxX - width : 0)
            return view.offset(x: over * Self.extra)
        }
    }
}

/// The Salah page stays anchored while you page (owner, 2026-10-19: "salah tab stays more anchored than others rather
/// than drag pushing it out as much pulling the others in"): it moves at `follows` of the finger and fades out by `goneAt`
/// of the way, so the side page comes in over nothing. A visual effect read per frame by the render pass, not a body:
/// PrayerTimesView's body still reads no per-frame value.
/// Tried first: Zikr and Settings drawn above it on their own solid page colour — on his phone the Zikr page's edge cut
/// through the Salah ring as it slid over ("i don't wanna see the page covering it. looks real bad"); dropped for the fade.
struct SalahPageAnchor: ViewModifier {
    /// How much of the drag the Salah page moves with.
    static let follows: CGFloat = 0.3
    /// Fully faded this far through the swipe (the incoming page's ring is still off its side).
    static let goneAt: CGFloat = 0.45
    @Environment(SharedStateClass.self) private var sharedState

    func body(content: Content) -> some View {
        content
            // Resting on Zikr or Settings, the faded page is still drawn 70 % over it (the offset below) and above Zikr in
            // the pager's order, and a faded view still takes touches: it swallowed the Zikr ring's tap and marked / unmarked
            // prayers from the Zikr tab (owner, 2026-10-20: "same for me … i could unmark prayers while on zikr tab"). It
            // takes touches only while it's the page you're on (`horizontalPage` changes on a settled swipe, never per frame).
            .allowsHitTesting(sharedState.horizontalPage == .main)
            .visualEffect { view, proxy in
                let x = proxy.frame(in: .scrollView(axis: .horizontal)).minX
                let moved = min(abs(x) / max(proxy.size.width, 1), 1)
                return view
                    .offset(x: -x * (1 - Self.follows))
                    .opacity(Double(max(0, 1 - moved / Self.goneAt)))
            }
    }
}

struct PagerBackdrop: View {
    let live: PagerLiveState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.circleTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let settings = Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground)
            HStack(spacing: 0) {
                // Past the ends: the edge page's own colour. A rubber-band pull past Zikr (or Settings) slid the panels off
                // and showed the window's stark white (owner, 2026-10-19: "need to fix background of app when swiping zikr
                // (edge most page) all the way. see stark white").
                theme.backdrop.frame(width: width)
                // Zikr and Salah: the theme's page, status-bar strip included.
                theme.backdrop.frame(width: width)
                theme.backdrop.frame(width: width)
                theme.surface.frame(width: width)   // Journey's page (its own surface)
                settings.frame(width: width)   // Settings' page
                settings.frame(width: width)   // past Settings
            }
            .frame(width: width * 6, alignment: .leading)
            .offset(x: -(live.scrollProgress + 1) * width)
        }
        .ignoresSafeArea()
    }
}

/// The pager's longer holds — the tour's (audit E17: only its swipe step pages) and the Zikr lock's narration — as
/// `.scrollDisabled`, in its own modifier (read in PrayerTimesView's body it re-rendered the whole tree). Rare, and they
/// reach the scroll views inside the pages too, which the tour relies on. The per-drag holds are `PagerPanLock`.
struct PagerLock: ViewModifier {
    var live: PagerLiveState
    func body(content: Content) -> some View {
        content.scrollDisabled(TourRuntime.shared.locksPager || ZikrLock.shared.focus)
    }
}

/// The per-drag holds (`live.pagerLocked`: a vertical drag on Salah, a finger on the
/// post-salah pill; and the live sheet's drag) switch the pager's own pan off and on in UIKit. As `.scrollDisabled` each
/// switch went down through every view in all three pages (the Settings form, the wheel, the list): 8–12 ms twice per
/// vertical swipe, a dropped frame each (perf trace 2026-10-10).
struct PagerPanLock: UIViewRepresentable {
    var live: PagerLiveState
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ view: Finder, context: Context) {
        // The lost page is the Salah page alone (circle step 3b): nothing else to swipe to. Here, not `.scrollDisabled` on
        // the pager: that reached every scroll view in the pages, and Journey's grid and calendar wouldn't scroll with no
        // location (sim, 2026-10-18).
        view.locked = live.pagerLocked || live.sheetPhase == .interacting || live.sheetPhase == .decelerating
            || CircleStage.shared.lost != nil
    }

    /// Sits in the pager's content: the nearest UIScrollView above it is the pager.
    final class Finder: UIView {
        private weak var pager: UIScrollView?
        var locked = false { didSet { if locked != oldValue { apply() } } }
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            pager = v as? UIScrollView
            apply()
        }
        private func apply() { pager?.panGestureRecognizer.isEnabled = !locked }
    }
}

/// The pager's Settings page. Equatable and always equal: it has no inputs that change, so when
/// the pager re-renders (every page turn publishes `sharedState`) SwiftUI skips it instead of
/// rebuilding the whole Settings Form. Settings still updates from its own state, @AppStorage
/// and the view model.
struct SettingsPage: View, Equatable {
    var onBack: () -> Void
    static func == (lhs: SettingsPage, rhs: SettingsPage) -> Bool { true }
    var body: some View { SettingsView(onBack: onBack, refetchOnLeave: false) }
}
