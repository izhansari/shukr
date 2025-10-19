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
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) private var context
    
    @Query private var taskItems: [TaskModel]
    
    // MARK: - Binding
    @Binding var showMantraSheetFromHomePage: Bool
    @Binding var showTasbeehPage: Bool
    
    // MARK: - State
    @State private var showAddTaskScreen: Bool = false
    @State private var taskToDelete: TaskModel? = nil
    @State private var showDeleteTaskAlert: Bool = false
    @State private var currentScrollTargetID: UUID? = nil
//    @State private var showTaskScroller: Bool = true
//    @State private var todaysSessions: [SessionDataModel] = []
    @State private var todaysSessionsDict: [String: (totalCount: Int, secondsPassed: TimeInterval)] = [:]
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
        .onAppear{
            updateTodaysSessions()
        }
//        .onChange(of: showTasbeehPage) {_, newValue in
//            updateTodaysSessions()
//        }
        .fullScreenCover(isPresented: $showAddTaskScreen) {
            AddDailyTaskView(isPresented: $showAddTaskScreen, scrollProxy: $currentScrollTargetID)
        }
        .alert(isPresented: $showDeleteTaskAlert) {
            Alert(
                title: Text("Delete Task"),
                message: Text("Are you sure you want to delete your \(taskToDelete?.mantra ?? "") task?"),
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

// MARK: - Subviews / Components
extension DailyTasksView {
        
    private var incompleteTasksCount: Int {
        taskItems.filter { !$0.isCompleted }.count
    }
    private var completedTasksCount: Int {
        taskItems.filter { $0.isCompleted }.count
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
//                Button(action: {
//                    startFreestyleTasbeehSession()
//                }) {
//                    Image(systemName: "infinity")
//                        .foregroundColor(.green.opacity(0.7))
//                }
//                .padding(.leading, 5)
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
                
                let sortedTasks = taskItems.sorted { !$0.isCompleted && $1.isCompleted }
                
                // 2) The Task Cards
                ForEach(sortedTasks, id: \.self) { task in
                    taskCard(for: task)
                        .onAppear{
                            task.updateRunningGoal(with: todaysSessionsDict)
//                            task.updateRunningGoal(with: todaysSessions/*using: context*/)
                        }
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
        .padding(.bottom, 20)
    }
    
    
    /// Create a Task Card with the “two-tap” logic
    private func taskCard(for task: TaskModel) -> some View {
        TaskCardView(task: task)
            .id(task.id)
            .onLongPressGesture {
                taskToDelete = task
                showDeleteTaskAlert = true
            }
            .onTapGesture {
                withAnimation{
                    sharedState.selectedTask = task
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
                        (currentScrollTargetID == task.id && !task.isCompleted ? Color.green : Color.gray).gradient.opacity(0.4),
                        lineWidth: currentScrollTargetID == task.id ? 1 : 0.4
                    )
            )
            .onChange(of: currentScrollTargetID) {_, newValue in
                if currentScrollTargetID == task.id {
//                    triggerSomeVibration(type: .light) herè
                    withAnimation{sharedState.selectedTask = task}
                }
            }
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
        // Optionally do more logic here, e.g. adjusting sharedState’s goals/timers
        presentationMode.wrappedValue.dismiss()
        sharedState.selectedTask = task
        showTasbeehPage = true
        sharedState.navPosition = .main
    }
    
    // Function to fetch today's sessions from swiftdata
    private func updateTodaysSessions() {
        // Build a fetch descriptor with a predicate
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
        let fetchDescriptor = FetchDescriptor<SessionDataModel>(
            predicate: #Predicate<SessionDataModel> {
                $0.startTime >= todayStart &&
                $0.startTime <= todayEnd
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        // Fetch sessions matching the criteria
        guard let fetchedSessions = try? context.fetch(fetchDescriptor) else {
            print("❌ (updateTodaysSessions) Failed to fetch sessions.")
            return
        }
        
//        todaysSessions = fetchedSessions
        
        // Create a dictionary to store the summed totals as tuples
        var sessionDictInProgress: [String: (totalCount: Int, secondsPassed: TimeInterval)] = [:]
        
        // Parse through todaysSessions and build the dictionary
        for session in fetchedSessions /*todaysSessions*/ {
            sessionDictInProgress[session.title, default: (totalCount: 0, secondsPassed: 0)].totalCount += session.totalCount
            sessionDictInProgress[session.title, default: (totalCount: 0, secondsPassed: 0)].secondsPassed += session.secondsPassed
        }
        
        todaysSessionsDict = sessionDictInProgress
        
        // You can now use sessionSummary as needed
        print("Session Summary: \(todaysSessionsDict)")
        
    }
}

struct TaskCardView: View {
    let task: TaskModel

    var body: some View {
        VStack(alignment: .center) {
            
            Text(task.mantra)
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
                    .opacity(task.isCompleted ? 1 : 0)
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
    @State private var selectedMantra: String? = nil
    @State private var searchQuery: String = ""
    @State private var showMantraPicker: Bool = false
    @State private var userSelectedCountMin: Bool? = nil // Default to count mode
    @State private var goalString: String = ""
    @State private var debugTaskInfoOnScreen = 0
    @State private var taskInMaking: TaskModel? = nil
    
    @State private var showBorder: Bool = false
    
    init( isPresented: Binding<Bool>, scrollProxy: Binding<UUID?>) {
        self._isPresented = isPresented
        self._scrollProxy = scrollProxy
    }

    // Function to create and persist the TaskModel, then dismiss the view
    func createTask() {
        let task = TaskModel(
            mantra: selectedMantra ?? "",
            isCountMode: taskIsCountMode ?? false,
            goal: goal ?? 0
            //runningGoal: 0
        )

        // Save the task to the persistent context
        context.insert(task)

        isGoalEntryFocused = false //Dismiss keyboard when background tapped

        // i think we can get rid of this all since its all State vars... and we close the view so it will be redrawn anyways
        isZikrFocused = false
        isGoalFocused = false
        selectedMantra = ""
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
        goal == nil || taskIsCountMode == nil || selectedMantra == nil
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
                        
                        Text("Create a New Task")
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
                    
                    // NEW: Zikr Picker Sheet
                    Button(action: {
                        showMantraPicker = true
                    }) {
                        Text(selectedMantra ?? "" == "" ? "Zikr" : (selectedMantra ?? ""))
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(selectedMantra ?? "" == ""  ? Color.secondary.opacity(0.5) : accentColor.opacity(1))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(accentColor.opacity(0.5), lineWidth: 1)
                                    .foregroundStyle(accentColor.opacity(0.15))
                            )
                    }
                    .sheet(isPresented: $showMantraPicker) {
                        MantraPickerView(
                            isPresented: $showMantraPicker,
                            selectedMantra: $selectedMantra, //try putting sharedstate.titleforsession in here
                            presentation: [.height(400)]
                        )
                    }
                                        
                }
                .padding()
                .border(borderColor)
                
                Spacer()
                
                Button(action: {
                    createTask()
                }) {
                    Text("Confirm")
                        .foregroundStyle(parametersIncomplete ? .secondary: Color.green.opacity(0.7))
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
                .disabled(parametersIncomplete)
                .padding(.horizontal)
                
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
