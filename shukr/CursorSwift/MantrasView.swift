//
//  MantrasView.swift
//  shukr
//
//  The Azkar library (code name "mantra"). A zikr has a short `name` (what cards, the picker and
//  session titles show), the `fullText` (Arabic / transliteration), free `notes`, a photo and a
//  voice memo. Built-ins (`builtInID`) are locked: name and text fixed, never deleted. Tasks and
//  sessions point at the row, so a rename shows everywhere. Deleting a zikr deletes its tasks too
//  (and their reminders); its sessions stay in history under their saved title
//  (`MantraModel.delete`). No bulk delete: one zikr at a time, from its own page (owner,
//  2026-09-27, feedback D505E0DE — a bulk Edit made a destructive choice too quick).
//

import SwiftUI
import SwiftData
import WidgetKit

struct MantrasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var mantras: [MantraModel]

    @State private var editingMantra: MantraModel? = nil
    @State private var showingNewMantra = false
    @State private var search = ""
    /// Inside `ZikrLibraryView`: the library owns the search field, the + and the sort button
    /// (both pages stay mounted side by side, so a page's own toolbar / search would show on the
    /// other page).
    var embedded = false
    var externalSearch = ""

    /// Matches the name, the full wording or the notes.
    private var query: String { (embedded ? externalSearch : search).trimmingCharacters(in: .whitespaces) }
    private var shown: [MantraModel] {
        let q = query
        guard !q.isEmpty else { return mantras }
        return mantras.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.fullText.localizedCaseInsensitiveContains(q)
                || $0.notes.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        if embedded {
            list
        } else {
            list
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search azkar")
                .navigationTitle("Azkar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { AzkarSortButton() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewMantra = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.green.opacity(0.7))
                        }
                    }
                }
                .sheet(isPresented: $showingNewMantra) {
                    MantraEditorView(mantra: nil)
                }
        }
    }

    private var list: some View {
        List {
            if mantras.isEmpty {
                Text("No azkar yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("No azkar match “\(query)”.")
                    .foregroundStyle(.secondary)
            } else {
                // Built-ins apart from the user's own (owner, 2026-09-27); they can't be deleted.
                let builtIns = sorted(shown.filter(\.isBuiltIn), builtIn: true)
                let own = sorted(shown.filter { !$0.isBuiltIn }, builtIn: false)
                // Yours first, built-ins below (owner, 2026-09-27, feedback 6B1CFEB8 — it replaced
                // a folding Built-in header).
                Section {
                    if own.isEmpty {
                        Text(query.isEmpty ? "Your own azkar go here. Tap + to add one." : "None of yours match.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(own) { row($0) }
                } header: {
                    Text("Your azkar")
                }
                // Built-ins always show, below yours (owner, 2026-09-27, feedback ADD5836A: the
                // "Show built-ins" switch is gone).
                if !builtIns.isEmpty {
                    Section("Built-in") {
                        ForEach(builtIns) { row($0) }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        // The old "only mine" filter's setting (2026-09-27, removed): don't leave it behind.
        .onAppear {
            UserDefaults.standard.removeObject(forKey: "azkar.hideBuiltIns")
            AzkarSort.migrateStoredDefault()
        }
        .sheet(item: $editingMantra) { mantra in
            MantraEditorView(mantra: mantra)
        }
    }

    /// The sort menu (the library's toolbar, or this page's own): one field + a direction, both
    /// remembered, applied within each section.
    @AppStorage(AzkarSort.key) private var sortRaw = AzkarSort.name.rawValue
    @AppStorage(AzkarSort.ascendingKey) private var ascending = true
    private var hasOwn: Bool { mantras.contains { !$0.isBuiltIn } }

    /// Within a section. Stats come from each zikr's sessions, worked out once per call.
    private func sorted(_ list: [MantraModel], builtIn: Bool) -> [MantraModel] {
        let sort = AzkarSort(rawValue: sortRaw) ?? .name
        // Ties (same count, never used, no pace…) keep the section's own order: the built-ins'
        // curated order, yours A–Z. Swift's sort isn't stable, so it's an explicit tiebreak.
        let rank: [PersistentIdentifier: Int] = Dictionary(uniqueKeysWithValues: list
            .sorted { builtIn ? BuiltInAzkar.order($0.name) < BuiltInAzkar.order($1.name)
                              : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .enumerated().map { ($1.persistentModelID, $0) })
        let tie = { (a: MantraModel, b: MantraModel) in (rank[a.persistentModelID] ?? 0) < (rank[b.persistentModelID] ?? 0) }
        // Missing data (never recited / used, no pace yet) goes last in either direction.
        func by<T: Comparable>(_ value: (MantraModel) -> T?) -> [MantraModel] {
            let v = Dictionary(uniqueKeysWithValues: list.map { ($0.persistentModelID, value($0)) })
            return list.sorted {
                switch (v[$0.persistentModelID] ?? nil, v[$1.persistentModelID] ?? nil) {
                case let (a?, b?): return a == b ? tie($0, $1) : (ascending ? a < b : a > b)
                case (_?, nil): return true
                case (nil, _?): return false
                default: return tie($0, $1)
                }
            }
        }
        switch sort {
        case .name:
            return list.sorted {
                let r = $0.name.localizedCaseInsensitiveCompare($1.name)
                return r == .orderedSame ? tie($0, $1) : (ascending ? r == .orderedAscending : r == .orderedDescending)
            }
        case .timesRecited:
            return by { m in let c = m.totalCount; return c > 0 ? c : nil }
        case .lastUsed:
            return by { $0.sessions.map(\.startTime).max() }
        case .pace:
            return by { $0.secondsPerCount }
        }
    }

    private func row(_ mantra: MantraModel) -> some View {
        Button {
            editingMantra = mantra
        } label: {
            ZikrListRow(mantra: mantra)
        }
        .tint(.primary) // rows, not links
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }
}

extension MantraModel {
    /// The one way to delete a zikr. Its tasks go with it (a task left with only the name
    /// snapshot would bring the zikr back on the next launch's data pass) and so do their
    /// reminders; its sessions stay in history under their saved title. Built-ins never.
    @MainActor static func delete(_ mantra: MantraModel, in context: ModelContext) {
        guard !mantra.isBuiltIn else { return }
        let tasks = Array(mantra.tasks)              // a copy: deleting edits the relationship
        let taskIDs = Set(tasks.map(\.id)), taskModels = Set(tasks.map(\.persistentModelID))
        for task in tasks { context.delete(task) }
        context.delete(mantra)
        try? context.save()
        if !tasks.isEmpty {
            NotificationScheduler.reschedule(context: context, reason: "zikr deleted")
            WidgetCenter.shared.reloadAllTimelines()
            TaskModel.deleted(taskIDs, models: taskModels)
        }
    }

    /// What deleting it does, for the confirmation.
    static func deleteMessage(_ mantra: MantraModel) -> String {
        let t = mantra.tasks.count, n = mantra.sessions.count
        let tasks = t == 0 ? "" : (t == 1 ? "Its task is deleted too. " : "Its \(t) tasks are deleted too. ")
        let sessions = n == 0 ? "" : (n == 1 ? "Its session stays in your history. " : "Its \(n) sessions stay in your history. ")
        return tasks + sessions + "This can't be undone."
    }
}


/// One zikr as the Azkar list shows it: name, the full text on one line, lifetime count and pace,
/// a note mark. Shared with the zikr picker (`MantraPickerView`), which trails a check instead of
/// the chevron.
struct ZikrListRow: View {
    let mantra: MantraModel
    var selected = false
    var showsChevron = true

    var body: some View {
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
            if selected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}


/// "Count in sets  [off / +5]  [− | +]" bound to any step value (the editor's draft, or live).
/// Shown as "count in sets" (owner, 2026-09-25: "quick add" didn't say what it's for — you
/// recite a set on your own, counting on your fingers or in your head, then tap once).
struct QuickAddStepper: View {
    @Binding var step: Int
    /// false: the − / + stay in place (so nothing moves) but are hidden and inert.
    var adjustable = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Count in sets")
                Text(step > 0 ? "on, each tap counts \(step)" : "recite a set, tap once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                // 1 is skipped (off → 2 → 3…): one per tap is what tapping the screen already does.
                value: Binding(get: { Double(step) }, set: { newValue in
                    let n = Int(newValue)
                    step = n == 1 ? (step == 0 ? 2 : 0) : n
                }),
                in: Double(QuickAddSteps.range.lowerBound)...Double(QuickAddSteps.range.upperBound),
                step: 1)
                .opacity(adjustable ? 1 : 0)
                .allowsHitTesting(adjustable)
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
    /// The photo / voice memo are part of the edit (owner, 2026-09-27: adding one left Save grey —
    /// it had quietly saved already): drafts until Save, dropped by Cancel.
    @State private var draftImage: Data?
    @State private var draftAudio: Data?
    @State private var mediaEdited = false
    @State private var recording = false
    /// Set while Cancel throws a take in progress away, so it doesn't land in the draft.
    @State private var discarding = false
    @State private var confirmDiscard = false

    init(mantra: MantraModel) {
        self.mantra = mantra
        _name = State(initialValue: mantra.name)
        _fullText = State(initialValue: mantra.fullText)
        _notes = State(initialValue: mantra.notes)
        _quickAdd = State(initialValue: mantra.quickAddStep)
        _draftImage = State(initialValue: mantra.imageData)
        _draftAudio = State(initialValue: mantra.audioData)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool {
        let key = BuiltInAzkar.key(trimmedName)   // the same match as seeding ("Subhan Allah" = "Subhanallah")
        return allMantras.contains { BuiltInAzkar.key($0.name) == key && $0.persistentModelID != mantra.persistentModelID }
    }
    private var hasEdits: Bool {
        name != mantra.name || fullText != mantra.fullText || notes != mantra.notes || quickAdd != mantra.quickAddStep
            || mediaEdited || recording
    }
    private var canSave: Bool { hasEdits && !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            ScrollView {
                MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: $quickAdd,
                                 imageData: draft($draftImage), audioData: draft($draftAudio),
                                 isDuplicate: isDuplicate, identityLocked: mantra.isBuiltIn)
                    .onPreferenceChange(MemoRecordingKey.self) { recording = $0 }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color("pauseColor").ignoresSafeArea())
            .fontDesign(.rounded)
            .navigationTitle("Edit zikr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissKeyboard()
                        if hasEdits { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SaveButton(enabled: canSave) { save() }
                }
            }
            .interactiveDismissDisabled(hasEdits)
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) {
                    discarding = true
                    ZikrAudio.stopAll()          // a take in progress goes too
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your edits, photo and voice memo changes aren't saved.")
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { ZikrAudio.stopAll() }   // really closed: keep a take, stop playback
    }

    /// A photo / memo change waits in the draft (and marks the edit) until Save.
    private func draft(_ value: Binding<Data?>) -> Binding<Data?> {
        Binding(get: { value.wrappedValue }, set: { new in
            guard !discarding else { return }
            value.wrappedValue = new
            mediaEdited = true
        })
    }

    private func save() {
        ZikrAudio.stopAll()   // a take in progress is finished into the draft (synchronously) and kept
        guard canSave else { return }
        dismissKeyboard()
        if mediaEdited {
            mantra.imageData = draftImage
            mantra.audioData = draftAudio
        }
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
    /// The photo and voice memo (notes #17), shown in the notes box's other two tabs.
    @Binding var imageData: Data?
    @Binding var audioData: Data?
    var isDuplicate = false
    /// Viewing: fields locked. Editing: the name, full mantra and notes each sit in a box with a
    /// sage edge (the full mantra's box shows either way). Every field keeps the box's padding
    /// in both modes, so switching moves nothing (owner). Count in sets is always adjustable.
    var editable = true
    /// A built-in: its name and full text stay as they are (notes, memo, photo, sets are the
    /// user's) — owner, 2026-09-27.
    var identityLocked = false
    @FocusState private var focus: Field?
    private enum Field { case name, fullText, notes }
    /// Which of notes / voice memo / photo the box shows. The box keeps one size for all three
    /// (owner, 2026-09-27: nothing on the card or page may move when switching).
    enum Pane: CaseIterable { case notes, memo, photo
        var symbol: String { switch self { case .notes: "doc.text"; case .memo: "waveform"; case .photo: "photo" } }
        var label: String { switch self { case .notes: "Notes"; case .memo: "Voice memo"; case .photo: "Photo" } }
    }
    /// The card's one audio engine (VoiceMemoPanel only borrows it), so a take survives tab
    /// switches and List cell recycling. Leaving the memo tab finishes it; the sheets call
    /// `ZikrAudio.stopAll()` when they really close.
    @State private var audio = ZikrAudio()
    @State private var pane: Pane = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "demoZikrPane") { case "memo": return .memo; case "photo": return .photo; default: break }
        #endif
        return .notes
    }()
    static let paneHeight: CGFloat = 132

    var body: some View {
        // Re-wired on every render, so a take always lands in the card's current binding (one
        // captured once in onAppear could go stale if the parent handed in a new one).
        let _ = wireRecorder()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("name", text: $name)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .autocorrectionDisabled(true)
                    .focused($focus, equals: .name)
                    .disabled(!editable || identityLocked)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(fieldBox(alwaysFilled: false, editing: editable && !identityLocked))
                    // Built-in: a small lock in the field while editing (an overlay, so nothing moves).
                    .overlay(alignment: .trailing) {
                        if identityLocked && editable {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.trailing, 10)
                                .accessibilityLabel("Built-in: name and text can't be changed")
                        }
                    }
                if isDuplicate {
                    Text("another zikr already has this name")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            editorBox(text: $fullText, field: .fullText,
                      placeholder: "the full zikr — Arabic, transliteration, meaning",
                      minHeight: 110, centered: true, enabled: !identityLocked)

            HStack(alignment: .top, spacing: 8) {
                // doc.text / waveform / photo, top to bottom — tabs for the box beside them.
                VStack(spacing: 6) {
                    ForEach(Pane.allCases, id: \.self) { p in
                        paneButton(p)
                    }
                }
                ZStack {
                    switch pane {
                    case .memo:
                        VoiceMemoPanel(audio: $audioData, engine: audio)
                            .padding(8)
                            .background(fieldBox(alwaysFilled: true))
                            .transition(.opacity)
                    case .photo:
                        ZikrPhotoPanel(image: $imageData)
                            .padding(imageData != nil ? 0 : 8)
                            .background(fieldBox(alwaysFilled: true))
                            .transition(.opacity)
                    case .notes:
                        notesPane
                            .transition(.opacity)
                    }
                }
                .frame(height: Self.paneHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(.easeInOut(duration: 0.22), value: pane)
            }
            .font(.footnote)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
            QuickAddStepper(step: $quickAdd)
                .font(.subheadline)
        }
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.2), value: editable)
        .onChange(of: editable) { _, on in if !on { focus = nil } }
        .onChange(of: pane) { old, _ in
            if old == .memo { audio.finishRecording(); audio.stopPlaying() }
        }
        .preference(key: MemoRecordingKey.self, value: audio.state == .recording)
    }

    private func wireRecorder() {
        let binding = $audioData
        audio.onRecorded = { data in
            binding.wrappedValue = data
            triggerSomeVibration(type: .success)
        }
    }

    /// The notes tab: the editor while editing, else the notes as text in the same box.
    private var notesPane: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if editable {
                editorBox(text: $notes, field: .notes,
                          placeholder: "notes — why or when you read it, who taught you",
                          minHeight: Self.paneHeight - 8, centered: false, inset: false)
            } else {
                // Long notes scroll inside the box; short ones don't bounce.
                ScrollView {
                    Text(notes.isEmpty ? "no notes yet" : notes)
                        .font(.subheadline)
                        .foregroundStyle(notes.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        // Same filled box as the memo / photo tabs (editing draws its own).
        .background { if !editable { fieldBox(alwaysFilled: true) } }
    }

    /// A tab in the left column: highlighted when selected; a small dot when that tab has something.
    private func paneButton(_ p: Pane) -> some View {
        let selected = pane == p
        let filled = switch p {
        case .notes: !notes.isEmpty
        case .memo: audioData != nil
        case .photo: imageData != nil
        }
        return Button {
            guard pane != p else { return }
            focus = nil
            pane = p
        } label: {
            Image(systemName: p.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.sage : (filled ? Color.secondary : Color(.tertiaryLabel)))
                .frame(width: 34, height: 34)
                .background(Circle().fill(selected ? Color.sage.opacity(0.16) : Color.clear))
                .overlay(alignment: .topTrailing) {
                    if filled && !selected {
                        Circle().fill(Color.sage).frame(width: 5, height: 5).offset(x: -5, y: 6)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(p.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A text editor with a placeholder, in the card's inset box (or bare, for notes).
    private func editorBox(text: Binding<String>, field: Field, placeholder: String,
                           minHeight: CGFloat, centered: Bool, inset: Bool = true, enabled: Bool = true) -> some View {
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
                .disabled(!editable || !enabled)
                .foregroundStyle(.primary)
        }
        .font(centered ? .system(size: 17, weight: .light, design: .rounded) : .subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(fieldBox(alwaysFilled: inset, editing: editable && enabled))
    }

    /// The box behind a field: filled always (`alwaysFilled`, the full mantra) or only while
    /// editing, with a sage edge while editing. Drawn behind fixed padding, so it never moves
    /// anything.
    private func fieldBox(alwaysFilled: Bool, editing: Bool? = nil) -> some View {
        let on = editing ?? editable
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(Color.primary.opacity(alwaysFilled || on ? 0.04 : 0))
            .overlay(shape.stroke(Color.sage.opacity(on ? 0.45 : 0), lineWidth: 1))
    }
}

/// True while the card is recording a voice memo (a new zikr's sheet won't swipe away then).
struct MemoRecordingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Save in a sheet's bar: green text when there's something to save, gray otherwise (owner,
/// 2026-09-25 — a filled green button was too much).
struct SaveButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Save")
                .fontWeight(.semibold)
                .foregroundStyle(enabled ? Color.green : Color.secondary)
        }
        .disabled(!enabled)
    }
}

/// Zikr History and Azkar as one page (2026-09-25 — owner: they're the same subject and
/// shouldn't be two hamburger rows): a History | Azkar switch in the navigation bar over the two
/// pages. Reached from the Zikr tab's top-left button (the hamburger stays on Salah), and from
/// the old routes (`showZikrHistory` / `showMantrasPage`).
///
/// **A native paging ScrollView** since 2026-09-27 (owner: paging was laggy). The hand-made pager
/// changed `@State dragX` every frame, re-rendering both big lists each time. Now the scrolling is
/// UIKit's, with no SwiftUI state per frame; the switch follows `scrollPosition`. It only
/// existed so rows could keep sideways swipes, and neither page has any now (History deletes via
/// Edit → select → Delete; Azkar has no bulk delete — its top-right slot is the sort button).
struct ZikrLibraryView: View {
    enum Tab: String, CaseIterable, Hashable { case history = "History", mantras = "Azkar" }
    /// The page, bound to the pager's scroll position (nil while between pages).
    @State private var page: Tab?
    /// The switch's value: follows the page once it settles; a tap scrolls there.
    @State private var tab: Tab
    @State private var search = ""
    @State private var showingNewMantra = false
    /// History's Edit mode (select → Delete); its button lives in this bar.
    @State private var editingHistory = false
    /// Held while the history chart is being scrubbed (and while editing): no paging.
    @State private var lock = LibraryPagerLock()

    /// Just whether there's any session (History's Edit hides without). Trap from an earlier
    /// version: a `#Predicate { $0.builtInID == nil }` query here looped SwiftUI's layout at
    /// 100 % CPU (the library never appeared).
    @Query private var anySession: [SessionDataModel]

    private let start: Tab

    init(start: Tab) {
        self.start = start
        _tab = State(initialValue: start)
        _page = State(initialValue: start)
        var one = FetchDescriptor<SessionDataModel>()
        one.fetchLimit = 1
        _anySession = Query(one)

    }

    private var editing: Bool { editingHistory }
    /// What the pages filter by: a stray space doesn't count as a search (it hid the built-ins'
    /// filter state and redrew both pages for nothing).
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }
    private var showsEdit: Bool { tab == .history && !anySession.isEmpty }
    /// The top-right slot's fixed width: "Done" / "Edit", or the sort pill (field + arrow).
    static let trailingSlotWidth: CGFloat = 50

    private static var bottomBarPlus: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    private var newZikrButton: some View {
        Button {
            showingNewMantra = true
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
        }
        .accessibilityLabel("New zikr")
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // Each page redraws only when its own inputs change: the library's body runs on every
                // page turn (the scroll position, the switch, the toolbar), and without these walls
                // both lists — History regrouping every session — redrew three times mid-swipe (owner:
                // paging lagged).
                LibraryPage(search: trimmedSearch, editing: $editingHistory) { search, editing in
                    HistoryPageView(search: search, editing: editing)
                }
                .equatable()
                .scrollDisabled(false)          // the lists keep scrolling while paging is off
                .containerRelativeFrame(.horizontal)
                .id(Tab.history)
                LibraryPage(search: trimmedSearch, editing: .constant(false)) { search, _ in
                    MantrasView(embedded: true, externalSearch: search)
                }
                .equatable()
                .scrollDisabled(false)
                .containerRelativeFrame(.horizontal)
                .id(Tab.mantras)
            }
            .scrollTargetLayout()
        }
        // Editing (a sideways drag would page and drop the selection) or scrubbing the chart.
        .scrollDisabled(editing || lock.locked)
        .scrollTargetBehavior(.paging)
        // Anchored at the centre: the switch changes past halfway, not on the first pixel of a drag.
        .scrollPosition(id: $page, anchor: .center)
        // The first layout ignores the initial scroll position: start on the right page.
        .defaultScrollAnchor(start == .mantras ? .trailing : .leading)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .environment(lock)
        .onChange(of: page) { _, new in
            PaceCoordinator.stopAll()          // a pace on the page left behind stops
            if let new, new != tab { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = new } }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // `.toolbar`: the field lives only where the toolbar puts it (the bottom-bar item above on
        // iOS 26) — with the automatic placement it could also draw its own, a second field.
        .searchable(text: $search, placement: .toolbar, prompt: tab == .history ? "Search sessions" : "Search azkar")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: Binding(get: { tab }, set: { new in
                    tab = new
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { page = new }
                })) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .disabled(editing)
            }
            // Top right: History's Edit, or Azkar's sort button in the same spot (owner, 2026-09-27,
            // feedback D505E0DE: no bulk edit for azkar, and the sort button gets room for its
            // field + direction icons). One toolbar item throughout: two items swapped on every page
            // turn and redrew themselves (owner).
            // Always there and always `trailingSlotWidth` wide (feedback 1F97A704): the switcher is
            // centred in the space the bar leaves it, so a wider sort pill, or Edit going away with
            // no sessions, pushed History | Azkar sideways. Edit greys out instead of vanishing.
            ToolbarItem(id: "libraryTrailing", placement: .topBarTrailing) {
                Group {
                    if tab == .mantras {
                        AzkarSortButton()
                    } else {
                        Button(editing ? "Done" : "Edit") {
                            withAnimation { editingHistory.toggle() }
                        }
                        .fontWeight(editing ? .semibold : .regular)
                        .disabled(!showsEdit)
                    }
                }
                .frame(width: Self.trailingSlotWidth)
            }
            // iOS 18: the ＋ stays top right (iOS 26 puts it by the search field).
            if tab == .mantras && !Self.bottomBarPlus {
                ToolbarItem(placement: .topBarTrailing) { newZikrButton }
            }
            // iOS 26: the search field in the bottom bar, with the ＋ beside it on Azkar — it
            // animates in as the page turns (owner, 2026-09-27).
            if #available(iOS 26.0, *) {
                if !editing {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
                if tab == .mantras {
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { newZikrButton }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tab)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: tab) { _, _ in editingHistory = false }
        .sheet(isPresented: $showingNewMantra) {
            MantraEditorView(mantra: nil)
        }
    }
}

/// A library page behind an equality wall: it redraws only when the search or its own edit mode
/// changes (a Binding is never equal to the last one, so the value is compared instead).
private struct LibraryPage<Content: View>: View, Equatable {
    let search: String
    let editing: Binding<Bool>
    let content: (String, Binding<Bool>) -> Content

    var body: some View { content(search, editing) }

    static func == (a: Self, b: Self) -> Bool {
        a.search == b.search && a.editing.wrappedValue == b.editing.wrappedValue
    }
}

/// How the Azkar list is ordered, within each section: one field and a direction, Notion-style
/// (owner, 2026-09-27, feedback ADD5836A — it was a list of opposite pairs). The default is Name,
/// A to Z, for both sections (feedback F5FDC4C1: no separate "Default"; the built-ins go
/// alphabetical too).
enum AzkarSort: String, CaseIterable, Identifiable {
    case name, timesRecited, pace, lastUsed
    static let key = "azkar.sortField"
    static let ascendingKey = "azkar.sortAscending"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .timesRecited: "Times recited"
        case .pace: "Pace"
        case .lastUsed: "Last used"
        }
    }
    var symbol: String {
        switch self {
        case .name: "textformat"
        case .timesRecited: "number"
        case .pace: "gauge.with.needle"
        case .lastUsed: "clock"
        }
    }
    /// The result of each direction, one short line (the arrow icon carries ↑ / ↓).
    func meaning(ascending: Bool) -> String {
        switch self {
        case .name: ascending ? "A to Z" : "Z to A"
        case .timesRecited: ascending ? "Fewest first" : "Most first"
        case .pace: ascending ? "Fastest first" : "Slowest first"      // seconds per count, low → high
        case .lastUsed: ascending ? "Oldest first" : "Recent first"
        }
    }
    /// The direction a field starts in when picked (the natural one); the toggle flips it.
    var naturalAscending: Bool { self == .name || self == .pace }

    /// A stored "standard" (the old Default) or anything unknown becomes Name, A to Z.
    static func migrateStoredDefault() {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key), AzkarSort(rawValue: raw) == nil else { return }
        d.set(AzkarSort.name.rawValue, forKey: key)
        d.set(true, forKey: ascendingKey)
    }
}

/// The sort menu: pick a field, then ↑ / ↓. On the default (Name, A to Z) the icon is the plain
/// sort glyph; otherwise the field's symbol with an arrow for the direction, green on a soft green
/// tint so an active sort shows (owner, 2026-09-27, feedback D505E0DE; a solid green fill was too
/// stark).
struct AzkarSortButton: View {
    @AppStorage(AzkarSort.key) private var sortRaw = AzkarSort.name.rawValue
    @AppStorage(AzkarSort.ascendingKey) private var ascending = true

    private var sort: AzkarSort { AzkarSort(rawValue: sortRaw) ?? .name }
    private var isDefault: Bool { sort == .name && ascending }

    var body: some View {
        Menu {
            Picker("Sort by", selection: Binding(get: { sort.rawValue }, set: { new in
                withAnimation(.snappy(duration: 0.25)) {
                    sortRaw = new
                    ascending = (AzkarSort(rawValue: new) ?? .name).naturalAscending
                }
            })) {
                ForEach(AzkarSort.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Picker("Direction", selection: Binding(get: { ascending }, set: { up in
                withAnimation(.snappy(duration: 0.25)) { ascending = up }
            })) {
                Label(sort.meaning(ascending: true), systemImage: "arrow.up").tag(true)
                Label(sort.meaning(ascending: false), systemImage: "arrow.down").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .tint(isDefault ? Color.primary : Color.green)
        .onAppear { AzkarSort.migrateStoredDefault() }
        .accessibilityLabel("Sorted by \(sort.title), \(sort.meaning(ascending: ascending))")
        .sensoryFeedback(.selection, trigger: sortRaw)
        .sensoryFeedback(.selection, trigger: ascending)
    }
}

extension AzkarSortButton {
    /// The field's symbol + ↑ / ↓ when sorted; the plain glyph on the default.
    @ViewBuilder fileprivate var label: some View {
        if isDefault {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(Color.primary)
        } else {
            HStack(spacing: 3) {
                Image(systemName: sort.symbol)
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.green)
            // The app's tinted look (like the active chips / Save), not a solid fill — owner: the
            // filled prominent button was too stark. It fills the slot (ZikrLibraryView's
            // `trailingSlotWidth`), never wider than Edit.
            .frame(width: ZikrLibraryView.trailingSlotWidth, height: 36)
            // The whole slot (the item clips at its frame, so it can't bleed out to the glass
            // edge): a thin rim instead of the old wide dark ring round a 30 pt capsule.
            .background(Capsule().fill(Color.green.opacity(0.16)))
        }
    }
}

/// Held while something on a library page owns sideways drags (the history chart scrubbing).
@Observable final class LibraryPagerLock {
    var locked = false
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
    /// A new zikr's photo / memo wait here until Save; an existing one's save straight to it.
    @State private var draftImage: Data?
    @State private var draftAudio: Data?
    @State private var showTitle = false
    /// Viewing by default; the pencil unlocks the fields in place (a new mantra starts editing).
    @State private var isEditing: Bool
    /// The task sheet for a new task with this zikr locked in (notes #17).
    @State private var creatingTask = false
    /// The card is recording a voice memo (a new zikr can't be swiped away then).
    @State private var recording = false
    @State private var confirmDiscard = false
    /// An existing zikr in ✎ mode: its photo / memo changes wait in the drafts until Save (read
    /// mode keeps saving them straight away). Cancel with changes asks first.
    @State private var mediaEdited = false
    @State private var discarding = false
    @State private var confirmDiscardChanges = false
    /// The sessions list's Edit → select → Delete (MantraSessionsSection draws the rows).
    @State private var sessionsEditing = false
    @State private var selectedSessions = Set<PersistentIdentifier>()
    @State private var confirmDeleteSessions = false
    @State private var confirmDelete = false
    /// Worked out when Delete is tapped, so nothing reads the row once it's gone.
    @State private var deleteTitle = ""
    @State private var deleteMessage = ""

    /// Create only: called with the new zikr once it's saved (the picker selects it).
    var onCreate: ((MantraModel) -> Void)? = nil

    init(mantra: MantraModel?, initialName: String = "", onCreate: ((MantraModel) -> Void)? = nil) {
        self.mantra = mantra
        self.onCreate = onCreate
        _name = State(initialValue: mantra?.name ?? initialName.trimmingCharacters(in: .whitespacesAndNewlines))
        _fullText = State(initialValue: mantra?.fullText ?? "")
        _notes = State(initialValue: mantra?.notes ?? "")
        _quickAdd = State(initialValue: mantra?.quickAddStep ?? 0)
        _isEditing = State(initialValue: mantra == nil)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another mantra (other than the one being edited) already uses this name.
    private var isDuplicate: Bool {
        let key = BuiltInAzkar.key(trimmedName)   // the same match as seeding ("Subhan Allah" = "Subhanallah")
        return allMantras.contains { BuiltInAzkar.key($0.name) == key && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var hasEdits: Bool {
        guard let mantra else { return true }
        return name != mantra.name || fullText != mantra.fullText || notes != mantra.notes
            || (isEditing && (mediaEdited || recording))
    }

    /// Count in sets works without the pencil (owner): on an existing mantra each step saves
    /// straight to the row; a new mantra keeps it in the draft until Save.
    private var liveQuickAdd: Binding<Int> {
        guard let mantra else { return $quickAdd }
        return Binding(get: { mantra.quickAddStep }, set: { newValue in
            mantra.quickAddStep = newValue
            try? context.save()
        })
    }

    private var canSave: Bool {
        hasEdits && !trimmedName.isEmpty && !isDuplicate
    }

    /// A new zikr with anything in it — typed, recorded, a photo, sets — won't swipe away, and
    /// Cancel asks first (2026-09-27 review: it could be swiped away with a memo on it).
    private var newHasContent: Bool {
        guard mantra == nil else { return false }
        let t = { (s: String) in !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return t(name) || t(fullText) || t(notes) || quickAdd != 0 || draftImage != nil || draftAudio != nil || recording
    }

    /// Read mode on an existing zikr: saved straight to it. ✎ mode (and a new zikr): the draft.
    private func media(_ key: ReferenceWritableKeyPath<MantraModel, Data?>, draft: Binding<Data?>) -> Binding<Data?> {
        if let mantra, !isEditing {
            return Binding(get: { mantra[keyPath: key] }, set: { mantra[keyPath: key] = $0; try? context.save() })
        }
        return Binding(get: { draft.wrappedValue }, set: { new in
            guard !discarding else { return }
            draft.wrappedValue = new
            mediaEdited = true
        })
    }

    /// ✎ on an existing zikr: the drafts start as its current photo / memo.
    private func beginEditing() {
        if let mantra { draftImage = mantra.imageData; draftAudio = mantra.audioData }
        mediaEdited = false
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
    }

    /// Restyled 2026-09-25 to match the pause screen (owner: "very plain"): the same card as
    /// its ✎ editor, the lifetime stats as `ZikrBento` tiles, and sessions grouped by day like
    /// Zikr History.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: liveQuickAdd,
                                     imageData: media(\.imageData, draft: $draftImage),
                                     audioData: media(\.audioData, draft: $draftAudio),
                                     isDuplicate: isDuplicate, editable: isEditing,
                                     identityLocked: mantra?.isBuiltIn ?? false)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground)))
                        .onPreferenceChange(MemoRecordingKey.self) { recording = $0 }
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

                    Section {
                        MantraTaskCircles(mantra: mantra) { creatingTask = true }
                    } header: {
                        HStack(spacing: 10) {
                            Text("Tasks")
                            Spacer()
                            Text(mantra.tasks.count == 1 ? "1 task" : "\(mantra.tasks.count) tasks")
                            // With no tasks the dashed "New task" circle is the only way in (owner).
                            if !mantra.tasks.isEmpty {
                                Button { creatingTask = true } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.green)
                                        .frame(width: 28, height: 28)
                                        .mapGlass(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("New task with this zikr")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    MantraSessionsSection(mantra: mantra, editing: $sessionsEditing, selected: $selectedSessions)

                    // Only while editing, never for a built-in (owner, 2026-09-27).
                    if isEditing && !mantra.isBuiltIn {
                        Section {
                            Button(role: .destructive) {
                                deleteTitle = "Delete “\(mantra.name)”?"
                                deleteMessage = MantraModel.deleteMessage(mantra)
                                confirmDelete = true
                            } label: {
                                Text("Delete zikr")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .fontDesign(.rounded)
            // Nothing here changes the bar's height (owner: the page kept shifting as Cancel /
            // Save and the title came and went): the trailing slot always holds a button — the
            // pencil while viewing, Save while editing (green only with something to save) —
            // and the name in the bar only fades in once the card has scrolled away.
            .contentMargins(.top, 6, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 64
            } action: { _, scrolledPast in
                withAnimation(.easeInOut(duration: 0.2)) { showTitle = scrolledPast }
            }
            .navigationTitle(mantra?.name ?? "New Zikr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mantra == nil ? "New Zikr" : name)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(mantra == nil || showTitle ? 1 : 0)
                }
                // Only while editing; the trailing button alone keeps the bar's height fixed.
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelEdits() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        SaveButton(enabled: canSave) { save() }
                    } else {
                        Button {
                            triggerSomeVibration(type: .light)
                            beginEditing()
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit")
                    }
                }
            }
            // Don't lose typed edits to a swipe; with no edits it swipes away like any sheet.
            .interactiveDismissDisabled((mantra != nil && hasEdits) || newHasContent)
            .fullScreenCover(isPresented: $creatingTask) {
                if let mantra { AddDailyTaskView(for: mantra, isPresented: $creatingTask) }
            }
            .toolbar {
                if sessionsEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { confirmDeleteSessions = true } label: {
                            Text(selectedSessions.isEmpty ? "Delete" : "Delete (\(selectedSessions.count))")
                        }
                        .tint(.red)
                        .disabled(selectedSessions.isEmpty)
                    }
                }
            }
            .alert(selectedSessions.count == 1 ? "Delete 1 session?" : "Delete \(selectedSessions.count) sessions?",
                   isPresented: $confirmDeleteSessions) {
                Button("Delete", role: .destructive) {
                    guard let mantra else { return }
                    let doomed = mantra.sessions.filter { selectedSessions.contains($0.persistentModelID) }
                    selectedSessions.removeAll()
                    withAnimation {
                        sessionsEditing = false
                        SessionDeletion.delete(doomed, in: context)
                    }
                    triggerSomeVibration(type: .medium)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their counts come off this zikr's totals and today's task progress. This can't be undone.")
            }
            .alert("Discard changes?", isPresented: $confirmDiscardChanges) {
                Button("Discard", role: .destructive) { revertEdits() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your edits, photo and voice memo changes aren't saved.")
            }
            .alert("Discard this zikr?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { ZikrAudio.stopAll(); dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("What you've typed, recorded or added isn't saved.")
            }
            .alert(deleteTitle, isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    guard let mantra else { return }
                    ZikrAudio.stopAll()
                    dismiss()                                   // leave first…
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        MantraModel.delete(mantra, in: context) // …then delete, so no view reads it
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
        }
        // Fires when this sheet closes, and when the New task cover (full screen) goes over it:
        // either way a take in progress is finished and saved, and playback stops.
        .onDisappear { ZikrAudio.stopAll() }
    }

    private func save() {
        ZikrAudio.stopAll()   // a take in progress is finished into the draft (synchronously) and kept
        guard canSave else { return }
        dismissKeyboard()
        let fullTextTrimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mantra {
            mantra.name = trimmedName
            mantra.fullText = fullTextTrimmed
            mantra.notes = notesTrimmed
            // Tasks read the live name through the relationship; keep their snapshot in step too
            // so a later deletion still shows the right name. Sessions keep their historical title.
            for task in mantra.tasks { task.mantraName = trimmedName }
            if mediaEdited {
                mantra.imageData = draftImage
                mantra.audioData = draftAudio
                mediaEdited = false
            }
            try? context.save()
            // Stay on the mantra, back to viewing.
            withAnimation(.easeInOut(duration: 0.2)) {
                name = mantra.name; fullText = mantra.fullText; notes = mantra.notes; quickAdd = mantra.quickAddStep
                isEditing = false
            }
            triggerSomeVibration(type: .success)
        } else {
            let new = MantraModel(name: trimmedName, fullText: fullTextTrimmed, notes: notesTrimmed)
            new.quickAddStep = quickAdd
            new.imageData = draftImage
            new.audioData = draftAudio
            context.insert(new)
            try? context.save()
            triggerSomeVibration(type: .success)
            dismiss()
            onCreate?(new)
        }
    }

    /// Existing mantra: put the fields back as they were (the sheet stays). New: close (asking
    /// first when there's something in it).
    private func cancelEdits() {
        dismissKeyboard()
        guard mantra != nil else {
            if newHasContent { confirmDiscard = true } else { dismiss() }
            return
        }
        if hasEdits { confirmDiscardChanges = true } else { revertEdits() }
    }

    /// Back to viewing, as the zikr was: typed edits and photo / memo drafts dropped (a take in
    /// progress too).
    private func revertEdits() {
        guard let mantra else { return }
        discarding = true
        ZikrAudio.stopAll()
        discarding = false
        mediaEdited = false
        draftImage = nil; draftAudio = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            name = mantra.name; fullText = mantra.fullText; notes = mantra.notes; quickAdd = mantra.quickAddStep
            isEditing = false
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

/// This mantra's tasks the way the Zikr page shows tasks: circles ringed with today's progress,
/// in a row you can scroll (2026-09-25, owner). Tap → the task sheet in edit mode (goal / units,
/// mantra locked); long-press → Edit / Delete.
struct MantraTaskCircles: View {
    let mantra: MantraModel
    /// The empty state's dashed "New task" circle.
    var onNewTask: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]
    @State private var editing: TaskModel?
    @State private var deleting: TaskModel?

    init(mantra: MantraModel, onNewTask: @escaping () -> Void = {}) {
        self.mantra = mantra
        self.onNewTask = onNewTask
        let todayStart = PrayerDay.sessionDayStart()   // the prayer day (Fajr to Fajr)
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart })
    }

    private var tasks: [TaskModel] { mantra.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        if tasks.isEmpty {
            // Like the Zikr page's last circle.
            ZikrCircleFace(title: "New task", icon: "plus", subtitle: "a daily goal", ring: .dashed)
                .scaleEffect(0.7)
                .frame(width: 140, height: 140)
                .contentShape(Circle())
                .onTapGesture { onNewTask() }
                .accessibilityAddTraits(.isButton)
                .frame(maxWidth: .infinity)
                .frame(height: 152)
        } else {
            // The focused circle sits in the middle of the width (owner).
            GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tasks) { task in
                        circle(task)
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.85)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .contentMargins(.horizontal, max((geo.size.width - 140) / 2, 0), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            }
            .frame(height: 152)
            .fullScreenCover(item: $editing) { task in
                AddDailyTaskView(editing: task, isPresented: Binding(
                    get: { editing != nil },
                    set: { if !$0 { editing = nil } }
                ))
            }
            .alert("Delete this task?",
                   isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                   presenting: deleting) { task in
                Button("Delete", role: .destructive) { withAnimation { TaskModel.delete(task, in: context) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { _ in
                Text("Its sessions stay in your history.")
            }
        }
    }

    private func circle(_ task: TaskModel) -> some View {
        let p = task.progress(in: todaysSessions)
        let done = task.isCompleted(with: p)
        let fraction = task.isCountMode ? Double(p.count) / Double(max(task.goal, 1))
                                        : p.seconds / Double(max(task.goal * 60, 1))
        let subtitle = done ? "done today"
            : task.isCountMode ? "\(p.count) of \(task.goal) today" : "\(Int(p.seconds / 60)) of \(task.goal) min"
        // Its own name when it has one (this page is already about the mantra), the goal otherwise.
        let goal = task.isCountMode ? "\(task.goal)" : "\(task.goal) min"
        return ZikrCircleFace(title: task.mantraLine == nil ? goal : task.title,
                              icon: task.mantraLine == nil ? (task.isCountMode ? "number" : "timer") : nil,
                              subtitle: subtitle, ring: .progress(min(fraction, 1)), done: done,
                              mantraLine: task.mantraLine == nil ? nil : (task.isCountMode ? "goal \(goal)" : goal))
            .scaleEffect(0.7)
            .frame(width: 140, height: 140)
            .contentShape(Circle())
            .onTapGesture { editing = task }
            .contentShape(.contextMenuPreview, Circle())
            .contextMenu {
                Button { editing = task } label: { Label("Edit goal", systemImage: "slider.horizontal.3") }
                Button(role: .destructive) { deleting = task } label: { Label("Delete", systemImage: "trash") }
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

    /// A section per day, headed "Today · 249 counted" — the same look as Zikr History. Deleting
    /// is Edit → select → Delete, as on History (no swipes, no Delete in the tap strip; 2026-09-27).
    /// The edit state, the bottom-bar Delete and its alert live on `MantraEditorView`: this body
    /// is several Sections, and modifiers on it were attached once per Section (duplicate or
    /// vanishing Delete buttons — review, 2026-09-27).
    @Binding var editing: Bool
    @Binding var selected: Set<PersistentIdentifier>

    @ViewBuilder var body: some View {
        if mantra.sessions.isEmpty {
            Section("Sessions") {
                Text("No sessions with this zikr yet.").foregroundStyle(.secondary)
            }
        } else {
            // "Sessions" with Edit / Done; while editing, the Delete button.
            Section {
                EmptyView()
            } header: {
                HStack {
                    Text("Sessions")
                    Spacer()
                    Button(editing ? "Done" : "Edit") {
                        withAnimation(.snappy(duration: 0.2)) {
                            editing.toggle()
                            if !editing { selected.removeAll() }
                        }
                    }
                    .font(.subheadline.weight(editing ? .semibold : .regular))
                    .textCase(nil)
                }
            }
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.sessions) { session in
                        row(session)
                    }
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

    @ViewBuilder private func row(_ session: SessionDataModel) -> some View {
        let id = session.persistentModelID
        if editing {
            let on = selected.contains(id)
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.accentColor : Color(.tertiaryLabel))   // stock, no green
                    .contentTransition(.symbolEffect(.replace))
                SessionRow(session: session, showsMantraName: false, tappable: false)   // a tap selects
            }
            .contentShape(Rectangle())
            .onTapGesture {
                triggerSomeVibration(type: .light)
                if on { selected.remove(id) } else { selected.insert(id) }
            }
        } else {
            // Tap → Feel the pace (no "Open zikr": this is its page).
            SessionRow(session: session, showsMantraName: false)
        }
    }
}
