import SwiftUI

/// The first counting session's tour (owner, audit J: the session tour). Same rules as the main tour: each tip asks, its
/// to-do ticks only on the user's own action, then its insight with Continue; ‹ Back within a screen; no emoji. Tap twice
/// · three separate drags · three counts in one stroke · pause · the pause screen's stats, finish time, notes and Finish
/// · the results' Done · History (from the Zikr page) and deleting this practice session · "now your real session".
/// Never in Tasbih Fatimah. Where they got to is kept for the next session. Show me around again starts it over.
@MainActor @Observable final class CountTips {
    static let shared = CountTips()
    static let stageKey = "countTips.v2.stage"
    static let sessionKey = "countTips.v2.session"

    enum Tip: Int { case tap, drags, stroke, pause, stats, finish, notes, finishButton, results, history, delete, end, done }

    /// The tip on screen now (nil when there's none, or once they're all done).
    private(set) var tip: Tip?
    /// The current tip's count (taps, drags, strokes in one touch).
    private(set) var progress = 0
    /// Its to-do is done: the ✓ a moment, then the insight.
    private(set) var completing = false
    private(set) var insight = false
    /// The pause screen shows a finish time (a goal session): its tip is skipped otherwise.
    @ObservationIgnored var finishShown = false
    /// Bumped to pop the history page once the practice session is deleted.
    private(set) var popHistory = 0

