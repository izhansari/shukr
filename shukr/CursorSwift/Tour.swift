import SwiftUI
import TipKit

/// The first-run tour on the live app (owner, ask onboarding-tour: "a little gentle onboarding once users get past set up
/// … not stand alone sheets, like acc interactive on the real app"; Ben's brief board/brief-frank-onboarding-tour.md).
/// Coach marks: a dim with a clear cut-out round the real control, one line beside it, the step ending on the real action.
/// The dim takes no touches, so the control under the cut-out (and everything else) works as usual.
enum TourStep: String, CaseIterable, Identifiable {
    case circle, hold, list, swipe, count, hintMark
    var id: String { rawValue }

    /// The measured frame it points at (TourTargets), or nil for a page-wide step.
    var target: String? {
        switch self {
        case .circle, .hold: "circle"
        case .list: "chevron"
        case .swipe: nil
        case .count: "zikrCircle"
        case .hintMark: "prayerDot."
        }
    }
    var words: String {
        switch self {
        case .circle: "This is your prayer. Tap the circle to flip between when it ends and how long is left."
        case .hold: "Hold the circle to mark your prayer prayed."
        case .list: "Swipe up for today's prayers."
        case .swipe: "Swipe right for your zikr."
        case .count: "Tap the circle to count. Your daily tasks live round it."
        case .hintMark: "Tap the dot to mark it prayed. Hold it to change the time."
        }
    }
    /// The callout's two lines (style .callout): a short headline and a quiet line under it.
    var headline: String {
        switch self {
        case .circle: "Tap your prayer"
        case .hold: "Hold your prayer"
        case .list: "Swipe up"
        case .swipe: "Swipe right"
        case .count: "Tap to count"
        case .hintMark: "Tap the dot"
        }
    }
    var subline: String {
        switch self {
        case .circle: "It flips between when it ends and the time left."
        case .hold: "That marks it prayed. Try it: this one's practice, we'll undo it."
        case .list: "Today's prayers are under the circle."
        case .swipe: "Your zikr and daily tasks are there."
        case .count: "Your daily tasks live round it."
        case .hintMark: "to mark it prayed. Hold it to change the time."
        }
    }
    var symbol: String {
        switch self {
        case .circle, .count, .hintMark: "hand.tap"
        case .hold: "hand.point.up.left.fill"
        case .list: "arrow.up"
        case .swipe: "arrow.right"
        }
    }
    /// The tour's place ("2 of 4"); nil for a one-time hint.
    var place: (Int, Int)? {
        switch self {
        case .circle: (1, 5)
        case .hold: (2, 5)
        case .list: (3, 5)
        case .swipe: (4, 5)
        case .count: (5, 5)
        case .hintMark: nil
        }
    }
    /// A round cut-out (the circles, the dot) or a capsule (the chevron).
    var roundHole: Bool { self != .list }
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
    /// No action can end the step right now (Hold with no prayer in its window): a "Next" instead.
    var showsNext = false
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
    var onNext: () -> Void = {}
    var onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @State private var shown = false
    /// The ring round the control drawing once, like the prayer ring filling (Sami), 0…1.
    @State private var drawn = 0.0

    var body: some View {
        let center = hole.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height * 0.45)
        let radius = hole.map { max($0.width, $0.height) / 2 } ?? 60
        // Below the control when there's room, else above it.
        let below = hole.map { size.height - $0.maxY > 230 } ?? true
        ZStack(alignment: .topLeading) {
            // The spotlight: the page washes out a little away from the control, in the page's own colour (no grey).
            RadialGradient(colors: [.clear, .clear, theme.backdrop.opacity(0.45)],
                           center: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)),
                           startRadius: 0, endRadius: max(size.width, size.height) * 0.75)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
            // A thin green ring drawing once round the control, in the prayer ring's own stroke (Sami: "like the ring
            // filling, not a pulse").
            if hole != nil {
                Group {
                    if step.roundHole {
                        Circle().trim(from: 0, to: drawn)
                            .stroke(Color(.systemGreen), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: radius * 2, height: radius * 2)
                    } else {
                        Capsule().trim(from: 0, to: drawn)
                            .stroke(Color(.systemGreen), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: (hole?.width ?? 0) + 8, height: (hole?.height ?? 0) + 4)
                    }
                }
                .position(center)
                .allowsHitTesting(false)
            }
            bubble(below: below)
                .frame(width: min(size.width - 48, 300))
                .scaleEffect(shown ? 1 : 0.6, anchor: below ? .top : .bottom)
                .opacity(shown ? 1 : 0)
                .position(x: size.width / 2, y: bubbleY(below: below, center: center, radius: radius))
        }
        .task {
            // The control first (its ring draws), then the bubble rises out of the page beside it.
            withAnimation(.easeInOut(duration: 0.9)) { drawn = 1 }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = true }
        }
    }

    private func bubbleY(below: Bool, center: CGPoint, radius: CGFloat) -> CGFloat {
        let h: CGFloat = 118
        guard let hole else { return size.height * 0.62 }
        return below ? hole.maxY + 14 + h / 2 : hole.minY - 14 - h / 2
    }

    private func bubble(below: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: step.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color(.systemGreen))
                    .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.9)), isActive: true)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(override?.0 ?? step.headline).font(.system(size: 17, weight: .semibold))
                    Text(override?.1 ?? (showsNext ? "When a prayer's time comes, hold the circle to mark it prayed." : step.subline))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if let place = step.place {
                    HStack(spacing: 5) {
                        ForEach(1...place.1, id: \.self) { i in
                            Circle().fill(i == place.0 ? Color(.systemGreen) : Color(.tertiaryLabel))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                Spacer()
                if override == nil {
                    Button("Not now", action: onSkip).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                }
                if showsNext && override == nil {
                    Button("Next", action: onNext).font(.footnote.weight(.semibold)).foregroundStyle(Color(.systemGreen))
                        .padding(.leading, 12)
                }
            }
            .padding(.leading, 42)
        }
        .padding(16)
        .background(
            // A soft pebble in the page's own colour, raised with the app's shadows (dark below-right, light above-left).
            BubbleShape(tailUp: below)
                .fill(theme.backdrop)
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.14), radius: 12, x: 5, y: 7)
                .shadow(color: .white.opacity(scheme == .dark ? 0.06 : 0.9), radius: 8, x: -4, y: -4)
        )
        .fontDesign(.rounded)
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
/// we gotta teach long pressing on the main circle too"): five steps, each ended by the real action — tap the circle
/// (flip), hold it (mark: practice, undone straight after), swipe up (the list), swipe right (Zikr), tap to count. It
/// starts once after the first-run setup (the welcome done), or from Settings → Show me around again.
@MainActor @Observable final class TourRuntime {
    static let shared = TourRuntime()
    static let doneKey = "tour.v1.done"
    /// Set when the first-run setup finishes: the tour starts once the welcome has played.
    static let pendingKey = "tour.v1.pending"
    static let start = Notification.Name("shukr.tour.start")

