import SwiftUI

// Journey was the pager's right page 2026-10-17 → 19; it's pushed from ☰ again (owner, 2026-10-19: "put Journey back in the
// hamburger menu only"). What's left here is what its views still read: the in-pager band (unused while `journeyInPager`
// is false, the default) and the hold the pager's pan reads.

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
