//
//  NewTaskFlow.swift
//  shukr
//
//  Making a zikr task (owner, 2026-10-01, the Zikr tab reorganisation): one sheet of short steps —
//  which zikr, the goal (hold − / + to repeat, tap the number to type it, count ⇄ minutes carries the
//  goal over at your pace), where it goes among your tasks (the system's own drag; only the new one
//  moves), and how it'll look with a name and a reminder. A new zikr is a card over the screen
//  (`newZikrCard`), also Azkar's ＋.
//  The last step is the task's review (owner, task-edit-review-page A, 2026-10-04): every choice a row, a tap opens
//  its step and "Done" comes back, like the setup's review. Editing a task opens the same page first
//  (`NewTaskFlow(editing:)`), so you edit on a page you've seen.
//

import SwiftUI
import SwiftData

// MARK: - New task: short steps in one sheet (owner: "simple and elegant")

/// One sheet, short steps in the app's own look: which zikr (a big light question over the list),
/// the goal in the app's circle, where it goes among your tasks (only when there are some), then how
/// it'll sit on the wheel with a name and a reminder. Every way to make a task opens this.
struct NewTaskFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var azkar: [MantraModel]
    @Query(sort: \TaskModel.sortOrder) private var existingTasks: [TaskModel]
    /// Where the new task goes among the existing ones (0 = first); nil = at the end (the default).
    @State private var insertAt: Int?
    var locked: MantraModel? = nil
    /// The task being edited: the flow opens on its review, and Save writes back (nil = a new task).
    var editing: TaskModel? = nil
    /// The task just made (the Zikr page centres it).
    var onCreated: (TaskModel) -> Void = { _ in }

    @State private var mantra: MantraModel?
    @State private var step = 1
    @State private var forward = true
    /// The step whose slide-in has finished (the placer scrolls its new row into view only then).
    @State private var arrivedStep = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var countMode = true
    @State private var goal = 33
    @State private var name = ""
    @State private var reminder = ReminderDraft()
    @State private var creatingZikr = false
    @State private var editingReminder = false
    @State private var search = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var goalFocused: Bool
    @State private var goalText = "33"
    /// A step opened from the review: its button reads "Done" and goes straight back (the setup's review does the same).
    @State private var returnToReview = false
    @State private var confirmDelete = false
    private var isEditing: Bool { editing != nil }
    private static let review = 4

    init(locked: MantraModel? = nil, onCreated: @escaping (TaskModel) -> Void = { _ in }) {
        self.locked = locked
        self.onCreated = onCreated
        _mantra = State(initialValue: locked)
        _step = State(initialValue: locked == nil ? 1 : 2)
        _arrivedStep = State(initialValue: locked == nil ? 1 : 2)
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "demoNewTaskStep")   // -demoNewTaskStep N (with -demoZikrPage)
        if n > 0 { _step = State(initialValue: n) }
        #endif
    }

    /// Editing `task`: its review first, the draft taken from it.
    init(editing task: TaskModel) {
        self.editing = task
        _mantra = State(initialValue: task.mantra)
        _step = State(initialValue: Self.review)
        _arrivedStep = State(initialValue: Self.review)
        _countMode = State(initialValue: task.isCountMode)
        _goal = State(initialValue: task.goal)
        _goalText = State(initialValue: "\(task.goal)")
        _name = State(initialValue: task.customName ?? "")
        _reminder = State(initialValue: ReminderDraft(task))
    }

    private var firstStep: Int { locked == nil ? 1 : 2 }
    private var yours: [MantraModel] { azkar.filter { !$0.isBuiltIn && matches($0) }.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    private var builtIns: [MantraModel] { azkar.filter { $0.isBuiltIn && matches($0) }.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    private func matches(_ m: MantraModel) -> Bool {
        search.isEmpty || m.name.localizedCaseInsensitiveContains(search) || m.fullText.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if editingReminder {
                    TaskReminderSheet(draft: reminder, embedded: true,
                                      onCancel: { openReminder(false) },
                                      onSave: { reminder = $0; openReminder(false) })
                        .transition(slide)
                } else {
                    switch step {
                    case 1: pickZikr.transition(slide)
                    case 2: pickGoal.transition(slide)
                    case 3: placeIt.transition(slide)
                    default: finish.transition(slide)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fontDesign(.rounded)
        // Never swiped away (owner): step one is a scrolling list, so a swipe meant for it closed the sheet. ✕ on
        // step one closes; ‹ walks back.
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .newZikrCard(isPresented: $creatingZikr, initialName: search) { made in
            mantra = made
            if returnToReview { backToReview() } else { go(2) }
        }

    }

    private var slide: AnyTransition {
        // Under Reduce Motion the steps cross-fade in place (Apple: fades, not slides — audit E11).
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }
    /// The steps this time: Where should it go? (3) only when there are tasks already (owner: a
    /// required step then); "Looks good" is 4.
    private var steps: [Int] {
        (existingTasks.isEmpty ? [1, 2, 4] : [1, 2, 3, 4]).filter { $0 >= firstStep }
    }
    private func next() { if let i = steps.firstIndex(of: step), i + 1 < steps.count { go(steps[i + 1]) } }
    private func back() {
        if returnToReview { backToReview(); return }
        if isEditing { dismiss(); return }
        if let i = steps.firstIndex(of: step), i > 0 { go(steps[i - 1]) } else { dismiss() }
    }
    /// From the review into one step; its button then reads "Done".
    private func edit(_ to: Int) { returnToReview = true; go(to) }
    private func backToReview() {
        goalFocused = false
        returnToReview = false
        go(Self.review)
    }
    /// A step's one button: on to the next, or back to the review it was opened from.
    private func stepButton() -> some View {
        primary(returnToReview ? "Done" : "Continue") { returnToReview ? backToReview() : next() }
    }
    private func openReminder(_ open: Bool) {
        forward = open
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { editingReminder = open }
    }
    private func go(_ to: Int) {
        forward = to > step
        Task { @MainActor in
            await CircleMotion.animate(CircleMotion.movement(Self.stepMotion, reduced: reduceMotion)) { step = to }
            arrivedStep = to
        }
    }
    private static let stepMotion = Animation.spring(response: 0.42, dampingFraction: 0.9)

    // MARK: the top: back / close, and three small steps

    private var topBar: some View {
        HStack {
            Button {
                if editingReminder { openReminder(false) } else { back() }
            } label: {
                Image(systemName: editingReminder || returnToReview || (step > firstStep && !isEditing) ? "chevron.left" : "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                // No dots once there's a review to come back to: the steps are no longer a sequence.
                ForEach(isEditing || returnToReview ? [] : steps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.sage : Color.primary.opacity(0.12))
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .light, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    // MARK: step 1 — which zikr

    private var pickZikr: some View {
        ScrollView {
            VStack(spacing: 18) {
                heading("Which zikr?", "Pick one you'd like to say every day")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 20)

                Button { creatingZikr = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sage)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.sage.opacity(0.14)))
                        Text(search.isEmpty ? "A new zikr" : "New zikr \u{201C}\(search)\u{201D}")
                            .foregroundStyle(Color.sage)
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.sage.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                if !yours.isEmpty { group("Your azkar", yours) }
                if !builtIns.isEmpty { group("Built-in", builtIns) }
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func group(_ title: String, _ list: [MantraModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.medium)).tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 34)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    Button {
                        mantra = m
                        if returnToReview { backToReview() } else { go(2) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name).foregroundStyle(.primary).lineLimit(1)
                                if !m.fullText.isEmpty {
                                    Text(m.fullText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: mantra == m ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(mantra == m ? Color.sage : Color.secondary.opacity(0.5))
                                .font(.system(size: mantra == m ? 18 : 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < list.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 20)
        }
    }

    // MARK: step 2 — the goal, in the app's circle

    /// From your own pace on this zikr: a count goal → how long it takes; a minutes goal → about how
    /// many counts fit (owner).
    private var estimate: String? {
        guard let pace = mantra?.secondsPerCount, pace > 0 else { return nil }
        if countMode {
            let secs = pace * Double(goal)
            if secs < 60 { return "under a minute a day at your pace" }
            let mins = Int((secs / 60).rounded())
            return mins < 60 ? "about \(mins) min a day at your pace"
                             : "about \(mins / 60)h\(mins % 60 == 0 ? "" : " \(mins % 60)m") a day at your pace"
        }
        let counts = Int((Double(goal) * 60 / pace).rounded())
        return "about \(counts.formatted()) counts a day at your pace"
    }

    private var pickGoal: some View {
        VStack(spacing: 0) {
            heading(mantra?.name ?? "Your goal", "How much each day?")
            Spacer(minLength: 16)
            HStack(spacing: 0) {
                kindButton("Count", true)
                kindButton("Minutes", false)
            }
            .padding(4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            Spacer(minLength: 22)
            HStack(spacing: 18) {
                // Tap = one; hold = keeps going, faster the longer it's held (owner).
                RepeatRoundButton(symbol: "minus") { step in goal = max(1, goal - step) }
                ZStack {
                    Circle().stroke(Color(.secondarySystemFill), lineWidth: 12)
                    Circle().stroke(Color.sage.opacity(goalFocused ? 1 : 0.85), lineWidth: goalFocused ? 3.5 : 2.5).padding(4.75)
                    VStack(spacing: 2) {
                        // Tap the number to type one: the number pad only (owner).
                        // Starts empty on a tap, the current number as a faint placeholder: typing
                        // replaces it rather than adding to it.
                        TextField("\(goal)", text: $goalText)
                            // The keyboard with digits on top and a return key shown as "done" (owner:
                            // the number pad had no way to close it); anything but digits is dropped.
                            .keyboardType(.numbersAndPunctuation)
                            .submitLabel(.done)
                            .autocorrectionDisabled()          // no word suggestions over a number
                            .textInputAutocapitalization(.never)
                            .onSubmit { goalFocused = false }
                            .focused($goalFocused)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 60, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 170)
                            .onChange(of: goalText) { _, t in
                                let digits = String(t.filter(\.isNumber).prefix(5))
                                if digits != t { goalText = digits }
                                if let n = Int(digits), n > 0 { goal = n }
                            }
                        Text(countMode ? "a day" : "min a day")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                .contentShape(Circle())
                .onTapGesture { goalFocused = true }
                RepeatRoundButton(symbol: "plus") { step in goal = min(99_999, goal + step) }
            }
            .onChange(of: goal) { _, g in if !goalFocused || Int(goalText) != g { goalText = "\(g)" } }
            .onChange(of: goalFocused) { _, on in goalText = on ? "" : "\(goal)" }
            .onAppear { goalText = "\(goal)" }
            Text(estimate ?? " ")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 26)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: estimate)
            Spacer()
            // Hidden while typing (owner: a tap meant to close the keyboard could land on it).
            if !goalFocused {
                stepButton()
                    .transition(.opacity)
            }
        }
        // A tap off the number puts the keypad away (it has no return key).
        .contentShape(Rectangle())
        .onTapGesture { goalFocused = false }
    }

    /// Switching Count ⇄ Minutes carries the goal over at your pace on this zikr (owner: "use that
    /// estimated value as the new value"): 100 counts at 14 s each → 24 min; 10 min → 42 counts.
    /// No pace yet → the usual defaults.
    private func converted(toCount count: Bool) -> Int {
        guard let pace = mantra?.secondsPerCount, pace > 0 else { return count ? 33 : 10 }
        if count { return max(1, Int((Double(goal) * 60 / pace).rounded())) }
        return max(1, Int((pace * Double(goal) / 60).rounded()))
    }

    private func kindButton(_ title: String, _ count: Bool) -> some View {
        Button {
            guard count != countMode else { return }
            withAnimation(.snappy(duration: 0.2)) {
                goal = converted(toCount: count)
                countMode = count
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(countMode == count ? Color.primary : Color.secondary)
                .frame(width: 104, height: 34)
                .background(Capsule().fill(countMode == count ? Color(.systemBackground) : .clear)
                    .shadow(color: .black.opacity(countMode == count ? 0.08 : 0), radius: 4, y: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: step 3 — where it goes (only with tasks already)

    private var placeIt: some View {
        VStack(spacing: 0) {
            heading("Where should it go?", "Drag it into place on your Zikr page")
            NewTaskPlacer(rows: existingTasks.map { .init(title: $0.title, kind: $0.isCountMode ? "\($0.goal.formatted()) count" : "\($0.goal) min") },
                          newTitle: previewTitle, newKind: countMode ? "\(goal.formatted()) count" : "\(goal) min",
                          position: Binding(get: { insertAt ?? existingTasks.count },
                                            set: { insertAt = $0 }),
                          arrived: arrivedStep == 3)
                .padding(.top, 16)
            stepButton()
        }
    }

    // MARK: step 4 — the review: how it'll look, and every choice a row

    private var previewTitle: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? (mantra?.name ?? "") : n
    }

    private var finish: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    heading(isEditing ? "Your task" : "Looks good", "Tap anything to change it")
                    ZikrCircleFace(title: previewTitle, icon: nil,
                                   subtitle: countMode ? "\(today.count) of \(goal)" : "\(today.minutes) of \(goal) min",
                                   ring: .progress(today.fraction),
                                   mantraLine: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : mantra?.name)
                        .frame(width: 190, height: 190)
                        .animation(.easeInOut(duration: 0.2), value: previewTitle)
                    card {
                        reviewRow("text.book.closed", "Zikr", mantra?.name ?? editing?.displayName ?? "") { edit(1) }
                        Divider().padding(.leading, 52)
                        reviewRow("target", "Goal", countMode ? "\(goal.formatted()) times a day" : "\(goal) min a day") { edit(2) }
                        // Where it goes, for a new one only: an existing task moves by dragging in Your tasks.
                        if !isEditing && !existingTasks.isEmpty {
                            Divider().padding(.leading, 52)
                            reviewRow("list.number", "Place", placeLine) { edit(3) }
                        }
                    }
                    card {
                        HStack(spacing: 12) {
                            Image(systemName: "character.cursor.ibeam").foregroundStyle(Color.sage).frame(width: 24)
                            TextField("Name it (optional), e.g. After Fajr", text: $name)
                                .focused($nameFocused)
                                .submitLabel(.done)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        Divider().padding(.leading, 52)
                        // The reminder: the old sheet's view, slid in within this sheet (owner: its look,
                        // but no second sheet).
                        reviewRow(reminder.kind == nil ? "bell" : "bell.fill", "Reminder",
                                  reminder.kind == nil ? "Off" : reminder.summary) { openReminder(true) }
                    }
                    if isEditing {
                        Button("Delete Task", role: .destructive) { confirmDelete = true }
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            primary(isEditing ? "Save" : "Add to my day") { isEditing ? save() : create() }
        }
        .confirmationDialog(editing.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete Task", role: .destructive) { deleteTask() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sessions stay in your history.")
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 20)
    }

    private func reviewRow(_ icon: String, _ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Color.sage).frame(width: 24)
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "3rd of 5": where the new task lands among yours.
    private var placeLine: String {
        let at = min(insertAt ?? existingTasks.count, existingTasks.count) + 1
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        return "\(ordinal.string(from: at as NSNumber) ?? "\(at)") of \(existingTasks.count + 1)"
    }

    /// Today's progress on the task being edited, against the goal as it stands in the draft (a new task: none).
    private var today: (count: Int, minutes: Int, fraction: Double) {
        guard let editing else { return (0, 0, 0) }
        let p = editing.progress(in: ZikrReminders.todaysSessions(context))
        let fraction = countMode ? Double(p.count) / Double(max(goal, 1)) : p.seconds / Double(max(goal, 1) * 60)
        return (p.count, Int(p.seconds / 60), min(1, fraction))
    }

    private func save() {
        guard let editing, let mantra else { return }
        // Another zikr keeps the task (and its streak and history): owner, task-edit-review-pick A.
        editing.mantra = mantra
        editing.mantraName = mantra.name
        editing.isCountMode = countMode
        editing.goal = goal
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editing.customName = trimmed.isEmpty ? nil : trimmed
        reminder.apply(to: editing)
        try? context.save()   // a reminder only in memory was lost if the app was killed before autosave
        NotificationScheduler.reschedule(context: context, reason: "task reminder")
        dismiss()
    }

    /// The page goes first, then the task (a task deleted under its own page left a stale view behind).
    private func deleteTask() {
        guard let editing else { return }
        let context = context
        dismiss()
        DispatchQueue.main.async { withAnimation { TaskModel.delete(editing, in: context) } }
    }

    // MARK: the one button (the pause screen's Resume look)

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.sage)
                .frame(width: 240, height: 52)
                .background(Capsule().fill(Color.sage.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func create() {
        guard let mantra else { return }
        let task = TaskModel(mantra: mantra, isCountMode: countMode, goal: goal,
                             sortOrder: TaskModel.nextSortOrder(in: context))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        task.customName = trimmed.isEmpty ? nil : trimmed
        reminder.apply(to: task)
        context.insert(task)
        // Into its place: renumber the list with the new one at `insertAt`.
        var order = existingTasks
        order.insert(task, at: min(insertAt ?? order.count, order.count))
        for (i, t) in order.enumerated() { t.sortOrder = i }
        try? context.save()
        if reminder.kind != nil { NotificationScheduler.reschedule(context: context, reason: "task reminder") }
        dismiss()
        onCreated(task)
    }
}

// MARK: - New zikr: the card itself, centred over a dimmed screen (owner: no whole sheet)

extension View {
    /// A new zikr as just the card (the same green-edged card as a zikr's page in edit mode), in the
    /// middle of the screen over a dimmed background, ✕ and ✓ beside the name. Used by the task flow's
    /// "A new zikr" and Azkar's +.
    func newZikrCard(isPresented: Binding<Bool>, initialName: String = "",
                     onCreate: @escaping (MantraModel) -> Void = { _ in }) -> some View {
        modifier(NewZikrCardPresenter(isPresented: isPresented, initialName: initialName, onCreate: onCreate))
    }
}

/// Over everything (the bar and the search field too): a clear full-screen cover without its slide —
/// the card and the dim fade in themselves.
private struct NewZikrCardPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let initialName: String
    let onCreate: (MantraModel) -> Void
    @State private var cover = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, on in
                var quiet = Transaction(); quiet.disablesAnimations = true
                withTransaction(quiet) { cover = on }
            }
            .fullScreenCover(isPresented: $cover) {
                NewZikrCard(isPresented: $isPresented, initialName: initialName, onCreate: onCreate)
                    .presentationBackground(.clear)
            }
    }
}

private struct NewZikrCard: View {
    @Binding var isPresented: Bool
    let initialName: String
    let onCreate: (MantraModel) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Query private var allMantras: [MantraModel]

    @State private var name = ""
    @State private var fullText = ""
    @State private var notes = ""
    @State private var quickAdd = 0
    @State private var image: Data?
    @State private var audio: Data?
    @State private var shown = false
    @State private var confirmDiscard = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool {
        let key = BuiltInAzkar.key(trimmed)
        return !trimmed.isEmpty && allMantras.contains { BuiltInAzkar.key($0.name) == key }
    }
    private var canSave: Bool { !trimmed.isEmpty && !isDuplicate }
    private var hasContent: Bool {
        !trimmed.isEmpty || !fullText.isEmpty || !notes.isEmpty || image != nil || audio != nil || quickAdd != 0
    }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.72 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack {
                Spacer(minLength: 60)
                MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: $quickAdd,
                                 imageData: $image, audioData: $audio, isDuplicate: isDuplicate,
                                 editable: true, nameAccessory: AnyView(controls))
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.sage.opacity(0.7), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                    .padding(.horizontal, 16)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                    .opacity(shown ? 1 : 0)
                Spacer(minLength: 60)
            }
        }
        .fontDesign(.rounded)
        .onAppear {
            name = initialName
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { shown = true }
        }
        .alert("Discard this zikr?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .accessibilityLabel("Cancel")
            Button { save() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSave ? Color.white : Color.secondary.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canSave ? Color.sage : Color.primary.opacity(0.06)))
            }
            .disabled(!canSave)
            .accessibilityLabel("Save zikr")
        }
        .buttonStyle(.plain)
    }

    private func close() {
        if hasContent { confirmDiscard = true } else { dismiss() }
    }

    private func dismiss() {
        ZikrAudio.stopAll()
        Task { @MainActor in
            await CircleMotion.animate(.easeOut(duration: CircleMotion.quick)) { shown = false }   // then the cover goes
            isPresented = false
        }
    }

    private func save() {
        ZikrAudio.stopAll()
        guard canSave else { return }
        let new = MantraModel(name: trimmed,
                              fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                              notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        new.quickAddStep = quickAdd
        new.imageData = image
        new.audioData = audio
        context.insert(new)
        try? context.save()
        triggerSomeVibration(type: .success)
        Task { @MainActor in
            await CircleMotion.animate(.easeOut(duration: CircleMotion.quick)) { shown = false }   // then the cover goes
            isPresented = false
            onCreate(new)
        }
    }
}


/// − / + that repeats while held, speeding up: 1 a step at first, then 5 after ~1.5 s, 10 after
/// ~3 s; a tap is one step (owner: "hold the plus … fast increase").
struct RepeatRoundButton: View {
    let symbol: String
    let action: (Int) -> Void
    @State private var timer: Timer?
    @State private var started: Date?
    @State private var pressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color.primary.opacity(pressed ? 0.14 : 0.06)))
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() }
            )
            .accessibilityLabel(symbol == "plus" ? "More" : "Less")
            .accessibilityAddTraits(.isButton)
            .onDisappear { end() }
    }

    private func begin() {
        pressed = true
        started = Date()
        action(1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        timer?.invalidate()
        // After a short hold, repeat.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                let held = Date().timeIntervalSince(started ?? Date())
                action(held > 3 ? 10 : (held > 1.5 ? 5 : 1))
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func end() {
        pressed = false
        timer?.invalidate()
        timer = nil
    }
}


// MARK: - Where the new task goes

/// Your tasks as numbered rows ("1 · Morning Durood / 50 count") with the new one among them, on the
/// system's own list reorder (owner: native): hold the new row anywhere and drag — the lift, the
/// haptics, the rows making room and the scrolling at the edges are all iOS's. Only the new row
/// moves (`onMove` ignores the rest).
struct NewTaskPlacer: View {
    struct Row { let title: String; let kind: String }
    let rows: [Row]
    let newTitle: String
    let newKind: String
    @Binding var position: Int
    /// Its step has finished sliding in: then the new row is scrolled into view (it waited a guessed 350 ms).
    var arrived = true
    @State private var order: [Int?] = []      // nil = the new task

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(order.enumerated()), id: \.element) { n, slot in
                    Group {
                        if let r = slot { row(rows[r], number: n + 1) } else { newRow(number: n + 1) }
                    }
                    .listRowBackground(slot == nil ? Color.sage.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                    .id(slot ?? -1)
                }
                .onMove { from, to in
                    // Only the new row moves. (`moveDisabled` on the others would be the tidy way, but it also
                    // stopped anything landing between them — the drop was refused.) Another row springs back.
                    guard from.allSatisfy({ order[$0] == nil }) else { return }
                    order.move(fromOffsets: from, toOffset: to)
                    position = order.firstIndex(where: { $0 == nil }) ?? position
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("placer-list")
            .onAppear {
                var o: [Int?] = rows.indices.map { $0 }
                o.insert(nil, at: min(position, o.count))
                order = o
            }
            .task(id: arrived) {
                // Once the slide-in has finished; earlier, the row landed half under the list's edge.
                guard arrived else { return }
                withAnimation(.snappy) { proxy.scrollTo(-1, anchor: position >= rows.count ? .bottom : .center) }   // centring the last row overshot, leaving it half under the edge
            }
        }
    }

    private func number(_ n: Int, new: Bool = false) -> some View {
        Text("\(n)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(new ? Color.sage : Color.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(new ? Color.sage.opacity(0.2) : Color.primary.opacity(0.07)))
    }

    private func row(_ r: Row, number n: Int) -> some View {
        HStack(spacing: 12) {
            number(n)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).lineLimit(1).foregroundStyle(.primary.opacity(0.75))
                Text(r.kind).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func newRow(number n: Int) -> some View {
        HStack(spacing: 12) {
            number(n, new: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(newTitle).fontWeight(.semibold).foregroundStyle(Color.sage).lineLimit(1)
                    Text("new").font(.caption2.weight(.bold)).foregroundStyle(Color.sage)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.sage.opacity(0.18)))
                }
                Text("\(newKind) · hold and drag").font(.footnote).foregroundStyle(Color.sage.opacity(0.8)).monospacedDigit()
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal").foregroundStyle(Color.sage.opacity(0.7))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("placer-new")
    }
}
