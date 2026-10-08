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
                .newZikrCard(isPresented: $showingNewMantra)   // the card over the page (decision zikr-card-edit B)
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
        let gone = mantra.persistentModelID
        context.delete(mantra)
        try? context.save()
        // Whoever holds this zikr as "the session's pick" drops it (audit A8: the post-salah pill read a deleted row).
        NotificationCenter.default.post(name: MantraModel.didDelete, object: gone)
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

/// A zikr's card, being edited (only ever in `ZikrCardEditor`, the card over a dimmed screen — decision
/// zikr-card-edit B): the name in large light type (with `nameAccessory` top right), then one fixed box with three
/// tabs down its left — the words (the full zikr, a rule, the notes: one tab, owner 2026-10-08), the voice memo, the
/// photo — then count in sets.
struct MantraCardFields: View {
    @Binding var name: String
    @Binding var fullText: String
    @Binding var notes: String
    @Binding var quickAdd: Int
    /// The photo and voice memo (notes #17), the box's other two tabs.
    @Binding var imageData: Data?
    @Binding var audioData: Data?
    var isDuplicate = false
    /// A built-in: its name and full text stay as they are (notes, memo, photo, sets are the
    /// user's) — owner, 2026-09-27.
    var identityLocked = false
    var startPane: Pane = .words
    /// Beside the name, top right: the card's ✕ and ✓.
    var nameAccessory: AnyView? = nil
    @FocusState private var focus: Field?
    private enum Field { case name, fullText, notes }
    /// Which part the box shows. The box keeps one size for all three (owner, 2026-09-27: nothing on the card may move
    /// when switching).
    enum Pane: CaseIterable { case words, memo, photo
        var symbol: String { switch self { case .words: "doc.text"; case .memo: "waveform"; case .photo: "photo" } }
        var label: String { switch self { case .words: "Full zikr and notes"; case .memo: "Voice memo"; case .photo: "Photo" } }
    }
    /// The card's one audio engine (VoiceMemoPanel only borrows it), so a take survives tab
    /// switches. Leaving the memo tab finishes it; the card calls `ZikrAudio.stopAll()` when it closes.
    @State private var audio = ZikrAudio()
    @State private var pane: Pane = .words
    @State private var paneSet = false
    static let paneHeight: CGFloat = 176

