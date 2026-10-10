//
//  DailyTasksView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers


/// The Zikr page (redesigned 2026-09-25 — owner: keep the circle theme, give the tasks the
/// room the fixed freestyle circle was using): a vertical wheel of circles — freestyle first,
/// then each daily task as a circle with today's progress as its ring, then a dashed "new
/// task" circle. Scrolls up and down one circle at a time; the ones off-centre shrink and fade
/// (the old card strip's effect, turned on its side). Tap a circle to bring it to the middle,
/// tap the middle one to start. Long-press a task for edit / reorder / delete. Dots on the left (drag them to scrub)
/// show where you are, green for the tasks done today.
struct ZikrPageView: View {
    @Binding var showMantraSheetFromHomePage: Bool
    @Binding var showTasbeehPage: Bool

    var body: some View {
        ZikrCircleWheel(showTasbeehPage: $showTasbeehPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Locked until the Zikr Tour is done (ZikrLock.swift): the wheel blurred under a glass pane — something's
            // there — and the way in.
            .blur(radius: ZikrLock.shared.covering ? 12 : 0)
            .allowsHitTesting(!ZikrLock.shared.covering)
            .overlay {
                if ZikrLock.shared.covering {
                    ZikrLockCover().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: ZikrLock.shared.locked)
    }
}

/// A task to bring to the middle of the Zikr wheel (from a Zikr widget row). Held until the wheel
/// is there to take it (a cold launch mounts it after the request).
enum ZikrFocus {
    static let notification = Notification.Name("zikrFocusTask")
    /// The task to centre, kept until the wheel has it (its tasks may not be loaded yet on a cold launch) — for
    /// `keep` at most (widget-open-chrome: "the task focus isn't reliable").
    static var pending: String? {
        guard let p = pendingID, Uptime.now - requestedAt < keep else { return nil }
        return p
    }
    private static var pendingID: String?
    private static var requestedAt: Double = 0
    private static let keep: Double = 3
    /// Centre it at once, no wheel turn (a widget open goes straight there).
    private(set) static var instant = false
    static func request(_ taskID: String, instant: Bool = false) {
        pendingID = taskID
        requestedAt = Uptime.now
        self.instant = instant
        NotificationCenter.default.post(name: notification, object: nil)
    }
    static func take() -> String? { defer { pendingID = nil; instant = false }; return pending }

    /// Start a task's session from elsewhere (a zikr's page, owner 2026-09-30): the app closes
    /// what covers it, goes to the Zikr page, and the wheel starts it (`resume`: from today's count).
    static let startNotification = Notification.Name("zikrStartTask")
    static let wheelStartNotification = Notification.Name("zikrWheelStartTask")
    private(set) static var pendingStart: (id: String, resume: Bool)?
    /// Where on screen the session opens out of, when it isn't the wheel's own ring (the Zikr lock's page 3 circle;
    /// owner: "start the counting session straight from this page using the task ring").
    private(set) static var startFrame: CGRect?
    static func start(_ taskID: String, resume: Bool, from frame: CGRect? = nil) {
        pendingStart = (taskID, resume)
        startFrame = frame
        NotificationCenter.default.post(name: startNotification, object: nil)
    }
    static func takeStartFrame() -> CGRect? { defer { startFrame = nil }; return startFrame }
    static func takeStart() -> (id: String, resume: Bool)? { defer { pendingStart = nil }; return pendingStart }
    /// A deleted task can't be focused later.
    static func forget(_ ids: [String]) { if let p = pendingID, ids.contains(p) { pendingID = nil } }
}

struct ZikrCircleWheel: View {
    @Environment(SharedStateClass.self) var sharedState
    @Environment(\.modelContext) private var context
    /// The zikr Freestyle counts under, by name ("" = just count) — the watch's "Pick a zikr" (owner, 2026-10-06:
    /// "i love the pick a zikr thing in the watch. but its not in the ios app"). Kept until changed, like the watch's.
    @AppStorage("freestylePick") private var freestylePick = ""
    @State private var showFreestylePicker = false
    @State private var importing: ImportedTask?
    @State private var pickedMantra: MantraModel?
    @Query(sort: \TaskModel.sortOrder) private var storedTasks: [TaskModel]
    @Query private var storedSessions: [SessionDataModel]
    /// The tour's Zikr chapter shows its example tasks instead (TourExamples, Tour.swift): never saved, never started.
    private var tasks: [TaskModel] { TourExamples.shared.tasks ?? storedTasks }
    private var todaysSessions: [SessionDataModel] { TourExamples.shared.sessions ?? storedSessions }
    @Binding var showTasbeehPage: Bool

    @State private var centered: String? = Item.freestyle.id
    @State private var showAddTask = false
    @State private var newTaskScrollTarget: UUID?
    /// A long-press on a task opens the Tasks sheet on that task's edit screen (owner, 2026-09-29,
    /// zikr-tasks-sheet: jiggle mode is gone; the sheet reorders, edits and deletes).
    @State private var tasksSheetOn: TaskModel?
    /// The hold menu's Open zikr / Delete….
    @State private var wheelOpenZikr: MantraModel?
    @State private var wheelDelete: TaskModel?
    /// How the circles fall away from the middle (Settings → My Dev Stuff while the owner picks).
    @AppStorage(ZikrWheelStyle.key) private var wheelStyleRaw = ZikrWheelStyle.gentle.rawValue
    /// A task tapped with some of today's goal already done: continue or start over?
    @State private var resumeAsk: TaskModel?
    /// A finger on the dots: they become a scrubber (like dragging a page's scroll bar).
    @State private var scrubbing = false
    /// The task a session was started from here, so coming back can move past it once it's done.
    @State private var sessionTaskID: UUID?
    /// The task a session just finished stays on the wheel until the session's ring has landed on it (full), then the wheel
    /// moves on and it leaves (owner, 2026-10-02: "from completion page back" — it left at once, and the full ring landed
    /// on the next task's).
    @State private var heldTaskID: UUID?
    /// The task's progress as it stood when its session opened: its ring shows that until the session's sheet has gone,
    /// then catches up in front of them (owner: "some sort of visual animation … so they comprehend how their ring has
    /// changed").
    @State private var ringHold: (id: UUID, progress: TaskProgress)?
    /// Under the soft look, a session opens out of the tapped ring (SessionHandoff): everything but that ring
    /// fades while it does, and back in as the session closes.
    @State private var openingSoft = false
    /// The centred ring's arc rewound for a session that starts from nothing (SessionHandoff, its landing base).
    @State private var arcRewound = false
    /// The wheel's own sequences (a start from elsewhere, a focus, landing after a session): one at a time, the latest
    /// cancelling the last (a landing left running cleared a new session's held task — audit E7).
    @State private var wheelTask: Task<Void, Never>?
    @State private var openingStyle: SessionOpening = .current
    /// Each circle's place on screen, kept outside state (written on every scroll frame; read only on a tap).
    @State private var circleFrames = CircleFrames()
    /// Until it's measured: the screen (the page runs nearly its full height).
    @State private var wheelBox = WheelBox(height: screenHeight ?? 800, minY: 0)
    final class CircleFrames { var byID: [String: CGRect] = [:] }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.circleTheme) private var theme

    init(showTasbeehPage: Binding<Bool>) {
        self._showTasbeehPage = showTasbeehPage
        let dayStart = PrayerDay.sessionDayStart()   // the prayer day (Fajr to Fajr)
        _storedSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= dayStart },
                                sort: \.startTime)
    }

    enum Item: Identifiable, Hashable {
        case freestyle, task(TaskModel), add
        var id: String {
            switch self {
            case .freestyle: "freestyle"
            case .task(let task): task.id.uuidString
            case .add: "add"
            }
        }
    }

    private let itemHeight: CGFloat = 250

    private func progress(_ task: TaskModel) -> TaskProgress { task.progress(in: todaysSessions) }
    private func isDone(_ task: TaskModel) -> Bool { task.isCompleted(with: progress(task)) }

    /// Freestyle, the tasks still to do today in the user's order (set in the Tasks sheet), then "new
    /// task". A finished task leaves the wheel (owner, 2026-09-30, note 5FB4D4B1: "just straight up hide
    /// any tasks that are finished"); the summary under the wheel opens the Tasks sheet with all of
    /// them. Coming back from a session centres the next one still to do (`landAfterSession`).
    private var items: [Item] {
        [.freestyle] + tasks.filter { !isDone($0) || $0.id == heldTaskID }.map { .task($0) } + [.add]
    }
    /// The summary's tap: Your tasks, the whole list, finished ones included (a page).
    @State private var showTasksPage = false

    var body: some View {
        wheel
            .overlay(alignment: .bottom) {
                // "2 of 9 tasks done" opens Your tasks (owner): the full list, what's finished.
                Button {
                    // The tours: the summary stays put — except the Zikr Tour's step that opens it.
                    if ZikrTour.shared.step == .timeLeft { ZikrTour.shared.summaryTapped() }
                    else if TourRuntime.shared.active || ZikrTour.shared.active { TourRuntime.shared.nudge(); return }
                    triggerSomeVibration(type: .light)
                    showTasksPage = true
                } label: {
                    tasksSummary
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows all your tasks")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("zikrSummary", $0) }
                .padding(.bottom, 100)
                .opacity(openingSoft ? 0 : 1)
                .allowsHitTesting(!openingSoft)
            }
            // Edit task: the task's review, the page that made it (task-edit-review-page).
            .sheet(item: $tasksSheetOn) { NewTaskFlow(editing: $0) }
            .navigationDestination(isPresented: $showTasksPage) {
                YourTasksPage()
                    // The Zikr Tour's "Hold and drag to change their order" (ZikrTour.swift), then back.
                    .overlay { ZikrTourInline(place: .yourTasks) }
                    .onChange(of: ZikrTour.shared.popPage) { _, _ in showTasksPage = false }
            }
            // The wheel's own pages say how to close them, so a reminder / widget / a start from elsewhere closes them
            // and waits until they've gone (the host's clearCovers) — it centred the task under Your tasks (audit E6).
            .onChange(of: showTasksPage) { _, open in
                CircleCover.set("yourTasks", open, close: { showTasksPage = false })
            }
            .sheet(item: $wheelOpenZikr) { MantraEditorView(mantra: $0).stageCover("wheelZikrPage") }
            .alert(wheelDelete.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "",
                   isPresented: Binding(get: { wheelDelete != nil }, set: { if !$0 { wheelDelete = nil } }),
                   presenting: wheelDelete) { task in
                Button("Delete Task", role: .destructive) {
                    withAnimation { TaskModel.delete(task, in: context) }
                    wheelDelete = nil
                }
                Button("Cancel", role: .cancel) { wheelDelete = nil }
            } message: { _ in
                Text("Its reminder goes too. The sessions you've counted stay in your history.")
            }
            // A task finished while it's in the middle (or anywhere) leaves the wheel: land on the
            // next one still to do rather than on a gap.
            .onChange(of: items.map(\.id)) { _, ids in
                if let c = centered, !ids.contains(c) {
                    withAnimation(CircleMotion.wheelCentre) {
                        centered = tasks.first(where: { $0.id.uuidString == c }).map { nextFocus(after: $0) } ?? Item.freestyle.id
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ZikrFocus.notification)) { _ in focusPending() }
            // The tasks arriving after the request (a cold launch): the request is still there for them.
            .onChange(of: tasks.count) { _, _ in focusPending() }
            .onReceive(NotificationCenter.default.publisher(for: ZikrFocus.wheelStartNotification)) { _ in startPending() }
            .onAppear { focusPending() }
    }

    /// "1 of 3 tasks done · about 14 min to go" / "all 3 tasks done today".
    private func summaryText(done: Int, secondsLeft: TimeInterval) -> String {
        if done == tasks.count { return "all \(tasks.count) tasks done today" }
        let base = "\(done) of \(tasks.count) tasks done"
        guard secondsLeft > 0 else { return base }
        let estimate = zikrEstimateString(secondsLeft).replacingOccurrences(of: "~", with: "")
        return base + " · about " + estimate + " to go"
    }

    /// A start asked for from a zikr's page: centre that task, then start it (no second question —
    /// the page already asked).
    private func startPending() {
        // Locked (ZikrLock): nothing starts from outside; the page shows its lock.
        if ZikrLock.shared.locked { _ = ZikrFocus.takeStart(); return }
        guard let request = ZikrFocus.pendingStart,
              let task = tasks.first(where: { $0.id.uuidString == request.id }) else { return }
        _ = ZikrFocus.takeStart()
        wheelTask?.cancel()
        // Opening out of a ring elsewhere (the lock's page 3): no turn of the wheel under it, straight in from there.
        if let frame = ZikrFocus.takeStartFrame() {
            var quiet = Transaction(); quiet.disablesAnimations = true
            withTransaction(quiet) { centered = request.id }
            start(task, resume: request.resume, from: frame)
            return
        }
        wheelTask = Task { @MainActor in
            // Centred first (a finished task isn't on the wheel: started without centring), then started once the
            // wheel has got there — it read the ring's place 0.45 s into the spring, a guess (audit E5).
            if !isDone(task) {
                await CircleMotion.animate(CircleMotion.wheelCentre) { centered = request.id }
            }
            guard !Task.isCancelled else { return }
            start(task, resume: request.resume)
        }
    }

    /// Scroll a widget-requested task to the middle (after the page has come in).
    private func focusPending() {
        guard let id = ZikrFocus.pending, let task = tasks.first(where: { $0.id.uuidString == id }) else { return }
        guard !isDone(task) else { _ = ZikrFocus.take(); return }   // finished: not on the wheel
        let instant = ZikrFocus.instant
        _ = ZikrFocus.take()
        wheelTask?.cancel()
        if instant {   // from a widget: already in the middle when the page shows, no turn
            var quiet = Transaction(); quiet.disablesAnimations = true
            withTransaction(quiet) { centered = id }
            return
        }
        wheelTask = Task { @MainActor in
            // Once the Zikr page has come in (it was a guessed 0.35 s).
            _ = await CircleStage.shared.until(deadline: 2) { CircleStage.shared.restingPage == .zikr }
            guard !Task.isCancelled else { return }
            withAnimation(CircleMotion.wheelCentre) { centered = id }
        }
    }

    /// "1 of 3 tasks done" under the wheel (the old strip's "1 of 3 Completed"); all done → sage.
    @ViewBuilder private var tasksSummary: some View {
        if !tasks.isEmpty {
            let done = tasks.filter { isDone($0) }.count
            // Everything left at your pace (tasks with no history yet are left out).
            let left = tasks.filter { !isDone($0) }.compactMap { $0.secondsLeft(progress($0)) }.reduce(0, +)
            HStack(spacing: 5) {
                if done == tasks.count { Image(systemName: "checkmark") }
                Text(summaryText(done: done, secondsLeft: left))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.6)
            }
            .font(.footnote)
            .fontWeight(.light)
            .fontDesign(.rounded)
            .foregroundStyle(done == tasks.count ? Color.sage : .secondary)
            .animation(.snappy, value: done)
        }
    }

    private var wheel: some View {
        let items = items
        let box = wheelBox
        return ScrollView(.vertical, showsIndicators: false) {
                // Never lazy (CLAUDE.md): a lazy stack only estimates rows it hasn't built, so centring a task further
                // down (a widget open, `scrollPosition` set before layout) landed on a neighbour (widget-open-chrome).
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        let away = openingSoft && item.id != centered
                        circle(for: item)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                circleFrames.byID[item.id] = frame
                                if item.id == centered {
                                    TourTargets.shared.set("zikrCircle", frame)
                                    // The wheel's centre slot: where the centred circle rests, whatever the scroll is
                                    // doing — the tour's bubble keeps to it (owner: it moved with the scroll).
                                    let mid = wheelBox.minY + wheelBox.height / 2
                                    TourTargets.shared.set("zikrSlot", CGRect(x: frame.minX, y: mid - frame.height / 2,
                                                                              width: frame.width, height: frame.height))
                                }
                            }
                            // Opening a session out of the centred ring (SessionHandoff): the others go the opening's
                            // way (sink / focus / fade); the centred one keeps its ring and lets its label go.
                            .modifier(SessionAppear(shown: !away, style: openingStyle))
                            .environment(\.zikrFaceContentAway, openingSoft && item.id == centered)
                            .environment(\.zikrFaceArcRewound, arcRewound && item.id == centered)
                            .frame(maxWidth: .infinity)
                            .frame(height: itemHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { tapped(item) }
                            .id(item.id)
                            // Size and fade follow the circle's distance from the middle in rows,
                            // easing out (owner: more dramatic, and not at its smallest the moment it
                            // leaves the middle): one row away ≈ 0.62×, two ≈ 0.45×, never below
                            // 0.38×. Neighbours are pulled in so shrinking doesn't open gaps.
                            .modifier(WheelFalloff(itemHeight: itemHeight,
                                                   style: ZikrWheelStyle(rawValue: wheelStyleRaw) ?? .gentle))
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, max((box.height - itemHeight) / 2, 0), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $centered, anchor: .center)
            // Soft edges under the page's title and bottom bar.
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0.06), .init(color: .black, location: 0.2),
                                       .init(color: .black, location: 0.8), .init(color: .clear, location: 0.94)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .leading) {   // left edge (owner)
                scrubber(items).opacity(openingSoft ? 0 : 1).allowsHitTesting(!openingSoft)
            }
            // Centre the focused circle on the SCREEN (owner): the page starts under the status
            // bar and runs to the bottom edge, so its own middle sits a little low. Shift the
            // whole wheel up by the difference (scroll snapping always centres in its own frame).
            .offset(y: -screenCentreShift(box))
            // Measured outside the shift (measured inside it, each shift moved what it's worked out from: a loop).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color.clear.onGeometryChange(for: WheelBox.self) {
                    WheelBox(height: $0.size.height, minY: $0.frame(in: .global).minY)
                } action: { wheelBox = $0 }
            }
        .onChange(of: centered) { old, id in
            triggerSomeVibration(type: .light)
            ZikrWheelFocus.shared.centre(id, from: old, in: items.map(\.id))   // the top bar's title
            if TourRuntime.shared.active { TourRuntime.shared.event(.wheelScrolled) }   // the Zikr chapter's to-do
        }
        .onAppear {
            ZikrWheelFocus.shared.centre(centered, from: nil, in: items.map(\.id))
            startPending()   // a start asked for before the wheel was there (it waited for the next notification)
        }
        #if DEBUG
        .task { TaskStreakDebug.log(tasks) }
        .fullScreenCover(isPresented: .constant(StreakHeroDemo.streak != nil)) {
            if let s = StreakHeroDemo.streak { StreakHeroDemo(streak: s) }
        }
        #endif
        .onAppear {
            if let task = sharedState.selectedTask { centered = task.id.uuidString }
        }
        // A task someone shared, on its review (TaskSharing); on a layer of its own beside the New task sheet.
        .background {
            Color.clear
                .sheet(item: $importing) { shared in
                    NewTaskFlow(importing: shared) { newTaskScrollTarget = $0.id }   // the wheel centres it
                }
        }
        #if DEBUG
        .task { await TaskSharing.demo(context) }
        #endif
        // A shared task waits until Zikr is unlocked and no tour runs (ZikrLock), then opens.
        .onChange(of: TaskSharing.shared.ready && ZikrLock.shared.unlocked && !ZikrTour.shared.active, initial: true) { _, open in
            if open, let shared = TaskSharing.shared.take(in: context) { importing = shared }
        }
        .sheet(isPresented: $showAddTask, onDismiss: { ZikrTour.shared.taskFlowClosed() }) {
            NewTaskFlow {
                newTaskScrollTarget = $0.id   // the wheel centres it
                ZikrTour.shared.taskCreated($0)
            }
        }
        // The Zikr Tour centres what its step is about (New task, its task).
        .onChange(of: ZikrTour.shared.centre.1) { _, _ in
            let id = ZikrTour.shared.centre.0
            guard items.contains(where: { $0.id == id }) else { return }
            withAnimation(CircleMotion.wheelCentre) { centered = id }
        }
        #if DEBUG
        .task {   // -demoYourTasks: Your tasks open (with -demoZikrTasksEdit N, task N's review over it)
            guard ProcessInfo.processInfo.arguments.contains("-demoYourTasks") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showTasksPage = true
        }
        .task {   // -demoNewTaskStep N: the flow open at step N
            guard UserDefaults.standard.integer(forKey: "demoNewTaskStep") > 0 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showAddTask = true
        }
        #endif
        .onChange(of: newTaskScrollTarget) { _, id in
            if let id { withAnimation(CircleMotion.wheelCentre) { centered = id.uuidString } }
        }
        // Back from a task's session: once it's done, land on the next task — after it in your
        // order, the first not done yet (wrapping), else freestyle (owner, 2026-09-28). The done
        // task stays where it is (2026-09-29).
        // The session's close says when its page is about to go (SessionHandoff `.revealing`): the ring's label and the
        // other circles come back under it — at once under the still-opaque page, or fading with a crossfading
        // session (Reduce Motion) — and its arc, where the session's has just landed. They ran on their own copy of
        // the session's timings (0.25 s, 0.45 s, `arcMove`) before (audit E3).
        .onChange(of: SessionHandoff.shared.phase == .revealing) { _, revealing in
            guard revealing else { return }
            if openingStyle == .fade {
                withAnimation(.easeOut(duration: CircleMotion.quick)) { openingSoft = false }
            } else {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { openingSoft = false }
            }
            arcBack()
        }
        // The cover has gone (or a plain sheet is going): back, if the close didn't bring it already; then land on the
        // next task once the session's cover has really gone (it was a guessed 0.3 s).
        // Paces are kept until the store saves (PaceCache); a new session today drops them too.
        .onChange(of: storedSessions.count) { PaceCache.forget() }
        .onChange(of: showTasbeehPage) { _, showing in
            guard !showing else { return }
            if openingSoft { withAnimation(.easeInOut(duration: CircleMotion.quick)) { openingSoft = false } }
            arcBack()
            guard let finished = sessionTaskID else { heldTaskID = nil; return }
            sessionTaskID = nil
            wheelTask?.cancel()
            wheelTask = Task { @MainActor in
                _ = await CircleStage.shared.until(deadline: 2) { !CircleStage.shared.covers.contains("tasbeeh") }
                guard !Task.isCancelled else { return }
                await showProgress(finished)
                guard !Task.isCancelled else { return }
                landAfterSession(finished)
            }
        }
        #if DEBUG
        // `-demoFinishTask N` (with -demoZikrPage): centre task N, save a session that completes it,
        // then come back as from its session — the wheel should land on the next task (simulator).
        .task { await demoFinishTask() }
        #endif
        .alert(resumeAsk?.title ?? "",
               isPresented: Binding(get: { resumeAsk != nil }, set: { if !$0 { resumeAsk = nil } }),
               presenting: resumeAsk) { task in
            Button(resumeLabel(task)) { start(task, resume: true); resumeAsk = nil }
            Button("Start over") { start(task); resumeAsk = nil }
            Button("Cancel", role: .cancel) { resumeAsk = nil }
        } message: { task in
            let p = progress(task)
            Text(task.isCountMode
                 ? "You've done \(p.count) of \(task.goal) today. Pick up from there, or count a fresh \(task.goal)?"
                 : "You've done \(zikrDurationString(p.seconds)) of \(task.goal) min today. Pick up from there, or start a fresh \(task.goal) min?")
        }
    }

    #if DEBUG
    private func demoFinishTask() async {
        let n = UserDefaults.standard.integer(forKey: "demoFinishTask")
        guard n > 0 else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard n <= tasks.count else { return }
        let task = tasks[n - 1]
        withAnimation { centered = task.id.uuidString }
        try? await Task.sleep(for: .seconds(1.5))
        let counts = task.isCountMode
        let mode: Int = counts ? 2 : 1
        let minutes: Int = counts ? 0 : task.goal
        let target: Int = counts ? task.goal : 0
        let total: Int = counts ? task.goal : 60
        let seconds: Double = counts ? Double(task.goal) : Double(task.goal * 60)
        let session = SessionDataModel(title: task.displayName, sessionMode: mode,
                                       targetMin: minutes, targetCount: target,
                                       totalCount: total, startTime: Date(),
                                       secondsPassed: seconds,
                                       avgTimePerClick: 1, tasbeehRate: "1m 40s", task: task, mantra: task.mantra)
        context.insert(session)
        try? context.save()
        try? await Task.sleep(for: .seconds(1))
        print("🧪 demoFinishTask: finished \(task.title) (done \(isDone(task)))")
        landAfterSession(task.id)
    }
    #endif

    /// How far the page's middle sits below the screen's middle.
    private func screenCentreShift(_ box: WheelBox) -> CGFloat {
        let screenHeight = Self.screenHeight ?? box.minY + box.height
        let pageMid = box.minY + box.height / 2
        return min(max(pageMid - screenHeight / 2, 0), 80)
    }

    private static var screenHeight: CGFloat? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height
    }

    /// The wheel's height and its top on screen, measured — not a GeometryReader: one re-ran the whole wheel (every
    /// ring's body) on every frame of a page swipe, its proxy changing as the page moves sideways (paging lag, Release
    /// trace 2026-10-09). A sideways move changes neither number, so nothing here redraws while paging.
    struct WheelBox: Equatable {
        var height: CGFloat
        var minY: CGFloat
    }

    private func face(for task: TaskModel) -> some View {
        let p = ringHold.flatMap { $0.id == task.id ? $0.progress : nil } ?? progress(task)
        let done = task.isCompleted(with: p)
        let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                        : p.seconds / Double(max(task.goal * 60, 1))
        return ZikrCircleFace(title: task.title, icon: nil,
                              subtitle: done ? "done today" : progressText(task, p),
                              ring: .progress(min(fraction, 1)), done: done,
                              mantraLine: task.mantraLine,
                              note: done ? nil : estimateNote(task, p))
    }

    /// Freestyle's zikr (the watch's "Pick a zikr"): tap → pick one; ✕ → just count. Frosted, over the ring.
    private var freestyleChip: some View {
        HStack(spacing: 8) {
            Button {
                guard !TourRuntime.shared.active else { TourRuntime.shared.nudge(); return }
                triggerSomeVibration(type: .light)
                showFreestylePicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(freestylePick.isEmpty ? "Pick a zikr" : freestylePick).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
            }
            if !freestylePick.isEmpty {
                Button { triggerSomeVibration(type: .light); freestylePick = "" } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .accessibilityLabel("Just count")
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .fontDesign(.rounded)
        .foregroundStyle(freestylePick.isEmpty ? Color.secondary : Color.sage)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: 180)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.75))   // a subtle grey edge (owner)
        .opacity(openingSoft ? 0 : 1)
        .sheet(isPresented: $showFreestylePicker) {
            MantraPickerView(isPresented: $showFreestylePicker, selectedMantraObject: $pickedMantra,
                             excluding: [PostSalahTasbeeh.mantraName])
        }
        .onChange(of: pickedMantra) { _, mantra in
            if let mantra { freestylePick = mantra.name }
            pickedMantra = nil
        }
    }

    // MARK: circles

    @ViewBuilder
    private func circle(for item: Item) -> some View {
        switch item {
        case .freestyle:
            ZikrCircleFace(title: "Zikr", icon: "circle.hexagonpath", subtitle: "click to freestyle", ring: .full)
                // Freestyle's zikr (the watch's "Pick a zikr"), frosted, on the circle's bottom edge — it moves with the
                // circle (owner: glass broke under the wheel's shrink and tilt; "Frosted always, on the circle").
                .overlay(alignment: .bottom) { freestyleChip.offset(y: 16) }
        case .add:
            ZikrCircleFace(title: "New task", icon: "plus", subtitle: "a daily goal", ring: .dashed)
        case .task(let task):
            // Hold = the task's options, like every task row in the tab (tap still starts it).
            let example = TourExamples.shared.isExample(task)
            face(for: task)
                .overlay(alignment: .top) {
                    // The tour's example tasks say so (owner: "make it clear that these are not real tasks").
                    if example { NextTag(label: TourCopy.Zikr.exampleTag).padding(.top, 52) }
                }
                // Hold anywhere in the circle (owner: only the words took the hold); the preview is the circle too.
                .contentShape(Circle())
                .contentShape(.contextMenuPreview, Circle())
                .contextMenu {
                    // Only the circle in focus (owner: "only allow long press on a task ring that's in focus"): an
                    // off-centre one's hold does nothing (no items, no menu) — its tap brings it to the middle.
                    // An example's options change nothing: picking one is the tour's to-do (Tour.swift).
                    if centered == task.id.uuidString {
                        TaskMenu(task: task,
                                 onEdit: { example ? TourRuntime.shared.event(.exampleOption) : (tasksSheetOn = task) },
                                 onOpenZikr: { example ? TourRuntime.shared.event(.exampleOption) : (wheelOpenZikr = task.mantra) },
                                 onReorder: example ? nil : { showTasksPage = true },
                                 onDelete: { example ? TourRuntime.shared.event(.exampleOption) : (wheelDelete = task) })
                    }
                }
        }
    }

    private func estimateNote(_ task: TaskModel, _ p: TaskProgress) -> String? {
        task.estimateNote(p)
    }

    private func progressText(_ task: TaskModel, _ p: TaskProgress) -> String {
        task.isCountMode ? "\(p.count) of \(task.goal)" : "\(Int(p.seconds / 60)) of \(task.goal) min"
    }

    private let dotSlot: CGFloat = 14
    private let scrubberPad: CGFloat = 10

    /// Down the left edge: one dot per circle, the centred one bigger; tasks done today are sage. Put a finger on
    /// them and drag to fly through the circles (owner: like grabbing a page's scroll bar); a
    /// pill beside the finger names the circle it's on.
    private func scrubber(_ items: [Item]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                let current = item.id == centered
                let done: Bool = { if case .task(let t) = item { return isDone(t) } else { return false } }()
                Circle()
                    .fill(done ? Color.sage : Color.primary.opacity(current ? 0.55 : 0.18))
                    .frame(width: current ? 7 : 5, height: current ? 7 : 5)
                    .frame(width: 24, height: dotSlot)
            }
        }
        .padding(.vertical, scrubberPad)
        .background(Capsule().fill(Color.primary.opacity(scrubbing ? 0.07 : 0)))
        .scaleEffect(scrubbing ? 1.15 : 1, anchor: .leading)
        .overlay(alignment: .topLeading) {
            if scrubbing, let index = items.firstIndex(where: { $0.id == centered }) {
                Text(label(items[index]))
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .fixedSize()
                    .offset(x: 40, y: scrubberPad + dotSlot * CGFloat(index) - 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle().inset(by: -12))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !scrubbing { withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = true } }
                    let index = min(max(Int((value.location.y - scrubberPad) / dotSlot), 0), items.count - 1)
                    if centered != items[index].id {
                        withAnimation(CircleMotion.wheelScrub) { centered = items[index].id }
                    }
                }
                .onEnded { _ in withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = false } }
        )
        .animation(.snappy(duration: CircleMotion.quick), value: centered)
        .padding(.leading, 8)
    }

    private func label(_ item: Item) -> String {
        switch item {
        case .freestyle: "Freestyle"
        case .task(let task): task.title
        case .add: "New task"
        }
    }

    // MARK: actions

    /// The sheet has gone: the task's ring goes from where it stood to where it is now, and a finished one is held full
    /// a moment (a success buzz) before the wheel moves on.
    private func showProgress(_ id: UUID) async {
        guard let hold = ringHold, hold.id == id, let task = tasks.first(where: { $0.id == id }) else { ringHold = nil; return }
        let now = progress(task)
        guard now.count != hold.progress.count || now.seconds != hold.progress.seconds else { ringHold = nil; return }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9)) { ringHold = nil }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 900))
        if isDone(task) {
            triggerSomeVibration(type: .success)
            try? await Task.sleep(for: .milliseconds(800))
        }
    }

    /// Back from a session of `finished`: once it's done, centre what comes next.
    private func landAfterSession(_ finished: UUID) {
        guard let task = tasks.first(where: { $0.id == finished }), isDone(task) else { heldTaskID = nil; return }
        // The ring has landed on it (held till now): it leaves and the wheel moves on, in one move — dropped after the
        // wheel had moved, the scroll kept its offset and the item after the next one came to the middle.
        withAnimation(CircleMotion.wheelCentre) {
            heldTaskID = nil
            centered = nextFocus(after: task)
        }
    }

    /// The next task to do after `task` in the user's order (wrapping), or freestyle when all are done.
    private func nextFocus(after task: TaskModel) -> String {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return Item.freestyle.id }
        let rotated = tasks[(i + 1)...] + tasks[..<i]
        return rotated.first(where: { !isDone($0) })?.id.uuidString ?? Item.freestyle.id
    }

    /// `resume`: begin with today's progress on the ring (only new counts are saved).
    private func start(_ task: TaskModel, resume: Bool = false, from entryFrame: CGRect? = nil) {
        wheelTask?.cancel()   // a landing still waiting must not clear this session's held task
        sessionTaskID = task.id
        heldTaskID = task.id
        ringHold = (task.id, progress(task))
        sharedState.selectedTask = task   // its didSet loads the mode / goal / mantra
        let p = progress(task)
        sharedState.resumeCount = resume && task.isCountMode ? p.count : 0
        sharedState.resumeSeconds = resume && !task.isCountMode ? p.seconds : 0
        openSession(from: task.id.uuidString, base: fraction(task), rewind: !resume, entryFrame: entryFrame)
    }

    /// The task's share done today, as its ring shows it.
    private func fraction(_ task: TaskModel) -> Double {
        let p = progress(task)
        let f = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1)) : p.seconds / Double(max(task.goal * 60, 1))
        return min(f, 1)
    }

    private func arcBack() {
        guard arcRewound else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { arcRewound = false }
    }

    /// The session's cover: under the soft look, out of the centred ring (SessionHandoff) — the rest fades, the
    /// cover comes up with no animation and the session takes it from the ring's place; otherwise the usual sheet.
    /// `base`: the ring's share as it stands; `rewind`: the session starts from nothing, so the arc rewinds to empty
    /// first (decision zikr-ring-progress B).
    private func openSession(from id: String, base: Double, rewind: Bool, entryFrame: CGRect? = nil) {
        // The plain full-screen sheet, sliding up (owner, 2026-10-09: "just open a full sheet when someone clicks a task
        // from the wheel … it feels more crisp"); its results are inside it. The ring handoff (SessionHandoff.open — the
        // wheel's ring becoming the session's) isn't used from the wheel any more; coming back, the ring catches up
        // instead (`showProgress`). It closes the way the post-salah session does, in place: what's on the page goes where
        // it stands and the page fades off the wheel — the sheet sliding down with the results on it, their ring moved
        // under it (owner: "ring comes out and in … keep it clean and easy").
        SessionHandoff.shared.openInPlace(entering: false)
        showTasbeehPage = true
    }

    private func resumeLabel(_ task: TaskModel) -> String {
        let p = progress(task)
        return task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))"
    }

    private func tapped(_ item: Item) {
        guard centered == item.id else {
            withAnimation(CircleMotion.wheelStep) { centered = item.id }
            return
        }
        // The tours: nothing starts from the wheel — except what the Zikr Tour's step asks for (New task, its task).
        if ZikrTour.shared.active || TourRuntime.shared.active {
            guard ZikrTour.shared.allowsWheelTap(item.id) else { TourRuntime.shared.nudge(); return }
            ZikrTour.shared.wheelTapped(item.id)
        }
        triggerSomeVibration(type: .light)
        switch item {
        case .freestyle:
            sharedState.targetCount = ""
            // Under the picked zikr, if it's still there (saved under it, like the watch's); else just counting.
            let picked = freestylePick.isEmpty ? nil : MantraModel.find(named: freestylePick, in: context)
            sharedState.titleForSession = picked?.name ?? ""
            sharedState.mantraForSession = picked
            sharedState.selectedMinutes = 0
            sharedState.selectedMode = 0
            openSession(from: item.id, base: 1, rewind: true)   // its full ring empties into a fresh count
        case .task(let task):
            let p = progress(task)
            if !isDone(task) && (p.count > 0 || p.seconds >= 1) {
                resumeAsk = task
            } else {
                start(task)
            }
        case .add:
            showAddTask = true
        }
    }
}