    private var stage: Tip {
        get { Tip(rawValue: UserDefaults.standard.integer(forKey: Self.stageKey)) ?? .done }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.stageKey) }
    }
    /// The tour's own session, deleted on the history step.
    private var sessionID: String? {
        get { UserDefaults.standard.string(forKey: Self.sessionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sessionKey) }
    }

    static func rearm() {
        UserDefaults.standard.removeObject(forKey: stageKey)
        UserDefaults.standard.removeObject(forKey: sessionKey)
        shared.tip = nil
    }

    // MARK: What each tip says

    struct Words { let symbol: String?; let headline: String; let line: String; let task: String?; let needed: Int
                   let insight: (String, String)? }
    static func words(_ tip: Tip) -> Words {
        switch tip {
        case .tap: Words(symbol: "hand.tap", headline: "Count", line: "The whole screen is your counter.",
                         task: "Tap anywhere, twice", needed: 2,
                         insight: ("That's it", "Tap anywhere, any time. You don't need to look."))
        case .drags: Words(symbol: nil, headline: "Drag to count", line: "Drag down anywhere, then lift your finger.",
                           task: "Three separate drags", needed: 3,
                           insight: ("Drag, lift, drag", "Each drag down counts one: a change from tapping."))
        case .stroke: Words(symbol: nil, headline: "Without lifting",
                            line: "Keep your finger down and move it down and up, like scrolling.",
                            task: "Count 3 in one stroke", needed: 3,
                            insight: ("One long stroke", "Each stroke down counts, for as long as you keep going."))
        case .pause: Words(symbol: "pause.circle", headline: "Pause", line: "The pause button is at the top left.",
                           task: "Tap pause", needed: 1,
                           insight: ("Paused", "Everything about this session is here."))
        case .stats: Words(symbol: "chart.bar", headline: "This session so far",
                           line: "Your time, your count and your pace, at the bottom.", task: nil, needed: 0, insight: nil)
        case .finish: Words(symbol: "flag.checkered", headline: "When you'll finish",
                            line: "At this pace, the time you'll reach your goal.", task: nil, needed: 0, insight: nil)
        case .notes: Words(symbol: "text.quote", headline: "Your zikr",
                           line: "Its words and your notes, to read while you pause.", task: nil, needed: 0, insight: nil)
        case .finishButton: Words(symbol: "checkmark.circle", headline: "Finish",
                                  line: "Done for now? Finish saves the session.",
                                  task: "Tap Finish, then again", needed: 1,
                                  insight: ("Saved", "Every session goes into your history."))
        case .results: Words(symbol: "arrow.uturn.backward", headline: "All done",
                             line: "Done takes you back to your zikr.", task: "Tap Done", needed: 1, insight: nil)
        case .history: Words(symbol: "clock.arrow.circlepath", headline: "Your history",
                             line: "Every session you finish is kept here.", task: "Open History, top left", needed: 1,
                             insight: nil)
        case .delete: Words(symbol: "trash", headline: "Tidy up",
                            line: "That was practice \u{2014} swipe it left, then Delete.", task: "Swipe the top one left, then Delete", needed: 1,
                            insight: ("Gone", "Swipe left on any session to delete it."))
        case .end: Words(symbol: "hand.tap", headline: "Your turn",
                         line: "Now the real one: tap the circle when you\u{2019}re ready.", task: nil, needed: 0,
                         insight: nil)
        case .done: Words(symbol: nil, headline: "", line: "", task: nil, needed: 0, insight: nil)
        }
    }

    // MARK: The session

    func sessionOpened(postSalah: Bool) {
        #if DEBUG
        if CommandLine.arguments.contains("-demoCountTips") { Self.rearm() }
        // `-countTipsFrom <n>`: start the session tour at that tip (its raw value: 0 tap … 7 finishButton, 8 results).
        if let i = CommandLine.arguments.firstIndex(of: "-countTipsFrom"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), let from = Tip(rawValue: n) { stage = from }
        #endif
        resetTip()
        guard !postSalah else { if (tip?.rawValue ?? 99) <= Tip.finishButton.rawValue { tip = nil }; return }
        var s = stage
        // Left on the pause screen's tips: they start again at the pause tip.
        if (Tip.stats.rawValue...Tip.finishButton.rawValue).contains(s.rawValue) { s = .pause; stage = s }
        // The later tips live on other screens (the Zikr page, History).
        if s.rawValue <= Tip.finishButton.rawValue { tip = s }
    }

    /// The tips that live on the Zikr page and History come back after a relaunch.
    func load() {
        #if DEBUG
        // `-countTipsFrom 9…11` (history, delete, end) opens on that tip at launch.
        if let i = CommandLine.arguments.firstIndex(of: "-countTipsFrom"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), let from = Tip(rawValue: n), from.rawValue >= Tip.history.rawValue {
            stage = from
        }
        #endif
        if tip == nil, [Tip.history, .delete, .end].contains(stage) { tip = stage }
    }

    func sessionClosed() {
        // Left from the results' Done: on to History on the Zikr page.
        if tip == .results { go(.history) } else if tip != nil, tip!.rawValue <= Tip.finishButton.rawValue { tip = nil }
    }

    /// A count from the screen: a tap, or a stroke of a held drag (`inTouch`: strokes so far in this touch).
    func counted(byDrag: Bool, inTouch: Int = 0) {
        guard let tip, !completing else { return }
        switch tip {
        case .tap where !byDrag: bump()
        case .stroke where byDrag:
            withAnimation(.snappy(duration: 0.25)) { progress = max(progress, inTouch) }
            if progress >= Self.words(.stroke).needed { complete() }
        default: break
        }
    }

    /// A drag lifted, with the counts it made.
    func dragEnded(strokes: Int) {
        guard let tip, !completing else { return }
        switch tip {
        case .drags where strokes > 0: bump()
        // Only three from a single touch tick it (audit J): a lift starts the count again.
        case .stroke: withAnimation(.snappy(duration: 0.25)) { progress = 0 }
        default: break
        }
    }

    /// The pause button pressed (not the pause going to the background makes).
    func pausePressed() { if tip == .pause { bump() } }
    /// The session saved by Finish: the tour's own session.
    func sessionSaved(_ id: UUID) {
        if tip == .finishButton { sessionID = id.uuidString; bump() }
    }
    func historyOpened() { if tip == .history { go(.delete) } }
    func sessionsDeleted(_ ids: [UUID]) {
        if tip == .delete, let mine = sessionID, ids.map(\.uuidString).contains(mine) { bump() }
    }

    func next() {
        guard let tip else { return }
        let w = Self.words(tip)
        guard insight || w.task == nil else { return }
        switch tip {
        case .pause: go(.stats)
        case .stats: go(finishShown ? .finish : .notes)
        case .finish: go(.notes)
        case .notes: go(.finishButton)
        case .finishButton: go(.results)
        case .delete:
            popHistory += 1   // back to the Zikr page
            go(.end)
        case .end: finishAll()
        default:
            if let n = Tip(rawValue: tip.rawValue + 1) { go(n) }
        }
    }

    /// Back, within a screen.
    func back() {
        guard let tip else { return }
        let prev: Tip? = switch tip {
        case .drags: .tap
        case .stroke: .drags
        case .finish: .stats
        case .notes: finishShown ? .finish : .stats
        case .finishButton: .notes
        default: nil
        }
        if let prev { go(prev) }
    }
    /// Not once Finish has saved the session (Back would land on the pause screen's tips over the results).
    var canGoBack: Bool { [.drags, .stroke, .finish, .notes, .finishButton].contains(tip) && !(tip == .finishButton && completing) }

    func skipAll() { finishAll() }

    private func finishAll() {
        stage = .done
        resetTip()
        withAnimation(.easeOut(duration: CircleMotion.quick)) { tip = nil }
    }

    private func bump() {
        guard let tip else { return }
        withAnimation(.snappy(duration: 0.25)) { progress += 1 }
        if progress >= Self.words(tip).needed { complete() }
    }

    /// The to-do done: the ✓ a moment, then its insight (or, with none, the next tip).
    private func complete() {
        guard let tip else { return }
        completing = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard self.tip == tip else { return }
            if Self.words(tip).insight != nil {
                withAnimation(.easeOut(duration: CircleMotion.quick)) { self.insight = true }
            } else if tip == .results {
                // Done closes the session; History follows on the Zikr page (sessionClosed).
            } else {
                self.next()
            }
        }
    }

    private func resetTip() { progress = 0; completing = false; insight = false }

    private func go(_ next: Tip) {
        stage = next
        resetTip()
        withAnimation(.easeInOut(duration: CircleMotion.quick)) { tip = next }
    }

    /// The results' Done (the session closes right after).
    func resultsDone() { if tip == .results { bump() } }
}

