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
    /// The lines between prayers in the card / well looks (owner, 2026-10-01: "curious to see … sunken and they
    /// don't have those separator lines"); Today's look always keeps them.
    static let linesKey = "salahLook.lines"

    /// The Salah page wears the soft material: any look but today's, or the soft ring alone.
    static func tinted(_ raw: String, softRing: Bool) -> Bool {
        (SalahLook(rawValue: raw) ?? .today) != .today || softRing
    }
}

#if DEBUG
extension SalahLook {
    /// Dev builds (the owner's phone and the simulators) start the look exploration on Sunken well with no lines
    /// between prayers (owner, 2026-10-01: "default to no lines with sunken card for this exploring aesthetic
    /// testing stuff"). Once per install, so a later pick in the palette menu stays. TestFlight / App Store
    /// builds aren't touched: everyone else keeps Today's look.
    static func seedExploringDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "salahLook.seeded.v1") else { return }
        d.set(true, forKey: "salahLook.seeded.v1")
        d.set(SalahLook.well.rawValue, forKey: key)
        d.set(false, forKey: linesKey)
    }
}
#endif

/// The palette's Play menu (owner, 2026-10-01: "idk what a good way is for you to allow me to be able to play them
/// in the sim and judge it"): each animation on the Salah page replayed on the spot, visual only — nothing is
/// marked, moved or saved.
enum SalahLookPlay {
    /// The completion flourish (and the post-salah pill after it) for the prayer on the circle, at today's score.
    static let mark = Notification.Name("salahLookPlay.mark")
    /// The opening welcome; object: true = from black (the sleep morning's open).
    static let welcome = Notification.Name("salahLookPlay.welcome")
    /// The good-morning card after a sleep-mode session, over the welcome from black, with the latest session.
    static let morning = Notification.Name("salahLookPlay.morning")
}

/// Opening a tasbeeh session from the Zikr wheel under the soft look (owner, 2026-10-01: "clicking on a zikr task
/// ring … everything else fades out and that ring becomes the same counter as in our tasbeeh session … no sheet
/// popping over"). The wheel records the tapped ring's place, fades the rest and opens the session with no
/// animation over a clear presentation background; the session's counter ring starts on that place and glides to
/// its own (a few points apart on most phones) while its page fades in. Closing fades the session away over the
/// wheel. Every other way into a session, and Today's look, keep the usual sheet.
enum SoftSessionEntry {
    /// The tapped ring's frame (global), read by the session as it opens; cleared once it has.
    static var fromFrame: CGRect? {
        didSet { fromFrameAt = fromFrame == nil ? nil : Date() }
    }
    private static var fromFrameAt: Date?
    /// `fromFrame` if it was set for this opening (within a second) — a stale one (an opening that never
    /// happened) must not move the next session's ring, opened some other way.
    static var freshFrame: CGRect? {
        guard let at = fromFrameAt, Date().timeIntervalSince(at) < 1 else { return nil }
        return fromFrame
    }
    /// The open session came in this way, so it leaves this way (the host's binding, PrayerTimesView).
    static var coverIsSoft = false
    /// Close it softly: the session fades out (then the host dismisses with no animation).
    static let leave = Notification.Name("softSessionEntry.leave")
    /// How long the session's leaving takes before the host may remove the cover (set by the session as it opens).
    static var leaveDelay: Double = 0.32

    /// The soft look is on (the wheel's rings are the tasbeeh ring then).
    static var enabled: Bool {
        let d = UserDefaults.standard
        return SalahLook.tinted(d.string(forKey: SalahLook.key) ?? SalahLook.today.rawValue,
                                softRing: d.bool(forKey: SalahLook.softRingKey))
    }
}

