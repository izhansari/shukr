//
//  ZikrTour.swift
//  shukr
//
//  The Zikr Tour (owner, 2026-10-06; board/brief-zikr-tour.md; decisions zikr-deep-shape A, zikr-deep-newtask A,
//  zikr-deep-count A, zikr-tour-task-guard A): make one real task — Astaghfirullah, 33 a day — count it, and see where
//  it shows up. Offered as chapter 3 of the app tour reaches the Zikr page, once on the first Zikr visit, and from ☰.
//  One bubble in the tour's chapter look wherever the step is: the Zikr page, inside New task, over the session, its
//  results, Your tasks, History, Azkar. Everything it makes is real: the task, the session, the streak, the pace.
//

import SwiftUI
import SwiftData

@MainActor @Observable final class ZikrTour {
    static let shared = ZikrTour()
    /// Taken to its end (a skip doesn't count): until then "Zikr Tour" sits in ☰ with the green dot.
    static let completedKey = "zikrTour.v1.completed"
    /// Offered once on the first Zikr visit (or seen in the app tour).
    static let offeredKey = "zikrTour.v1.offered"

    enum Step: Int, Comparable {
        case offer, kinds, pick, goal, place, review, start, taps, drags, stroke, keepGoing, results,
             timeLeft, yourTasks, history, historyPage, azkar, azkarPage, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    private(set) var step: Step? {
        didSet {
            #if DEBUG
            if step != oldValue { print("ZIKRTOUR step \(step.map { "\($0)" } ?? "-")") }
            #endif
        }
    }
    /// Chapter 3 of the app tour (its Continue goes on to Settings), or on its own.
    private(set) var inAppTour = false
    /// The current step's count (taps, drags, strokes in one touch, the session's total).
    private(set) var progress = 0
    /// The session's count so far: "Reach 33" starts from it, not from 0.
    @ObservationIgnored private var sessionTotal = 0
    /// Its to-do done: the ✓ a moment, then the next step.
    private(set) var completing = false
    var openSection: String?
    /// The task the tour counts (made in it, or theirs already).
    private(set) var taskID: UUID?
    private(set) var reused = false
    /// Their Astaghfirullah task was already done today: no counting steps.
    private(set) var skippedCount = false
    /// The session's pace, seconds a count.
    private(set) var pace: Double?
    /// How the session went (the results' streak line says it as it is — finished early, no streak yet).
    struct Outcome { let counted: Int; let goal: Int; let streak: Int; let met: Bool; let task: String }
    private(set) var outcome: Outcome?
    /// Bumped to close the page the tour is on (Your tasks, History, Azkar).
    private(set) var popPage = 0
    /// Asks the wheel to centre an item ("add", a task's id).
    private(set) var centre: (String, Int) = ("", 0)

    var active: Bool { step != nil }
    static var completed: Bool { UserDefaults.standard.bool(forKey: completedKey) }
    static let astaghfirullah = "Astaghfirullah"
    static func isAstaghfirullah(_ name: String?) -> Bool {
        BuiltInAzkar.key(name ?? "") == BuiltInAzkar.key(astaghfirullah)
    }

    // MARK: Starting and ending

    /// The offer: chapter 3 of the app tour, the first Zikr visit, or ☰ (`straightIn`: no offer, the steps at once).
    func offer(inAppTour: Bool) {
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        self.inAppTour = inAppTour
        go(.offer)
    }

    /// The lock card's "Unlock with the tour" (ZikrLock): straight into the steps, as Show me — their Astaghfirullah task
    /// if they have one (done today: straight to how long tasks take), else making it.
    /// The counter's welcome has been seen ("Let's begin"): the counting starts (ZikrTourSessionLayer).
    var welcomed = true

    /// The three ways practised in the welcome's boxes: straight on to counting it ("Keep going"), the in-counter
    /// lessons done there.
    func practiced() {
        welcomed = true
        go(.keepGoing)
    }

    /// The guard (owner: "there's no guard for finishing by tapping the whole thing and never dragging"; a guided flow
    /// lets through only the step's own move): while a lesson runs only its move counts — taps in the first, drags in the
    /// next two — and nothing reaches the goal before the last lesson. Outside the lessons everything counts.
    func allows(byDrag: Bool, total: Int) -> Bool {
        guard active, let step else { return true }
        switch step {
        case .taps: if byDrag { return false }
        case .drags, .stroke: if !byDrag { return false }
        default: return true
        }
        return total + 1 < countGoal
    }