/// The session tour's tips over the session, drawn in the session's own look. Only a tip with buttons takes touches:
/// everywhere else a tap still counts.
struct CountTipsLayer: View {
    let paused: Bool
    /// Nothing else is in the way (the "still there?" countdown, the count not in yet).
    let clear: Bool
    /// The results are up.
    let results: Bool
    let pauseButton: CGRect
    let chips: CGRect
    @State private var tips = CountTips.shared

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let size = proxy.size
            let t = TourTargets.shared
            ZStack {
                if clear, let tip = tips.tip {
                    switch tip {
                    case .tap where !paused && !results, .drags where !paused && !results, .stroke where !paused && !results:
                        bubble(tip).position(x: size.width / 2, y: size.height - 180)
                    case .pause where !paused && !results && pauseButton.width > 0:
                        bubble(tip, tail: .up, tailX: pauseButton.midX - origin.x - 16)
                            .padding(.leading, 16).frame(maxWidth: .infinity, alignment: .leading)
                            .position(x: size.width / 2, y: pauseButton.maxY - origin.y + 96)
                    // Paused: the insight of the pause tip, then each piece, by it.
                    case .pause where paused:
                        bubble(tip).position(x: size.width / 2, y: size.height * 0.45)
                    case .stats where paused, .finish where paused:
                        if let f = t.frame("ct.stats") {
                            bubble(tip, tail: .down).position(x: size.width / 2, y: f.minY - origin.y - 80)
                        }
                    case .notes where paused:
                        if let f = t.frame("ct.notes") {
                            bubble(tip, tail: .up).position(x: size.width / 2, y: f.maxY - origin.y + 80)
                        }
                    case .finishButton where paused:
                        if let f = t.frame("ct.finish") {
                            bubble(tip, tail: .up, tailX: 300 - (size.width - f.midX + origin.x) + 16)
                                .padding(.trailing, 16).frame(maxWidth: .infinity, alignment: .trailing)
                                .position(x: size.width / 2, y: f.maxY - origin.y + 100)
                        }
                    case .finishButton where results:
                        bubble(tip).position(x: size.width / 2, y: size.height * 0.4)
                    case .results where results:
                        if let f = t.frame("ct.done") {
                            bubble(tip, tail: .down).position(x: size.width / 2, y: f.minY - origin.y - 76)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: paused)
        }
        .ignoresSafeArea()
        // VoiceOver: each tip said as it comes (audit C15).
        .onChange(of: tips.tip) { _, tip in
            guard let tip else { return }
            let w = CountTips.words(tip)
            AccessibilityNotification.Announcement("\(w.headline). \(w.line)").post()
        }
        .onChange(of: tips.insight) { _, on in
            if on, let tip = tips.tip, let i = CountTips.words(tip).insight {
                AccessibilityNotification.Announcement("\(i.0). \(i.1)").post()
            }
        }
    }

    private func bubble(_ tip: CountTips.Tip, tail: CountTipBubble.Tail? = nil, tailX: CGFloat = 150) -> some View {
        CountTipCard(tip: tip, tail: tail, tailX: tailX)
            .transition(.opacity)
    }
}

/// One session-tour tip: the ask (and its to-do, with "n of N") or, once done, its insight; Back / Not now / Continue.
struct CountTipCard: View {
    let tip: CountTips.Tip
    var tail: CountTipBubble.Tail? = nil
    var tailX: CGFloat = 150
    @State private var tips = CountTips.shared

