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
    /// Inside `AzkarPage`: the page owns the search field, the + and the sort button
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

/// A zikr's card, editable: the name in large light type (with `nameAccessory` top right), then
/// one fixed box with four tabs down its left — the full zikr (ع), notes, voice memo, photo — then
/// count in sets. No background — the zikr page (and a new zikr) put it on a
/// grouped card.
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
    /// Beside the name, top right (owner, 2026-09-29, #17): the zikr page's ✎ / Cancel · Save —
    /// it edits only these fields, so it sits on the card, not in the page's bar.
    var nameAccessory: AnyView? = nil
    @FocusState private var focus: Field?
    private enum Field { case name, fullText, notes }
    /// Which of the full zikr / notes / voice memo / photo the box shows. The box keeps one size for
    /// all four (owner, 2026-09-27: nothing on the card or page may move when switching). The full
    /// zikr is a tab too since 2026-09-29 (#17, option A: ع first and the default; it scrolls in the box).
    enum Pane: CaseIterable { case fullText, notes, memo, photo
        var symbol: String { switch self { case .fullText: ""; case .notes: "doc.text"; case .memo: "waveform"; case .photo: "photo" } }
        var label: String { switch self { case .fullText: "Full zikr"; case .notes: "Notes"; case .memo: "Voice memo"; case .photo: "Photo" } }
    }
    /// The card's one audio engine (VoiceMemoPanel only borrows it), so a take survives tab
    /// switches and List cell recycling. Leaving the memo tab finishes it; the sheets call
    /// `ZikrAudio.stopAll()` when they really close.
    @State private var audio = ZikrAudio()
    @State private var pane: Pane = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "demoZikrPane") {
        case "notes": return .notes; case "memo": return .memo; case "photo": return .photo; default: break
        }
        #endif
        return .fullText
    }()
    static let paneHeight: CGFloat = 132

    var body: some View {
        // Re-wired on every render, so a take always lands in the card's current binding (one
        // captured once in onAppear could go stale if the parent handed in a new one).
        let _ = wireRecorder()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    // "Nickname" (owner): a short name for it — the full zikr has its own tab.
                    TextField("Nickname", text: $name)
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
                    if let nameAccessory { nameAccessory }
                }
                if isDuplicate {
                    Text("another zikr already has this name")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                // ع / doc.text / waveform / photo, top to bottom — tabs for the box beside them.
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
                    case .fullText:
                        fullTextPane
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

    /// The full zikr tab: the editor while editing (a built-in's text stays as it is), else the text —
    /// Arabic lines in the Uthmani face, the rest light rounded — scrolling inside the box.
    private var fullTextPane: some View {
        ZStack(alignment: .top) {
            Color.clear
            if editable && !identityLocked {
                editorBox(text: $fullText, field: .fullText,
                          placeholder: "The full zikr — Arabic, transliteration, or meaning",
                          minHeight: Self.paneHeight - 8, centered: true, inset: false)
            } else {
                ScrollView {
                    Group {
                        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("no text yet")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        } else {
                            ZikrFullText(text: fullText, arabicSize: 22, otherSize: 14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background { if !(editable && !identityLocked) { fieldBox(alwaysFilled: true) } }
    }

    /// The notes tab: the editor while editing, else the notes as text in the same box.
    private var notesPane: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if editable {
                editorBox(text: $notes, field: .notes,
                          placeholder: "Notes to remember — where you heard it, who taught you, why you read it",
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
        case .fullText: !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .notes: !notes.isEmpty
        case .memo: audioData != nil
        case .photo: imageData != nil
        }
        return Button {
            guard pane != p else { return }
            focus = nil
            pane = p
        } label: {
            Group {
                if p == .fullText { Text("ع").font(.system(size: 17, weight: .medium)) }
                else { Image(systemName: p.symbol).font(.system(size: 14, weight: .medium)) }
            }
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

/// A zikr's full text as the cards show it: Arabic lines in the Uthmani face, the rest
/// (transliteration, meaning) in light rounded type, centred.
struct ZikrFullText: View {
    let text: String
    var arabicSize: CGFloat = 26
    var otherSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    let arabic = t.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                    Text(t)
                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: arabicSize)
                                     : .system(size: otherSize, weight: .light, design: .rounded))
                        .foregroundStyle(arabic ? .primary : .secondary)
                        .lineSpacing(arabic ? 6 : 2)
                        .multilineTextAlignment(.center)
                }
            }
        }
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
    /// A fixed width, so the bar's title never shifts as the field / direction change.
    static let width: CGFloat = 50
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
            // filled prominent button was too stark. It fills its fixed slot (`width`).
            .frame(width: AzkarSortButton.width, height: 36)
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
    /// A session row's tap / long-press "Delete…" (owner, ask session-page — as on History, minus
    /// "Open zikr": this is its page). Here, not on the sessions section (its modifiers repeat per Section).
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
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
                                     identityLocked: mantra?.isBuiltIn ?? false,
                                     nameAccessory: AnyView(cardControls))
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground)))
                        // While editing, a sage edge round the whole card: this is what ✎ edits,
                        // not the sessions or the rest of the page (owner, note 3CA19C68).
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.sage.opacity(isEditing ? 0.75 : 0), lineWidth: 1.5)
                                .animation(.easeInOut(duration: 0.2), value: isEditing)
                                .allowsHitTesting(false)
                        }
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
                        MantraTaskCircles(mantra: mantra, onNewTask: { creatingTask = true }) { task, resume in
                            // Close this page, then the Zikr page starts it.
                            ZikrAudio.stopAll()
                            dismiss()
                            let id = task.id.uuidString
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ZikrFocus.start(id, resume: resume) }
                        }
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
                    MantraSessionsSection(mantra: mantra, editing: $sessionsEditing, selected: $selectedSessions,
                                          sessionToOpen: $sessionToOpen, sessionToDelete: $sessionToDelete)

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
            // No bar (owner, 2026-09-29, #17): ✎ / Cancel · Save sit on the card beside the name —
            // they only edit the card — and the space the bar took is the page's again.
            .contentMargins(.top, 12, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(item: $sessionToOpen) { session in
                SessionPage(session: session)   // no Open zikr: we're on it
            }
            .onChange(of: sessionToOpen) { _, open in if open != nil { PaceCoordinator.stopAll() } }
            .alert("Delete this session?", isPresented: Binding(get: { sessionToDelete != nil },
                                                               set: { if !$0 { sessionToDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let doomed = sessionToDelete {
                        withAnimation { SessionDeletion.delete([doomed], in: context) }
                    }
                    sessionToDelete = nil
                }
                Button("Cancel", role: .cancel) { sessionToDelete = nil }
            } message: {
                Text("Its count comes off this zikr's totals and today's task progress. This can't be undone.")
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
        #if DEBUG
        // `-demoZikrEditing`: the page opens in ✎ mode (simulator screenshots).
        .task {
            guard mantra != nil, ProcessInfo.processInfo.arguments.contains("-demoZikrEditing") else { return }
            try? await Task.sleep(for: .seconds(1))
            beginEditing()
        }
        #endif
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

    /// Top right of the card: ✎ while viewing; Cancel and ✓ (Save) while editing (✓ sage only with
    /// something to save). Fixed height, so the name row never moves.
    private var cardControls: some View {
        HStack(spacing: 6) {
            if isEditing {
                Button("Cancel") { cancelEdits() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                // Save is a checkmark (owner), sage once there's something to save.
                Button { save() } label: {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canSave ? Color.sage : Color.secondary.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canSave ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06)))
                }
                .disabled(!canSave)
                .accessibilityLabel("Save")
            } else {
                Button {
                    triggerSomeVibration(type: .light)
                    beginEditing()
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sage)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.sage.opacity(0.14)))
                }
                .accessibilityLabel("Edit zikr")
                .disabled(sessionsEditing)      // one mode at a time while sessions are selected
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
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
/// in a row you can scroll (2026-09-25, owner). Tap → "Start?" (then the Zikr page starts it);
/// long-press → the task sheet in edit mode (2026-09-30). Deleting is in the Zikr page's Tasks list.
struct MantraTaskCircles: View {
    let mantra: MantraModel
    /// The empty state's dashed "New task" circle.
    var onNewTask: () -> Void = {}
    /// Start the task (owner, 2026-09-30, note 3CA19C68): the page closes, the session opens.
    var onStart: (TaskModel, _ resume: Bool) -> Void = { _, _ in }
    @State private var asking: TaskModel?
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]
    @State private var editing: TaskModel?

    init(mantra: MantraModel, onNewTask: @escaping () -> Void = {}, onStart: @escaping (TaskModel, Bool) -> Void = { _, _ in }) {
        self.mantra = mantra
        self.onNewTask = onNewTask
        self.onStart = onStart
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
            // Tap = "Start?" (owner): part-done today → continue or start over, as on the Zikr page.
            .alert(asking.map { "Start \($0.title)?" } ?? "",
                   isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                   presenting: asking) { task in
                let p = task.progress(in: todaysSessions)
                if !task.isCompleted(with: p) && (p.count > 0 || p.seconds >= 1) {
                    Button(task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))") {
                        asking = nil; onStart(task, true)
                    }
                    Button("Start over") { asking = nil; onStart(task, false) }
                } else {
                    Button("Start") { asking = nil; onStart(task, false) }
                }
                Button("Cancel", role: .cancel) { asking = nil }
            } message: { task in
                let p = task.progress(in: todaysSessions)
                Text(task.isCompleted(with: p) ? "Done today. Start another session?"
                     : task.isCountMode ? "\(p.count) of \(task.goal) today." : "\(Int(p.seconds / 60)) of \(task.goal) min today.")
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
            // Tap → "Start?"; hold → its edit sheet (owner, 2026-09-30).
            .onTapGesture { triggerSomeVibration(type: .light); asking = task }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                editing = task
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
    @Binding var sessionToOpen: SessionDataModel?
    @Binding var sessionToDelete: SessionDataModel?

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
                    // "Select", not a second "Edit" (the pencil edits the zikr; owner, zikr-two-edits):
                    // quiet grey, "Done" in the accent while selecting — iOS's own multi-select word.
                    Button(editing ? "Done" : "Select") {
                        withAnimation(.snappy(duration: 0.2)) {
                            editing.toggle()
                            if !editing { selected.removeAll() }
                        }
                    }
                    .font(.subheadline.weight(editing ? .semibold : .regular))
                    .foregroundStyle(editing ? Color.accentColor : Color.secondary)
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
            SelectableRow(selected: $selected, id: id) {
                SessionRow(session: session, showsMantraName: false, tappable: false)   // a tap selects
            }
        } else {
            // Tap → the session's page; hold → its options; tap the pace to feel it. No "Open zikr":
            // this is its page.
            SessionRow(session: session, showsMantraName: false,
                       onOpen: { sessionToOpen = session }, onDelete: { sessionToDelete = session })
        }
    }
}

/// A session row while selecting (Zikr History, a zikr page's sessions): our own check circle
/// before the row, a tap toggles it. Selecting animates the check in; deselecting is instant —
/// the replace effect (and List's own selection) ran the filled check out in grey, a grey flash
/// (owner, FAD0EBFA: "just deselect it and don't animate that deselection").
struct SelectableRow<Content: View>: View {
    @Binding var selected: Set<PersistentIdentifier>
    let id: PersistentIdentifier
    @ViewBuilder var content: Content

    var body: some View {
        let on = selected.contains(id)
        HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? Color.accentColor : Color(.tertiaryLabel))   // stock, no green
                .contentTransition(.identity)
            content
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Plain on / off both ways, no animation (owner, 5ABED020: an animated check reads as a hang).
            triggerSomeVibration(type: .light)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                if on { selected.remove(id) } else { selected.insert(id) }
            }
        }
    }
}