    /// What "Keep going" counts to: the first zikr's own goal (100 a day since decision first-zikr-virtue C), else 33.
    private(set) var countGoal = 33

    func begin(in context: ModelContext) {
        countGoal = 33
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        inAppTour = false
        let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let task = tasks.first { Self.isAstaghfirullah($0.mantra?.name ?? $0.mantraName) }
        let dayStart = PrayerDay.sessionDayStart()
        let today = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
        showMe(existing: task, doneToday: task.map { $0.isCompleted(with: $0.progress(in: today)) } ?? false)
    }

    /// The lock's page 3 (owner, 2026-10-08: "we should just go ahead and create a task for them … show it as a task ring
    /// … they then click on to start the counter"): the first zikr's task is made already; its ring's tap opens the
    /// counter straight into the counting lessons — no task-making in the tour.
    func startFirst(_ task: TaskModel) {
        countGoal = task.isCountMode ? task.goal : 33
        welcomed = false
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        inAppTour = false
        taskID = task.id
        reused = true
        skippedCount = false
        go(.taps)
    }

    /// Show me: their Astaghfirullah task if they have one (no duplicate), else making it.
    /// Already done for today: it's off the wheel and there's nothing left to count, so straight to how long tasks take.
    func showMe(existing: TaskModel?, doneToday: Bool = false) {
        countGoal = 33
        if let existing {
            taskID = existing.id
            reused = true
            skippedCount = doneToday
            if doneToday { go(.timeLeft) } else {
                go(.start)
                requestCentre(existing.id.uuidString)
            }
        } else {
            reused = false
            skippedCount = false
            go(.kinds)
            requestCentre("add")
        }
    }

    /// Skip to Settings / Not now / Skip tour: gone, not completed.
    func dismiss() {
        let wasInTour = inAppTour
        end()
        if wasInTour { TourRuntime.shared.zikrTourEnded() }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        ZikrLock.shared.unlock()   // the Zikr tab is theirs now (ZikrLock.swift)
        let wasInTour = inAppTour
        end()
        if wasInTour { TourRuntime.shared.zikrTourEnded() }
    }

    private func end() {
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            step = nil
            progress = 0
            completing = false
            openSection = nil
        }
        inAppTour = false
        taskID = nil
        pace = nil
        outcome = nil
    }

    // MARK: What the wheel and the pages may do

    /// A wheel tap (the item centred): only the one the step asks for.
    func allowsWheelTap(_ id: String) -> Bool {
        switch step {
        case .kinds: return id == "add"
        case .start: return id == taskID?.uuidString
        default: return false
        }
    }
    /// The wheel's tap went through: on to the next step.
    func wheelTapped(_ id: String) {
        if step == .kinds, id == "add" { complete() }
        if step == .start, id == taskID?.uuidString { complete() }
    }

    /// New task, while making the tour's: only Astaghfirullah (owner: guard it), 33 a day.
    var guardsNewTask: Bool { step.map { $0 >= .pick && $0 <= .review } ?? false }
    func allowsPick(_ name: String) -> Bool { !guardsNewTask || Self.isAstaghfirullah(name) }
    func allowsGoal(countMode: Bool, goal: Int) -> Bool { !guardsNewTask || (countMode && goal == 33) }
    func allowsAdd(name: String?, countMode: Bool, goal: Int) -> Bool {
        !guardsNewTask || (Self.isAstaghfirullah(name) && countMode && goal == 33)
    }
    /// New task's own step (1 zikr, 2 goal, 3 place, 4 review).
    func taskFlowAt(_ flowStep: Int) {
        guard guardsNewTask || step == .kinds else { return }
        let to: Step = switch flowStep { case 1: .pick; case 2: .goal; case 3: .place; default: .review }
        if step != to { go(to) }
    }
    /// The sheet closed without a task: back to the wheel's step.
    func taskFlowClosed() { if guardsNewTask { go(.kinds); requestCentre("add") } }
    func taskCreated(_ task: TaskModel) {
        guard guardsNewTask else { return }
        taskID = task.id
        go(.start)
        requestCentre(task.id.uuidString)
    }