/// How a session opens out of a Zikr ring (SoftSessionEntry), picked in the palette (owner, 2026-10-01: "too simple
/// of a crossfade... something elegant but simple").
enum SessionOpening: String, CaseIterable, Identifiable {
    /// The session's page opens out from the ring's centre in a widening circle (and closes back into it); the wheel's
    /// other circles drift away as they fade.
    case iris
    /// Everything crossfades in place.
    case fade
    var id: String { rawValue }
    var title: String { self == .iris ? "Iris" : "Crossfade" }
    static let key = "salahLook.opening"
    static var current: SessionOpening { SessionOpening(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .iris }
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

extension RowMotion {
    static var current: RowMotion { RowMotion(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .today }
}

/// The prayer list's fold, shared so the soft looks' "N done" can live in the chrome — a fixed spot just above
/// the bottom bar, fading with it, not moving with the card (owner, 2026-10-01). TodaysPrayerListView owns the
/// rule (which rows show) and publishes the footer's count; Today's look keeps its footer in the card.
@Observable final class PrayerListFold {
    static let shared = PrayerListFold()
    /// "N done" tapped: the done prayers are shown too.
    var showDone = false
    /// The soft footer's count, or nil when there's no footer.
    var softFooterCount: Int? = nil
}

/// The soft looks' "N done", above the bottom bar (PagerChromeView). The chevron points to where the rows
/// appear: up while folded, down once they're shown (owner: "switch chevron directions for done and hide").
struct SoftDoneFooter: View {
    private var fold = PrayerListFold.shared

    var body: some View {
        if let count = fold.softFooterCount {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(RowMotion.current.animation(springy: .spring(response: 0.45, dampingFraction: 0.85))) {
                    fold.showDone.toggle()
                }
            } label: {
                // Secondary text, a step quieter than the bar's icons (owner: it read "the same exact color as the
                // icons in the bottom bar").
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                    Text("\(count) done")
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(fold.showDone ? 180 : 0))
                }
                .font(.caption)
                .fontDesign(.rounded)
                .fontWeight(.light)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)   // a little air above the bar (owner: "too close to the bottom bar")
            .transition(.opacity)
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
        switch SalahLook(rawValue: lookRaw) ?? .today {
        case .today:
            content.frame(width: 260).clipShape(RoundedRectangle(cornerRadius: 20)).background(FlatBorder())
        case .card, .well, .pills, .quiet:
            content.frame(width: 290)   // the card goes round the rows only (SalahLookCard), "N done" under it
        }
    }
}

/// The soft looks' card round the prayer rows (inside TodaysPrayerListView, so "N done" sits outside it).
struct SalahLookCard: ViewModifier {
    @AppStorage(SalahLook.key) private var lookRaw = SalahLook.today.rawValue

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: 24, style: .continuous)
        switch SalahLook(rawValue: lookRaw) ?? .today {
        case .card:
            content.clipShape(card).background(NeuRaised(shape: card, radius: 14, offset: 7))
        case .well:
            content.clipShape(card).background(NeuPressed(shape: card, radius: 7, offset: 5))
        case .today, .pills, .quiet:
            content
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
    @AppStorage(SalahLook.linesKey) private var lines = true
    @AppStorage(SessionOpening.key) private var openingRaw = SessionOpening.iris.rawValue

    var body: some View {
        Menu {
            Picker("List", selection: $lookRaw) {
                ForEach(SalahLook.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Lines between prayers", isOn: $lines)
            Toggle("Soft ring", isOn: $softRing)
            Picker("Colours", selection: $paletteRaw) {
                ForEach(SalahPalette.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            Picker("Rows come and go", selection: $motionRaw) {
                ForEach(RowMotion.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            Picker("Zikr ring opens", selection: $openingRaw) {
                ForEach(SessionOpening.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
        } label: {
            ChromeIcon(systemName: "paintpalette")
        }
        .accessibilityLabel("Salah page look")
    }
}

/// Top right on the Salah page, beside the palette, while the owner judges the looks: each animation replayed on
/// the spot, one tap away (owner, 2026-10-01: "make a new button for play in the top right. i hate the nested
/// selection"). Visual only — nothing marked, moved or saved (SalahLookPlay).
struct SalahPlayButton: View {
    @EnvironmentObject private var sharedState: SharedStateClass
    @EnvironmentObject private var location: EnvLocationManager

    var body: some View {
        Menu {
            Button("Marking a prayer", systemImage: "checkmark.circle") { post(SalahLookPlay.mark) }
            Button("Prayer begins", systemImage: "sunrise") { post(PrayerStartPreview.request) }
            Button("Opening", systemImage: "sparkles") { post(SalahLookPlay.welcome, false) }
            Button("Good morning (after sleep)", systemImage: "moon.zzz") { post(SalahLookPlay.morning) }
            Button("No location", systemImage: "location.slash") { after { location.playLostPreview() } }
            Button("Perfect day", systemImage: "star") { playPerfectDay() }
            Button("Streaks", systemImage: "flame") {
                post(.prayerStreakContinued, 12)
                post(.onTimeStreakContinued, 5)
            }
        } label: {
            ChromeIcon(systemName: "play.circle")
        }
        .accessibilityLabel("Play an animation")
        #if DEBUG
        // `-salahPlay mark|begins|welcome|morning|lost|perfect|streaks`: that item, 4 s after launch (checking them
        // in the simulator, whose simulated taps can't open a Menu).
        .task {
            guard let which = UserDefaults.standard.string(forKey: "salahPlay") else { return }
            try? await Task.sleep(for: .seconds(4))
            switch which {
            case "mark": post(SalahLookPlay.mark)
            case "begins": post(PrayerStartPreview.request)
            case "welcome": post(SalahLookPlay.welcome, false)
            case "morning": post(SalahLookPlay.morning)
            case "perfect": playPerfectDay()
            case "lost": after { location.playLostPreview() }
            case "streaks": post(.prayerStreakContinued, 12); post(.onTimeStreakContinued, 5)
            default: break
            }
        }
        #endif
    }

    /// Perfect day plays in the prayer list (the dots pop, "perfect day" under it): open it first.
    private func playPerfectDay() {
        let open = sharedState.navPosition == .bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                sharedState.horizontalPage = .main
                sharedState.navPosition = .bottom
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0.35 : 1.0)) {
            NotificationCenter.default.post(name: .perfectDay, object: true)
        }
    }

    private func after(_ go: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: go)
    }

    private func post(_ name: Notification.Name, _ object: Any? = nil) {
        // After the menu has closed, so the animation plays on a clear page.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: name, object: object)
        }
    }
}

/// The top bar's icon look (the ☰'s grey, light weight).
private struct ChromeIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .frame(width: 24, height: 24)
            .font(.system(size: 18))
            .fontWeight(.light)
            .foregroundColor(.gray.opacity(0.8))
            .padding(.vertical)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
    }
}
