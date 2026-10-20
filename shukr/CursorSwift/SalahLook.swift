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
    // Sami's trial looks (PrayerListLooks.swift, owner 2026-10-14), all in the public well, under "Sami list" in the
    // palette menu. (A · Rings went: the main ring already shows the window — owner.)
    /// B · the day as one thin line through the dots.
    case timeline
    /// C · the prayer on now raised, with its time left (no line under it — owner: we never show progress as a line).
    case now
    /// D · B's line through the dots + C's raised now; bigger names, more air.
    case dayNow
    /// E · the prayer on now leads: a taller raised block, its name a size up, its time left under it; the rest compact.
    case nowLeads
    /// F · each row says what matters for it: when you prayed, the time left, when it starts.
    case prayedAt
    /// The raised list (owner, 2026-10-14: "make it the real thing"; PrayerListRaisedMock.swift was the mock): the whole
    /// list one raised card with capsule-round corners, the prayer on now a capsule band of it raised a step more; G's
    /// behaviour (the score / "at time" on a tap, the marked row's buttons). The public look.
    case raised
    /// G · F's shape, quieter (owner: not the word "prayed"): prayed rows keep their start time; a tap puts the score
    /// where the name sits ("Middle · 88") and when you prayed where the time sits.
    case prayedOnTap

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today's look"
        case .pills: "Pills"
        case .card: "Raised card"
        case .well: "Sunken well"
        case .quiet: "Quiet"
        case .timeline: "B · Timeline"
        case .now: "C · Now"
        case .dayNow: "D · Line + Now"
        case .nowLeads: "E · Now leads"
        case .prayedAt: "F · What happened"
        case .prayedOnTap: "G · F, prayed time on tap"
        case .raised: "Raised list"
        }
    }

    /// The looks before Sami's (the palette's List picker).
    static let originals: [SalahLook] = [.today, .pills, .card, .well, .quiet]
    /// Sami's trial looks (the palette's "Sami list").
    static let sami: [SalahLook] = [.raised, .timeline, .now, .dayNow, .nowLeads, .prayedAt, .prayedOnTap]
    var isSami: Bool { Self.sami.contains(self) }
    /// The prayer on now is the one raised block, with its time left (C, D, E, F).
    var raisesNow: Bool { [.now, .dayNow, .nowLeads, .prayedAt, .prayedOnTap, .raised].contains(self) }
    /// G's behaviour: the score / "at time" on a prayed row's tap, unprayed names regular, the marked row's buttons (G and
    /// the raised list).
    var behavesLikeG: Bool { self == .prayedOnTap || self == .raised }
    /// The raised list's row height: its band is a capsule of it, the card's corners its half. 54 pt (owner, 2026-10-18:
    /// "list items that have more space above and below … they're way too close to each other"; was 44 ≈ the original
    /// list's pitch). Journey's day card uses it too (owner: both pages alike).
    static let raisedRowHeight: CGFloat = 54
    /// The day's line through the dots (B, D).
    var drawsDayLine: Bool { self == .timeline || self == .dayNow }

    static let key = "salahLook.list"
    static let softRingKey = "salahLook.softRing"
    /// The lines between prayers in the card / well looks (owner, 2026-10-01: "curious to see … sunken and they
    /// don't have those separator lines"); Today's look always keeps them.
    static let linesKey = "salahLook.lines"

    // Whether the page wears the soft material is the theme's `soft` (CircleTheme.swift).
}

