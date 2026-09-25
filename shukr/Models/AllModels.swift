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
import UserNotifications

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
    /// Vertical state of the center page only (.main = circle, .bottom = salah sheet open).
    /// Paging to Zikr / Settings does NOT change this, so the center page comes back exactly
    /// as it was left. (.left / .right / .top are legacy and no longer set.)
    @Published var navPosition: ViewPosition = .main
    @Published var cameFromNavPosition: ViewPosition = .main // legacy, unused
    @Published var showSideMenu: Bool = false                  // legacy, unused (menu is a native Menu now)

    /// Which page of the horizontal pager is showing. Written by the pager when a swipe
    /// settles, and by anything that wants to navigate (bottom bar, widget deep link, menu).
    enum HorizontalPage: Hashable { case zikr, main, settings }
    @Published var horizontalPage: HorizontalPage = .main
    
    /// The mantra object behind `titleForSession`, so a saved session can link to it.
    /// Nil when the title came from somewhere without a row (post-salah sequence); `saveSession`
    /// then falls back to a lookup by name.
    @Published var mantraForSession: MantraModel? = nil

    @Published var selectedTask: TaskModel? = nil {
        didSet {
            if let task = selectedTask{
//                let remainingGoal = task.isCountMode ? (task.goal - task.runningCount) : task.goal - Int(task.runningSeconds/60))
                titleForSession = task.displayName
                mantraForSession = task.mantra
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
        mantraForSession = nil
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
    
    /// Scores the prayer as marked at `atDate` (PrayerScoring has the rule).
    func setPrayerScore(atDate: Date = Date()) {
        timeAtComplete = atDate
        let score = PrayerScoring.score(start: startTime, end: endTime, markedAt: atDate)
        numberScore = score
        englishScore = PrayerScoring.grade(for: score).rawValue
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
        PrayerScoring.color(for: numberScore)
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





/// A zikr the user can count. Tasks and sessions point at it; renaming it renames them.
/// Schema V2 (see `SchemaVersions.swift`): `text` became `name`, plus `fullText` / `notes`.
@Model
class MantraModel: Identifiable {
    /// Ship-with-the-app mantras. Seeded as real rows (migration + first launch) so they are
    /// editable like any other; this list is only the seed source.
    static let builtIn: [String] = ["Alhamdulillah", "Subhanallah", "Allahu Akbar", "Astaghfirullah"]

    @Attribute(.unique) var id: UUID = UUID()
    /// Short name: what cards, the picker and session titles show.
    @Attribute(originalName: "text") var name: String
    /// The full mantra (Arabic / transliteration) to refresh memory mid-session.
    var fullText: String = ""
    /// Free-form notes ("sheikh said read this every morning…").
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \TaskModel.mantraRef)
    var tasks: [TaskModel] = []
    @Relationship(deleteRule: .nullify, inverse: \SessionDataModel.mantra)
    var sessions: [SessionDataModel] = []

    init(name: String, fullText: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.fullText = fullText
        self.notes = notes
        self.createdAt = .now
    }

    /// Case-insensitive, whitespace-trimmed lookup by name.
    static func find(named name: String, in context: ModelContext) -> MantraModel? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, let all = try? context.fetch(FetchDescriptor<MantraModel>()) else { return nil }
        return all.first { $0.name.lowercased() == key }
    }

    /// Insert any built-in that isn't there yet. Runs on fresh installs (the migration seeds
    /// upgrades). Returns how many were added; the caller saves.
    @discardableResult
    static func seedBuiltInsIfNeeded(in context: ModelContext) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).map { $0.name.lowercased() })
        var added = 0
        for name in builtIn where !existing.contains(name.lowercased()) {
            context.insert(MantraModel(name: name))
            added += 1
        }
        return added
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

    /// The daily task this session was started from (nil for freestyle / post-salah / legacy sessions).
    /// Only linked sessions count toward a task's daily progress.
    var task: TaskModel?
    /// The mantra counted. `title` stays as the snapshot of its name at the time, so history
    /// keeps reading right if the mantra is renamed or deleted.
    var mantra: MantraModel?


    init(title: String, sessionMode: Int, targetMin: Int, targetCount: Int, totalCount: Int, startTime: Date, secondsPassed: TimeInterval, avgTimePerClick: TimeInterval, tasbeehRate: String, task: TaskModel? = nil, mantra: MantraModel? = nil) {
        self.task = task
        self.mantra = mantra
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
    /// Name snapshot (was the only `mantra` field before V2). Fallback for display if the
    /// mantra row is gone; the editor keeps it in step with renames.
    @Attribute(originalName: "mantra") var mantraName: String
    /// The mantra this task counts. Inverse of `MantraModel.tasks`. Stored as `mantraRef`, not
    /// `mantra`: `mantraName` carries the renaming identifier "mantra" (above), and Core Data's
    /// inferred migration requires renaming identifiers to be unique within an entity — a
    /// relationship also named `mantra` broke the upgrade on iOS 27 (CoreData 134190, "Each
    /// property must have a unique renaming identifier"). Code keeps using `mantra` below.
    var mantraRef: MantraModel?
    var mantra: MantraModel? {
        get { mantraRef }
        set { mantraRef = newValue }
    }
    var isCountMode: Bool
    var goal: Int
    /// Position on the Zikr page's card strip; the user sets it from the card's edit button.
    /// New tasks go to the end. (Schema V2; the migration numbers existing tasks.)
    var sortOrder: Int = 0

    /// Sessions started from this task's card. Inverse of `SessionDataModel.task`.
    /// Deleting a task keeps its sessions in history (nullify), it just unlinks them.
    @Relationship(deleteRule: .nullify, inverse: \SessionDataModel.task)
    var sessions: [SessionDataModel] = []

    /// What to show on the card: the live mantra name, or the snapshot if it was deleted.
    var displayName: String { mantra?.name ?? mantraName }

    init(mantra: MantraModel?, isCountMode: Bool, goal: Int, mantraName: String? = nil, sortOrder: Int = 0) {
        self.mantraRef = mantra
        self.mantraName = mantraName ?? mantra?.name ?? ""
        self.isCountMode = isCountMode
        self.goal = goal
        self.sortOrder = sortOrder
    }

    /// One past the highest `sortOrder` in the store, so a new task lands at the end.
    static func nextSortOrder(in context: ModelContext) -> Int {
        (((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).map(\.sortOrder).max() ?? -1) + 1
    }

    /// Today's progress toward this task, computed from the sessions that were
    /// explicitly started from it. Freestyle sessions with the same mantra do not
    /// count, and one task's sessions never spill into another task with the same mantra.
    func progress(in todaysSessions: [SessionDataModel]) -> TaskProgress {
        let mine = todaysSessions.filter { $0.task?.persistentModelID == persistentModelID }
        return TaskProgress(
            count: mine.reduce(0) { $0 + $1.totalCount },
            seconds: mine.reduce(0) { $0 + $1.secondsPassed }
        )
    }

    func isCompleted(with progress: TaskProgress) -> Bool {
        isCountMode ? (progress.count >= goal) : (progress.seconds >= Double(goal) * 60)
    }
}

struct TaskProgress {
    var count: Int = 0
    var seconds: TimeInterval = 0
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


// MARK: - Mantra stats

extension MantraModel {
    /// What the sessions linked to this mantra add up to. Nothing is stored: sessions are the
    /// record, so the numbers can't drift, and a session that's deleted or relinked is
    /// reflected at once.
    var totalCount: Int { sessions.reduce(0) { $0 + $1.totalCount } }
    var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.secondsPassed } }

    /// Average seconds per count, time-weighted over every session that counted something
    /// (active seconds / total counts), so a long slow session weighs more than a quick one.
    /// Uses each session's `activeSeconds`, so time left running after the last count doesn't
    /// inflate it. Nil until something has been counted.
    var secondsPerCount: TimeInterval? {
        let counted = sessions.filter { $0.totalCount > 0 && $0.activeSeconds > 0 }
        let counts = counted.reduce(0) { $0 + $1.totalCount }
        guard counts > 0 else { return nil }
        return counted.reduce(0.0) { $0 + $1.activeSeconds } / Double(counts)
    }
}

extension SessionDataModel {
    /// Time actually spent counting: up to the last count, pauses excluded. `secondsPassed` runs
    /// until the session was stopped, so a session left running after the last tap (phone set
    /// down, app in the background, stopped for inactivity) showed e.g. 33.6 s per count for a
    /// real pace of 5.1 s (owner's data, 2026-09-25). `avgTimePerClick` is recomputed at every
    /// count as (time so far − pauses) / count, so × count = the time at the last count.
    /// Falls back to `secondsPassed` for sessions saved without it.
    var activeSeconds: TimeInterval {
        guard avgTimePerClick > 0, totalCount > 0 else { return secondsPassed }
        return min(avgTimePerClick * Double(totalCount), secondsPassed > 0 ? secondsPassed : .infinity)
    }

    /// Seconds per count over the active time; nil if nothing was counted.
    var secondsPerCount: TimeInterval? {
        guard totalCount > 0, activeSeconds > 0 else { return nil }
        return activeSeconds / Double(totalCount)
    }
}

/// "1h 05m", "12m 03s" or "45s".
func zikrDurationString(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    if m > 0 { return String(format: "%dm %02ds", m, sec) }
    return "\(sec)s"
}
