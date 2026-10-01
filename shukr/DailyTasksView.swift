//
//  DailyTasksView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers


struct DailyTasksView: View {
    // MARK: - Environment / Queries
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.modelContext) private var context
    
    @Query(sort: \TaskModel.sortOrder) private var taskItems: [TaskModel]
    /// Today's sessions, live. SwiftData re-runs this on every insert, so a card flips to
    /// complete the moment a session saves — no onAppear / remount needed.
    @Query private var todaysSessions: [SessionDataModel]
    
    // MARK: - Binding
    @Binding var showMantraSheetFromHomePage: Bool
    @Binding var showTasbeehPage: Bool
    
    init(showMantraSheetFromHomePage: Binding<Bool>, showTasbeehPage: Binding<Bool>) {
        self._showMantraSheetFromHomePage = showMantraSheetFromHomePage
        self._showTasbeehPage = showTasbeehPage
        let todayStart = PrayerDay.sessionDayStart()   // the prayer day, rollover included
        _todaysSessions = Query(
            filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart },
            sort: \.startTime
        )
    }
    
    // MARK: - State
    @State private var showAddTaskScreen: Bool = false
    @State private var showReorderSheet: Bool = false
    @State private var taskToDelete: TaskModel? = nil
    @State private var showDeleteTaskAlert: Bool = false
    @State private var currentScrollTargetID: UUID? = nil
    /// The main pager's live state (nil outside the pager). The strip holds the pager still
    /// while a finger is on it: nested same-axis scroll views chain in UIKit, so a drag past
    /// the last card would otherwise turn the page.
    @Environment(PagerLiveState.self) private var live: PagerLiveState?
    // “Select Zikr” logic
//    @State private var chosenMantra: String? = ""
    
    // MARK: - Constants
    let zikrButtonUUID = UUID()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            
            headerView
//            if showTaskScroller{
                if taskItems.isEmpty {
                    NoTasksView(showAddTaskScreen: $showAddTaskScreen)
                }
                else{
                    tasksScrollView
                    
                }
//            }
//            else{
//                ZikrSelectionCardView(showMantraSheetFromHomePage: $showMantraSheetFromHomePage)
//                    .contentMargins(.bottom, 10, for: .scrollContent)
//                    .frame(width: 260)
//                    .padding(.bottom, 20)
//                
//            }
        }
        .fullScreenCover(isPresented: $showAddTaskScreen) {
            AddDailyTaskView(isPresented: $showAddTaskScreen, scrollProxy: $currentScrollTargetID)
        }
        .sheet(isPresented: $showReorderSheet) {
            ReorderTasksView()
                .presentationDetents([.medium, .large])
        }
        .alert(isPresented: $showDeleteTaskAlert) {
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete your \(taskToDelete?.title ?? "") task?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let task = taskToDelete {
                        withAnimation{
                            TaskModel.delete(task, in: context)   // its reminders go too
                            taskToDelete = nil
                            sharedState.resetTasbeehInputs()
                        }
                    }
                },
                secondaryButton: .cancel {
                    taskToDelete = nil
                }
            )
        }
    }
}

/// The Zikr page (redesigned 2026-09-25 — owner: keep the circle theme, give the tasks the
/// room the fixed freestyle circle was using): a vertical wheel of circles — freestyle first,
/// then each daily task as a circle with today's progress as its ring, then a dashed "new
/// task" circle. Scrolls up and down one circle at a time; the ones off-centre shrink and fade
/// (the old card strip's effect, turned on its side). Tap a circle to bring it to the middle,
/// tap the middle one to start. Long-press a task for edit / reorder / delete. Dots on the left (drag them to scrub)
/// show where you are, green for the tasks done today. The old strip (`DailyTasksView`) is kept
/// below, unused.
struct ZikrPageView: View {
    @Binding var showMantraSheetFromHomePage: Bool
    @Binding var showTasbeehPage: Bool

