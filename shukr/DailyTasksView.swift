//
//  DailyTasksView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData


struct DailyTasksView: View {
    @Binding var showAddTaskScreen: Bool
    
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.presentationMode) var presentationMode

    @Environment(\.modelContext) private var context
    @Query private var taskItems: [TaskModel] // Query to fetch persisted TaskModel items
    @Query private var sessionItems: [SessionDataModel]
    
    @State private var showDeleteTaskAlert: Bool = false
    @State private var showTaskCompletionTypePrompt: Bool = false
    var titleOfTaskToDelete: String = ""
    @State private var taskToDelete: TaskModel? = nil
    @State private var taskToComplete: TaskModel? = nil

    var dataTasks: [TaskModel] = []

    var body: some View {
        if taskItems.isEmpty /*tasks.isEmpty*/ {
            // Default view for when there are no tasks
            NoTasksView(showAddTaskScreen: $showAddTaskScreen)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(taskItems/*tasks.indices*/, id: \.self) { task in
                        TaskCardView(task: task/*tasks[index]*/)
                            .onLongPressGesture{
//                                titleOfTaskToDelete = task.mantra
                                taskToDelete = task
                                showDeleteTaskAlert = true
                            }
                            .onTapGesture {
                                let remainingGoal = task.goal - task.runningGoal
                                taskToComplete = task
                                sharedState.titleForSession = task.mantra
                                if(task.mode == .count){
                                    sharedState.selectedPage = 2
                                    sharedState.targetCount = "\(remainingGoal <= 0 ? task.goal : remainingGoal)"
                                }else{
                                    sharedState.selectedPage = 1
                                    sharedState.selectedMinutes = remainingGoal <= 0 ? task.goal : remainingGoal
                                }
                                self.presentationMode.wrappedValue.dismiss()
                            }
                            .onAppear{
                                task.calculateRunningGoal(from: sessionItems) // not the best way to do this but okay for now... will work on this later.
                                print(">>>>>>>on appear")
                            }
                            .onChange(of: sessionItems) {_, newSessions in
                                task.calculateRunningGoal(from: newSessions)
                                print(">>>>>>>cuz change")
                            }
                    }
                    .alert(isPresented: $showDeleteTaskAlert) {
                        Alert(
                            title: Text("Delete Task"),
                            message: Text("Are you sure you want to delete your \(taskToDelete?.mantra ?? "") task?"),
                            primaryButton: .destructive(Text("Delete")) {
                                if let session = taskToDelete {
                                    context.delete(session) // Delete from SwiftData
                                    taskToDelete = nil // Reset the sessionToDelete
                                }
                            },
                            secondaryButton: .cancel {
                                taskToDelete = nil // Reset the sessionToDelete
                            }
                        )
                    }
//                    .alert(isPresented: $showTaskCompletionTypePrompt) {
//                        Alert(
//                            title: Text("Choose Completion Type"),
//                            message: Text("Would you like to complete the remaining or do a full session for the target?"),
//                            primaryButton: .default(Text("Remaining")) {
////                                if let session = taskToDelete {
//                                    taskToComplete = nil // Reset the sessionToDelete
////                                }
//                            },
//                            secondaryButton: .cancel {
//                                taskToComplete = nil // Reset the sessionToDelete
//                            }
//                        )
//                    }


                    // Plus Button Card
                    Button(action: {
                        showAddTaskScreen = true
                    }) {
                        VStack {
//                            Image(systemName: "plus.circle.fill")
//                                .resizable()
//                                .frame(width: 40, height: 40)
//                                .foregroundColor(.gray)
                            Image(systemName: "plus.circle")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.green.opacity(0.7))
                        }
                        .frame(width: 100, height: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 25)
            }
        }
    }
}

struct NoTasksView: View {
    @Binding var showAddTaskScreen: Bool

    var body: some View {
        VStack {
            Button(action: {
                showAddTaskScreen = true
            }) {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 190, height: 100)
                    .overlay(
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
                    )
            }
        }
    }
}



struct AddDailyTaskView: View {
    @Binding var isPresented: Bool
    
    @FocusState var isGoalEntryFocused: Bool
    
    @Environment(\.modelContext) private var context
    @Query private var taskItems: [TaskModel] // Query to fetch persisted TaskModel items
    @Query private var sessionItems: [SessionDataModel]

    // Task creation properties
    @State private var mantra: String? = "" // Will be updated by MantraPickerView
    @State private var taskMode: TaskModel.TaskMode = .count // Default to count mode
    @State private var goal: Int = 0
    @State private var selectedMantra: String? = nil
    @State private var showMantraPicker: Bool = false
    
    
    private var allowButtonClick: Bool {
        return (mantra == "" || mantra == nil || goal <= 0)
    }
    
    @State private var debugTaskInfoOnScreen = 0
    
