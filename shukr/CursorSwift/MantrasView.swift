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
    @State private var search = ""

    /// Matches the name, the full wording or the notes.
    private var shown: [MantraModel] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return mantras }
        return mantras.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.fullText.localizedCaseInsensitiveContains(q)
                || $0.notes.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if mantras.isEmpty {
                Text("No mantras yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("No mantras match “\(search)”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shown) { mantra in
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
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search mantras")
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
        let rows = shown
        for index in offsets {
            context.delete(rows[index]) // relationships are .nullify: tasks/sessions survive, unlinked
        }
    }
}


/// "Count in sets  [off / +5]  [− | +]" bound to any step value (the editor's draft, or live).
/// Shown as "count in sets" (owner, 2026-09-25: "quick add" didn't say what it's for — you
/// recite a set on your own, counting on your fingers or in your head, then tap once).
struct QuickAddStepper: View {
    @Binding var step: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Count in sets")
                Text(step > 0 ? "one tap counts \(step)" : "read a few on your own, then tap once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Text(step > 0 ? "+\(step)" : "off")
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(step > 0 ? Color.sage : .secondary)
                .contentTransition(.numericText())
                .frame(minWidth: 40, alignment: .trailing)
            HoldRepeatStepper(
                value: Binding(get: { Double(step) }, set: { step = Int($0) }),
                in: Double(QuickAddSteps.range.lowerBound)...Double(QuickAddSteps.range.upperBound),
                step: 1)
        }
        .animation(.snappy(duration: 0.2), value: step)
    }
}

/// The quick-add step for one mantra (or no mantra), saved as it changes. The mantra's page and
/// the pause screen.
struct QuickAddStepRow: View {
    let mantra: MantraModel?
    @Environment(\.modelContext) private var context
    @AppStorage(QuickAddSteps.noMantraKey) private var noMantraStep = 0

    var body: some View {
        QuickAddStepper(step: Binding(
            get: { mantra?.quickAddStep ?? noMantraStep },
            set: { newValue in
                if let mantra {
                    mantra.quickAddStep = newValue
                    try? context.save()
                } else {
                    noMantraStep = newValue
                }
            }))
    }
}

/// The pause screen's ✎: the mantra card itself, editable — the same glass card, name in the
/// same light type, the full mantra in its inset box, notes, quick add — over the pause
/// screen's colour (owner, 2026-09-25: the Form editor was "a really ugly view" after that card).
/// Opens straight into editing; Save stays gray until something changes, and a swipe can't
/// throw away edits.
struct MantraCardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMantras: [MantraModel]
    let mantra: MantraModel

    @State private var name: String
    @State private var fullText: String
    @State private var notes: String
    @State private var quickAdd: Int

    init(mantra: MantraModel) {
        self.mantra = mantra
        _name = State(initialValue: mantra.name)
        _fullText = State(initialValue: mantra.fullText)
        _notes = State(initialValue: mantra.notes)
        _quickAdd = State(initialValue: mantra.quickAddStep)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool {
        let lower = trimmedName.lowercased()
        return allMantras.contains { $0.name.lowercased() == lower && $0.persistentModelID != mantra.persistentModelID }
    }
    private var hasEdits: Bool {
        name != mantra.name || fullText != mantra.fullText || notes != mantra.notes || quickAdd != mantra.quickAddStep
    }
    private var canSave: Bool { hasEdits && !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            ScrollView {
                MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: $quickAdd,
                                 isDuplicate: isDuplicate)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color("pauseColor").ignoresSafeArea())
            .fontDesign(.rounded)
            .navigationTitle("Edit mantra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasEdits)
        }
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave else { return }
        dismissKeyboard()
        mantra.name = trimmedName
        mantra.fullText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        mantra.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        mantra.quickAddStep = quickAdd
        for task in mantra.tasks { task.mantraName = trimmedName }   // as MantraEditorView does
        try? context.save()
        triggerSomeVibration(type: .success)
        dismiss()
    }
}

/// A mantra as the pause card shows it, editable: the name in large light type, the full mantra
/// in its centred inset box, notes beside the note icon, then count in sets. No background —
/// the pause-screen editor puts it on glass, the Mantras page on a grouped card.
struct MantraCardFields: View {
    @Binding var name: String
    @Binding var fullText: String
    @Binding var notes: String
    @Binding var quickAdd: Int
    var isDuplicate = false
    @FocusState private var focus: Field?
    private enum Field { case name, fullText, notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("name", text: $name)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .autocorrectionDisabled(true)
                    .focused($focus, equals: .name)
                if isDuplicate {
                    Text("another mantra already has this name")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            editorBox(text: $fullText, field: .fullText,
                      placeholder: "the full mantra — Arabic, transliteration, meaning",
                      minHeight: 110, centered: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 9)
                editorBox(text: $notes, field: .notes,
                          placeholder: "notes — why or when you read it, who taught you",
                          minHeight: 70, centered: false, inset: false)
            }
            .font(.footnote)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
            QuickAddStepper(step: $quickAdd)
                .font(.subheadline)
        }
        .fontDesign(.rounded)
    }

    /// A text editor with a placeholder, in the card's inset box (or bare, for notes).
    private func editorBox(text: Binding<String>, field: Field, placeholder: String,
                           minHeight: CGFloat, centered: Bool, inset: Bool = true) -> some View {
        ZStack(alignment: centered ? .top : .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .padding(.top, 8)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .multilineTextAlignment(centered ? .center : .leading)
                .focused($focus, equals: field)
                .frame(minHeight: minHeight)
        }
        .font(centered ? .system(size: 17, weight: .light, design: .rounded) : .subheadline)
        .padding(.horizontal, inset ? 8 : 0)
        .padding(.vertical, inset ? 4 : 0)
        .background {
            if inset {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04))
            }
        }
    }
}

