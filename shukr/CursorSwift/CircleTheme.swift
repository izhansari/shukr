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
    /// A tasbeeh session's layout when picked on its own (DEBUG `-salahLook.sessionLayout ringAbove|classic`); nil
    /// follows the material (`sessionLayout`).
    var sessionLayoutPick: SessionLayout? = nil

    /// The look before the prototype (DEBUG builds can still pick it in the palette menu; circle-check's "today").
    static let today = CircleTheme()
    /// The public look (decision public-style-lock A, owner: "sunken well · soft ring · no lines between prayers ·
    /// light mode in grey-blue style but dark mode in charcoal"; rows make room then fade — RowMotion.standard —
    /// and a zikr ring opens in sink and rise — SessionOpening).
    static let publicLook = CircleTheme(list: .well, softRing: true, palette: .greyBlue, lines: false)
    /// **The look that ships.** Public builds (TestFlight, App Store) are locked to it: they read none of the palette
    /// menu's keys, so an old pick can't linger. DEBUG builds start from it and the palette menu overrides it.
    static let standard: CircleTheme = .publicLook

    /// The palette menu's stored picks in DEBUG builds (launch arguments override them for a run); `standard` in
    /// public ones.
    static var stored: CircleTheme {
        #if !DEBUG
        return standard
        #endif
        let d = UserDefaults.standard
        let s = standard
        return CircleTheme(list: SalahLook(rawValue: d.string(forKey: SalahLook.key) ?? "") ?? s.list,
                           softRing: d.object(forKey: SalahLook.softRingKey) == nil ? s.softRing : d.bool(forKey: SalahLook.softRingKey),
                           palette: SalahPalette(rawValue: d.string(forKey: SalahPalette.key) ?? "") ?? s.palette,
                           lines: d.object(forKey: SalahLook.linesKey) == nil ? s.lines : d.bool(forKey: SalahLook.linesKey),
                           sessionLayoutPick: SessionLayout(rawValue: d.string(forKey: SessionLayout.key) ?? ""))
    }

    // MARK: What views ask

    /// The pages wear the soft material (the Salah and Zikr backdrop, the bottom bar, the tasbeeh page): any list
    /// look but today's, or the soft ring alone.
    var soft: Bool { list != .today || softRing }
    /// How a tasbeeh session lays out round its ring — apart from the material, so the layout survives a change of
    /// look (Sami's review of b3ed3e3; owner: "making sure our code holds up to interchangeable styling"). The soft
    /// material brings the ring-above layout unless one is picked.
    var sessionLayout: SessionLayout { sessionLayoutPick ?? (soft ? .ringAbove : .classic) }
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

    // MARK: Surfaces (views draw these instead of asking "soft?" — audit F, U3)

    /// The page behind the circle: the Salah and Zikr pages, the bottom bar, the welcome, the morning card.
    var backdrop: Color { soft ? surface : Color(.systemBackground) }

    /// The prayer arc's stroke: a fine round band with a glow on the soft ring; 4 pt, butt caps, no glow otherwise.
    struct Arc: Equatable {
        var width: CGFloat
        var cap: CGLineCap
        /// The arc's colour at this opacity, as its shadow.
        var glow: Double
        /// In a prayer's Perfect window the arc comes alive (the drifting fill).
        var alivePerfect: Bool
    }
    var arc: Arc {
        softRing ? Arc(width: AliveRingTuning.fine.band, cap: .round, glow: AliveRingTuning.fine.glow, alivePerfect: true)
                 : Arc(width: 4, cap: .butt, glow: 0, alivePerfect: false)
    }

    /// The circle's track under the arc: the soft ring's raised band (its surface, lifted), or Today's 12 pt grey band.
    struct Track: Equatable {
        var width: CGFloat
        var fill: Color
        /// The soft lift's shadows (down-right shade, up-left light), or none.
        var lifted: Bool
        /// A prayer still to come draws its dashes inside the band (the soft ring), not instead of it.
        var dashesInBand: Bool
    }
    var track: Track {
        softRing ? Track(width: AliveRingTuning.fine.band, fill: surface, lifted: true, dashesInBand: true)
                 : Track(width: 12, fill: Color(.secondarySystemFill), lifted: false, dashesInBand: false)
    }

    /// The prayer list's way in under the circle: Today's slides up from the bottom; the soft looks rise 36 pt from just
    /// under their place, so they never cross the fixed "N done" line or the bar (decision list-reveal-rise A).
    var listEntrance: AnyTransition {
        soft ? .offset(y: 36).combined(with: .opacity) : .move(edge: .bottom).combined(with: .opacity)
    }
    /// Room under the open list for the soft looks' "N done" line, which sits in the chrome above the bar.
    var listFooterRoom: CGFloat { soft ? 44 : 0 }
    /// Today's row fill: see-through on a tinted page (the soft ring with Today's list drew black slabs).
    func rowFill(_ plain: Color) -> Color { soft ? .clear : plain }
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
    #if DEBUG
    @AppStorage(SalahLook.key) private var list = CircleTheme.standard.list.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = CircleTheme.standard.softRing
    @AppStorage(SalahPalette.key) private var palette = CircleTheme.standard.palette.rawValue
    @AppStorage(SalahLook.linesKey) private var lines = CircleTheme.standard.lines
    @AppStorage(SessionLayout.key) private var sessionLayout = ""

    func body(content: Content) -> some View {
        content.environment(\.circleTheme, CircleTheme(list: SalahLook(rawValue: list) ?? CircleTheme.standard.list,
                                                       softRing: softRing,
                                                       palette: SalahPalette(rawValue: palette) ?? CircleTheme.standard.palette,
                                                       lines: lines,
                                                       sessionLayoutPick: SessionLayout(rawValue: sessionLayout)))
    }
    #else
    /// Public builds: the locked look, whatever the stored keys say (decision public-style-lock A).
    func body(content: Content) -> some View {
        content.environment(\.circleTheme, CircleTheme.standard)
    }
    #endif
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
    /// The public look's (owner, public-style-lock: "light mode in grey-blue style but dark mode in charcoal"): the
    /// tasbeeh grey-blue in light mode, charcoal in dark.
    case greyBlue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .charcoal: "Charcoal"
        case .stone: "Stone"
        case .tasbeeh: "Tasbeeh's (grey-blue)"
        case .greyBlue: "Grey-blue light, charcoal dark"
        }
    }

    static let key = "salahLook.palette"

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    var surface: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 0.925, alpha: 1), dark: UIColor(white: 0.10, alpha: 1))
        case .stone: Self.dynamic(light: UIColor(red: 0.937, green: 0.929, blue: 0.914, alpha: 1),
                                  dark: UIColor(red: 0.118, green: 0.112, blue: 0.104, alpha: 1))
        case .tasbeeh: Color("NeuRing")
        case .greyBlue: Self.lightOf(.tasbeeh, \.surface, darkFrom: .charcoal)
        }
    }

    var shade: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 0, alpha: 0.17), dark: UIColor(white: 0, alpha: 0.75))
        case .stone: Self.dynamic(light: UIColor(red: 0.42, green: 0.36, blue: 0.28, alpha: 0.24),
                                  dark: UIColor(white: 0, alpha: 0.72))
        case .tasbeeh: Color("NeuDarkShad")
        case .greyBlue: Self.lightOf(.tasbeeh, \.shade, darkFrom: .charcoal)
        }
    }

    var light: Color {
        switch self {
        case .charcoal: Self.dynamic(light: UIColor(white: 1, alpha: 0.95), dark: UIColor(white: 1, alpha: 0.06))
        case .stone: Self.dynamic(light: UIColor(white: 1, alpha: 0.9),
                                  dark: UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.06))
        case .tasbeeh: Color("NeuLightShad")
        case .greyBlue: Self.lightOf(.tasbeeh, \.light, darkFrom: .charcoal)
        }
    }

    /// One palette's light-mode colour with another's dark-mode one.
    private static func lightOf(_ lightPalette: SalahPalette, _ part: KeyPath<SalahPalette, Color>,
                                darkFrom darkPalette: SalahPalette) -> Color {
        let light = UIColor(lightPalette[keyPath: part]), dark = UIColor(darkPalette[keyPath: part])
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? dark.resolvedColor(with: traits)
                : light.resolvedColor(with: UITraitCollection(traitsFrom: [traits, UITraitCollection(userInterfaceStyle: .light)]))
        })
    }
}

