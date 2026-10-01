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

struct YourTasksPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @State private var sessions: [SessionDataModel] = []
    /// The task whose edit screen is pushed.
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var creating = false
    @State private var openZikr: MantraModel?

    var body: some View {
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
                            Button { editing = task } label: { TaskRow(task: task, sessions: sessions) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    TaskMenu(task: task,
                                             onStart: { start(task) },
                                             onEdit: { editing = task },
                                             onOpenZikr: { openZikr = task.mantra },
                                             onDelete: { toDelete = task })
                                }
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
                        Button { creating = true } label: {
                            Label("New task", systemImage: "plus.circle.fill").foregroundStyle(Color.sage)
                        }
                    } footer: {
                        Text("Hold and drag to change the order on the Zikr page. Swipe left to delete.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fontDesign(.rounded)
            .navigationTitle("Your tasks")
            .navigationBarTitleDisplayMode(.large)
            // Also top right: with many tasks the New task row is off screen.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New task")
                }
            }
            .navigationDestination(item: $editing) { task in
                AddDailyTaskView(editing: task, isPresented: Binding(
                    get: { editing != nil }, set: { if !$0 { editing = nil } }))
                    .toolbar(.hidden, for: .navigationBar)   // the editor has its own ‹
            }
        .sheet(isPresented: $creating) { NewTaskFlow() }
        .sheet(item: $openZikr) { MantraEditorView(mantra: $0) }
        .onAppear { sessions = ZikrReminders.todaysSessions(context) }
        .onChange(of: editing) { _, _ in sessions = ZikrReminders.todaysSessions(context) }
        #if DEBUG
        .task { await demo() }
        #endif
    }

    // MARK: changes

    /// Back to the Zikr page first, then its wheel starts the task (continuing today's count).
    private func start(_ task: TaskModel) {
        let id = task.id.uuidString
        let resume = task.progress(in: sessions).count > 0 || task.progress(in: sessions).seconds >= 1
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ZikrFocus.start(id, resume: resume) }
    }

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
        if edit > 0, edit <= tasks.count { editing = tasks[edit - 1] }
        if del > 0, del <= tasks.count { toDelete = tasks[del - 1] }
    }
    #endif
}

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
    let onDelete: () -> Void

    var body: some View {
        if let onStart { Button(action: onStart) { Label("Start", systemImage: "play.fill") } }
        Button(action: onEdit) { Label("Edit task", systemImage: "pencil") }
        if let onOpenZikr, task.mantra != nil {
            Button(action: onOpenZikr) { Label("Open zikr", systemImage: "text.quote") }
        }
        Divider()
        Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
    }
}
