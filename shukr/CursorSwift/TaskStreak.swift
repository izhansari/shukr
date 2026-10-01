//
//  TaskStreak.swift
//  shukr
//
//  A task's streak (owner, 2026-10-01; decisions task-streak-rule A, task-streak-miss A, task-streak-look C,
//  task-streak-results A): a prayer day counts when that day's sessions of the task met the goal they ran
//  with; a missed day starts it again and the best is kept. Computed from the task's own sessions — no
//  stored state, nothing in the schema. Sessions carry their task only since 4980db3 (2026-09-23), so
//  streaks start from there.
//

import SwiftUI
import SwiftData
import UIKit

struct TaskStreak: Equatable {
    /// Days in a row: today counts once it's done; until then, the run up to yesterday (still to keep).
    var current = 0
    var best = 0
    var keptToday = false
}

extension TaskModel {
    func streak(now: Date = Date()) -> TaskStreak {
        // Each prayer day (Fajr to Fajr, like "today's progress"): did its sessions meet the goal?
        var byDay: [Date: [SessionDataModel]] = [:]
        for s in sessions { byDay[PrayerDay.start(for: s.startTime), default: []].append(s) }
        let met = Set(byDay.compactMap { day, list in Self.metGoal(list, task: self) ? day : nil })
        guard !met.isEmpty else { return TaskStreak() }

        let cal = Calendar.current
        func before(_ d: Date) -> Date { cal.date(byAdding: .day, value: -1, to: d) ?? d.addingTimeInterval(-86_400) }
        let today = PrayerDay.start(for: now)
        let keptToday = met.contains(today)
        var current = 0
        var day = keptToday ? today : before(today)
        while met.contains(day) { current += 1; day = before(day) }

        var best = 0, run = 0
        var last: Date?
        for d in met.sorted() {
            run = last.map { cal.isDate(before(d), inSameDayAs: $0) } == true ? run + 1 : 1
            best = max(best, run)
            last = d
        }
        return TaskStreak(current: current, best: max(best, current), keptToday: keptToday)
    }

    /// One day's sessions against the goal they ran with (a task session takes the task's goal as its
    /// target when it starts), so changing a task's goal never rewrites its past days. The day's newest
    /// session decides count or minutes; a session with no target falls back to the task's goal today.
    private static func metGoal(_ list: [SessionDataModel], task: TaskModel) -> Bool {
        guard let newest = list.max(by: { $0.startTime < $1.startTime }) else { return false }
        let countMode = newest.sessionMode == 2 ? true : newest.sessionMode == 1 ? false : task.isCountMode
        if countMode {
            let goal = newest.targetCount > 0 ? newest.targetCount : task.goal
            return list.reduce(0) { $0 + $1.totalCount } >= goal
        }
        let minutes = newest.targetMin > 0 ? newest.targetMin : task.goal
        return list.reduce(0) { $0 + $1.secondsPassed } >= Double(minutes) * 60
    }
}

#if DEBUG
/// `-demoStreakHero 7,21` (current,best): the results screen's streak moment alone, on the results'
/// colour, from a cold launch (looks only; the real one needs a session that finishes a goal).
struct StreakHeroDemo: View {
    static var streak: TaskStreak? {
        guard let raw = UserDefaults.standard.string(forKey: "demoStreakHero") else { return nil }
        let n = raw.split(separator: ",").compactMap { Int($0) }
        guard let c = n.first else { return nil }
        return TaskStreak(current: c, best: max(n.count > 1 ? n[1] : c, c), keptToday: true)
    }
    let streak: TaskStreak
    var body: some View {
        ZStack {
            Color("pauseColor").ignoresSafeArea()
            StreakResultsHero(streak: streak).offset(y: -120)
        }
    }
}

