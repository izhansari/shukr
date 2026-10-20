//
//  JourneyStore.swift
//  shukr
//
//  Journey's numbers in one place (cleanup-map tangle 4, step 4; owner, 2026-10-20: "I think it's better we have a cleaner
//  data model so that whatever we build afterwards has a good base and foundation"). Was five loose statics — JourneyLog.last,
//  PrayerScores.last / lastBySpan, JourneyMakeUpPage.last, JourneyLens.shared — each with its own writer and its own idea of
//  stale (the goal audit's findings 5, 8, 12). Now one observable owner: one loader, one "something changed" flag, and any
//  page that shows Journey's numbers reads them here.
//

import SwiftUI
import SwiftData

@MainActor @Observable final class JourneyStore {
    static let shared = JourneyStore()

    // MARK: What it holds

    /// The last log read (JourneyLog.load), nil until the first read since launch. Readers: Journey's page and card, the
    /// month / year flights, the map sheet's day header ("Day N").
    private(set) var log: JourneyLog?
    /// Your journey's numbers for that log (the card, Milestones).
    private(set) var stats: YourJourneyStats?
    /// The header's ring: since the fresh start, and over every day while one is on (the ⇄ picks).
    private(set) var headerScores: (score: Int?, strongest: String?)?
    private(set) var lifetimeHeaderScores: (score: Int?, strongest: String?)?
    /// To make up's row on Journey: every unmarked prayer on a day shukr was used.
    private(set) var makeUpTotal: Int?
    /// Prayer scores' builds, one per span (`.all` is also written by Journey's load, so Prayer scores opens on it at once).
    var scoresBySpan: [PrayerScores.Span: PrayerScores] = [:]
    /// To make up's last read (the page opens on it while a fresh one is read).
    var makeUp: (open: [JourneyMakeUpPage.Entry], madeUp: [JourneyMakeUpPage.Entry])?
    /// After a fresh start, which way the card counts: from it (false, the default each launch) or over every day.
    var lifetime = false

    /// A mark, an unmark, an outside mark or an Excused change since the last read landed: the next reader reads again.
    var stale: Bool { changes != readAt }

    // MARK: Bookkeeping

    @ObservationIgnored private var changes = 0
    @ObservationIgnored private var readAt = -1
    @ObservationIgnored private var loadToken = 0

    private init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.journeyChanged, SharedStore.markedElsewhere, Excused.changed] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changes += 1 }
            }
        }
        // The goal or the fresh start changed: what's kept was counted the old way, and the card goes back to "since the
        // fresh start". (The .journeyChanged posted right after reloads, once — audit #9.)
        center.addObserver(forName: PrayerStats.rulesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lifetime = false
                self?.scoresBySpan = [:]
                self?.changes += 1
            }
        }
    }

    /// The one loader: the log, the card's numbers, the header ring and To make up's count, all read off the main thread from
    /// one moment, landing together and never mid-flight (`JourneyFlights.whenIdle`). A newer call drops an older result.
    func load(container: ModelContainer, today: Date) {
        loadToken += 1
        let token = loadToken
        let at = changes
        let ranges = Excused.ranges
        Task {
            let t = JourneyPerf.now, now = Date()   // one moment for all three (a Fajr turn mid-load can't split them)
            let built = await JourneyLog.load(container: container, ranges: ranges, now: now)
            JourneyPerf.took("log.load", since: t)
            guard token == loadToken else { return }
            // The card's numbers off the main thread too (42 ms on main on his 13 Pro Max per reload, a goal flip's worst
            // frame — journey-perf.log, 2026-10-18), alongside the scores. The excused days from the ranges read on main
            // (Excused.ranges' cache isn't safe off it).
            let t2 = JourneyPerf.now
            let statsTask = Task.detached(priority: .userInitiated) {
                YourJourneyStats(log: built, today: today, excused: Excused.Days(ranges))
            }
            let scoresTask = Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                // At the log's own goal and fresh start (the header ring then reads since it, as Prayer scores does).
                let s = PrayerScores.build(log: built, context: context, now: now, countsFrom: built.countsFrom, goal: built.goal)
                let all = built.countsFrom == nil ? nil : PrayerScores.build(log: built, context: context, now: now, countsFrom: nil, goal: built.goal)
                return (s, all, JourneyMakeUpPage.entries(in: context, ranges: ranges, now: now).open.count)
            }
            let builtStats = await statsTask.value
            JourneyPerf.took("stats.load", since: t2)
            guard token == loadToken else { return }
            JourneyFlights.whenIdle {
                guard token == self.loadToken else { return }
                self.log = built
                self.stats = builtStats
                self.readAt = at
            }
            let (s, all, open) = await scoresTask.value
            JourneyPerf.took("scores+makeUp.load", since: t2)
            guard token == loadToken else { return }
            JourneyFlights.whenIdle {
                guard token == self.loadToken else { return }
                self.headerScores = (s.prayedScore, s.prayed > 0 ? s.ranked.first : nil)
                self.lifetimeHeaderScores = all.map { ($0.prayedScore, $0.prayed > 0 ? $0.ranked.first : nil) }
                self.makeUpTotal = open
                self.scoresBySpan[.all] = s
            }
        }
    }

    /// Read only when there's nothing yet or something changed since (the map sheet's day header, a reopen of Journey).
    func loadIfNeeded(container: ModelContainer, today: Date) {
        guard log == nil || stale else { return }
        load(container: container, today: today)
    }

    /// The card's numbers before the first read lands (worked out on the main thread from what's there, as the page did).
    func fillStats(today: Date) {
        guard stats == nil else { return }
        stats = JourneyPerf.time("stats") { YourJourneyStats(log: log ?? JourneyLog(), today: today) }
    }
}