    // MARK: The session

    func counted(byDrag: Bool, inTouch: Int, total: Int) {
        sessionTotal = total
        guard let step, !completing else { return }
        switch step {
        case .taps where !byDrag: bump(3)
        case .stroke where byDrag:
            withAnimation(.snappy(duration: 0.25)) { progress = max(progress, inTouch) }
            if progress >= 3 { complete() }
        case .keepGoing:
            withAnimation(.snappy(duration: 0.25)) { progress = total }
        default: break
        }
    }
    func dragEnded(strokes: Int) {
        guard let step, !completing else { return }
        switch step {
        case .drags where strokes > 0: bump(3)
        case .stroke: withAnimation(.snappy(duration: 0.25)) { progress = 0 }
        default: break
        }
    }
    /// The session saved (its goal reached, or finished early): the results.
    func sessionSaved(_ session: SessionDataModel) {
        guard let step, step >= .taps, step <= .keepGoing else { return }
        pace = session.avgTimePerClick > 0 ? session.avgTimePerClick : nil
        let streak = session.task?.streak()
        let met = (streak?.keptToday ?? false) || (session.targetCount > 0 && session.totalCount >= session.targetCount)
        // Today's count for the task (what its ring shows), not just this session's.
        let dayStart = PrayerDay.sessionDayStart()
        let today = session.task.map { $0.progress(in: $0.sessions.filter { $0.startTime >= dayStart }).count } ?? session.totalCount
        outcome = Outcome(counted: max(today, session.totalCount), goal: session.targetCount,
                          streak: max(streak?.current ?? 0, met ? 1 : 0), met: met,
                          task: session.task?.title ?? "Your zikr")
        go(.results)
    }
    func resultsDone() { if step == .results { complete() } }
    func sessionClosed() {
        // Closed without saving (✕ before a count): back to starting it.
        if let step, step >= .taps, step <= .keepGoing { go(.start) }
    }

    // MARK: The line under the wheel, the pages

    func summaryTapped() { if step == .timeLeft { complete() } }
    func historyOpened() { if step == .history { go(.historyPage) } }
    func azkarOpened() { if step == .azkar { go(.azkarPage) } }

    /// Continue / Done on the bubble.
    func next() {
        switch step {
        case .yourTasks: popPage += 1; go(.history)
        case .historyPage: popPage += 1; go(.azkar)
        case .azkarPage: popPage += 1; go(.done)
        case .done: finish()
        default: break
        }
    }

    func toggle(_ id: String) {
        withAnimation(.smooth(duration: CircleMotion.standard)) { openSection = openSection == id ? nil : id }
    }

    // MARK: Moving on

    private func bump(_ needed: Int) {
        withAnimation(.snappy(duration: 0.25)) { progress += 1 }
        if progress >= needed { complete() }
    }

    private func complete() {
        #if DEBUG
        print("ZIKRTOUR complete \(step.map { "\($0)" } ?? "-")")
        #endif
        guard let step else { return }
        withAnimation(.snappy(duration: 0.25)) { completing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            guard self.step == step else { return }
            switch step {
            case .kinds: go(.pick)          // New task opens (the wheel's tap)
            case .start: go(.taps)
            case .stroke: go(.keepGoing)
            // Done closes the session onto the Zikr page and the tour ends there (owner: what's needed is the counter;
            // History and Azkar are easy to find later).
            case .results: go(.done)
            case .timeLeft: go(.yourTasks)
            default: if let n = Step(rawValue: step.rawValue + 1) { go(n) }
            }
        }
    }

    private func go(_ next: Step) {
        withAnimation(.smooth(duration: CircleMotion.standard)) {
            step = next
            progress = next == .keepGoing ? sessionTotal : 0
            completing = false
            openSection = nil
        }
    }

    private func requestCentre(_ id: String) { centre = (id, centre.1 + 1) }

    #if DEBUG
    /// `-zikrTourFrom <step raw value>`: on its own, straight to that step (its task: the first Astaghfirullah one).
    static var debugStarted = false
    func debugStart(_ raw: Int, task: TaskModel?) {
        guard let s = Step(rawValue: raw) else { return }
        inAppTour = false
        taskID = task?.id
        go(s)
    }
    #endif