    var body: some View {
        let w = CountTips.words(tip)
        let showInsight = tips.insight && w.insight != nil
        let continueShown = showInsight || w.task == nil
        CountTipBubble(symbol: w.symbol,
                       headline: showInsight ? w.insight!.0 : w.headline,
                       subline: showInsight ? w.insight!.1 : w.line,
                       tasks: showInsight ? [] : (w.task.map { [$0] } ?? []),
                       done: tips.completing,
                       progress: w.needed > 1 && !tips.completing ? (tips.progress, w.needed) : nil,
                       tail: tail, tailX: tailX,
                       buttons: .init(back: tips.canGoBack ? { tips.back() } : nil,
                                      skip: { tips.skipAll() },
                                      next: continueShown ? (tip == .end ? ("Done", { tips.next() }) : ("Continue", { tips.next() })) : nil))
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
    /// Back / Not now / Continue (the session tour's rules, audit J).
    struct Buttons {
        var back: (() -> Void)? = nil
        var skip: (() -> Void)? = nil
        var next: (String, () -> Void)? = nil
    }
    var buttons: Buttons? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    /// The tour's bubble look while the owner compares (audit E21): an edge and a stronger shadow.
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(.title3, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.9)), isActive: !done && !reduceMotion)
                    } else if reduceMotion {
                        Image(systemName: "arrow.up.and.down")   // the moving finger, still (audit C14)
                            .font(.system(.title3, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.7))
                    } else {
                        StrokeFinger()
                    }
                }
                .frame(width: 28)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.system(.body, design: .rounded, weight: .regular))
                        .accessibilityAddTraits(.isHeader)
                    Text(subline)
                        .font(.system(.subheadline, design: .rounded, weight: .light))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !tasks.isEmpty {
                TourChecklist(tasks: tasks, ticked: done ? [0] : [], progress: progress)
                    .padding(.leading, 40)
            }
            if let buttons {
                HStack {
                    if let back = buttons.back {
                        Button(action: back) {
                            Image(systemName: "chevron.left").font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel)).frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Back")
                    }
                    Spacer()
                    if let skip = buttons.skip {
                        Button("Not now", action: skip).buttonStyle(.plain)
                            .font(.system(.footnote, design: .rounded)).foregroundStyle(Color(.secondaryLabel))
                    }
                    if let next = buttons.next {
                        Button(next.0, action: next.1).buttonStyle(.plain)
                            .font(.system(.footnote, design: .rounded, weight: .medium)).foregroundStyle(TourInk.green)
                            .padding(.leading, 16)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(16)
        .frame(width: 300)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // fixed 300 pt wide over the counter
        .accessibilityElement(children: .contain)
        .tourBubble(PointerBubble(tail: tail, tailX: tailX), look: TourBubbleLook(rawValue: lookRaw) ?? .glass,
                    scheme: scheme, backdrop: theme.backdrop)
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

/// The session tour's tips on the Zikr page: History (after the practice session), then "your turn" by the circle.
struct ZikrPageTipsLayer: View {
    let covered: Bool
    let onZikr: Bool
    @State private var tips = CountTips.shared
    @Environment(SharedStateClass.self) private var sharedState

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let size = proxy.size
            let t = TourTargets.shared
            ZStack {
                if !covered, onZikr, TourRuntime.shared.step == nil, let tip = tips.tip {
                    switch tip {
                    case .history:
                        if let door = t.frame("historyDoor") {
                            CountTipCard(tip: tip, tail: .up, tailX: door.midX - origin.x - 16)
                                .padding(.leading, 16).frame(maxWidth: .infinity, alignment: .leading)
                                .position(x: size.width / 2, y: door.maxY - origin.y + 90)
                        }
                    case .end:
                        if let circle = t.frame("zikrCircle") {
                            CountTipCard(tip: tip, tail: .up)
                                .position(x: size.width / 2, y: circle.maxY - origin.y + 80)
                        }
                    default: EmptyView()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { tips.load() }
        // These tips are about the Zikr page: a session closed onto another page goes there.
        .onChange(of: tips.tip, initial: true) { _, tip in
            guard tip == .history || tip == .end, TourRuntime.shared.step == nil else { return }
            // A beat later: on a cold launch the pager isn't laid out yet and put itself back on Salah.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                if sharedState.horizontalPage != .zikr || CircleStage.shared.restingPage != .zikr { sharedState.go(to: .zikr) }
            }
        }
    }
}
