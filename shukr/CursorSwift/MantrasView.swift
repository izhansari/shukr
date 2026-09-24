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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Durood", text: $name)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Name")
                } footer: {
                    if isDuplicate {
                        Text("A mantra with this name already exists.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Shown on task cards, in the picker and in history.")
                    }
                }

                Section {
                    TextEditor(text: $fullText)
                        .frame(minHeight: 80)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Full mantra")
                } footer: {
                    Text("The complete wording, Arabic or transliterated.")
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Why or when to read it, who recommended it, anything you want to remember.")
                }

                if let mantra {
                    // Count / time / rate as the pause screen's bento boxes, then this mantra's
                    // tasks as the Zikr page's card strip, then its sessions as in Zikr History.
                    Section("Stats") {
                        MantraStatsBento(mantra: mantra)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section("Tasks") {
                        MantraTasksStrip(mantra: mantra)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    MantraSessionsSections(mantra: mantra)
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

    var body: some View {
        let pace = mantra.secondsPerCount
        HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                box {
                    HStack {
                        Image(systemName: "circle.hexagonpath").font(.system(size: 20))
                        Spacer()
                        Text(mantra.totalCount.formatted()).font(.system(size: 14, weight: .medium)).monospacedDigit()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 44)
                box {
                    HStack {
                        Image(systemName: "gauge.with.needle").font(.system(size: 20))
                        Spacer()
                        Text(zikrDurationString(mantra.totalSeconds)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 44)
            }

            box {
                VStack(spacing: 6) {
                    Text("Rate").font(.system(size: 18, weight: .medium)).underline()
                    ZStack {
                        VStack(spacing: 2) {
                            Text(pace.map { String(format: "%.1fs", $0) } ?? "–")
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("per count").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .opacity(showingPerCount ? 1 : 0)
                        .offset(y: showingPerCount ? 0 : -20)
                        VStack(spacing: 2) {
                            Text(pace.map { zikrDurationString($0 * 100) } ?? "–")
                                .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Text("per tasbeeh").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .opacity(showingPerCount ? 0 : 1)
                        .offset(y: showingPerCount ? 20 : 0)
                    }
                }
            }
            .frame(height: 44 * 2 + gap)
            .contentShape(Rectangle())
            .onTapGesture {
                guard pace != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    triggerSomeVibration(type: .medium)
                    showingPerCount.toggle()
                }
            }
        }
    }

    private func box<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
    }
}

/// This mantra's tasks as the Zikr page's card strip (same `TaskCardView`, same today's
/// completion). Long-press a card to delete the task; sessions it produced keep their history.
struct MantraTasksStrip: View {
    let mantra: MantraModel
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]

    init(mantra: MantraModel) {
        self.mantra = mantra
        let todayStart = Calendar.current.startOfDay(for: Date())
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart })
    }

    private var tasks: [TaskModel] { mantra.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        if tasks.isEmpty {
            Text("No tasks use this mantra.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(task: task, isCompleted: task.isCompleted(with: task.progress(in: todaysSessions)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.gradient.opacity(0.4), lineWidth: 0.4))
                            .contextMenu {
                                Button(role: .destructive) {
                                    context.delete(task)
                                } label: {
                                    Label("Delete task", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// This mantra's sessions, newest first, one section per day — the Zikr History layout, so
/// "when did I last do this one" is the first row.
struct MantraSessionsSections: View {
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
        if mantra.sessions.isEmpty {
            Section("Sessions") {
                Text("No sessions with this mantra yet.").foregroundStyle(.secondary)
            }
        } else {
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.sessions) { session in SessionRow(session: session) }
                } header: {
                    HStack {
                        Text(zikrDayLabel(day.date))
                        Spacer()
                        Text("\(day.sessions.reduce(0) { $0 + $1.totalCount }) counted")
                    }
                }
            }
        }
    }
}
