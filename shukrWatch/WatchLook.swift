//
//  WatchLook.swift
//  shukrWatch
//
//  Light, dark or auto on the watch, from the phone's Settings (owner, 2026-10-06: "light mode and dark mode both in
//  the watch app … controlled from the settings … light, dark, or the follow the sun auto thing"). The phone sends its
//  `modeToggleNew` (0 light, 1 dark, 2 auto) as `appearance`; auto is the phone's own rule
//  (`PrayerViewModel.isDaytime`): light from sunrise (Fajr's end) until Maghrib, worked out here from the watch's own
//  prayer times, and switched at those moments without the phone. With the wrist down it's always dark, like the rest
//  of watchOS's always-on screens.
//

import SwiftUI

@MainActor
final class WatchLook: ObservableObject {
    static let shared = WatchLook()
    @Published private(set) var dark = true
    private var next: Task<Void, Never>?

    private init() { refresh() }

    /// 0 light, 1 dark, 2 auto. Dark until the phone has said (the watch was dark-only before).
    private var mode: Int {
        #if DEBUG
        // `-watchLook light|dark|auto`: simulator checks.
        switch UserDefaults.standard.string(forKey: "watchLook") {
        case "light": return 0
        case "dark": return 1
        case "auto": return 2
        default: break
        }
        #endif
        return WatchStore.defaults.object(forKey: WatchStore.Key.appearance) as? Int ?? 1
    }

    /// Re-reads the setting and the sun; on a new context, on becoming active, and at the next sunrise / Maghrib.
    func refresh(now: Date = Date()) {
        var switchAt: Date?
        let isDark: Bool
        switch mode {
        case 0: isDark = false
        case 1: isDark = true
        default:
            if let day = WatchPrayers.day(at: now), let sunrise = day.sunrise,
               let maghrib = day.prayers.first(where: { $0.name == "Maghrib" })?.start {
                isDark = !(now >= sunrise && now < maghrib)
                // After Maghrib the prayer day runs on to Fajr: look again in a while (the next day's sunrise isn't
                // in this day).
                switchAt = [sunrise, maghrib].filter { $0 > now }.min() ?? now.addingTimeInterval(30 * 60)
            } else {
                isDark = false   // no times yet: light, as the phone does
            }
        }
        if dark != isDark { dark = isDark }
        next?.cancel()
        guard let switchAt else { return }
        next = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(1, switchAt.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

extension WatchNeu {
    /// The phone's public look (CircleTheme.publicLook, palette greyBlue — owner: "the soft ring … I want the soft
    /// look"): the tasbeeh grey-blue in light mode (NeuRing / NeuDarkShad / NeuLightShad), charcoal in dark.
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.10) : Color(red: 0.890, green: 0.898, blue: 0.933)
    }
    static func darkShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.75) : Color.black.opacity(0.25)
    }
    static func lightShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white
    }
    /// Every page wears the soft surface, as the phone's Salah, Zikr and tasbeeh pages do.
    static func page(_ scheme: ColorScheme) -> Color { bg(scheme) }
}

/// The soft ring's raised band (CircleTheme.track with `softRing`): the page's surface, lifted — shade down-right,
/// light up-left.
struct WatchSoftBand: View {
    var width: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .stroke(WatchNeu.bg(scheme), lineWidth: width)
            .shadow(color: WatchNeu.darkShadow(scheme), radius: width * 0.6, x: width * 0.3, y: width * 0.3)
            .shadow(color: WatchNeu.lightShadow(scheme), radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
    }
}

/// The whole app's look: the colour scheme and the page colour behind everything.
struct WatchLookRoot: ViewModifier {
    @ObservedObject private var look = WatchLook.shared
    @Environment(\.isLuminanceReduced) private var wristDown
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: WatchSession

    func body(content: Content) -> some View {
        let scheme: ColorScheme = look.dark || wristDown ? .dark : .light
        content
            .background(WatchNeu.page(scheme).ignoresSafeArea())
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
            .persistentSystemOverlays(scheme == .light ? .hidden : .automatic)
            .onChange(of: session.revision) { _, _ in look.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { look.refresh() } }
    }
}

extension View {
    func watchLookRoot() -> some View { modifier(WatchLookRoot()) }
    /// A paged screen's background, told to watchOS (its clock and page dots follow it).
    func watchPageBackground() -> some View { modifier(WatchPageBackground()) }
}

struct WatchPageBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .containerBackground(WatchNeu.page(scheme), for: .tabView)
    }
}