/// The Zikr wheel's shapes, to try side by side (owner, 2026-09-25: the arc "needs tweaking";
/// pick one, then drop the rest). `radius` = how far left the arc pulls the off-centre circles
/// (0 = straight column), `anglePerRow` = how far round the wheel one row is, `tilt` = how much
/// of that turn the circle itself takes (1 = fully turned with the wheel).
enum ZikrWheelStyle: String, CaseIterable, Identifiable {
    case straight, arcNoTilt, gentle, lazySusan, tight
    static let key = "zikrWheelStyle"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: "Straight (original)"
        case .arcNoTilt: "Arc, no tilt"
        case .gentle: "Gentle arc, half tilt"
        case .lazySusan: "Lazy Susan"
        case .tight: "Tight wheel"
        }
    }
    var radius: CGFloat {
        switch self {
        case .straight: 0
        case .arcNoTilt, .lazySusan: 300
        case .gentle: 240
        case .tight: 210
        }
    }
    var anglePerRow: CGFloat {
        switch self {
        case .straight: 0
        case .arcNoTilt, .lazySusan: 0.7
        case .gentle: 0.55
        case .tight: 0.95
        }
    }
    var tilt: CGFloat {
        switch self {
        case .straight, .arcNoTilt: 0
        case .gentle: 0.5
        case .lazySusan, .tight: 1
        }
    }
}