    // MARK: The bubble

    private typealias C = TourCopy.ZikrTour

    /// The bubble now: the chapter's steps so far (the finished ones folded), the current one open.
    var page: TourPage {
        guard let step else { return TourPage(headline: C.title) }
        let index = inAppTour ? 3 : 0
        if step == .offer {
            return TourPage(headline: C.title, index: index, progress: 0,
                            sections: [TourSection(id: "zt.offer", lead: C.offer)],
                            primary: C.showMe, secondary: inAppTour ? C.skipToSettings : C.notNow)
        }
        // Where each step sits: its section, its lead, its one to-do.
        func section(_ id: String, _ title: String, from: Step, to: Step, lead: String, todo: String?,
                     needed: Int = 0) -> TourSection? {
            guard step >= from else { return nil }
            var s = TourSection(id: id, title: title, done: step > to, lead: lead, tasks: todo.map { [$0] } ?? [])
            if step <= to, needed > 1, !completing { s.progress = (progress, needed) }
            return s
        }
        let kindsLead = reused ? C.reuseLead : C.kindsLead
        let taskLead: String = switch step {
            case .pick: C.pickLead
            case .goal: C.goalLead
            case .place: C.placeLead
            default: C.reviewLead
        }
        let taskTodo: String = switch step {
            case .pick: C.pickTodo
            case .goal: C.goalTodo
            case .place: C.placeTodo
            default: C.reviewTodo
        }
        let countLead: String = switch step {
            case .start: reused ? C.reuseLead : C.startLead
            case .taps: C.tapLead
            case .drags: C.dragLead
            case .stroke: C.strokeLead
            default: C.goLead(countGoal)
        }
        let countTodo: String = switch step {
            case .start: C.startTodo
            case .taps: C.tapTodo
            case .drags: C.dragTodo
            case .stroke: C.strokeTodo
            default: C.goTodo(countGoal)
        }
        let countNeeded = switch step { case .taps, .drags, .stroke: 3; case .keepGoing: countGoal; default: 0 }
        let streakText = outcome.map { C.streakLead(counted: $0.counted, goal: $0.goal, streak: $0.streak, met: $0.met, task: $0.task) }
            ?? "Every day you meet your goal, your streak grows."
        let streakLead = streakText   // the results page shows the pace itself
        let timeLead = step == .yourTasks ? C.tasksLead : skippedCount ? "\(C.reuseDoneLead) \(C.timeLead)" : C.timeLead
        let whereLead: String = switch step {
            case .history: C.historyLead
            case .historyPage: C.historyPageLead
            case .azkar: C.azkarLead
            default: C.azkarPageLead
        }
        let whereTodo: String? = switch step {
            case .history: C.historyTodo
            case .azkar: C.azkarTodo
            default: nil
        }
        var sections: [TourSection] = [
            reused ? section("zt.kinds", C.kindsStep, from: .kinds, to: .kinds, lead: kindsLead, todo: nil)
                   : section("zt.kinds", C.kindsStep, from: .kinds, to: .kinds, lead: kindsLead, todo: C.kindsTodo),
            reused ? nil : section("zt.task", C.taskStep, from: .pick, to: .review, lead: taskLead, todo: taskTodo),
            skippedCount ? nil : section("zt.count", C.countStep, from: .start, to: .keepGoing, lead: countLead, todo: countTodo, needed: countNeeded),
            skippedCount ? nil : section("zt.streak", C.streakStep, from: .results, to: .results, lead: streakLead, todo: C.streakTodo),
            // How long tasks take, History, Azkar: only when today's count was already done (nothing to count, so the
            // tour shows those instead); otherwise it ends at the results (owner, 2026-10-08).
            skippedCount ? section("zt.time", C.timeStep, from: .timeLeft, to: .yourTasks, lead: timeLead,
                                   todo: step == .timeLeft ? C.timeTodo : nil) : nil,
            skippedCount ? section("zt.where", C.whereStep, from: .history, to: .azkarPage, lead: whereLead, todo: whereTodo) : nil,
        ].compactMap { $0 }
        // Reused task: the kinds line shows straight away, as done.
        if reused, step >= .start, let i = sections.firstIndex(where: { $0.id == "zt.kinds" }) { sections[i].done = true }
        if step == .done { sections.append(TourSection(id: "zt.done", note: C.doneLine(met: outcome?.met ?? true, counted: outcome?.counted ?? 0, goal: outcome?.goal ?? 0))) }
        let units = 6.0
        let finished = Double([Step.kinds, .review, .keepGoing, .results, .yourTasks, .azkarPage].filter { $0 < step }.count)
        let primary: String? = switch step {
            case .yourTasks, .historyPage, .azkarPage: TourCopy.continueButton
            case .done: inAppTour ? TourCopy.continueButton : C.doneButton
            default: nil
        }
        return TourPage(headline: C.title, index: index, progress: step == .done ? 1 : finished / units,
                        sections: sections, primary: primary)
    }