    var body: some View {
        ZikrCircleWheel(showTasbeehPage: $showTasbeehPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A task to bring to the middle of the Zikr wheel (from a Zikr widget row). Held until the wheel
/// is there to take it (a cold launch mounts it after the request).
enum ZikrFocus {
    static let notification = Notification.Name("zikrFocusTask")
    private(set) static var pending: String?
    static func request(_ taskID: String) {
        pending = taskID
        NotificationCenter.default.post(name: notification, object: nil)
    }
    static func take() -> String? { defer { pending = nil }; return pending }

    /// Start a task's session from elsewhere (a zikr's page, owner 2026-09-30): the app closes
    /// what covers it, goes to the Zikr page, and the wheel starts it (`resume`: from today's count).
    static let startNotification = Notification.Name("zikrStartTask")
    static let wheelStartNotification = Notification.Name("zikrWheelStartTask")
    private(set) static var pendingStart: (id: String, resume: Bool)?
    static func start(_ taskID: String, resume: Bool) {
        pendingStart = (taskID, resume)
        NotificationCenter.default.post(name: startNotification, object: nil)
    }
    static func takeStart() -> (id: String, resume: Bool)? { defer { pendingStart = nil }; return pendingStart }
    /// A deleted task can't be focused later.
    static func forget(_ ids: [String]) { if let p = pending, ids.contains(p) { pending = nil } }
}

struct ZikrCircleWheel: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @Query private var todaysSessions: [SessionDataModel]
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

    init(showTasbeehPage: Binding<Bool>) {
        self._showTasbeehPage = showTasbeehPage
        let dayStart = PrayerDay.sessionDayStart()   // the prayer day (Fajr to Fajr)
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= dayStart },
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
        [.freestyle] + tasks.filter { !isDone($0) }.map { .task($0) } + [.add]
    }
    /// The summary's tap: Your tasks, the whole list, finished ones included (a page).
    @State private var showTasksPage = false

    var body: some View {
        wheel
            .overlay(alignment: .bottom) {
                // "2 of 9 tasks done" opens Your tasks (owner): the full list, what's finished.
                Button {
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
                .padding(.bottom, 100)
            }
            .sheet(item: $tasksSheetOn) { task in
                NavigationStack {
                    AddDailyTaskView(editing: task, isPresented: Binding(
                        get: { tasksSheetOn != nil }, set: { if !$0 { tasksSheetOn = nil } }))
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .navigationDestination(isPresented: $showTasksPage) { YourTasksPage() }
            .sheet(item: $wheelOpenZikr) { MantraEditorView(mantra: $0) }
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
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        centered = tasks.first(where: { $0.id.uuidString == c }).map { nextFocus(after: $0) } ?? Item.freestyle.id
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ZikrFocus.notification)) { _ in focusPending() }
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
        guard let request = ZikrFocus.pendingStart,
              let task = tasks.first(where: { $0.id.uuidString == request.id }) else { return }
        _ = ZikrFocus.takeStart()
        if !isDone(task) {   // a finished task isn't on the wheel: start it without centring
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { centered = request.id }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { start(task, resume: request.resume) }
    }

    /// Scroll a widget-requested task to the middle (after the page has come in).
    private func focusPending() {
        guard let id = ZikrFocus.pending, let task = tasks.first(where: { $0.id.uuidString == id }) else { return }
        guard !isDone(task) else { _ = ZikrFocus.take(); return }   // finished: not on the wheel
        _ = ZikrFocus.take()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { centered = id }
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
        return GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        circle(for: item)
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
            .contentMargins(.vertical, max((geo.size.height - itemHeight) / 2, 0), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $centered, anchor: .center)
            // Soft edges under the page's title and bottom bar.
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0.06), .init(color: .black, location: 0.2),
                                       .init(color: .black, location: 0.8), .init(color: .clear, location: 0.94)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .leading) { scrubber(items) }   // left edge (owner)
            // Centre the focused circle on the SCREEN (owner): the page starts under the status
            // bar and runs to the bottom edge, so its own middle sits a little low. Shift the
            // whole wheel up by the difference (scroll snapping always centres in its own frame).
            .offset(y: -screenCentreShift(geo))
        }
        .onChange(of: centered) { old, id in
            triggerSomeVibration(type: .light)
            ZikrWheelFocus.shared.centre(id, from: old, in: items.map(\.id))   // the top bar's title
        }
        .onAppear { ZikrWheelFocus.shared.centre(centered, from: nil, in: items.map(\.id)) }
        #if DEBUG
        .task { TaskStreakDebug.log(tasks) }
        .fullScreenCover(isPresented: .constant(StreakHeroDemo.streak != nil)) {
            if let s = StreakHeroDemo.streak { StreakHeroDemo(streak: s) }
        }
        #endif
        .onAppear {
            if let task = sharedState.selectedTask { centered = task.id.uuidString }
        }
        .sheet(isPresented: $showAddTask) {
            NewTaskFlow { newTaskScrollTarget = $0.id }   // the wheel centres it
        }
        #if DEBUG
        .task {   // -demoNewTaskStep N: the flow open at step N
            guard UserDefaults.standard.integer(forKey: "demoNewTaskStep") > 0 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showAddTask = true
        }
        #endif
        .onChange(of: newTaskScrollTarget) { _, id in
            if let id { withAnimation { centered = id.uuidString } }
        }
        // Back from a task's session: once it's done, land on the next task — after it in your
        // order, the first not done yet (wrapping), else freestyle (owner, 2026-09-28). The done
        // task stays where it is (2026-09-29).
        .onChange(of: showTasbeehPage) { _, showing in
            guard !showing, let finished = sessionTaskID else { return }
            sessionTaskID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { landAfterSession(finished) }
        }
        #if DEBUG
        // `-demoFinishTask N` (with -demoZikrPage): centre task N, save a session that completes it,
        // then come back as from its session — the wheel should land on the next task (simulator).
        .task {
            let n = UserDefaults.standard.integer(forKey: "demoFinishTask")
            guard n > 0 else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard n <= tasks.count else { return }
            let task = tasks[n - 1]
            withAnimation { centered = task.id.uuidString }
            try? await Task.sleep(for: .seconds(1.5))
            let session = SessionDataModel(title: task.displayName, sessionMode: task.isCountMode ? 2 : 1,
                                           targetMin: task.isCountMode ? 0 : task.goal, targetCount: task.isCountMode ? task.goal : 0,
                                           totalCount: task.isCountMode ? task.goal : 60, startTime: Date(),
                                           secondsPassed: task.isCountMode ? Double(task.goal) : Double(task.goal * 60),
                                           avgTimePerClick: 1, tasbeehRate: "1m 40s", task: task, mantra: task.mantra)
            context.insert(session)
            try? context.save()
            try? await Task.sleep(for: .seconds(1))
            print("🧪 demoFinishTask: finished \(task.title) (done \(isDone(task)))")
            landAfterSession(task.id)
        }
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

    /// How far the page's middle sits below the screen's middle.
    private func screenCentreShift(_ geo: GeometryProxy) -> CGFloat {
        let screenHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height
            ?? geo.frame(in: .global).maxY
        let pageMid = geo.frame(in: .global).minY + geo.size.height / 2
        return min(max(pageMid - screenHeight / 2, 0), 80)
    }

    private func face(for task: TaskModel) -> some View {
        let p = progress(task)
        let done = task.isCompleted(with: p)
        let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                        : p.seconds / Double(max(task.goal * 60, 1))
        return ZikrCircleFace(title: task.title, icon: nil,
                              subtitle: done ? "done today" : progressText(task, p),
                              ring: .progress(min(fraction, 1)), done: done,
                              mantraLine: task.mantraLine,
                              note: done ? nil : estimateNote(task, p))
    }

    // MARK: circles

    @ViewBuilder
    private func circle(for item: Item) -> some View {
        switch item {
        case .freestyle:
            ZikrCircleFace(title: "Zikr", icon: "circle.hexagonpath", subtitle: "click to freestyle", ring: .full)
        case .add:
            ZikrCircleFace(title: "New task", icon: "plus", subtitle: "a daily goal", ring: .dashed)
        case .task(let task):
            // Hold = the task's options, like every task row in the tab (tap still starts it).
            face(for: task)
                .contentShape(.contextMenuPreview, Circle())
                .contextMenu {
                    TaskMenu(task: task,
                             onEdit: { tasksSheetOn = task },
                             onOpenZikr: { wheelOpenZikr = task.mantra },
                             onDelete: { wheelDelete = task })
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
                    if !scrubbing { withAnimation(.snappy(duration: 0.2)) { scrubbing = true } }
                    let index = min(max(Int((value.location.y - scrubberPad) / dotSlot), 0), items.count - 1)
                    if centered != items[index].id {
                        withAnimation(.snappy(duration: 0.18)) { centered = items[index].id }
                    }
                }
                .onEnded { _ in withAnimation(.snappy(duration: 0.25)) { scrubbing = false } }
        )
        .animation(.snappy(duration: 0.2), value: centered)
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

    /// Back from a session of `finished`: once it's done, centre what comes next.
    private func landAfterSession(_ finished: UUID) {
        guard let task = tasks.first(where: { $0.id == finished }), isDone(task) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { centered = nextFocus(after: task) }
    }

    /// The next task to do after `task` in the user's order (wrapping), or freestyle when all are done.
    private func nextFocus(after task: TaskModel) -> String {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return Item.freestyle.id }
        let rotated = tasks[(i + 1)...] + tasks[..<i]
        return rotated.first(where: { !isDone($0) })?.id.uuidString ?? Item.freestyle.id
    }

    /// `resume`: begin with today's progress on the ring (only new counts are saved).
    private func start(_ task: TaskModel, resume: Bool = false) {
        sessionTaskID = task.id
        sharedState.selectedTask = task   // its didSet loads the mode / goal / mantra
        let p = progress(task)
        sharedState.resumeCount = resume && task.isCountMode ? p.count : 0
        sharedState.resumeSeconds = resume && !task.isCountMode ? p.seconds : 0
        showTasbeehPage = true
    }

    private func resumeLabel(_ task: TaskModel) -> String {
        let p = progress(task)
        return task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))"
    }

    private func tapped(_ item: Item) {
        guard centered == item.id else {
            withAnimation(.snappy) { centered = item.id }
            return
        }
        triggerSomeVibration(type: .light)
        switch item {
        case .freestyle:
            sharedState.targetCount = ""
            sharedState.titleForSession = ""
            sharedState.mantraForSession = nil
            sharedState.selectedMinutes = 0
            sharedState.selectedMode = 0
            showTasbeehPage = true
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.secondarySystemFill), lineWidth: 12)
            switch ring {
            case .full:
                glow(Circle())
            case .progress(let fraction):
                glow(Circle().trim(from: 0, to: max(fraction, 0.001)).rotation(.degrees(-90)))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
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
        }
        .frame(width: 200, height: 200)
    }

    private func glow<S: Shape>(_ shape: S) -> some View {
        shape
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: Color.green.opacity(0.5), radius: 5)
            .shadow(color: Color.green.opacity(0.3), radius: 10)
            .shadow(color: Color.green.opacity(0.2), radius: 15)
    }
}

