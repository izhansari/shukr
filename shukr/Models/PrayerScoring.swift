//
//  PrayerScoring.swift
//  shukr
//
//  The one prayer-scoring rule. Everything that scores a prayer goes through here: marking it
//  in the app, the widget's checkmark, the notification's "I already prayed", editing the
//  time, and the one-time recalculation of old rows. Compiled into the app and the widget
//  (Models/ is in both targets).
//
//  A prayer's `numberScore` is its points out of 100, stored as 0...1:
//    Early    marked within 30 min of the adhan            100
//    On time  rest of the window, first half                99 → 80
//    Late     rest of the window, second half               79 → 60
//    Qaza     marked after the window closed                40
//    Missed   never marked                                  0 (numberScore stays nil)
//  After the first 30 minutes the points slide evenly from 100 to 60 at the window's end, so
//  there's no cliff inside the window; the only drop is 60 → 40 when it closes. Qaza still
//  counts because the app is meant to motivate — praying late beats not praying.
//  The day score is the average of the five (unmarked = 0).
//
//  Until 2026-09-24 `numberScore` was the fraction of the window left at the tap (0 = Qaza) and
//  the day score reshaped it (first quarter = 100%, then 65–90%, Qaza 65%).
//  `recalculateHistoryIfNeeded` converts old rows once.
//

import Foundation
import SwiftUI
import SwiftData

enum PrayerScoring {
    static let earlyWindow: TimeInterval = 30 * 60
    static let inWindowFloor = 0.6
    static let qaza = 0.4

    enum Grade: String {
        case early = "Early", onTime = "On time", late = "Late", qaza = "Qaza"
    }

    /// Points (0...1) for a prayer whose window is `start...end`, marked at `markedAt`.
    static func score(start: Date, end: Date, markedAt: Date) -> Double {
        if markedAt > end { return qaza }
        let elapsed = markedAt.timeIntervalSince(start)
        if elapsed <= earlyWindow { return 1 }
        let rest = end.timeIntervalSince(start) - earlyWindow
        guard rest > 0 else { return 1 }
        let fractionOfRestLeft = min(max(end.timeIntervalSince(markedAt) / rest, 0), 1)
        return inWindowFloor + (1 - inWindowFloor) * fractionOfRestLeft
    }

    static func grade(for score: Double) -> Grade {
        if score >= 0.9999 { return .early }
        if score >= 0.8 { return .onTime }
        if score >= inWindowFloor - 0.0001 { return .late }
        return .qaza
    }

    /// "On time · 88"
    static func summary(for score: Double) -> String {
        "\(grade(for: score).rawValue) · \(Int((score * 100).rounded()))"
    }

    static func color(for score: Double?) -> Color {
        guard let score else { return .gray }
        switch grade(for: score) {
        case .early: return .green
        case .onTime: return .yellow
        case .late: return .red
        case .qaza: return .gray
        }
    }

    // MARK: - One-time recalculation of rows scored by the old rule

    static let recalculatedKey = "prayerScoringV2Recalculated"

    /// Rescores every completed prayer with the current rule, moves old Isha rows to the 11:59 PM
    /// end, and rewrites every day's average. Run once by the app at launch (flag in the app
    /// group); a failure leaves the flag unset so the next launch retries.
    /// Rows without a saved tap time get one back from their old score (old score = fraction of
    /// the window left, so tap = end − score × window); an old 0 was a Qaza.
    static func recalculateHistoryIfNeeded(in container: ModelContainer) {
        let defaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        guard defaults?.bool(forKey: recalculatedKey) != true else { return }
        backUpStore(label: "before-scoring-v2")
        let context = ModelContext(container)
        do {
            let prayers = try context.fetch(FetchDescriptor<PrayerModel>())
            var rescored = 0, ishaMoved = 0
            for prayer in prayers {
                let oldEnd = prayer.endTime
                if prayer.name == "Isha" {
                    let newEnd = PrayerDay.ishaEnd(on: prayer.startTime, ishaStart: prayer.startTime, nextFajr: nil)
                    if newEnd != prayer.endTime { prayer.endTime = newEnd; ishaMoved += 1 }
                }
                guard prayer.isCompleted else { continue }
                let markedAt: Date
                if let tapped = prayer.timeAtComplete {
                    markedAt = tapped
                } else if let old = prayer.numberScore {
                    let window = oldEnd.timeIntervalSince(prayer.startTime)
                    markedAt = old <= 0 ? oldEnd.addingTimeInterval(1) : oldEnd.addingTimeInterval(-old * window)
                } else {
                    continue
                }
                let newScore = score(start: prayer.startTime, end: prayer.endTime, markedAt: markedAt)
                prayer.numberScore = newScore
                prayer.englishScore = grade(for: newScore).rawValue
                rescored += 1
            }

            // Day averages: every day that has prayer rows or a stored score.
            let calendar = Calendar.current
            var byDay: [Date: [PrayerModel]] = [:]
            for prayer in prayers { byDay[calendar.startOfDay(for: prayer.startTime), default: []].append(prayer) }
            let dailies = try context.fetch(FetchDescriptor<DailyPrayerScore>())
            var dailyByDay: [Date: DailyPrayerScore] = [:]
            for daily in dailies { dailyByDay[calendar.startOfDay(for: daily.date)] = daily }
            for (day, rows) in byDay {
                let average = dayScore(for: rows)
                if let daily = dailyByDay[day] {
                    daily.averageScore = average
                } else {
                    let daily = DailyPrayerScore(date: day)
                    daily.averageScore = average
                    context.insert(daily)
                }
            }
            try context.save()
            defaults?.set(true, forKey: recalculatedKey)
            print("✅ scoring V2 recalculation: rescored=\(rescored) isha moved=\(ishaMoved) days=\(byDay.count)")
        } catch {
            print("❌ scoring V2 recalculation failed: \(error.localizedDescription)")
        }
    }

    /// Copies the shared store (+ -wal / -shm) to `<app group>/Library/Backups/` before a
    /// rewrite of old rows. Library is where `devicectl device copy from` can reach it (the store
    /// itself sits at the group root, which it can't). Runs at launch before anything writes.
    static func backUpStore(label: String) {
        let fm = FileManager.default
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget") else { return }
        let dir = group.appending(path: "Library/Backups")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = group.appending(path: "shukr.store" + suffix)
            let to = dir.appending(path: "shukr.store.\(label)" + suffix)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            do { try fm.copyItem(at: from, to: to) } catch { print("⚠️ store backup \(suffix): \(error.localizedDescription)") }
        }
    }

    /// Average of the five prayers' points; unmarked (or missing) prayers count 0.
    static func dayScore(for prayers: [PrayerModel]) -> Double {
        let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let total = names.reduce(0.0) { sum, name in
            guard let prayer = prayers.first(where: { $0.name == name }), prayer.isCompleted else { return sum }
            return sum + (prayer.numberScore ?? 0)
        }
        return total / Double(names.count)
    }
}
