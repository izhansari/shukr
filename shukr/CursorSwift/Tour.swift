import SwiftUI
import SwiftData
import TipKit

/// The first-run tour on the live app (owner, ask onboarding-tour: "a little gentle onboarding once users get past set up
/// … not stand alone sheets, like acc interactive on the real app"; Ben's brief board/brief-frank-onboarding-tour.md).
/// Coach marks: a dim with a clear cut-out round the real control, one line beside it, the step ending on the real action.
/// The dim takes no touches, so the control under the cut-out (and everything else) works as usual.
enum TourStep: String, CaseIterable, Identifiable {
    // The tour itself, four cards (tour v2, Izhan's spec 2026-10-05, board/brief-tour-v2.md): each card is one topic —
    // learn it where it lives, then try it — and the one bubble drifts from card to card, turning its page.
    case circle, list, zikr, settings
    // Before them: a welcome, and how the tour goes (owner: "something Muslim and friendly").
    case intro
    // After the tour: the first real mark's celebration, the post-salah pill's card, the map hint.
    case celebrate, firstPill, map, hintMark
    var id: String { rawValue }

    /// The four cards, in order.
    static let cards: [TourStep] = [.circle, .list, .zikr, .settings]
    var isCard: Bool { Self.cards.contains(self) }
    /// A page of the tour itself: the welcome or a card (not a post-tour step).
    var isTourPage: Bool { self == .intro || isCard }
    /// A card's chapter title, led by its number in the bubble (owner).
    var chapterTitle: String {
        switch self {
        case .circle: TourCopy.Circle.title
        case .list: TourCopy.List.title
        case .zikr: TourCopy.Zikr.title
        case .settings: TourCopy.Settings.title
        default: ""
        }
    }

    /// The post-tour steps' words (the cards' own are TourRuntime.page).
    var headline: String {
        switch self {
        case .celebrate: TourCopy.AfterTour.celebrateTitle
        case .firstPill: TourCopy.AfterTour.pillTitle
        case .map: TourCopy.AfterTour.mapTitle
        case .hintMark: TourCopy.AfterTour.markTitle
        default: ""
        }
    }
    var subline: String {
        switch self {
        case .celebrate: TourCopy.AfterTour.celebrateLine
        case .firstPill: TourCopy.AfterTour.pillLine
        case .map: TourCopy.AfterTour.mapLine
        case .hintMark: TourCopy.AfterTour.markLine
        default: ""
        }
    }
    var symbol: String {
        switch self {
        case .circle, .hintMark, .firstPill: "hand.tap"
        case .intro: "moon.stars"
        case .list: "list.bullet"
        case .zikr: "circle.hexagongrid"
        case .settings: "gearshape"
        case .celebrate: "sparkles"
        case .map: "map"
        }
    }
    /// The measured frame a post-tour step points at.
    var target: String? {
        switch self {
        case .celebrate, .map: "circle"
        case .hintMark: "prayerDot."
        case .firstPill: "pill"
        default: nil
        }
    }
    var roundHole: Bool { self != .list }
    /// The post-tour steps' to-dos and insights (the cards' own are TourRuntime.page).
    var tasks: [String] {
        switch self {
        case .firstPill: [TourCopy.AfterTour.pillTodo]
        case .map: [TourCopy.AfterTour.mapTodo]
        default: []
        }
    }
    var insight: (String, String)? {
        switch self {
        case .firstPill: (TourCopy.AfterTour.pillDoneTitle, TourCopy.AfterTour.pillDoneLine)
        default: nil
        }
    }
    var words: String { headline + ". " + subline }
    var place: (Int, Int)? { nil }
}

/// Where a card is: learn it first, then try it (the circle and the list), or go there first, then learn it (Zikr,
/// Settings); Settings ends on its last line, the tour's own row.
/// Where a chapter is: `go` (get to its page), `learn` (its first "what it's for" step), `learnMore` (its second: the
/// circle's colours with the demo ring, the list's what you can do), `tryIt` (the to-dos), `last` (Settings' closing words).
enum TourPhase: Equatable { case go, learn, learnMore, tryIt, last, deep }

/// One part of a step's "what it's for": a short lead and its list (owner: glanceable, never a paragraph).
struct TourBlock: Equatable {
    var lead: String? = nil
    let items: [String]
    /// The ring's colours: each item gets its colour's dot, lit as the demo's ring reaches it.
    var colours = false
    /// Numbered instead of dotted (the welcome's four chapters).
    var numbered = false
    /// "situation|what happens" each: the two in columns with an arrow between (the circle's "what it shows").
    var pairs = false
}

/// One step of a chapter (owner: steps that collapse as you go): open while it's the current one, then folded to a ✓
/// line that opens it again.
struct TourSection: Identifiable {
    let id: String
    var title: String? = nil
    var done = false
    var lead: String? = nil
    var blocks: [TourBlock] = []
    var tasks: [String] = []
    var note: String? = nil
    /// The note as a quiet footnote (the welcome's last line, under its list).
    var quietNote = false
    /// "2 of 3" beside its one to-do (the counting session's tips).
    var progress: (Int, Int)? = nil
    /// Something to open again once it's folded.
    var peekable: Bool { !blocks.isEmpty || !tasks.isEmpty }
}

/// What the one bubble says right now: built by TourRuntime from the card and its phase. A card is a chapter (owner):
/// its index and title, a ring for how far through it you are, and its steps; a post-tour step is a plain headline,
/// line and to-dos.
struct TourPage {
    var headline: String
    var subline: String? = nil
    /// The chapter's number (cards only).
    var index: Int? = nil
    /// How far through the chapter, 0…1.
    var progress: Double = 0
    var sections: [TourSection] = []
    /// A post-tour step's to-dos (a chapter's are in its sections); `locked` ones wait (greyed) until the ones before.
    var tasks: [String] = []
    var locked: Set<Int> = []
    /// A post-tour step's closing line.
    var insight: String? = nil
    /// The main button (nil: none — the step ends on an action).
    var primary: String? = nil
    /// A quiet second button ("Play again").
    var secondary: String? = nil
    /// The to-dos, wherever they are (a chapter's step or the post-tour page).
    var todo: [String] { sections.first(where: { !$0.tasks.isEmpty })?.tasks ?? tasks }
}

/// Where the tour's targets are on screen, reported by the views themselves (global frames, written only on change).
@MainActor @Observable final class TourTargets {
    static let shared = TourTargets()
    private(set) var frames: [String: CGRect] = [:]
    /// The list row the tour's last row tap was on (its change glows — tour v2).
    @ObservationIgnored var lastTappedRow: String?
    func set(_ key: String, _ frame: CGRect) {
        guard frame.width > 0, frames[key] != frame else { return }
        frames[key] = frame
    }
    func frame(_ key: String) -> CGRect? {
        key == "circle" ? (settledCircle ?? WelcomeTarget.circleFrame) : frames[key]
    }
    /// The circle's frame once it has held still a moment: the circle's measured frame blinked smaller for 3 frames as
    /// the ring turned yellow, and the card hung under it jumped up and back (owner's recording, 2026-10-05).
    private(set) var settledCircle: CGRect?
    @ObservationIgnored private var circleSettle: Task<Void, Never>?
    func circleMoved(_ frame: CGRect) {
        circleSettle?.cancel()
        if settledCircle == nil { settledCircle = frame; return }
        circleSettle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled, settledCircle != frame else { return }
            settledCircle = frame
        }
    }
}

/// The tour's one bubble over the live app (tour v2): where its target is, in this view's space, and the callout.
/// Touches pass through to the app; the input guard (TourLayer) decides which reach it.
struct TourOverlay: View {
    let step: TourStep
    let page: TourPage
    var target: String? = nil
    var place: (Int, Int)? = nil
    var ticked: Set<Int> = []
    var lit: Set<Int> = []
    /// A finished step opened again (its id).
    var openSection: String? = nil
    /// The touch to show (global).
    var hint: TouchHintSpec? = nil
    /// The bubble's bottom here (global y), above what it talks about (the list — audit J); nil: by the target.
    var aboveY: CGFloat? = nil
    var showsBack = false
    /// What just changed (global), glowing a moment; `flashes` counts the glows.
    var flash: CGRect? = nil
    var flashes = 0
    /// Touches the tour didn't let through: the target pulses.
    var nudges = 0
    /// The qibla line's quiet "skip" (a compass that won't settle).
    var qiblaSkip = false
    /// The page turned forward (the next card in from the right) or back.
    var forward = true
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
    var onBack: () -> Void = {}
    var onToggle: (String) -> Void = { _ in }
    var onSkipQibla: () -> Void = {}
    private var targets: TourTargets { TourTargets.shared }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let hole: CGRect? = target.flatMap { targets.frame($0) }.map {
                Self.local($0, origin).insetBy(dx: step.roundHole ? -10 : -14, dy: step.roundHole ? -10 : -6)
            }
            TourCallout(step: step, page: page, hole: hole, size: geo.size, place: place, ticked: ticked, lit: lit,
                        openSection: openSection,
                        hint: hint.map { TouchHintSpec(kind: $0.kind, at: CGPoint(x: $0.at.x - origin.x, y: $0.at.y - origin.y)) },
                        aboveY: aboveY.map { $0 - origin.y }, showsBack: showsBack,
                        flash: flash.map { Self.local($0, origin) }, flashes: flashes, nudges: nudges, qiblaSkip: qiblaSkip,
                        forward: forward, onPrimary: onPrimary, onSecondary: onSecondary, onBack: onBack,
                        onToggle: onToggle, onSkipQibla: onSkipQibla)
        }
        .ignoresSafeArea()
    }

    private static func local(_ r: CGRect, _ origin: CGPoint) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
}

#if DEBUG
/// DEBUG launch arguments for the tour: `-tourStart`, `-tourSkipInvite`, `-tourFrom <card>[:learn|learnMore|tryIt|go|last]`,
/// `-tourWidgetWrote`, `-tourAwayAfter`; `-demoTourHint` / `-demoTourTip` for the old pictures.
struct TourDemoLayer: View {
    @Environment(SharedStateClass.self) private var sharedState
    @EnvironmentObject private var viewModel: PrayerViewModel

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
        .task {
            // `-armFirstMark YES`: the next real mark is celebrated (as after the first-run setup) — the pictures.
            if UserDefaults.standard.bool(forKey: "armFirstMark") {
                UserDefaults.standard.set(true, forKey: TourRuntime.celebrateArmedKey)
            }
            // `-tourStart [-tourStartAfter s]`: the real tour, as Settings → Show me around again starts it.
            // Once per launch: this view comes back after every pushed page (it restarted the tour under History).
            if ProcessInfo.processInfo.arguments.contains("-tourStart"), !TourDebugOnce.started {
                TourDebugOnce.started = true
                let wait = UserDefaults.standard.double(forKey: "tourStartAfter")
                try? await Task.sleep(for: .seconds(wait > 0 ? wait : 3))
                NotificationCenter.default.post(name: TourRuntime.start, object: nil)
                // `-tourFrom <card>[:<phase>]`: straight to that card (and phase), its practice state set as on a Back.
                let parts = (UserDefaults.standard.string(forKey: "tourFrom") ?? "").split(separator: ":").map(String.init)
                let from = parts.first.flatMap(TourStep.init(rawValue:))
                let phase: TourPhase? = parts.count > 1 ? ["learn": .learn, "learnMore": .learnMore, "colours": .learnMore, "tryIt": .tryIt, "go": .go, "last": .last][parts[1]] : nil
                if let from {
                    try? await Task.sleep(for: .seconds(1.5))
                    TourRuntime.shared.debugJump(to: from, phase: phase)
                }
                // `-tourWidgetWrote YES`: as if a widget / banner had marked a prayer (the next activation reconciles):
                // today's real score must stay as it was (Bradley's review).
                if UserDefaults.standard.bool(forKey: "tourWidgetWrote") {
                    try? await Task.sleep(for: .seconds(3))
                    UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: SharedStore.widgetWroteStoreKey)
                }
                // `-tourAwayAfter s`: s seconds later the page is taken to Zikr, as a widget would (Back to the tour);
                // `-tourAwayTo settings` takes it to Settings instead (the settings step without a tap).
                let away = UserDefaults.standard.double(forKey: "tourAwayAfter")
                if away > 0 {
                    try? await Task.sleep(for: .seconds(away))
                    sharedState.go(to: UserDefaults.standard.string(forKey: "tourAwayTo") == "settings" ? .settings : .zikr)
                }
                return
            }
            if TourHintDemo.hint != nil || TourHintDemo.tip != nil {
                try? await Task.sleep(for: .seconds(1.5))
                TourHintDemo.start(sharedState)
                return
            }
        }
    }
}
#endif

/// The tour without a dim (Bradley's and Sami's direction, after the owner's "don't love the style"): the app says it
/// in its own words, where it already speaks — the circle's time line, a line over the chevron, the top bar's title, the
/// current row's time — for the one step, gone on the real action. Read by those views; nil = their usual words.
@MainActor @Observable final class TourHints {
    static let shared = TourHints()
    var circleLine: String?
    var chevronLine: String?
    var titleLine: String?
    var markLine: String?
}