/// The wheel's look per circle, from its distance to the middle in rows (eased): size and fade
/// fall away (1 row ≈ 0.62×, 2 ≈ 0.45×, floor 0.38×) and neighbours are pulled in so shrinking
/// doesn't open gaps (owner: more dramatic, not at its smallest right away). With an arc
/// `style` the circles ride a big arc bulging right — the middle one at its rightmost point, the others
/// falling away to the left (1 row ≈ 70 pt, 2 ≈ 250 pt), the owner's sketch — and turned with
/// the wheel (±40° a row), like items on a lazy Susan seen from above.
struct WheelFalloff: ViewModifier {
    let itemHeight: CGFloat
    let style: ZikrWheelStyle

    func body(content: Content) -> some View {
        let radius = style.radius, perRow = style.anglePerRow, tilt = style.tilt
        return content.visualEffect { [itemHeight, radius, perRow, tilt] content, proxy in
            let frame = proxy.frame(in: .scrollView(axis: .vertical))
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? frame.height
            let rows: CGFloat = (frame.midY - viewport / 2) / itemHeight
            let d: CGFloat = min(abs(rows), 3)
            let ease: CGFloat = 1 - exp(-1.1 * d)
            let scale: CGFloat = 1 - 0.62 * ease
            // Where it sits on the wheel: 0 at the middle (rightmost point), ± going up / down.
            let theta: CGFloat = min(max(rows, -2.2), 2.2) * perRow
            let arcX: CGFloat = -(1 - cos(theta)) * radius
            let pullY: CGFloat = -(rows >= 0 ? 1 : -1) * itemHeight * (1 - scale) * 0.45 * min(d, 1.5)
            return content
                .scaleEffect(scale)
                .opacity(1 - 0.7 * ease)
                // Turned with the wheel, like a lazy Susan seen from above (owner): each circle
                // faces out from the hub, so the ones above tilt back and the ones below forward.
                .rotationEffect(.radians(Double(theta * tilt)))
                .offset(x: arcX, y: pullY)
        }
    }
}