    /// Which place the current step's bubble belongs to.
    enum Place { case zikrPage, newTask, session, results, yourTasks, history, azkar }
    var place: Place? {
        switch step {
        case nil: nil
        case .offer, .kinds, .start, .timeLeft, .history, .azkar, .done: .zikrPage
        case .pick, .goal, .place, .review: .newTask
        case .taps, .drags, .stroke, .keepGoing: .session
        case .results: .results
        case .yourTasks: .yourTasks
        case .historyPage: .history
        case .azkarPage: .azkar
        }
    }
}

/// The Zikr Tour's bubble — the tour's own (TourPageView in our rounded glass), wherever the step is.
struct ZikrTourBubble: View {
    @State private var tour = ZikrTour.shared
    var onSecondary: () -> Void = {}
    @Environment(\.tourShowMe) private var showMe
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @AppStorage(TourInk.lookKey) private var lookRaw = TourBubbleLook.glass.rawValue

    /// Always the slim strip in the Zikr tab (owner, 2026-10-09: "i dont want the tooltip bubble anywhere in the zikr
    /// tab"); a step with a button (the end, Continue) carries it in the strip.
    static var mode: TourGuideMode { .strip }

    var body: some View {
        let page = tour.page
        if let primary = page.primary {
            // A step to read, with its button: its line, the button under it.
            let section = page.activeSection
            let line = section?.lead ?? section?.note ?? page.subline ?? ""
            TourCoachStrip(chapter: section?.title ?? page.headline, todos: [line], ticked: [],
                           extra: (primary, { tour.step == .offer ? showMe() : tour.next() }), extraProminent: true)
                .frame(maxWidth: 400)
        } else {
            TourCoachStrip(chapter: page.headline, lead: tour.step == .results ? page.activeSection?.lead : page.shortLead,
                           todos: page.currentTodos,
                           ticked: tour.completing ? [0] : [], locked: page.locked, progress: page.activeSection?.progress)
                .frame(maxWidth: 400)
        }
    }
}

/// The bubble in one place (New task, the session, the results, a page): drawn only while the step is there.
struct ZikrTourInline: View {
    let place: ZikrTour.Place
    var alignment: Alignment = .bottom
    var padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 40, trailing: 0)
    @State private var tour = ZikrTour.shared
    var body: some View {
        if tour.place == place {
            ZikrTourBubble()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(padding)
                .transition(.opacity)
        }
    }
}