#if DEBUG
extension SalahLook {
    /// Dev builds (the owner's phone and the simulators): a new install starts on the main build's look; an old one got
    /// each one-time move below once (Sunken well first, 2026-10-01; then the raised list and the rows' motions), so a
    /// later pick in the palette menu stays. TestFlight / App Store builds are locked to `CircleTheme.standard` (the
    /// public look) and never read these keys.
    static func seedExploringDefaults() {
        let d = UserDefaults.standard
        // A fresh install starts on the main build's look (the keys unset → CircleTheme.standard): every seed below is an
        // old install's move, and run in this order on a new one the last (v1) put it back on Sunken well (Sami, 2026-10-19:
        // a new sim came up on the well, its card rising from pressed to raised).
        if !d.bool(forKey: "salahLook.seeded.v1") {
            for v in 1...6 { d.set(true, forKey: "salahLook.seeded.v\(v)") }
            return
        }
        // Installs made before that fix (every team sim, recreated 2026-10-18) were left on Sunken well by the seeding
        // order, not by a pick (owner, 2026-10-19: "why is the recessed look everywhere for the list instead of the new look
        // we've made … it keeps popping up in different sim tests"): once, back to the main build's look.
        if !d.bool(forKey: "salahLook.seeded.v6") {
            d.set(true, forKey: "salahLook.seeded.v6")
            if d.string(forKey: key) == SalahLook.well.rawValue {
                d.removeObject(forKey: key)
                d.removeObject(forKey: linesKey)
            }
        }
        // The accordion became the rows' motion (owner, 2026-10-14): once, onto it.
        if !d.bool(forKey: "salahLook.seeded.v3") {
            d.set(true, forKey: "salahLook.seeded.v3")
            d.set(RowMotion.unfold.rawValue, forKey: RowMotion.key)
        }
        // The fan, the different style to try (owner, 2026-10-14): once, onto it.
        if !d.bool(forKey: "salahLook.seeded.v4") {
            d.set(true, forKey: "salahLook.seeded.v4")
            d.set(RowMotion.fan.rawValue, forKey: RowMotion.key)
        }
        // Settle (out, then in) became the rows' motion (owner, 2026-10-14): once, onto it.
        if !d.bool(forKey: "salahLook.seeded.v5") {
            d.set(true, forKey: "salahLook.seeded.v5")
            d.set(RowMotion.settle.rawValue, forKey: RowMotion.key)
        }
        // The raised list became the look (owner, 2026-10-14): once, onto it, whatever was picked before.
        if !d.bool(forKey: "salahLook.seeded.v2") {
            d.set(true, forKey: "salahLook.seeded.v2")
            d.set(SalahLook.raised.rawValue, forKey: key)
        }
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
///
/// One observable object the wheel, the host (PrayerTimesView's cover) and the session share (the transitions cleanup,
/// audit E): it replaced `SoftSessionEntry`'s statics — a frame handed through a static with a wall-clock freshness
/// check, and a close timed three times (host, session, wheel) off a hand-summed `leaveDelay`. Now the session plays
/// its close and says so; the host and the wheel follow its phases.
@MainActor @Observable final class SessionHandoff {
    static let shared = SessionHandoff()

    // MARK: Opening

    /// What the wheel hands the session as it opens out of a ring: the ring's place (global) and the task's share
    /// before the session (decision zikr-ring-progress B: the arc lands there as it closes; nil = a plain close).
    struct Entry {
        let frame: CGRect
        let landingBase: Double?
        let at: TimeInterval
    }
    @ObservationIgnored private var entry: Entry?
    /// The entry if it was handed over for this opening (within a second, by `Uptime`, never the wall clock — circle-check
    /// pins it): a stale one (an opening that never happened) must not move the next session's ring.
    var freshEntry: Entry? {
        guard let entry, Uptime.now - entry.at < Self.entryFreshness else { return nil }
        return entry
    }
    /// The session takes the entry as it opens (and keeps its own copy).
    func takeEntry() -> Entry? {
        defer { entry = nil }
        return freshEntry
    }
    private static let entryFreshness: Double = 1

    /// The wheel opens a session out of a ring: the cover comes up clear (the session fades in over the wheel).
    func open(from frame: CGRect, landingBase: Double?) {
        entry = Entry(frame: frame, landingBase: landingBase, at: Uptime.now)
        soft = true
        inPlace = false
        phase = .open
    }

    /// A session opened on the Salah page (post-salah, Tasbih Fatimah; decision post-salah-entry A): one cover, out
    /// then in, both ways, nothing measured — the same whether the list is open or closed. In: the cover comes up with
    /// no animation over a clear background, its page fades in over the Salah page, then its contents
    /// (`enteringInPlace`, tasbeehView); then the cover is opaque (`enteredInPlace`). Out: its contents go where they
    /// stand, its page fades off the Salah page, the cover goes with no animation (post-salah-close). The host calls it
    /// before presenting (`entering`); a session that's already up calls it with `entering: false` so it still closes
    /// in place. Only from a plain state: a wheel session keeps its own way in and out.
    /// False when refused (a session's cover is still up or closing): the caller presents it the usual way then.
    @discardableResult
    func openInPlace(entering: Bool = true) -> Bool {
        guard phase == .closed else { return false }
        entry = nil
        inPlace = true
        soft = entering
        phase = .open
        return true
    }
    /// The in-place entry is still to play (read once by the session as it's made).
    var enteringInPlace: Bool { inPlace && soft && phase == .open }
    /// The in-place entry has played: the cover is opaque again (the page under it isn't kept drawing).
    func enteredInPlace() { if inPlace && phase == .open { soft = false } }
    /// Opened with `openInPlace`: the close plays in place (no ring to land).
    private(set) var inPlace = false
    /// The session closes by its own fade (a wheel session, or one opened in place): resets wait for the cover to go.
    var closesSoftly: Bool { soft || inPlace }

    // MARK: The cover

    /// The cover is clear behind the session (it opened out of a ring), from the opening until the cover has really
    /// gone (`coverGone`). Observed by the host's `.presentationBackground`: cleared at the close's start, a re-render
    /// mid-close would have made it opaque over the wheel (audit E2).
    private(set) var soft = false

    enum Phase {
        /// No soft session (or a plain one).
        case closed
        case open
        /// The host asked it to close: the session plays its close (tasbeehView), then says `.done`.
        case leaving
        /// Its page is about to go: the wheel puts its ring's label and arc back under it (still opaque).
        case revealing
        /// The close has played: the host removes the cover, with no animation.
        case done
    }
    private(set) var phase: Phase = .closed

    /// The host's binding was set to false: a soft cover on screen closes by its session's own close; anything else
    /// (a plain sheet, the app in the background — a sleep finish needs it gone in that turn) closes at once.
    func shouldPlayClose(appActive: Bool) -> Bool { closesSoftly && appActive && phase == .open }
    func requestClose() {
        if inPlace { soft = true }   // the cover clears behind the page, so the Salah page is there as the page fades
        phase = .leaving
    }
    func reveal() { if phase == .leaving { phase = .revealing } }
    func finishClose() { if phase == .leaving || phase == .revealing { phase = .done } }

    /// The cover has gone (its `onDismiss`): the rest of the app may change what the session showed.
    func coverGone() {
        soft = false
        inPlace = false
        phase = .closed
        entry = nil
        let work = afterCloseWork
        afterCloseWork = []
        work.forEach { $0() }
    }

    @ObservationIgnored private var afterCloseWork: [() -> Void] = []
    /// Runs `work` once the session's cover has gone — after a soft close (so a reset doesn't change what's still
    /// fading: the pause card collapsed when its zikr was cleared mid-fade), else now. Was a guess of the close's
    /// length plus 0.05 s.
    func afterClose(_ work: @escaping () -> Void) {
        if closesSoftly && UIApplication.shared.applicationState == .active {
            afterCloseWork.append(work)
        } else {
            work()
        }
    }
}

/// How a session opens out of a Zikr ring (SessionHandoff), picked in the palette (owner, 2026-10-01, decision
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
    /// A stored pick in DEBUG builds; public builds are locked to sink and rise (decision public-style-lock A).
    static var current: SessionOpening {
        #if DEBUG
        SessionOpening(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .sink
        #else
        .sink
        #endif
    }
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

/// "Journey ›" on the day's page, in "N done"'s spot above the bottom bar (decision memories-link-place B: under the
/// day's line the list rode up over it) — Journey (Journey.swift) holds the day, the month and Moments (owner, 2026-10-15).
/// While a developed photo waits for its tap it reads "N photos to develop ›" and opens Moments, where they develop.
struct MemoriesFooterLink: View {
    private var day = DayPageState.shared
    private var photos = PrayerPhotoRevision.shared
    private var reveals = PhotoRevealState.shared

    /// Developed photos still to be tapped (PhotoDevelop.needsReveal), any day.
    private var waiting: Int { PrayerPhotos.all().filter { PhotoDevelop.needsReveal(key: $0.key) }.count }

    var body: some View {
        let _ = photos.value
        let _ = reveals.value
        if day.up {
            let toDevelop = photos.hasPhotos ? waiting : 0
            Button {
                triggerSomeVibration(type: .light)
                if toDevelop > 0 { MemoriesPresenter.shared.open = true } else { JourneyPresenter.shared.open = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: toDevelop > 0 ? "photo.stack" : "point.bottomleft.forward.to.point.topright.scurvepath")
                        .font(.system(size: 12, weight: .light))
                        // A photo waiting for its tap: the same thin sage ring the fifths will wear (owner).
                        .overlay(alignment: .topTrailing) {
                            if toDevelop > 0 {
                                // Grey, not sage: no sage on the Salah page (owner, 2026-10-15).
                                Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8).offset(x: 4, y: -3)
                            }
                        }
                    Text(toDevelop > 0 ? "\(toDevelop) photo\(toDevelop == 1 ? "" : "s") to develop" : "Journey")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                }
                // In the background, never competing with the list (owner): tertiary type, light, a faint lift.
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).opacity(0.6))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The day card is Journey's alone now (owner, 2026-10-16: "the salah stays simple"); Journey's flip pill
            // still sits where this link does — read once the day page is up and settled (closed, the footer is off
            // the bottom of the screen).
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { f in
                if day.lifted, f.maxY <= UIScreen.main.bounds.height, day.salahPill != f { day.salahPill = f }
            }
            .padding(.bottom, 12)   // the same air above the bar as "N done"
            .transition(.opacity)
            .animation(.easeOut(duration: CircleMotion.quick), value: toDevelop)
        }
    }
}