    private(set) var step: TourStep?
    /// After the practice mark: "That's it — undone" for a moment.
    private(set) var practiceNote = false
    /// Bumped when a practice mark has been undone (the page clears the post-salah pill it brought).
    private(set) var undone = 0

    enum Event { case circleTapped, held(PrayerModel, PrayerViewModel), next, listOpened, zikrPage, sessionStarted }

    func begin() {
        practiceNote = false
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = .circle }
    }

    func skip() { finish() }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
    }

    func event(_ e: Event) {
        guard let step else { return }
        switch (step, e) {
        case (.circle, .circleTapped): go(to: .hold)
        case (.hold, .held(let prayer, let viewModel)): practice(prayer, viewModel)
        case (.hold, .next): go(to: .list)
        case (.list, .listOpened): go(to: .swipe)
        case (.swipe, .zikrPage): go(to: .count)
        case (.count, .sessionStarted): finish()
        default: break
        }
    }

    /// Out, then in: the bubble goes, then the next one comes at the next control.
    private func go(to next: TourStep) {
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            guard UserDefaults.standard.bool(forKey: Self.doneKey) == false else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = next }
        }
    }

    /// The practice mark: the flourish plays as usual, then it's undone (owner: "ideally it's all a test and it undoes
    /// it") and the post-salah pill it brought is cleared.
    private func practice(_ prayer: PrayerModel, _ viewModel: PrayerViewModel) {
        practiceNote = true
        Task {
            try? await Task.sleep(for: .seconds(2.6))   // the completion flourish
            if prayer.isCompleted { viewModel.togglePrayerCompletion(for: prayer) }
            undone += 1
            try? await Task.sleep(for: .seconds(1.8))
            practiceNote = false
            go(to: .list)
        }
    }
}

/// The tour's layer over the pager: the callout for the current step, only on the page it belongs to and only when
/// nothing covers the app. Watches the real state changes that end the steps.
struct TourLayer: View {
    let covered: Bool
    @Environment(SharedStateClass.self) private var sharedState
    @EnvironmentObject private var viewModel: PrayerViewModel
    private var runtime: TourRuntime { TourRuntime.shared }

    var body: some View {
        ZStack {
            if let step = runtime.step, !covered, onItsPage(step) {
                let noPrayerNow = step == .hold && (viewModel.relevantPrayer.map { $0.status() == .upcoming || $0.isCompleted } ?? true)
                TourOverlay(step: step, style: .callout,
                            override: step == .hold && runtime.practiceNote ? ("That's it", "It was practice, so we'll undo it in a moment.") : nil,
                            showsNext: noPrayerNow && !runtime.practiceNote,
                            onNext: { runtime.event(.next) },
                            onSkip: { runtime.skip() })
                    .id(step)
            }
        }
        .onChange(of: sharedState.navPosition) { _, position in
            if position == .bottom { runtime.event(.listOpened) }
        }
        .onChange(of: sharedState.horizontalPage) { _, page in
            if page == .zikr { runtime.event(.zikrPage) }
        }
    }

    private func onItsPage(_ step: TourStep) -> Bool {
        switch step {
        case .count: sharedState.horizontalPage == .zikr
        case .circle, .hold, .list: sharedState.horizontalPage == .main && sharedState.navPosition == .main
        case .swipe: sharedState.horizontalPage == .main
        case .hintMark: sharedState.horizontalPage == .main && sharedState.navPosition == .bottom
        }
    }
}