/// The Zikr page's layer: the offer and the page's steps, the only touches let through, Skip top right, the first-visit
/// offer.
struct ZikrTourLayer: View {
    let covered: Bool
    let onZikr: Bool
    @State private var tour = ZikrTour.shared
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @Environment(\.modelContext) private var context

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let t = TourTargets.shared
            ZStack {
                if !covered, onZikr, tour.place == .zikrPage {
                    TourInputGuard(openings: openings(t)) {}
                    bubble(t, origin: origin, height: proxy.size.height)
                    TourSkipButton {
                        tour.dismiss()
                        if TourRuntime.shared.active { TourRuntime.shared.skip() }
                    }
                    .opacity(tour.step == .offer || tour.step == .done ? 0 : 1)   // the offer and the end have their own buttons
                    .allowsHitTesting(tour.step != .offer && tour.step != .done)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, (t.frame("historyDoor").map { $0.midY - origin.y } ?? 76) - 16)
                    .padding(.trailing, 60)
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: tour.step)
        }
        .ignoresSafeArea()
        #if DEBUG
        .task {   // once per launch: the layer comes back after every pushed page
            if !ZikrTour.debugStarted, let i = CommandLine.arguments.firstIndex(of: "-zikrTourFrom"),
               i + 1 < CommandLine.arguments.count, let raw = Int(CommandLine.arguments[i + 1]) {
                ZikrTour.debugStarted = true
                try? await Task.sleep(for: .seconds(2))
                tour.debugStart(raw, task: tasks.first { ZikrTour.isAstaghfirullah($0.mantra?.name ?? $0.mantraName) })
            }
        }
        #endif
        // The first Zikr visit: offered once, if the tour hasn't been seen (not over the app tour, not before setup) —
        // and not while the page is locked: the lock's card is the offer then (ZikrLock).
        .onChange(of: onZikr, initial: true) { _, on in
            guard on, !covered, !tour.active, !TourRuntime.shared.active, FirstRunSetup.isDone, !ZikrLock.shared.locked,
                  !ZikrTour.completed, !UserDefaults.standard.bool(forKey: ZikrTour.offeredKey) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                guard onZikr, !tour.active, !TourRuntime.shared.active else { return }
                tour.offer(inAppTour: false)
            }
        }
    }

    @ViewBuilder private func bubble(_ t: TourTargets, origin: CGPoint, height: CGFloat) -> some View {
        let slot = t.frame("zikrSlot")
        let bubble = ZikrTourBubble(onSecondary: { tour.dismiss() })
            .environment(\.tourShowMe, {
                let task = tasks.first { ZikrTour.isAstaghfirullah($0.mantra?.name ?? $0.mantraName) }
                let dayStart = PrayerDay.sessionDayStart()
                let today = (try? context.fetch(FetchDescriptor<SessionDataModel>(
                    predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
                tour.showMe(existing: task, doneToday: task.map { $0.isCompleted(with: $0.progress(in: today)) } ?? false)
            })
        if ZikrTourBubble.mode == .strip {
            let target = openings(t).first.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            bubble.tourStripPlaced(top: tour.step == .done || TourStripPlace.top(target: target, height: height),
                                   size: CGSize(width: UIScreen.main.bounds.width, height: height),
                                   topInset: 112, bottomInset: 104)
        } else {
        switch tour.step {
        // Over the wheel (the line under it and the doors stay clear).
        case .offer, .kinds, .start:
            bubble.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(0, height - ((slot?.minY ?? 300) - origin.y) + 12))
        // Under the doors: History / Azkar.
        case .history, .azkar:
            bubble.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, (t.frame("historyDoor").map { $0.maxY - origin.y } ?? 100) + 12)
        // Over the line under the wheel (the end too: six ✓ lines don't fit above the wheel).
        default:
            bubble.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(0, height - ((t.frame("zikrSummary")?.minY ?? 600) - origin.y) + 12))
        }
        }
    }

    /// The one thing the step asks for: the circle at the wheel's middle, the line under it, a door.
    private func openings(_ t: TourTargets) -> [CGRect] {
        switch tour.step {
        case .kinds, .start: t.frame("zikrSlot").map { [$0] } ?? []
        case .timeLeft: t.frame("zikrSummary").map { [$0] } ?? []
        case .history: t.frame("historyDoor").map { [$0.insetBy(dx: -8, dy: -8)] } ?? []
        case .azkar: t.frame("azkarDoor").map { [$0.insetBy(dx: -8, dy: -8)] } ?? []
        default: []
        }
    }
}

/// The offer's Show me (the page knows their tasks; the bubble doesn't).
private struct TourShowMeKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var tourShowMe: () -> Void {
        get { self[TourShowMeKey.self] }
        set { self[TourShowMeKey.self] = newValue }
    }
}

/// The Zikr Tour over its session: counting low on the screen (not on the pause screen), the results over Done; Skip top
/// right, left of −.
struct ZikrTourSessionLayer: View {
    let paused: Bool
    let results: Bool
    @State private var tour = ZikrTour.shared
    /// The session's ring has landed (it glides in from the circle it opened out of): only then the card, the hint
    /// and Skip come in — over the ring, the card hid the opening's move.
    @State private var settled = false

