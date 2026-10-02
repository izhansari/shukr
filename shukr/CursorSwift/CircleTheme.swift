//
//  CircleTheme.swift
//  shukr
//
//  The look as one value (the circle system's rule 9, shukrGit/board/circle-system.md; decision circle-system A,
//  2026-10-02). Views read `@Environment(\.circleTheme)` and never the SalahLook / SalahPalette keys themselves, so
//  a look is one value to swap: `.today` (the look before the prototype) or a soft one. It's set at PrayerTimesView's
//  root and on each cover's root (`circleThemeRoot()`, the palette menu's picks); a view outside them reads the stored
//  picks (`CircleTheme.stored`). Motion never depends on the theme (CircleMotion.swift).
//

import SwiftUI

struct CircleTheme: Equatable {
    /// The prayer list's style (the prototype's list looks; `.today` = the thin bordered card).
    var list: SalahLook = .today
    /// The soft ring: the raised band under the circle's arc and the tasbeeh arc.
    var softRing = false
    var palette: SalahPalette = .charcoal
    /// Lines between prayers in the card / well looks (Today's look always has them).
    var lines = true

    /// The look before the prototype.
    static let today = CircleTheme()

    /// The palette menu's stored picks (DEBUG launch arguments override them for a run).
    static var stored: CircleTheme {
        let d = UserDefaults.standard
        return CircleTheme(list: SalahLook(rawValue: d.string(forKey: SalahLook.key) ?? "") ?? .today,
                           softRing: d.bool(forKey: SalahLook.softRingKey),
                           palette: SalahPalette(rawValue: d.string(forKey: SalahPalette.key) ?? "") ?? .charcoal,
                           lines: d.object(forKey: SalahLook.linesKey) == nil ? true : d.bool(forKey: SalahLook.linesKey))
    }

    // MARK: What views ask

    /// The pages wear the soft material (the Salah and Zikr backdrop, the bottom bar, the tasbeeh page): any list
    /// look but today's, or the soft ring alone.
    var soft: Bool { list != .today || softRing }
    /// "N done" and "perfect day" sit under the list's card (the soft list looks); Today's look keeps them inside.
    var listFooterOutside: Bool { list != .today }
    var showsRowDividers: Bool { list == .today || ((list == .card || list == .well) && lines) }
    /// Space between prayer rows: pills stand apart.
    var rowSpacing: CGFloat { list == .pills ? 12 : 6 }
    /// A row's vertical padding: the well's rows a bit shorter (owner, 2026-10-01).
    var rowVerticalPadding: CGFloat { list == .well ? 8 : 12 }
    /// The current prayer's name in full primary (the soft list looks); Today's look keeps it secondary.
    var emphasisesCurrentRow: Bool { list != .today }
    /// The tasbeeh ring's material: the picked palette under the soft look (the same material as the rings it opens
    /// out of), its own grey-blue otherwise.
    var ringPalette: SalahPalette { soft ? palette : .tasbeeh }

    // MARK: The material

    var surface: Color { palette.surface }
    var shade: Color { palette.shade }
    var light: Color { palette.light }
}

private struct CircleThemeKey: EnvironmentKey {
    /// Outside a themed root (an overlay at the app's root): the stored picks, read when asked.
    static var defaultValue: CircleTheme { .stored }
}

extension EnvironmentValues {
    var circleTheme: CircleTheme {
        get { self[CircleThemeKey.self] }
        set { self[CircleThemeKey.self] = newValue }
    }
}

/// Sets the theme from the palette menu's picks and keeps it current as they change. On PrayerTimesView's root and on
/// each cover's root (the environment isn't trusted to cross a presentation).
struct CircleThemeRoot: ViewModifier {
    @AppStorage(SalahLook.key) private var list = SalahLook.today.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = false
    @AppStorage(SalahPalette.key) private var palette = SalahPalette.charcoal.rawValue
    @AppStorage(SalahLook.linesKey) private var lines = true

    func body(content: Content) -> some View {
        content.environment(\.circleTheme, CircleTheme(list: SalahLook(rawValue: list) ?? .today,
                                                       softRing: softRing,
                                                       palette: SalahPalette(rawValue: palette) ?? .charcoal,
                                                       lines: lines))
    }
}

extension View {
    func circleThemeRoot() -> some View { modifier(CircleThemeRoot()) }
}

// MARK: - Palettes and the soft materials

