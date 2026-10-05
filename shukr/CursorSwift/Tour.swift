import SwiftUI
import TipKit

/// The first-run tour on the live app (owner, ask onboarding-tour: "a little gentle onboarding once users get past set up
/// … not stand alone sheets, like acc interactive on the real app"; Ben's brief board/brief-frank-onboarding-tour.md).
/// Coach marks: a dim with a clear cut-out round the real control, one line beside it, the step ending on the real action.
/// The dim takes no touches, so the control under the cut-out (and everything else) works as usual.
enum TourStep: String, CaseIterable, Identifiable {
    case circle, colors, qibla, list, rowTime, mark, fold, markedRow, edit, undo, zikr, settings, celebrate, map, hintMark
    var id: String { rawValue }

    /// The measured frame it points at (TourTargets), or nil for a page-wide step.
    var target: String? {
        switch self {
        case .circle, .colors, .qibla, .celebrate, .map: "circle"
        case .edit: "prayerRow.Fajr"
        case .undo, .mark, .hintMark: "prayerDot."   // + the prayer's name (TourLayer)
        case .fold: "doneFold"
        case .rowTime, .markedRow: "prayerRow."      // + the row's name (TourLayer)
        case .list: "chevron"
        case .zikr, .settings: nil                   // the settings row once there (TourLayer)
        }
    }
    var words: String { headline + ". " + subline }

    /// The ask's two lines: a short headline and a quiet line under it.
    var headline: String {
        switch self {
        case .circle: "Your prayer"
        case .colors: "Green, yellow, red"
        case .qibla: "Face the qibla"
        case .list: "Today's prayers"
        case .rowTime: "How long until it starts"
        case .mark: "Mark your prayer"
        case .fold: "Your marked prayers"
        case .markedRow: "Your time and score"
        case .edit: "Fix a mark"
        case .undo: "Undo a mark"
        case .zikr: "Your zikr"
        case .settings: "Settings"
        case .celebrate: "Your first prayer, marked"
        case .map: "See where you prayed"
        case .hintMark: "Tap the dot"
        }
    }
    var subline: String {
        switch self {
        case .circle:
            #if DEBUG
            UserDefaults.standard.string(forKey: "mockTourStart") == "B"
                ? "Let's practise on a pretend prayer — nothing here is saved."
                : "This is a practice prayer: nothing here is saved."
            #else
            "This is a practice prayer: nothing here is saved."
            #endif
        case .colors: "The ring's colour is the score you'd get if you prayed now."
        case .qibla: "The small arrow on the circle points the way."
        case .list: "They're under the circle."
        case .rowTime: "A coming prayer's time can show how long is left."
        case .mark: "It's the practice prayer, so nothing is saved."
        case .fold: "Marked prayers tuck under \u{201C}done\u{201D}."
        case .markedRow: "A marked prayer shows when you prayed and your score."
        case .edit: "Fajr was marked late, so it counts as Qaza. Say you really prayed it on time."
        case .undo: "Marked one by mistake?"
        case .zikr: "It's one page over."
        case .settings: "The bar at the bottom takes you to any page, too."
        case .celebrate: "Keep it up — every prayer you mark grows your streak."
        case .map: "Every prayer you mark is on the map, under Explore → Prayers."
        case .hintMark: "to mark it prayed. Hold it to change the time."
        }
    }
    /// What the step was good for, shown once its to-dos are done, with Continue (owner, audit J: "do → insight →
    /// continue"). nil: the ask stays, with Continue (a step with nothing to do).
    var insight: (String, String)? {
        switch self {
        case .circle: ("Your prayer at a glance", "Tap the circle any time to see how long is left before it ends.")
        case .colors: ("Pray in the green", "The earlier you pray, the higher the score. Grey means missed.")
        case .qibla: ("That's the qibla", "Wherever you are, the arrow points the way. Tap it for the map.")
        case .list: ("Your day, prayer by prayer", "Tap a prayer's dot to mark it. Its time says when it starts, or how long until. Marked prayers tuck under \u{201C}done\u{201D}.")
        case .rowTime: ("Plan ahead", "Tap a coming prayer's time to see how long until it starts. It flips back by itself.")
        case .mark: ("Marked", "After each prayer this pill offers Tasbih Fatimah (33 · 33 · 34). Tap it to start, or \u{2715} to skip.")
        case .fold: ("Out of the way", "Your list stays short, and your marked prayers are one tap away.")
        case .markedRow: ("How you did", "Each marked prayer shows its score. Fajr says Qaza: it was marked after its time.")
        case .edit: ("Fixed", "You can change the time, and the place too. What the app recorded is kept, so you can always go back to it.")
        case .undo: ("Undone", "That's how you take back a mark.")
        case .zikr: ("Your zikr", "Your zikr and daily tasks live here. Tap the circle to start counting, any time.")
        case .settings: ("Show me around again", "Run this tour again any time, from here.")
        case .celebrate, .map, .hintMark: nil
        }
    }
    /// The step's notes (owner, audit I: "two kinds of line"): bullets that light as they happen, nothing to do.
    var notes: [String] {
        switch self {
        case .colors: ["Green: the first 30 minutes", "Yellow: on time", "Red: late"]
        case .qibla: ["It turns green when you face it"]
        default: []
        }
    }
    /// The step's to-dos: each ticked only by the user's own action (audit J: never by a state that changes by itself).
    var tasks: [String] {
        switch self {
        case .circle: ["Tap the circle", "Tap again to flip it back"]
        case .qibla: ["Turn until the arrow points up"]
        case .list: ["Swipe up"]
        case .rowTime: ["Tap Maghrib's time"]
        case .mark: ["Tap Asr's dot, or hold the circle", "Close the pill with \u{2715}"]
        case .fold: ["Tap \u{201C}done\u{201D} to show them", "Tap it again to hide them"]
        case .markedRow: ["Tap Fajr's time"]
        case .edit: ["Hold Fajr's row", "Pick a time in the yellow", "Save"]
        case .undo: ["Tap Asr's dot, then Yes"]
        case .zikr: ["Swipe right"]
        case .settings: ["Tap Settings below"]
        case .map: ["Tap the arrow on the circle"]
        case .colors, .celebrate, .hintMark: []
        }
    }
    var symbol: String {
        switch self {
        case .circle, .hintMark: "hand.tap"
        case .mark, .fold: "checkmark.circle"
        case .colors: "circle.lefthalf.filled"
        case .edit: "clock.arrow.circlepath"
        case .undo: "arrow.uturn.backward"
        case .qibla: "location.north.line"
        case .rowTime: "hourglass"
        case .markedRow: "checkmark.seal"
        case .celebrate: "sparkles"
        case .map: "map"
        case .list: "arrow.up"
        case .zikr: "circle.hexagongrid"
        case .settings: "gearshape"
        }
    }
    /// The steps on the list (the bubble sits above the list, never over its rows — audit J).
    var aboutTheList: Bool { [.rowTime, .mark, .fold, .markedRow, .edit, .undo].contains(self) }
    /// The tour's place ("2 of 12") is the runtime's (`TourRuntime.place(of:)`).
    var place: (Int, Int)? { nil }
    /// A round cut-out (the circles, the dot) or a capsule (the chevron).
    var roundHole: Bool { ![.list, .fold, .rowTime, .markedRow, .edit].contains(self) }
}

