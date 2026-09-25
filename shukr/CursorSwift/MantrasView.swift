//
//  MantrasView.swift
//  shukr
//
//  Manage the mantra list from the side menu. A mantra has a short `name` (what cards, the
//  picker and session titles show), the `fullText` (Arabic / transliteration) and free `notes`.
//  The four built-ins are ordinary rows here — seeded on migration / first launch — so they can
//  be edited like the rest. Tasks and sessions point at the row, so a rename shows everywhere;
//  deleting a row unlinks them (tasks fall back to their name snapshot, sessions keep `title`).
//

import SwiftUI
import SwiftData

struct MantrasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var mantras: [MantraModel]

    @State private var editing: MantraModel? = nil
    @State private var showingNewMantra = false

    var body: some View {
        List {
            if mantras.isEmpty {
                Text("No mantras yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mantras) { mantra in
                    Button {
                        editing = mantra
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mantra.name)
                                    .foregroundStyle(.primary)
                                if !mantra.fullText.isEmpty {
                                    Text(mantra.fullText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let pace = mantra.secondsPerCount {
                                    Text("\(mantra.totalCount.formatted()) counted · \(String(format: "%.1fs", pace)) each")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if !mantra.notes.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary) // rows, not links
                }
                .onDelete(perform: delete)
            }
        }
        .fontDesign(.rounded)
        .navigationTitle("Mantras")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewMantra = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.green.opacity(0.7))
                }
            }
        }
        .sheet(item: $editing) { mantra in
            MantraEditorView(mantra: mantra)
        }
        .sheet(isPresented: $showingNewMantra) {
            MantraEditorView(mantra: nil)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(mantras[index]) // relationships are .nullify: tasks/sessions survive, unlinked
        }
    }
}