/// One circle on the Zikr page, in the Salah circle's type (light rounded name, thin caption):
/// the thick gray track with a glowing green ring on top — full for freestyle, today's progress
/// for a task (full + a check once done), dashed for "new task".
struct ZikrCircleFace: View {
    enum Ring { case full, progress(Double), dashed }
    let title: String
    let icon: String?
    let subtitle: String
    let ring: Ring
    var done = false
    /// Under the title, small: the mantra when the task has its own name ("After Fajr" over
    /// "Bismillah").
    var mantraLine: String? = nil
    /// A third, quieter line: roughly how long what's left takes ("~4 min").
    var note: String? = nil
    /// The Salah look prototype (SalahLook.swift): any soft look gives the wheel the tasbeeh ring — the soft
    /// band and a 6 pt round arc with a glow (owner, 2026-10-01: "make the zikr tab also use the neumorphic
    /// style. and the task rings too").
    @Environment(\.circleTheme) private var theme
    private var soft: Bool { theme.soft }
    /// Opening into its session (the wheel, SessionHandoff): the label goes, the ring stays for the counter's.
    @Environment(\.zikrFaceContentAway) private var contentAway
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zikrFaceArcRewound) private var arcRewound

    var body: some View {
        ZStack {
            if soft {
                if case .dashed = ring {} else { NeuRingTrack() }
            } else {
                Circle()
                    .stroke(Color(.secondarySystemFill), lineWidth: 12)
            }
            switch ring {
            case .full:
                glow(Circle().trim(from: 0, to: arcRewound ? 0 : 1).rotation(.degrees(-90)))
            case .progress(let fraction):
                glow(Circle().trim(from: 0, to: arcRewound ? 0 : max(fraction, 0.001)).rotation(.degrees(-90)))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(CircleMotion.arcFill, value: fraction)
            case .dashed:
                Circle()
                    .stroke(Color.sage.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            }

            VStack(spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .light))
                    }
                    Text(title)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                }
                .frame(maxWidth: 150)
                if let mantraLine {
                    Text(mantraLine)
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 150)
                        .padding(.top, -3)
                }
                HStack(spacing: 4) {
                    if done { Image(systemName: "checkmark") }
                    Text(subtitle)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .fontWeight(.thin)
                .foregroundStyle(done ? Color.sage : .secondary)
                if let note {
                    Text(note)
                        .font(.caption)
                        .fontWeight(.light)
                        .foregroundStyle(.tertiary)
                }
            }
            .fontDesign(.rounded)
            // The wheel's own choice (`openSession`): a plain fade under Reduce Motion — it shrank and dropped here while
            // the other circles faded (transitions audit, bug 6).
            .modifier(SessionAppear(shown: !contentAway, style: reduceMotion ? .fade : .current))
        }
        .frame(width: 200, height: 200)
    }

    @ViewBuilder private func glow<S: Shape>(_ shape: S) -> some View {
        if soft {
            // The tasbeeh arc's shape — as wide as the band, round ends, its glow — in the prayer ring's green
            // (PrayerScoring's Perfect), solid (owner, 2026-10-01: "just make it green … the green we use on the
            // prayer ring"; the living fill stays the tasbeeh session's own).
            shape
                .stroke(Color.green, style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 6)
        } else {
            shape
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: Color.green.opacity(0.5), radius: 5)
                .shadow(color: Color.green.opacity(0.3), radius: 10)
                .shadow(color: Color.green.opacity(0.2), radius: 15)
        }
    }
}