/// Where the tour's targets are on screen, reported by the views themselves (global frames, written only on change).
@MainActor @Observable final class TourTargets {
    static let shared = TourTargets()
    private(set) var frames: [String: CGRect] = [:]
    func set(_ key: String, _ frame: CGRect) {
        guard frame.width > 0, frames[key] != frame else { return }
        frames[key] = frame
    }
    func frame(_ key: String) -> CGRect? {
        key == "circle" ? WelcomeTarget.circleFrame : frames[key]
    }
}

/// Two looks for the words, for the owner's pick (decision onboarding-tour-look): a small card by the cut-out, or a
/// line near the bottom.
enum TourCardStyle: String { case card, line, callout }

/// The dim with its cut-out and the words. Touches pass through the dim to the real app; only "Skip tour" takes one.
struct TourOverlay: View {
    let step: TourStep
    var style: TourCardStyle = .card
    /// A target in place of the step's own (the mark hint: "prayerDot.<the current prayer>").
    var target: String? = nil
    /// The words in place of the step's (the practice mark's "That's it").
    var override: (String, String)? = nil
    /// No action can end the step right now: a "Next" instead.
    var showsNext = false
    /// The tour's place when it isn't the step's own (a tour without the undo step has 5).
    var place: (Int, Int)? = nil
    /// The to-dos in place of the step's own (the mark step with no prayer due), and which are done.
    var tasks: [String]? = nil
    var ticked: Set<Int> = []
    /// The notes that have lit (shown while the step asks; hidden with its insight).
    var lit: Set<Int> = []
    var showNotes = true
    /// What the step was good for, added under its ticked to-dos once they're done.
    var insight: (String, String)? = nil
    var nextLabel = "Next"
    /// The touch to show (global).
    var hint: TouchHintSpec? = nil
    /// The bubble's bottom here (global y), above what it talks about (the list steps — audit J); nil: by the hole.
    var aboveY: CGFloat? = nil
    var showsBack = false
    var onNext: () -> Void = {}
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    private var targets: TourTargets { TourTargets.shared }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let hole: CGRect? = (target ?? step.target).flatMap { targets.frame($0) }.map {
                $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: step.roundHole ? -10 : -14, dy: step.roundHole ? -10 : -6)
            }
            ZStack(alignment: .topLeading) {
                if style == .callout {
                    TourCallout(step: step, hole: hole, size: geo.size, override: override, showsNext: showsNext,
                                place: place ?? step.place, tasks: tasks ?? step.tasks, ticked: ticked,
                                notes: showNotes ? step.notes : [], lit: lit, insight: insight, nextLabel: nextLabel,
                                hint: hint.map { TouchHintSpec(kind: $0.kind, at: CGPoint(x: $0.at.x - origin.x, y: $0.at.y - origin.y)) },
                                aboveY: aboveY.map { $0 - origin.y }, showsBack: showsBack,
                                onNext: onNext, onBack: onBack, onSkip: onSkip)
                } else {
                    dim(size: geo.size, hole: hole)
                        .allowsHitTesting(false)
                    if let hole {
                        holeEdge(hole).allowsHitTesting(false)
                    }
                    switch style {
                    case .card: card(in: geo.size, hole: hole)
                    case .line: line(in: geo.size)
                    case .callout: EmptyView()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func dim(size: CGSize, hole: CGRect?) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let hole {
                if step.roundHole {
                    let d = max(hole.width, hole.height)
                    p.addEllipse(in: CGRect(x: hole.midX - d / 2, y: hole.midY - d / 2, width: d, height: d))
                } else {
                    p.addRoundedRect(in: hole, cornerSize: CGSize(width: hole.height / 2, height: hole.height / 2))
                }
            }
        }
        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
    }

    @ViewBuilder private func holeEdge(_ hole: CGRect) -> some View {
        if step.roundHole {
            let d = max(hole.width, hole.height)
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: d, height: d)
                .position(x: hole.midX, y: hole.midY)
        } else {
            Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
        }
    }

    /// A: a small card under the cut-out (above it when there's no room below), or low on the page for a page-wide step.
    @ViewBuilder private func card(in size: CGSize, hole: CGRect?) -> some View {
        let below = hole.map { size.height - $0.maxY > 230 } ?? true
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: step.symbol).font(.title3).foregroundStyle(Color(.systemGreen))
                Text(step.words).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let place = step.place {
                    Text("\(place.0) of \(place.1)").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(step.place == nil ? "Got it" : "Skip tour", action: onSkip)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: min(size.width - 48, 320), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .fontDesign(.rounded)
        VStack(spacing: 0) {
            if below {
                Color.clear.frame(height: hole.map { $0.maxY + 20 } ?? size.height * 0.58)
                content
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                content
                Color.clear.frame(height: hole.map { size.height - $0.minY + 20 } ?? 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// B: one line near the bottom, white on the dim, with Skip under it.
    private func line(in size: CGSize) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: step.symbol)
                Text(step.words).multilineTextAlignment(.center)
            }
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            Button(step.place == nil ? "Got it" : "Skip tour", action: onSkip)
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
        }
        .fontDesign(.rounded)
        .frame(width: size.width)
        .position(x: size.width / 2, y: size.height - 150)
    }
}