/// The "Zikr / click to freestyle" circle that used to appear in MainCircleView when the
/// bottom sheet was on its Zikr tab. Same look; tapping starts a freestyle tasbeeh session.
struct ZikrCircleView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Binding var showTasbeehPage: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.clear))
                .stroke(Color(.secondarySystemFill), lineWidth: 12)
                .frame(width: 200, height: 200)
            
            // Same type as the Salah circle / Insights ring: large, light, rounded.
            VStack(spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "circle.hexagonpath")
                        .font(.system(size: 22, weight: .light))
                    Text("Zikr")
                        .font(.system(size: 32, weight: .light, design: .rounded))
                }
                Text("click to freestyle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
            }
            
            Circle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: 200, height: 200)
                .shadow(color: Color.green.opacity(0.5), radius: 5)
                .shadow(color: Color.green.opacity(0.3), radius: 10)
                .shadow(color: Color.green.opacity(0.2), radius: 15)
        }
        .contentShape(Circle())
        .onTapGesture {
            triggerSomeVibration(type: .light)
            sharedState.targetCount = ""
            sharedState.titleForSession = ""
            sharedState.selectedMinutes = 0
            sharedState.selectedMode = 0
            showTasbeehPage = true
        }
    }
}

// MARK: - Subviews / Components
extension DailyTasksView {
        
