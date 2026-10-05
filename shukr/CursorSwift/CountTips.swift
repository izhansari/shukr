import SwiftUI

/// The first counting session's tips (owner: "definitely add this when they do their first tasbeeh session - non tasbih
/// fatimah i guess. big thing to make sure they know is they can continuous hold and drag down and up. so a scroll
/// motion, a continuous hold to down up drag, or tapping work to increment."). Four, each ended by the real thing:
/// tap anywhere (a tap) · hold and drag down and up (three strokes) · pause for more (⏸) · the pause screen's chips
/// (resume or finish). Where they got to is kept, so a session left halfway picks up there next time; never in Tasbih
/// Fatimah. Show me around again starts them over (`rearm`). None of it takes a touch: the whole screen still counts.
@MainActor @Observable final class CountTips {
    static let shared = CountTips()
    static let stageKey = "countTips.v1.stage"

    enum Tip: Int { case tap, drag, pause, settings, done }

    /// The tip on screen now (nil outside a normal session, or once they're all done).
    private(set) var tip: Tip?
    /// Strokes counted on the drag tip (three end it).
    private(set) var strokes = 0
    /// The tip's to-do is done (its green ✓), for a moment before the next tip.
    private(set) var done = false
    static let strokesNeeded = 3

    private var stage: Tip {
        get { Tip(rawValue: UserDefaults.standard.integer(forKey: Self.stageKey)) ?? .done }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.stageKey) }
    }

    static func rearm() { UserDefaults.standard.removeObject(forKey: stageKey) }

    func sessionOpened(postSalah: Bool) {
        #if DEBUG
        if CommandLine.arguments.contains("-demoCountTips") { Self.rearm() }
        #endif
        strokes = 0; done = false
        tip = postSalah || stage == .done ? nil : stage
    }

    func sessionClosed() {
        if tip == .settings { stage = .done }   // finished from the pause screen: they've seen it
        tip = nil
    }

    /// A count from the screen: a tap, or a stroke of a held drag.
    func counted(byDrag: Bool) {
        guard let tip else { return }
        switch tip {
        // Only the thing it asks for ticks it (owner: "it doesn't let us progress until the user does exactly that").
        case .tap where !byDrag && !done:
            finishTip(then: .drag)
        case .drag where byDrag && !done:
            withAnimation(.snappy(duration: 0.25)) { strokes += 1 }
            guard strokes >= Self.strokesNeeded else { return }
            finishTip(then: .pause)
        default: break
        }
    }

    /// ⏸ pressed (not the pause going to the background makes).
    func pausePressed() {
        if tip == .pause { advance(to: .settings) }
    }

    /// Back to counting from the pause screen.
    func resumed() {
        if tip == .settings { advance(to: .done) }
    }

    /// The ✓, a moment to see it, then the next tip.
    private func finishTip(then next: Tip) {
        withAnimation(.snappy(duration: 0.3)) { done = true }
        stage = next
        let current = tip
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard self.tip == current else { return }
            self.done = false
            self.advance(to: next)
        }
    }

    private func advance(to next: Tip) {
        stage = next
        withAnimation(.easeInOut(duration: CircleMotion.quick)) { tip = next == .done ? nil : next }
    }
}

