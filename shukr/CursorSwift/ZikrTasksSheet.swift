//
//  ZikrTasksSheet.swift
//  shukr
//
//  The Zikr page's "Tasks" sheet (owner, 2026-09-29, ask zikr-tasks-sheet — replaces the wheel's
//  jiggle mode and the reminders page): every task in the wheel's order with today's progress and
//  its reminder; hold and drag to reorder (the wheel follows), tap → the task's edit screen pushed
//  inside the sheet, swipe → delete (confirmed), ＋ → a new task.
//

import SwiftUI
import SwiftData

/// The Zikr page's top-right button: opens the Tasks sheet.
struct ZikrTasksButton: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            showSheet = true
        } label: {
            Text("Tasks")
                .font(.subheadline.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.gray.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .padding()
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Zikr tasks")
        .sheet(isPresented: $showSheet) { ZikrTasksSheet() }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoZikrTasks") else { return }
            try? await Task.sleep(for: .seconds(2.5))
            showSheet = true
        }
        #endif
    }
}

struct ZikrTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @State private var sessions: [SessionDataModel] = []
    @State private var path: [TaskModel] = []
    @State private var toDelete: TaskModel?
    @State private var creating = false

    /// Opens straight onto `task`'s edit screen (a long-press on the wheel), so Back lands on the list.
    var startOn: TaskModel? = nil

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if tasks.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Color.sage)
                            Text("No zikr tasks yet").font(.headline)
                            Text("A task is a daily goal for a zikr — 33 Astaghfirullah, 10 minutes of Subhanallah.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    }
                } else {
                    Section {
                        ForEach(tasks) { task in
                            NavigationLink(value: task) { row(task) }
                                .confirmationDialog("Delete “\(task.title)”?",
                                                    isPresented: Binding(get: { toDelete == task }, set: { if !$0 { toDelete = nil } }),
                                                    titleVisibility: .visible) {
                                    Button("Delete Task", role: .destructive) {
                                        withAnimation { TaskModel.delete(task, in: context) }
                                        toDelete = nil
                                    }
                                    Button("Cancel", role: .cancel) { toDelete = nil }
                                } message: {
                                    Text("Its reminder goes too. The sessions you've counted stay in your history.")
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // Not `role: .destructive`: that makes the List expect the row to
                                    // go at once and the confirm never showed (sim).
                                    Button { toDelete = task } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                        }
                        .onMove(perform: move)
                    } footer: {
                        Text("Hold and drag to change the order on the Zikr page. Swipe left to delete.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(.rounded)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New task")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: TaskModel.self) { task in
                AddDailyTaskView(editing: task, isPresented: Binding(
                    get: { path.contains(task) },
                    set: { if !$0 { path.removeAll { $0 == task } } }))
                    .toolbar(.hidden, for: .navigationBar)   // the editor has its own ‹
            }
        }
        .sheet(isPresented: $creating) {
            AddDailyTaskView(isPresented: $creating, scrollProxy: .constant(nil))
        }
        .onAppear {
            sessions = ZikrReminders.todaysSessions(context)
            if let startOn { path = [startOn] }
        }
        .onChange(of: path) { _, _ in sessions = ZikrReminders.todaysSessions(context) }
        #if DEBUG
        .task { await demo() }
        #endif
    }

    // MARK: row

    private func row(_ task: TaskModel) -> some View {
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
                HStack(spacing: 5) {
                    Text(task.title).lineLimit(1)
                    Text("· " + (task.isCountMode ? "\(task.goal) count" : "\(task.goal) min"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                        .layoutPriority(1)
                }
                Text(progressText(task, p, done: done))
                    .font(.subheadline)
                    .foregroundStyle(done ? Color.sage : Color.secondary)
                    .monospacedDigit()
                if task.reminderKind != nil {
                    Label(reminderText(task), systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func progressText(_ task: TaskModel, _ p: TaskProgress, done: Bool) -> String {
        // No "today" (owner): everything here is today's.
        if done { return "done" }
        if task.isCountMode { return "\(p.count) of \(task.goal)" }
        return "\(Int(p.seconds / 60)) of \(task.goal) min"
    }

    /// "Every day · 10 min after Fajr" / "Weekdays at 9:30 PM".
    private func reminderText(_ task: TaskModel) -> String {
        let days = ZikrReminders.weekdaysString(task.reminderWeekdays)
        let dayWord = days == "every day" ? "Every day" : days.prefix(1).uppercased() + days.dropFirst()
        if task.reminderKind == "prayer", let prayer = task.reminderPrayer {
            let m = task.reminderOffsetMinutes ?? 0
            let when = m == 0 ? "at \(prayer)" : "\(abs(m)) min \(m < 0 ? "before" : "after") \(prayer)"
            return "\(dayWord) · \(when)"
        }
        return "\(dayWord) at \(ZikrReminders.clockString(task.reminderTimeMinutes ?? 20 * 60))"
    }

    // MARK: changes

    private func move(from source: IndexSet, to destination: Int) {
        var order = tasks
        order.move(fromOffsets: source, toOffset: destination)
        for (i, task) in order.enumerated() where task.sortOrder != i { task.sortOrder = i }
        try? context.save()
    }

    #if DEBUG
    /// `-demoZikrTasksSeed`: task 1 done, task 2 a reminder, task 3 partly done (simulator shots);
    /// `-demoZikrTasksEdit N` pushes task N's editor, `-demoZikrTasksDelete N` asks to delete it.
    private func demo() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoZikrTasksSeed"), tasks.count >= 3,
           !sessions.contains(where: { $0.task != nil }) {
            func session(_ task: TaskModel, count: Int) {
                context.insert(SessionDataModel(title: task.displayName, sessionMode: 2, targetMin: 0,
                                                targetCount: task.goal, totalCount: count, startTime: Date(),
                                                secondsPassed: Double(count), avgTimePerClick: 1,
                                                tasbeehRate: "1s", task: task, mantra: task.mantra))
            }
            if tasks[0].isCountMode { session(tasks[0], count: tasks[0].goal) }
            tasks[1].reminderKind = "prayer"; tasks[1].reminderPrayer = "Fajr"; tasks[1].reminderOffsetMinutes = 10
            if tasks[2].isCountMode { session(tasks[2], count: max(1, tasks[2].goal / 3)) }
            try? context.save()
            sessions = ZikrReminders.todaysSessions(context)
        }
        if args.contains("-demoZikrTasksPartial"), let t = tasks.first(where: { $0.isCountMode && $0.progress(in: sessions).count == 0 && $0.goal < 200 }) {
            context.insert(SessionDataModel(title: t.displayName, sessionMode: 2, targetMin: 0, targetCount: t.goal,
                                            totalCount: t.goal * 4 / 10, startTime: Date(), secondsPassed: 20,
                                            avgTimePerClick: 1, tasbeehRate: "1s", task: t, mantra: t.mantra))
            try? context.save()
            sessions = ZikrReminders.todaysSessions(context)
        }
        let edit = UserDefaults.standard.integer(forKey: "demoZikrTasksEdit")
        let del = UserDefaults.standard.integer(forKey: "demoZikrTasksDelete")
        try? await Task.sleep(for: .seconds(1.5))
        if edit > 0, edit <= tasks.count { path = [tasks[edit - 1]] }
        if del > 0, del <= tasks.count { toDelete = tasks[del - 1] }
    }
    #endif
}