struct AddDailyTaskView: View {
    @Environment(\.modelContext) private var context
    @Environment(SharedStateClass.self) var sharedState
    @FocusState var isGoalEntryFocused: Bool

    @Query private var taskItems: [TaskModel] // Query to fetch persisted TaskModel items
    @Query private var mantraItems: [MantraModel]

    @Binding var isPresented: Bool
    @Binding var scrollProxy: UUID?
    
    // Bindings and state variables
    @FocusState var isGoalFocused: Bool
    @FocusState var isZikrFocused: Bool
    @State private var taskIsCountMode: Bool? = nil
    @State private var goal: Int? = nil
    @State private var selectedMantra: MantraModel? = nil
    @State private var searchQuery: String = ""
    @State private var showMantraPicker: Bool = false
    @State private var userSelectedCountMin: Bool? = nil // Default to count mode
    @State private var goalString: String = ""
    @State private var debugTaskInfoOnScreen = 0
    @State private var taskInMaking: TaskModel? = nil
    
    @State private var showBorder: Bool = false
    @State private var confirmSave: Bool = false
    /// Optional own name, e.g. "After Fajr" (notes #7) — the circle's title, the mantra under it.
    @State private var customName: String = ""
    @FocusState private var isNameFocused: Bool
    /// The task's reminder (ZikrReminders), saved with the task.
    @State private var reminder = ReminderDraft()
    @State private var showReminder = false