/// Create or edit one mantra. `mantra == nil` means create.
struct MantraEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMantras: [MantraModel]

    let mantra: MantraModel?
    @State private var name: String
    @State private var fullText: String
    @State private var notes: String
    // Field descriptions sit behind an info button in each header, like Settings.
    @State private var showNameInfo = false
    @State private var showFullTextInfo = false
    @State private var showNotesInfo = false

    init(mantra: MantraModel?) {
        self.mantra = mantra
        _name = State(initialValue: mantra?.name ?? "")
        _fullText = State(initialValue: mantra?.fullText ?? "")
        _notes = State(initialValue: mantra?.notes ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another mantra (other than the one being edited) already uses this name.
    private var isDuplicate: Bool {
        let lower = trimmedName.lowercased()
        return allMantras.contains { $0.name.lowercased() == lower && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    /// The row an info button reveals — same look as Settings' dropdown info.
    private func fieldInfo(_ text: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle")
            Text(text).font(.caption)
        }
        .foregroundColor(.gray)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Durood", text: $name)
                        .autocorrectionDisabled(true)
                    if showNameInfo {
                        fieldInfo("Shown on task cards, in the picker and in history.")
                    }
                } header: {
                    headerWithInfoButton(title: "Name", isPopupVisible: $showNameInfo)
                } footer: {
                    if isDuplicate {
                        Text("A mantra with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextEditor(text: $fullText)
                        .frame(minHeight: 80)
                        .autocorrectionDisabled(true)
                    if showFullTextInfo {
                        fieldInfo("The complete wording, Arabic or transliterated.")
                    }
                } header: {
                    headerWithInfoButton(title: "Full mantra", isPopupVisible: $showFullTextInfo)
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                    if showNotesInfo {
                        fieldInfo("Why or when to read it, who recommended it, anything you want to remember.")
                    }
                } header: {
                    headerWithInfoButton(title: "Notes", isPopupVisible: $showNotesInfo)
                }

                if let mantra {
                    // Count / time / rate as the pause screen's bento boxes. They live in the
                    // section header: a grouped section clips its rows to its own corner shape
                    // (26 pt on iOS 26+), which cut the boxes' corners when they were a row.
                    Section {
                        MantraTaskRows(mantra: mantra)
                    } header: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lifetime Stats")
                            MantraStatsBento(mantra: mantra)
                                .padding(.bottom, 16)
                            Text("Tasks")
                        }
                    }
                    MantraSessionsSection(mantra: mantra)
                }
            }
            .fontDesign(.rounded)
            .navigationTitle(mantra == nil ? "New Mantra" : "Edit Mantra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let fullTextTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mantra {
            mantra.name = trimmedName
            mantra.fullText = fullTextTrimmed
            mantra.notes = notesTrimmed
            // Tasks read the live name through the relationship; keep their snapshot in step too
            // so a later deletion still shows the right name. Sessions keep their historical title.
            for task in mantra.tasks { task.mantraName = trimmedName }
        } else {
            context.insert(MantraModel(name: trimmedName, fullText: fullTextTrimmed, notes: notesTrimmed))
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MantrasView()
    }
    .modelContainer(for: [MantraModel.self, TaskModel.self, SessionDataModel.self], inMemory: true)
}


// MARK: - Editor: stats, tasks, sessions

/// Count · time · rate for one mantra, laid out like the pause screen's stats grid (count and
/// time stacked on the left, the rate box on the right). Tap the rate box to flip between
/// seconds per count and time per tasbeeh (100 counts), same slide-and-fade as there.
struct MantraStatsBento: View {
    let mantra: MantraModel
    @State private var showingPerCount = true
    private let gap: CGFloat = 10
    private let boxHeight: CGFloat = 56

    var body: some View {
        let pace = mantra.secondsPerCount
        HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                box {
                    HStack {
                        Image(systemName: "circle.hexagonpath").font(.system(size: 20))
                        Spacer()
                        VStack(spacing: 2) {
                            Text(mantra.totalCount.formatted())
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("total count").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: boxHeight)
                box {
                    HStack {
                        Image(systemName: "gauge.with.needle").font(.system(size: 20))
                        Spacer()
                        VStack(spacing: 2) {
                            Text(zikrDurationString(mantra.totalSeconds))
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("total time").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: boxHeight)
            }

            box {
                VStack(spacing: 6) {
                    Text("Rate").font(.system(size: 18, weight: .medium)).underline()
                    ZStack {
                        VStack(spacing: 2) {
                            Text(pace.map { String(format: "%.1fs", $0) } ?? "–")
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("per count").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .opacity(showingPerCount ? 1 : 0)
                        .offset(y: showingPerCount ? 0 : -20)
                        VStack(spacing: 2) {
                            Text(pace.map { zikrDurationString($0 * 100) } ?? "–")
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("per tasbeeh").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .opacity(showingPerCount ? 0 : 1)
                        .offset(y: showingPerCount ? 20 : 0)
                    }
                }
            }
            .frame(height: boxHeight * 2 + gap)
            .contentShape(Rectangle())
            .onTapGesture {
                guard pace != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    triggerSomeVibration(type: .medium)
                    showingPerCount.toggle()
                }
            }
        }
        .foregroundStyle(Color(.label))   // the header styles its text secondary; values are primary
        .textCase(nil)
        .padding(.horizontal, -20)        // the header is inset from the section cards; line up with them
    }

    private func box<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// This mantra's tasks as rows: mode + goal, today's progress. Tap opens the task sheet in
/// edit mode (goal / units; the mantra is locked); swipe to delete (sessions it produced keep
/// their history).
struct MantraTaskRows: View {
    let mantra: MantraModel
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]
    @State private var editing: TaskModel? = nil

    init(mantra: MantraModel) {
        self.mantra = mantra
        let todayStart = Calendar.current.startOfDay(for: Date())
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart })
    }

    private var tasks: [TaskModel] { mantra.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        if tasks.isEmpty {
            Text("No tasks use this mantra.").foregroundStyle(.secondary)
        } else {
            ForEach(tasks) { task in
                let progress = task.progress(in: todaysSessions)
                let done = task.isCompleted(with: progress)
                Button {
                    editing = task
                } label: {
                    HStack {
                        Image(systemName: task.isCountMode ? "number" : "timer")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(task.isCountMode ? "\(task.goal) counts" : "\(task.goal) min")
                            .foregroundStyle(.primary)
                        Spacer()
                        if done {
                            Label("Done today", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(task.isCountMode
                                 ? "\(progress.count) / \(task.goal) today"
                                 : "\(Int(progress.seconds / 60)) / \(task.goal) min today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(tasks[index]) }
            }
            .fullScreenCover(item: $editing) { task in
                // The "Create a New Task" sheet in edit mode: mantra locked, Save only once
                // something changed, confirmation before it lands.
                AddDailyTaskView(editing: task, isPresented: Binding(
                    get: { editing != nil },
                    set: { if !$0 { editing = nil } }
                ))
            }
        }
    }
}

/// This mantra's sessions under one "Sessions" header, newest first, as one card with a
/// tinted day-divider row before each day's rows — so "when did I last do this one" is the
/// first row. (Day rows with the page's background split the card and read as empty sections.)
struct MantraSessionsSection: View {
    let mantra: MantraModel

    private var days: [(date: Date, sessions: [SessionDataModel])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [SessionDataModel]] = [:]
        for session in mantra.sessions.sorted(by: { $0.startTime > $1.startTime }) {
            let day = calendar.startOfDay(for: session.startTime)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(session)
        }
        return order.map { (date: $0, sessions: byDay[$0] ?? []) }
    }

    var body: some View {
        Section("Sessions") {
            if mantra.sessions.isEmpty {
                Text("No sessions with this mantra yet.").foregroundStyle(.secondary)
            } else {
                // One card: each day is a divider row inside it, then that day's sessions.
                ForEach(days, id: \.date) { day in
                    HStack {
                        Text(zikrDayLabel(day.date))
                        Spacer()
                        Text("\(day.sessions.reduce(0) { $0 + $1.totalCount }) counted")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    // Same card colour, faintly tinted (tertiary grouped equals the page
                    // background in light mode and split the card).
                    .listRowBackground(Color(.secondarySystemGroupedBackground).overlay(Color.primary.opacity(0.04)))
                    ForEach(day.sessions) { session in SessionRow(session: session, showsMantraName: false) }
                }
            }
        }
    }
}