/// The soft looks' "N done", above the bottom bar (PagerChromeView). The chevron points to where the rows
/// appear: up while folded, down once they're shown (owner: "switch chevron directions for done and hide").
struct SoftDoneFooter: View {
    private var fold = PrayerListFold.shared

    var body: some View {
        if let count = fold.softFooterCount {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(RowMotion.current.animation(springy: CircleMotion.spring)) {
                    fold.showDone.toggle()
                }
                TourRuntime.shared.event(.foldTapped)   // the user's tap, not a fold the app made
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
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("doneFold", $0) }
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
        case .card, .well, .pills, .quiet, .timeline, .now, .dayNow, .nowLeads, .prayedAt, .prayedOnTap, .raised:
            content.frame(width: 290)   // the card goes round the rows only (SalahLookCard), "N done" under it
        }
    }
}

/// The prayer list's insets inside its card for the look: the raised list's band reaches the card's edges, the others sit
/// 16 in and 12 down. Shared by the Salah list and Journey's day card, so the two cards are one size in every look.
struct SalahListInsets: ViewModifier {
    @Environment(\.circleTheme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, theme.list == .raised ? 0 : 16)
            .padding(.vertical, theme.list == .raised ? 0 : 12)
    }
}

/// The soft looks' card round the prayer rows (inside TodaysPrayerListView, so "N done" sits outside it).
struct SalahLookCard: ViewModifier {
    /// All five marked (the day's page): the well rises into a raised card (NeuLiftCard), only then.
    var raised = false
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: 24, style: .continuous)
        switch theme.list {
        case .card:
            content.clipShape(card).background(NeuRaised(shape: card, radius: 14, offset: 7))
        case .raised:
            // One raised card, its corners as round as the band (half a row), the rows edge to edge inside it.
            let round = RoundedRectangle(cornerRadius: SalahLook.raisedRowHeight / 2, style: .circular)
            content.clipShape(round).background(NeuRaised(shape: round))
        case .well, .timeline, .now, .dayNow, .nowLeads, .prayedAt, .prayedOnTap:   // Sami's looks sit in the public look's well
            content.clipShape(card)
                .background(NeuLiftCard(shape: card, lift: raised ? 1 : 0))
                .scaleEffect(raised && !reduceMotion ? 1.012 : 1)
                .animation(reduceMotion ? .easeOut(duration: CircleMotion.quick) : CircleMotion.dayCardLift, value: raised)
        case .today, .pills, .quiet:
            content
        }
    }
}