    private var hintKind: GestureHint.Kind? {
        guard !tour.completing, tour.progress == 0 else { return nil }
        switch tour.step {
        case .taps: return .tap
        case .drags: return .drag
        case .stroke: return .stroke
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let t = TourTargets.shared
            ZStack {
                // The counter's welcome first (its own moment, not a bubble): the lessons wait for "Let's begin".
                if tour.step == .taps, !tour.welcomed, !paused, !results, settled {
                    CounterWelcome { withAnimation(.easeInOut(duration: 0.45)) { tour.practiced() } }
                        .transition(.opacity)
                }
                if tour.place == .session, !paused, !results, settled, tour.welcomed || tour.step != .taps {
                    // A ghost finger showing the move (owner, 2026-10-08), until they've done it once.
                    CounterGestureHint(kind: hintKind)
                    ZikrTourBubble()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 56)
                        .transition(.opacity)
                    TourSkipButton {
                        tour.dismiss()
                        if TourRuntime.shared.active { TourRuntime.shared.skip() }
                    }
                    .opacity(tour.step == .offer || tour.step == .done ? 0 : 1)   // the offer and the end have their own buttons
                    .allowsHitTesting(tour.step != .offer && tour.step != .done)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, (t.frame("ct.finish").map { $0.midY - origin.y } ?? 76) - 16)
                    .padding(.trailing, t.frame("ct.finish").map { proxy.size.width - ($0.minX - origin.x) + 10 } ?? 72)
                }
                // At the top, where the results page is empty (owner: "the strip is still obstructing. move the strips
                // to the top when applicable").
                if tour.place == .results, results {
                    ZikrTourBubble()
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, proxy.safeAreaInsets.top + 62)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: CircleMotion.quick), value: tour.step)
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.35)) { settled = true }
        }
    }
}

/// The counter's welcome in the Zikr Tour (owner, 2026-10-09: "a nice welcome and just explains we gonna show them the
/// different ways to count and we'll do it together"; then "three different boxed areas in an hstack that has each ghost
/// finger graphic in it and they can satisfy the taps in those graphics before starting the actual counter … a green
/// border … a cross on its caption … each time they satisfy one flash that area's border"): the page's own colour over
/// the counter, three practice boxes, "Let's begin" once all three are done. It takes every touch, so nothing counts
/// under it; the boxes' moves are practice only.
struct CounterWelcome: View {
    let onBegin: () -> Void
    /// "Let's begin" once this many are done (owner: "if they go ahead and satisfy one of them, they can skip forward").
    var minimumDone = 1
    @Environment(\.circleTheme) private var theme
    @State private var done: Set<GestureHint.Kind> = []
    private typealias C = TourCopy.ZikrTour