/// Apple's own tips (TipKit), the native alternative: a small popover at the real control, no dim.
struct FlipCircleTip: Tip {
    var title: Text { Text("Tap the circle") }
    var message: Text? { Text("It flips between when this prayer ends and how long is left.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
struct SwipeToZikrTip: Tip {
    var title: Text { Text("Swipe right for your zikr") }
    var message: Text? { Text("Your daily tasks and the counter live there.") }
    var image: Image? { Image(systemName: "arrow.right") }
}

#if DEBUG
/// A TipKit popover on a view, for the pictures only.
struct DemoTip<T: Tip>: ViewModifier {
    let tip: T
    let on: Bool
    var edge: Edge = .bottom
    func body(content: Content) -> some View {
        if on { content.popoverTip(tip, arrowEdge: edge) } else { content }
    }
}

/// `-demoTourHint circle|list|zikr|mark` (the words in place) and `-demoTourTip circle|zikr` (TipKit): pictures.
enum TourHintDemo {
    static var hint: String? { UserDefaults.standard.string(forKey: "demoTourHint") }
    static var tip: String? { UserDefaults.standard.string(forKey: "demoTourTip") }
    @MainActor static func start(_ sharedState: SharedStateClass) {
        if tip != nil {
            try? Tips.resetDatastore()
            Tips.showAllTipsForTesting()
            try? Tips.configure()
        }
        switch hint {
        case "circle": TourHints.shared.circleLine = "tap to see time left"
        case "list": TourHints.shared.chevronLine = "swipe up for today's prayers"
        case "zikr": TourHints.shared.titleLine = "swipe right for your zikr"
        case "mark":
            TourHints.shared.markLine = "tap the dot to mark"
            sharedState.navPosition = .bottom
        default: break
        }
    }
}
#endif

/// Places the tour's bubble: measures it, hangs it from `edge` (its top when `below`, else its bottom; centred on
/// `fallbackY` without one), centred across, and keeps it clear of the status bar and the home indicator.
private struct TourBubblePlacement: Layout {
    let edge: CGFloat?
    let below: Bool
    let fallbackY: CGFloat
    /// What the step asks you to touch (this view's space): the bubble never lands on it — kept on screen, a tall
    /// bubble (the largest text) moves to its other side instead (Sami: card 9 covered Fajr's row at AX XXXL).
    var avoid: CGRect? = nil
    /// The highest the bubble goes: under Skip tour during the tour (Sami: card 9's payoff covered it).
    var topLimit: CGFloat = 64
    /// It may move to its target's other side when it doesn't fit; never while a finished step is open again — it
    /// grows where it is (owner: opening Try it sent it from over the circle to under it).
    var mayFlip = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let size = bubble.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let h = size.height
        let wanted = edge.map { below ? $0 + h / 2 : $0 - h / 2 } ?? fallbackY
        // Never off the screen, nor under the status bar or the home indicator (a tall bubble, large text, a small phone).
        let top = topLimit + h / 2, bottom = bounds.height - 24 - h / 2
        func clamp(_ y: CGFloat) -> CGFloat { bottom > top ? min(max(y, top), bottom) : bounds.height / 2 }
        var y = clamp(wanted)
        if mayFlip, let avoid, avoid.intersects(CGRect(x: 0, y: y - h / 2, width: bounds.width, height: h)) {
            // Its other side, if that's clear: under the target, else over it.
            let options = [avoid.maxY + 14 + h / 2, avoid.minY - 14 - h / 2].map(clamp)
            if let clear = options.first(where: { !avoid.intersects(CGRect(x: 0, y: $0 - h / 2, width: bounds.width, height: h)) }) {
                y = clear
            }
        }
        bubble.place(at: CGPoint(x: bounds.midX, y: bounds.minY + y), anchor: .center,
                     proposal: ProposedViewSize(width: size.width, height: h))
    }
}

/// The tour's bubble (tour v2): one bubble for the whole tour. It drifts to the card's place (its position, tail and
/// spotlight animate), turns its page inside itself between cards (the old words out to one side, the new in from the
/// other), and grows or changes in place within a card. A light spotlight in the page's own colour, the thumbprint
/// beside the thing to touch, a glow on what just changed, a pulse on the target when a touch wasn't let through.
struct TourCallout: View {
    let step: TourStep
    let page: TourPage
    let hole: CGRect?
    let size: CGSize
    var place: (Int, Int)? = nil
    var ticked: Set<Int> = []
    var lit: Set<Int> = []
    var openSection: String? = nil
    /// The touch to show, in this view's space.
    var hint: TouchHintSpec? = nil
    /// The bubble's bottom here (this view's space): above the list on its card (audit J).
    var aboveY: CGFloat? = nil
    var showsBack = false
    var flash: CGRect? = nil
    var flashes = 0
    var nudges = 0
    var qiblaSkip = false
    var forward = true
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
    var onBack: () -> Void = {}
    var onToggle: (String) -> Void = { _ in }
    var onSkipQibla: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @Environment(SharedStateClass.self) private var sharedState
    @State private var shown = false
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// How the bubble drifts between places, and how its page turns.
    static let drift = Animation.smooth(duration: 0.55)

    var body: some View {
        let center = hole.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height * 0.45)
        // Below the control when there's room, else above it — from a fixed allowance, never from the bubble's own
        // measured height (that fed back and spun the main thread — Sami's round D run).
        let below = aboveY == nil && (hole.map { size.height - $0.maxY > 260 } ?? true)
        let width = typeSize >= .xxLarge ? size.width - 32 : min(size.width - 40, 330)
        // The tail points at the control, kept clear of the corners.
        let tail = hole.map { min(max($0.midX - size.width / 2, -(width / 2 - 40)), width / 2 - 40) } ?? 0
        ZStack(alignment: .topLeading) {
            // The spotlight: the page washes out a little away from the control, in the page's own colour (no grey).
            RadialGradient(colors: [.clear, .clear, theme.backdrop.opacity(0.45)],
                           center: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)),
                           startRadius: 0, endRadius: max(size.width, size.height) * 0.75)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
                .animation(Self.drift, value: hole.map { "\(Int($0.midX)),\(Int($0.midY))" } ?? "-")
            // What just changed: a soft glow round it, once (owner: "give attention to the areas being changed").
            if let flash { ChangeGlow(frame: flash, token: flashes).id(flashes) }
            // A touch that wasn't let through: the thing to touch pulses (no buzz — owner).
            // A touch the tour didn't let through: nothing shows (user testing, 2026-10-06 — the pulse round the target
            // read as "tap here"; no buzz either).
            // Where to touch, and how: a grey thumbprint on the thing to touch (user testing: beside it misled).
            if let hint { TouchHint(spec: hint).transition(.opacity) }
            // A step to do: the slim strip at an edge, clear of its target (decision tour-hint-style A); its explanation
            // first, once, as the card with "Got it".
            let key = page.guideKey(step.rawValue)
            let mode = TourGuideMode.of(page, key: key)
            if mode == .strip {
                TourCoachStrip(chapter: page.headline, lead: page.shortLead, todos: page.currentTodos, ticked: ticked, locked: page.locked,
                               progress: page.activeSection?.progress,
                               onDetails: page.explains ? { withAnimation(.smooth(duration: 0.35)) { TourGuideState.shared.again(key) } } : nil,
                               onBack: showsBack ? onBack : nil,
                               extra: qiblaSkip ? (TourCopy.Circle.noCompass, onSkipQibla) : nil)
                    .tourStripPlaced(top: TourStripPlace.top(target: hole, height: size.height, keepBottom: aboveY != nil),
                                     size: size, topInset: typeSize.isAccessibilitySize ? 158 : 112,
                                     bottomInset: sharedState.horizontalPage == .main ? 40 : 104)
                    .opacity(shown ? 1 : 0)
                    .transition(.opacity)
            } else {
            // Measured and placed in one layout pass (`TourBubblePlacement`).
            TourBubblePlacement(edge: bubbleEdge(below: below), below: aboveY != nil ? false : below,
                                // Nothing to point at (Settings' learn): low, clear of what it talks about.
                                // The welcome: dead centre (owner).
                                fallbackY: step == .settings ? size.height : size.height * (step == .intro ? 0.5 : 0.6), avoid: hole,
                                topLimit: typeSize.isAccessibilitySize ? 158 : 112,
                                // A bubble asked to sit above (the circle once marked, the list, the wheel) never flips
                                // under its target — under it covered the swipe up on a 13 Pro Max (owner); it overlaps
                                // the target's top instead.
                                mayFlip: openSection == nil && aboveY == nil) {
                bubble(below: below, tail: tail,
                       page: mode == .cardThenStrip ? page.withGotIt : page,
                       primary: mode == .cardThenStrip ? { withAnimation(.smooth(duration: 0.35)) { TourGuideState.shared.gotIt(key) } } : onPrimary)
                    .frame(width: width)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // taller couldn't clear its target (Sami, AX XXXL)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.96)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            // The drift: the one bubble moves to the card's new place (owner: "visually moves or drifts smoothly").
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.drift,
                       value: "\(hole.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? "-")|\(aboveY.map { Int($0) } ?? -1)|\(below)")
            }
        }
        .task {
            // Reduce Motion (audit C14): the bubble fades in.
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { shown = true }
                return
            }
            // A beat (the last chapter's bubble fading), then this one comes in where it belongs — each chapter.
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
        }
    }

    /// The edge the bubble hangs from: its top when below the control, its bottom when above (nil = no control).
    private func bubbleEdge(below: Bool) -> CGFloat? {
        if let aboveY { return aboveY - 14 }
        guard let hole else { return nil }
        return below ? hole.maxY + 14 : hole.minY - 14
    }

    private func bubble(below: Bool, tail: CGFloat, page: TourPage, primary: @escaping () -> Void) -> some View {
        // The page turns inside the bubble: each card's content is its own view, sliding out one side and in the
        // other (owner: "it pages over inside of the tooltip"); the bubble itself stays.
        ZStack(alignment: .topLeading) {
            TourPageView(step: step, page: page, place: place, ticked: ticked, lit: lit, openSection: openSection,
                         showsBack: showsBack, qiblaSkip: qiblaSkip,
                         onPrimary: primary, onSecondary: onSecondary, onBack: onBack,
                         onToggle: onToggle, onSkipQibla: onSkipQibla)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .padding(16)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .tint(TourInk.green)   // never the system blue
        .accessibilityElement(children: .contain)
        // No tail (owner: "a complete rounded rectangle, no pointy").
        .tourBubble(BubbleShape(tailUp: below, tailOffset: tail, tailScale: 0), look: TourBubbleLook(rawValue: lookRaw) ?? .glass,
                    scheme: scheme, backdrop: theme.backdrop)
    }
}

