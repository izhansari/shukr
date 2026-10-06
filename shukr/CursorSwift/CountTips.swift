import SwiftUI
import SwiftData

/// The first counting session's tips (owner, 2026-10-06: "make it similar to what we just made for the app tour").
/// Three chapters in the tour's own bubble — the chapter's number and title, a ring for how far through it, its steps
/// folding to ✓ lines: 1 Counting (tap 3 times · 3 separate drags · 3 drags without lifting) · 2 Pausing (pause · the
/// pause screen in a line, then Finish) · 3 After (Done · History · deleting the practice session) · "your turn".
/// Each to-do ticks only on the user's own action. "Skip tips" (two taps) sits top right — not on the pause screen.
///
/// A practice session (decision count-tips-session B): finished while the tips run, with no more counts than they ask
/// for, it's never saved — it lives in a store of its own, in memory, shows in History as "Practice", and its delete
/// is a pretend one. Counted for real (more than `practiceMost`), or the tips skipped, the session is saved as usual.
/// Freestyle only (never a task's or Tasbih Fatimah's). Where they got to is kept for the next session; Show me around
/// again starts it over.
@MainActor @Observable final class CountTips {
    static let shared = CountTips()
    static let stageKey = "countTips.v3.stage"
    static let keptKey = "countTips.v3.kept"

    enum Tip: Int { case tap, drags, stroke, pause, paused, results, history, delete, end, done }

    /// The tip on screen now (nil when there's none, or once they're all done).
    private(set) var tip: Tip?
    /// The current tip's count (taps, drags, strokes in one touch).
    private(set) var progress = 0
    /// Its to-do is done: the ✓ a moment, then the next step.
    private(set) var completing = false
    /// A finished step opened again by a tap on its ✓ line.
    var openSection: String?
    /// Kept so the session's pause-screen code compiles unchanged (the finish-time tip is gone: freestyle has no goal).
    @ObservationIgnored var finishShown = false
    /// Bumped to pop the history page once the practice session is deleted.
    private(set) var popHistory = 0
    /// The practice session, never saved: shown in History until its pretend delete.
    private(set) var practiceSession: SessionDataModel?
    @ObservationIgnored private var practiceStore: ModelContainer?