/// The soft looks' colours: a surface, a shadow down-right and a light up-left, each with a light- and a
/// dark-mode value (owner, 2026-10-01: "darker for dark mode. not this grayblue … my shadows arent perfect").
enum SalahPalette: String, CaseIterable, Identifiable {
    /// Neutral grey; near-black in dark mode.
    case charcoal
    /// A warm off-white; warm near-black in dark mode.
    case stone
    /// The tasbeeh page's own (NeuRing / NeuDarkShad / NeuLightShad): the grey-blue.
    case tasbeeh

    var id: String { rawValue }
    var title: String {
        switch self {
        case .charcoal: "Charcoal"
        case .stone: "Stone"
        case .tasbeeh: "Tasbeeh's (grey-blue)"
        }
    }

    static let key = "salahLook.palette"
    static var current: SalahPalette { CircleTheme.stored.palette }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    var surface: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 0.925, alpha: 1), dark: UIColor(white: 0.10, alpha: 1))
        case .stone: Self.dynamic(light: UIColor(red: 0.937, green: 0.929, blue: 0.914, alpha: 1),
                                  dark: UIColor(red: 0.118, green: 0.112, blue: 0.104, alpha: 1))
        case .tasbeeh: Color("NeuRing")
        }
    }

    var shade: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 0, alpha: 0.17), dark: UIColor(white: 0, alpha: 0.75))
        case .stone: Self.dynamic(light: UIColor(red: 0.42, green: 0.36, blue: 0.28, alpha: 0.24),
                                  dark: UIColor(white: 0, alpha: 0.72))
        case .tasbeeh: Color("NeuDarkShad")
        }
    }

    var light: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 1, alpha: 0.95), dark: UIColor(white: 1, alpha: 0.06))
        case .stone: Self.dynamic(light: UIColor(white: 1, alpha: 0.9),
                                  dark: UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.06))
        case .tasbeeh: Color("NeuLightShad")
        }
    }
}

/// The stored palette's colours, for code outside a view (still used by the welcome and the lost page's rings until
/// they read the theme — circle steps 3–4).
enum Neu {
    static var surface: Color { SalahPalette.current.surface }
    static var dark: Color { SalahPalette.current.shade }
    static var light: Color { SalahPalette.current.light }
}

/// Lifted off the page. Blur twice the offset, both shadows the same distance — the soft, even lift.
struct NeuRaised<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 8
    var offset: CGFloat = 4
    @Environment(\.circleTheme) private var theme

    var body: some View {
        shape.fill(theme.surface)
            .shadow(color: theme.shade, radius: radius, x: offset, y: offset)
            .shadow(color: theme.light, radius: radius, x: -offset, y: -offset)
    }
}

/// Pressed into the page.
struct NeuPressed<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 5
    var offset: CGFloat = 3
    @Environment(\.circleTheme) private var theme

    var body: some View {
        shape.fill(theme.surface
            .shadow(.inner(color: theme.shade, radius: radius, x: offset, y: offset))
            .shadow(.inner(color: theme.light, radius: radius, x: -offset, y: -offset)))
    }
}

/// The page's surface (backdrop, bottom bar).
struct NeuSurface: View {
    @Environment(\.circleTheme) private var theme
    var body: some View { theme.surface }
}

/// A groove between the page and the bottom bar: a shade line over a light one, like a line pressed into the
/// surface (owner, 2026-10-01: "bottom bar needs some divider. neumorphic too").
struct NeuGroove: View {
    @Environment(\.circleTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.shade.opacity(0.6)).frame(height: 1)
            Rectangle().fill(theme.light).frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The ring's soft track, drawn like the tasbeeh counter's ring (NeuCircularProgressView, "fine"): a 6 pt
/// band at 200 pt, a dark shadow (4, +2) and a light one (6, −2), under the arc.
struct NeuRingTrack: View {
    /// 1 = the raised band; down to 0 it narrows and settles into the surface, as the dashed "not started" ring comes
    /// in (MainCircleView's trackSolid) — the grey band's own narrowing, in this material.
    var solid: CGFloat = 1
    @Environment(\.circleTheme) private var theme

    var body: some View {
        let lift = Double(min(max(solid, 0), 1))
        Circle()
            .stroke(lineWidth: max(AliveRingTuning.fine.band * solid, 0.5))
            .frame(width: 200, height: 200)
            .foregroundStyle(theme.surface)
            .shadow(color: theme.shade.opacity(lift), radius: 4, x: 2, y: 2)
            .shadow(color: theme.light.opacity(lift), radius: 6, x: -2, y: -2)
            .opacity(solid > 0.02 ? 1 : 0)
            .allowsHitTesting(false)
    }
}