/// One card's content in the bubble. A chapter (owner): "1  Prayer Circle" with a ring top right for how far through it
/// you are, then its steps — the current one open, the finished ones folded to a ✓ line each (tap to open again). A
/// post-tour step: its symbol, headline, line, to-dos. Then the row of Back · the dots · the buttons.
struct TourPageView: View {
    let step: TourStep
    let page: TourPage
    var place: (Int, Int)?
    var ticked: Set<Int>
    var lit: Set<Int>
    var openSection: String?
    var showsBack: Bool
    var qiblaSkip: Bool
    var onPrimary: () -> Void
    var onSecondary: () -> Void
    var onBack: () -> Void
    var onToggle: (String) -> Void
    var onSkipQibla: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let index = page.index { chapterHeader(index) } else { plainHeader }
            if page.sections.isEmpty {
                plainBody
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // Two or more finished steps fold into one "✓ N done" line (decision tour-bubble-size A: the
                    // bubble was half a tester's screen); a tap lists them again, each still openable.
                    let done = page.sections.filter(\.done)
                    let folded = done.count >= 2 && !showDone && !done.contains { $0.id == openSection }
                    if folded {
                        doneLine(done.count)
                            .transition(.opacity)
                    }
                    ForEach(folded ? page.sections.filter { !$0.done } : page.sections) { section in
                        TourSectionView(section: section, open: openSection == section.id, ticked: ticked,
                                        locked: page.locked, lit: lit) { onToggle(section.id) }
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                                    removal: .opacity))
                    }
                }
                .onChange(of: page.sections.filter(\.done).count) { _, _ in showDone = false }
            }
            if qiblaSkip {
                Button(TourCopy.Circle.noCompass, action: onSkipQibla)
                    .buttonStyle(.plain)
                    .font(.system(.footnote, design: .rounded, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(minHeight: 28)
                    .transition(.opacity)
            }
            // The buttons' row only when there's something in it: an empty one left a 40 pt strip under every to-do.
            if showsBack || page.secondary != nil || page.primary != nil {
            HStack(spacing: 12) {
                if showsBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .padding(.leading, -6)
                }
                // No dots (user testing, 2026-10-06: they confused people) — the chapter's number and ring say where.
                Spacer(minLength: 0)
                if let secondary = page.secondary {
                    Button(secondary, action: onSecondary)
                        .buttonStyle(.plain)
                        .font(.system(.footnote, design: .rounded, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .fixedSize()
                        .transition(.opacity)
                }
                if let primary = page.primary {
                    Button(action: onPrimary) {
                        Text(primary)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Capsule().fill(TourInk.green))
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 32)
            }
        }
        // One text size smaller than the phone's (decision tour-bubble-size A), still following its setting.
        .dynamicTypeSize(Self.oneSmaller(typeSize))
    }

    @State private var showDone = false
    @Environment(\.dynamicTypeSize) private var typeSize

    static func oneSmaller(_ size: DynamicTypeSize) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let i = all.firstIndex(of: size), i > 0 else { return size }
        return all[i - 1]
    }

    /// "✓ 4 done ⌄": the finished steps in one line, in the look of a single ✓ line.
    private func doneLine(_ count: Int) -> some View {
        Button {
            withAnimation(.smooth(duration: CircleMotion.standard)) { showDone = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(TourInk.green)
                Text(TourCopy.doneCount(count))
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
            }
            .font(.system(.footnote, design: .rounded, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.6))
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(TourCopy.doneCount(count)). Show them")
    }

    /// "1  Prayer Circle", the chapter's ring at the right.
    private func chapterHeader(_ index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if index > 0 {   // 0: a chapter on its own (the Zikr Tour from ☰), no number
                Text("\(index)")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Text(page.headline)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TourChapterRing(progress: page.progress)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chapter \(index): \(page.headline), \(Int((page.progress * 100).rounded())) percent done")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var plainHeader: some View {
        if step == .intro {
            // The opening: "Bismillah" the biggest thing in the tour (owner), its symbol beside it, the line under it.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: step.symbol)
                        .font(.system(.title3, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .accessibilityHidden(true)
                    Text(page.headline)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                if let line = page.subline {
                    Text(line)
                        .font(.system(.body, design: .rounded, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 4)
        } else {
            plainStack
        }
    }

    private var plainStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: step.symbol)
                .font(.system(.caption, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.6))
                .accessibilityHidden(true)
            Text(page.headline)
                .font(.system(.body, design: .rounded, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let line = page.subline {
                Text(line)
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var plainBody: some View {
        if !page.tasks.isEmpty {
            TourChecklist(tasks: page.tasks, ticked: ticked, locked: page.locked)
        }
        if let insight = page.insight {
            Text(insight)
                .font(.system(.subheadline, design: .rounded, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .transition(.opacity)
        }
    }
}

/// One step of a chapter. Current: a small label, then its content. Finished: a ✓ line (tap to open it again). The
/// content is one view all along, clipped to a height that animates to nothing, so finishing a step rolls it up into
/// its line (owner: "the current content collapsing into a line item").
struct TourSectionView: View {
    let section: TourSection
    let open: Bool
    let ticked: Set<Int>
    let locked: Set<Int>
    let lit: Set<Int>
    let onToggle: () -> Void

    private var shown: Bool { !section.done || open }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title {
                if section.done {
                    Button(action: onToggle) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TourInk.green)
                            Text(title)
                            if section.peekable {
                                Image(systemName: "chevron.down")
                                    .font(.system(.caption2, weight: .semibold))
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                        }
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .frame(minHeight: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(section.peekable)   // not .disabled: that greyed the line next to the others
                    .accessibilityLabel(section.peekable ? (open ? "Hide: \(title)" : "Show again: \(title)") : "Done: \(title)")
                    .transition(.opacity.animation(.easeOut(duration: CircleMotion.quick).delay(0.15)))
                } else {
                    Text(title.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                }
            }
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: shown ? nil : 0, alignment: .top)
                .clipped()
                .opacity(shown ? 1 : 0)
                .padding(.top, shown ? 0 : -6)   // no gap left under the line
                .accessibilityHidden(!shown)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lead = section.lead {
                Text(lead)
                    .font(.system(.subheadline, design: .rounded, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !section.blocks.isEmpty {
                TourLearnBlocks(blocks: section.blocks, lit: section.done ? Set(0..<3) : lit)
            }
            if !section.tasks.isEmpty {
                TourChecklist(tasks: section.tasks, ticked: section.done ? Set(section.tasks.indices) : ticked,
                              locked: section.done ? [] : locked, progress: section.done ? nil : section.progress)
            }
            if let note = section.note {
                Text(note)
                    .font(.system(section.quietNote ? .footnote : .subheadline, design: .rounded, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(section.quietNote ? 0.6 : 1))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, section.quietNote ? 4 : 0)
            }
        }
    }
}

/// How far through the chapter: a small ring top right of the bubble (owner).
struct TourChapterRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(TourInk.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)   // nothing yet: the track alone
            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TourInk.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
        .animation(.smooth(duration: CircleMotion.slow), value: progress)
        .accessibilityHidden(true)
    }
}

/// A card's "what it's for": each block a lead, then its short list (the colours with their dots).
struct TourLearnBlocks: View {
    let blocks: [TourBlock]
    let lit: Set<Int>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    if let lead = blocks[i].lead {
                        Text(lead)
                            .font(.system(.subheadline, design: .rounded, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if blocks[i].colours {
                        TourColorKey(notes: blocks[i].items, lit: lit, vertical: true)
                    } else if blocks[i].pairs {
                        TourPairs(lines: blocks[i].items)
                    } else {
                        TourBullets(lines: blocks[i].items, numbered: blocks[i].numbered)
                    }
                }
            }
        }
    }
}

/// The "what it's for" lines: a small dot each.
struct TourBullets: View {
    let lines: [String]
    var small = false
    /// The welcome's chapters: "Title|subtitle" each, numbered, the title as a title and the words under it.
    var numbered = false
    var body: some View {
        VStack(alignment: .leading, spacing: numbered ? 10 : (small ? 4 : 6)) {
            ForEach(lines.indices, id: \.self) { i in
                if numbered { chapterLine(i) } else { bullet(i) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bullet(_ i: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color.primary.opacity(0.3)).frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                .frame(width: 15)
            Text(lines[i])
                .font(.system(small ? .footnote : .subheadline, design: .rounded, weight: .light))
                .foregroundStyle(Color.primary.opacity(small ? 0.6 : 0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "1  Prayer Circle" in the chapters' own title type, its words under it as a subtitle (owner).
    private func chapterLine(_ i: Int) -> some View {
        let parts = lines[i].split(separator: "|", maxSplits: 1).map(String.init)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Under "Bismillah": the chapter a step down (callout, medium), its words a step further (footnote, light).
            Text("\(i + 1)")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.4))
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(parts[0])
                    .font(.system(.callout, design: .rounded, weight: .medium))
                if parts.count > 1 {
                    Text(parts[1])
                        .font(.system(.footnote, design: .rounded, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
        }
    }
}

/// The ring's colours as one compact row of keys, each lighting (green dot, full words) as the demo's ring reaches it.
struct TourColorKey: View {
    let notes: [String]
    let lit: Set<Int>
    /// One under another, like the card's other lists (the circle's learn page); else side by side.
    var vertical = false
    private static let colors: [Color] = [PrayerScoring.color(for: 1), PrayerScoring.color(for: 0.9), PrayerScoring.color(for: 0.7)]
    var body: some View {
        if vertical {
            // Laid out like TourBullets: the dot in the bullet's column.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes.indices, id: \.self) { i in
                    let on = lit.contains(i)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Self.colors[min(i, 2)].opacity(on ? 1 : 0.6))
                            .frame(width: on ? 9 : 7, height: on ? 9 : 7)
                            .frame(width: 15)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        Text(notes[i])
                            .font(.system(.subheadline, design: .rounded, weight: on ? .medium : .light))
                            .foregroundStyle(Color.primary.opacity(on ? 0.95 : 0.75))
                    }
                    .animation(.snappy(duration: 0.3), value: on)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(i))
                }
            }
        } else {
            // Two lines at most: the three keys side by side, wrapping only at large text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { keys }
                VStack(alignment: .leading, spacing: 4) { keys }
            }
        }
    }
    private func label(_ i: Int) -> String { "\(["Green", "Yellow", "Red"][min(i, 2)]): \(notes[i])" }
    @ViewBuilder private var keys: some View {
        ForEach(notes.indices, id: \.self) { i in
            let on = lit.contains(i)
            HStack(spacing: 5) {
                Circle().fill(Self.colors[min(i, 2)].opacity(on ? 1 : 0.45)).frame(width: on ? 8 : 7, height: on ? 8 : 7)
                Text(notes[i])
                    .font(.system(.footnote, design: .rounded, weight: on ? .medium : .light))
                    .foregroundStyle(Color.primary.opacity(on ? 0.9 : 0.45))
                    .fixedSize()
            }
            .animation(.snappy(duration: 0.3), value: on)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(i))
        }
    }
}

/// The tour's place: a dot per card, the current one a longer oval (owner).
struct TourDots: View {
    let current: Int
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.primary.opacity(0.6) : Color.primary.opacity(i < current ? 0.3 : 0.15))
                    .frame(width: i == current ? 16 : 5, height: 5)
            }
        }
        .animation(.smooth(duration: CircleMotion.standard), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(count)")
    }
}

/// What just changed glows a moment: a soft green outline that breathes in and out once.
struct ChangeGlow: View {
    let frame: CGRect
    let token: Int
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: min(frame.height, frame.width) / 2, style: .continuous)
            .stroke(TourInk.green.opacity(on ? 0.55 : 0), lineWidth: 2)
            .shadow(color: TourInk.green.opacity(on ? 0.45 : 0), radius: 10)
            .frame(width: frame.width + 12, height: frame.height + 12)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .task {
                withAnimation(.easeOut(duration: 0.25)) { on = true }
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(.easeIn(duration: 0.5)) { on = false }
            }
    }
}

/// The target pulses once when a touch elsewhere wasn't let through ("over here").
struct TargetPulse: View {
    let frame: CGRect
    let round: Bool
    @State private var go = false
    var body: some View {
        Group {
            if round {
                let d = max(frame.width, frame.height)
                Circle().stroke(Color.primary.opacity(go ? 0 : 0.35), lineWidth: 2)
                    .frame(width: d, height: d)
                    .scaleEffect(go ? 1.15 : 1)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(go ? 0 : 0.35), lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .scaleEffect(go ? 1.05 : 1)
            }
        }
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { go = true } }
    }
}

/// The tip's material (owner: "the tool tip is a little hard to see… maybe we make it liquid glass-y? or something that
/// just doesn't look the same material as our soft ring material"): glass (the default), ink (the opposite of the
/// page's look), or the old soft pebble. `-tourBubbleLook glass|ink|soft` for the pictures.
enum TourBubbleLook: String { case glass, ink, soft }

extension View {
    @ViewBuilder
    func tourBubble<S: Shape>(_ shape: S, look: TourBubbleLook, scheme: ColorScheme, backdrop: Color) -> some View {
        switch look {
        case .glass:
            // Frosted (owner, 2026-10-06: "at least turn it frosted if we cant do glass"): iOS 26's glassEffect drew
            // these opaque, a solid slab over half the screen; the thin material lets the page show through, blurred.
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 14, y: 6)
        case .ink:
            // The page's opposite: dark on a light page, light on a dark one; the words follow.
            self.environment(\.colorScheme, scheme == .dark ? .light : .dark)
                .background(shape.fill(scheme == .dark ? Color(white: 0.95) : Color(white: 0.14))
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 6))
        case .soft:
            // The old pebble in the page's own colour, raised with the app's shadows.
            self.background(shape.fill(backdrop)
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.14), radius: 12, x: 5, y: 7)
                .shadow(color: .white.opacity(scheme == .dark ? 0.06 : 0.9), radius: 8, x: -4, y: -4))
        }
    }
}

/// The tour's colours: the prayer ring's green (owner: "our green color - not the sage. but not too much of it"): full
/// for the ✓ and Next; faint (0.45) for the ring round a control, so it never reads as a scored prayer's ring.
enum TourInk {
    static let green = Color.green
    /// The tip's material (TourBubbleLook).
    static let lookKey = "tourBubbleLook"
}

/// A step's to-dos: an empty ring each, filled with a green ✓ the moment its action happens; the words go quiet once done.
struct TourChecklist: View {
    let tasks: [String]
    let ticked: Set<Int>
    /// To-dos that wait on the ones before them: greyed, a dashed ring (owner: "graying it out until the previous one is
    /// satisfied"), brightening when they open.
    var locked: Set<Int> = []
    /// The drag tip's strokes, beside its one to-do ("2 of 3").
    var progress: (Int, Int)? = nil
    /// Notes: a bullet each, lit (green, the words full) as it happens; nothing to tick.
    var notes: [String] = []
    var lit: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(tasks.indices, id: \.self) { i in
                let done = ticked.contains(i)
                let waiting = locked.contains(i) && !done
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : (waiting ? "circle.dashed" : "circle"))
                        .font(.system(.subheadline, weight: .regular))
                        .foregroundStyle(done ? TourInk.green : Color.primary.opacity(0.35))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: reduceMotion ? false : done)
                    Text(tasks[i])
                        .font(.system(.subheadline, design: .rounded, weight: .regular))
                        // Done stays readable on glass (Sami: only the strike line showed).
                        .foregroundStyle(done ? Color.primary.opacity(0.5) : Color.primary)
                        .strikethrough(done, color: .secondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress, !done {
                        Text("\(progress.0) of \(progress.1)")
                            .font(.system(.footnote, design: .rounded, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(0.55))   // not .secondary: lost on the glass
                            .contentTransition(.numericText())
                    }
                }
                .opacity(waiting ? 0.38 : 1)
                .animation(.snappy(duration: 0.3), value: done)
                .animation(.easeOut(duration: CircleMotion.standard), value: waiting)
                // VoiceOver reads each to-do with its state (audit C15).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(i, done: done, waiting: waiting))
            }
            ForEach(notes.indices, id: \.self) { i in
                let on = lit.contains(i)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(on ? TourInk.green : Color.primary.opacity(0.25))
                        .frame(width: 7, height: 7)
                        .frame(width: 15)   // under the to-dos' rings
                        .scaleEffect(on && !reduceMotion ? 1.15 : 1)
                    Text(notes[i])
                        .font(.system(.subheadline, design: .rounded, weight: .regular))
                        .foregroundStyle(on ? Color.primary : Color.primary.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.snappy(duration: 0.3), value: on)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notes[i])
            }
        }
    }
}

extension TourChecklist {
    /// VoiceOver's words for a to-do: its state, its words, the drag tip's count.
    func label(_ i: Int, done: Bool, waiting: Bool) -> String {
        let state = done ? "Done: " : (waiting ? "Later: " : "To do: ")
        var count = ""
        if let progress, !done { count = ", \(progress.0) of \(progress.1)" }
        return state + tasks[i] + count
    }
}