/// Zikr History and Mantras as one page (2026-09-25 — owner: they're the same subject and
/// shouldn't be two hamburger rows): a History | Mantras switch in the navigation bar over the
/// two existing pages. Reached from the Zikr tab's top-left button (the hamburger stays on
/// Salah), and from the old routes (`showZikrHistory` / `showMantrasPage`).
struct ZikrLibraryView: View {
    enum Tab: String, CaseIterable { case history = "History", mantras = "Mantras" }
    @State private var tab: Tab

    init(start: Tab) { _tab = State(initialValue: start) }

    var body: some View {
        Group {
            switch tab {
            case .history: HistoryPageView()
            case .mantras: MantrasView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: tab)
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
    @State private var quickAdd: Int

    init(mantra: MantraModel?) {
        self.mantra = mantra
        _name = State(initialValue: mantra?.name ?? "")
        _fullText = State(initialValue: mantra?.fullText ?? "")
        _notes = State(initialValue: mantra?.notes ?? "")
        _quickAdd = State(initialValue: mantra?.quickAddStep ?? 0)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another mantra (other than the one being edited) already uses this name.
    private var isDuplicate: Bool {
        let lower = trimmedName.lowercased()
        return allMantras.contains { $0.name.lowercased() == lower && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var hasEdits: Bool {
        guard let mantra else { return true }
        return name != mantra.name || fullText != mantra.fullText || notes != mantra.notes
            || quickAdd != mantra.quickAddStep
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    /// Restyled 2026-09-25 to match the pause screen (owner: "very plain"): the same card as
    /// its ✎ editor, the lifetime stats as `ZikrBento` tiles, and sessions grouped by day like
    /// Zikr History.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: $quickAdd,
                                     isDuplicate: isDuplicate)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground)))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let mantra {
                    Section {
                        ZikrBento(count: mantra.totalCount, seconds: mantra.totalSeconds,
                                  secondsPerCount: mantra.secondsPerCount ?? 0,
                                  perTasbeeh: mantra.secondsPerCount.map { zikrDurationString($0 * 100) } ?? "–",
                                  timeText: zikrDurationString(mantra.totalSeconds),
                                  countCaption: "total count", timeCaption: "total time", grouped: true)
                    } header: {
                        Text("Lifetime")
                            .padding(.leading, 16)   // the zero row insets pull the header left too
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Section("Tasks") {
                        MantraTaskRows(mantra: mantra)
                    }
                    MantraSessionsSection(mantra: mantra)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .fontDesign(.rounded)
            // Opening a mantra is mostly for its stats: title is its name, and Cancel / Save
            // only appear once a field actually changes (a new mantra always has them).
            .navigationTitle(mantra?.name ?? "New Mantra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasEdits {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelEdits() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: hasEdits)
            // Don't lose typed edits to a swipe; with no edits it swipes away like any sheet.
            .interactiveDismissDisabled(mantra != nil && hasEdits)
        }
    }

    private func save() {
        guard canSave else { return }
        dismissKeyboard()
        let fullTextTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mantra {
            mantra.name = trimmedName
            mantra.fullText = fullTextTrimmed
            mantra.notes = notesTrimmed
            mantra.quickAddStep = quickAdd
            // Tasks read the live name through the relationship; keep their snapshot in step too
            // so a later deletion still shows the right name. Sessions keep their historical title.
            for task in mantra.tasks { task.mantraName = trimmedName }
            // Stay on the mantra: the fields now match it, so Cancel / Save go away.
            withAnimation {
                name = mantra.name; fullText = mantra.fullText; notes = mantra.notes; quickAdd = mantra.quickAddStep
            }
            triggerSomeVibration(type: .light)
        } else {
            let new = MantraModel(name: trimmedName, fullText: fullTextTrimmed, notes: notesTrimmed)
            new.quickAddStep = quickAdd
            context.insert(new)
            dismiss()
        }
    }

    /// Existing mantra: put the fields back as they were (the sheet stays). New: close.
    private func cancelEdits() {
        dismissKeyboard()
        guard let mantra else { dismiss(); return }
        withAnimation {
            name = mantra.name; fullText = mantra.fullText; notes = mantra.notes; quickAdd = mantra.quickAddStep
        }
    }
}

#Preview {
    NavigationStack {
        MantrasView()
    }
    .modelContainer(for: [MantraModel.self, TaskModel.self, SessionDataModel.self], inMemory: true)
}


// MARK: - Editor: tasks, sessions

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
        let todayStart = PrayerDay.sessionDayStart()   // the prayer day, rollover included
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

    /// A section per day, headed "Today · 249 counted" — the same look as Zikr History.
    var body: some View {
        if mantra.sessions.isEmpty {
            Section("Sessions") {
                Text("No sessions with this mantra yet.").foregroundStyle(.secondary)
            }
        } else {
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.sessions) { session in SessionRow(session: session, showsMantraName: false) }
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
