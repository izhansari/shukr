//
//  DailyTasksView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData


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

/// Full-page home for zikr: the freestyle circle over the daily task cards, laid out like
/// the old bottom-sheet Zikr tab. It's the left page of the main pager, which is a horizontal
/// ScrollView, so the task cards' own horizontal scroll nests inside it the UIKit way:
/// cards scroll first, the page turns at their edge.
struct ZikrPageView: View {
    @Binding var showMantraSheetFromHomePage: Bool
    @Binding var showTasbeehPage: Bool

    var body: some View {
        VStack {
            Spacer()
            Spacer()
            Spacer()
            
            ZikrCircleView(showTasbeehPage: $showTasbeehPage)
            
            Spacer()
            Spacer()
            
            DailyTasksView(
                showMantraSheetFromHomePage: $showMantraSheetFromHomePage,
                showTasbeehPage: $showTasbeehPage
            )
            .frame(width: 260)
            .background(FlatBorder())
            .padding(.bottom, 30)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            
            VStack {
                HStack(alignment: .center) {
                    Image(systemName: "circle.hexagonpath")
                    Text("Zikr")
                        .fontWeight(.bold)
                }
                .font(.title)
                Text("click to freestyle")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fontDesign(.rounded)
                    .fontWeight(.light)
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