    var body: some View {
        // Re-wired on every render, so a take always lands in the card's current binding (one
        // captured once in onAppear could go stale if the parent handed in a new one).
        let _ = wireRecorder()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    // "Nickname" (owner): a short name for it — the full zikr has its own place.
                    TextField("Nickname", text: $name)
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .autocorrectionDisabled(true)
                        .focused($focus, equals: .name)
                        .disabled(identityLocked)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(fieldBox(alwaysFilled: false, editing: !identityLocked))
                        // Built-in: a small lock in the field (an overlay, so nothing moves).
                        .overlay(alignment: .trailing) {
                            if identityLocked {
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
                // words / waveform / photo, top to bottom — tabs for the box beside them.
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
                    case .words:
                        wordsPane
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
        .onAppear {
            guard !paneSet else { return }
            paneSet = true
            pane = startPane
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "demoZikrPane") {
            case "memo": pane = .memo
            case "photo": pane = .photo
            default: break
            }
            #endif
        }
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

    /// The words, one tab (owner, 2026-10-08: "merge the full text and notes into one edit field window with a
    /// separator"): the full zikr centred in the light type, a rule, the notes under it; both grow with what's typed
    /// and scroll inside the box. A built-in's full text shows as it is, locked.
    private var wordsPane: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    if identityLocked {
                        ZikrFullText(text: fullText, arabicSize: 22, otherSize: 14)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
                            }
                    } else {
                        TextField("The full zikr — Arabic, transliteration, or meaning", text: $fullText, axis: .vertical)
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2...)
                            // Arabic and transliterations aren't English: no autocorrect, no spelling taps that select
                            // a "misspelled" word (typing then replaced it).
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .focused($focus, equals: .fullText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Notes — where you heard it, who taught you, why you read it", text: $notes, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(2...)
                        .focused($focus, equals: .notes)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(fieldBox(alwaysFilled: true, editing: true))
    }

    /// A tab in the left column: highlighted when selected; a small dot when that tab has something.
    private func paneButton(_ p: Pane) -> some View {
        let selected = pane == p
        let filled = switch p {
        case .words: !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !notes.isEmpty
        case .memo: audioData != nil
        case .photo: imageData != nil
        }
        return Button {
            guard pane != p else { return }
            focus = nil
            pane = p
        } label: {
            Image(systemName: p.symbol).font(.system(size: 14, weight: .medium))
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

    /// The box behind a field: filled always (`alwaysFilled`) or only while editable, with a sage edge while
    /// editable. Drawn behind fixed padding, so it never moves anything.
    private func fieldBox(alwaysFilled: Bool, editing: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(Color.primary.opacity(alwaysFilled || editing ? 0.04 : 0))
            .overlay(shape.stroke(Color.sage.opacity(editing ? 0.45 : 0), lineWidth: 1))
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

    let mantra: MantraModel
    /// The card over the page, open on a tab (decision zikr-card-edit B: the page shows, the card edits).
    @State private var editing: ZikrCardRequest?
    /// The task sheet for a new task with this zikr locked in (notes #17).
    @State private var creatingTask = false
    /// The sessions list's Edit → select → Delete (MantraSessionsSection draws the rows).
    @State private var sessionsEditing = false
    @State private var selectedSessions = Set<PersistentIdentifier>()
    @State private var confirmDeleteSessions = false
    /// A session row's tap / long-press "Delete…" (owner, ask session-page — as on History, minus
    /// "Open zikr": this is its page). Here, not on the sessions section (its modifiers repeat per Section).
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?

    /// Opened from a running session's pause screen (a tap on the zikr's card — decision pause-zikr-edit A): no task
    /// rows (a tap there would start another session) and no Delete (the session is counting this zikr).
    var inSession = false

    init(mantra: MantraModel, inSession: Bool = false) {
        self.mantra = mantra
        self.inSession = inSession
    }

    /// The zikr as the pause screen shows it (owner, 2026-10-08: "i like how we display the viewable item … in the
    /// pause page"), then the lifetime stats as `ZikrBento` tiles, its tasks, and sessions grouped by day like Zikr
    /// History. Nothing on the page edits the zikr: a tap on it opens the card (`ZikrCardEditor`).
    var body: some View {
        // The page dismisses, then deletes 0.35 s later; if the sheet is still animating out when the row goes, a
        // re-render must not read it (audit A9).
        if mantra.isDeleted || mantra.modelContext == nil { Color.clear } else { page }
    }

    private var page: some View {
        NavigationStack {
            List {
                Section {
                    ZikrReadCard(mantra: mantra, canEdit: !sessionsEditing) { pane in
                        triggerSomeVibration(type: .light)
                        editing = ZikrCardRequest(mantra: mantra, pane: pane)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

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

                // Its tasks as the same rows as Your tasks (the Zikr tab reorganisation): tap → "Start?",
                // hold → the task's options; + Add task opens the steps on the goal.
                if !inSession {
                    MantraTaskRows(mantra: mantra, onNewTask: { creatingTask = true }) { task, resume in
                        // Close this page; the host waits until what covers the pager has really gone, goes to the
                        // Zikr page, and its wheel starts it (it was a guessed 0.35 s — audit E5).
                        ZikrAudio.stopAll()
                        dismiss()
                        ZikrFocus.start(task.id.uuidString, resume: resume)
                    }
                }
                MantraSessionsSection(mantra: mantra, editing: $sessionsEditing, selected: $selectedSessions,
                                      sessionToOpen: $sessionToOpen, sessionToDelete: $sessionToDelete)
            }
            .fontDesign(.rounded)
            // No bar (owner, 2026-09-29, #17): the page's space is the page's.
            .contentMargins(.top, 12, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $creatingTask) { NewTaskFlow(locked: mantra) }
            // The card over the page; Delete zikr is confirmed in it, then the page leaves and deletes.
            .zikrCardEditor($editing, allowDelete: !inSession) { doomed in
                ZikrAudio.stopAll()
                dismiss()                                   // leave first…
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    MantraModel.delete(doomed, in: context) // …then delete, so no view reads it
                }
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
        }
        #if DEBUG
        // `-demoZikrEditing`: the card opens over the page (simulator screenshots).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoZikrEditing") else { return }
            try? await Task.sleep(for: .seconds(1))
            editing = ZikrCardRequest(mantra: mantra)
        }
        #endif
        // Fires when this sheet closes, and when the New task cover (full screen) goes over it: playback stops.
        .onDisappear { ZikrAudio.stopAll() }
    }
}

/// A zikr shown, not edited (decision zikr-card-edit B; the pause screen's well, owner: "i like how we display the
/// viewable item"): its name with the memo's ▶︎ and the photo at the right and ✎, a rule, the full text centred
/// (Arabic in the Uthmani face), a rule, the notes; count in sets at the foot. A tap on the name, the words or the
/// sets opens the card on the words; ✎ too. ▶︎ plays and the photo opens — they never change anything.
struct ZikrReadCard: View {
    let mantra: MantraModel
    var canEdit = true
    let onEdit: (MantraCardFields.Pane) -> Void

    var body: some View {
        let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button { onEdit(.words) } label: {
                    Text(mantra.name)
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ZikrMediaStrip(mantra: mantra, paused: true, compact: true)
                Button { onEdit(.words) } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sage)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.sage.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit zikr")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            rule
            Button { onEdit(.words) } label: {
                VStack(spacing: 10) {
                    if !full.isEmpty {
                        ZikrFullText(text: full, arabicSize: 26, otherSize: 15)
                            .frame(maxWidth: .infinity)
                    }
                    if !full.isEmpty && !notes.isEmpty { rule.padding(.vertical, 4) }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                            Text(notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .font(.footnote)
                    }
                    if full.isEmpty && notes.isEmpty {
                        Text(mantra.isBuiltIn ? "Add your notes" : "Add the full zikr and your notes")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            rule
            Button { onEdit(.words) } label: {
                HStack {
                    Text("Count in sets")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(mantra.quickAddStep > 0 ? "+\(mantra.quickAddStep)" : "off")
                        .monospacedDigit()
                        .foregroundStyle(mantra.quickAddStep > 0 ? Color.sage : .secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .fontDesign(.rounded)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .allowsHitTesting(canEdit)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
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
/// A zikr's tasks on its page: one row each (`TaskRow`), tap → "Start …?" (Continue / Start over when
/// part-done today; owner, note 3CA19C68), hold → Start · Edit task · Delete…; then + Add task.
struct MantraTaskRows: View {
    let mantra: MantraModel
    var onNewTask: () -> Void = {}
    /// Start the task: the page closes, the session opens.
    var onStart: (TaskModel, _ resume: Bool) -> Void = { _, _ in }
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]
    @State private var asking: TaskModel?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?

    init(mantra: MantraModel, onNewTask: @escaping () -> Void = {}, onStart: @escaping (TaskModel, Bool) -> Void = { _, _ in }) {
        self.mantra = mantra
        self.onNewTask = onNewTask
        self.onStart = onStart
        let todayStart = PrayerDay.sessionDayStart()   // the prayer day (Fajr to Fajr)
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart })
    }

    private var tasks: [TaskModel] { mantra.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    private func partDone(_ task: TaskModel) -> Bool {
        let p = task.progress(in: todaysSessions)
        return !task.isCompleted(with: p) && (p.count > 0 || p.seconds >= 1)
    }

    var body: some View {
        Section {
            ForEach(tasks) { task in
                Button { triggerSomeVibration(type: .light); asking = task } label: {
                    TaskRow(task: task, sessions: todaysSessions, showsZikr: false, showsHandle: false)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    TaskMenu(task: task,
                             onStart: { onStart(task, partDone(task)) },
                             onEdit: { editing = task },
                             onDelete: { toDelete = task })
                }
            }
            Button(action: onNewTask) {
                Label("Add task", systemImage: "plus.circle.fill").foregroundStyle(Color.sage)
            }
        } header: {
            Text("Tasks")
        }
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }   // the task's review (task-edit-review-page)
        .alert(asking.map { "Start \($0.title)?" } ?? "",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { task in
            let p = task.progress(in: todaysSessions)
            if partDone(task) {
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
        .alert(toDelete.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "",
               isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
               presenting: toDelete) { task in
            Button("Delete Task", role: .destructive) {
                withAnimation { TaskModel.delete(task, in: context) }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: { _ in
            Text("Its reminder goes too. The sessions you've counted stay in your history.")
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
