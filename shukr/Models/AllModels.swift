//
//  AllModels.swift
//  shukr
//
//  Created on 10/2/24.
//

import Foundation
import SwiftData
import SwiftUI
import CoreLocation
import WidgetKit

class SharedStateClass: ObservableObject {
    enum bottomTabEnum {
        case salah, zikr
    }
    enum ViewPosition {
        case top
        case main
        case bottom
        case left
        case right
    }
    @Published var selectedMode: Int = 1
    @Published var bottomTabPosition: bottomTabEnum = .salah
    
    @Published var titleForSession: String = ""
    @Published var selectedMinutes: Int = 0
    @Published var targetCount: String = ""

    @Published var isDoingPostNamazZikr: Bool = false
//    @Published var showingOtherPages: Bool = false
    @Published var allowQiblaHaptics: Bool = false
    @Published var showSalahTabOld: Bool = true
    @Published var navPosition: ViewPosition = .main
    @Published var cameFromNavPosition: ViewPosition = .main
    @Published var showSideMenu: Bool = false
    
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
    
    enum prayerStatus {
        case current
        case upcoming
        case missed
        // havent added this into status yet
        case completed_Valid
        case completed_Kaza
    }
    
    func status() -> prayerStatus { // we can expand this out to use and enum and make that
        let currentTime = Date()
        let isCurrent = currentTime >= startTime && currentTime < endTime
        let isUpcoming = currentTime < startTime
        //let completedInTimeRange = currentTime >= startTime && currentTime < endTime
        
        if isCurrent { return .current }
        else if isUpcoming { return .upcoming }
        else{ return .missed }
    }
    
    func setPrayerScore(atDate: Date = Date()) {
        print("setting time at complete as: ", atDate)
        timeAtComplete = atDate

        if let completedTime = timeAtComplete {
            let timeLeft = endTime.timeIntervalSince(completedTime)
            let totalInterval = endTime.timeIntervalSince(startTime)
            let score = timeLeft / totalInterval
            numberScore = max(0, min(score, 1))

            if let percentage = numberScore {
                if percentage > 0.50 {
                    englishScore = "Optimal"
                } else if percentage > 0.25 {
                    englishScore = "Good"
                } else if percentage > 0 {
                    englishScore = "Poor"
                } else {
                    englishScore = "Kaza"
                }
            }
        }
    }
    
    func setPrayerLocation(with location: CLLocation?) {
        guard let location = location else {
            print("Location not available")
            return
        }
        print("setting location at complete as: ", location.coordinate.latitude, "and ", location.coordinate.longitude)
        latPrayedAt = location.coordinate.latitude
        longPrayedAt = location.coordinate.longitude

    }
    
    func cancelUpcomingNudges(){
        // need to do a check for if the prayer is in the same day as today... else toggling complete on a past prayer will also cancel todays active prayer's notif...
        let prayerInToday = Calendar.current.isDate(startTime, inSameDayAs: Date())
        let center = UNUserNotificationCenter.current()
        let identifiers = ["\(name)Mid", "\(name)End"]

        if prayerInToday {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            print("✅ Canceled notifications for \(name): [\(identifiers)]")
        }else{
            print("⚪️ prayerInToday \(prayerInToday) - so skipped cancel notifications for \(name): [\(identifiers)]")
        }
        
    }
    
    func getColorForPrayerScore() -> Color {
        guard let score = numberScore else { return .gray }

        if score >= 0.50 {
            return .green
        } else if score >= 0.25 {
            return .yellow
        } else if score > 0 {
            return .red
        } else {
            return .gray
        }
    }
    
    func weightedSummaryScoreFromNumberScore() -> Double {
        guard let score = numberScore else { return 0 }
        
        // If prayed in the first 25% of the window, return 100%
        if score >= 0.75 {
            return 1.0
        }
        
        // For prayers after the 25% mark
        // Map the score from [0, 0.75] to [0.65, 0.9]
        let scaledScore = (score / 0.75) * 0.25 + 0.65
        
        return scaledScore
        
//        guard let score = numberScore else { return 0 }
//        if score >= 0.75 {
//            return 1
//        } else if score >= 0.5 {
//            return 0.9
//        } else if score > 0.25 {
//            return 0.8
//        } else if score > 0 {
//            return 0.7
//        } else {
//            return 0.0
//        }
    }
    
//    func weightedSummaryScoreFromEnglishScore() -> Double {
//        switch englishScore {
//        case "Optimal":
//            return 1.0
//        case "Good":
//            return 0.85
//        case "Poor":
//            return 0.75
//        case "Kaza":
//            return 0.5
//        default:
//            return 0.0
//        }
//    }

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


@Model
class DailyPrayerScore {
    @Attribute(.unique) var id: UUID = UUID()
    var date: Date
    var averageScore: Double?

    init(date: Date) {
        self.date = date
    }

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
