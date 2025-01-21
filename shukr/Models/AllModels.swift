//
//  AllModels.swift
//  shukr
//
//  Created on 10/2/24.
//

import Foundation
import SwiftData
import SwiftUI

class SharedStateClass: ObservableObject {
    enum ViewPosition {
        case top
        case main
        case bottom
        case left
        case right
    }
    @Published var selectedMode: Int = 1
    
    @Published var titleForSession: String = ""
    @Published var selectedMinutes: Int = 0
    @Published var targetCount: String = ""

    @Published var isDoingPostNamazZikr: Bool = false
//    @Published var showingOtherPages: Bool = false
    @Published var showingPulseView: Bool = false
    @Published var showSalahTab: Bool = true
    @Published var navPosition: ViewPosition = .main
    @Published var cameFromNavPosition: ViewPosition = .main
    
    @Published var selectedTask: TaskModel? = nil {
        didSet {
            if let task = selectedTask{
//                let remainingGoal = task.isCountMode ? (task.goal - task.runningCount) : task.goal - Int(task.runningSeconds/60))
                titleForSession = task.mantra
                if(task.isCountMode){ //modeflag
                    selectedMode = 2
                    targetCount = "\(task.goal)"
                }else{
                    selectedMode = 1
                    selectedMinutes = task.goal
                }
            }
        }
    }
    
    func resetTasbeehInputs(){
        selectedTask = nil
        selectedMinutes = 0
        targetCount = ""
        titleForSession = ""
        selectedMode = 1
    }


//    @Published var newTopMainOrBottom: ViewPosition = .main {
//        didSet {
////            print("newTopMainOrBottom changed to: \(newTopMainOrBottom)")
//        }
//    }
//    var firstLaunch: Bool = true
    
}


@Model
class PrayerModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String // e.g., "Fajr", "Dhuhr"
    var dateAtMake: Date
    var startTime: Date
    var endTime: Date
    var isCompleted: Bool = false
    var timeAtComplete: Date? // Exact timestamp of marking completion
    var numberScore: Double? // Numerical performance score
    var englishScore: String? // Descriptive performance score (e.g., "Good", "Poor")
    var latPrayedAt: Double? // lat where the prayer was performed (Cant store CLLocation in swiftdata)
    var longPrayedAt: Double? // long where the prayer was performed

    var prayerStartedAt: Date? // When the prayer was started
    var prayerCompletedAt: Date? // When the prayer was marked complete
    var duration: TimeInterval? // How long the prayer lasted


    init(
        name: String,
        startTime: Date,
        endTime: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        dateAtMake: Date = .now
    ) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.latPrayedAt = latitude
        self.longPrayedAt = longitude
        self.dateAtMake = dateAtMake
    }
    
    func resetPrayer() {
        self.isCompleted = false
        self.timeAtComplete = nil
        self.numberScore = nil
        self.englishScore = nil
        self.latPrayedAt = nil
        self.longPrayedAt = nil
    }
}



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
        self.totalCount = totalCount
        self.startTime = startTime
        self.secondsPassed = secondsPassed
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
    
    @Attribute(.unique) var id: UUID = UUID()
    var mantra: String
    var isCountMode: Bool
    var goal: Int
//    var isComplete: Bool = false

    var isCompleted: Bool {
         isCountMode ? (runningCount >= goal) : (Int(runningSeconds/60) > goal)
    }

    var runningCount: Int = 0
    var runningSeconds: Double = 0
    
    init(mantra: String, isCountMode: Bool, goal: Int) {
        self.mantra = mantra
        self.isCountMode = isCountMode
        self.goal = goal
    }
    
    // Function to calculate running goal using a predicate
    func updateRunningGoal(with todaysSessions: [String: (totalCount: Int, secondsPassed: TimeInterval)]) {
        
        // search dict to find this mantra in it
        let sessionsForMantra = todaysSessions[self.mantra]
        
        // Calculate the running goal based on the task mode
        if isCountMode{
            runningCount = sessionsForMantra?.totalCount ?? 0
        } else{
            runningSeconds = sessionsForMantra?.secondsPassed ?? 0
        }

    }

//    func updateRunningGoal2(with todaysSessions: [SessionDataModel]) {
//        // Define today's start and end times
////        let todayStart = Calendar.current.startOfDay(for: Date())
////        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
////
////        // Store `mantra` locally for use in the predicate
////        let mantraCopy = self.mantra
////
////        // Build a fetch descriptor with a predicate
////        let fetchDescriptor = FetchDescriptor<SessionDataModel>(
////            predicate: #Predicate<SessionDataModel> {
////                $0.startTime >= todayStart &&
////                $0.startTime <= todayEnd &&
////                $0.title == mantraCopy // Use a local copy of `self.mantra`
////            },
////            sortBy: [SortDescriptor(\.startTime, order: .forward)]
////        )
////
////        // Fetch sessions matching the criteria
////        guard let todaysMantraSessions = try? context.fetch(fetchDescriptor) else {
////            print("❌ (updateRunningGoal) Failed to fetch sessions.")
////            return
////        }
//        
//        let sessionsForMantra = todaysSessions.filter { $0.title == self.mantra }
//
//        // Calculate the running goal based on the task mode
//        if isCountMode{
//            runningCount = sessionsForMantra.reduce(0) { $0 + $1.totalCount }
//        } else{
//            runningSeconds = sessionsForMantra.reduce(0) { $0 + $1.secondsPassed }
//        }
//
//    }
    
}



//@Model
//class TaskModel2: Identifiable {
//    
//    @Attribute(.unique) var id: UUID = UUID()
//    var mantra: String
//    var isCountMode: Bool
//    var goal: Int
//
//    var isCompleted: Bool {
//        goal != 0 && runningGoal != 0 && runningGoal >= goal
//    }
//    
//    var runningGoal: Int = 0 // Dynamically updated
//
//    init(mantra: String, isCountMode: Bool, goal: Int) {
//        self.mantra = mantra
//        self.isCountMode = isCountMode
//        self.goal = goal
//    }
//
//    // Function to calculate running goal using a predicate
//    func updateRunningGoal(using context: ModelContext) throws {
//        // Define today's start and end times
//        let todayStart = Calendar.current.startOfDay(for: Date())
//        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
//
//        // Build a fetch descriptor with a predicate
//        let fetchDescriptor = FetchDescriptor<SessionDataModel>(
//            predicate: #Predicate<SessionDataModel> {
//                $0.startTime >= todayStart &&
//                $0.startTime <= todayEnd &&
//                $0.title == self.mantra
//            },
//            sortBy: [SortDescriptor(\.startTime, order: .forward)]
//        )
//
//        // Fetch sessions matching the criteria
//        let todaysMantraSessions = try context.fetch(fetchDescriptor)
//
//        // Calculate the running goal
//        runningGoal = todaysMantraSessions.reduce(0) { $0 + $1.totalCount }
//    }
//}