/// Top right on the Salah page (DEBUG): the main build's look first — ticked while it's what's showing, one tap back to it
/// — and the old looks tucked under Explore, grouped, for inspiration (owner, 2026-10-14: "whatever we use as defaults in
/// our main build, make that the default and put them tucked away … organize them nicer … I just keep it for inspo").
struct SalahLookSwitcher: View {
    @AppStorage(SalahLook.key) private var lookRaw = CircleTheme.standard.list.rawValue
    @AppStorage(SalahLook.softRingKey) private var softRing = CircleTheme.standard.softRing
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.standard.rawValue
    @AppStorage(SalahPalette.key) private var paletteRaw = CircleTheme.standard.palette.rawValue
    @AppStorage(SalahLook.linesKey) private var lines = CircleTheme.standard.lines
    @AppStorage(SessionOpening.key) private var openingRaw = SessionOpening.sink.rawValue
    @AppStorage(SalahSheetDrag.key) private var sheetFollows = SalahSheetDrag.defaultOn
    @AppStorage(EditorBoxFill.key) private var boxFillRaw = EditorBoxFill.standard.rawValue

    /// Everything as the main build (TestFlight / App Store) has it.
    private var isMainLook: Bool {
        lookRaw == CircleTheme.standard.list.rawValue && softRing == CircleTheme.standard.softRing
            && paletteRaw == CircleTheme.standard.palette.rawValue && lines == CircleTheme.standard.lines
            && motionRaw == RowMotion.standard.rawValue && openingRaw == SessionOpening.sink.rawValue
            && sheetFollows == SalahSheetDrag.defaultOn
    }
    private func useMainLook() {
        lookRaw = CircleTheme.standard.list.rawValue
        softRing = CircleTheme.standard.softRing
        paletteRaw = CircleTheme.standard.palette.rawValue
        lines = CircleTheme.standard.lines
        motionRaw = RowMotion.standard.rawValue
        openingRaw = SessionOpening.sink.rawValue
        sheetFollows = SalahSheetDrag.defaultOn
    }

