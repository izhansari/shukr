import SwiftUI

// Journey as the pager's right page (owner, 2026-10-17: "Let's see how we can move the Journey page to the right side of the
// Salah page … Ideally, I can swipe to it freely from the main app … everything operates the way it does now"). Settings,
// which was there, is the Salah page's gear (SettingsPresenter).

/// Journey in the pager. Built once the app has settled after launch — not in the launch's first frames, and not at a swipe's
/// start (its first build is the heavy part) — or at once if it's wanted sooner; kept after. Equatable and always equal: the
/// pager's re-renders skip it; it redraws for its own reads (the page it's on).
struct JourneyPagerPage: View, Equatable {
    let live: PagerLiveState
    static func == (a: Self, b: Self) -> Bool { true }
    @State private var built = false
    @Environment(SharedStateClass.self) private var sharedState
    @Environment(\.circleTheme) private var theme

    var body: some View {
        if built {
            // Shown once the pager rests on it, not at the swipe's detent: a reload applied mid-coast stalled frames (the
            // old Settings refetch at the commit, perf 2026-10-10 — the helper's check).
            JourneyPage(visible: CircleStage.shared.restingPage == .journey)
                .environment(\.journeyInPager, true)
                // The pager runs under the home indicator; Journey's page stops above it, as it did pushed.
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: JourneyBar.screenBottom) }
        } else {
            theme.surface
                .task {
                    // The Salah page at rest with its opening done, then a breath.
                    _ = await CircleStage.shared.until(deadline: 8) {
                        CircleStage.shared.restingPage == .main && !CircleStage.shared.pageHidden
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !built else { return }
                    JourneyPerf.began("journey prebuild")   // its cost on the Salah page, measured
                    built = true
                }
                // Wanted sooner: a swipe heading there (read in a leaf — not this view per pager frame), or asked for.
                .background { JourneyHeading(live: live) { built = true } }
                .onChange(of: sharedState.horizontalPage) { _, page in if page == .journey { built = true } }
        }
    }
}

/// A swipe heading for Journey before it's built: one call, from a leaf (it reads the pager's live progress every frame).
private struct JourneyHeading: View {
    let live: PagerLiveState
    let go: () -> Void
    var body: some View {
        Color.clear.onChange(of: live.scrollProgress > 1.01) { _, heading in if heading { go() } }
    }
}

/// Journey's calendar or a day open over its page: the pager holds still (its pan off — PagerPanLock), so the calendar's
/// own edge swipe and ‹ go back, as they did pushed. Journey at rest: a swipe right pages to Salah.
@MainActor @Observable final class JourneyPagerHold {
    static let shared = JourneyPagerHold()
    var held = false
}

/// A clip at the page's sides only: the pager's pages are clipped so none draws over its neighbour, but Journey's calendar and
/// day page reach up into the status bar's strip, as they did pushed.
struct SidesOnly: Shape {
    func path(in r: CGRect) -> Path { Path(CGRect(x: r.minX, y: r.minY - 2000, width: r.width, height: r.height + 4000)) }
}

extension EnvironmentValues {
    /// Journey is the pager's page (no system bar): its calendar's ‹ and Month | Year, and a day's heading, draw in its own
    /// band where the bar was (`JourneyBar`). Pushed (What's new's copy), the system bar's toolbar items as before.
    @Entry var journeyInPager = false
}

/// The band at the top of Journey's page where the system bar was when it was pushed: everything on the page sits where it
/// did, and the calendar's ‹ and toggle, and the day's heading, draw in it.
enum JourneyBar {
    /// The bar's own height when Journey was pushed (its title sat 10 pt higher at 44).
    static let height: CGFloat = 54

    /// The screen's top inset (the status bar): a day page laid out from the screen's top puts its heading under it.
    @MainActor static var screenTop: CGFloat { window?.safeAreaInsets.top ?? 0 }
    /// The screen's bottom inset (the home indicator).
    @MainActor static var screenBottom: CGFloat { window?.safeAreaInsets.bottom ?? 0 }
    @MainActor private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
}

/// The calendar's and the day's ‹ in Journey's band: a glass circle, as iOS 26's bar buttons (Settings' header's way).
struct JourneyBarBack: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .barGlass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
