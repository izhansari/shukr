//
//  AppOverlays.swift
//  shukr
//
//  App-wide pieces that sit over or under every page: OverlayAlert (an alert above whatever is presented), StageCover
//  (what's presented over the Salah page registers, so opens can wait for it to go), UIKit's appearance probe, and the
//  DEBUG -demoLand page. Moved out of PrayerTimesAndTracker.swift (cleanup-map tangle 1, step 6).
//

import SwiftUI
import UIKit

/// An alert over everything in the app, whatever is presented (sheets, popovers, covers — some are
/// presented from nested controllers, out of reach from the root): its own window just above the
/// app's, in the app's own light / dark look. One at a time; `finish()` removes the window.
@MainActor enum OverlayAlert {
    private static var window: UIWindow?

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    static var canShow: Bool { window == nil && scene != nil }

    static func show(_ alert: UIAlertController) {
        guard window == nil, let scene else { return }
        let appWindow = scene.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        // The app's own appearance (shukr's Light / Dark / Auto, not the system's).
        w.overrideUserInterfaceStyle = appWindow?.rootViewController?.traitCollection.userInterfaceStyle ?? .unspecified
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
        root.present(alert, animated: true)
    }

    /// A SwiftUI prompt in the same window (it draws its own dim and card, and calls `finish()` when it's done).
    static func show(prompt: some View) {
        guard window == nil, let scene else { return }
        let appWindow = scene.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.overrideUserInterfaceStyle = appWindow?.rootViewController?.traitCollection.userInterfaceStyle ?? .unspecified
        let root = UIHostingController(rootView: AnyView(prompt))
        root.view.backgroundColor = .clear
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
    }

    /// After an action: hand the keyboard / focus back to the app's window.
    static func finish() {
        let appWindow = scene?.windows.first { $0 !== window && $0.windowLevel == .normal }
        window?.isHidden = true
        window = nil
        appWindow?.makeKey()
    }
}


/// Something presented over the page (a sheet, a full-screen cover, a popover) registers on the stage while it's on
/// screen: from its appearance until its dismissal has finished (onDisappear comes after it has slid away), with how to
/// close it. So a widget / alarm / What's new open closes it and waits until it's really gone (`clearCovers`), and a
/// moment waits for a clear circle (audit D, finding 10 — the waits were guesses: 0.55 s, 0.9 s, 0.25 s).
struct StageCover: ViewModifier {
    let key: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onAppear {
                let dismiss = dismiss
                CircleCover.set(key, true, close: { dismiss() })
            }
            .onDisappear { CircleCover.set(key, false) }
    }
}

extension View {
    /// On the root of what's presented (see StageCover).
    func stageCover(_ key: String) -> some View { modifier(StageCover(key: key)) }
}

extension SharedStateClass {
    /// Goes to `page` and returns once the pager rests there (true) — or false: a swipe took it elsewhere, it didn't
    /// arrive in time, or the task was cancelled. What waits for a page waits for this, not for a guessed time (audit D).
    @MainActor @discardableResult
    func navigate(to page: HorizontalPage, animated: Bool = true) async -> Bool {
        go(to: page, animated: animated)
        return await CircleStage.shared.until(deadline: 1.5) { CircleStage.shared.restingPage == page }
    }

    /// The page change now, in this turn (a caller that can't wait: the curtain's snapshot is next). `animated: false`
    /// scrolls the pager at once too.
    @MainActor func go(to page: HorizontalPage, animated: Bool = true) {
        guard horizontalPage != page else { return }
        quietPageChange = !animated
        guard !animated else { horizontalPage = page; return }
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { horizontalPage = page }
    }

    /// The pager asks how to scroll to a changed page (once per change).
    func takeQuietPageChange() -> Bool {
        defer { quietPageChange = false }
        return quietPageChange
    }
}

/// UIKit's appearance callbacks for the page it sits in: did-appear once a pop back to it has finished, did-disappear once
/// something pushed or presented full-screen over it has arrived. (SwiftUI's onAppear comes as a pop starts.)
struct AppearanceProbe: UIViewControllerRepresentable {
    var didAppear: () -> Void
    var didDisappear: () -> Void

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.didAppear = didAppear
        probe.didDisappear = didDisappear
    }

    final class Probe: UIViewController {
        var didAppear: () -> Void = {}
        var didDisappear: () -> Void = {}
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isHidden = true   // shown, even empty and clear, it turned the home indicator white on light pages
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didAppear()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            didDisappear()
        }
    }
}

#if DEBUG
/// `-demoLand salah|zikr|journey|settings`: which page a test launch lands on (no value = Salah). Any `-demo…` arg
/// already skips the welcome / opening, setup and the prompts; this one also passes the zikr lock.
enum DemoLand {
    static let page: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoLand") else { return nil }
        let next = args.indices.contains(i + 1) ? args[i + 1].lowercased() : ""
        return ["zikr", "journey", "settings"].contains(next) ? next : "salah"
    }()
}
#endif