    @State private var taskInMaking: TaskModel? = nil
    
    var runningGoalToShow: String{
        if let yo = taskInMaking{
            return "completed \(yo.runningGoal) \(yo.mode == .count ? "count" : "minutes")"
        }
        return ""
    }

    // Function to create and persist the TaskModel, then dismiss the view
    func createTask() {
        let task = TaskModel(
            mantra: mantra ?? "",
            mode: taskMode,
            goal: goal
//            sessionItems: sessionItems
//            runningGoal: 0
        )
        
        // Save the task to the persistent context
        context.insert(task)
        
        isGoalEntryFocused = false //Dismiss keyboard when background tapped
        
        // Reset the form after saving
        mantra = ""
        goal = 0
        isPresented = false // Dismiss the view after task creation
    }
    
    var body: some View {
        VStack {
            
            // Add a cancel button (X) at the top-right corner
            HStack {
                Spacer()
                Button(action: {
                    isPresented = false // Close the view when the X button is pressed
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.gray.opacity(0.7)) // Style similar to pause/cancel buttons
//                        .padding(.top, 10)
                        .padding(.trailing, 10)
                }
            }.padding()
            
            Text("Create a New Task")
                .font(.title)
                .fontWeight(.thin)
                .padding(.bottom, 20)
            
            TaskCardView(task: TaskModel(
                mantra: mantra == "" ? "choose mantra" : mantra ?? "its nil",
                mode: taskMode,
                goal: goal
//                sessionItems: sessionItems
                )
            )
            .padding(40)
            
            
            // Picker for selecting Task Mode (count or time)
            Picker("Task Mode", selection: $taskMode) {
                Text("Count").tag(TaskModel.TaskMode.count)
                Text("Time").tag(TaskModel.TaskMode.time)
            }
            .frame(width: 200)
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Input field for goal
            HStack {
                TextField("goal", value: $goal, formatter: NumberFormatter())
                    .focused($isGoalEntryFocused)
                    .keyboardType(.numberPad)
                    .fontWeight(.light)
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 100, height: 100)
            }
            .padding(.horizontal)

            // Button to open MantraPickerView
            Button(action: {
                showMantraPicker.toggle()
            }) {
                Text("Select Mantra")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
//            Text("\(runningGoalToShow)")
//                .onChange(of: mantra){
//                    taskInMaking = TaskModel(mantra: mantra ?? "", mode: taskMode, goal: goal, sessionItems: sessionItems)
//                }
//                .onChange(of: goal){
//                    taskInMaking = TaskModel(mantra: mantra ?? "", mode: taskMode, goal: goal, sessionItems: sessionItems)
//                }
//                .onChange(of: taskMode){
//                    taskInMaking = TaskModel(mantra: mantra ?? "", mode: taskMode, goal: goal, sessionItems: sessionItems)
//                }
            
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(isPresented: $showMantraPicker, selectedMantra: $mantra)
            }
            
            Spacer()
            
            // Button to create the task
            Button(action: {
                createTask()
            }) {
                Text("Create Task")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(!allowButtonClick ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .padding(.bottom, 20)
            .disabled(allowButtonClick)
        }
        .background(Color("pauseColor"))
        .onTapGesture {
            isGoalEntryFocused = false //Dismiss keyboard when background tapped
        }
        .opacity(isPresented ? 1 : 0.0)
        .animation(.easeInOut, value: isPresented)
    }
}


struct TaskCardView: View {
    let task: TaskModel

    var body: some View {
        VStack(alignment: .leading) {
            
            // Mantra title at the top, fixed height for consistency
            Text(task.mantra)
                .font(.headline)
                .bold()
                .multilineTextAlignment(.leading)
                .lineLimit(2) // Limit to 2 lines for consistency
                .padding(.top, 8)
                .padding(.horizontal, 9)
            
            Spacer()
            
            // Bottom section: Mode icon and goal on the left, completion indicator on the right
            HStack(spacing: 2) { // Reduced space between icon and goal
                HStack(spacing: 0) { // Reduced space between icon and text
                    if task.mode == .count {
                        Image(systemName: "number")
                        Text("\(task.goal)")
                    } else {
                        Image(systemName: "timer")
                        Text("\(task.goal)m")
                    }
                }

                Spacer()

                // Completion indicator (circle)
                if task.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(.trailing, 5) // Padding from the right
                        .padding(.top, 5) // Padding from the top
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .padding(.trailing, 5)
                        .padding(.top, 5)
                }
            }
            .padding(.all, 8)

        }
        .frame(width: 140, height: 100)
        .background(task.isCompleted ? Color.green.opacity(0.3) : Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    @Previewable @State var testBool: Bool = true
    ZStack{
        VStack{
            DailyTasksView(showAddTaskScreen: $testBool)
            Spacer()
        }
        AddDailyTaskView(isPresented: $testBool)
    }
}