/// A rounded bubble with a soft tail at the top or bottom (no hard triangle: the tail's sides are curves), `tailOffset`
/// from the centre.
struct BubbleShape: Shape {
    var tailUp: Bool
    var tailOffset: CGFloat = 0
    /// 0: no tail (nothing to point at), growing back when there is.
    var tailScale: CGFloat = 1
    /// The tail slides with the bubble's drift (tour v2).
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tailOffset, tailScale) }
        set { tailOffset = newValue.first; tailScale = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22, tw: CGFloat = 30 * tailScale, th: CGFloat = 10 * tailScale
        var p = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        guard tailScale > 0.01 else { return p }
        let mid = rect.midX + tailOffset
        if tailUp {
            p.move(to: CGPoint(x: mid - tw / 2, y: rect.minY + 1))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.minY - th), control: CGPoint(x: mid - tw / 6, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: mid + tw / 2, y: rect.minY + 1), control: CGPoint(x: mid + tw / 6, y: rect.minY))
            p.closeSubpath()
        } else {
            p.move(to: CGPoint(x: mid - tw / 2, y: rect.maxY - 1))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.maxY + th), control: CGPoint(x: mid - tw / 6, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: mid + tw / 2, y: rect.maxY - 1), control: CGPoint(x: mid + tw / 6, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// The tour itself, on a practice day (tour v2, Izhan's spec 2026-10-05, board/brief-tour-v2.md). Four cards — the
/// circle, the list, Zikr, Settings — in one bubble that drifts to each card's place and turns its page. The circle and the
/// list: learn first, then try (to-dos, ticked only by the user's own action; one waits, greyed, until the ones before it
/// are done). Zikr and Settings: go there first, then learn it where it lives. Nothing moves on by itself.
@MainActor @Observable final class TourRuntime {
    static let shared = TourRuntime()
    static let doneKey = "tour.v1.done"
    /// Taken to its end (Done on the last card — a skip doesn't count): until then "App Tour" sits in the ☰ menu with a
    /// dot on ☰ (owner, 2026-10-05).
    static let completedKey = "tour.v2.completed"
    /// Set when the first-run setup finishes: the tour starts once the welcome has played.
    static let pendingKey = "tour.v1.pending"
    static let start = Notification.Name("shukr.tour.start")

    private(set) var step: TourStep? {
        didSet {
            #if DEBUG
            if step != oldValue { print("TOUR step \(step.map(\.rawValue) ?? "-")") }   // the sim walk waits on these
            #endif
        }
    }
    /// Where the card is (learn / try / go / last).
    private(set) var phase: TourPhase = .learn {
        didSet {
            #if DEBUG
            if phase != oldValue { print("TOUR phase \(phase)") }
            #endif
        }
    }
    /// The way the bubble's page turned last (the next card in from the right; Back from the left).
    private(set) var forward = true
    /// The prayer the practice marked (Asr).
    private(set) var practicePrayer: PrayerModel?
    /// Bumped when the practice's post-salah pill should go (the page clears it).
    private(set) var clearPill = 0
    /// The current card's to-dos that are done, and its notes (the colours) that have lit.
    private(set) var ticked: Set<Int> = []
    private(set) var lit: Set<Int> = []
    /// Kept for the counting tips' and the time editor's checks: the post-tour steps' ✓ moment.
    private(set) var completing = false
    /// A post-tour step's insight is up (the cards show theirs in `page`).
    private(set) var insight = false
    /// Between begin() and finish(): events belong to the tour, never to the "first real mark" outside it; the pager
    /// and the list are held.
    private(set) var active = false
    /// The invitation is up, on the real day (decision onboarding-start A): Show me / Later. Only after the first-run
    /// setup — Settings' "Show me around again" goes straight in (owner).
    private(set) var inviting = false
    /// How often the tour has started from the first-run setup: a kill mid-tour resumes it once (audit A3).
    static let startedKey = "tour.v1.started"

    /// The circle's colours demo has played once (Continue appears), and is playing now.
    private(set) var sweepPlayed = false
    private(set) var sweeping = false
    /// A finished step opened again by a tap on its ✓ line (its id); one at a time.
    var openSection: String?
    /// A touch the tour didn't let through (owner: no buzz — the thing to touch pulses instead).
    private(set) var nudges = 0
    /// A to-do just done: the thing that changed glows a moment (owner: "give attention to the areas being changed").
    private(set) var flashes = 0
    private(set) var flashKey: String?
    /// Settings: where its page should be (the top on arriving, the tour's row at the end).
    enum SettingsScroll: Equatable { case top, tourRow }
    private(set) var settingsScroll: (SettingsScroll, Int) = (.top, 0)
    /// The qibla line's "skip": a compass that won't settle (set by the layer after a wait).
    var qiblaSkippable = false

    /// The pager stays on the card's page, except while the Zikr card asks for the swipe.
    var locksPager: Bool { active && !(step == .zikr && phase == .go) }
    /// The list stays as the card needs it (TourLayer.sheetPosition); free only where the card is about other pages.
    /// The Zikr card's learn page names Azkar, top right: its door shows then (not tappable — the tour's guard).
    static var showsAzkarDoor: Bool { shared.step == .zikr && shared.phase != .go }
    /// Card 1 lets go once Asr is marked: its last to-do is the swipe up.
    var holdsSheet: Bool {
        active && !(step == .zikr && phase == .go) && step != .settings && !(step == .circle && ticked.contains(2))
    }
    /// The post-salah pill is on the page.
    @ObservationIgnored var pillVisible = false

    /// Whether a prayer's time editor may open now. Outside the tour, always. In it: the list card's last to-do opens
    /// Fajr's only (the one it names and the thumbprint is on — testers held Asr and made it Qaza); once that's saved,
    /// any marked practice prayer, to keep practising (owner, 2026-10-06).
    /// The list's last to-do, still to do: Fajr's save needs a time in the yellow (owner, 2026-10-06 — "they have to put
    /// it in yellow, either by the time wheel or the color bar"); after it, any time saves.
    func needsYellow(_ prayer: PrayerModel) -> Bool {
        active && step == .list && phase == .tryIt && !ticked.contains(3) && prayer.name == "Fajr"
            && Self.isPracticeAnywhere(prayer)
    }

    func allowsEditing(_ prayer: PrayerModel) -> Bool {
        guard active else { return true }
        guard step == .list && phase == .tryIt && !page.locked.contains(3) && prayer.isCompleted
                && Self.isPracticeAnywhere(prayer) else { return false }
        return ticked.contains(3) || prayer.name == "Fajr"
    }

    /// Whether a mark or an unmark may happen now. Outside the tour, always. In it, only the circle's hold, once its
    /// first two to-dos are done (owner: the marking comes last — it moves the circle on). Unmarking: never in the tour
    /// (the list's dots are mentioned, not tried).
    func allows(marking: Bool, _ prayer: PrayerModel) -> Bool {
        guard active else { return true }
        return marking && step == .circle && phase == .tryIt && ticked.isSuperset(of: [0, 1]) && !ticked.contains(2)
            && prayer.name == "Asr" && Self.isPracticeAnywhere(prayer)
    }
    /// Which run of the tour this is: anything scheduled by an earlier run never lands.
    @ObservationIgnored private var run = 0

    // MARK: The practice day

    /// The tour runs on a pretend day (owner: "this whole thing happens with a dummy prayer with dummy data"): five
    /// prayers never saved — Fajr (marked late: Qaza) and Dhuhr done, Asr in its window now, Maghrib and Isha to come.
    private(set) var practiceDay: [PrayerModel]? {
        didSet { Self.practiceMirror = practiceDay }
    }
    /// The same, for the view model's loads that may run off the main actor (a notification action): read, not
    /// written, there. Written only here, by `practiceDay`'s didSet, on the main actor (audit A8).
    nonisolated(unsafe) static var practiceMirror: [PrayerModel]?
    nonisolated static func isPracticeAnywhere(_ prayer: PrayerModel) -> Bool {
        practiceMirror?.contains { $0 === prayer } ?? false
    }
    @ObservationIgnored weak var viewModel: PrayerViewModel?
    func isPractice(_ prayer: PrayerModel) -> Bool { practiceDay?.contains { $0 === prayer } ?? false }
    private var practiceAsr: PrayerModel? { practiceDay?.first { $0.name == "Asr" } }
    private var practiceFajr: PrayerModel? { practiceDay?.first { $0.name == "Fajr" } }
    private static let practiceWindow: TimeInterval = 187 * 60   // Asr 4:31–7:38 PM

    private func startPractice() {
        let now = Date()
        practiceDay = Self.practicePlan.map {
            PrayerModel(name: $0.name, startTime: now.addingTimeInterval($0.from * 60),
                        endTime: now.addingTimeInterval(($0.from + $0.length) * 60))
        }
        if let dhuhr = practiceDay?.first(where: { $0.name == "Dhuhr" }) {
            dhuhr.isCompleted = true
            dhuhr.setPrayerScore(atDate: dhuhr.startTime.addingTimeInterval(12 * 60))
        }
        markFajrLate()
        viewModel?.loadTodaysPrayerObjects()
    }

    /// Fajr marked after its time: Qaza — the obvious one to fix on the list card.
    private func markFajrLate() {
        guard let fajr = practiceFajr else { return }
        fajr.resetPrayer()
        fajr.isCompleted = true
        fajr.setPrayerScore(atDate: fajr.endTime.addingTimeInterval(50 * 60))
    }

    /// The practice day, in minutes from now: laid out as the plain day it reads as (PracticeClock: Fajr 5:12–6:38 AM,
    /// Dhuhr 1:05–4:31 PM, Asr 4:31–7:38 PM, Maghrib 7:38–8:55 PM, Isha 8:55 PM–12:00 AM; owner, section H).
    private static let practicePlan: [(name: String, from: Double, length: Double)] = {
        let asrStart = Double(PracticeClock.asrStartMinute)
        return [("Fajr", 312, 398), ("Dhuhr", 785, 991), ("Asr", 991, 1178), ("Maghrib", 1178, 1255), ("Isha", 1255, 1440)]
            .map { ($0.0, $0.1 - asrStart - 5, $0.2 - $0.1) }
    }()

    /// The practice day kept round now (audit A5): a phone left on a card never lets Asr end or Maghrib come due.
    func repinPractice() {
        guard let day = practiceDay, !sweeping else { return }
        let now = Date()
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) {
            for plan in Self.practicePlan {
                guard let p = day.first(where: { $0.name == plan.name }) else { continue }
                p.startTime = now.addingTimeInterval(plan.from * 60)
                p.endTime = now.addingTimeInterval((plan.from + plan.length) * 60)
            }
        }
    }

    private func endPractice() {
        guard practiceDay != nil else { return }
        practiceDay = nil
        viewModel?.loadTodaysPrayerObjects()
        viewModel?.calculateDayScore(for: PrayerDay.date())   // the circle's score is today's again (Bradley)
    }

    /// Asr's place in its window, as a share of it (its start moved back; the window keeps its length).
    private func setPracticeProgress(_ share: Double, animation: Animation? = .easeInOut(duration: 0.9)) {
        guard let asr = practiceAsr else { return }
        let start = Date().addingTimeInterval(-share * Self.practiceWindow)
        withAnimation(animation) {
            asr.startTime = start
            asr.endTime = start.addingTimeInterval(Self.practiceWindow)
        }
    }

    /// The practice day as a card starts (forward or Back): Asr unmarked on the circle card, marked after it; Fajr late
    /// until it's fixed; "done" closed; no pill.
    private func prepare(_ card: TourStep) {
        // The Zikr chapter's example tasks: up from its first step until Settings is reached (the tab is tapped from
        // the Zikr page).
        TourExamples.shared.hide()   // the Zikr chapter is the Zikr Tour now: real tasks, no examples
        guard practiceDay != nil else { return }
        repinPractice()
        if let asr = practiceAsr {
            let marked = card != .circle
            if marked && !asr.isCompleted {
                asr.isCompleted = true
                asr.setPrayerScore(atDate: asr.startTime.addingTimeInterval(5 * 60))
            } else if !marked && asr.isCompleted {
                asr.resetPrayer()
            }
            practicePrayer = marked ? asr : nil
        }
        if card == .circle || card == .list { markFajrLate() }
        clearPill += 1
        if PrayerListFold.shared.showDone { PrayerListFold.shared.showDone = false }
        viewModel?.objectWillChange.send()
    }

    /// The circle card's colours demo (owner: "user triggered … they see the whole sweep and then the continue button
    /// turns on"): the ring fills smoothly from just begun to nearly over in 7 s — green, then yellow, then red — once,
    /// each colour's line lighting as the ring first reaches it; then the ring is back where it was.
    /// The colours demo's clock: the moment in the practice window the sweep has reached (the circle's time line
    /// switches to the time left in its last hour, as the real one does — owner).
    func sweepNow(for prayer: PrayerModel) -> Date? {
        guard let share = colorSweep, isPractice(prayer) else { return nil }
        return prayer.startTime.addingTimeInterval(share * prayer.endTime.timeIntervalSince(prayer.startTime))
    }

    private func playColors(run thisRun: Int) {
        guard !sweeping else { return }
        sweeping = true
        lit = []
        let start = 5 * 60 / Self.practiceWindow
        colorSweep = start
        Task { @MainActor in
            let sweep: TimeInterval = 8, top = 0.97, frame: TimeInterval = 1.0 / 60
            // Where the ring turns each colour: green at once, then the scoring rule's own changes (30 min in, then
            // halfway through the rest — PrayerScoring.gradeChanges), as shares of the practice window.
            let lights: [Double] = [0.005, Self.sweepStops.yellow, Self.sweepStops.red]
            var playing: Bool { run == thisRun && step == .circle && phase == .learnMore }
            var elapsed: TimeInterval = 0
            var last = Date()
            while playing, elapsed < sweep {
                // Paused while the app isn't in front (a call, the background): the colours are seen (Bradley).
                if !CircleStage.shared.sceneActive {
                    _ = await CircleStage.shared.until { CircleStage.shared.sceneActive }
                    last = Date()
                }
                let now = Date()
                elapsed += now.timeIntervalSince(last)
                last = now
                let share = start + (top - start) * min(elapsed / sweep, 1)
                colorSweep = share
                for (i, at) in lights.enumerated() where share >= at { light(i) }
                try? await Task.sleep(for: .seconds(frame))
            }
            guard run == thisRun else { return }
            try? await Task.sleep(for: .seconds(1.2))   // a beat in the red, the minutes left readable
            guard run == thisRun else { return }
            withAnimation(.easeInOut(duration: CircleMotion.standard)) {
                colorSweep = nil
                sweeping = false
                sweepPlayed = true
            }
            setPracticeProgress(5 * 60 / Self.practiceWindow)   // back to just begun (green)
        }
    }

    /// The colours demo's ring: a share of the window the practice ring draws directly, every frame, instead of its
    /// times — nil otherwise.
    private(set) var colorSweep: Double?
    /// Where the practice window's colour changes (PrayerScoring.gradeChanges), as shares of it.
    static let sweepStops: (yellow: Double, red: Double) = {
        let changes = PrayerScoring.gradeChanges(start: .distantPast, end: Date.distantPast.addingTimeInterval(practiceWindow))
            .map { $0.timeIntervalSince(.distantPast) / practiceWindow }
        return (changes.first ?? 0.16, changes.last ?? 0.58)
    }()
    /// The sweep's colour: the ring's own green, yellow and red, blended across each change (no snap).
    static func sweepColor(_ share: Double) -> Color {
        let blend = 0.05
        func mix(_ a: UIColor, _ b: UIColor, _ t: Double) -> Color {
            var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
                = (0, 0, 0, 0, 0, 0, 0, 0)
            a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let t = CGFloat(min(max(t, 0), 1))
            return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t)
        }
        let green = UIColor(PrayerScoring.color(for: 1)), yellow = UIColor(PrayerScoring.color(for: 0.9)),
            red = UIColor(PrayerScoring.color(for: 0.7))
        let (y, r) = (sweepStops.yellow, sweepStops.red)
        if share < y - blend { return Color(green) }
        if share < y + blend { return mix(green, yellow, (share - (y - blend)) / (2 * blend)) }
        if share < r - blend { return Color(yellow) }
        if share < r + blend { return mix(yellow, red, (share - (r - blend)) / (2 * blend)) }
        return Color(red)
    }

    // MARK: What the bubble says

    /// The current card's words, to-dos and buttons (the post-tour steps have their own, in TourLayer).
    var page: TourPage {
        // A step finishing, its first beat: it rolls up into its ✓ line, nothing new under it yet.
        if let into = folding {
            var p = page(for: step, phase: into)
            if let last = p.sections.last, !last.done { p.sections.removeLast() }
            p.primary = nil
            p.secondary = nil
            return p
        }
        return page(for: step, phase: phase)
    }
    /// A step finishing is two beats (owner: the content collapses into its line item, one card the whole way): first
    /// the fold (this, the phase it's folding into), then the next step under it.
    private(set) var folding: TourPhase?

    /// The owner's words for the circle (2026-10-05), as he laid them out.
    static let circleBlocks = [
        // When → what it shows (owner's words, 2026-10-05): the situation, an arrow, the prayer.
        TourBlock(lead: TourCopy.Circle.showsLead, items: TourCopy.Circle.situations, pairs: true),
        TourBlock(lead: TourCopy.Circle.coloursLead, items: TourCopy.Circle.colours, colours: true),
    ]

    /// A chapter's page: its number and title, how far through it, its steps (the finished ones first).
    private func chapter(_ card: TourStep, _ done: Double, of units: Double, _ sections: [TourSection],
                         locked: Set<Int> = [], primary: String? = nil, secondary: String? = nil) -> TourPage {
        TourPage(headline: card.chapterTitle, index: (TourStep.cards.firstIndex(of: card) ?? 0) + 1,
                 progress: min(done / units, 1), sections: sections, locked: locked,
                 primary: primary, secondary: secondary)
    }

    // Each card is a chapter (owner): "1  Prayer Circle", a ring for how far through it, and its steps — each open while
    // it's the one, then folded to a ✓ line. Learning is short lists (owner's layout), never a paragraph.
    private func page(for step: TourStep?, phase: TourPhase) -> TourPage {
        switch step {
        case .intro:
            // Before the chapters: how the tour goes (owner). No greeting — the setup has said welcome, salam and
            // Bismillah already; this just begins (owner: "just make it say Bismillah. Let's take a quick look around").
            let intro = TourSection(id: "intro",
                                    blocks: [TourBlock(items: TourCopy.Welcome.chapters, numbered: true)],
                                    note: TourCopy.Welcome.footnote,
                                    quietNote: true)
            return TourPage(headline: TourCopy.Welcome.title, subline: TourCopy.Welcome.line, sections: [intro],
                            primary: TourCopy.Welcome.button)
        case .circle:
            var shows = TourSection(id: "circle.shows", title: TourCopy.Circle.showsStep, blocks: [Self.circleBlocks[0]])
            var colours = TourSection(id: "circle.colours", title: TourCopy.Circle.coloursStep, blocks: [Self.circleBlocks[1]])
            var tryIt = TourSection(id: "circle.try", title: TourCopy.tryIt, tasks: TourCopy.Circle.todos)
            switch phase {
            case .learn:
                return chapter(.circle, 0, of: 5, [shows], primary: TourCopy.continueButton)
            case .learnMore:
                shows.done = true
                return chapter(.circle, 1, of: 5, [shows, colours],
                               // The demo starts by itself (owner, 2026-10-06): no button until it has played.
                               primary: sweepPlayed && !sweeping ? TourCopy.continueButton : nil,
                               secondary: sweepPlayed && !sweeping ? TourCopy.Circle.playAgain : nil)
            default:
                shows.done = true
                colours.done = true
                let marked = ticked.contains(2)
                let done = Double(ticked.intersection([0, 1, 2]).count)
                guard marked else { return chapter(.circle, 2 + done, of: 5, [shows, colours, tryIt], locked: lockedCircle) }
                // Marked: the to-dos fold too, and the payoff — small enough to sit above the circle, the whole page
                // under it free for the swipe.
                tryIt.done = true
                let payoff = TourSection(id: "circle.marked",
                                         note: TourCopy.Circle.marked)
                return chapter(.circle, 5, of: 5, [shows, colours, tryIt, payoff], locked: lockedCircle)
            }
        case .list:
            // Two short steps (owner: the first was still too long), one line a bullet.
            var shows = TourSection(id: "list.shows", title: TourCopy.List.showsStep,
                                    // Marked ones tuck away — said with how to get them back (owner: "only unmarked ones are
                                    // shown" alone sounded like losing them).
                                    blocks: [TourBlock(items: TourCopy.List.shows)])
            var can = TourSection(id: "list.can", title: TourCopy.List.canStep,
                                  // What, not how (owner): the gestures are the to-dos' job.
                                  blocks: [TourBlock(items: TourCopy.List.can)])
            guard phase != .learn else { return chapter(.list, 0, of: 6, [shows], primary: TourCopy.continueButton) }
            shows.done = true
            guard phase != .learnMore else { return chapter(.list, 1, of: 6, [shows, can], primary: TourCopy.continueButton) }
            can.done = true
            let all = ticked.isSuperset(of: [0, 1, 2, 3])
            let tryIt = TourSection(id: "list.try", title: TourCopy.tryIt,
                                    // The ones they can do now first, the waiting (greyed) ones after (owner).
                                    tasks: TourCopy.List.todos,
                                    note: all ? TourCopy.List.allDone : nil)
            return chapter(.list, 2 + Double(ticked.intersection([0, 1, 2, 3]).count), of: 6, [shows, can, tryIt],
                           locked: lockedList, primary: all ? TourCopy.continueButton : nil)
        case .zikr:
            var there = TourSection(id: "zikr.go", title: TourCopy.getThere, lead: TourCopy.Zikr.getThereLead,
                                    tasks: [TourCopy.Zikr.getThereTodo])
            guard phase != .go else { return chapter(.zikr, 0, of: 4, [there]) }
            there.done = true
            // Example tasks on the wheel (TourExamples), said so (owner: "not real tasks … just example tasks").
            var page = TourSection(id: "zikr.shows", title: TourCopy.Zikr.pageStep, lead: TourCopy.Zikr.pageLead,
                                   blocks: [TourBlock(items: TourCopy.Zikr.page)])
            guard phase != .learn else { return chapter(.zikr, 1, of: 4, [there, page], primary: TourCopy.continueButton) }
            page.done = true
            let all = ticked.isSuperset(of: [0, 1])
            // Done: the to-dos fold to their ✓ line (as the circle's do), so the bubble stays over the wheel.
            let tryIt = TourSection(id: "zikr.try", title: TourCopy.tryIt, done: all, tasks: TourCopy.Zikr.todos)
            let after = TourSection(id: "zikr.after", note: TourCopy.Zikr.allDone)
            return chapter(.zikr, 2 + Double(ticked.intersection([0, 1]).count), of: 4,
                           [there, page, tryIt] + (all ? [after] : []), primary: all ? TourCopy.continueButton : nil)
        case .settings:
            var there = TourSection(id: "settings.go", title: TourCopy.getThere, lead: TourCopy.Settings.getThereLead,
                                    tasks: [TourCopy.Settings.getThereTodo])
            guard phase != .go else { return chapter(.settings, 0, of: 2, [there]) }
            there.done = true
            var here = TourSection(id: "settings.shows", title: TourCopy.Settings.hereStep,
                                   blocks: [TourBlock(items: TourCopy.Settings.here)])
            guard phase == .last else { return chapter(.settings, 1, of: 2, [there, here], primary: TourCopy.continueButton) }
            here.done = true
            let again = TourSection(id: "settings.again", title: TourCopy.Settings.lastStep, note: TourCopy.Settings.last)
            return chapter(.settings, 2, of: 2, [there, here, again], primary: TourCopy.Settings.doneButton)
        default:
            return TourPage(headline: step?.headline ?? "")
        }
    }

    /// The circle's to-dos that wait: the hold until the tap and the qibla are done (marking moves the circle on, so
    /// it comes last — owner); the swipe up until it's marked.
    private var lockedCircle: Set<Int> {
        var l: Set<Int> = []
        if !ticked.isSuperset(of: [0, 1]) { l.insert(2) }
        if !ticked.contains(2) { l.insert(3) }
        return l
    }
    /// The list's: a marked prayer's score once they're unfolded; the fix once the three taps are done.
    /// One at a time, in order (owner, 2026-10-06: a coming prayer first, the others greyed; then unfold; then the
    /// marked one's score; then the hold) — so the thumbprint always follows the one open to-do.
    private var lockedList: Set<Int> {
        var l: Set<Int> = []
        if !ticked.contains(0) { l.insert(1) }
        if !ticked.isSuperset(of: [0, 1]) { l.insert(2) }
        if !ticked.isSuperset(of: [0, 1, 2]) { l.insert(3) }
        return l
    }

    // MARK: To-dos, notes

    /// One to-do done (the green ✓) — only if it isn't waiting on another — and the thing that changed glows.
    private func tick(_ i: Int, flash key: String? = nil) {
        guard step != nil, !page.locked.contains(i), !ticked.contains(i) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = ticked.insert(i) }
        if let key { glow(key) }
    }

    /// The thing that changed glows once — then the glow is forgotten, so a bubble rebuilt later (a new chapter, a menu
    /// closing) never plays it again somewhere stale (owner: a false glow lingered at the end of chapter 3).
    private func glow(_ key: String) {
        flashKey = key
        flashes += 1
        let mine = flashes
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if flashes == mine { flashKey = nil }
        }
    }

    /// A colour's note has happened: its line lights.
    private func light(_ i: Int) {
        guard !lit.contains(i) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = lit.insert(i) }
    }

    /// A touch the tour didn't let through: the thing to touch pulses (no buzz — owner).
    func nudge() { nudges += 1 }

    // MARK: The steps

    /// The first real mark gets a celebration (and then the map), once — armed by the first-run setup only.
    static let celebrateArmedKey = "tour.firstMark.armed"
    /// The first real mark's post-salah pill waits for the celebration's Continue (owner: "hold the post salah tasbih
    /// pill until after they have marked and they press continue"); then the pill comes, with its own card.
    @ObservationIgnored private var firstMarkPending = false
    private(set) var heldPillName: String?
    /// Bumped when the held pill should come (the page raises it).
    private(set) var pillRelease = 0
    /// Called where the pill would rise after a mark: true = held — for the first-mark celebration, and always during
    /// the tour (owner: "the post salah tasbi pill doesn't actually appear in our onboarding").
    func holdPill(_ name: String) -> Bool {
        if active { return true }
        guard firstMarkPending else { return false }
        heldPillName = name
        return true
    }

    /// How the first mark is celebrated (decision first-mark-celebration A: the edge glow).
    enum CelebrateStyle { case confetti, glow, perfectDay, quiet }
    static var celebrateStyle: CelebrateStyle {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "celebrateStyle") {
        case "A": return .glow
        case "B": return .perfectDay
        case "C": return .quiet
        default: break
        }
        #endif
        return .glow   // decision first-mark-celebration: A (owner, 2026-10-05: "go with option A")
    }

    enum Event {
        case circleTapped, listOpened, unmarked, mapOpened, foldTapped, qiblaAligned, next, back
        /// The Zikr chapter: the wheel moved; an example task's option picked from its hold menu.
        case wheelScrolled, exampleOption
        case comingRowTapped, markedRowTapped, pillClosed, pillOpened, zikrPage, settingsPage
        /// The circle card's "See it in action" / "Play again"; the qibla line's skip (no compass).
        case demo, skipQibla
        /// The time editor opened on a prayer; its score now (0…1); Save.
        case editorOpened(String), editorSaved(String)
        /// A real mark (the circle held, or a dot tapped), or the mark's preview when no prayer is due.
        case marked(PrayerModel, PrayerViewModel), markedPreview(PrayerViewModel)
    }

    /// The card's place in the tour ("1 of 4"); nil for the post-tour steps.
    func place(of step: TourStep) -> (Int, Int)? {
        TourStep.cards.firstIndex(of: step).map { ($0 + 1, TourStep.cards.count) }
    }
    /// A card to go back to.
    /// Back: the step before, within the chapter — never the last chapter (owner, 2026-10-06); none on a chapter's first
    /// step, nor back to a "Get there" (they're already there).
    var canGoBack: Bool { previousPhase != nil }
    private var previousPhase: TourPhase? {
        switch (step, phase) {
        case (.circle, .learnMore), (.list, .learnMore): .learn
        case (.circle, .tryIt), (.list, .tryIt): .learnMore
        case (.zikr, .tryIt): .learn
        case (.settings, .last): .learn
        default: nil
        }
    }

    /// The tour's door after the first-run setup: the invitation on the real day.
    func invite() {
        guard !active, step == nil else { return }
        withAnimation(.easeOut(duration: CircleMotion.quick)) { inviting = true }
    }

    /// "Show me": the practice day comes in and the first card with it.
    func acceptInvite() {
        guard inviting else { return }
        withAnimation(.easeOut(duration: CircleMotion.quick)) { inviting = false }
        begin()
    }

    /// "Later": nothing more, ever, except Settings → Show me around again (the card said so).
    func declineInvite() {
        guard inviting else { return }
        withAnimation(.easeOut(duration: CircleMotion.quick)) { inviting = false }
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    func begin() {
        guard !active else { return }
        inviting = false
        practicePrayer = nil
        CountTips.rearm()   // the first counting session's tips come again too
        run += 1
        // `pendingKey` stays until finish(): a kill mid-tour starts it again on the next launch, once (audit A3).
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.startedKey) + 1, forKey: Self.startedKey)
        active = true
        sweepPlayed = false
        startPractice()
        resetCardState()
        forward = true
        phase = .learn
        prepare(.circle)
        // The card a turn later: the practice day's fetch (startPractice) could draw the layer mid-begin, and a step set
        // in the same turn was then never drawn (Frank's trap).
        let thisRun = run
        Task { @MainActor in
            guard run == thisRun, active, step == nil else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = .intro }
        }
    }

    /// Builds before 2026-10-05 could save the practice day's score as a real day's: once, the last few prayer days
    /// are scored again from their real rows.
    static func repairScoresOnce(_ viewModel: PrayerViewModel) {
        let key = "tour.scoreRepair.v1"
        var force = false
        #if DEBUG
        force = ProcessInfo.processInfo.arguments.contains("-scoreRepairTest")   // run it again (the sim check)
        #endif
        guard practiceMirror == nil, force || !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let today = PrayerDay.date()
        for back in 0...3 {
            guard let day = Calendar.current.date(byAdding: .day, value: -back, to: today),
                  !viewModel.loadPrayerObjects(for: day).isEmpty else { continue }   // no rows: no record (Sami)
            viewModel.calculateDayScore(for: day, fromStore: true)
        }
    }

    /// The first-run tour should start (again) now: set up, not done, and started fewer than twice.
    static var shouldAutoStart: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: pendingKey) && !d.bool(forKey: doneKey) && d.integer(forKey: startedKey) < 2
    }

    func skip() { finish(completed: false) }

    /// The Zikr Tour (chapter 3) ended — finished, or Skip to Settings: on to Settings.
    func zikrTourEnded() {
        guard active, step == .zikr else { return }
        go(to: .settings)
    }

    private func finish(completed: Bool) {
        run += 1
        active = false
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        if completed { UserDefaults.standard.set(true, forKey: Self.completedKey) }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        practicePrayer = nil
        clearPill += 1
        TourExamples.shared.hide()
        endPractice()
        resetCardState()
        sweepPlayed = false
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
    }

    private func resetCardState() {
        ticked = []
        lit = []
        completing = false
        insight = false
        openSection = nil
        folding = nil
        qiblaSkippable = false
        sweeping = false
        colorSweep = nil   // the colours demo's ring goes with it (a skip, Back)
        flashKey = nil     // no glow carried into the next chapter
    }

    func event(_ e: Event) {
        // Outside the tour: the first real mark is celebrated (once), then the map is shown.
        guard let step else {
            if active { return }   // between two cards: the tour's, not a "first real mark" (audit A7)
            if case .marked = e, UserDefaults.standard.bool(forKey: Self.celebrateArmedKey) {
                UserDefaults.standard.set(false, forKey: Self.celebrateArmedKey)
                firstMarkPending = true
                heldPillName = nil
                run += 1
                let thisRun = run
                Task {
                    try? await Task.sleep(for: .seconds(2.4))   // after the mark's own flourish
                    guard run == thisRun, self.step == nil else { return }
                    withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = .celebrate }
                }
            }
            return
        }
        switch (step, phase, e) {
        // After the tour (before the cards' cases): the held pill comes, with its card (or the map hint at once).
        case (.celebrate, _, .next):
            firstMarkPending = false
            if heldPillName != nil {
                pillRelease += 1
                post(.firstPill)
            } else {
                post(.map)
            }
        case (.firstPill, _, .pillOpened): insight = true
        case (.firstPill, _, .pillClosed) where !insight: post(.map)
        case (.firstPill, _, .next): post(.map)
        case (.map, _, .mapOpened), (.map, _, .next), (.hintMark, _, .next):
            withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }

        case (_, _, .back): goBack(from: step)

        // 1 · The circle: learn (the colours demo, then Continue), then try.
        case (.intro, _, .next): go(to: .circle)
        case (.circle, .learn, .next): setPhase(.learnMore)
        case (.circle, .learnMore, .demo): playColors(run: run)
        case (.circle, .learnMore, .next) where sweepPlayed: setPhase(.tryIt)
        case (.circle, .learnMore, .next) where !sweeping: playColors(run: run)   // "See it in action"
        // The glow only on the time words when they flip; none for the qibla or the mark (owner, 2026-10-06).
        case (.circle, .tryIt, .circleTapped): tick(0, flash: "circleTime")
        case (.circle, .tryIt, .qiblaAligned): tick(1)
        case (.circle, .tryIt, .skipQibla): tick(1)
        case (.circle, .tryIt, .marked(let prayer, _)):
            practicePrayer = prayer
            tick(2)
        // The swipe up is the `marked` sentence's ask, not a to-do line (three lines, counted by position — Ben's
        // audit): no tick, on to the list.
        case (.circle, .tryIt, .listOpened) where ticked.contains(2):
            go(to: .list, after: 0.6)

        // 2 · The list: learn, then try.
        case (.list, .learn, .next): setPhase(.learnMore)
        case (.list, .learnMore, .next): setPhase(.tryIt)
        case (.list, .tryIt, .comingRowTapped): tick(0, flash: "comingRow")
        case (.list, .tryIt, .foldTapped): tick(1)   // no glow on unfolding (owner)
        case (.list, .tryIt, .markedRowTapped): tick(2, flash: "markedRow")
        case (.list, .tryIt, .editorSaved): tick(3)
        case (.list, .tryIt, .next) where ticked.isSuperset(of: [0, 1, 2, 3]): go(to: .zikr)

        // 3 · Zikr: go there, then learn it.
        // The Zikr page: the Zikr Tour takes chapter 3 from here (its offer first: Show me / Skip to Settings).
        case (.zikr, .go, .zikrPage):
            withAnimation(.smooth(duration: CircleMotion.standard)) { phase = .deep }
            ZikrTour.shared.offer(inAppTour: true)
        case (.zikr, .learn, .next): setPhase(.tryIt)
        case (.zikr, .tryIt, .wheelScrolled): tick(0)
        case (.zikr, .tryIt, .exampleOption): tick(1)
        case (.zikr, .tryIt, .next) where ticked.isSuperset(of: [0, 1]): go(to: .settings)

        // 4 · Settings: go there, then learn it at the top, then the tour's own row.
        case (.settings, .go, .settingsPage):
            TourExamples.shared.hide()   // off the Zikr page: the user's own tasks are back
            settingsScroll = (.top, settingsScroll.1 + 1)
            setPhase(.learn)
        case (.settings, .learn, .next):
            settingsScroll = (.tourRow, settingsScroll.1 + 1)
            setPhase(.last)
            // Once it has scrolled there, the row glows (owner: "highlight it").
            let thisRun = run
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard run == thisRun, step == .settings, phase == .last else { return }
                glow("tourAgainRow")
            }
        case (.settings, .last, .next): finish(completed: true)
        default: break
        }
    }

    /// A phase within the card: the bubble grows or changes in place (no page turn).
    private func setPhase(_ next: TourPhase) {
        guard folding == nil else { return }
        func land() {
            withAnimation(.smooth(duration: CircleMotion.standard)) {
                if next == .tryIt { ticked = [] }
                openSection = nil
                folding = nil
                phase = next
            }
            // The circle's colours: the demo plays as the step opens (owner: "just start it").
            if step == .circle, next == .learnMore, !sweepPlayed { playColors(run: run) }
        }
        // The step that's done rolls up into its ✓ line first, then the next comes in under it.
        guard step?.isCard == true, next != phase else { return land() }
        openSection = nil
        withAnimation(.smooth(duration: CircleMotion.standard)) { folding = next }
        let thisRun = run, card = step
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CircleMotion.standard + 0.05))
            guard run == thisRun, step == card, folding == next else { return }
            land()
        }
    }

    /// A post-tour step (the celebration's followers): straight there, its own words.
    private func post(_ next: TourStep) {
        completing = false
        insight = false
        ticked = []
        withAnimation(.smooth(duration: CircleMotion.standard)) { step = next }
    }

    /// Back: the card before, as it starts (its practice state put back).
    /// One step back within the chapter: its practice state as the step needs it (a to-do step left: its ticks and
    /// what they changed are undone — the circle's Asr unmarked again), the step's page back as it was.
    private func goBack(from step: TourStep) {
        guard let back = previousPhase else { return }
        if phase == .tryIt { prepare(step) }
        if step == .settings { settingsScroll = (.top, settingsScroll.1 + 1) }
        withAnimation(.smooth(duration: CircleMotion.standard)) {
            ticked = []
            lit = back == .learnMore && step == .circle ? [0, 1, 2] : lit   // the colours' lines, lit as after the demo
            openSection = nil
            folding = nil
            qiblaSkippable = false
            phase = back
        }
    }

    #if DEBUG
    /// `-tourFrom <card>[:<phase>]`: straight to a card (and a phase), its practice state set as on a Back.
    func debugJump(to target: TourStep, phase wanted: TourPhase? = nil) {
        go(to: target)
        guard let wanted else { return }
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard run == thisRun, step == target else { return }
            if target == .circle && wanted == .tryIt { sweepPlayed = true }
            setPhase(wanted)
        }
    }
    #endif

    /// The next card: the practice day set for it, then the bubble turns its page (the page turns inside the bubble, which
    /// drifts to the card's place — it never goes away). `after`: a beat to see the last ✓ first.
    private func go(to next: TourStep, back: Bool = false, after: TimeInterval = 0) {
        let thisRun = run
        Task { @MainActor in
            if after > 0 { try? await Task.sleep(for: .seconds(after)) }
            guard run == thisRun else { return }
            prepare(next)
            // The card a turn after its practice state (as in begin(): a change in the same turn could go undrawn).
            try? await Task.sleep(for: .milliseconds(1))
            guard run == thisRun else { return }
            forward = !back
            withAnimation(.smooth(duration: CircleMotion.standard)) {
                resetCardState()
                if next == .circle && back { sweepPlayed = true }   // back to the circle: its demo was seen
                phase = (next == .zikr || next == .settings) ? .go : (next == .circle && back ? .tryIt : .learn)
                step = next
            }
        }
    }
}

