//
//  PrayerViewModel+DayScore.swift
//  shukr
//
//  The day score: one DailyPrayerScore row a day, the average of the five prayers' points (PrayerScoring).
//  Moved out of PrayerViewModel.swift (cleanup-map tangle 2, step 2).
//

import SwiftUI
import SwiftData

extension PrayerViewModel {

    /// `date`: any time on the prayer day's calendar date — a row's `dayStart`, never its `startTime` (an Isha after
    /// midnight belongs to the day before: mark audit #1). `fromStore`: score from the store's rows even for today (the
    /// one-time repair runs before today's list may be loaded — Bradley's review).
    func calculateDayScore(for date: Date, fromStore: Bool = false) {
        let today = PrayerDay.date()
        let updatingToday = Calendar.current.isDate(date, inSameDayAs: today)
        // During the tour `todaysPrayers` is its practice day: today is scored from the store's real rows, never the
        // practice ones (Bradley's review: a mid-tour widget / banner mark saved the practice score as today's).
        let practiceShown = TourRuntime.practiceMirror != nil
        let objectsToCheck: [PrayerModel] = updatingToday && !practiceShown && !fromStore ? todaysPrayers : loadPrayerObjects(for: date)
        // An excused day not prayed in full has no score (Excused.swift): the charts leave it out rather than show it low.
        if Set(objectsToCheck.filter(\.isCompleted).map(\.name)).count < 5, Excused.Days().excludes(Calendar.current.startOfDay(for: date)) {   // `date` is on the prayer day's own date; PrayerDay.start(for:) read a midnight as the day before
            if updatingToday { todaysScore = 0 }
            clearDailyScore(for: date)
            return
        }
        // Average of the five prayers' points, unmarked = 0 (PrayerScoring).
        let dayScore = PrayerScoring.dayScore(for: objectsToCheck)
        if updatingToday { todaysScore = dayScore }
        saveDailyScore(for: date, score: dayScore)

    }
    
    
    /// An excused day's saved score, cleared (nil: the charts skip it).
    func clearDailyScore(for date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyPrayerScore>(predicate: #Predicate<DailyPrayerScore> { $0.date >= startOfDay && $0.date <= startOfDay })
        guard let records = try? context.fetch(descriptor), records.contains(where: { $0.averageScore != nil }) else { return }
        for r in records { r.averageScore = nil }
        if !batchingScores { try? context.save() }
    }

    /// After Excused changes: the last 60 days' scores (a removed mistaken start gives its day's score back) and the
    /// streaks, recounted.
    @MainActor func excusedChanged() {
        let cal = Calendar.current
        let today = PrayerDay.start(for: Date())
        batchingScores = true
        for back in 0..<60 {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { break }
            calculateDayScore(for: day.addingTimeInterval(12 * 3600), fromStore: true)
        }
        batchingScores = false
        if context.hasChanges { try? context.save() }
        DayHistory.invalidate()
        calculatePrayerStreak()
        pushCompletionsToWidget()
        objectWillChange.send()
    }

    // Add this method to PrayerViewModel to save a daily score to SwiftData
    func saveDailyScore(for date: Date, score: Double) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-1)
        
        // Check if a record for this date already exists
        let fetchDescriptor = FetchDescriptor<DailyPrayerScore>(
            predicate: #Predicate<DailyPrayerScore> {
                $0.date >= startOfDay && $0.date <= startOfDay
            }
        )
        
        do {
            let existingRecords = try context.fetch(fetchDescriptor)
            
            if let existingRecord = existingRecords.first {
                guard existingRecord.averageScore != score else { return }   // unchanged: nothing to write
                // Update existing record
                existingRecord.averageScore = score
                // We could also update individual prayer scores here if needed
            } else {
                // Create new record
                let newDailyScore = DailyPrayerScore(date: startOfDay)
                newDailyScore.averageScore = score
                context.insert(newDailyScore)
            }
            
            if !batchingScores { try context.save() }
        } catch {
            print("❌ Error saving daily prayer score: \(error.localizedDescription)")
        }
    }
}
