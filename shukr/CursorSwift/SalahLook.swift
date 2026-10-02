//
//  SalahLook.swift
//  shukr
//
//  Prototype (owner, 2026-10-01, decision prayer-list-look): soft (neumorphic) looks for the Salah page in
//  the tasbeeh page's material, switched from the top right while he lives with them. Owner only
//  (`WhatsNewAccess.available`); everyone else keeps `.today`. Any soft look tints the whole Salah page —
//  backdrop, top and bottom bars — in `Neu.surface` (the tasbeeh ring's colour, with a dark-mode twin).
//

import SwiftUI

enum SalahLook: String, CaseIterable, Identifiable {
    /// The look before the prototype: a thin bordered card, white page.
    case today
    /// Each prayer a raised pill; the current one pressed in, done ones flat on the page.
    case pills
    /// One raised card holding the list.
    case card
    /// One sunken well holding the list.
    case well
    /// No card, pills or lines; only the current prayer pressed in.
    case quiet

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today's look"
        case .pills: "Pills"
        case .card: "Raised card"
        case .well: "Sunken well"
        case .quiet: "Quiet"
        }
    }

    static let key = "salahLook.list"
    static let softRingKey = "salahLook.softRing"

    /// The Salah page wears the soft material: any look but today's, or the soft ring alone.
    static func tinted(_ raw: String, softRing: Bool) -> Bool {
        (SalahLook(rawValue: raw) ?? .today) != .today || softRing
    }
}

/// How prayer rows come and go in the list (a done one folding away, "N done" opening and closing). Tried
/// from the same palette menu (owner, 2026-10-01: "fix the transitions of show hiding the prayer items").
enum RowMotion: String, CaseIterable, Identifiable {
    /// The others move first, then the new row fades in; a leaving row fades out quickly before they close
    /// up. With a plain fade a row came in at its final place while its neighbours were still sliding, so
    /// two names sat on top of each other for a few frames (owner's recording, 2026-10-01: "still no good").
    case room
    /// The motion before: in sliding down from the top, out shrinking to the left, on a spring.
    case today
    /// Opacity only, a short ease.
    case fade
    /// A small drop: fading in from a few points above, out the same way.
    case drop
    /// The system's blur-replace: soft focus in and out.
    case blur
    /// Instant: rows appear and go with no motion.
    case none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .room: "Make room, then fade"
        case .today: "Today's motion"
        case .fade: "Fade"
        case .drop: "Drop"
        case .blur: "Blur"
        case .none: "No motion"
        }
    }

    static let key = "salahLook.rowMotion"

    var transition: AnyTransition {
        switch self {
        case .room:
            .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.24)),
                        removal: .opacity.animation(.easeIn(duration: 0.08)))
        case .today:
            .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
        case .fade: .opacity
        case .drop: .opacity.combined(with: .offset(y: -10))
        case .blur: AnyTransition(.blurReplace)
        case .none: .identity
        }
    }

    /// The animation for a row change; `springy` is what today's motion used at that spot.
    func animation(springy: Animation) -> Animation? {
        switch self {
        case .today: springy
        case .room, .fade, .drop, .blur: .easeInOut(duration: 0.3)
        case .none: nil
        }
    }
}

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
    static var current: SalahPalette { SalahPalette(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .charcoal }

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

/// The current palette's colours. Views that draw with them also observe `SalahPalette.key`, so a change in
/// the menu repaints them.
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
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue

    var body: some View {
        let p = SalahPalette(rawValue: paletteRaw) ?? .charcoal
        shape.fill(p.surface)
            .shadow(color: p.shade, radius: radius, x: offset, y: offset)
            .shadow(color: p.light, radius: radius, x: -offset, y: -offset)
    }
}

/// Pressed into the page.
struct NeuPressed<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 5
    var offset: CGFloat = 3
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue

    var body: some View {
        let p = SalahPalette(rawValue: paletteRaw) ?? .charcoal
        shape.fill(p.surface
            .shadow(.inner(color: p.shade, radius: radius, x: offset, y: offset))
            .shadow(.inner(color: p.light, radius: radius, x: -offset, y: -offset)))
    }
}

/// The page's surface (backdrop, bottom bar), repainted when the palette changes.
struct NeuSurface: View {
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue
    var body: some View { (SalahPalette(rawValue: paletteRaw) ?? .charcoal).surface }
}

/// A groove between the page and the bottom bar: a shade line over a light one, like a line pressed into the
/// surface (owner, 2026-10-01: "bottom bar needs some divider. neumorphic too").
struct NeuGroove: View {
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue

    var body: some View {
        let p = SalahPalette(rawValue: paletteRaw) ?? .charcoal
        VStack(spacing: 0) {
            Rectangle().fill(p.shade.opacity(0.6)).frame(height: 1)
            Rectangle().fill(p.light).frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The prayer list's frame and card for the chosen look (was `.frame(width: 260).background(FlatBorder())`).
struct SalahLookListFrame: ViewModifier {
    @AppStorage(SalahLook.key) private var lookRaw = SalahLook.today.rawValue

    func body(content: Content) -> some View {
        // The rows are clipped to the card: rows coming in ("N done", a fold) appear at their final place at
        // once while the card's height animates, so unclipped they floated on the page outside it for a few
        // frames — "ghosty" (owner's recording, 2026-10-01). Clipped, the card opens like a drawer.
        let card = RoundedRectangle(cornerRadius: 24, style: .continuous)
        switch SalahLook(rawValue: lookRaw) ?? .today {
        case .today:
            content.frame(width: 260).clipShape(RoundedRectangle(cornerRadius: 20)).background(FlatBorder())
        case .card:
            content.frame(width: 290).clipShape(card).background(NeuRaised(shape: card, radius: 14, offset: 7))
        case .well:
            content.frame(width: 290).clipShape(card).background(NeuPressed(shape: card, radius: 7, offset: 5))
        case .pills, .quiet:
            content.frame(width: 290)
        }
    }
}

/// The ring's soft track, drawn like the tasbeeh counter's ring (NeuCircularProgressView, "fine"): a 6 pt
/// band at 200 pt, a dark shadow (4, +2) and a light one (6, −2), under the arc.
struct NeuRingTrack: View {
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue

    var body: some View {
        let p = SalahPalette(rawValue: paletteRaw) ?? .charcoal
        Circle()
            .stroke(lineWidth: AliveRingTuning.fine.band)
            .frame(width: 200, height: 200)
            .foregroundStyle(p.surface)
            .shadow(color: p.shade, radius: 4, x: 2, y: 2)
            .shadow(color: p.light, radius: 6, x: -2, y: -2)
            .allowsHitTesting(false)
    }
}

/// Top right on the Salah page while the owner tries the looks: the list look, the soft ring, the colours and
/// how rows come and go.
struct SalahLookSwitcher: View {
    @AppStorage(SalahLook.key) private var lookRaw = SalahLook.today.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = false
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.today.rawValue
    @AppStorage(SalahPalette.key) private var paletteRaw = SalahPalette.charcoal.rawValue

    var body: some View {
        Menu {
            Picker("List", selection: $lookRaw) {
                ForEach(SalahLook.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Soft ring", isOn: $softRing)
            Picker("Colours", selection: $paletteRaw) {
                ForEach(SalahPalette.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            Picker("Rows come and go", selection: $motionRaw) {
                ForEach(RowMotion.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "paintpalette")
                .frame(width: 24, height: 24)
                .font(.system(size: 18))
                .fontWeight(.light)
                .foregroundColor(.gray.opacity(0.8))
                .padding()
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Salah page look")
    }
}