    /// Edit mode: the task being changed. Its mantra is locked (the sheet is opened from that
    /// mantra's page); only goal and units can change, saved after a confirmation.
    private let editingTask: TaskModel?
    /// A new task from a zikr's page: that zikr is picked and locked (notes #17).
    private let lockedMantra: Bool

    init( isPresented: Binding<Bool>, scrollProxy: Binding<UUID?>) {
        self._isPresented = isPresented
        self._scrollProxy = scrollProxy
        self.editingTask = nil
        self.lockedMantra = false
    }

    /// A new task for `mantra`, which can't be changed here.
    init(for mantra: MantraModel, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._scrollProxy = .constant(nil)
        self.editingTask = nil
        self.lockedMantra = true
        _selectedMantra = State(initialValue: mantra)
    }

    /// Same sheet, prefilled from `task`, with the mantra locked.
    init(editing task: TaskModel, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._scrollProxy = .constant(nil)
        self.editingTask = task
        self.lockedMantra = true
        _goal = State(initialValue: task.goal)
        _taskIsCountMode = State(initialValue: task.isCountMode)
        _selectedMantra = State(initialValue: task.mantra)
        _customName = State(initialValue: task.customName ?? "")
        _reminder = State(initialValue: ReminderDraft(task))
    }

    private var trimmedName: String? {
        let n = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }

