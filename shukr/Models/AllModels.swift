//
//  AllModels.swift
//  shukr
//
//  Created on 10/2/24.
//

import Foundation
import SwiftData
import SwiftUI




@Model
class DuaModel: Identifiable { // Updated to use SwiftData model //GPT
    @Attribute(.unique) var id: UUID = UUID()
    var title: String
    var duaBody: String
    var date: Date
    
    init(id: UUID = UUID(), title: String, duaBody: String, date: Date) { // Default UUID parameter //GPT
        self.id = id
        self.title = title
        self.duaBody = duaBody
        self.date = date
    }
}





@Model
class MantraModel: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String

    init(text: String) {
        self.id = UUID()
        self.text = text
    }
}





class MockModelContext: ObservableObject {
    @Published var sessions: [SessionDataModel]
    @Published var mantras: [MantraModel]

    init(sessions: [SessionDataModel], mantras: [MantraModel]) {
        self.sessions = sessions
        self.mantras = mantras
    }
}





@Model
class SessionDataModel: Identifiable {

    @Attribute(.unique) var id: UUID = UUID()

    var title: String                   // (placeHolderTitle for now...)
    var sessionMode: Int                // selectedMode
    var targetMin: Int                  // selectedMin
    var targetCount: Int                // targetCount

    var totalCount: Int                 // tasbeeh
    
    var startTime: Date                 // startTime (prev sessionTime)
    var secondsPassed: TimeInterval     // ???
    var timeDurationString: String         // formatTimePassed
    var avgTimePerClick: TimeInterval   // avgTimePerClick

    var tasbeehRate: String             // tasbeehRate

    
    init(title: String, sessionMode: Int, targetMin: Int, targetCount: Int, totalCount: Int, startTime: Date, secondsPassed: TimeInterval, avgTimePerClick: TimeInterval, tasbeehRate: String) {
        self.title = title
        self.sessionMode = sessionMode
        self.targetMin = targetMin
        self.targetCount = targetCount
        self.totalCount = totalCount /* clickStats.count */
        self.startTime = startTime
        self.secondsPassed = secondsPassed /* clickStats.last?.date.timeIntervalSince(startTime)*/
        var formatFromSeconds: String{
            let minutes = Int(secondsPassed) / 60
            let seconds = Int(secondsPassed) % 60
            
            if minutes > 0 { return "\(minutes)m \(seconds)s"}
            else { return "\(seconds)s" }
        }
        self.timeDurationString = formatFromSeconds
        self.avgTimePerClick = avgTimePerClick
        self.tasbeehRate = tasbeehRate
    }
}





@Model
class TaskModel: Identifiable {
    
    //mineeeeeeeeeeeeeeeeeeeeeeeeeeee

    @Attribute(.unique) var id: UUID = UUID()
    var mantra: String
    var isCountMode: Bool
//    var mode: TaskMode
    var goal: Int

//    var sessionItems: [SessionDataModel]

    var isCompleted: Bool {
        goal != 0 && runningGoal != 0 && runningGoal >= goal
    }

    var runningGoal: Int = 0

//    enum TaskMode: String, Codable {
//        case count, time
//    }
    
    init(mantra: String, /*mode: TaskMode*/ isCountMode: Bool, goal: Int/*, sessionItems: [SessionDataModel]*/) {
        self.mantra = mantra
//        self.mode = mode
        self.isCountMode = isCountMode
        self.goal = goal
//        self.sessionItems = sessionItems
    }
    
    // Calculate running goal for the task
//        func calculateRunningGoal(from sessionItems: [SessionDataModel]) {
//            if mode == .count {
//                runningGoal = sessionItems.filter { session in
//                    Calendar.current.isDateInToday(session.startTime) && session.title == mantra
//                }.reduce(0) { $0 + $1.totalCount }
//            } else {  // For time-based tasks
//                runningGoal = sessionItems.filter { session in
//                    Calendar.current.isDateInToday(session.startTime) && session.title == mantra
//                }.reduce(0) { $0 + Int($1.secondsPassed / 60) } // Calculate minutes
//            }
//        }

//        // Check if task is completed
//        func isCompleted(from sessionItems: [SessionDataModel]) -> Bool {
//            return calculateRunningGoal(from: sessionItems) >= goal
//        }
}