/// The tour's layer over the pager: the one bubble (tour v2 — it stays, drifting from card to card and turning its page;
/// it only steps aside while something truly covers the page), the input guard, Skip tour, the invitation and Back to
/// the tour. Watches the real state changes that tick the to-dos.
struct TourLayer: View {
    let covered: Bool
    @Environment(SharedStateClass.self) private var sharedState
    @EnvironmentObject private var viewModel: PrayerViewModel
    @EnvironmentObject private var compass: CompassState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "You skipped the tour" for a few seconds after a skip (owner: tell them where to find it again).
    @State private var skippedNote = false
    private var runtime: TourRuntime { TourRuntime.shared }

    var body: some View {
        watching(layers)
    }

    /// The layers, front to back: the input guard, the invitation, the one bubble, Back to the tour, Skip tour, the
    /// skipped note.
    private var layers: some View {
        ZStack {
            // Only the card's own moves (owner: "only the intended thing"): while the tour runs the app takes no touch
            // except through the card's openings — no buzz on the others (owner): the thing to touch pulses instead.
            // Chapter 3's Zikr Tour draws its own bubble, guard and Skip (ZikrTour.swift).
            let zikrTour = runtime.step == .zikr && runtime.phase == .deep
            if runtime.active, !covered, !zikrTour {
                TourInputGuard(openings: openings(runtime.step)) { runtime.nudge() }
            }
            inviteLayer
            // The one bubble, for the whole tour: never rebuilt between cards (owner: "one tooltip that visually moves
            // … to the next focus location"); out of sight only while a sheet or a cover is over the page, or the card's
            // page isn't showing (Back to the tour then).
            if let step = runtime.step, !zikrTour {
                bubble(step)
            }
            backPill
            if !zikrTour { skipLayer }
        }
    }

