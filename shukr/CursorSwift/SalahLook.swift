//
//  SalahLook.swift
//  shukr
//
//  Prototype (owner, 2026-10-01, decision prayer-list-look): soft (neumorphic) looks for the Salah page in
//  the tasbeeh page's material, switched from the top right while he lives with them. Owner only
//  (`WhatsNewAccess.available`); everyone else keeps `.today`. Any soft look tints the whole Salah page —
//  backdrop, top and bottom bars — in the theme's surface (CircleTheme.swift).
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

    // Whether the page wears the soft material is the theme's `soft` (CircleTheme.swift).
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

    /// One ring (decision zikr-ring-progress B, owner 2026-10-02: "do B"): the arc never crossfades into another length.
    /// Opening, the wheel's arc stays (Continue) or rewinds to empty (Start over, freestyle) as the label sinks, so the
    /// count rises into a ring that already says where it starts; closing, the session's arc moves to where the
    /// wheel's will stand, and only then does the wheel's take over. This is the task's share done today before the
    /// session (freestyle: 1, its full ring), set by the wheel as it opens; nil = not opened from the wheel.
    static var landingBase: Double?
    /// How long the arc takes to rewind or to land.
    static let arcMove: Double = 0.4

    /// Run `work` once the session has gone: after its soft close (so a reset doesn't change what's still fading — the
    /// pause card collapsed when its zikr was cleared mid-fade), else now. Call before setting `isPresented = false`.
    static func afterClose(_ work: @escaping () -> Void) {
        if coverIsSoft && UIApplication.shared.applicationState == .active {
            DispatchQueue.main.asyncAfter(deadline: .now() + leaveDelay + 0.05, execute: work)
        } else {
            work()
        }
    }

    /// The soft look is on (the wheel's rings are the tasbeeh ring then).
    static var enabled: Bool { CircleTheme.stored.soft }
}

/// How a session opens out of a Zikr ring (SoftSessionEntry), picked in the palette (owner, 2026-10-01, decision
/// zikr-ring-transition: "go with E or D. but account for the content in the ring and that it transitions to the
/// counter text properly"; the iris was "a looney tunes cartoon"). The ring itself never moves; its label goes and the
/// counter's text comes in its place, then the buttons, a beat apart.
enum SessionOpening: String, CaseIterable, Identifiable {
    /// E: the other circles and the ring's label sink into the surface (a little smaller, a touch lower, gone); the
    /// session's count and buttons rise out of it.
    case sink
    /// D: everything but the ring goes soft-focus as it fades; the session's count and buttons come into focus.
    case focus
    /// Everything crossfades in place.
    case fade
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sink: "Sink and rise"
        case .focus: "Focus"
        case .fade: "Crossfade"
        }
    }
    static let key = "salahLook.opening"
    static var current: SessionOpening { SessionOpening(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .sink }
}

/// Something in or out the way the opening style moves it: sink = smaller, lower, faded (rising back); focus =
/// blurred, faded; fade = faded.
struct SessionAppear: ViewModifier {
    let shown: Bool
    var style: SessionOpening = .current

    func body(content: Content) -> some View {
        switch style {
        case .sink:
            content
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.94)
                .offset(y: shown ? 0 : 5)
        case .focus:
            content
                .opacity(shown ? 1 : 0)
                .blur(radius: shown ? 0 : 8)
        case .fade:
            content.opacity(shown ? 1 : 0)
        }
    }
}

extension EnvironmentValues {
    /// The Zikr wheel's centred ring is opening into its session: its label goes (SessionAppear), the ring stays.
    @Entry var zikrFaceContentAway: Bool = false
    /// …and its arc has rewound to empty, the session starting from nothing (SoftSessionEntry.landingBase).
    @Entry var zikrFaceArcRewound: Bool = false
}

// RowMotion lives in CircleMotion.swift.

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

// SalahPalette, Neu and the soft materials (NeuRaised, NeuPressed, NeuSurface, NeuGroove, NeuRingTrack) live in
// CircleTheme.swift and read the theme.

/// The prayer list's frame and card for the chosen look (was `.frame(width: 260).background(FlatBorder())`).
struct SalahLookListFrame: ViewModifier {
    @Environment(\.circleTheme) private var theme

    func body(content: Content) -> some View {
        // The rows are clipped to the card: rows coming in ("N done", a fold) appear at their final place at
        // once while the card's height animates, so unclipped they floated on the page outside it for a few
        // frames — "ghosty" (owner's recording, 2026-10-01). Clipped, the card opens like a drawer.
        switch theme.list {
        case .today:
            // Exactly as before the look prototype: not clipped (Sami's audit — the clip cut Today's slide-in rows).
            content.frame(width: 260).background(FlatBorder())
        case .card, .well, .pills, .quiet:
            content.frame(width: 290)   // the card goes round the rows only (SalahLookCard), "N done" under it
        }
    }
}

/// The soft looks' card round the prayer rows (inside TodaysPrayerListView, so "N done" sits outside it).
struct SalahLookCard: ViewModifier {
    @Environment(\.circleTheme) private var theme

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: 24, style: .continuous)
        switch theme.list {
        case .card:
            content.clipShape(card).background(NeuRaised(shape: card, radius: 14, offset: 7))
        case .well:
            content.clipShape(card).background(NeuPressed(shape: card, radius: 7, offset: 5))
        case .today, .pills, .quiet:
            content
        }
    }
}

/// Top right on the Salah page while the owner tries the looks: the list look, the soft ring, the colours and
/// how rows come and go.
struct SalahLookSwitcher: View {
    @AppStorage(SalahLook.key) private var lookRaw = CircleTheme.standard.list.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = CircleTheme.standard.softRing
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.today.rawValue
    @AppStorage(SalahPalette.key) private var paletteRaw = CircleTheme.standard.palette.rawValue
    @AppStorage(SalahLook.linesKey) private var lines = CircleTheme.standard.lines
    @AppStorage(SessionOpening.key) private var openingRaw = SessionOpening.sink.rawValue

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
            // `-salahPlayDelay <s>` (default 4): later, past the opening welcome.
            let delay = UserDefaults.standard.double(forKey: "salahPlayDelay")
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 4))
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

    /// Perfect day plays in the prayer list (the dots pop, "perfect day" under it): open it first, with the done
    /// prayers unfolded (else only the one left popped, under a lone row — Sami's audit, finding 10).
    private func playPerfectDay() {
        let open = sharedState.navPosition == .bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0.1 : 0.7)) {
            withAnimation(RowMotion.current.animation(springy: .spring(response: 0.45, dampingFraction: 0.85))) {
                PrayerListFold.shared.showDone = true
            }
        }
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