    var body: some View {
        Menu {
            Button { useMainLook() } label: {
                Label("Main build's look", systemImage: isMainLook ? "checkmark" : "arrow.uturn.backward")
            }
            // Out in the open while he picks (owner, 2026-10-20: "put it as an option in the top right palette thing for me
            // and ill decide after looking"): the prayer editor's boxes, see-through (Frank) or solid grey (Zoe).
            Picker("Editor boxes", selection: $boxFillRaw) {
                ForEach(EditorBoxFill.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            Menu {
                Section("List") {
                    Menu("Prayer list") {
                        Picker("Main and Sami's", selection: $lookRaw) {
                            ForEach(SalahLook.sami) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                        Picker("Earlier looks", selection: $lookRaw) {
                            ForEach(SalahLook.originals) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.inline)
                    }
                    Toggle("Lines between prayers", isOn: $lines)
                }
                Section("Ring & colours") {
                    Toggle("Soft ring", isOn: $softRing)
                    Picker("Colours", selection: $paletteRaw) {
                        ForEach(SalahPalette.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                }
                Section("Motion") {
                    Picker("Rows come and go", selection: $motionRaw) {
                        ForEach(RowMotion.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Picker("Zikr ring opens", selection: $openingRaw) {
                        ForEach(SessionOpening.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    // The Salah list's drag (owner's names): it follows the finger, or the swipe finishes and it pops.
                    Picker("Salah list drag", selection: $sheetFollows) {
                        Text("Vertical live dragging").tag(true)
                        Text("Gesture completion drag").tag(false)
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                Label("Explore", systemImage: "sparkles")
            }
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
    @Environment(SharedStateClass.self) private var sharedState
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
        // A script, each step awaited: the menu gone, the Salah page, the list up, its done rows out, then the cascade
        // (a chain of asyncAfters guessed each step's length — audit F).
        Task { @MainActor in
            guard await CircleGate.pause(CircleMotion.menuAwayDuration) else { return }
            await sharedState.navigate(to: .main)
            await CircleMotion.animate(CircleMotion.page) { sharedState.navPosition = .bottom }
            await CircleMotion.animate(RowMotion.current.animation(springy: CircleMotion.spring)) {
                PrayerListFold.shared.showDone = true
            }
            NotificationCenter.default.post(name: .perfectDay, object: true)
        }
    }

    /// After the Play menu has closed, so the animation plays on a clear page. A SwiftUI menu says nothing when it has
    /// gone, so this is the one named wait.
    private func after(_ go: @escaping () -> Void) {
        Task { @MainActor in
            guard await CircleGate.pause(CircleMotion.menuAwayDuration) else { return }
            go()
        }
    }

    private func post(_ name: Notification.Name, _ object: Any? = nil) {
        after { NotificationCenter.default.post(name: name, object: object) }
    }
}

/// The top bar's icon look (the ☰'s grey, light weight).
struct ChromeIcon: View {
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
