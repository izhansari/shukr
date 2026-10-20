//
//  StreakWalk.swift
//  shukr
//
//  The streak count, one rule for every walker (cleanup-map tangle 2, step 5).
//

import Foundation

/// How a run of days becomes a streak, kept in one place: a day that counts adds one, an excused day (`.skip`) neither adds
/// nor breaks, and a day that breaks ends the run — except today, which never breaks it (it may still count later).
/// Each walker says what each of its days is and feeds them here: the Salah page's rows through `Excused.streakDay`
/// (`refreshStreaksFromHistory`, `bestRun`), Your journey's log through `YourJourneyStats.verdict`. The goal and the
/// excused days live in those verdicts; the fresh start is where a walker begins (or stops).
enum StreakWalk {
    /// Oldest first, up to today: the run going now (today in it once it counts), the best run and its first and last day
    /// (the latest of equal ones).
    struct Forward {
        let today: Date
        private(set) var run = 0
        private(set) var best = 0
        private(set) var bestDays: ClosedRange<Date>?
        private var runStart: Date?

        init(today: Date) { self.today = today }

        mutating func add(_ day: Date, _ verdict: Excused.StreakDay) {
            switch verdict {
            case .counts:
                if run == 0 { runStart = day }
                run += 1
                if run >= best, let start = runStart { best = run; bestDays = start...day }
            case .skip: break
            case .breaks: if day != today { run = 0 }
            }
        }
    }

    /// Newest first, from yesterday back: the run that ends yesterday. Over at the first day that breaks (`alive` false),
    /// so a walker can stop reading days.
    struct Backward {
        private(set) var run = 0
        private(set) var alive = true

        mutating func add(_ verdict: Excused.StreakDay) {
            guard alive else { return }
            switch verdict {
            case .counts: run += 1
            case .skip: break
            case .breaks: alive = false
            }
        }
    }
}