    private var isEditing: Bool { editingTask != nil }
    /// Edit mode: nothing to save until goal or units differ from the task.
    private var unchanged: Bool {
        guard let editingTask else { return false }
        return goal == editingTask.goal && taskIsCountMode == editingTask.isCountMode
            && trimmedName == editingTask.customName.flatMap { $0.isEmpty ? nil : $0 }
            && reminder == ReminderDraft(editingTask)
    }

    private func saveEdits() {
        guard let editingTask, let goal, let taskIsCountMode else { return }
        editingTask.goal = goal
        editingTask.isCountMode = taskIsCountMode
        editingTask.customName = trimmedName
        reminder.apply(to: editingTask)
        try? context.save()   // a reminder only in memory was lost if the app was killed before autosave
        NotificationScheduler.reschedule(context: context, reason: "task reminder")
        isGoalFocused = false
        isPresented = false
    }

    // Function to create and persist the TaskModel, then dismiss the view
    func createTask() {
        guard let selectedMantra else { return } // Confirm is disabled until a mantra is picked
        let task = TaskModel(
            mantra: selectedMantra,
            isCountMode: taskIsCountMode ?? false,
            goal: goal ?? 0,
            sortOrder: TaskModel.nextSortOrder(in: context) // new cards go to the end
        )
        task.customName = trimmedName
        reminder.apply(to: task)

        // Save the task to the persistent context
        context.insert(task)
        try? context.save()
        if reminder.kind != nil { NotificationScheduler.reschedule(context: context, reason: "task reminder") }

        isGoalEntryFocused = false //Dismiss keyboard when background tapped

        // The fields stay as they are while the cover slides away (clearing selectedMantra here
        // flashed "Zikr" in the label).
        isZikrFocused = false
        isGoalFocused = false
        
        // Dismiss the view after task creation
        isPresented = false

        // From the Zikr page: scroll to the new circle. From a zikr's page (locked) there's no
        // wheel to focus, and selectedTask re-renders the home screen behind the sheets.
        guard !lockedMantra else { return }
        scrollProxy = task.id
        sharedState.selectedTask = task
    }

    
//    private var predefinedMantras: [String] = ["", "Alhamdulillah", "Subhanallah", "Allahu Akbar", "Astaghfirullah", "jiofej eiojioefjfe iojeiofjfi ojiofejoijf eoijeofi"]

    private var accentColor: Color{
        .green
    }
    
    private var borderColor: Color{
        accentColor.opacity(showBorder ? 0.5 : 0)
    }
    
    private var unitText: String{
        taskIsCountMode ?? false ?
               (goal ?? 0 > 1 ? "Counts" : "Count") :
                (goal ?? 0 > 1 ? "Minutes" : "Minute")
    }
    
    private var parametersIncomplete: Bool{
        goal == nil || goal == 0 || taskIsCountMode == nil || (selectedMantra == nil && !isEditing)
    }
    // Create a NumberFormatter for formatting integers
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none // No specific style, just plain integers
        formatter.allowsFloats = false // Disallow floating point numbers
        return formatter
    }()
    
