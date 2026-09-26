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
                message: Text("Are you sure you want to delete your \(taskToDelete?.displayName ?? "") task?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let task = taskToDelete {
                        withAnimation{
                            context.delete(task)
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

struct ZikrCircleWheel: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @Query private var todaysSessions: [SessionDataModel]
    @Binding var showTasbeehPage: Bool

    @State private var centered: String? = Item.freestyle.id
    @State private var showAddTask = false
    @State private var newTaskScrollTarget: UUID?
    @State private var editingTask: TaskModel?
    /// Home-screen-style arranging: long-press a task → the tasks jiggle in a grid with −
    /// badges; drag to reorder, tap to edit the goal, Done (or a tap on the background) to leave.
    @State private var arranging = false
    @State private var arrangeOrder: [TaskModel] = []
    @State private var draggingID: UUID?
    /// How the circles fall away from the middle (Settings → My Dev Stuff while the owner picks).
    @AppStorage(ZikrWheelStyle.key) private var wheelStyleRaw = ZikrWheelStyle.gentle.rawValue
    /// The lifted circle follows the finger here (in the grid's own coordinates).
    @State private var dragPoint: CGPoint = .zero
    @State private var gridWidth: CGFloat = 360
    @Environment(PagerLiveState.self) private var live: PagerLiveState?
    @State private var taskToDelete: TaskModel?
    /// A task tapped with some of today's goal already done: continue or start over?
    @State private var resumeAsk: TaskModel?
    /// A finger on the dots: they become a scrubber (like dragging a page's scroll bar).
    @State private var scrubbing = false

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

    /// Freestyle, the tasks in the user's order with today's finished ones moved to the end
    /// (as the strip did), then "new task".
    private var items: [Item] {
        let open = tasks.filter { !isDone($0) }, done = tasks.filter { isDone($0) }
        return [.freestyle] + (open + done).map { .task($0) } + [.add]
    }

    var body: some View {
        ZStack {
            wheel
                .overlay(alignment: .bottom) { tasksSummary.padding(.bottom, 108) }
                .opacity(arranging ? 0 : 1)
                .scaleEffect(arranging ? 0.94 : 1)
                .allowsHitTesting(!arranging)
            if arranging {
                arrangeGrid
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: arranging)
        .onChange(of: arranging) { _, on in live?.holdForArranging = on }
        // Leaving the page (the bottom bar still works while arranging) ends arranging, or the
        // pager stayed held and the Salah page couldn't be swiped at all (owner, 2026-09-25).
        .onChange(of: sharedState.horizontalPage) { _, page in
            if page != .zikr && arranging { stopArranging() }
        }
        .onDisappear { live?.holdForArranging = false }
    }

    /// "1 of 3 tasks done" under the wheel (the old strip's "1 of 3 Completed"); all done → sage.
    @ViewBuilder private var tasksSummary: some View {
        if !tasks.isEmpty {
            let done = tasks.filter { isDone($0) }.count
            HStack(spacing: 5) {
                if done == tasks.count { Image(systemName: "checkmark") }
                Text(done == tasks.count ? "all \(tasks.count) tasks done today" : "\(done) of \(tasks.count) tasks done")
                    .contentTransition(.numericText())
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
        .onChange(of: centered) { _, _ in triggerSomeVibration(type: .light) }
        .onAppear {
            if let task = sharedState.selectedTask { centered = task.id.uuidString }
        }
        .fullScreenCover(isPresented: $showAddTask) {
            AddDailyTaskView(isPresented: $showAddTask, scrollProxy: $newTaskScrollTarget)
        }
        .onChange(of: newTaskScrollTarget) { _, id in
            if let id { withAnimation { centered = id.uuidString } }
        }
        .sheet(item: $editingTask) { task in
            AddDailyTaskView(editing: task, isPresented: Binding(get: { editingTask != nil }, set: { if !$0 { editingTask = nil } }))
        }
        .alert(resumeAsk?.displayName ?? "",
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
        .alert("Delete this task?",
               isPresented: Binding(get: { taskToDelete != nil }, set: { if !$0 { taskToDelete = nil } }),
               presenting: taskToDelete) { task in
            Button("Delete", role: .destructive) {
                withAnimation {
                    arrangeOrder.removeAll { $0.id == task.id }
                    context.delete(task)
                    sharedState.resetTasbeehInputs()
                }
                taskToDelete = nil
            }
            Button("Cancel", role: .cancel) { taskToDelete = nil }
        } message: { task in
            Text("\(task.displayName) · its sessions stay in your history.")
        }
    }

    /// How far the page's middle sits below the screen's middle.
    private func screenCentreShift(_ geo: GeometryProxy) -> CGFloat {
        let screenHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height
            ?? geo.frame(in: .global).maxY
        let pageMid = geo.frame(in: .global).minY + geo.size.height / 2
        return min(max(pageMid - screenHeight / 2, 0), 80)
    }

    // MARK: arranging (home-screen style)

    private func startArranging() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        arrangeOrder = tasks   // the user's order (done ones aren't moved to the end here)
        arranging = true
    }

    private func stopArranging() {
        commitArrangeOrder()
        draggingID = nil
        arranging = false
    }

    private func commitArrangeOrder() {
        for (position, task) in arrangeOrder.enumerated() where task.sortOrder != position {
            task.sortOrder = position
        }
        try? context.save()
    }

    private var arrangeGrid: some View {
        VStack(spacing: 10) {
            HStack {
                Text("drag to reorder · tap to edit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    triggerSomeVibration(type: .light)
                    stopArranging()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.sage.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3), spacing: rowSpacing) {
                    ForEach(Array(arrangeOrder.enumerated()), id: \.element.id) { index, task in
                        arrangeCell(task, index: index)
                    }
                }
                .padding(.horizontal, gridPad.width)
                .padding(.vertical, gridPad.height)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                // The lifted circle, drawn above the grid at the finger.
                .overlay(alignment: .topLeading) {
                    if let id = draggingID, let task = arrangeOrder.first(where: { $0.id == id }) {
                        circle(forArranging: task)
                            .scaleEffect(1.15)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                            .position(dragPoint)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(.named("arrange"))
            }
            .scrollDisabled(draggingID != nil)
        }
        .fontDesign(.rounded)
        .padding(.top, 58)
        .padding(.bottom, 96)
        .contentShape(Rectangle())
        .onTapGesture { stopArranging() }   // a tap between circles leaves, like the home screen
    }

    private let gridPad = CGSize(width: 16, height: 20)
    private let gridSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 26
    private let cellSize: CGFloat = 108

    /// The slot under a point in the grid (3 columns): the lifted circle takes that place.
    private func slot(at point: CGPoint) -> Int {
        let columnWidth = (gridWidth - gridPad.width * 2) / 3
        let column = min(max(Int((point.x - gridPad.width) / max(columnWidth, 1)), 0), 2)
        let row = max(Int((point.y - gridPad.height + rowSpacing / 2) / (cellSize + rowSpacing)), 0)
        return min(row * 3 + column, arrangeOrder.count - 1)
    }

    /// Hold a circle briefly, then drag: it lifts and follows the finger, the others make room.
    private func arrangeDrag(_ task: TaskModel) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("arrange")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draggingID == nil {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    draggingID = task.id
                }
                dragPoint = drag.location
                let to = slot(at: drag.location)
                if let from = arrangeOrder.firstIndex(where: { $0.id == task.id }), from != to {
                    withAnimation(.snappy(duration: 0.25)) {
                        arrangeOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    }
                    triggerSomeVibration(type: .light)
                }
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.25)) { draggingID = nil }
                commitArrangeOrder()
            }
    }

    private func arrangeCell(_ task: TaskModel, index: Int) -> some View {
        ZStack(alignment: .topLeading) {
            circle(forArranging: task)
            Button {
                triggerSomeVibration(type: .light)
                taskToDelete = task
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.regularMaterial))
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: 4)
            .accessibilityLabel("Delete \(task.displayName)")
        }
        .frame(width: cellSize, height: cellSize)
        // The home screen's wobble; slightly different speeds so they don't move in step.
        .phaseAnimator([-1.8, 1.8]) { view, angle in
            view.rotationEffect(.degrees(angle))
        } animation: { _ in .easeInOut(duration: 0.13 + Double(index % 3) * 0.018) }
        .opacity(draggingID == task.id ? 0 : 1)   // it's drawn at the finger instead
        .contentShape(Circle())
        .onTapGesture { editingTask = task }
        .gesture(arrangeDrag(task))
    }

    private func circle(forArranging task: TaskModel) -> some View {
        let p = progress(task)
        let done = task.isCompleted(with: p)
        let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                        : p.seconds / Double(max(task.goal * 60, 1))
        return ZikrCircleFace(title: task.displayName, icon: nil,
                              subtitle: done ? "done" : progressText(task, p),
                              ring: .progress(min(fraction, 1)), done: done)
            .scaleEffect(0.5)
            .frame(width: 100, height: 100)
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
            let p = progress(task)
            let done = task.isCompleted(with: p)
            let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                            : p.seconds / Double(max(task.goal * 60, 1))
            ZikrCircleFace(title: task.displayName, icon: nil,
                           subtitle: done ? "done today" : progressText(task, p),
                           ring: .progress(min(fraction, 1)), done: done)
                .onLongPressGesture(minimumDuration: 0.45) { startArranging() }
        }
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
        case .task(let task): task.displayName
        case .add: "New task"
        }
    }

    // MARK: actions

    /// `resume`: begin with today's progress on the ring (only new counts are saved).
    private func start(_ task: TaskModel, resume: Bool = false) {
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
                HStack(spacing: 4) {
                    if done { Image(systemName: "checkmark") }
                    Text(subtitle)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .fontWeight(.thin)
                .foregroundStyle(done ? Color.sage : .secondary)
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
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    HStack {
                        Text(task.displayName)
                        Spacer()
                        Text(task.isCountMode ? "#\(task.goal)" : "\(task.goal) min")
                            .foregroundStyle(.secondary)
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
    }
}

struct TaskCardView: View {
    let task: TaskModel
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .center) {
            
            Text(task.displayName)
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

    /// Edit mode: the task being changed. Its mantra is locked (the sheet is opened from that
    /// mantra's page); only goal and units can change, saved after a confirmation.
    private let editingTask: TaskModel?

    init( isPresented: Binding<Bool>, scrollProxy: Binding<UUID?>) {
        self._isPresented = isPresented
        self._scrollProxy = scrollProxy
        self.editingTask = nil
    }

    /// Same sheet, prefilled from `task`, with the mantra locked.
    init(editing task: TaskModel, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._scrollProxy = .constant(nil)
        self.editingTask = task
        _goal = State(initialValue: task.goal)
        _taskIsCountMode = State(initialValue: task.isCountMode)
        _selectedMantra = State(initialValue: task.mantra)
    }

    private var isEditing: Bool { editingTask != nil }
    /// Edit mode: nothing to save until goal or units differ from the task.
    private var unchanged: Bool {
        guard let editingTask else { return false }
        return goal == editingTask.goal && taskIsCountMode == editingTask.isCountMode
    }

    private func saveEdits() {
        guard let editingTask, let goal, let taskIsCountMode else { return }
        editingTask.goal = goal
        editingTask.isCountMode = taskIsCountMode
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

        // Save the task to the persistent context
        context.insert(task)

        isGoalEntryFocused = false //Dismiss keyboard when background tapped

        // i think we can get rid of this all since its all State vars... and we close the view so it will be redrawn anyways
        isZikrFocused = false
        isGoalFocused = false
        self.selectedMantra = nil
        goal = 0
        
        // Dismiss the view after task creation
        isPresented = false

        //set proxy to this
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
                            if isEditing {
                                Image(systemName: "lock.fill").font(.caption2)
                            }
                        }
                            .font(.headline)
                            .foregroundColor(selectedMantra == nil && !isEditing ? Color.secondary.opacity(0.5) : accentColor.opacity(isEditing ? 0.6 : 1))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(accentColor.opacity(isEditing ? 0.25 : 0.5), lineWidth: 1)
                                    .foregroundStyle(accentColor.opacity(isEditing ? 0.06 : 0.15))
                            )
                    }
                    .disabled(isEditing)
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
                    Text("Today's progress is recomputed from its sessions.")
                }
                
            }
//            .scrollDismissesKeyboard(.automatic)

            .padding()
            .border(borderColor)
        }
//        .scrollDismissesKeyboard(.automatic)

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