/// A tasbeeh session's layout (decision session-flow-build A).
enum SessionLayout: String {
    /// The pause screen and the results cover the counter (Today's look).
    case classic
    /// The counter's ring stays on screen: raised for the pause cards, centred for the results.
    case ringAbove
    static let key = "salahLook.sessionLayout"
}

/// A card lifted off the page in the theme's material: the soft lift, else a plain tint with a hairline. Layouts draw
/// with these (not NeuRaised) so they hold up whichever material is picked.
struct ThemedRaised<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 8
    var offset: CGFloat = 4
    @Environment(\.circleTheme) private var theme

    var body: some View {
        if theme.soft {
            NeuRaised(shape: shape, radius: radius, offset: offset)
        } else {
            shape.fill(Color.primary.opacity(0.05))
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// A well pressed into the page in the theme's material: the soft press, else a plain tint.
struct ThemedPressed<S: Shape>: View {
    let shape: S
    @Environment(\.circleTheme) private var theme

    var body: some View {
        if theme.soft {
            NeuPressed(shape: shape)
        } else {
            shape.fill(Color.primary.opacity(0.04))
        }
    }
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

/// Pressed into the page at `lift` 0 (NeuPressed's well), raised off it at 1 — one shape whose shadows travel: the inner
/// ones shrink to nothing by halfway, then the outer ones grow (the day's page, Izhan: "make it look like the card raises up
/// off the page. not just a crossfade"). Animatable: `lift` is drawn at every step between.
struct NeuLiftCard<S: Shape>: View, Animatable {
    let shape: S
    var lift: CGFloat
    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }
    @Environment(\.circleTheme) private var theme

    var body: some View {
        let sink = max(0, 1 - lift * 2), rise = max(0, lift * 2 - 1)
        // Inner shadows only while they show: at zero size they filled the card with the light colour (white in dark).
        let fill: AnyShapeStyle = sink > 0.01
            ? AnyShapeStyle(theme.surface
                .shadow(.inner(color: theme.shade.opacity(sink), radius: 7 * sink, x: 5 * sink, y: 5 * sink))
                .shadow(.inner(color: theme.light.opacity(sink), radius: 7 * sink, x: -5 * sink, y: -5 * sink)))
            : AnyShapeStyle(theme.surface)
        shape.fill(fill)
            .shadow(color: theme.shade.opacity(rise), radius: 12 * rise, x: 6 * rise, y: 6 * rise)
            .shadow(color: theme.light.opacity(rise), radius: 12 * rise, x: -6 * rise, y: -6 * rise)
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

/// The line between the page and the bottom bar: a groove pressed into the soft surface, else the plain divider.
/// `plain`: the plain one regardless (the Settings page keeps the system look).
struct ThemedBarDivider: View {
    var plain = false
    @Environment(\.circleTheme) private var theme

    var body: some View {
        let groove = theme.soft && !plain
        Divider()
            .frame(height: 2)
            .background(Color(.secondarySystemBackground))
            .opacity(groove ? 0 : 1)
            .overlay(alignment: .top) { if groove { NeuGroove() } }
    }
}
