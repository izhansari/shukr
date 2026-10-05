import SwiftUI
import TipKit

/// The first-run tour on the live app (owner, ask onboarding-tour: "a little gentle onboarding once users get past set up
/// … not stand alone sheets, like acc interactive on the real app"; Ben's brief board/brief-frank-onboarding-tour.md).
/// Coach marks: a dim with a clear cut-out round the real control, one line beside it, the step ending on the real action.
/// The dim takes no touches, so the control under the cut-out (and everything else) works as usual.
enum TourStep: String, CaseIterable, Identifiable {
    case circle, colors, qibla, list, rowTime, mark, pill, fold, markedRow, edit, swipe, count, celebrate, map, hintMark
    var id: String { rawValue }

    /// The measured frame it points at (TourTargets), or nil for a page-wide step.
    var target: String? {
        switch self {
        case .circle, .colors, .qibla, .celebrate, .map: "circle"
        case .edit: "prayerRow."   // + the practice prayer's name (TourLayer): the words say hold the row
        case .fold: "doneFold"
        case .pill: "pill"
        case .rowTime, .markedRow: "prayerRow."   // + the row's name (TourLayer)
        case .list: "chevron"
        case .mark: "prayerDot."   // + the current prayer's name, or the circle when none is due (TourLayer)
        case .swipe: nil
        case .count: "zikrCircle"
        case .hintMark: "prayerDot."
        }
    }
    var words: String {
        switch self {
        case .circle: "This is your prayer. Tap the circle to flip between when it ends and how long is left."
        case .mark: "Tap your prayer's dot, or hold the circle, to mark it prayed."
        case .colors: "The ring's colour is the score you'd get if you prayed now."
        case .edit: "Hold a marked prayer's row to change when or where you prayed."
        case .fold: "Tap N done to show or hide your marked prayers."
        case .qibla: "Turn until the arrow on the circle points straight up: that's the qibla."
        case .rowTime: "Tap a coming prayer's time to see how long until it starts."
        case .pill: "After each prayer, the pill offers Tasbih Fatimah."
        case .markedRow: "Tap a marked prayer's time to see when you prayed and your score."
        case .celebrate: "Your first prayer, marked."
        case .map: "Tap the arrow on the circle for the map."
        case .list: "Swipe up for today's prayers."
        case .swipe: "Swipe right for your zikr."
        case .count: "Tap the circle to count. Your daily tasks live round it."
        case .hintMark: "Tap the dot to mark it prayed. Hold it to change the time."
        }
    }
    /// The callout's two lines (style .callout): a short headline and a quiet line under it.
    var headline: String {
        switch self {
        case .circle: "Your prayer"
        case .mark: "Mark your prayer"
        case .colors: "Green, yellow, red"
        case .edit: "Fix a marked prayer"
        case .fold: "Your marked prayers"
        case .qibla: "Face the qibla"
        case .rowTime: "How long until it starts"
        case .pill: "After each prayer"
        case .markedRow: "Your time and score"
        case .celebrate: "Your first prayer, marked"
        case .map: "See where you prayed"
        case .list: "Today's prayers"
        case .swipe: "Your zikr"
        case .count: "Start counting"
        case .hintMark: "Tap the dot"
        }
    }
    var subline: String {
        switch self {
        case .circle: "This is a practice prayer: nothing here is saved."
        case .mark: "It's the practice prayer, so nothing is saved."
        case .colors: "The ring's colour is the score you'd get if you prayed now. Grey: missed."
        // The owner's own example (audit E20).
        case .edit: "Say you prayed Fajr but forgot to mark it. No worries: mark it now, then fix the time, and even the place."
        case .fold: "Marked prayers tuck under \u{201C}done\u{201D}."
        case .qibla: "The small arrow on the circle turns green when you face it."
        case .rowTime: "A coming prayer's time can show how long is left."
        case .pill: "It offers Tasbih Fatimah (33 · 33 · 34) after you pray."
        case .markedRow: "A marked prayer shows when you prayed and your score."
        case .celebrate: "Keep it up — every prayer you mark grows your streak."
        case .map: "Every prayer you mark is on the map, under Explore → Prayers."
        case .list: "They're under the circle."
        case .swipe: "Your zikr and daily tasks are on the next page."
        // The tour ends before anything real is written (audit A2): the next tap starts a real session.
        case .count: "Tap the circle when you're ready: this one's real, and saved to your history."
        case .hintMark: "to mark it prayed. Hold it to change the time."
        }
    }
    /// The step's to-dos (owner: "like to do list bullets and then marked done when event has been triggered"): each is
    /// ticked by the real action, and the step moves on only once they all are.
    var tasks: [String] {
        switch self {
        case .circle: ["Tap the circle: time left", "Tap again: when it ends"]
        case .colors: ["Green: the first 30 minutes", "Yellow: on time", "Red: late"]
        case .qibla: ["Turn until the arrow points up"]
        case .list: ["Swipe up"]
        case .rowTime: ["Tap a coming prayer's time"]
        case .mark: ["Tap its dot, or hold the circle"]
        case .pill: ["Tap \u{2715} to close it for now"]
        case .fold: ["Tap \u{201C}done\u{201D} to show them", "Tap it again to hide them"]
        case .markedRow: ["Tap a marked prayer's time"]
        // Undo is the third (owner: "you can move that step into the other tooltip since they're all about editing
        // marked prayers").
        case .edit: ["Hold its row", "Close it", "Marked by mistake? Tap its dot, then Yes"]
        case .swipe: ["Swipe right"]
        case .map: ["Tap the arrow on the circle"]
        case .celebrate, .count, .hintMark: []
        }
    }
    var symbol: String {
        switch self {
        case .circle, .count, .hintMark: "hand.tap"
        case .mark: "checkmark.circle"
        case .colors: "circle.lefthalf.filled"
        case .edit: "clock.arrow.circlepath"
        case .fold: "checkmark.circle"
        case .qibla: "location.north.line"
        case .rowTime: "hourglass"
        case .pill: "circle.dotted.circle"
        case .markedRow: "checkmark.seal"
        case .celebrate: "sparkles"
        case .map: "map"
        case .list: "arrow.up"
        case .swipe: "arrow.right"
        }
    }
    /// The tour's place ("2 of 4"); nil for a one-time hint.
    var place: (Int, Int)? {
        switch self {
        case .circle: (1, 12)
        case .colors: (2, 12)
        case .qibla: (3, 12)
        case .list: (4, 12)
        case .rowTime: (5, 12)
        case .mark: (6, 12)
        case .pill: (7, 12)
        case .fold: (8, 12)
        case .markedRow: (9, 12)
        case .edit: (10, 12)
        case .swipe: (11, 12)
        case .count: (12, 12)
        case .celebrate, .map, .hintMark: nil
        }
    }
    /// A round cut-out (the circles, the dot) or a capsule (the chevron).
    var roundHole: Bool { ![.list, .fold, .pill, .rowTime, .markedRow, .edit].contains(self) }
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
    /// The touch to show (global).
    var hint: TouchHintSpec? = nil
    var onNext: () -> Void = {}
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
                                hint: hint.map { TouchHintSpec(kind: $0.kind, at: CGPoint(x: $0.at.x - origin.x, y: $0.at.y - origin.y)) },
                                onNext: onNext, onSkip: onSkip)
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
        }
        .task {
            // `-tourStart [-tourStartAfter s]`: the real tour, as Settings → Show me around again starts it.
            if ProcessInfo.processInfo.arguments.contains("-tourStart") {
                let wait = UserDefaults.standard.double(forKey: "tourStartAfter")
                try? await Task.sleep(for: .seconds(wait > 0 ? wait : 3))
                NotificationCenter.default.post(name: TourRuntime.start, object: nil)
                return
            }
            if TourHintDemo.hint != nil || TourHintDemo.tip != nil {
                try? await Task.sleep(for: .seconds(1.5))
                TourHintDemo.start(sharedState)
                return
            }
            guard let raw = UserDefaults.standard.string(forKey: "demoTour"), let wanted = TourStep(rawValue: raw) else { return }
            try? await Task.sleep(for: .seconds(2))
            if wanted == .count { sharedState.horizontalPage = .zikr }
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

/// Round 3 (owner: "too subtle … not a fan of the stock apple tool tip"; Bradley's four changes): a shukr-made callout.
/// A light spotlight (the rest of the page washes out a little, never grey), the control glowing twice, and a soft raised
/// bubble that grows out of the control's edge with a soft tail: the gesture moving inside it, a headline and a quiet
/// line, three dots for the tour's place and "Not now".
struct TourCallout: View {
    let step: TourStep
    let hole: CGRect?
    let size: CGSize
    var override: (String, String)? = nil
    var showsNext = false
    var place: (Int, Int)? = nil
    /// The step's to-dos and which are done (TourRuntime.ticked).
    var tasks: [String] = []
    var ticked: Set<Int> = []
    /// The touch to show, in this view's space.
    var hint: TouchHintSpec? = nil
    var onNext: () -> Void = {}
    var onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @State private var shown = false
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The bubble's own height, measured (it grows with the to-dos).
    @State private var bubbleHeight: CGFloat = 130

    var body: some View {
        let center = hole.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height * 0.45)
        let radius = hole.map { max($0.width, $0.height) / 2 } ?? 60
        // Below the control when there's room, else above it.
        let below = hole.map { size.height - $0.maxY > bubbleHeight + 60 } ?? true
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
            bubble(below: below)
                // Larger text gets the screen's width (audit C13); the bubble is measured and kept on screen (bubbleY).
                .frame(width: typeSize >= .xxLarge ? size.width - 32 : min(size.width - 48, 300))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bubbleHeight = $0 }
                .scaleEffect(shown || reduceMotion ? 1 : 0.6, anchor: below ? .top : .bottom)
                .opacity(shown ? 1 : 0)
                .position(x: size.width / 2, y: bubbleY(below: below, center: center, radius: radius))
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

    private func bubbleY(below: Bool, center: CGPoint, radius: CGFloat) -> CGFloat {
        let h = bubbleHeight
        let wanted: CGFloat
        if let hole {
            wanted = below ? hole.maxY + 14 + h / 2 : hole.minY - 14 - h / 2
        } else {
            wanted = size.height * 0.62
        }
        // Never off the screen, nor under the status bar or the home indicator (a tall bubble, large text, a small phone).
        let top: CGFloat = 64 + h / 2, bottom = size.height - 24 - h / 2
        return bottom > top ? min(max(wanted, top), bottom) : size.height / 2
    }

    private func bubble(below: Bool) -> some View {
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
            if !tasks.isEmpty {
                TourChecklist(tasks: tasks, ticked: ticked)
                    .padding(.leading, 40)
            }
            HStack {
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
                if override == nil && place != nil && step != .count {   // the last step: Done is the way out
                    Button("Not now", action: onSkip)
                        .buttonStyle(.plain)
                        .font(.system(.footnote, design: .rounded, weight: .regular))
                        .foregroundStyle(Color(.secondaryLabel)).fixedSize()
                }
                if showsNext && override == nil {
                    Button(step == .map ? "Got it" : step == .count ? "Done" : "Next", action: onNext)
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
        .tourBubble(BubbleShape(tailUp: below), look: TourBubbleLook(rawValue: lookRaw) ?? .glass,
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
                        .foregroundStyle(done ? Color.secondary : Color.primary)
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
        }
    }
}

/// A rounded bubble with a soft tail at the top or bottom centre (no hard triangle: the tail's sides are curves).
struct BubbleShape: Shape {
    var tailUp: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22, tw: CGFloat = 30, th: CGFloat = 10
        var p = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        let mid = rect.midX
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

/// The tour itself (owner: "throw it on my phone so i can try it … i also don't want for a user to mark real prayers …
/// we gotta teach long pressing on the main circle too"; then "why dont you show them how to undo it … what if they load
/// the app at a time theres no prayer?"). Each step ends on the real action: tap the circle (flip) · hold it (a mark) ·
/// swipe up (the list) · undo it (the mark's dot → Unmark) · swipe right (Zikr) · tap to count.
/// The hold is practice either way: with a prayer in its window it's a real mark, undone by the user in the next step
/// (and by the tour itself if they leave first); with none (after sunrise, after midnight) it's the mark's preview —
/// the flourish, nothing written — and the undo step is left out.
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
    /// After the hold: "That's it" for a moment.
    private(set) var practiceNote: (String, String)?
    /// The prayer the practice marked for real (the undo step points at its dot; undone if the tour ends first).
    private(set) var practicePrayer: PrayerModel?
    @ObservationIgnored private weak var practiceViewModel: PrayerViewModel?
    /// Bumped when the practice's post-salah pill should go (the page clears it).
    private(set) var clearPill = 0
    /// The current step's to-dos that are done (indexes into its `tasks`).
    private(set) var ticked: Set<Int> = []
    /// Every to-do is done: the bubble stays a moment, wherever the action took the page, then the next step.
    private(set) var completing = false
    /// Between begin() and finish(), gaps between steps included: events then belong to the tour, never to the
    /// "first real mark" outside it (audit A7); the pager and the list are held (audit E17).
    private(set) var active = false
    /// When the current step came up: none ends sooner than `minimumDwell` after it (audit E18).
    @ObservationIgnored private var shownAt = Date()
    static let minimumDwell: TimeInterval = 2.5
    /// The ✓ stays this long before the next step: do → acknowledged → next, the same for every step.
    static let acknowledge: TimeInterval = 1.5
    /// How often the tour has started from the first-run setup: a kill mid-tour resumes it once (audit A3).
    static let startedKey = "tour.v1.started"

    /// The pager stays on the step's page; only the swipe step pages (audit E17).
    /// Once the swipe is ticked it locks too: swiping straight back during its ✓ left the count step hidden on Salah with
    /// the pager held (Ben's G4).
    var locksPager: Bool { active && !(step == .swipe && !completing) }

    /// The post-salah pill is on the page (its step ticks at once if it's already gone — Ben's G3).
    @ObservationIgnored var pillVisible = false

    /// Whether a mark or an unmark may happen now (Ben's G1 / G2). Outside the tour, always. In it, only the practice
    /// day's own moves: a mark on the mark step; Asr's undo as "Fix a marked prayer"'s third to-do.
    func allows(marking: Bool, _ prayer: PrayerModel) -> Bool {
        guard active else { return true }
        if marking { return step == .mark && ticked.isEmpty }
        return step == .edit && prayer === practicePrayer && ticked.isSuperset(of: [0, 1])
    }
    /// The list stays open or closed as the step needs; only the list step opens it (audit E17).
    var holdsSheet: Bool { active && step != .list }
    /// Which run of the tour this is: a step scheduled by an earlier run (or after Not now) never shows.
    @ObservationIgnored private var run = 0
    /// The tour runs on a pretend day (owner: "Ideally this whole thing happens with a dummy prayer with dummy data … so
    /// there's always a prayer for them to see and we can manipulate the progress ring"): five prayers never saved — Fajr
    /// and Dhuhr done, Asr in its window now, Maghrib and Isha to come. The view model shows it instead of today while
    /// the tour runs (`loadTodaysPrayerObjects`); marking, undoing and editing these touch nothing real.
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
    private static let practiceWindow: TimeInterval = 180 * 60

    private func startPractice() {
        let now = Date()
        func make(_ name: String, from minutes: Double, for length: Double, done: Bool) -> PrayerModel {
            let p = PrayerModel(name: name, startTime: now.addingTimeInterval(minutes * 60),
                                endTime: now.addingTimeInterval((minutes + length) * 60))
            if done {
                p.isCompleted = true
                p.setPrayerScore(atDate: p.startTime.addingTimeInterval(12 * 60))
            }
            return p
        }
        practiceDay = Self.practicePlan.map { make($0.name, from: $0.from, for: $0.length, done: $0.done) }
        viewModel?.loadTodaysPrayerObjects()
    }

    /// The practice day, in minutes from now: Fajr and Dhuhr done, Asr just begun, Maghrib and Isha to come.
    private static let practicePlan: [(name: String, from: Double, length: Double, done: Bool)] = [
        ("Fajr", -600, 90, true), ("Dhuhr", -300, 180, true), ("Asr", -5, 180, false),
        ("Maghrib", 190, 75, false), ("Isha", 280, 120, false)]

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
    }

    /// Asr's place in its window, as a share of it (its start moved back; the window keeps its length).
    private func setPracticeProgress(_ share: Double) {
        guard let asr = practiceAsr else { return }
        let start = Date().addingTimeInterval(-share * Self.practiceWindow)
        withAnimation(.easeInOut(duration: 0.9)) {
            asr.startTime = start
            asr.endTime = start.addingTimeInterval(Self.practiceWindow)
        }
    }

    /// The colours step: the practice ring goes green → yellow → red, each ticked off as the ring gets there, then on.
    private func playColors(run thisRun: Int) {
        Task {
            // The bubble comes first (go(to:) waits 0.45 s), then each colour.
            try? await Task.sleep(for: .seconds(1.2))
            for (i, share) in [0.06, 0.4, 0.85].enumerated() {
                guard run == thisRun, step == .colors else { return }
                setPracticeProgress(share)
                try? await Task.sleep(for: .seconds(1.0))   // the ring's move (0.9 s), then its tick
                guard run == thisRun, step == .colors else { return }
                tick(i)
                try? await Task.sleep(for: .seconds(1.1))
            }
            guard run == thisRun else { return }
            setPracticeProgress(5 * 60 / Self.practiceWindow)   // back to just begun (green) for the mark
        }
    }

    /// One to-do done (the green ✓). With all of the step's done: a moment to see it, then `then` (the next step).
    private func tick(_ i: Int, of count: Int? = nil, then: (() -> Void)? = nil) {
        guard let step, !completing, !ticked.contains(i) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = ticked.insert(i) }
        guard ticked.count >= (count ?? step.tasks.count) else { return }
        completing = true
        let thisRun = run
        let wait = max(Self.acknowledge, Self.minimumDwell - Date().timeIntervalSince(shownAt))
        Task {
            try? await Task.sleep(for: .seconds(wait))
            guard run == thisRun, self.step == step else { return }
            (then ?? { self.advance(from: step) })()
        }
    }

    /// The next to-do not yet done (steps whose to-dos are done in order).
    private func tickNext(then: (() -> Void)? = nil) {
        guard let step, let i = step.tasks.indices.first(where: { !ticked.contains($0) }) else { return }
        tick(i, then: then)
    }

    /// The step after `step` in this run's list.
    private func advance(from step: TourStep) {
        switch step {
        case .count: finish()
        case .map: withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }
        case .colors: go(to: .qibla)
        case .fold:
            if steps.contains(.markedRow) {
                // The next steps need the marked row in view.
                if !PrayerListFold.shared.showDone { PrayerListFold.shared.showDone = true }
                go(to: .markedRow)
            } else {
                go(to: .swipe)
            }
        default:
            guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { finish(); return }
            go(to: steps[i + 1])
        }
    }

    /// The tour's steps this time (no undo after a preview).
    private(set) var steps: [TourStep] = TourRuntime.allSteps
    static let allSteps: [TourStep] = [.circle, .colors, .qibla, .list, .rowTime, .mark, .pill, .fold, .markedRow, .edit, .swipe, .count]
    /// The first real mark gets a celebration (and then the map), once — armed by the first-run setup or by Show me
    /// around again, so someone already using the app never gets it out of the blue.
    static let celebrateArmedKey = "tour.firstMark.armed"

    enum Event {
        case circleTapped, listOpened, zikrPage, sessionStarted, unmarked, mapOpened, editorOpened, foldToggled, qiblaAligned, next
        case comingRowTapped, markedRowTapped, pillGone, editorClosed
        /// A real mark (the circle held, or a dot tapped), or the mark's preview when no prayer is due.
        case marked(PrayerModel, PrayerViewModel), markedPreview(PrayerViewModel)
    }

    func place(of step: TourStep) -> (Int, Int)? {
        steps.firstIndex(of: step).map { ($0 + 1, steps.count) }
    }

    func begin() {
        practiceNote = nil
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
        ticked = []
        completing = false
        shownAt = Date()
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = .circle }
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
        undoPracticeIfLeft()
        endPractice()
        ticked = []
        completing = false
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
    }

    /// The practice mark never stays: left marked when the tour ends, the tour undoes it.
    private func undoPracticeIfLeft() {
        if let prayer = practicePrayer, !isPractice(prayer), prayer.isCompleted, let viewModel = practiceViewModel {
            viewModel.togglePrayerCompletion(for: prayer)
            clearPill += 1
        }
        practicePrayer = nil
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
        // Each step moves on only once its to-dos are all done, each ticked by its real action (owner: "it doesn't let
        // us progress until the user does exactly that … then we show it's been done in the tooltip").
        case (.circle, .circleTapped):
            tickNext { self.go(to: .colors); self.playColors(run: self.run) }
        // Facing the qibla ends it (owner: "pointing in qibla direction will satisfy that step"); Next only when the
        // compass can't (TourLayer).
        case (.qibla, .qiblaAligned): tick(0)
        case (.qibla, .next): go(to: .list)
        case (.list, .listOpened): tick(0)
        case (.rowTime, .comingRowTapped): tick(0)
        case (.mark, .marked(let prayer, let viewModel)):
            practicePrayer = prayer
            practiceViewModel = viewModel
            // The mark's flourish plays under the ✓ first.
            tick(0) {
                let thisRun = self.run
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard self.run == thisRun else { return }
                    self.go(to: .pill)
                }
            }
        case (.mark, .markedPreview(let viewModel)):
            // A preview writes nothing: no change or undo to teach; the fold only if earlier prayers are marked.
            steps.removeAll { $0 == .edit || $0 == .pill }
            let anyDone = viewModel.todaysPrayers.contains { $0.isCompleted }
            if !anyDone { steps.removeAll { $0 == .fold || $0 == .markedRow } }
            practiceNote = ("That's it", "No prayer is due now, so that was just a preview.")
            tick(0) {
                let thisRun = self.run
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    guard self.run == thisRun else { return }
                    self.practiceNote = nil
                    self.clearPill += 1
                    self.go(to: anyDone ? .fold : .swipe)
                }
            }
        // The post-salah pill closed (✕, its own time, or tapped open): on to where the marked prayers went.
        case (.pill, .pillGone): tick(0)
        case (.fold, .foldToggled): tickNext()
        case (.markedRow, .markedRowTapped): tick(0)
        // The editor opened (a sheet over the page): ticked under it; its close ticks the second and moves on.
        case (.edit, .editorOpened): tick(0)
        case (.edit, .editorClosed) where ticked.contains(0): tick(1)
        // Undone: the third to-do (an undo before the first two is refused — `allows`).
        case (.edit, .unmarked):
            clearPill += 1
            // The dot stays pointed at while the ✓ shows; the practice prayer is let go as the step moves on.
            tick(2) { self.practicePrayer = nil; self.go(to: .swipe) }
        case (.swipe, .zikrPage): tick(0)
        case (.count, .sessionStarted), (.count, .next): finish()
        case (.celebrate, .next): go(to: .map)
        case (.map, .mapOpened): withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }
        case (.map, .next): withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }
        default: break
        }
    }

    /// Out, then in: the bubble goes, then the next one comes at the next control.
    private func go(to next: TourStep) {
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
        ticked = []
        completing = false
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            guard run == thisRun else { return }
            if next != .colors { repinPractice() }
            shownAt = Date()
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = next }
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
    private var runtime: TourRuntime { TourRuntime.shared }

    var body: some View {
        ZStack {
            // Done, it stays a moment wherever the action took the page (the list up, the Zikr page) so the ✓ is seen.
            if let step = runtime.step, !covered, onItsPage(step) || runtime.completing {
                // Once the mark is made the step keeps its words and its dot while it acknowledges (it read "No prayer
                // is due now" and jumped to the circle the moment Asr was marked).
                let marked = step == .mark && (runtime.completing || !runtime.ticked.isEmpty)
                let due = marked ? runtime.practicePrayer
                    : viewModel.relevantPrayer.flatMap { $0.status() == .current && !$0.isCompleted ? $0 : nil }
                TourOverlay(step: step, style: .callout,
                            target: target(step, due: due),
                            override: override(step, due: due),
                            // Only where no action can end it: the celebration, and a compass that can't settle.
                            showsNext: step == .celebrate || step == .count
                                || (step == .qibla && !runtime.completing && (compass.status != .ok || qiblaWaited)),
                            place: runtime.place(of: step),
                            tasks: step == .mark && due == nil && runtime.practiceNote == nil ? ["Hold the circle"] : nil,
                            ticked: runtime.ticked,
                            hint: runtime.completing ? nil : hint(step, due: due),
                            onNext: { runtime.event(.next) },
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
        .onChange(of: sharedState.horizontalPage) { _, page in
            if page == .zikr { runtime.event(.zikrPage) }
        }
        .onAppear { runtime.viewModel = viewModel }
        // VoiceOver says each step as it comes, and each to-do as it's done (audit C15); touches still pass through.
        .onChange(of: runtime.step) { _, step in
            guard let step else { return }
            // A to-do that's already true ticks as the step comes (Ben's G3), and the count step's page is put back.
            switch step {
            case .list where sharedState.navPosition == .bottom: runtime.event(.listOpened)
            case .swipe where sharedState.horizontalPage == .zikr: runtime.event(.zikrPage)
            case .pill where !runtime.pillVisible: runtime.event(.pillGone)
            case .count where sharedState.horizontalPage != .zikr: sharedState.go(to: .zikr)
            default: break
            }
            let todo = step.tasks.isEmpty ? "" : " To do: " + step.tasks.joined(separator: ", ") + "."
            AccessibilityNotification.Announcement("\(step.headline). \(step.subline)\(todo)").post()
        }
        .onChange(of: runtime.ticked) { old, new in
            guard let step = runtime.step, let i = new.subtracting(old).first, step.tasks.indices.contains(i) else { return }
            AccessibilityNotification.Announcement("Done: \(step.tasks[i])").post()
        }
        // Back from the background: the practice day round now again (Ben's round C).
        .onChange(of: CircleStage.shared.sceneActive) { _, active in
            if active, runtime.active, runtime.step != .colors { runtime.repinPractice() }
        }
        // The time editor closed (the edit step's second to-do).
        .onChange(of: covered) { _, isCovered in
            if !isCovered { runtime.event(.editorClosed) }
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
        // "N done" shown or hidden.
        .onChange(of: PrayerListFold.shared.showDone) { _, _ in runtime.event(.foldToggled) }
        // The practice mark undone by the user (its dot → Unmark).
        .onChange(of: runtime.practicePrayer?.isCompleted) { _, done in
            if done == false { runtime.event(.unmarked) }
        }
    }

    /// Words in place of the step's own: a note after the action, or the case where the action can't happen now.
    private func override(_ step: TourStep, due: PrayerModel?) -> (String, String)? {
        if let note = runtime.practiceNote, step == .mark { return note }
        switch step {
        case .mark where due == nil:
            return ("Mark your prayer", "No prayer is due now: holding the circle shows how it looks.")
        // Not once it's faced: turning away after the ✓ shook the compass and swapped the words in for a moment (owner:
        // "when i move it shows and other tooltip quick").
        case .qibla where compass.status != .ok && runtime.ticked.isEmpty && !runtime.completing:
            return ("Face the qibla", "Your compass needs a moment: move the phone in a figure 8, or tap Next.")
        default:
            return nil
        }
    }

    /// What a step lights: the mark step the due prayer's dot (the circle when none is due), the undo step the practice
    /// prayer's dot; the others their own.
    private func target(_ step: TourStep, due: PrayerModel?) -> String? {
        switch step {
        case .mark: due.map { "prayerDot." + $0.name } ?? "circle"
        // The row, not the dot (the dot unmarks — audit E19): Fajr's, as the words say (Sami's F2); the undo is Asr's dot.
        // Once held and closed, the tip moves to the undo's dot (it sat over Asr's row).
        case .edit: runtime.practicePrayer.map {
            runtime.ticked.isSuperset(of: [0, 1]) ? "prayerDot." + $0.name : "prayerRow." + editRow($0.name)
        }
        case .rowTime: viewModel.todaysPrayers.first { $0.startTime > Date() }.map { "prayerRow." + $0.name }
        case .markedRow: viewModel.todaysPrayers.first { $0.isCompleted }.map { "prayerRow." + $0.name }
        default: step.target
        }
    }

    /// The touch each step asks for, where it goes (global): a tap, a hold or a swipe on the thing the words name.
    private func hint(_ step: TourStep, due: PrayerModel?) -> TouchHintSpec? {
        let t = TourTargets.shared
        let circle = t.frame("circle")
        func mid(_ r: CGRect?) -> CGPoint? { r.map { CGPoint(x: $0.midX, y: $0.midY) } }
        /// A row's time, at its trailing end.
        func time(_ name: String?) -> CGPoint? {
            name.flatMap { t.frame("prayerRow." + $0) }.map { CGPoint(x: $0.maxX - 44, y: $0.midY) }
        }
        let practice = runtime.practicePrayer?.name
        switch step {
        // Low in the circle, clear of its words.
        case .circle: return circle.map { .init(kind: .tap, at: CGPoint(x: $0.midX, y: $0.midY + $0.height * 0.3)) }
        // Above the bubble (which sits over the chevron), in the open page: a swipe up works anywhere there.
        case .list: return t.frame("chevron").map { .init(kind: .swipe(dx: 0, dy: -100), at: CGPoint(x: $0.midX, y: $0.minY - 175)) }
        case .rowTime:
            return time(viewModel.todaysPrayers.first { $0.startTime > Date() }?.name).map { .init(kind: .tap, at: $0) }
        case .mark:
            if !runtime.ticked.isEmpty { return nil }
            if let due { return mid(t.frame("prayerDot." + due.name)).map { .init(kind: .tap, at: $0) } }
            return circle.map { .init(kind: .hold, at: CGPoint(x: $0.midX, y: $0.midY + $0.height * 0.3)) }
        // The pill's ✕ sits on its top right corner.
        case .pill: return t.frame("pill").map { .init(kind: .tap, at: CGPoint(x: $0.maxX - 25, y: $0.minY + 20)) }
        case .fold: return mid(t.frame("doneFold")).map { .init(kind: .tap, at: $0) }
        case .markedRow: return time(viewModel.todaysPrayers.first { $0.isCompleted }?.name).map { .init(kind: .tap, at: $0) }
        case .edit:
            guard let practice else { return nil }
            if !runtime.ticked.contains(0) {
                return t.frame("prayerRow." + editRow(practice)).map { .init(kind: .hold, at: CGPoint(x: $0.midX, y: $0.midY)) }
            }
            if runtime.ticked.contains(1) { return mid(t.frame("prayerDot." + practice)).map { .init(kind: .tap, at: $0) } }
            return nil   // the editor is up: its own buttons
        case .swipe:
            return circle.map { .init(kind: .swipe(dx: 170, dy: 0), at: CGPoint(x: $0.minX - 20, y: $0.minY - 56)) }
        case .count: return t.frame("zikrCircle").map { .init(kind: .tap, at: CGPoint(x: $0.midX, y: $0.midY + $0.height * 0.3)) }
        // The qibla arrow sits on the circle's upper right.
        case .map: return circle.map { .init(kind: .tap, at: CGPoint(x: $0.midX + $0.width * 0.315, y: $0.midY - $0.height * 0.235)) }
        case .colors, .qibla, .celebrate, .hintMark: return nil
        }
    }

    /// The row the edit step holds: Fajr (its words' example, marked on the practice day), else the practice mark.
    private func editRow(_ practice: String) -> String {
        viewModel.todaysPrayers.contains { $0.name == "Fajr" && $0.isCompleted } ? "Fajr" : practice
    }

    /// Where the list must be for a step (nil: either).
    private func sheetPosition(_ step: TourStep?) -> SharedStateClass.ViewPosition? {
        switch step {
        case .circle, .colors, .qibla: .main
        case .rowTime, .mark, .fold, .markedRow, .edit: .bottom
        default: nil
        }
    }

    private func onItsPage(_ step: TourStep) -> Bool {
        switch step {
        case .count: sharedState.horizontalPage == .zikr
        case .circle, .colors, .qibla, .list: sharedState.horizontalPage == .main && sharedState.navPosition == .main
        case .rowTime, .mark, .fold, .markedRow, .edit: sharedState.horizontalPage == .main && sharedState.navPosition == .bottom
        case .pill: sharedState.horizontalPage == .main
        case .celebrate, .map: sharedState.horizontalPage == .main
        case .swipe: sharedState.horizontalPage == .main
        case .hintMark: sharedState.horizontalPage == .main && sharedState.navPosition == .bottom
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