    @ViewBuilder private var inviteLayer: some View {
        // The door after the first-run setup, on the real day (decision onboarding-start A).
        if runtime.inviting, !covered, sharedState.horizontalPage == .main, sharedState.navPosition == .main {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let below = TourTargets.shared.frame("circle").map { $0.maxY - origin.y + 24 } ?? geo.size.height * 0.62
                TourInviteCard(onShow: { runtime.acceptInvite() }, onLater: { runtime.declineInvite() })
                    .frame(width: min(geo.size.width - 48, 320))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, below)
            }
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
            .onAppear {
                AccessibilityNotification.Announcement(TourCopy.Invite.title).post()
            }
        }
    }

    @ViewBuilder private func bubble(_ step: TourStep) -> some View {
        let visible = !covered && onItsPage(step)
        let tryingIt = step.isCard && runtime.phase == .tryIt
        let skipQibla = step == .circle && tryingIt && runtime.qiblaSkippable && !runtime.ticked.contains(1)
        TourOverlay(step: step, page: page(step), target: target(step), place: runtime.place(of: step),
                    ticked: runtime.ticked, lit: runtime.lit,
                    openSection: runtime.openSection,
                    hint: hint(step), aboveY: aboveY(step),
                    showsBack: runtime.canGoBack,
                    flash: flashFrame(), flashes: runtime.flashes, nudges: runtime.nudges,
                    qiblaSkip: skipQibla, forward: runtime.forward,
                    onPrimary: { runtime.event(.next) },
                    onSecondary: { runtime.event(.demo) },
                    onBack: { runtime.event(.back) },
                    onToggle: toggleSection,
                    onSkipQibla: { runtime.event(.skipQibla) })
            // A new chapter is a new bubble (owner, 2026-10-06: "make the bubble disappear and the next one appear"):
            // the old one fades where it is, then the new one comes in at its place (TourCallout's entrance).
            .id(step)
            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeIn(duration: 0.18))))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(.easeOut(duration: CircleMotion.quick), value: visible)
        if step == .celebrate && !reduceMotion {
            switch TourRuntime.celebrateStyle {
            case .confetti: ConfettiBurst().allowsHitTesting(false)
            case .glow: FirstMarkGlow()
            case .perfectDay, .quiet: EmptyView()
            }
        }
    }

    /// A finished step's ✓ line: open it again, or fold it back.
    private func toggleSection(_ id: String) {
        withAnimation(.smooth(duration: CircleMotion.standard)) {
            runtime.openSection = runtime.openSection == id ? nil : id
        }
    }

    @ViewBuilder private var backPill: some View {
        // Taken off the card's page (a widget or a control opened another page; the pager is held): one way back.
        if let step = runtime.step, step.isTourPage, !covered, !onItsPage(step) {
            BackToTourPill { returnTo(step) }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 150)   // above the Zikr page's "tasks done" line and the tab bar
                .transition(.opacity)
        }
    }

    @ViewBuilder private var skipLayer: some View {
        // The way out, for the whole tour, in one place (owner: "just keep it in the top right"): two taps, like
        // Finish early. Where the page has its own top-right button it slides left beside it, in the same row: Zikr's
        // Azkar (shown while its card names it), Settings' light / dark (a row lower sat on the location's refresh).
        let besideCorner = (TourRuntime.showsAzkarDoor && sharedState.horizontalPage == .zikr)
            || sharedState.horizontalPage == .settings
        if runtime.active, !covered {
            TourSkipButton {
                runtime.skip()
                withAnimation(.easeOut(duration: CircleMotion.quick)) { skippedNote = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, (typeSize.isAccessibilitySize ? 56 : 12) - (sharedState.horizontalPage == .settings ? 8 : 0))   // Settings' header sits higher
            .padding(.trailing, besideCorner ? 60 : 16)
            .animation(.smooth(duration: CircleMotion.standard), value: besideCorner)
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
        }
        if skippedNote {
            TourSkippedNote { withAnimation(.easeOut(duration: CircleMotion.quick)) { skippedNote = false } }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 52)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation(.easeOut(duration: CircleMotion.quick)) { skippedNote = false }
                }
        }
    }

    /// The real state changes that move the tour on.
    private func watching(_ content: some View) -> some View {
        content
            .onChange(of: runtime.step) { _, step in
                guard let step else { return }
                if step.isTourPage, !onItsPage(step) { returnTo(step) }
                announce()
            }
            .onChange(of: runtime.phase) { _, _ in
                guard let step = runtime.step, step.isTourPage else { return }
                if !onItsPage(step) { returnTo(step) }
                announce()
            }
            .onChange(of: sharedState.navPosition) { _, position in navChanged(position) }
            // A page reached and at rest (not mid-swipe: ticking mid-move froze the pager — Sami's round D run).
            .onChange(of: CircleStage.shared.restingPage) { _, page in pageRested(page) }
            .onAppear { runtime.viewModel = viewModel }
        .modifier(TourLayerWatchers2(runtime: runtime, compass: compass, qiblaWatch: qiblaWatch))
    }
}

/// The rest of the layer's watchers (split for the type checker).
private struct TourLayerWatchers2: ViewModifier {
    let runtime: TourRuntime
    @ObservedObject var compass: CompassState
    let qiblaWatch: () async -> Void
    private var watchKey: String { (runtime.step?.rawValue ?? "-") + "|" + String(describing: runtime.phase) }

    func body(content: Content) -> some View {
        content
            .onChange(of: runtime.lit) { old, new in
                let colours = TourRuntime.circleBlocks.first(where: \.colours)?.items ?? []
                guard let i = new.subtracting(old).first, colours.indices.contains(i) else { return }
                AccessibilityNotification.Announcement(colours[i]).post()
            }
            .onChange(of: runtime.ticked) { old, new in
                guard let i = new.subtracting(old).first, runtime.page.todo.indices.contains(i) else { return }
                AccessibilityNotification.Announcement("Done: \(runtime.page.todo[i])").post()
            }
            // Back from the background: the practice day round now again (Ben's round C).
            .onChange(of: CircleStage.shared.sceneActive) { _, active in
                if active, runtime.active { runtime.repinPractice() }
            }
            // Facing the qibla (also if already facing it when the line comes up).
            .onChange(of: compass.qibla.aligned) { _, aligned in
                if aligned, runtime.step == .circle, runtime.phase == .tryIt { runtime.event(.qiblaAligned) }
            }
            .task(id: watchKey) { await qiblaWatch() }
            // The practice mark undone (never in the tour now, kept for safety): its pill goes too.
            .onChange(of: runtime.practicePrayer?.isCompleted) { _, done in
                if done == false { runtime.event(.unmarked) }
            }
    }
}

extension TourLayer {

