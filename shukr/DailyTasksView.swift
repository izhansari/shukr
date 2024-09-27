//
//  DailyTasksView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI


struct DailyTasksView: View {
    struct Task {
        var mantra: String
        var mode: TaskMode
        var countGoal: Int?
        var timeGoal: Int?
        var isCompleted: Bool
    }

    enum TaskMode {
        case count, time
    }

//    var tasks: [Task] = [] // Empty tasks array to simulate no tasks
    var tasks: [Task] = [
        Task(mantra: "Alhamdulillah", mode: .count, countGoal: 100, timeGoal: nil, isCompleted: false),
        Task(mantra: "Subhanallah", mode: .time, countGoal: nil, timeGoal: 10, isCompleted: true),
        Task(mantra: "Allahu Akbar", mode: .count, countGoal: 200, timeGoal: nil, isCompleted: false)
    ]

    var body: some View {
        if tasks.isEmpty {
            // Default view for when there are no tasks
            NoTasksView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tasks.indices, id: \.self) { index in
                        TaskCardView(task: tasks[index])
                    }

                    // Plus Button Card
                    Button(action: {
                        // Handle adding new task
                    }) {
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
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
    var body: some View {
        VStack {
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
        .padding()
    }
}

struct TaskCardView: View {
    let task: DailyTasksView.Task

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
                if task.mode == .count, let countGoal = task.countGoal {
                    HStack(spacing: 0) { // Reduced space between icon and text
                        Image(systemName: "number")
                        Text("\(countGoal)")
                    }
                } else if task.mode == .time, let timeGoal = task.timeGoal {
                    HStack(spacing: 1) { // Reduced space between icon and text
                        Image(systemName: "timer")
                        Text("\(timeGoal)m")
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
    DailyTasksView()
}