    private var stage: Tip {
        get { Tip(rawValue: UserDefaults.standard.integer(forKey: Self.stageKey)) ?? .done }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.stageKey) }
    }
    private var kept: Bool { UserDefaults.standard.bool(forKey: Self.keptKey) }

    static func rearm() {
        UserDefaults.standard.removeObject(forKey: stageKey)
        UserDefaults.standard.removeObject(forKey: keptKey)
        shared.tip = nil
        shared.practiceSession = nil
    }

    // MARK: The pages (the words: TourCopy.Session)

    private typealias C = TourCopy.Session

    /// The bubble for a tip: its chapter, the steps so far (the finished ones folded), the current one open.
    func page(for tip: Tip) -> TourPage {
        let done = completing
        func step(_ id: String, _ title: String, _ lead: String, _ todo: String?, _ t: Tip, needed: Int = 1) -> TourSection {
            var s = TourSection(id: id, title: title, done: t.rawValue < tip.rawValue, lead: lead,
                                tasks: todo.map { [$0] } ?? [])
            if t == tip, needed > 1, !done { s.progress = (progress, needed) }
            return s
        }
        switch tip {
        case .tap, .drags, .stroke:
            let all = [step("ct.tap", C.tapStep, C.tapLead, C.tapTodo, .tap, needed: 3),
                       step("ct.drags", C.dragStep, C.dragLead, C.dragTodo, .drags, needed: 3),
                       step("ct.stroke", C.strokeStep, C.strokeLead, C.strokeTodo, .stroke, needed: 3)]
            let n = tip.rawValue
            return TourPage(headline: C.countingTitle, index: 1, progress: Double(n + (done ? 1 : 0)) / 3,
                            sections: Array(all.prefix(n + 1)))
        case .pause, .paused:
            let all = [step("ct.pause", C.pauseStep, C.pauseLead, C.pauseTodo, .pause),
                       step("ct.paused", C.pausedStep, C.pausedLead, C.pausedTodo, .paused)]
            let n = tip.rawValue - Tip.pause.rawValue
            return TourPage(headline: C.pausingTitle, index: 2, progress: Double(n + (done ? 1 : 0)) / 2,
                            sections: Array(all.prefix(n + 1)))
        case .results, .history, .delete, .end, .done:
            var all = [step("ct.results", C.resultsStep, C.resultsLead, C.resultsTodo, .results),
                       step("ct.history", C.historyStep, C.historyLead, C.historyTodo, .history)]
            // Counted for real: kept — nothing to delete (Ben's audit N).
            all.append(kept ? TourSection(id: "ct.kept", title: C.keptStep, done: tip == .end, lead: C.keptLead)
                            : step("ct.delete", C.deleteStep, C.deleteLead, C.deleteTodo, .delete))
            let n = min(tip.rawValue, Tip.delete.rawValue) - Tip.results.rawValue
            var sections = Array(all.prefix(n + 1))
            var primary: String?
            if tip == .end {
                sections.append(TourSection(id: "ct.end", note: C.endLine))
                primary = C.endButton
            } else if tip == .delete && kept {
                primary = TourCopy.continueButton
            }
            let finished = Double(n + (done ? 1 : 0))
            return TourPage(headline: C.afterTitle, index: 3, progress: tip == .end ? 1 : finished / 3,
                            sections: sections, primary: primary)
        }
    }

    // MARK: The session

    /// `task`: a task's session — never the practice one (its counts would go into the task's day and streak; Ben's
    /// audit N): the tips wait for a freestyle session.
    func sessionOpened(postSalah: Bool, task: Bool = false) {
        #if DEBUG
        if CommandLine.arguments.contains("-demoCountTips") { Self.rearm() }
        // `-countTipsFrom <n>`: start at that tip (0 tap … 4 paused, 5 results).
        if let i = CommandLine.arguments.firstIndex(of: "-countTipsFrom"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), let from = Tip(rawValue: n) { stage = from }
        #endif
        resetTip()
        guard !postSalah && !task else { if (tip?.rawValue ?? 99) <= Tip.paused.rawValue { tip = nil }; return }
        var s = stage
        // Left on the pause screen: back to the pause step.
        if s == .paused { s = .pause; stage = s }
        // The later tips live on other screens (the Zikr page, History).
        if s.rawValue <= Tip.paused.rawValue { tip = s }
    }

    /// The tips that live on the Zikr page and History come back after a relaunch — the practice session doesn't
    /// (it was never saved): then straight to "your turn".
    func load() {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "-countTipsFrom"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]), let from = Tip(rawValue: n), from.rawValue >= Tip.history.rawValue {
            stage = from
        }
        #endif
        if [Tip.history, .delete].contains(stage), practiceSession == nil, !kept { stage = .end }
        if tip == nil, [Tip.history, .delete, .end].contains(stage) { tip = stage }
    }

    func sessionClosed() {
        // Left from the results' Done: on to History on the Zikr page.
        if tip == .results { go(.history) } else if tip != nil, tip!.rawValue <= Tip.paused.rawValue { tip = nil }
    }

    /// A count from the screen: a tap, or a stroke of a held drag (`inTouch`: strokes so far in this touch).
    func counted(byDrag: Bool, inTouch: Int = 0) {
        guard let tip, !completing else { return }
        switch tip {
        case .tap where !byDrag: bump(needed: 3)
        case .stroke where byDrag:
            withAnimation(.snappy(duration: 0.25)) { progress = max(progress, inTouch) }
            if progress >= 3 { complete() }
        default: break
        }
    }

    /// A drag lifted, with the counts it made.
    func dragEnded(strokes: Int) {
        guard let tip, !completing else { return }
        switch tip {
        case .drags where strokes > 0: bump(needed: 3)
        // Only three from a single touch tick it (audit J): a lift starts the count again.
        case .stroke: withAnimation(.snappy(duration: 0.25)) { progress = 0 }
        default: break
        }
    }

    /// The pause button pressed (not the pause going to the background makes).
    func pausePressed() { if tip == .pause { bump(needed: 1) } }

    /// More counts than the tips ask for (3 taps, 3 drags, 3 in one drag = 9, with room): a real session.
    static let practiceMost = 12

    /// Saving a session now (Finish while the tips run, no more counts than they ask for): it's the practice one, and
    /// isn't saved. The caller makes it (`holdPractice`) instead of inserting it.
    func takesPractice(count: Int) -> Bool {
        guard let tip, tip.rawValue <= Tip.paused.rawValue else { return false }
        return count <= Self.practiceMost
    }

    /// The practice session, in a store of its own in memory (the History row reads it like any session).
    func holdPractice(_ session: SessionDataModel) {
        if practiceStore == nil {
            practiceStore = try? ModelContainer(for: Schema(ShukrSchemaV2.models),
                                                configurations: ModelConfiguration("countTipsPractice", isStoredInMemoryOnly: true))
        }
        practiceStore?.mainContext.insert(session)
        practiceSession = session
    }

    /// The session saved by Finish (practice or real): the pause screen's to-do.
    func sessionSaved(_ id: UUID, count: Int) {
        guard tip == .paused else { return }
        if practiceSession?.id == id { UserDefaults.standard.removeObject(forKey: Self.keptKey) }
        else { UserDefaults.standard.set(true, forKey: Self.keptKey) }   // counted for real: it's theirs
        bump(needed: 1)
    }

    /// The practice session (only it may be deleted while the delete tip is up).
    func isPractice(_ id: UUID) -> Bool { practiceSession?.id == id }
    /// The delete tip is up: no other session can be deleted (Ben's audit N).
    var guardsDeletes: Bool { tip == .delete }
    func historyOpened() { if tip == .history { go(.delete) } }
    /// The practice session's delete: pretend — it was never saved (decision count-tips-session B).
    func practiceDeleted() {
        guard tip == .delete else { return }
        withAnimation(.easeOut(duration: CircleMotion.standard)) { practiceSession = nil }
        bump(needed: 1)
    }
    /// Real sessions deleted elsewhere: nothing for the tips.
    func sessionsDeleted(_ ids: [UUID]) {}

    /// Continue / Done on the tips' own buttons.
    func next() {
        switch tip {
        case .delete where kept:
            popHistory += 1   // back to the Zikr page
            go(.end)
        case .end: finishAll()
        default: break
        }
    }

    func toggle(_ id: String) {
        withAnimation(.smooth(duration: CircleMotion.standard)) { openSection = openSection == id ? nil : id }
    }

    /// Skip tips: a session that hadn't finished yet is saved as usual (the practice rule needs the tips running).
    func skipAll() { finishAll() }

    private func finishAll() {
        stage = .done
        resetTip()
        withAnimation(.easeOut(duration: CircleMotion.quick)) { tip = nil; practiceSession = nil }
    }

    private func bump(needed: Int) {
        guard tip != nil else { return }
        withAnimation(.snappy(duration: 0.25)) { progress += 1 }
        if progress >= needed { complete() }
    }

    /// The to-do done: its ✓ a moment, then the next step (the results' Done closes the session: History follows).
    private func complete() {
        guard let tip else { return }
        withAnimation(.snappy(duration: 0.25)) { completing = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard self.tip == tip else { return }
            switch tip {
            case .results: break   // sessionClosed() moves on
            case .delete:
                popHistory += 1   // back to the Zikr page
                go(.end)
            default:
                if let n = Tip(rawValue: tip.rawValue + 1) { go(n) }
            }
        }
    }

    private func resetTip() { progress = 0; completing = false; openSection = nil }

    private func go(_ next: Tip) {
        stage = next
        withAnimation(.smooth(duration: CircleMotion.standard)) {
            resetTip()
            tip = next
        }
    }

    /// The results' Done (the session closes right after).
    func resultsDone() { if tip == .results { bump(needed: 1) } }
}