enum TaskStreakDebug {
    /// `-logTaskStreaks YES`: every task's streak and the days that counted, in the console.
    static func log(_ tasks: [TaskModel]) {
        guard UserDefaults.standard.bool(forKey: "logTaskStreaks") else { return }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        for t in tasks {
            let st = t.streak()
            var days: [Date: (Int, Double)] = [:]
            for s in t.sessions { let d = PrayerDay.start(for: s.startTime); days[d, default: (0, 0)].0 += s.totalCount; days[d, default: (0, 0)].1 += s.secondsPassed }
            let list = days.keys.sorted().map { "\(f.string(from: $0)) \(days[$0]!.0)c/\(Int(days[$0]!.1))s" }.joined(separator: ", ")
            print("🔥 \(t.title) goal \(t.goal)\(t.isCountMode ? "c" : "min"): current \(st.current) best \(st.best) keptToday \(st.keptToday) | \(list)")
        }
    }
}
#endif

/// A task's streak beside it: the flame filled in sage once today's goal is met, an outline in grey
/// while today is still to do.
struct TaskStreakBadge: View {
    let streak: TaskStreak

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: streak.keptToday ? "flame.fill" : "flame")
                .font(.system(size: 12, weight: .semibold))
            Text("\(streak.current)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(streak.keptToday ? Color.sage : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.current) day streak\(streak.keptToday ? "" : ", not done today")")
    }
}

/// The task the Zikr page's wheel has centred (nil: freestyle / New task), for the top bar's title.
/// Its own object so only the title redraws when the wheel turns.
@Observable final class ZikrWheelFocus {
    static let shared = ZikrWheelFocus()
    var taskID: UUID?
}

/// The results screen's top after the session that finished a task's goal for the day (decision
/// task-streak-results A, owner: "show the flame, then back to checkmark"): the flame pops into the ✓'s
/// spot, the streak ticks up to today's, holds, then turns into the ✓ and "saved to your history"; a small
/// sage streak line stays under it.
struct StreakResultsHero: View {
    let streak: TaskStreak
    /// Under sleep mode: no buzz (a sleeper's phone stays still).
    var quiet = false
    @State private var shown = false
    @State private var days: Int
    @State private var settled = false

    init(streak: TaskStreak, quiet: Bool = false) {
        self.streak = streak
        self.quiet = quiet
        _days = State(initialValue: max(streak.current - 1, 0))
    }

    private var isNew: Bool { streak.current <= 1 }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: settled ? "checkmark" : "flame.fill")
                .font(.system(size: settled ? 22 : 26, weight: .medium))
                .foregroundStyle(Color.sage)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.sage.opacity(0.16)))
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
            ZStack {
                if settled {
                    Text("saved to your history")
                        .font(.system(size: 17, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .transition(.blurReplace)
                } else {
                    // The same type as "saved to your history" that follows (owner): only the words change.
                    Text(isNew ? "A new streak" : "\(days) days in a row")
                        .font(.system(size: 17, weight: .light, design: .rounded))
                        .contentTransition(.numericText(value: Double(days)))
                        .transition(.blurReplace)
                }
            }
            .frame(height: 24)
            Group {
                if settled {
                    Label(isNew ? "Day 1" : "\(streak.current) days in a row", systemImage: "flame.fill")
                        .foregroundStyle(Color.sage)
                } else if streak.best > streak.current {
                    Text("\(streak.best) days is your best").foregroundStyle(.secondary)
                } else if !isNew {
                    Text("This is your best").foregroundStyle(Color.sage)
                } else {
                    Text(" ")
                }
            }
            .font(.footnote)
            .id(settled)
            .transition(.opacity)
            .opacity(settled || isNew || days == streak.current ? 1 : 0)   // about the new number: after the tick
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true }
            try? await Task.sleep(for: .milliseconds(650))
            if !isNew { withAnimation(.snappy) { days = streak.current } }
            if !quiet { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            try? await Task.sleep(for: .milliseconds(1900))
            withAnimation(.smooth(duration: 0.5)) { settled = true }
        }
    }
}