#if DEBUG
/// `-demoTour <step> [-tourStyle line]`: the overlay drawn over the live app for the pictures, a few seconds in (the
/// targets measured), with the page the step needs.
struct TourDemoLayer: View {
    @Environment(SharedStateClass.self) private var sharedState
    @EnvironmentObject private var viewModel: PrayerViewModel
    @State private var step: TourStep?
    private let style = TourCardStyle(rawValue: UserDefaults.standard.string(forKey: "tourStyle") ?? "") ?? .card

    var body: some View {
        ZStack {
            if let step {
                TourOverlay(step: step, style: style,
                            target: step == .hintMark ? viewModel.relevantPrayer.map { "prayerDot." + $0.name } : nil) { self.step = nil }
            }
            // `-mockTourStart A`: decision onboarding-start's A, a picture only (Ben's audit L): the invitation on the
            // real day, under the circle. Nothing behind its buttons.
            if UserDefaults.standard.string(forKey: "mockTourStart") == "A", let circle = TourTargets.shared.frame("circle") {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    TourInviteMock()
                        .frame(width: min(geo.size.width - 48, 300))
                        .position(x: geo.size.width / 2, y: circle.maxY - origin.y + 24 + 95)
                }
            }
        }
        .task {
            // `-tourStart [-tourStartAfter s]`: the real tour, as Settings → Show me around again starts it.
            if ProcessInfo.processInfo.arguments.contains("-tourStart") {
                let wait = UserDefaults.standard.double(forKey: "tourStartAfter")
                try? await Task.sleep(for: .seconds(wait > 0 ? wait : 3))
                NotificationCenter.default.post(name: TourRuntime.start, object: nil)
                // `-tourFrom <step>`: straight to that step (its practice state set as on a Back).
                if let raw = UserDefaults.standard.string(forKey: "tourFrom"), let from = TourStep(rawValue: raw) {
                    try? await Task.sleep(for: .seconds(1.5))
                    TourRuntime.shared.debugJump(to: from)
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
            guard let raw = UserDefaults.standard.string(forKey: "demoTour"), let wanted = TourStep(rawValue: raw) else { return }
            try? await Task.sleep(for: .seconds(2))
            if wanted == .hintMark { sharedState.navPosition = .bottom }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = wanted }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let size = bubble.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let h = size.height
        let wanted = edge.map { below ? $0 + h / 2 : $0 - h / 2 } ?? fallbackY
        // Never off the screen, nor under the status bar or the home indicator (a tall bubble, large text, a small phone).
        let top = 64 + h / 2, bottom = bounds.height - 24 - h / 2
        let y = bottom > top ? min(max(wanted, top), bottom) : bounds.height / 2
        bubble.place(at: CGPoint(x: bounds.midX, y: bounds.minY + y), anchor: .center,
                     proposal: ProposedViewSize(width: size.width, height: h))
    }
}

/// Round 3 (owner: "too subtle … not a fan of the stock apple tool tip"; Bradley's four changes): a shukr-made callout.
/// A light spotlight (the rest of the page washes out a little, never grey), the control glowing twice, and a soft raised
/// bubble that grows out of the control's edge with a soft tail: the gesture moving inside it, a headline and a quiet
/// line, the tour's place (dots) and Continue.
struct TourCallout: View {
    let step: TourStep
    let hole: CGRect?
    let size: CGSize
    var override: (String, String)? = nil
    var showsNext = false
    var place: (Int, Int)? = nil
    /// The step's to-dos and which are done (TourRuntime.ticked); its notes and which have lit.
    var tasks: [String] = []
    var ticked: Set<Int> = []
    var notes: [String] = []
    var lit: Set<Int> = []
    /// The insight, under the ticked to-dos (owner, Ben's section K: the card stays, the insight is added to it).
    var insight: (String, String)? = nil
    var nextLabel = "Next"
    /// The touch to show, in this view's space.
    var hint: TouchHintSpec? = nil
    /// The bubble's bottom here (this view's space): above the list on its steps (audit J).
    var aboveY: CGFloat? = nil
    var showsBack = false
    var onNext: () -> Void = {}
    var onBack: () -> Void = {}
    var onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @State private var shown = false
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let center = hole.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height * 0.45)
        // Below the control when there's room, else above it.
        // Above or below from a fixed allowance, never from the bubble's own measured height: that fed back (a taller
        // bubble flipped it, the flip re-measured it) and spun the main thread on Settings (Sami's round D run).
        let below = aboveY == nil && (hole.map { size.height - $0.maxY > 260 } ?? true)
        let width = typeSize >= .xxLarge ? size.width - 32 : min(size.width - 48, 300)
        // The tail points at the control (Settings' tab sits right of centre), kept clear of the corners.
        let tail = hole.map { min(max($0.midX - size.width / 2, -(width / 2 - 40)), width / 2 - 40) } ?? 0
        ZStack(alignment: .topLeading) {
            // The spotlight: the page washes out a little away from the control, in the page's own colour (no grey).
            RadialGradient(colors: [.clear, .clear, theme.backdrop.opacity(0.45)],
                           center: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)),
                           startRadius: 0, endRadius: max(size.width, size.height) * 0.75)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
            // Where to touch, and how: a grey thumbprint that taps, holds or slides (owner: "a grayish circle indicator
            // about as big as a thumbprint that pulses slowly … that way we don't gotta show the green circle").
            if let hint { TouchHint(spec: hint) }
            // Measured and placed in one layout pass (`TourBubblePlacement`): never a stored height fed back into its
            // position — that looped on Settings (Sami, 402 pt: 116 % CPU, the step never reached Done).
            TourBubblePlacement(edge: bubbleEdge(below: below), below: aboveY != nil ? false : below,
                                fallbackY: size.height * 0.62) {
                bubble(below: below, tail: tail)
                    // Larger text gets the screen's width (audit C13); kept on screen by the placement.
                    .frame(width: width)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.6, anchor: below ? .top : .bottom)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
        }
        .task {
            // Reduce Motion (audit C14): the ring is simply there and the bubble fades in.
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { shown = true }
                return
            }
            // A beat, then the bubble rises out of the page beside the control.
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = true }
        }
    }

    /// The edge the bubble hangs from: its top when below the control, its bottom when above (nil = no control).
    private func bubbleEdge(below: Bool) -> CGFloat? {
        if let aboveY { return aboveY - 14 }
        guard let hole else { return nil }
        return below ? hole.maxY + 14 : hole.minY - 14
    }

    private func bubble(below: Bool, tail: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // The gesture, in the page's ink: green is kept for what's done (owner: "not too much of it").
                Image(systemName: step.symbol)
                    .font(.system(.title3, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.9)),
                                  isActive: !reduceMotion && ticked.count < max(tasks.count, 1))
                    .accessibilityHidden(true)
                    .frame(width: 28)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    // The app's own type: rounded, light (owner: "change the type face in tooltip to match").
                    Text(override?.0 ?? step.headline)
                        .font(.system(.body, design: .rounded, weight: .regular))
                        .accessibilityAddTraits(.isHeader)
                    Text(override?.1 ?? step.subline)
                        .font(.system(.subheadline, design: .rounded, weight: .light))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !tasks.isEmpty || !notes.isEmpty {
                TourChecklist(tasks: tasks, ticked: ticked, notes: notes, lit: lit)
                    .padding(.leading, 40)
            }
            if let insight {
                VStack(alignment: .leading, spacing: 3) {
                    // Not twice: the Zikr step's insight has the card's own headline (Sami's nit).
                    if insight.0 != (override?.0 ?? step.headline) {
                        Text(insight.0)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                    }
                    Text(insight.1)
                        .font(.system(.subheadline, design: .rounded, weight: .light))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 40)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
            }
            HStack {
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
                    .padding(.leading, -34)   // in the icon's column
                }
                if let place {
                    HStack(spacing: 3) {
                        ForEach(1...place.1, id: \.self) { i in
                            Circle().fill(i <= place.0 ? Color.primary.opacity(i == place.0 ? 0.6 : 0.3) : Color(.tertiaryLabel).opacity(0.5))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(place.0) of \(place.1)")
                }
                Spacer()
                // No "Not now" here (owner): the way out is Skip tour at the top, two taps (TourSkipButton).
                if showsNext {
                    Button(nextLabel, action: onNext)
                        .buttonStyle(.plain)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(TourInk.green).fixedSize()
                        .padding(.leading, 16)
                }
            }
            .padding(.leading, 40)
        }
        .padding(16)
        .tint(TourInk.green)   // never the system blue
        .accessibilityElement(children: .contain)
        .tourBubble(BubbleShape(tailUp: below, tailOffset: tail), look: TourBubbleLook(rawValue: lookRaw) ?? .glass,
                    scheme: scheme, backdrop: theme.backdrop)
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
            if #available(iOS 26.0, *) {
                self.glassEffect(.regular, in: shape)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 16, y: 8)
            } else {
                self.background(.regularMaterial, in: shape)
                    .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            }
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
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
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .animation(.snappy(duration: 0.3), value: done)
                // VoiceOver reads each to-do with its state (audit C15).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((done ? "Done: " : "To do: ") + tasks[i]
                                    + (progress.map { done ? "" : ", \($0.0) of \($0.1)" } ?? ""))
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