    var body: some View {
        ZStack {
            theme.backdrop.opacity(0.96)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: 0) {
                Text(C.welcomeKicker.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.4)
                    .foregroundStyle(Color.sage)
                Text(C.welcomeTitle)
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .padding(.top, 12)
                Text(C.welcomeBody)
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.top, 14)
                HStack(alignment: .top, spacing: 10) {
                    PracticeBox(kind: .tap, caption: C.practiceTap) { done.insert(.tap) }
                    PracticeBox(kind: .drag, caption: C.practiceDrag) { done.insert(.drag) }
                    PracticeBox(kind: .stroke, caption: C.practiceStroke) { done.insert(.stroke) }
                }
                .padding(.top, 30)
                Button(action: onBegin) {
                    HStack(spacing: 6) {
                        Text(C.welcomeButton)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .opacity(done.count >= minimumDone ? 1 : 0.3)
                .disabled(done.count < minimumDone)
                .animation(.easeInOut(duration: 0.3), value: done.count)
                .padding(.top, 30)
            }
            .padding(.horizontal, 18)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// One way to count, to try: its ghost finger looping inside, three of the move to fill it. Each right move flashes the
/// border green; three, and the border stays green, the caption crossed out. A stroke's three are in one touch.
/// While a finger is down the box presses in, the ghost steps aside and an arrow shows the next move; a wrong move
/// flashes the border red and says why in a few words (owner: "it doesn't tell you if you're wrong … show me what to
/// do now that I'm holding the box down … minimal").
private struct PracticeBox: View {
    let kind: GestureHint.Kind
    let caption: String
    let onDone: () -> Void
    @State private var count = 0
    @State private var flash: Color?
    @State private var why: String?
    @State private var pressed = false
    @State private var pressedAt = Date()
    // A drag's way, as the counter reads it: down past `step` counts, back up half of it re-arms.
    @State private var highest: CGFloat = 0
    @State private var lowest: CGFloat = 0
    @State private var armed = true
    @State private var strokes = 0
    @State private var whyTask: Task<Void, Never>?
    private static let needed = 3
    private static let step: CGFloat = 40
    private var isDone: Bool { count >= Self.needed }

    var body: some View {
        let box = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 10) {
            ZStack {
                NeuPressed(shape: box, radius: 5, offset: 3)
                GestureHint(kind: kind, height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .opacity(isDone ? 0.2 : (pressed ? 0 : 1))
                // Held: the next move.
                if pressed, !isDone, kind != .tap {
                    Image(systemName: armed ? "arrow.down" : "arrow.up")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.sage)
                        .id(armed)
                        .transition(.opacity)
                }
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.sage)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 170)
            .overlay(box.strokeBorder(border, lineWidth: flash != nil ? 3 : (isDone ? 2 : 1.5)))
            .scaleEffect(pressed && !isDone ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .animation(.easeOut(duration: 0.15), value: armed)
            .contentShape(box)
            .gesture(practice)
            .allowsHitTesting(!isDone)
            Text(caption)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .strikethrough(isDone, color: Color.sage)
                .foregroundStyle(isDone ? Color.sage : Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                HStack(spacing: 5) {
                    ForEach(0..<Self.needed, id: \.self) { i in
                        Circle().fill(i < count ? Color.sage : Color.primary.opacity(0.15)).frame(width: 6, height: 6)
                    }
                }
                .opacity(why == nil ? 1 : 0)
                if let why {
                    Text(why)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 16)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: isDone)
        .animation(.easeOut(duration: 0.2), value: why)
    }

    /// Green flashing a right move, red a wrong one; green to stay once done; a quiet edge while held.
    private var border: Color {
        if let flash { return flash }
        if isDone { return .sage }
        return pressed ? Color.primary.opacity(0.3) : .clear
    }

    /// One gesture for every box: it sees the press, the way, and the lift, so a wrong move can be told apart.
    private var practice: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !pressed { pressed = true; pressedAt = Date(); strokes = 0 }
                guard kind == .stroke else { return }
                let y = v.translation.height
                highest = min(highest, y)
                lowest = max(lowest, y)
                if armed && y - highest > Self.step {
                    armed = false
                    lowest = y
                    strokes += 1
                    hit()
                } else if !armed && lowest - y > Self.step / 2 {
                    armed = true
                    highest = y
                }
            }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                let moved = max(abs(dx), abs(dy)) > 10
                let held = Date().timeIntervalSince(pressedAt)
                pressed = false
                highest = 0; lowest = 0; armed = true
                guard !isDone else { return }
                switch kind {
                case .tap:
                    if moved { wrong("Just tap") } else if held > 0.6 { wrong("A quick tap") } else { hit() }
                case .drag:
                    if !moved { wrong("Drag down") }
                    else if dy < 0 { wrong("Down, not up") }
                    else if dy < Self.step { wrong("A bit further") }
                    else { hit() }
                case .stroke:
                    if strokes == 0 { wrong(moved ? "Down, then up" : "Hold and drag") }
                    else { wrong("Keep your finger down"); withAnimation(.easeOut(duration: 0.2)) { count = 0 } }
                }
            }
    }

    private func hit() {
        guard !isDone else { return }
        withAnimation(.easeOut(duration: 0.15)) { count += 1; flash = .sage; why = nil }
        if isDone {
            triggerSomeVibration(type: .success)
            onDone()
        } else {
            triggerSomeVibration(type: .light)
        }
        clearFlash()
    }

    private func wrong(_ reason: String) {
        triggerSomeVibration(type: .warning)
        withAnimation(.easeOut(duration: 0.15)) { flash = .red; why = reason }
        clearFlash()
        whyTask?.cancel()
        whyTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { why = nil }
        }
    }

    private func clearFlash() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeIn(duration: 0.3)) { flash = nil }
        }
    }
}
