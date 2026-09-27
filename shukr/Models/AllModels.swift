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

    /// "Continue from where you left off" on a task (Zikr page): the next session starts with
    /// today's count / time already on the ring. Read and cleared by `tasbeehView.startTimer`;
    /// only the new counts are saved, so today's total isn't counted twice.
    var resumeCount: Int = 0
    var resumeSeconds: TimeInterval = 0

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

    /// The masjid it was prayed at (schema 2.2.0, `MasjidDetector`): nil = not checked yet,
    /// "" = checked, not at a masjid.
    var mosqueName: String? = nil

    /// What the app recorded when the prayer was marked, kept the first time the user edits the
    /// time / the spot (schema 2.3.0, owner 2026-09-26: "so I can always revert it"). nil = never
    /// edited (the live value is the recorded one).
    var recordedTimeAtComplete: Date? = nil
    var recordedLat: Double? = nil
    var recordedLon: Double? = nil

    var recordedSpot: CLLocationCoordinate2D? {
        guard let recordedLat, let recordedLon else { return nil }
        return CLLocationCoordinate2D(latitude: recordedLat, longitude: recordedLon)
    }
    /// The time was changed from what was recorded (by more than half a minute).
    var timeEdited: Bool {
        guard let recorded = recordedTimeAtComplete, let now = timeAtComplete else { return false }
        return abs(now.timeIntervalSince(recorded)) >= 30
    }
    /// The spot was moved from where it was recorded (by more than a few metres).
    var spotEdited: Bool {
        guard let r = recordedSpot, let lat = latPrayedAt, let lon = longPrayedAt else { return false }
        return CLLocation(latitude: r.latitude, longitude: r.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon)) > 3
    }
    /// A user's time edit: keeps the recorded time (once), then rescores at the new one.
    func editTime(to date: Date) {
        if recordedTimeAtComplete == nil { recordedTimeAtComplete = timeAtComplete }
        setPrayerScore(atDate: date)
    }
    /// Back to the time the app recorded.
    func revertTime() {
        guard let recorded = recordedTimeAtComplete else { return }
        setPrayerScore(atDate: recorded)
        recordedTimeAtComplete = nil
    }

    var atMasjid: Bool { !(mosqueName ?? "").isEmpty }
    /// Friday's Dhuhr prayed at a masjid — and only that (owner: a Friday Dhuhr anywhere else is
    /// a normal Dhuhr). Scores full marks whatever the clock says: Jumu'ah follows the masjid's
    /// time, so it's never graded by the clock — it just reads "Jumu'ah" (owner, 2026-09-26).
    var isJumuah: Bool {
        name == "Dhuhr" && atMasjid && Calendar.current.component(.weekday, from: startTime) == 6
    }
    var displayName: String { isJumuah ? "Jumu'ah" : name }
    /// The grade in words: "Perfect", "On time"… — for a Jumu'ah just "Jumu'ah". Read this rather
    /// than the stored `englishScore`, which older rows wrote as "Early".
    var gradeWord: String? {
        guard let s = numberScore else { return nil }
        return isJumuah ? "Jumu'ah" : PrayerScoring.grade(for: s).rawValue
    }
    /// "On time · 88"; a Jumu'ah says "Jumu'ah" (at its masjid) instead of a grade.
    var scoreSummary: String? {
        guard let s = numberScore else { return nil }
        guard isJumuah else { return PrayerScoring.summary(for: s) }
        return mosqueName.map { "Jumu'ah at \($0)" } ?? "Jumu'ah"
    }

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
        self.mosqueName = nil
        self.recordedTimeAtComplete = nil
        self.recordedLat = nil
        self.recordedLon = nil
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
        let score = isJumuah ? 1 : PrayerScoring.score(start: startTime, end: endTime, markedAt: atDate)
        numberScore = score
        englishScore = gradeWord
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
    
    /// Marked prayed: its Mid / End nudges go (dated ids, so exactly this day's — any day can be
    /// cancelled now; the undated ids of older builds only for today).
    func cancelUpcomingNudges(){
        let center = UNUserNotificationCenter.current()
        var identifiers = ["Mid", "End"].map { PrayerNotificationID.make(day: startTime, prayer: name, kind: $0) }
        if Calendar.current.isDate(startTime, inSameDayAs: PrayerDay.date()) {
            identifiers += ["\(name)Mid", "\(name)End"]   // legacy, pre-2026-09-27
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("✅ Canceled notifications for \(name): \(identifiers)")
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
    /// The tasbeeh's quick-add step for this mantra: a "+N" button that counts N in one tap;
    /// 0 = no button (schema 2.1.0, 2026-09-25; briefly lived in UserDefaults before that).
    var quickAddStep: Int = 0
    var createdAt: Date = Date()
    /// For learning it (schema 2.5.0, 2026-09-27, notes #17): one photo (a written dua, calligraphy,
    /// a teacher's handwriting; JPEG, ~1200 px) and one voice memo (how it's said; AAC .m4a, ≤ 2 min).
    /// Stored outside the database file.
    @Attribute(.externalStorage) var imageData: Data? = nil
    @Attribute(.externalStorage) var audioData: Data? = nil

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

    /// Set on the app's own rows (the built-ins and Tasbih Fatimah) by the seeders / `tagRows`
    /// (schema 2.6.0). Never guessed from the name.
    var builtInID: String? = nil
    /// A built-in (or Tasbih Fatimah): name and full text locked, never deleted.
    var isBuiltIn: Bool { builtInID != nil }

    /// Case-insensitive, whitespace-trimmed lookup by name.
    static func find(named name: String, in context: ModelContext) -> MantraModel? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let all = try? context.fetch(FetchDescriptor<MantraModel>()) else { return nil }
        // Exact name first, then the shared normalisation (letters and digits).
        return all.first { $0.name == trimmed } ?? all.first { BuiltInAzkar.key($0.name) == BuiltInAzkar.key(trimmed) }
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

    /// The user's own name for the task, e.g. "After Fajr" (schema 2.4.0, notes #7). nil / empty =
    /// none: the task is called by its mantra, as before.
    var customName: String? = nil
    /// The task's title: its own name, else the mantra.
    var title: String {
        let own = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return own.isEmpty ? displayName : own
    }
    /// The mantra, when the title is the task's own name (shown smaller, under it).
    var mantraLine: String? {
        let own = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return own.isEmpty ? nil : displayName
    }

    // One reminder per task (schema 2.4.0, notes #11; off while `reminderKind` is nil).
    /// "time" (a clock time) or "prayer" (minutes before / after a prayer); nil = no reminder.
    var reminderKind: String? = nil
    /// For "time": minutes after midnight (e.g. 20:00 → 1200).
    var reminderTimeMinutes: Int? = nil
    /// For "prayer": the prayer, and minutes from its start (negative = before).
    var reminderPrayer: String? = nil
    var reminderOffsetMinutes: Int? = nil
    /// Which weekdays, as bits (Sunday = 1 << 0 … Saturday = 1 << 6); nil = every day.
    var reminderWeekdays: Int? = nil

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

extension TaskModel {
    /// Your pace for this task: the mantra's time-weighted seconds per count, else the task's own
    /// sessions'. Nil until something has been counted.
    var secondsPerCount: TimeInterval? {
        if let rate = mantra?.secondsPerCount { return rate }
        let counted = sessions.filter { $0.totalCount > 0 && $0.activeSeconds > 0 }
        let counts = counted.reduce(0) { $0 + $1.totalCount }
        guard counts > 0 else { return nil }
        return counted.reduce(0.0) { $0 + $1.activeSeconds } / Double(counts)
    }

    /// Roughly how long what's left of today's goal takes: counts left × your pace, or the minutes
    /// left for a timed task. 0 when done; nil for a count task with no history yet.
    func secondsLeft(_ progress: TaskProgress) -> TimeInterval? {
        if isCompleted(with: progress) { return 0 }
        if isCountMode {
            guard let rate = secondsPerCount else { return nil }
            return Double(max(goal - progress.count, 0)) * rate
        }
        return max(Double(goal) * 60 - progress.seconds, 0)
    }
}

extension TaskModel {
    /// A timed task: roughly how many counts you'll have reached when the minutes are up (today's
    /// counts + minutes left ÷ your pace). Nil for count tasks, or with no pace yet.
    func countsAtGoal(_ progress: TaskProgress) -> Int? {
        guard !isCountMode, let rate = secondsPerCount, rate > 0 else { return nil }
        let left = max(Double(goal) * 60 - progress.seconds, 0)
        return progress.count + Int((left / rate).rounded())
    }

    /// The quiet third line on a task: how long a count goal will take ("~4 min"), or how many
    /// counts a timed goal will come to ("~780 counts") — "~1 min" under "0 of 1 min" said nothing
    /// (owner). Nil when done or with no history.
    func estimateNote(_ progress: TaskProgress) -> String? {
        if isCompleted(with: progress) { return nil }
        if isCountMode {
            guard let s = secondsLeft(progress), s > 0 else { return nil }
            return zikrEstimateString(s)
        }
        return countsAtGoal(progress).map { "~\($0) counts" }
    }
}

/// "~4 min", "~1h 10m", "<1 min" — an estimate, so rounded up to whole minutes.
func zikrEstimateString(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "<1 min" }
    let minutes = Int((seconds / 60).rounded(.up))
    if minutes < 60 { return "~\(minutes) min" }
    return "~\(minutes / 60)h \(minutes % 60)m"
}

/// "1h 05m", "12m 03s" or "45s".
func zikrDurationString(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    if m > 0 { return String(format: "%dm %02ds", m, sec) }
    return "\(sec)s"
}

// MARK: - Quick add

/// The tasbeeh's quick-add step: a "+N" button in a running session that counts N in one tap
/// (Durood +5, Bismillah +20…); 0 = no button. Each mantra keeps its own on the row
/// (`MantraModel.quickAddStep`); sessions without a mantra have no row, so theirs is a setting.
enum QuickAddSteps {
    static let range = 0...500
    /// Sessions with no mantra.
    static let noMantraKey = "quickAddStepNoMantra"
    /// Before schema 2.1.0 the steps lived here as "uuid:5,uuid:20,none:3" (a day, 2026-09-25),
    /// and before that as one global Settings value, `tasbeehSecondaryStep`.
    private static let legacyKey = "mantraQuickAddSteps"

    static func step(for mantra: MantraModel?) -> Int {
        mantra?.quickAddStep ?? UserDefaults.standard.integer(forKey: noMantraKey)
    }

    /// Carries the UserDefaults steps onto the rows once, then drops the old key. Run by the
    /// app's data pass (standard defaults are the app's own, so never from the widget).
    @discardableResult
    static func moveLegacySteps(into mantras: [MantraModel]) -> Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: noMantraKey) == nil {
            defaults.set(defaults.integer(forKey: "tasbeehSecondaryStep"), forKey: noMantraKey)
        }
        guard let raw = defaults.string(forKey: legacyKey), !raw.isEmpty else { return 0 }
        var moved = 0
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            if parts[0] == "none" {
                defaults.set(n, forKey: noMantraKey)
            } else if let mantra = mantras.first(where: { $0.id.uuidString == parts[0] }) {
                mantra.quickAddStep = n
                moved += 1
            }
        }
        defaults.removeObject(forKey: legacyKey)
        return moved
    }
}