/// A rounded bubble with a soft tail at the top or bottom (no hard triangle: the tail's sides are curves), `tailOffset`
/// from the centre.
struct BubbleShape: Shape {
    var tailUp: Bool
    var tailOffset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22, tw: CGFloat = 30, th: CGFloat = 10
        var p = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
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

/// The tour itself, on a practice day (Tour.swift's top; owner's rounds A–J). Every step: its to-dos, ticked only by the
/// user's own action, and its notes, lit as they happen → once all are done, its insight with Continue (nothing moves on
/// by itself) → the next step. Back returns to the previous step, its practice state put back.
@MainActor @Observable final class TourRuntime {
    static let shared = TourRuntime()
    static let doneKey = "tour.v1.done"
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
    /// The prayer the practice marked (Asr; the undo step points at its dot).
    private(set) var practicePrayer: PrayerModel?
    /// Bumped when the practice's post-salah pill should go (the page clears it).
    private(set) var clearPill = 0
    /// The current step's to-dos that are done, and its notes that have lit.
    private(set) var ticked: Set<Int> = []
    private(set) var lit: Set<Int> = []
    /// Every to-do done and note lit: the ✓ shows a moment, then the insight.
    private(set) var completing = false
    /// The step's insight is up, with Continue (audit J).
    private(set) var insight = false
    /// Between begin() and finish(), gaps between steps included: events then belong to the tour, never to the
    /// "first real mark" outside it (audit A7); the pager and the list are held (audit E17).
    private(set) var active = false
    /// How often the tour has started from the first-run setup: a kill mid-tour resumes it once (audit A3).
    static let startedKey = "tour.v1.started"
    /// How long the ✓ shows before the insight.
    static let acknowledge: TimeInterval = 0.9

    /// The pager stays on the step's page, except where the step is about other pages.
    /// The pager stays on the step's page; only the Zikr step swipes (Settings is reached by the bar — audit J).
    var locksPager: Bool { active && step != .zikr }
    /// The list stays open or closed as the step needs; the list step opens it, and the last two leave it be.
    var holdsSheet: Bool { active && !(step == .list || step == .zikr || step == .settings) }
    /// The post-salah pill is on the page.
    @ObservationIgnored var pillVisible = false