    private func isCompleted(_ task: TaskModel) -> Bool {
        task.isCompleted(with: task.progress(in: todaysSessions))
    }
    private var incompleteTasksCount: Int {
        taskItems.filter { !isCompleted($0) }.count
    }
    private var completedTasksCount: Int {
        taskItems.filter { isCompleted($0) }.count
    }
    private var subtitleText: String {
        completedTasksCount == taskItems.count ?
        "All Done!" :
        "\(completedTasksCount) of \(taskItems.count) Completed"
    }
    private func startFreestyleTasbeehSession(){
        sharedState.targetCount = ""
        sharedState.titleForSession = ""
        sharedState.selectedMinutes = 0
        sharedState.selectedMode = 0
        showTasbeehPage = true
    }
    /// A header with a centered title and a plus button on the right
    private var headerView: some View {
        ZStack {
            
            VStack(alignment: .center) {
                Text("Tasks")
                    .font(.callout)
                    .foregroundColor(.secondary.opacity(1))
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                
                // Subtitle: says count of tasks lefe or "All Done"
                if (!taskItems.isEmpty) {
                        Text(subtitleText)
                            .font(.footnote)
                            .foregroundColor(.secondary.opacity(1))
                            .fontDesign(.rounded)
                            .fontWeight(.light)
                }

            }
            
//            HStack{
//                Button(action: {
//                    withAnimation{
//                        showTaskScroller.toggle()
//                    }
//                }) {
//                    Image(systemName: showTaskScroller ? "chevron.left" : "list.bullet")
//                        .foregroundColor(.green.opacity(0.7))
//                }
//                .padding(.leading, 5)
//                
//                Spacer()
//
//            }
            
            
            HStack{
                // Reorder the cards (drag handles in a sheet). Left corner; + keeps the right.
                Button(action: {
                    showReorderSheet = true
                }) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.leading, 5)
                Spacer()
                Button(action: {
                        showAddTaskScreen = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.trailing, 5)
            }
            .opacity(!taskItems.isEmpty ? 1 : 0)
//            .opacity(showTaskScroller && !taskItems.isEmpty ? 1 : 0)
            

        }
        .padding()
    }
    
