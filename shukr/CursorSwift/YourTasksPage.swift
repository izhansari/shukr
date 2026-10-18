//
//  YourTasksPage.swift
//  shukr
//
//  Your tasks (owner, 2026-09-29 as the Tasks sheet; a page since the Zikr tab reorganisation,
//  2026-10-01): every task in the wheel's order with today's progress, its reminder and streak; hold
//  and drag to reorder (the wheel follows), tap → the task's edit screen, swipe → delete (confirmed),
//  ＋ → a new task. Reached from "N of M tasks done" under the wheel.
//

import SwiftUI
import SwiftData


/// One task as a row (Your tasks, a zikr's page): today's ring or ✓, its name and goal, "40 of 100" /
/// "done", the reminder, the streak. On a zikr's page (`showsZikr` false) the zikr is the page's
/// own, so the row leads with the task's name or its goal.
struct TaskRow: View {
    let task: TaskModel
    let sessions: [SessionDataModel]
    var showsZikr = true
    var showsHandle = true

    var body: some View {
        let p = task.progress(in: sessions)
        let done = task.isCompleted(with: p)
        let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                        : p.seconds / Double(max(task.goal, 1) * 60)
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Circle().fill(Color.sage)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                // On a zikr's page the zikr is the page: its name, or "Every day". The goal and its unit are
                // on the line below ("0 of 100 count"; owner: not repeated after the name).
                Text(showsZikr ? task.title : (task.customName ?? "Every day")).lineLimit(1)
                Text(progressText(p, done: done))
                    .font(.subheadline)
                    .foregroundStyle(done ? Color.sage : Color.secondary)
                    .monospacedDigit()
                if task.reminderKind != nil {
                    // Sage, on a soft sage capsule (owner: tasks with a reminder obvious at a glance).
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill").font(.system(size: 9.5, weight: .semibold))
                        Text(reminderText).lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.sage)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.sage.opacity(0.14)))
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 4)
            let streak = task.streak()
            if streak.current > 0 { TaskStreakBadge(streak: streak) }
            if showsHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func progressText(_ p: TaskProgress, done: Bool) -> String {
        // No "today" (owner): everything here is today's.
        if done { return "done" }
        if task.isCountMode { return "\(p.count) of \(task.goal) count" }
        return "\(Int(p.seconds / 60)) of \(task.goal) min"
    }

    /// "Every day · 10 min after Fajr" / "Weekdays at 9:30 PM".
    private var reminderText: String {
        let days = ZikrReminders.weekdaysString(task.reminderWeekdays)
        let dayWord = days == "every day" ? "Every day" : days.prefix(1).uppercased() + days.dropFirst()
        if task.reminderKind == "prayer", let prayer = task.reminderPrayer {
            let m = task.reminderOffsetMinutes ?? 0
            let when = m == 0 ? "at \(prayer)" : "\(abs(m)) min \(m < 0 ? "before" : "after") \(prayer)"
            return "\(dayWord) · \(when)"
        }
        return "\(dayWord) at \(ZikrReminders.clockString(task.reminderTimeMinutes ?? 20 * 60))"
    }

}

/// A task's options on a hold, the same everywhere in the Zikr tab (owner: "hold = options, like every
/// row in the tab"): Start, Edit task, Open zikr (left out on the zikr's own page), Delete… (confirmed
/// by whoever shows it).
struct TaskMenu: View {
    let task: TaskModel
    var onStart: (() -> Void)? = nil
    let onEdit: () -> Void
    var onOpenZikr: (() -> Void)? = nil
    /// The wheel's: Your tasks, to drag them into order (owner: "add a reorder tasks option when long pressed").
    var onReorder: (() -> Void)? = nil
    let onDelete: () -> Void

    var body: some View {
        if let onStart { Button(action: onStart) { Label("Start", systemImage: "play.fill") } }
        Button(action: onEdit) { Label("Edit task", systemImage: "pencil") }
        // The zikr's page: its lifetime count, pace and sessions (owner: "change open zikr to instead say zikr stats").
        if let onOpenZikr, task.mantra != nil {
            Button(action: onOpenZikr) { Label("Zikr stats", systemImage: "chart.bar") }
        }
        if let onReorder {
            Button {
                // After the menu has gone: a page pushed while it closes can be refused.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.35))
                    onReorder()
                }
            } label: { Label("Reorder tasks", systemImage: "arrow.up.arrow.down") }
        }
        // Sends the task and its zikr whole (TaskSharing); not on the tour's example tasks.
        if TourExamples.shared.tasks == nil {
            Button {
                // After the menu has gone: a sheet presented while it closes can be refused.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.35))
                    TaskSharing.share(task)
                }
            } label: { Label("Share task…", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
    }
}