    /// Whether a mark or an unmark may happen now (Ben's G1 / G2). Outside the tour, always. In it, only the step's own:
    /// a mark on the mark step; Asr's undo on the undo step.
    func allows(marking: Bool, _ prayer: PrayerModel) -> Bool {
        guard active else { return true }
        if marking { return step == .mark && !ticked.contains(0) }
        return step == .undo && prayer === practicePrayer && !completing
    }
    /// Which run of the tour this is: a step scheduled by an earlier run (or after Not now) never shows.
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

    /// Fajr marked after its time: Qaza, for the fix step (audit J).
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

    /// The practice day kept round now (audit A5): a phone left on a step never lets Asr end or Maghrib come due.
    func repinPractice() {
        guard let day = practiceDay else { return }
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
    private func setPracticeProgress(_ share: Double, animated: Bool = true) {
        guard let asr = practiceAsr else { return }
        let start = Date().addingTimeInterval(-share * Self.practiceWindow)
        withAnimation(animated ? .easeInOut(duration: 0.9) : nil) {
            asr.startTime = start
            asr.endTime = start.addingTimeInterval(Self.practiceWindow)
        }
    }

    /// The practice day as a step starts (forward or Back): Asr marked only from the fold step to the undo step, Fajr
    /// late until it's fixed, "done" open on the marked-row steps, no pill, Asr just begun.
    private func prepare(_ step: TourStep) {
        guard practiceDay != nil else { return }
        repinPractice()
        if let asr = practiceAsr {
            let marked = [.fold, .markedRow, .edit, .undo].contains(step)
            if marked && !asr.isCompleted {
                asr.isCompleted = true
                asr.setPrayerScore(atDate: asr.startTime.addingTimeInterval(5 * 60))
            } else if !marked && asr.isCompleted {
                asr.resetPrayer()
            }
            practicePrayer = marked ? asr : nil
        }
        if [.circle, .colors, .qibla, .list, .rowTime, .mark, .fold, .markedRow, .edit].contains(step) { markFajrLate() }
        if step != .mark || !pillVisible { clearPill += 1 }
        let open = [.markedRow, .edit, .undo].contains(step)
        if PrayerListFold.shared.showDone != open { PrayerListFold.shared.showDone = open }
        viewModel?.objectWillChange.send()
    }

    /// The colours step: the practice ring goes green → yellow → red, each note lit as the ring gets there.
    private func playColors(run thisRun: Int) {
        Task {
            try? await Task.sleep(for: .seconds(1.2))   // the bubble first
            for (i, share) in [0.06, 0.4, 0.85].enumerated() {
                // Paused while the app isn't in front (a call, the background): the colours are seen (Bradley).
                _ = await CircleStage.shared.until { CircleStage.shared.sceneActive }
                guard run == thisRun, step == .colors else { return }
                setPracticeProgress(share)
                try? await Task.sleep(for: .seconds(1.0))
                guard run == thisRun, step == .colors else { return }
                light(i)
                try? await Task.sleep(for: .seconds(1.1))
            }
            guard run == thisRun else { return }
            setPracticeProgress(5 * 60 / Self.practiceWindow)   // back to just begun (green)
        }
    }

    // MARK: To-dos, notes, insight

    /// One to-do done (the green ✓).
    private func tick(_ i: Int) {
        guard let step, !completing, step.tasks.indices.contains(i), !ticked.contains(i) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = ticked.insert(i) }
        checkDone()
    }

    /// A note has happened: its bullet lights.
    private func light(_ i: Int) {
        guard let step, step.notes.indices.contains(i), !lit.contains(i) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = lit.insert(i) }
        checkDone()
    }

    /// The next to-do not yet done (steps whose to-dos are done in order).
    private func tickNext() {
        guard let step, let i = step.tasks.indices.first(where: { !ticked.contains($0) }) else { return }
        tick(i)
    }