    private func navChanged(_ position: SharedStateClass.ViewPosition) {
        if position == .bottom { runtime.event(.listOpened) }
        // Held: the list stays as the card needs it — a chevron tap or a stray swipe is put back.
        if runtime.holdsSheet, let wanted = sheetPosition(runtime.step), position != wanted {
            withAnimation(CircleMotion.page) { sharedState.navPosition = wanted }
        }
    }

    private func pageRested(_ page: SharedStateClass.HorizontalPage?) {
        // The Zikr card frees the pager for its swipe right; a swipe left (to Settings) is put back (Sami).
        if runtime.active, runtime.step == .zikr, runtime.phase == .go, page == .settings {
            withAnimation(CircleMotion.page) { sharedState.horizontalPage = .main }
            return
        }
        if page == .zikr { runtime.event(.zikrPage) }
        if page == .settings { runtime.event(.settingsPage) }
    }

    /// The qibla line: already facing it ticks it once the bubble is up; a compass that can't settle gets a quiet
    /// "skip" after a while (at once without a compass).
    private func qiblaWatch() async {
        runtime.qiblaSkippable = false
        guard runtime.step == .circle, runtime.phase == .tryIt else { return }
        try? await Task.sleep(for: .seconds(1))
        guard runtime.step == .circle, runtime.phase == .tryIt else { return }
        if compass.qibla.aligned { runtime.event(.qiblaAligned) }
        try? await Task.sleep(for: .seconds(compass.status == .ok ? 15 : 0))
        guard !Task.isCancelled, runtime.step == .circle, runtime.phase == .tryIt else { return }
        withAnimation(.easeOut(duration: CircleMotion.quick)) { runtime.qiblaSkippable = true }
    }

    private func announce() {
        let page = runtime.page
        let todo = page.todo.isEmpty ? "" : " To do: " + page.todo.joined(separator: ", ") + "."
        AccessibilityNotification.Announcement("\(page.headline) \(page.subline ?? "")\(todo)").post()
    }

    /// What the bubble says: a card's page, or a post-tour step's own words.
    private func page(_ step: TourStep) -> TourPage {
        if step.isTourPage { return runtime.page }
        switch step {
        case .celebrate: return TourPage(headline: step.headline, subline: step.subline, primary: TourCopy.continueButton)
        case .firstPill:
            return TourPage(headline: step.headline, subline: step.subline, tasks: step.tasks,
                            insight: runtime.insight ? step.insight.map { $0.0 + " " + $0.1 } : nil,
                            primary: runtime.insight ? TourCopy.continueButton : nil)
        case .map: return TourPage(headline: step.headline, subline: step.subline, tasks: step.tasks, primary: TourCopy.AfterTour.gotIt)
        default: return TourPage(headline: step.headline, subline: step.subline, primary: TourCopy.AfterTour.gotIt)
        }
    }

    /// What the bubble points at, for the card and its phase.
    private func target(_ step: TourStep) -> String? {
        switch (step, runtime.phase) {
        case (.circle, _): return "circle"
        case (.list, _): return "prayerList"
        case (.zikr, .go): return "circle"
        case (.zikr, _): return "zikrSlot"   // the wheel's centre, still while it scrolls (owner)
        case (.settings, .go): return "settingsTab"
        case (.settings, .last): return "tourAgainRow"
        case (.settings, _): return nil
        case (.firstPill, _) where runtime.insight || !runtime.pillVisible: return "circle"
        default: return step.target
        }
    }

    /// Where the bubble's bottom goes on the list card: above the list, never over its rows (audit J).
    private func aboveY(_ step: TourStep) -> CGFloat? {
        switch step {
        case .list: return TourTargets.shared.frame("prayerList")?.minY
        // Marked: over the circle, so the swipe up has the page under it (the bubble there took the touches).
        case .circle where runtime.ticked.contains(2): return TourTargets.shared.frame("circle").map { $0.minY - 10 }
        // Over the wheel: the tasks line under it is one of the things it talks about.
        case .zikr where runtime.phase != .go: return TourTargets.shared.frame("zikrSlot").map { $0.minY - 10 }
        default: return nil
        }
    }

    /// The touch the next to-do asks for, BESIDE the thing that changes (owner: the thumbprint sat on the circle's time
    /// and hid the change) — one cue at a time: none once it's done (the change glows instead), none while learning.
    private func hint(_ step: TourStep) -> TouchHintSpec? {
        let t = TourTargets.shared
        let circle = t.frame("circle")
        let ticked = runtime.ticked, locked = runtime.page.locked
        func next(_ i: Int) -> Bool { !ticked.contains(i) && !locked.contains(i) }
        func time(_ name: String) -> CGPoint? { t.frame("prayerRow." + name).map { CGPoint(x: $0.maxX - 44, y: $0.midY) } }
        func mid(_ r: CGRect?) -> CGPoint? { r.map { CGPoint(x: $0.midX, y: $0.midY) } }
        switch (step, runtime.phase) {
        case (.circle, .tryIt):
            guard let c = circle else { return nil }
            // On the thing to touch, not beside it (user testing, 2026-10-06: beside it misled).
            if next(0) { return .init(kind: .tap, at: CGPoint(x: c.midX, y: c.midY + c.height * 0.3)) }   // low on the circle (owner)
            if next(1) { return nil }   // turning the phone: no touch
            if next(2) { return .init(kind: .hold, at: CGPoint(x: c.midX, y: c.midY)) }
            if next(3) { return t.frame("chevron").map { .init(kind: .swipe(dx: 0, dy: -100), at: CGPoint(x: $0.midX, y: $0.minY - 40)) } }
            return nil
        case (.list, .tryIt):
            if next(0) { return time("Maghrib").map { .init(kind: .tap, at: $0) } }
            if next(1) { return mid(t.frame("doneFold")).map { .init(kind: .tap, at: $0) } }   // on "3 done"
            if next(2) { return time("Fajr").map { .init(kind: .tap, at: $0) } }
            if next(3) { return t.frame("prayerRow.Fajr").map { .init(kind: .hold, at: CGPoint(x: $0.midX, y: $0.midY)) } }
            return nil
        case (.zikr, .tryIt):
            guard let c = t.frame("zikrSlot") else { return nil }
            // Up the wheel beside the circle; then a hold on it.
            if next(0) { return .init(kind: .swipe(dx: 0, dy: -110), at: CGPoint(x: c.maxX - 10, y: c.maxY + 30)) }
            if next(1) { return .init(kind: .hold, at: CGPoint(x: c.midX, y: c.midY)) }
            return nil
        case (.zikr, .go):
            guard sharedState.horizontalPage == .main, let c = circle else { return nil }
            // Across the circle: the bubble sits under it (no room above once the list's rows show).
            return .init(kind: .swipe(dx: 170, dy: 0), at: CGPoint(x: c.minX - 20, y: c.midY))
        case (.settings, .go):
            guard sharedState.horizontalPage != .settings else { return nil }
            return mid(t.frame("settingsTab")).map { .init(kind: .tap, at: $0) }
        case (.map, _):
            return circle.map { .init(kind: .tap, at: CGPoint(x: $0.midX + $0.width * 0.315, y: $0.midY - $0.height * 0.235)) }
        case (.firstPill, _):
            return t.frame("pill").map { .init(kind: .tap, at: CGPoint(x: $0.midX, y: $0.midY)) }
        default: return nil
        }
    }

    /// The thing that just changed (owner: "give attention to the areas that are being changed").
    private func flashFrame() -> CGRect? {
        let t = TourTargets.shared
        switch runtime.flashKey {
        case "circleTime":
            return t.frame("circle").map { CGRect(x: $0.midX - $0.width * 0.36, y: $0.midY + 2, width: $0.width * 0.72, height: 30) }
        case "qiblaArrow", "circle": return t.frame("circle")
        case "doneFold": return t.frame("doneFold")
        case "tourAgainRow": return t.frame("tourAgainRow")
        // Only the time that changed, not the whole row (owner).
        case "markedRow", "comingRow":
            return t.lastTappedRow.flatMap { t.frame("prayerRow." + $0) }
                .map { CGRect(x: $0.maxX - 116, y: $0.minY + 4, width: 108, height: $0.height - 8) }
        default: return nil
        }
    }

    /// Back to where the card happens: its page, and the list open or closed as it needs.
    private func returnTo(_ step: TourStep) {
        let page: SharedStateClass.HorizontalPage = switch (step, runtime.phase) {
        case (.zikr, .go): .main
        case (.zikr, _): .zikr
        case (.settings, .go): .zikr
        case (.settings, _): .settings
        default: .main
        }
        sharedState.go(to: page)
        if let wanted = sheetPosition(step), sharedState.navPosition != wanted {
            withAnimation(CircleMotion.page) { sharedState.navPosition = wanted }
        }
    }

    /// Where the list must be for a card (nil: either).
    private func sheetPosition(_ step: TourStep?) -> SharedStateClass.ViewPosition? {
        switch step {
        case .circle: runtime.ticked.contains(2) ? nil : .main   // marked: the swipe up opens it (the card's last move)
        case .intro: .main
        case .list: .bottom
        case .zikr: .main
        default: nil
        }
    }

    /// Where the card's moves may happen (global frames). A card's harmless taps stay open after their to-do is done
    /// (owner: "those actions should be allowed over and over again, as long as they are in that step"); the ones that
    /// change something are refused by `TourRuntime.allows` / `allowsEditing` (a pulse, no buzz).
    private func openings(_ step: TourStep?) -> [CGRect] {
        guard let step, onItsPage(step) else { return [] }
        let t = TourTargets.shared
        func f(_ key: String) -> [CGRect] { t.frame(key).map { [$0] } ?? [] }
        /// The page between `top` and the tab bar: where a swipe starts.
        func swipeBand(from top: CGFloat?) -> [CGRect] {
            guard let bottom = t.frame("settingsTab")?.minY else { return [] }
            let y = (top ?? 140)
            return [CGRect(x: 0, y: y, width: 10_000, height: max(bottom - 8 - y, 0))]
        }
        switch (step, runtime.phase) {
        case (.circle, .tryIt):
            return f("circle") + (runtime.ticked.contains(2) ? swipeBand(from: t.frame("circle").map { $0.maxY + 8 }) : [])
        case (.list, .tryIt):
            let rows = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].flatMap { f("prayerRow." + $0) }
            return f("doneFold") + rows
        case (.zikr, .go): return sharedState.horizontalPage == .main ? swipeBand(from: 120) : []
        // Scroll the wheel, hold a task: the page under the bubble (taps start nothing — the wheel's own guard).
        // From the wheel's top (under the top bar and its doors), not the centre circle's: a drag on the wheel's upper
        // half was taken (owner: "my drags a bit to the side don't seem to work").
        case (.zikr, .tryIt): return sharedState.horizontalPage == .zikr ? swipeBand(from: t.frame("historyDoor").map { $0.maxY + 12 } ?? 120) : []
        case (.settings, .go): return sharedState.horizontalPage == .settings ? [] : f("settingsTab")
        default: return []
        }
    }

    private func onItsPage(_ step: TourStep) -> Bool {
        let page = sharedState.horizontalPage, list = sharedState.navPosition
        switch (step, runtime.phase) {
        case (.circle, _): return page == .main && (list == .main || runtime.ticked.contains(2))
        case (.list, _): return page == .main && list == .bottom
        case (.zikr, .go): return page == .main || page == .zikr
        case (.zikr, _): return page == .zikr
        case (.settings, .go): return page == .zikr || page == .settings
        case (.settings, _): return page == .settings
        case (.hintMark, _): return page == .main && list == .bottom
        default: return page == .main
        }
    }
}

/// The first mark's celebration: a short burst of small pieces in the app's calm colours from the circle, then gone.
struct ConfettiBurst: View {
    @State private var go = false
    private let pieces: [(angle: Double, distance: CGFloat, size: CGFloat, color: Color)] = (0..<44).map { i in
        let colors: [Color] = [Color(.systemGreen), Color(.systemYellow), Color(.systemTeal), .sage, Color(.systemMint)]
        return (Double(i) / 44 * 2 * .pi + Double.random(in: -0.2...0.2),
                CGFloat.random(in: 130...270), CGFloat.random(in: 8...13), colors[i % colors.count])
    }

    var body: some View {
        GeometryReader { geo in
            let c = WelcomeTarget.circleFrame.map { CGPoint(x: $0.midX - geo.frame(in: .global).minX, y: $0.midY - geo.frame(in: .global).minY) }
                ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.4)
            ZStack {
                ForEach(pieces.indices, id: \.self) { i in
                    let p = pieces[i]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 1.6)
                        .rotationEffect(.degrees(go ? Double(i * 47) : 0))
                        .position(x: c.x + (go ? cos(p.angle) * p.distance : 0),
                                  y: c.y + (go ? sin(p.angle) * p.distance + 40 : 0))
                        .opacity(go ? 0 : 0.95)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 2.2)) { go = true } }
    }
}

/// A touch to show: where, and which gesture.
struct TouchHintSpec {
    enum Kind { case tap, hold, swipe(dx: CGFloat, dy: CGFloat) }
    var kind: Kind
    var at: CGPoint
}

/// A grey thumbprint showing the touch the step asks for (owner: "a grayish circle indicator about as big as a thumbprint
/// that pulses slowly to indicate a tap … same idea for long pressing. same idea for dragging but over an oval"). Slow
/// loops, drawn from the clock (no state); still under Reduce Motion. Takes no touches.
struct TouchHint: View {
    let spec: TouchHintSpec
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let size: CGFloat = 46

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            content(reduceMotion ? nil : context.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thumb: some View {
        Circle()
            .fill(Color.primary.opacity(0.14))
            .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))
            .frame(width: Self.size, height: Self.size)
    }

    /// 0…1 through a loop of `length` seconds (a still frame at `still` without motion).
    private func phase(_ t: Double?, _ length: Double, still: Double) -> Double {
        t.map { $0.truncatingRemainder(dividingBy: length) / length } ?? still
    }

    @ViewBuilder private func content(_ t: Double?) -> some View {
        let size = Self.size
        switch spec.kind {
        case .tap:
            // 1.8 s: a press (down, up), a ripple widening and fading, a rest.
            let p = phase(t, 1.8, still: 0.4)
            let press = p < 0.12 ? p / 0.12 : (p < 0.24 ? 1 - (p - 0.12) / 0.12 : 0)
            let r = (p - 0.18) / 0.5
            ZStack {
                if t != nil, r > 0, r < 1 {
                    Circle().stroke(Color.primary.opacity(0.28 * (1 - r)), lineWidth: 1.5)
                        .frame(width: size * (1 + 0.9 * r), height: size * (1 + 0.9 * r))
                }
                thumb.scaleEffect(1 - 0.14 * press)
            }
            .position(spec.at)
        case .hold:
            // 2.6 s: pressed down, a ring filling round it while held, let go, a rest.
            let p = phase(t, 2.6, still: 0.5)
            let down = p < 0.1 ? p / 0.1 : (p < 0.72 ? 1 : (p < 0.8 ? 1 - (p - 0.72) / 0.08 : 0))
            let fill = p < 0.1 ? 0 : min((p - 0.1) / 0.55, 1) * (p < 0.8 ? 1 : 0)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                    .frame(width: size + 14, height: size + 14)
                Circle().trim(from: 0, to: t == nil ? 0.75 : fill)
                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 14, height: size + 14)
                thumb.scaleEffect(1 - 0.12 * down)
            }
            .position(spec.at)
        case .swipe(let dx, let dy):
            // 2 s over an oval track: touch down, slide along it, lift off at the end, a rest.
            let p = phase(t, 2.0, still: 0)
            let length = hypot(dx, dy)
            let along = p < 0.15 ? 0 : (p < 0.7 ? (p - 0.15) / 0.55 : 1)
            let eased = along * along * (3 - 2 * along)
            let alpha = p < 0.08 ? p / 0.08 : (p < 0.7 ? 1 : max(0, 1 - (p - 0.7) / 0.12))
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(width: length + size, height: size)
                    .rotationEffect(.radians(atan2(dy, dx)))
                    .position(x: spec.at.x + dx / 2, y: spec.at.y + dy / 2)
                thumb
                    .opacity(t == nil ? 1 : alpha)
                    .position(x: spec.at.x + dx * eased, y: spec.at.y + dy * eased)
                if t == nil {   // still: the way to go
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .rotationEffect(.radians(atan2(dy, dx)))
                        .position(x: spec.at.x + dx * 0.6, y: spec.at.y + dy * 0.6)
                }
            }
        }
    }
}

