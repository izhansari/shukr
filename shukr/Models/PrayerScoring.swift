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
//    Opening  the first third of its window                100
//    Middle   the second third                              99 → 80
//    Closing  the last third                                79 → 60
//    Qaza     marked after the window closed                40
//  Thirds since 2026-10-20 (prayer-metrics rethink, board/scoring-rethink/plan-v3.md; owner: "Opening = the first third of
//  the window."): a fixed 30 minutes was 31–46 % of Fajr's and Maghrib's window but 10–19 % of Dhuhr's, so the same habit
//  graded differently by prayer and season. Opening was Perfect until then (owner: "i dont like the word early … we
//  could maybe do 'Opening'"), Early until 2026-09-26. The points no longer show on screen once phase 3 lands; they
//  still order and shade.
//  Middle / Closing were "On time" / "Late" until 2026-10-17 (owner: users read "on time" as just being inside the
//  window and "late" as prayed outside it). Old rows' `englishScore` keeps whichever word was current; the UI reads
//  `gradeWord`, never the stored string.
//    Missed   never marked                                  0 (numberScore stays nil)
//  After the first third the points slide evenly from 100 to 60 at the window's end (80 at two thirds), so
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
    /// The Opening's share of a window: the first third (Middle the second, Closing the last).
    static let openingShare = 1.0 / 3
    static let inWindowFloor = 0.6
    static let qaza = 0.4

    /// The one place the grade words live: every screen, the setup legend, Siri and the watch's copy read them from here.
    /// (Case names keep their old meaning — `.onTime` is Middle, `.late` is Closing — so saved keys never change.)
    enum Grade: String, CaseIterable {
        case perfect = "Opening", onTime = "Middle", late = "Closing", qaza = "Qaza"

        /// Spoken after "Asr marked as prayed …" (Siri, VoiceOver): "during the Middle window" (owner: "user marked as
        /// prayed during the [score text descriptor] window" — one template, plug and play).
        var spokenWhen: String {
            self == .qaza ? "after its window, as Qaza" : "during the \(rawValue) window"
        }
        /// The highest number this grade may show: the grade is decided on the raw score but the number is rounded,
        /// so a 0.996 read "On time · 100" next to Perfect's 100.
        var shownCeiling: Int {
            switch self { case .perfect: 100; case .onTime: 99; case .late: 79; case .qaza: 40 }
        }
    }

    /// Points (0...1) for a prayer whose window is `start...end`, marked at `markedAt`.
    static func score(start: Date, end: Date, markedAt: Date) -> Double {
        if markedAt > end { return qaza }
        let window = end.timeIntervalSince(start)
        guard window > 0 else { return 1 }
        if markedAt.timeIntervalSince(start) <= window * openingShare { return 1 }
        let rest = window * (1 - openingShare)
        let fractionOfRestLeft = min(max(end.timeIntervalSince(markedAt) / rest, 0), 1)
        return inWindowFloor + (1 - inWindowFloor) * fractionOfRestLeft
    }

    static func grade(for score: Double) -> Grade {
        if score >= 0.9999 { return .perfect }
        if score >= 0.8 { return .onTime }
        if score >= inWindowFloor - 0.0001 { return .late }
        return .qaza
    }

    /// When a prayer's colour changes on the clock: Opening → Middle (a third in) and Middle → Closing (two thirds in).
    /// The Prayers widget adds a timeline entry at each (the watch has the same rule in `WatchScoring.gradeChanges`).
    static func gradeChanges(start: Date, end: Date) -> [Date] {
        let window = end.timeIntervalSince(start)
        guard window > 0 else { return [] }
        return [start.addingTimeInterval(window * openingShare), start.addingTimeInterval(window * 2 * openingShare)]
    }

    /// The number shown for a score, never above its grade's band ("Middle · 99", not "Middle · 100").
    static func points(for score: Double) -> Int {
        min(Int((score * 100).rounded()), grade(for: score).shownCeiling)
    }

    /// What a mark says where its grade is shown: the word alone, "Middle" (prayer-metrics phase 3: no 0–100 on any screen;
    /// was "Middle · 87"). `points` still orders and shades.
    static func summary(for score: Double) -> String {
        grade(for: score).rawValue
    }

    /// "Asr marked as prayed during the Closing window. Score: 66." — Siri's answer and the Live Activity's VoiceOver.
    static func spokenMark(_ name: String, score: Double) -> String {
        "\(name) marked as prayed \(grade(for: score).spokenWhen)."   // no "Score: N" (prayer-metrics phase 3)
    }

    /// Closing's colour, #C93B10 in both looks (owner, 2026-10-20: "both C93B10"; was system red): a red leaning orange.
    static let closing = Color(red: 0xC9 / 255.0, green: 0x3B / 255.0, blue: 0x10 / 255.0)

    static func color(for score: Double?) -> Color {
        guard let score else { return .gray }
        switch grade(for: score) {
        case .perfect: return .green
        case .onTime: return .yellow
        case .late: return closing
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
                // A no-time mark has no clock to rescore from: it stays in its time (MarkKind, phase 6).
                if prayer.timeUnknown { continue }
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
            for prayer in prayers { byDay[prayer.dayStart, default: []].append(prayer) }   // 2.8.0: by prayer day
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

    // MARK: - One-time regrade to thirds (prayer-metrics rethink, phase 2)

    static let thirdsKey = "prayerScoringV3Thirds"

    /// Regrades every timed mark by the thirds rule (Opening = the first third) and rewrites every day's average, once,
    /// after a store backup ("before-thirds"). Jumu'ah keeps its 100; a mark with no saved tap time keeps its score (it
    /// can't be placed in its window). A failure leaves the flag unset so the next launch retries. Before 2026-10-20 the
    /// Opening (Perfect) was the first 30 minutes of every window.
    static func regradeToThirdsIfNeeded(in container: ModelContainer) {
        let defaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        guard defaults?.bool(forKey: thirdsKey) != true else { return }
        backUpStore(label: "before-thirds")
        let context = ModelContext(container)
        do {
            let prayers = try context.fetch(FetchDescriptor<PrayerModel>())
            var regraded = 0, moved = 0
            // A no-time mark (MarkKind.timeUnknown) has no clock to regrade from: it stays in its time.
            for prayer in prayers where prayer.isCompleted && !prayer.isJumuah && !prayer.timeUnknown {
                guard let markedAt = prayer.timeAtComplete else { continue }
                let new = score(start: prayer.startTime, end: prayer.endTime, markedAt: markedAt)
                if let old = prayer.numberScore, grade(for: old) != grade(for: new) { moved += 1 }
                prayer.numberScore = new
                prayer.englishScore = grade(for: new).rawValue
                regraded += 1
            }
            try rewriteDayAverages(prayers, in: context)
            try context.save()
            defaults?.set(true, forKey: thirdsKey)
            print("✅ scoring V3 (thirds) regrade: regraded=\(regraded) changed grade=\(moved)")
        } catch {
            print("❌ scoring V3 (thirds) regrade failed: \(error.localizedDescription)")
        }
    }

    /// The stored day averages (DailyPrayerScore, read only by Your Data's export) that have one, from their rows by prayer
    /// day. A day whose average is nil stays nil (Excused clears an excused day's: `clearDailyScore`), and none is added.
    private static func rewriteDayAverages(_ prayers: [PrayerModel], in context: ModelContext) throws {
        let calendar = Calendar.current
        var byDay: [Date: [PrayerModel]] = [:]
        for prayer in prayers { byDay[prayer.dayStart, default: []].append(prayer) }
        for daily in try context.fetch(FetchDescriptor<DailyPrayerScore>()) where daily.averageScore != nil {
            guard let rows = byDay[calendar.startOfDay(for: daily.date)] else { continue }
            daily.averageScore = dayScore(for: rows)
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
        // External-storage blobs (zikr photos / voice memos, schema 2.5.0) live beside the store
        // in .shukr_SUPPORT/_EXTERNAL_DATA; the rows only point at them. Kept visible here — to
        // restore, put it back next to the store as ".shukr_SUPPORT".
        let support = group.appending(path: ".shukr_SUPPORT")
        let supportCopy = dir.appending(path: "shukr_SUPPORT.\(label)")
        if fm.fileExists(atPath: support.path), !fm.fileExists(atPath: supportCopy.path) {
            do { try fm.copyItem(at: support, to: supportCopy) } catch { print("⚠️ store backup (media): \(error.localizedDescription)") }
        }
    }

    /// Average of the five prayers' points; unmarked (or missing) prayers count 0.
    static func dayScore(for prayers: [PrayerModel]) -> Double {
        let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let total = names.reduce(0.0) { sum, name in
            // A completed row wins over an unmarked twin (audit B4: `.first` could land on the unmarked one).
            guard let prayer = prayers.first(where: { $0.name == name && $0.isCompleted }) else { return sum }
            return sum + (prayer.numberScore ?? 0)
        }
        return total / Double(names.count)
    }
}
