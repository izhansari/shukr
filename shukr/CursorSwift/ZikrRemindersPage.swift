//
//  ZikrRemindersPage.swift
//  shukr
//
//  Every zikr task reminder in one place (owner, 2026-09-29, ideas #27: "a new button on the Zikr
//  page … like an alarm … we see all the zikr reminders there and we can edit them or delete them").
//  The bell sits in the Zikr page's top-right slot (Reorder takes it while arranging); the page lists
//  each reminder with when it goes off and the next time, soonest first; a tap edits it in the task
//  sheet's own `TaskReminderSheet`, a swipe removes the reminder (never the task). Tasks without one
//  are listed quietly below ("+ Add"), a tap to add one.
//

import SwiftUI
import SwiftData

/// The Zikr page's bell, the History & Azkar button's size and style (no count — owner: "just bell").
struct ZikrRemindersButton: View {
    @State private var showPage = false

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            showPage = true
        } label: {
            Image(systemName: "bell")
                .frame(width: 24, height: 24)
                .font(.system(size: 19))
                .fontWeight(.light)
                .foregroundColor(.gray.opacity(0.8))
                .padding()
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Zikr reminders")
        .sheet(isPresented: $showPage) { ZikrRemindersView() }
        #if DEBUG
        // `-demoZikrReminders` (with -demoZikrPage): open the page (simulator screenshots).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoZikrReminders") else { return }
            try? await Task.sleep(for: .seconds(2.5))
            showPage = true
        }
        #endif
    }
}

/// Every task's reminder: what, when, and the next time it goes off.
struct ZikrRemindersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @State private var editing: TaskModel?
    /// Recomputed on appear and after every change (the next times need today's sessions).
    @State private var sessions: [SessionDataModel] = []

    private var withReminder: [(task: TaskModel, next: Date?)] {
        tasks.filter { $0.reminderKind != nil }
            .map { ($0, ZikrReminders.nextFire($0, sessions: sessions)) }
            .sorted { a, b in
                switch (a.next, b.next) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.task.sortOrder < b.task.sortOrder
                }
            }
    }
    private var withoutReminder: [TaskModel] { tasks.filter { $0.reminderKind == nil } }

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    empty(title: "No zikr tasks yet",
                          line: "Make a task on the Zikr page (the dashed “New task” circle), then it can remind you.")
                } else {
                    if withReminder.isEmpty {
                        empty(title: "No reminders yet",
                              line: "Pick a task below to be reminded at a time, or around a prayer.")
                    } else {
                        Section {
                            ForEach(withReminder, id: \.task.id) { item in
                                Button { editing = item.task } label: { row(item.task, next: item.next) }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { remove(item.task) } label: {
                                            Label("Remove reminder", systemImage: "bell.slash")
                                        }
                                    }
                            }
                        } footer: {
                            Text("Soonest first. Swipe to remove a reminder; the task stays.")
                        }
                    }
                    if !withoutReminder.isEmpty {
                        Section("No reminder") {
                            ForEach(withoutReminder) { task in
                                Button { editing = task } label: { quietRow(task) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(.rounded)
            .navigationTitle("Zikr reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { task in
                TaskReminderSheet(draft: ReminderDraft(task), onCancel: { editing = nil }) { picked in
                    save(picked, to: task)
                    editing = nil
                }
            }
        }
        .onAppear { sessions = ZikrReminders.todaysSessions(context) }
        #if DEBUG
        // `-demoZikrRemindersSeed`: give the first three tasks a reminder each (simulator screenshots).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoZikrRemindersSeed"),
                  !tasks.contains(where: { $0.reminderKind != nil }) else { return }
            let seeds: [(String, Int?, String?, Int?, Int?)] = [
                ("prayer", nil, "Fajr", 10, nil), ("time", 21 * 60 + 30, nil, nil, 0b011_1110),
                ("prayer", nil, "Maghrib", -20, nil),
            ]
            for (task, seed) in zip(tasks, seeds) {
                task.reminderKind = seed.0
                task.reminderTimeMinutes = seed.1
                task.reminderPrayer = seed.2
                task.reminderOffsetMinutes = seed.3
                task.reminderWeekdays = seed.4
            }
            try? context.save()
        }
        #endif
    }

    // MARK: rows

    private func row(_ task: TaskModel, next: Date?) -> some View {
        HStack(spacing: 12) {
            icon(task)
            VStack(alignment: .leading, spacing: 2) {
                titleLine(task)
                Text(whenText(task))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            // Next: the day small on top ("today" / "tomorrow" / "wed"), the time under it.
            VStack(alignment: .trailing, spacing: 2) {
                Text(next.map(dayText) ?? "next")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(next.map { shortTimePM($0) } ?? "—")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(next == nil ? Color.secondary : Color.sage)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func quietRow(_ task: TaskModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.tertiary)
                .frame(width: 34, height: 34)
            titleLine(task).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.subheadline)
            .foregroundStyle(Color.sage)
            .fixedSize()
        }
        .contentShape(Rectangle())
    }

    /// The prayer's own symbol for a prayer reminder, a clock for a set time, on a sage disc.
    private func icon(_ task: TaskModel) -> some View {
        let symbol = task.reminderKind == "prayer" ? prayerSymbol(task.reminderPrayer ?? "") : "clock"
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.sage)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.sage.opacity(0.14)))
    }

    private func empty(title: String, line: String) -> some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.sage)
                Text(title).font(.headline)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    // MARK: wording

    /// "Astaghfirullah · 786 count" / "Subhanallah · 2 min" (owner): the name, then the goal, quieter;
    /// a long name gives way first.
    private func titleLine(_ task: TaskModel) -> some View {
        HStack(spacing: 5) {
            Text(task.title)
                .lineLimit(1)
                .layoutPriority(0)
            Text("· " + (task.isCountMode ? "\(task.goal) count" : "\(task.goal) min"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
                .layoutPriority(1)
        }
    }

    /// "Every day at 7:30 AM" · "Weekdays · 20 min before Maghrib" · "Mon, Wed · at Fajr".
    private func whenText(_ task: TaskModel) -> String {
        let days = ZikrReminders.weekdaysString(task.reminderWeekdays)
        if task.reminderKind == "prayer", let prayer = task.reminderPrayer {
            let m = task.reminderOffsetMinutes ?? 0
            let when = m == 0 ? "at \(prayer)" : "\(abs(m)) min \(m < 0 ? "before" : "after") \(prayer)"
            return days == "every day" ? "Every day · \(when)" : "\(days.prefix(1).uppercased() + days.dropFirst()) · \(when)"
        }
        let time = ZikrReminders.clockString(task.reminderTimeMinutes ?? 20 * 60)
        return days == "every day" ? "Every day at \(time)" : "\(days.prefix(1).uppercased() + days.dropFirst()) at \(time)"
    }

    /// The next time's day: "today" · "tomorrow" · "wed".
    private func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        return cal.shortWeekdaySymbols[cal.component(.weekday, from: date) - 1]
    }

    // MARK: changes (saved and rescheduled, like the task sheet)

    private func save(_ draft: ReminderDraft, to task: TaskModel) {
        withAnimation {
            draft.apply(to: task)
            try? context.save()
        }
        NotificationScheduler.reschedule(context: context, reason: "reminders page")
        sessions = ZikrReminders.todaysSessions(context)
    }

    private func remove(_ task: TaskModel) {
        var off = ReminderDraft(task)
        off.kind = nil
        save(off, to: task)
    }
}