/// The practice day's clock (owner, audit section H: "fixed plausible times"; the colours demo "isn't how our actual
/// salah ring behaves" when its "ends at" moved). Its windows sit round the real now, so the ring, the colour and the
/// mark's score behave as they do for a real prayer; its times are shown as a plain afternoon, Asr at 4:31 PM. The
/// shift is taken from Asr's start, so the colours demo, which slides Asr's window, leaves "ends 7:38 PM" where it is.
enum PracticeClock {
    static let asrStartMinute = 16 * 60 + 31

    /// How far a prayer's times are moved for show: 0 for a real prayer.
    static func shift(for prayer: PrayerModel) -> TimeInterval {
        guard TourRuntime.isPracticeAnywhere(prayer),
              let asr = TourRuntime.practiceMirror?.first(where: { $0.name == "Asr" }) else { return 0 }
        let asrShown = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(asrStartMinute) * 60)
        return asrShown.timeIntervalSince(asr.startTime)
    }

    /// A practice prayer's time as shown (a real prayer's as it is).
    static func shown(_ date: Date, of prayer: PrayerModel) -> Date { date.addingTimeInterval(shift(for: prayer)) }
}

/// The tour's input guard: a clear sheet over the app that takes every touch — taps, holds, swipes — except through
/// `openings` (global frames), where the touch reaches the app beneath. A touch it takes gets a light no.
struct TourInputGuard: View {
    let openings: [CGRect]
    /// A touch it took (owner: no buzz — the tour makes the thing to touch pulse instead).
    var onBlocked: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let shape = Path { p in
                p.addRect(CGRect(origin: .zero, size: geo.size).insetBy(dx: -200, dy: -200))
                for o in openings {
                    // Plain rects: SwiftUI's even-odd hit test reads a small curved hole (Asr's 26 pt dot) as filled, so
                    // the undo step's tap never got through at 402 pt (Sami); `CGPath` and plain rects get it right.
                    p.addRect(o.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6))
                }
            }
            Color.clear
                .contentShape(shape, eoFill: true)
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in onBlocked() })
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

/// Skip tour (owner: "a double tap confirmation … like how our finish early buttons are"): the first tap arms it —
/// "✓ Tap again to skip" in sage, growing leftwards (it's placed by its trailing edge) — the second skips; it lets go
/// after 3 s.
struct TourSkipButton: View {
    /// Its words: the tour's, or the counting session's tips' ("Skip tips").
    var label = TourCopy.Skip.button
    var confirm = TourCopy.Skip.confirm
    let action: () -> Void
    /// Its own fade in (the layer inserts it without one).
    @State private var shown = false
    @State private var armed = false
    @State private var token = 0
    /// The words, out while the capsule changes (out, then in — the two labels never cross).
    @State private var wordsAway = false
    /// The green edge, faded on its own (the capsule itself changes size at once — see `change(to:)`).
    @State private var edge = false
    @Environment(\.circleTheme) private var theme

    var body: some View {
        // One capsule whose words and colour change, with its own tap: what's drawn is what takes the tap (as a system
        // Button, the armed capsule's left part took no tap — Sami, Frank).
        // Armed: a green edge and green words, grown into (owner: "animate when it changes states … a green border").
        HStack(spacing: 5) {
            if armed {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            Text(armed ? confirm : label)
                .font(.system(.footnote, design: .rounded, weight: armed ? .semibold : .medium))
        }
        .opacity(wordsAway ? 0 : 1)
        .foregroundStyle(armed ? TourInk.green : Color.primary.opacity(0.6))
        .padding(.horizontal, 14)
        .frame(height: 32)
        // Solid: the page's own colour under the tint, so what it covers (Zikr's title beside Azkar) doesn't show
        // through (owner: "fill in its background so we don't have ghosting").
        .background(Capsule().fill(Color.primary.opacity(0.06)).background(Capsule().fill(theme.backdrop)))
        .overlay(Capsule().strokeBorder(TourInk.green, lineWidth: 1.5).opacity(edge ? 1 : 0))
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture(perform: tap)
        .opacity(shown ? 1 : 0)
        .task { withAnimation(.easeOut(duration: CircleMotion.quick)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(armed ? confirm : label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, tap)
    }

    private func tap() {
        if armed {
            triggerSomeVibration(type: .medium)
            armed = false
            edge = false
            action()
        } else {
            triggerSomeVibration(type: .light)
            token += 1
            let mine = token
            change(to: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // an input timeout, not a motion
                if mine == token { change(to: false) }
            }
        }
    }

    /// Out, then in: the words fade, the capsule changes size while they're away — at once, never animated (an
    /// animated width kept the old tap area: the armed capsule's left part took no tap — Frank's trap, seen again
    /// 2026-10-06) — then the new words and the green edge fade in.
    private func change(to on: Bool) {
        withAnimation(.easeOut(duration: 0.1)) { wordsAway = true; if !on { edge = false } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { armed = on }
            withAnimation(.easeIn(duration: 0.15)) { wordsAway = false; if on { edge = true } }
        }
    }
}

/// After a skip: where the tour lives now (owner: "hey, you skipped the tour … you can find it in settings").
struct TourSkippedNote: View {
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(TourCopy.Skip.skippedTitle)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            Text(TourCopy.Skip.skippedLine)
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 340, alignment: .leading)
        .tourBubble(RoundedRectangle(cornerRadius: 20, style: .continuous),
                    look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
        .padding(.horizontal, 24)
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The tour's door (decision onboarding-start A, Ben's audit L): on the real day, under the circle, in the tour's look —
/// no ring, no to-dos, no haptic. Show me (green) / Later (quiet).
struct TourInviteCard: View {
    let onShow: () -> Void
    let onLater: () -> Void
    /// Its own fade in (the layer inserts it without one).
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TourCopy.Invite.title)
                    .font(.system(.body, design: .rounded, weight: .regular))
                Text(TourCopy.Invite.line)
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(TourCopy.Invite.later, action: onLater)
                    .buttonStyle(.plain)
                    .font(.system(.footnote, design: .rounded, weight: .regular))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                Spacer()
                Button(action: onShow) {
                    Text(TourCopy.Invite.showMe)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Capsule().fill(TourInk.green))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // taller couldn't clear its target (Sami, AX XXXL)
        .tourBubble(RoundedRectangle(cornerRadius: 22, style: .continuous),
                    look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
        .accessibilityElement(children: .contain)
        .opacity(shown ? 1 : 0)
        .task { withAnimation(.easeOut(duration: 0.4)) { shown = true } }
    }
}

/// Decision first-mark-celebration A: the map's qibla edge glow in the ring's green, once — in, a breath, out.
struct FirstMarkGlow: View {
    @State private var on = false
    var body: some View {
        AlignedEdgeGlow(on: on)
            .task {
                on = true
                try? await Task.sleep(for: .seconds(1.6))
                on = false
            }
    }
}

/// "Back to the tour ›": shown when something took the page away from the tour's step.
struct BackToTourPill: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(TourCopy.backToTour)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .tourBubble(Capsule(), look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
        }
        .buttonStyle(.plain)
    }
}

/// The fix step's tip inside the time editor (audit J: "the tooltip continues into a sheet"): what to do there, its
/// two to-dos ticking as the time lands in the yellow and as it's saved.
struct TourSheetTip: View {
    private var runtime: TourRuntime { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TourCopy.List.editorTitle)
                .font(.system(.body, design: .rounded, weight: .regular))
            Text(TourCopy.List.editorLine)
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TourChecklist(tasks: [TourCopy.List.editorTodo], ticked: runtime.ticked.contains(3) ? [0] : [])
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.tertiarySystemFill)))
        // The sheet adds a fixed room for it (PrayerTimeEditSheet, +132): larger, it pushed Save off the sheet and the
        // step couldn't be finished (Sami, AX XXXL).
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
    }
}

/// A dot on ☰ until the tour has been taken to its end (owner, 2026-10-05): it leads to "App Tour" in the menu. The
/// compass's red dot sits over it when that's needed too.
struct TourMenuBadge: View {
    @AppStorage(TourRuntime.completedKey) private var completed = false
    var body: some View {
        Circle()
            .fill(TourInk.green)
            .frame(width: 8, height: 8)
            // The app tour not yet taken to its end (the Zikr Tour's dot is on the Zikr tab now, with its lock).
            .opacity(completed || TourRuntime.shared.active || ZikrTour.shared.active ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: completed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "App Tour" at the bottom of the ☰ menu until the tour has been taken to its end (a skip leaves it there); then
/// it's gone for good — Settings' "Show me around again" stays (owner, 2026-10-05).
struct TourMenuRow: View {
    @AppStorage(TourRuntime.completedKey) private var completed = false
    let action: () -> Void

    var body: some View {
        if !completed {
            Button(action: action) {
                Label {
                    Text(TourCopy.menuRow)
                } icon: {
                    Image(systemName: "sparkles")
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(TourInk.green).frame(width: 7, height: 7).offset(x: 3, y: -2)
                        }
                }
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("A short look around shukr")
        }
    }
}

/// The Zikr chapter's example tasks (owner, decision tour-zikr-practice A: "make it clear that these are not real tasks
/// … they're just example tasks"): three tasks, their zikr and a few days of sessions in a store of their own, in
/// memory only — never the user's store, gone when the chapter is. While they're up the wheel, its summary line and
/// the page title read them instead of the user's tasks; each circle says "example"; nothing on them starts, edits or
/// deletes anything.
@MainActor @Observable final class TourExamples {
    static let shared = TourExamples()
    private(set) var tasks: [TaskModel]?
    private(set) var sessions: [SessionDataModel]?
    @ObservationIgnored private var container: ModelContainer?

    func isExample(_ task: TaskModel) -> Bool { tasks?.contains { $0.id == task.id } ?? false }

    func show() {
        guard tasks == nil else { return }
        guard let made = try? ModelContainer(for: Schema(ShukrSchemaV2.models),
                                             configurations: ModelConfiguration("tourExamples", isStoredInMemoryOnly: true))
        else { return }
        let context = made.mainContext
        context.autosaveEnabled = false
        let today = PrayerDay.sessionDayStart().addingTimeInterval(2 * 3600)
        func day(_ back: Int) -> Date { today.addingTimeInterval(Double(-back) * 86_400) }

        // One done today (it has left the wheel; it counts in "1 of 3"), one halfway, one not started.
        let plan: [(name: String, full: String, count: Bool, goal: Int, today: Int, days: Int)] = [
            ("Subhanallah", "سُبْحَانَ ٱللَّٰهِ", true, 33, 33, 3),
            ("Salawat", "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ", true, 100, 40, 5),
            ("Astaghfirullah", "أَسْتَغْفِرُ ٱللَّٰهَ", false, 5, 0, 2),
        ]
        var tasks: [TaskModel] = []
        var todays: [SessionDataModel] = []
        for (i, p) in plan.enumerated() {
            let mantra = MantraModel(name: p.name, fullText: p.full)
            context.insert(mantra)
            let task = TaskModel(mantra: mantra, isCountMode: p.count, goal: p.goal, sortOrder: i)
            context.insert(task)
            tasks.append(task)
            let pace = 1.2   // seconds a count
            func session(on date: Date, counts: Int) -> SessionDataModel {
                let seconds = p.count ? Double(counts) * pace : Double(p.goal) * 60
                let s = SessionDataModel(title: p.name, sessionMode: p.count ? 2 : 1,
                                         targetMin: p.count ? 0 : p.goal, targetCount: p.count ? p.goal : 0,
                                         totalCount: p.count ? counts : Int(seconds / pace), startTime: date,
                                         secondsPassed: seconds, avgTimePerClick: pace, tasbeehRate: "",
                                         task: task, mantra: mantra)
                context.insert(s)
                return s
            }
            // A run of earlier days that met the goal: the title shows a streak.
            for back in 1...p.days { _ = session(on: day(back), counts: p.goal) }
            if p.today > 0 { todays.append(session(on: today, counts: p.today)) }
        }
        container = made
        self.sessions = todays
        self.tasks = tasks
    }

    func hide() {
        guard tasks != nil else { return }
        tasks = nil
        sessions = nil
        // The store a little longer: a view drawn from the last frame may still read an example as it goes.
        let going = container
        container = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            _ = going
        }
    }
}

/// "during a prayer → the current one": the situation in a heavier weight, a quiet arrow, what it does lighter — in
/// columns, so the arrows line up and the pattern reads at a glance (owner).
struct TourPairs: View {
    let lines: [String]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(lines.indices, id: \.self) { i in
                let parts = lines[i].split(separator: "|", maxSplits: 1).map(String.init)
                GridRow(alignment: .firstTextBaseline) {
                    // Still a bulleted list (owner): the dot in the bullets' own column.
                    Circle().fill(Color.primary.opacity(0.3)).frame(width: 4, height: 4)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                        .frame(width: 15)
                    Text(parts[0])
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.95))
                    Image(systemName: "arrow.right")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.35))
                    Text(parts.count > 1 ? parts[1] : "")
                        .font(.system(.subheadline, design: .rounded, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(parts.joined(separator: ": "))
            }
        }
    }
}

#if DEBUG
@MainActor enum TourDebugOnce { static var started = false }
#endif