    /// Every to-do ticked and every note lit: the ✓ a moment, then the insight and Continue.
    private func checkDone() {
        guard let step, !completing, ticked.count >= step.tasks.count, lit.count >= step.notes.count else { return }
        completing = true
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(Self.acknowledge))
            guard run == thisRun, self.step == step else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { insight = true }
        }
    }

    // MARK: The steps

    /// The tour's steps this time.
    private(set) var steps: [TourStep] = TourRuntime.allSteps
    static let allSteps: [TourStep] = [.circle, .colors, .qibla, .list, .rowTime, .mark, .fold, .markedRow, .edit, .undo,
                                       .zikr, .settings]
    /// The first real mark gets a celebration (and then the map), once — armed by the first-run setup only.
    static let celebrateArmedKey = "tour.firstMark.armed"

    enum Event {
        case circleTapped, listOpened, unmarked, mapOpened, foldTapped, qiblaAligned, next, back
        case comingRowTapped, markedRowTapped, pillClosed, zikrPage, settingsPage
        /// The time editor opened on a prayer; its score now (0…1); Save.
        case editorOpened(String), editorScored(Double), editorSaved(String)
        /// A real mark (the circle held, or a dot tapped), or the mark's preview when no prayer is due.
        case marked(PrayerModel, PrayerViewModel), markedPreview(PrayerViewModel)
    }

    func place(of step: TourStep) -> (Int, Int)? {
        steps.firstIndex(of: step).map { ($0 + 1, steps.count) }
    }
    /// A step to go back to.
    var canGoBack: Bool { step.flatMap { steps.firstIndex(of: $0) }.map { $0 > 0 } ?? false }

    func begin() {
        practicePrayer = nil
        steps = Self.allSteps
        // The celebration is armed by the first-run setup only (FirstRunSetup.markDone): Show me around again never
        // brings confetti to someone already using the app (audit A6).
        CountTips.rearm()   // the first counting session's tips come again too
        run += 1
        // `pendingKey` stays until finish(): a kill mid-tour starts it again on the next launch, once (audit A3).
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.startedKey) + 1, forKey: Self.startedKey)
        active = true
        startPractice()
        resetStepState()
        prepare(.circle)
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = .circle }
    }

    /// Builds before 2026-10-05 could save the practice day's score as a real day's (a widget / banner mark mid-tour
    /// re-scored "today" from the practice list — Bradley's review): once, the last few prayer days are scored again
    /// from their real rows.
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

    func skip() { finish() }

    private func finish() {
        run += 1
        active = false
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        practicePrayer = nil
        // The practice mark's pill goes with the tour: left up, a tap opened a real, saved Tasbih Fatimah (Bradley).
        clearPill += 1
        endPractice()
        resetStepState()
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
    }

    private func resetStepState() {
        ticked = []
        lit = []
        completing = false
        insight = false
    }

    func event(_ e: Event) {
        // Outside the tour: the first real mark is celebrated (once), then the map is shown.
        guard let step else {
            if active { return }   // between two steps: the tour's, not a "first real mark" (audit A7)
            if case .marked = e, UserDefaults.standard.bool(forKey: Self.celebrateArmedKey) {
                UserDefaults.standard.set(false, forKey: Self.celebrateArmedKey)
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
        switch (step, e) {
        // Continue, once the insight is up; Back, any time.
        case (_, .next) where insight || step.tasks.isEmpty && step.notes.isEmpty: advance(from: step)
        case (_, .back): goBack(from: step)
        // Only the user's own action ticks (audit J): the circle's tap, not its flip state.
        // Two taps, two to-dos (owner): time left, then back to when it ends.
        case (.circle, .circleTapped):
            tickNext()
        case (.qibla, .qiblaAligned):
            tick(0)
            light(0)
        // No compass: Next is the way past it.
        case (.qibla, .next): advance(from: step)
        case (.list, .listOpened): tick(0)
        case (.rowTime, .comingRowTapped): tick(0)
        case (.mark, .marked(let prayer, _)):
            practicePrayer = prayer
            tick(0)
        case (.mark, .markedPreview):
            // No prayer due (the practice day always has one; kept for safety): nothing to close or undo.
            steps.removeAll { $0 == .undo }
            tick(0)
            tick(1)
        // ✕ (or a flick), never the pill's own expiry (audit J).
        case (.mark, .pillClosed) where ticked.contains(0): tick(1)
        // The fold's tap, never a fold the app made itself (audit J).
        case (.fold, .foldTapped): tickNext()
        case (.markedRow, .markedRowTapped): tick(0)
        case (.edit, .editorOpened(let name)) where name == "Fajr": tick(0)
        // On time (yellow) or better.
        case (.edit, .editorScored(let score)) where ticked.contains(0) && score >= 0.8: tick(1)
        case (.edit, .editorSaved(let name)) where name == "Fajr" && ticked.contains(1): tick(2)
        case (.undo, .unmarked):
            clearPill += 1
            tick(0)
        case (.zikr, .zikrPage): tick(0)
        case (.settings, .settingsPage): tick(0)
        case (.celebrate, .next): go(to: .map)
        case (.map, .mapOpened), (.map, .next): withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }
        default: break
        }
    }

    /// The step after `step` in this run's list; after the last, the end.
    private func advance(from step: TourStep) {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { finish(); return }
        go(to: steps[i + 1])
    }

    /// The step before, as it starts (audit J: "Back").
    private func goBack(from step: TourStep) {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        go(to: steps[i - 1])
    }

    #if DEBUG
    func debugJump(to target: TourStep) { go(to: target) }
    #endif

    /// Out, then in: the bubble goes, the practice day is set for the next step, then it comes at the next control.
    private func go(to next: TourStep) {
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
        resetStepState()
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            guard run == thisRun else { return }
            prepare(next)
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = next }
            if next == .colors { playColors(run: thisRun) }
        }
    }
}

/// The tour's layer over the pager: the callout for the current step, only on the page it belongs to and only when
/// nothing covers the app. Watches the real state changes that end the steps.
struct TourLayer: View {
    let covered: Bool
    @Environment(SharedStateClass.self) private var sharedState
    @EnvironmentObject private var viewModel: PrayerViewModel
    @EnvironmentObject private var compass: CompassState
    /// The qibla step has waited a while (a compass that won't settle): a Next appears.
    @State private var qiblaWaited = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "You skipped the tour" for a few seconds after a skip (owner: tell them where to find it again).
    @State private var skippedNote = false
    private var runtime: TourRuntime { TourRuntime.shared }