/// The tips over the session, drawn in the session's own look. Never hit-testable: a tap on a tip still counts.
struct CountTipsLayer: View {
    let paused: Bool
    /// Nothing else is in the way (results, the "still there?" countdown, the count not in yet).
    let clear: Bool
    let pauseButton: CGRect
    let chips: CGRect
    @State private var tips = CountTips.shared

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack {
                if clear, let tip = tips.tip {
                    switch tip {
                    case .tap where !paused:
                        CountTipBubble(symbol: "hand.tap", headline: "Count",
                                       subline: "The whole screen is your counter.",
                                       tasks: ["Tap anywhere"], done: tips.done)
                            .position(x: proxy.size.width / 2, y: proxy.size.height - 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    case .drag where !paused:
                        CountTipBubble(symbol: nil, headline: "Or hold and drag",
                                       subline: "Keep your finger down and move it down and up, like scrolling. Each stroke down counts.",
                                       tasks: ["Drag down and up"], done: tips.done,
                                       progress: (tips.strokes, CountTips.strokesNeeded))
                            .position(x: proxy.size.width / 2, y: proxy.size.height - 170)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    case .pause where !paused && pauseButton.width > 0:
                        let tailX = pauseButton.midX - origin.x
                        CountTipBubble(symbol: "pause.circle", headline: "Pause for more",
                                       subline: "Count in sets, sleep mode and haptics are on the pause screen.",
                                       tasks: ["Tap \u{23F8}"], done: false,
                                       tail: .up, tailX: tailX - 16)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .position(x: proxy.size.width / 2, y: pauseButton.maxY - origin.y + 82)
                            .transition(.opacity)
                    case .settings where paused && chips.width > 0:
                        CountTipBubble(symbol: "slider.horizontal.3", headline: "This session's settings",
                                       subline: "Tap one to switch it; \u{24D8} says what it does.",
                                       tasks: ["Tap anywhere else to carry on"], done: false,
                                       tail: .down, tailX: (chips.midX - origin.x) - (proxy.size.width - 300) / 2)
                            .position(x: proxy.size.width / 2, y: chips.minY - origin.y - 84)
                            .transition(.opacity)
                    default:
                        EmptyView()
                    }
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: paused)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// One tip: a raised pebble in the page's colour (the tour's), an SF symbol or the moving finger, words, and for the
/// drag tip three dots that fill as the strokes come.
struct CountTipBubble: View {
    enum Tail { case up, down }
    /// nil: the finger moving down and up.
    var symbol: String?
    let headline: String
    let subline: String
    var tasks: [String] = []
    var done = false
    var progress: (Int, Int)? = nil
    var tail: Tail? = nil
    /// The tail's x inside the bubble.
    var tailX: CGFloat = 150
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    /// The tour's bubble look while the owner compares (audit E21): an edge and a stronger shadow.
    @AppStorage(TourInk.solidKey) private var solid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 21, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.9)), isActive: !done)
                    } else {
                        StrokeFinger()
                    }
                }
                .frame(width: 28)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.system(size: 18, weight: .regular, design: .rounded))
                    Text(subline)
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !tasks.isEmpty {
                TourChecklist(tasks: tasks, ticked: done ? [0] : [], progress: progress)
                    .padding(.leading, 40)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            PointerBubble(tail: tail, tailX: tailX)
                .fill(theme.backdrop)
                .overlay { if solid { PointerBubble(tail: tail, tailX: tailX).stroke(Color.primary.opacity(0.14), lineWidth: 1) } }
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : (solid ? 0.24 : 0.14)), radius: solid ? 16 : 12, x: 5, y: 7)
                .shadow(color: .white.opacity(scheme == .dark ? 0.06 : 0.9), radius: 8, x: -4, y: -4)
        )
    }
}

/// A fingertip stroking down and up on a short track, the drag it teaches.
private struct StrokeFinger: View {
    @State private var down = false
    var body: some View {
        ZStack {
            Capsule().fill(Color.primary.opacity(0.1)).frame(width: 14, height: 40)
            Circle().fill(Color.primary.opacity(0.6)).frame(width: 14, height: 14)
                .offset(y: down ? 13 : -13)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { down = true }
        }
    }
}

/// A rounded bubble with a soft tail at `tailX` along its top or bottom edge (or none).
struct PointerBubble: Shape {
    var tail: CountTipBubble.Tail?
    var tailX: CGFloat
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 22, tw: CGFloat = 26, th: CGFloat = 10
        var p = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        guard let tail else { return p }
        let x = min(max(rect.minX + tailX, rect.minX + 14 + tw / 2), rect.maxX - 14 - tw / 2)
        let y = tail == .up ? rect.minY : rect.maxY
        let tip = tail == .up ? y - th : y + th
        let inside: CGFloat = tail == .up ? 1 : -1
        p.move(to: CGPoint(x: x - tw / 2, y: y + inside))
        p.addQuadCurve(to: CGPoint(x: x, y: tip), control: CGPoint(x: x - tw / 6, y: y))
        p.addQuadCurve(to: CGPoint(x: x + tw / 2, y: y + inside), control: CGPoint(x: x + tw / 6, y: y))
        p.closeSubpath()
        return p
    }
}