    /// The main horizontal scroll of tasks (including Zikr button and plus button)
    private var tasksScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                
                // User's order (sortOrder), with today's completed ones moved to the end.
                let sortedTasks = taskItems.filter { !isCompleted($0) } + taskItems.filter { isCompleted($0) }
                
                // 2) The Task Cards
                ForEach(sortedTasks, id: \.self) { task in
                    taskCard(for: task)
                }
                .onAppear {
                    // When tasks appear, decide initial scroll selection
                    if let selected = sharedState.selectedTask { // for if we come back from tasbeehpage and already had a task previously selected - go there.
                        currentScrollTargetID = selected.id
                    }

                }
            }
            .onChange(of: currentScrollTargetID) {_, newValue in
                triggerSomeVibration(type: .light)
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $currentScrollTargetID)   // iOS 17 approach
        .contentMargins(.horizontal, 54, for: .scrollContent)
        .contentMargins(.top, 3, for: .scrollContent)
        .contentMargins(.bottom, 10, for: .scrollContent)
        .padding(.horizontal)
        .frame(width: 260)
        .scrollTargetBehavior(.viewAligned)
        // Touch-down on the strip locks the pager; release or the strip settling unlocks it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if live?.pagerLocked == false { live?.pagerLocked = true } }
                .onEnded { _ in live?.pagerLocked = false }
        )
        .onScrollPhaseChange { _, phase, _ in
            if phase == .idle { live?.pagerLocked = false }
        }
        // The pager's own gesture holds the pager for touches that start inside this frame.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { live?.stripFrame = $0 }
        .padding(.bottom, 20)
    }
    
    
    /// Create a Task Card with the “two-tap” logic
    private func taskCard(for task: TaskModel) -> some View {
        TaskCardView(task: task, isCompleted: isCompleted(task))
            .id(task.id)
            .onLongPressGesture {
                taskToDelete = task
                showDeleteTaskAlert = true
            }
            .onTapGesture {
                withAnimation{
                    // If already centered => do the main action
                    if currentScrollTargetID == task.id {
                        tapOnTaskCardAction(task: task)
                    }
                    // Otherwise => scroll to center
                    else {
                        currentScrollTargetID = task.id
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        (currentScrollTargetID == task.id && !isCompleted(task) ? Color.green : Color.gray).gradient.opacity(0.4),
                        lineWidth: currentScrollTargetID == task.id ? 1 : 0.4
                    )
            )
            // Centering a card is local state only. It used to write sharedState.selectedTask,
            // whose didSet writes four more @Published properties: five whole-home-screen
            // re-renders per card the strip passed, which is what made scrolling it stutter.
            // The tap action sets selectedTask when it's actually needed.
            .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.8)
                    .offset(y: phase.isIdentity ? 0 : 10)
            }
    }
        
    // MARK: - Actions
    private func tapOnTaskCardAction(task: TaskModel) {
        sharedState.selectedTask = task
        showTasbeehPage = true
    }
    
}