    var body: some View {
        ZStack {
            // The way out, away from the tips (owner: no "Not now" in them): two taps, like Finish early.
            if runtime.active, runtime.step != nil, !covered {
                TourSkipButton {
                    runtime.skip()
                    withAnimation(.easeOut(duration: CircleMotion.quick)) { skippedNote = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 52)
                .padding(.trailing, 16)
                .transition(.opacity)
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
            // Taken off the step's page (a widget or a control opened another page; the pager is held, so it was a
            // dead end — Ben's round C): one way back.
            if let step = runtime.step, !covered, !onItsPage(step) {
                BackToTourPill { returnTo(step) }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 150)   // above the Zikr page's "tasks done" line and the tab bar
                    .transition(.opacity)
            }
            if let step = runtime.step, !covered, onItsPage(step) {
                let insight = runtime.insight
                // The ask stays as it was — headline, ticked to-dos, notes — and the insight is added under it (owner,
                // Ben's section K: swapping the words read as a new card).
                let words = override(step)
                let nothingToDo = step.tasks.isEmpty && step.notes.isEmpty
                TourOverlay(step: step, style: .callout,
                            target: target(step),
                            override: words,
                            // Continue once the insight is up (or at once for a step with nothing to do); Next only
                            // where no action can end it: a compass that can't settle.
                            showsNext: insight || nothingToDo || step == .celebrate
                                || (step == .qibla && !runtime.completing && (compass.status != .ok || qiblaWaited)),
                            place: runtime.place(of: step),
                            ticked: runtime.ticked,
                            lit: runtime.lit,
                            insight: insight ? step.insight : nil,
                            nextLabel: nextLabel(step, insight: insight || nothingToDo),
                            hint: runtime.completing || insight ? nil : hint(step),
                            aboveY: aboveY(step),
                            showsBack: runtime.canGoBack,
                            onNext: { runtime.event(.next) },
                            onBack: { runtime.event(.back) },
                            onSkip: { runtime.skip() })
                    .id(step)
                if step == .celebrate && !reduceMotion { ConfettiBurst().allowsHitTesting(false) }
            }
        }
        .onChange(of: sharedState.navPosition) { _, position in
            if position == .bottom { runtime.event(.listOpened) }
            // Held: the list stays as the step needs it (audit E17) — a chevron tap or a stray swipe is put back.
            if runtime.holdsSheet, let wanted = sheetPosition(runtime.step), position != wanted {
                withAnimation(CircleMotion.page) { sharedState.navPosition = wanted }
            }
        }
        // A page reached and at rest (not mid-swipe: ticking mid-move froze the pager — Sami's round D run).
        .onChange(of: CircleStage.shared.restingPage) { _, page in
            if page == .zikr { runtime.event(.zikrPage) }
            if page == .settings { runtime.event(.settingsPage) }
        }
        .onAppear { runtime.viewModel = viewModel }
        .onChange(of: runtime.step) { _, step in
            guard let step else { return }
            // The step's page and list as it starts (a Back from another page included).
            if !onItsPage(step) { returnTo(step) }
            // The last two are about other pages: the list closes for them.
            if (step == .zikr || step == .settings) && sharedState.navPosition != .main {
                withAnimation(CircleMotion.page) { sharedState.navPosition = .main }
            }
            // VoiceOver says each step as it comes, each to-do as it's done (audit C15); touches still pass through.
            let todo = step.tasks.isEmpty ? "" : " To do: " + step.tasks.joined(separator: ", ") + "."
            AccessibilityNotification.Announcement("\(step.headline). \(step.subline)\(todo)").post()
        }
        .onChange(of: runtime.insight) { _, on in
            if on, let insight = runtime.step?.insight {
                AccessibilityNotification.Announcement("\(insight.0). \(insight.1)").post()
            }
        }
        .onChange(of: runtime.lit) { old, new in
            guard let step = runtime.step, let i = new.subtracting(old).first, step.notes.indices.contains(i) else { return }
            AccessibilityNotification.Announcement(step.notes[i]).post()
        }
        .onChange(of: runtime.ticked) { old, new in
            guard let step = runtime.step, let i = new.subtracting(old).first, step.tasks.indices.contains(i) else { return }
            AccessibilityNotification.Announcement("Done: \(step.tasks[i])").post()
        }
        // Back from the background: the practice day round now again (Ben's round C).
        .onChange(of: CircleStage.shared.sceneActive) { _, active in
            if active, runtime.active, runtime.step != .colors { runtime.repinPractice() }
        }
        // Facing the qibla (also if already facing it when the step comes up).
        .onChange(of: compass.qibla.aligned) { _, aligned in
            if aligned { runtime.event(.qiblaAligned) }
        }
        .task(id: runtime.step) {
            qiblaWaited = false
            guard runtime.step == .qibla else { return }
            // Already facing it: ticked once the bubble is up, not before it (audit E18).
            try? await Task.sleep(for: .seconds(1))
            guard runtime.step == .qibla else { return }
            if compass.qibla.aligned { runtime.event(.qiblaAligned); return }
            try? await Task.sleep(for: .seconds(20))
            qiblaWaited = true
        }
        // The practice mark undone by the user (its dot → Unmark).
        .onChange(of: runtime.practicePrayer?.isCompleted) { _, done in
            if done == false { runtime.event(.unmarked) }
        }
    }

    private func nextLabel(_ step: TourStep, insight: Bool) -> String {
        if step == .settings && insight { return "Done" }
        if step == .map { return "Got it" }
        return insight ? "Continue" : "Next"
    }

    /// Words in place of the step's own: where the action can't happen right now.
    private func override(_ step: TourStep) -> (String, String)? {
        switch step {
        case .qibla where compass.status != .ok && runtime.ticked.isEmpty && !runtime.completing:
            return ("Face the qibla", "Your compass needs a moment: move the phone in a figure 8, or tap Next.")
        default:
            return nil
        }
    }

    /// Where the bubble's bottom goes on the list steps: above the list, over the circle — never over the rows (audit J).
    private func aboveY(_ step: TourStep) -> CGFloat? {
        let onList = step.aboutTheList || (step == .list && sharedState.navPosition == .bottom)
        guard onList else { return nil }
        return TourTargets.shared.frame("prayerList")?.minY
    }

    /// What a step points at.
    private func target(_ step: TourStep) -> String? {
        switch step {
        case .mark: "prayerDot.Asr"
        case .undo: "prayerDot.Asr"
        case .rowTime: "prayerRow.Maghrib"
        case .markedRow: "prayerRow.Fajr"
        case .list where sharedState.navPosition == .bottom: "prayerList"
        // On the Zikr page: under its circle (the taller card with its insight sat over the circle, centred on the page).
        case .zikr where sharedState.horizontalPage == .zikr: "zikrCircle"
        case .settings where sharedState.horizontalPage == .settings: "tourAgainRow"
        case .settings: "settingsTab"
        default: step.target
        }
    }

    /// The touch each step asks for, where it goes (global): a tap, a hold or a swipe on the thing the words name.
    private func hint(_ step: TourStep) -> TouchHintSpec? {
        let t = TourTargets.shared
        let circle = t.frame("circle")
        func mid(_ r: CGRect?) -> CGPoint? { r.map { CGPoint(x: $0.midX, y: $0.midY) } }
        /// A row's time, at its trailing end.
        func time(_ name: String) -> CGPoint? { t.frame("prayerRow." + name).map { CGPoint(x: $0.maxX - 44, y: $0.midY) } }
        switch step {
        // Low in the circle, clear of its words.
        case .circle: return circle.map { .init(kind: .tap, at: CGPoint(x: $0.midX, y: $0.midY + $0.height * 0.3)) }
        // Above the bubble (which sits over the chevron), in the open page: a swipe up works anywhere there.
        case .list: return t.frame("chevron").map { .init(kind: .swipe(dx: 0, dy: -100), at: CGPoint(x: $0.midX, y: $0.minY - 175)) }
        case .rowTime: return time("Maghrib").map { .init(kind: .tap, at: $0) }
        case .mark:
            if !runtime.ticked.contains(0) { return mid(t.frame("prayerDot.Asr")).map { .init(kind: .tap, at: $0) } }
            // The pill's ✕ sits on its top right corner.
            return t.frame("pill").map { .init(kind: .tap, at: CGPoint(x: $0.maxX - 25, y: $0.minY + 20)) }
        case .fold: return mid(t.frame("doneFold")).map { .init(kind: .tap, at: $0) }
        case .markedRow: return time("Fajr").map { .init(kind: .tap, at: $0) }
        case .edit:
            guard !runtime.ticked.contains(0) else { return nil }   // the editor's own tip takes it from there
            return t.frame("prayerRow.Fajr").map { .init(kind: .hold, at: CGPoint(x: $0.midX, y: $0.midY)) }
        case .undo: return mid(t.frame("prayerDot.Asr")).map { .init(kind: .tap, at: $0) }
        case .zikr:
            guard sharedState.horizontalPage == .main else { return nil }
            return circle.map { .init(kind: .swipe(dx: 170, dy: 0), at: CGPoint(x: $0.minX - 20, y: $0.minY - 56)) }
        case .settings:
            guard sharedState.horizontalPage != .settings else { return nil }
            return mid(t.frame("settingsTab")).map { .init(kind: .tap, at: $0) }
        // The qibla arrow sits on the circle's upper right.
        case .map: return circle.map { .init(kind: .tap, at: CGPoint(x: $0.midX + $0.width * 0.315, y: $0.midY - $0.height * 0.235)) }
        case .colors, .qibla, .celebrate, .hintMark: return nil
        }
    }

    /// Back to where `step` happens: its page, and the list open or closed as it needs.
    private func returnTo(_ step: TourStep) {
        let page: SharedStateClass.HorizontalPage = switch step {
        case .zikr: runtime.ticked.contains(0) ? .zikr : .main
        case .settings: runtime.ticked.contains(0) ? .settings : .zikr
        default: .main
        }
        sharedState.go(to: page)
        if let wanted = sheetPosition(step), sharedState.navPosition != wanted {
            withAnimation(CircleMotion.page) { sharedState.navPosition = wanted }
        }
    }

    /// Where the list must be for a step (nil: either).
    private func sheetPosition(_ step: TourStep?) -> SharedStateClass.ViewPosition? {
        switch step {
        case .circle, .colors, .qibla: .main
        case .rowTime, .mark, .fold, .markedRow, .edit, .undo: .bottom
        default: nil
        }
    }

    private func onItsPage(_ step: TourStep) -> Bool {
        let page = sharedState.horizontalPage, list = sharedState.navPosition
        switch step {
        case .circle, .colors, .qibla: return page == .main && list == .main
        case .list: return page == .main && (list == .main || runtime.ticked.contains(0))
        case .rowTime, .mark, .fold, .markedRow, .edit, .undo, .hintMark: return page == .main && list == .bottom
        case .zikr: return page == .main || page == .zikr
        case .settings: return page == .zikr || page == .settings
        case .celebrate, .map: return page == .main
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

/// Skip tour (owner: "a double tap confirmation … like how our finish early buttons are"): the first tap arms it —
/// "✓ Tap again to skip" in sage, growing leftwards — the second skips; it lets go after 3 s.
struct TourSkipButton: View {
    let action: () -> Void
    @State private var armed = false
    @State private var token = 0

    var body: some View {
        Button {
            if armed {
                triggerSomeVibration(type: .medium)
                armed = false
                action()
            } else {
                triggerSomeVibration(type: .light)
                token += 1
                let mine = token
                armed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // an input timeout, not a motion
                    if mine == token { armed = false }
                }
            }
        } label: {
            // Armed, its words are the button: the whole sage capsule takes the second tap (an overlay didn't).
            ZStack(alignment: .trailing) {
                Text("Skip tour")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .opacity(armed ? 0 : 1)
                if armed {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        Text("Tap again to skip").font(.system(.footnote, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.sage))
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                }
            }
            .animation(.snappy(duration: 0.25), value: armed)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(armed ? "Tap again to skip the tour" : "Skip tour")
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
            Text("You skipped the tour")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            Text("Take it any time: Settings → Show me around again.")
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

#if DEBUG
/// Decision onboarding-start's A (Ben's audit L), drawn for its picture: the tour's look, no ring, no to-dos.
struct TourInviteMock: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Want a quick look around?")
                    .font(.system(.body, design: .rounded, weight: .regular))
                Text("Two minutes, on a practice prayer — nothing you do here is saved. You can run it again any time from Settings.")
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Later")
                    .font(.system(.footnote, design: .rounded, weight: .regular))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
                Text("Show me")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(TourInk.green))
            }
        }
        .padding(18)
        .tourBubble(RoundedRectangle(cornerRadius: 22, style: .continuous),
                    look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
    }
}
#endif

/// "Back to the tour ›": shown when something took the page away from the tour's step.
struct BackToTourPill: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Back to the tour")
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
        let done = Set([runtime.ticked.contains(1) ? 0 : nil, runtime.ticked.contains(2) ? 1 : nil].compactMap { $0 })
        VStack(alignment: .leading, spacing: 8) {
            Text("Fajr was marked late")
                .font(.system(.body, design: .rounded, weight: .regular))
            Text("Drag the colour bar, or pick a time in the yellow.")
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TourChecklist(tasks: ["Pick a time in the yellow", "Save"], ticked: done)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.tertiarySystemFill)))
        .accessibilityElement(children: .contain)
    }
}