/// One tip's bubble: the tour's own (TourPageView, a plain rounded rectangle — no tail).
struct CountTipCard: View {
    let tip: CountTips.Tip
    @State private var tips = CountTips.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    var body: some View {
        let page = tips.page(for: tip)
        TourPageView(step: .zikr, page: page, place: nil, ticked: tips.completing ? [0] : [], lit: [],
                     openSection: tips.openSection, showsBack: false, qiblaSkip: false,
                     onPrimary: { tips.next() }, onSecondary: {}, onBack: {},
                     onToggle: { tips.toggle($0) }, onSkipQibla: {})
            .padding(16)
            .frame(width: 330)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .contain)
            .tourBubble(RoundedRectangle(cornerRadius: 22, style: .continuous),
                        look: TourBubbleLook(rawValue: lookRaw) ?? .glass, scheme: scheme, backdrop: theme.backdrop)
    }
}

/// "Skip tips", top right, two taps (the tour's own button).
struct CountTipsSkip: View {
    var body: some View {
        TourSkipButton(label: TourCopy.Session.skip, confirm: TourCopy.Session.skipConfirm) { CountTips.shared.skipAll() }
    }
}

/// The tips over the session. Only the bubble takes touches: everywhere else a tap still counts.
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
            let finish = TourTargets.shared.frame("ct.finish")
            ZStack {
                if clear, let tip = tips.tip {
                    Group {
                        switch tip {
                        // Counting: low, clear of the count.
                        case .tap where !paused && !results, .drags where !paused && !results, .stroke where !paused && !results:
                            CountTipCard(tip: tip)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, 56)
                        // The pause button, top left: under it.
                        case .pause where !paused && !results && pauseButton.width > 0:
                            CountTipCard(tip: tip)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, pauseButton.maxY - origin.y + 14)
                        // Paused: under Finish (top right).
                        case .pause where paused, .paused where paused && !results:
                            CountTipCard(tip: tip)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, (finish.map { $0.maxY - origin.y } ?? 120) + 14)
                        case .paused where results:
                            CountTipCard(tip: tip)
                                .frame(maxHeight: .infinity, alignment: .center)
                        // The results: over Done.
                        case .results where results:
                            if let f = TourTargets.shared.frame("ct.done") {
                                CountTipCard(tip: tip)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                    .padding(.bottom, size.height - (f.minY - origin.y) + 14)
                            }
                        default:
                            EmptyView()
                        }
                    }
                    .frame(width: size.width)
                    .transition(.opacity)
                    // Skip tips: top right, left of − (not on the pause screen — owner).
                    if !paused, tip.rawValue <= CountTips.Tip.results.rawValue {
                        CountTipsSkip()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, (finish.map { $0.midY - origin.y } ?? 76) - 16)
                            .padding(.trailing, finish.map { size.width - ($0.minX - origin.x) + 10 } ?? 72)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: paused)
            .animation(.easeInOut(duration: CircleMotion.quick), value: tips.tip)
        }
        .ignoresSafeArea()
        // VoiceOver: each step said as it comes (audit C15).
        .onChange(of: tips.tip) { _, tip in
            guard let tip, let s = tips.page(for: tip).sections.last else { return }
            AccessibilityNotification.Announcement([s.title, s.lead, s.tasks.first].compactMap { $0 }.joined(separator: ". ")).post()
        }
    }
}

/// The tips on the Zikr page: History (after the session), then "your turn" by the circle; Skip tips beside Azkar.
struct ZikrPageTipsLayer: View {
    let covered: Bool
    let onZikr: Bool
    @State private var tips = CountTips.shared
    @Environment(SharedStateClass.self) private var sharedState

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let t = TourTargets.shared
            ZStack {
                if !covered, onZikr, TourRuntime.shared.step == nil, let tip = tips.tip {
                    switch tip {
                    case .history:
                        if let door = t.frame("historyDoor") {
                            CountTipCard(tip: tip)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, door.maxY - origin.y + 12)
                            CountTipsSkip()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(.top, door.midY - origin.y - 16)
                                .padding(.trailing, 60)
                        }
                    case .end:
                        if let circle = t.frame("zikrSlot") ?? t.frame("zikrCircle") {
                            CountTipCard(tip: tip)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, circle.maxY - origin.y + 14)
                        }
                    default: EmptyView()
                    }
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: tips.tip)
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
