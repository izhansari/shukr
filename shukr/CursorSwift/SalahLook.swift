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
        case .today: "Today's motion"
        case .fade: "Fade"
        case .drop: "Drop"
        case .blur: "Blur"
        case .none: "No motion"
        }
    }

    static let key = "salahLook.rowMotion"
    static var current: RowMotion { RowMotion(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .today }

    var transition: AnyTransition {
        switch self {
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
        case .fade, .drop, .blur: .easeInOut(duration: 0.3)
        case .none: nil
        }
    }
}

/// The tasbeeh page's material (NeuCircularProgressView): one surface, a dark shadow down-right, a light one
/// up-left.
enum Neu {
    static let surface = Color("NeuRing")
    static let dark = Color("NeuDarkShad")
    static let light = Color("NeuLightShad")
}

/// Lifted off the page.
struct NeuRaised<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 5
    var offset: CGFloat = 4

    var body: some View {
        shape.fill(Neu.surface)
            .shadow(color: Neu.dark, radius: radius, x: offset, y: offset)
            .shadow(color: Neu.light, radius: radius, x: -offset, y: -offset)
    }
}

/// Pressed into the page.
struct NeuPressed<S: Shape>: View {
    let shape: S
    var radius: CGFloat = 4
    var offset: CGFloat = 3

    var body: some View {
        shape.fill(Neu.surface
            .shadow(.inner(color: Neu.dark, radius: radius, x: offset, y: offset))
            .shadow(.inner(color: Neu.light, radius: radius, x: -offset, y: -offset)))
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
            content.frame(width: 290).clipShape(card).background(NeuRaised(shape: card, radius: 8, offset: 6))
        case .well:
            content.frame(width: 290).clipShape(card).background(NeuPressed(shape: card, radius: 5, offset: 5))
        case .pills, .quiet:
            content.frame(width: 290)
        }
    }
}

/// The ring's soft track: a raised band under the arc, like the tasbeeh counter's ring.
struct NeuRingTrack: View {
    var body: some View {
        Circle()
            .stroke(lineWidth: 22)
            .frame(width: 200, height: 200)
            .foregroundStyle(Neu.surface)
            .shadow(color: Neu.dark, radius: 4, x: 2, y: 2)
            .shadow(color: Neu.light, radius: 6, x: -2, y: -2)
            .allowsHitTesting(false)
    }
}

/// Top right on the Salah page while the owner tries the looks: the list look and the soft ring.
struct SalahLookSwitcher: View {
    @AppStorage(SalahLook.key) private var lookRaw = SalahLook.today.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = false
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.today.rawValue

    var body: some View {
        Menu {
            Picker("List", selection: $lookRaw) {
                ForEach(SalahLook.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Soft ring", isOn: $softRing)
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