//    private func resetStates(){
//        goal = nil
//        taskIsCountMode = nil
//        searchQuery = ""
//        selectedMantra = nil
//    }
    
    private func closeView(){
        withAnimation{
            isPresented = false
        }
    }

    var body: some View {
        
        
        // Combine predefined and custom mantras, and filter by search query
//        let filteredMantras = (predefinedMantras + mantraItems.map { $0.text })
//            .filter { searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) }
//            .sorted()
        ZStack{
            Color.white.opacity(0.01)
                .onTapGesture { isGoalFocused = false }
//                .scrollDismissesKeyboard(.automatic)
            
            VStack{
                
                ZStack{
                    HStack{
                        Button(action: { closeView() }) {
                            Image(systemName: "chevron.left")
                                .frame(width: 20, height: 20) // Keep image size constant
                                .foregroundColor(.secondary)
                        }
                        .padding(20) // Increase tappable area
                        .contentShape(Rectangle()) // Ensure the entire padded area is tappable
                        
                        Spacer()
                    }
                    HStack{
                        
                        Spacer()
                        
                        Text(isEditing ? "Edit Task" : "Create a New Task")
                            .font(.title2)
                            .fontWeight(.thin)
                            .onTapGesture {
                                showBorder.toggle()
                            }
                        
                        Spacer()
                    }

                }
                .border(borderColor)
                
                Spacer()
                
                HStack {
                    // Numeric Goal Input
                    TextField("Num", value: $goal, formatter: numberFormatter)
                        .tint(.green)
                        .foregroundColor(goal == 0 ? Color.secondary : accentColor)
                        .opacity(goal == 0 ? 0.5 : 1)
                        .keyboardType(.numberPad)
                        .focused($isGoalFocused)
                        .multilineTextAlignment(.center)
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(width: 70)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(accentColor.opacity(0.5), lineWidth: 1)
                                .foregroundColor(accentColor.opacity(0.15))
                        )
                        .onSubmit {
                            isGoalFocused = false
                            if (goal == 0){
                                goal = nil
                            }
                            if (goal ?? 0 > 10000){
                                goal = 10000
                            }
                        }
                    
                    // Unit Selection Menu
                    Menu {
                        Button("Counts") {
                            taskIsCountMode = true
                        }
                        Button("Minutes") {
                            taskIsCountMode = false
                        }
//                        .onAppear() {
//                            isGoalFocused = false
//                        }
                    } label: {
                        Text(taskIsCountMode == nil ? "Units" : unitText)
                        //                .frame(width: 60)
                            .font(.headline)
                            .foregroundColor(taskIsCountMode == nil ? Color.secondary.opacity(0.5) : accentColor.opacity(1))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(accentColor.opacity(0.5), lineWidth: 1)
                                    .foregroundStyle(accentColor.opacity(0.15))
                            )
                    }
//                    .onChange(of: taskIsCountMode) { _, newVal in
//                        isGoalFocused = false
//                    }

                    
                    
                    // "of" Label
                    Text("of")
                        .font(.headline)
                        .foregroundColor(Color.secondary.opacity(1))
                        .padding(.vertical, 4)
                    
                    // OLD: Zikr Picker Menu
//                    Menu {
//                        ForEach(filteredMantras, id: \ .self) { zikr in
//                            if zikr != "" {
//                                Button("\(zikr)") {
//                                    selectedMantra = zikr
//                                }
//                            }
//                        }
//                    } label: {
//                        Text(selectedMantra ?? "" == "" ? "Zikr" : (selectedMantra ?? ""))
//                            .font(.headline)
//                            .lineLimit(1)
//                            .foregroundColor(selectedMantra ?? "" == ""  ? Color.secondary.opacity(0.5) : accentColor.opacity(1))
//                            .padding(.horizontal, 8)
//                            .padding(.vertical, 4)
//                            .background(
//                                RoundedRectangle(cornerRadius: 5)
//                                    .stroke(accentColor.opacity(0.5), lineWidth: 1)
//                                    .foregroundStyle(accentColor.opacity(0.15))
//                            )
//                    }
                    
                    // NEW: Zikr Picker Sheet (locked in edit mode: it's that mantra's task)
                    Button(action: {
                        showMantraPicker = true
                    }) {
                        HStack(spacing: 4) {
                            Text(selectedMantra?.name ?? editingTask?.displayName ?? "Zikr")
                                .lineLimit(1)
                            if lockedMantra {
                                Image(systemName: "lock.fill").font(.caption2)
                            }
                        }
                            .font(.headline)
                            .foregroundColor(selectedMantra == nil && !lockedMantra ? Color.secondary.opacity(0.5) : accentColor.opacity(lockedMantra ? 0.6 : 1))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(accentColor.opacity(lockedMantra ? 0.25 : 0.5), lineWidth: 1)
                                    .foregroundStyle(accentColor.opacity(lockedMantra ? 0.06 : 0.15))
                            )
                    }
                    .disabled(lockedMantra)
                    .sheet(isPresented: $showMantraPicker) {
                        MantraPickerView(
                            isPresented: $showMantraPicker,
                            selectedMantraObject: $selectedMantra,
                            presentation: [.height(400)]
                        )
                    }
                                        
                }
                .padding()
                .border(borderColor)

                // Optional name: three "Bismillah · 50" tasks a day become "After Fajr",
                // "After Maghrib"… Left empty, the task is called by its mantra as before.
                TextField("Name (optional), e.g. After Fajr", text: $customName)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, design: .rounded))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                    .frame(maxWidth: 300)
                    .padding(.top, 4)

                // Reminder (notes #11): off by default.
                Button { showReminder = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: reminder.kind == nil ? "bell.slash" : "bell")
                        Text(reminder.kind == nil ? "Reminder · Off" : reminder.summary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(reminder.kind == nil ? Color.secondary : Color.green)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(reminder.kind == nil ? Color(.tertiarySystemFill) : Color.green.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .sheet(isPresented: $showReminder) {
                    TaskReminderSheet(draft: reminder, onCancel: { showReminder = false }) { picked in
                        reminder = picked
                        showReminder = false
                    }
                }

                Spacer()
                
                Button(action: {
                    if isEditing { confirmSave = true } else { createTask() }
                }) {
                    Text(isEditing ? "Save" : "Confirm")
                        .foregroundStyle(parametersIncomplete || unchanged ? .secondary: Color.green.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(minWidth: 0, maxWidth: 150)
                    
//                        .font(.headline)
//                        .foregroundColor(parametersIncomplete ? Color.secondary.opacity(0.5) : accentColor.opacity(1))
////                        .padding(.horizontal, 8)
//                        .padding(.vertical, 8)
//                        .frame(minWidth: 0, maxWidth: 150)
//                        .background(
//                            RoundedRectangle(cornerRadius: 5)
//                                .stroke(accentColor.opacity(0.5), lineWidth: 1)
//                                .foregroundStyle(accentColor.opacity(0.15))
//                        )
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(parametersIncomplete || unchanged)
                .padding(.horizontal)
                .confirmationDialog("Save changes to this task?", isPresented: $confirmSave, titleVisibility: .visible) {
                    Button("Save") { saveEdits() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(editingTask.map { goal == $0.goal && taskIsCountMode == $0.isCountMode } ?? false
                         ? "Its name and reminder change everywhere."
                         : "Today's progress is recomputed from its sessions.")
                }
                
            }
//            .scrollDismissesKeyboard(.automatic)

            .padding()
            .border(borderColor)
        }
//        .scrollDismissesKeyboard(.automatic)
        // A new task starts on the goal: the number pad is up straight away (notes #17). Focus
        // set while the cover is still presenting can be dropped, so it's re-asserted on the
        // next run-loop turn too (no fixed delay).
        .defaultFocus($isGoalFocused, !isEditing)
        .onAppear {
            guard !isEditing else { return }
            isGoalFocused = true
            DispatchQueue.main.async { isGoalFocused = true }
        }

    }
    
}


#Preview {
    @Previewable @State var testBool: Bool = true
    ZStack{
        VStack{
//            DailyTasksView(/*showAddTaskScreen: $testBool*/)
            Spacer()
        }
//        AddDailyTaskView(isPresented: $testBool, scrollProxy: UUID())
    }
}
