import SwiftUI
import TipKit

/// The first-run tour on the live app (owner, ask onboarding-tour: "a little gentle onboarding once users get past set up
/// … not stand alone sheets, like acc interactive on the real app"; Ben's brief board/brief-frank-onboarding-tour.md).
/// Coach marks: a dim with a clear cut-out round the real control, one line beside it, the step ending on the real action.
/// The dim takes no touches, so the control under the cut-out (and everything else) works as usual.
enum TourStep: String, CaseIterable, Identifiable {
    case circle, colors, list, mark, fold, edit, undo, swipe, count, celebrate, map, hintMark
    var id: String { rawValue }

    /// The measured frame it points at (TourTargets), or nil for a page-wide step.
    var target: String? {
        switch self {
        case .circle, .colors, .celebrate, .map: "circle"
        case .edit: "prayerDot."   // + the practice prayer's name (TourLayer)
        case .fold: "doneFold"
        case .list: "chevron"
        case .mark: "prayerDot."   // + the current prayer's name, or the circle when none is due (TourLayer)
        case .undo: "prayerDot."   // + the practice prayer's name (TourLayer)
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
        case .undo: "Tap its dot, then Yes, to undo a mark."
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
        case .circle: "Tap your prayer"
        case .mark: "Mark your prayer"
        case .colors: "Green, yellow, red"
        case .edit: "Change the time or place"
        case .fold: "Show or hide them"
        case .undo: "Undo it"
        case .celebrate: "Your first prayer, marked"
        case .map: "See where you prayed"
        case .list: "Swipe up"
        case .swipe: "Swipe right"
        case .count: "Tap to count"
        case .hintMark: "Tap the dot"
        }
    }
    var subline: String {
        switch self {
        case .circle: "It flips between when it ends and the time left."
        case .mark: "Tap its dot, or hold the circle. It's practice: you'll undo it after."
        case .colors: "The ring fills as the time passes. Green: the first 30 minutes. Yellow: on time. Red: late. Grey: missed."
        case .edit: "Hold its row: you can change when or where you prayed. Close it to carry on."
        case .fold: "Marked prayers tuck under \u{201C}done\u{201D}. Tap it to see them all, again to hide them."
        case .undo: "Tap its dot, then Yes. That's how you fix a mark."
        case .celebrate: "Keep it up — every prayer you mark grows your streak."
        case .map: "Tap the small arrow at the top of the circle, then Explore → Prayers."
        case .list: "Today's prayers are under the circle."
        case .swipe: "Your zikr and daily tasks are there."
        case .count: "Your daily tasks live round it."
        case .hintMark: "to mark it prayed. Hold it to change the time."
        }
    }
    var symbol: String {
        switch self {
        case .circle, .count, .hintMark: "hand.tap"
        case .mark: "checkmark.circle"
        case .colors: "circle.lefthalf.filled"
        case .edit: "clock.arrow.circlepath"
        case .fold: "checkmark.circle"
        case .undo: "arrow.uturn.backward"
        case .celebrate: "sparkles"
        case .map: "map"
        case .list: "arrow.up"
        case .swipe: "arrow.right"
        }
    }
    /// The tour's place ("2 of 4"); nil for a one-time hint.
    var place: (Int, Int)? {
        switch self {
        case .circle: (1, 9)
        case .colors: (2, 9)
        case .list: (3, 9)
        case .mark: (4, 9)
        case .fold: (5, 9)
        case .edit: (6, 9)
        case .undo: (7, 9)
        case .swipe: (8, 9)
        case .count: (9, 9)
        case .celebrate, .map, .hintMark: nil
        }
    }
    /// A round cut-out (the circles, the dot) or a capsule (the chevron).
    var roundHole: Bool { self != .list && self != .fold }
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
                                place: place ?? step.place, onNext: onNext, onSkip: onSkip)
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
            // Not on the colours step: the prayer ring's own colour is what it explains.
            if hole != nil && step != .colors {
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
                    Text(override?.1 ?? step.subline)
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if let place {
                    HStack(spacing: 5) {
                        ForEach(1...place.1, id: \.self) { i in
                            Circle().fill(i == place.0 ? Color(.systemGreen) : Color(.tertiaryLabel))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                Spacer()
                if override == nil && place != nil {
                    Button("Not now", action: onSkip).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                }
                if showsNext && override == nil {
                    Button(step == .map ? "Got it" : "Next", action: onNext).font(.footnote.weight(.semibold)).foregroundStyle(Color(.systemGreen))
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

    private(set) var step: TourStep?
    /// After the hold: "That's it" for a moment.
    private(set) var practiceNote: (String, String)?
    /// The prayer the practice marked for real (the undo step points at its dot; undone if the tour ends first).
    private(set) var practicePrayer: PrayerModel?
    @ObservationIgnored private weak var practiceViewModel: PrayerViewModel?
    /// Bumped when the practice's post-salah pill should go (the page clears it).
    private(set) var clearPill = 0
    /// Which run of the tour this is: a step scheduled by an earlier run (or after Not now) never shows.
    @ObservationIgnored private var run = 0
    /// The tour's steps this time (no undo after a preview).
    private(set) var steps: [TourStep] = [.circle, .colors, .list, .mark, .fold, .edit, .undo, .swipe, .count]
    /// The first real mark gets a celebration (and then the map), once — armed by the first-run setup or by Show me
    /// around again, so someone already using the app never gets it out of the blue.
    static let celebrateArmedKey = "tour.firstMark.armed"

    enum Event {
        case circleTapped, listOpened, zikrPage, sessionStarted, unmarked, mapOpened, editorOpened, foldToggled, next
        /// A real mark (the circle held, or a dot tapped), or the mark's preview when no prayer is due.
        case marked(PrayerModel, PrayerViewModel), markedPreview(PrayerViewModel)
    }

    func place(of step: TourStep) -> (Int, Int)? {
        steps.firstIndex(of: step).map { ($0 + 1, steps.count) }
    }

    func begin() {
        practiceNote = nil
        practicePrayer = nil
        steps = [.circle, .colors, .list, .mark, .fold, .edit, .undo, .swipe, .count]
        UserDefaults.standard.set(true, forKey: Self.celebrateArmedKey)
        run += 1
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = .circle }
    }

    func skip() { finish() }

    private func finish() {
        run += 1
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        undoPracticeIfLeft()
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
    }

    /// The practice mark never stays: left marked when the tour ends, the tour undoes it.
    private func undoPracticeIfLeft() {
        if let prayer = practicePrayer, prayer.isCompleted, let viewModel = practiceViewModel {
            viewModel.togglePrayerCompletion(for: prayer)
            clearPill += 1
        }
        practicePrayer = nil
    }

    func event(_ e: Event) {
        // Outside the tour: the first real mark is celebrated (once), then the map is shown.
        guard let step else {
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
        case (.circle, .circleTapped): go(to: .colors)
        case (.colors, .next): go(to: .list)
        case (.list, .listOpened): go(to: .mark)
        case (.mark, .marked(let prayer, let viewModel)):
            practicePrayer = prayer
            practiceViewModel = viewModel
            noteThen(("That's it", "Marked. Next: where it went, how to change it, and undo it."), next: .fold)
        case (.mark, .markedPreview(let viewModel)):
            // A preview writes nothing: no change or undo to teach; the fold only if earlier prayers are marked.
            steps.removeAll { $0 == .undo || $0 == .edit }
            let anyDone = viewModel.todaysPrayers.contains { $0.isCompleted }
            if !anyDone { steps.removeAll { $0 == .fold } }
            noteThen(("That's it", "No prayer is due now, so that was just a preview."), next: anyDone ? .fold : .swipe)
        case (.fold, .foldToggled):
            if steps.contains(.edit) {
                // The next steps need the marked row in view.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    if !PrayerListFold.shared.showDone { PrayerListFold.shared.showDone = true }
                }
                go(to: .edit)
            } else {
                go(to: .swipe)
            }
        // The editor opened (a sheet over the page): the undo step waits under it, shown when it closes.
        case (.edit, .editorOpened): go(to: .undo)
        case (.undo, .unmarked), (.edit, .unmarked):
            practicePrayer = nil
            clearPill += 1
            go(to: .swipe)
        case (.swipe, .zikrPage): go(to: .count)
        case (.count, .sessionStarted): finish()
        case (.celebrate, .next): go(to: .map)
        case (.map, .mapOpened), (.map, .next): withAnimation(.easeOut(duration: CircleMotion.quick)) { self.step = nil }
        default: break
        }
    }

    /// Out, then in: the bubble goes, then the next one comes at the next control.
    private func go(to next: TourStep) {
        withAnimation(.easeOut(duration: CircleMotion.quick)) { step = nil }
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            guard run == thisRun else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { step = next }
        }
    }

    /// The flourish plays under a short note, then the next step.
    private func noteThen(_ note: (String, String), next: TourStep) {
        practiceNote = note
        let thisRun = run
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            guard run == thisRun else { return }
            clearPill += 1   // the post-salah pill the mark brought
            practiceNote = nil
            go(to: next)
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
                let due = viewModel.relevantPrayer.flatMap { $0.status() == .current && !$0.isCompleted ? $0 : nil }
                TourOverlay(step: step, style: .callout,
                            target: target(step, due: due),
                            override: step == .mark ? (runtime.practiceNote ?? (due == nil
                                ? ("Mark your prayer", "No prayer is due now: hold the circle to see how it looks.") : nil)) : nil,
                            showsNext: step == .colors || step == .celebrate || step == .map,
                            place: runtime.place(of: step),
                            onNext: { runtime.event(.next) },
                            onSkip: { runtime.skip() })
                    .id(step)
                if step == .celebrate { ConfettiBurst().allowsHitTesting(false) }
            }
        }
        .onChange(of: sharedState.navPosition) { _, position in
            if position == .bottom { runtime.event(.listOpened) }
        }
        .onChange(of: sharedState.horizontalPage) { _, page in
            if page == .zikr { runtime.event(.zikrPage) }
        }
        // "N done" shown or hidden.
        .onChange(of: PrayerListFold.shared.showDone) { _, _ in runtime.event(.foldToggled) }
        // The practice mark undone by the user (its dot → Unmark).
        .onChange(of: runtime.practicePrayer?.isCompleted) { _, done in
            if done == false { runtime.event(.unmarked) }
        }
    }

    /// What a step lights: the mark step the due prayer's dot (the circle when none is due), the undo step the practice
    /// prayer's dot; the others their own.
    private func target(_ step: TourStep, due: PrayerModel?) -> String? {
        switch step {
        case .mark: due.map { "prayerDot." + $0.name } ?? "circle"
        case .undo, .edit: runtime.practicePrayer.map { "prayerDot." + $0.name }
        default: step.target
        }
    }

    private func onItsPage(_ step: TourStep) -> Bool {
        switch step {
        case .count: sharedState.horizontalPage == .zikr
        case .circle, .colors, .list: sharedState.horizontalPage == .main && sharedState.navPosition == .main
        case .mark, .fold, .edit, .undo: sharedState.horizontalPage == .main && sharedState.navPosition == .bottom
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