/// Sheet from the tasks card's edit button: drag to set the order the cards appear in.
/// Writes `sortOrder` straight onto the models; the card strip's query is sorted by it.
struct ReorderTasksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                            if let line = task.mantraLine {
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(task.isCountMode ? "\(task.goal)" : "\(task.goal) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, .constant(.active)) // handles always showing; this sheet is the edit mode
            .fontDesign(.rounded)
            .navigationTitle("Reorder Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = tasks
        ordered.move(fromOffsets: source, toOffset: destination)
        for (position, task) in ordered.enumerated() where task.sortOrder != position {
            task.sortOrder = position
        }
        try? context.save()   // saved on every move, so nothing is lost if the app goes away
    }
}

struct TaskCardView: View {
    let task: TaskModel
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .center) {
            
            Text(task.title)
                .font(.footnote) //.callout
                .foregroundColor(.secondary.opacity(1)) //1
                .fontDesign(.rounded)
                .fontWeight(.light)
                .lineLimit(2) // Limit to 2 lines for consistency
                .multilineTextAlignment(.center)
                .frame(height: 40)

            Spacer()
            
            ZStack{
                HStack {
                    HStack(spacing: 0) {
                        Image(systemName: task.isCountMode ? "number" : "timer")
                        Text("\(task.goal)")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary.opacity(0.9)) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                }
                HStack {
                    HStack(spacing: 0) {
                        Image(systemName: "checkmark")
                        Spacer()
                    }
                    .font(.footnote)
                    .foregroundColor(Color.green) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                    .opacity(isCompleted ? 1 : 0)
                }
            }
            
            Spacer()

        }
        .padding()
        .frame(width: 120, height: 80)
//        .background( Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ZikrSelectionCardView: View {
    @EnvironmentObject var sharedState: SharedStateClass

    @Binding var showMantraSheetFromHomePage: Bool
    
    var body: some View {
        Button(action: {
            withAnimation{
                showMantraSheetFromHomePage = true
            }
        }) {
            VStack(alignment: .center) {
                
                Spacer()
                
                Text("choose zikr")
                    .font(.footnote) //.callout
                    .foregroundColor(.secondary.opacity(1)) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                    .lineLimit(2) // Limit to 2 lines for consistency
                    .multilineTextAlignment(.center)
                    .frame(height: 40)
                
                Spacer()
                
            }
            .padding()
            .frame(width: 120, height: 80)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((Color.gray).gradient.opacity(0.4), lineWidth: 1)
        )
        .onAppear{
            sharedState.resetTasbeehInputs()
        }
        .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
        


    }
}


//struct TaskCardView_old: View {
//    let task: TaskModel
//
//    var body: some View {
//        VStack(alignment: .leading) {
//
//            // Mantra title at the top, fixed height for consistency
//            Text(task.mantra)
//                .font(.footnote)
//                .multilineTextAlignment(.leading)
//                .lineLimit(2) // Limit to 2 lines for consistency
//                .padding(.top, 8)
//                .padding(.horizontal, 9)
//
//            Spacer()
//
//            // Bottom section: Mode icon and goal on the left, completion indicator on the right
//            HStack(spacing: 2) {
//                HStack(spacing: 0) {
//                    Image(systemName: task.isCountMode ? "number" : "timer")
//                    Text("\(task.goal)")
//                }
//                .font(.footnote)
//
//                Spacer()
//
//                // Completion indicator (circle)
//                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
//                    .foregroundColor(task.isCompleted ? .green : .gray)
//                    .padding(.trailing, 5) // Padding from the right
//                    .padding(.top, 5) // Padding from the top
//            }
//            .padding(.all, 8)
//
//        }
//        .frame(width: 120, height: 80)
////        .background(task.isCompleted ? Color.green.opacity(0.3) : Color.gray.opacity(0.1))
//        .cornerRadius(10)
//    }
//}


struct NoTasksView: View {
    @Binding var showAddTaskScreen: Bool

    var body: some View {
        VStack {
            Button(action: {
                showAddTaskScreen = true
            }) {
                VStack(spacing: 10) {
                    // Plus Button
                    Image(systemName: "plus.circle")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.green.opacity(0.7))
                    
                    // Text prompt
                    Text("create a daily task")
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundColor(.gray)
                }
                .frame(width: 190, height: 100)
            }
        }
    }
}


struct AddDailyTaskView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
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
