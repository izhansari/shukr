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
    /// Inside `ZikrLibraryView`: the library owns the search field and the + (both pages stay
    /// mounted side by side, so a page's own toolbar / search would show on the other page).
    var embedded = false
    var externalSearch = ""

    /// Matches the name, the full wording or the notes.
    private var shown: [MantraModel] {
        let q = (embedded ? externalSearch : search).trimmingCharacters(in: .whitespaces)
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
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search mantras")
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
                .sheet(isPresented: $showingNewMantra) {
                    MantraEditorView(mantra: nil)
                }
        }
    }

    private var list: some View {
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
                    .noPageZone("mantra-\(mantra.id)")   // row swipes (delete) stay the row's
                }
                .onDelete(perform: delete)
            }
        }
        .fontDesign(.rounded)
        .sheet(item: $editing) { mantra in
            MantraEditorView(mantra: mantra)
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
                    SaveButton(enabled: canSave) { save() }
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
    /// Viewing: fields locked. Editing: the name, full mantra and notes each sit in a box with a
    /// sage edge (the full mantra's box shows either way). Every field keeps the box's padding
    /// in both modes, so switching moves nothing (owner). Count in sets is always adjustable.
    var editable = true
    @FocusState private var focus: Field?
    private enum Field { case name, fullText, notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("name", text: $name)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .autocorrectionDisabled(true)
                    .focused($focus, equals: .name)
                    .disabled(!editable)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(fieldBox(alwaysFilled: false))
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
        .animation(.easeInOut(duration: 0.2), value: editable)
        .onChange(of: editable) { _, on in if !on { focus = nil } }
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
                .disabled(!editable)
                .foregroundStyle(.primary)
        }
        .font(centered ? .system(size: 17, weight: .light, design: .rounded) : .subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(fieldBox(alwaysFilled: inset))
    }

    /// The box behind a field: filled always (`alwaysFilled`, the full mantra) or only while
    /// editing, with a sage edge while editing. Drawn behind fixed padding, so it never moves
    /// anything.
    private func fieldBox(alwaysFilled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(Color.primary.opacity(alwaysFilled || editable ? 0.04 : 0))
            .overlay(shape.stroke(Color.sage.opacity(editable ? 0.45 : 0), lineWidth: 1))
    }
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

/// Zikr History and Mantras as one page (2026-09-25 — owner: they're the same subject and
/// shouldn't be two hamburger rows): a History | Mantras switch in the navigation bar over the
/// two existing pages. Reached from the Zikr tab's top-left button (the hamburger stays on
/// Salah), and from the old routes (`showZikrHistory` / `showMantrasPage`).
struct ZikrLibraryView: View {
    enum Tab: String, CaseIterable { case history = "History", mantras = "Mantras" }
    @State private var tab: Tab
    @State private var search = ""
    @State private var showingNewMantra = false
    /// Our own pager: a sideways drag turns the page only when it starts on the background —
    /// not on a session / mantra row (their swipe actions) or the history chart (it scrubs).
    /// A system paged TabView took every sideways swipe, rows included (owner wanted both).
    @State private var zones = NoPageZones()
    @State private var dragX: CGFloat = 0
    @State private var pagingDrag: Bool?

    init(start: Tab) { _tab = State(initialValue: start) }

    private func pageGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if pagingDrag == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4
                    // Mantras → History (finger moving right) clashes with nothing (mantra rows
                    // only swipe left to delete), so it pages from anywhere; everything else
                    // leaves rows and the chart to their own drags.
                    let freeDirection = tab == .mantras && value.translation.width > 0
                    pagingDrag = horizontal && (freeDirection || !zones.contains(value.startLocation))
                }
                guard pagingDrag == true else { return }
                // Rubber-band past the ends (right on History, left on Mantras).
                let t = value.translation.width
                let pastEnd = (tab == .history && t > 0) || (tab == .mantras && t < 0)
                dragX = pastEnd ? t / 4 : t
            }
            .onEnded { value in
                defer { pagingDrag = nil }
                guard pagingDrag == true else { return }
                let projected = value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if tab == .history && projected < -width / 3 { tab = .mantras }
                    else if tab == .mantras && projected > width / 3 { tab = .history }
                    dragX = 0
                }
            }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                HistoryPageView(search: search)
                    .frame(width: width)
                MantrasView(embedded: true, externalSearch: search)
                    .frame(width: width)
            }
            .offset(x: (tab == .history ? 0 : -width) + dragX)
            .scrollDisabled(pagingDrag == true)   // no vertical wobble during a page swipe
            .simultaneousGesture(pageGesture(width: width))
        }
        .clipped()
        .environment(zones)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .searchable(text: $search, prompt: tab == .history ? "Search sessions" : "Search mantras")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: Binding(get: { tab }, set: { new in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { tab = new }
                })) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            if tab == .mantras {   // a hidden button still drew its empty glass circle
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewMantra = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.green.opacity(0.7))
                    }
                    .accessibilityLabel("New mantra")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(isPresented: $showingNewMantra) {
            MantraEditorView(mantra: nil)
        }
    }
}

/// Screen areas (global frames) where a sideways drag belongs to the view there, not to the
/// library's pager. Written by `.noPageZone(_:)`; read only inside the pager's gesture, so
/// frame updates while scrolling don't re-render anything.
@Observable final class NoPageZones {
    @ObservationIgnored var frames: [String: CGRect] = [:]
    func contains(_ point: CGPoint) -> Bool { frames.values.contains { $0.contains(point) } }
}

private struct NoPageZoneModifier: ViewModifier {
    let id: String
    @Environment(NoPageZones.self) private var zones: NoPageZones?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { zones?.frames[id] = $0 }
            .onDisappear { zones?.frames[id] = nil }
    }
}

extension View {
    /// Marks this view as a place where sideways drags aren't page turns (see ZikrLibraryView).
    func noPageZone(_ id: String) -> some View { modifier(NoPageZoneModifier(id: id)) }
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
    @State private var showTitle = false
    /// Viewing by default; the pencil unlocks the fields in place (a new mantra starts editing).
    @State private var isEditing: Bool

    init(mantra: MantraModel?) {
        self.mantra = mantra
        _name = State(initialValue: mantra?.name ?? "")
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
        let lower = trimmedName.lowercased()
        return allMantras.contains { $0.name.lowercased() == lower && $0.persistentModelID != mantra?.persistentModelID }
    }

    private var hasEdits: Bool {
        guard let mantra else { return true }
        return name != mantra.name || fullText != mantra.fullText || notes != mantra.notes
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

    /// Restyled 2026-09-25 to match the pause screen (owner: "very plain"): the same card as
    /// its ✎ editor, the lifetime stats as `ZikrBento` tiles, and sessions grouped by day like
    /// Zikr History.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MantraCardFields(name: $name, fullText: $fullText, notes: $notes, quickAdd: liveQuickAdd,
                                     isDuplicate: isDuplicate, editable: isEditing)
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

                    Section {
                        MantraTaskCircles(mantra: mantra)
                    } header: {
                        HStack {
                            Text("Tasks")
                            Spacer()
                            Text(mantra.tasks.count == 1 ? "1 task" : "\(mantra.tasks.count) tasks")
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    MantraSessionsSection(mantra: mantra)
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
            .navigationTitle(mantra?.name ?? "New Mantra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mantra == nil ? "New Mantra" : name)
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
                            withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit")
                    }
                }
            }
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
            // Tasks read the live name through the relationship; keep their snapshot in step too
            // so a later deletion still shows the right name. Sessions keep their historical title.
            for task in mantra.tasks { task.mantraName = trimmedName }
            // Stay on the mantra, back to viewing.
            withAnimation(.easeInOut(duration: 0.2)) {
                name = mantra.name; fullText = mantra.fullText; notes = mantra.notes; quickAdd = mantra.quickAddStep
                isEditing = false
            }
            triggerSomeVibration(type: .success)
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
    @Environment(\.modelContext) private var context
    @Query private var todaysSessions: [SessionDataModel]
    @State private var editing: TaskModel?
    @State private var deleting: TaskModel?

    init(mantra: MantraModel) {
        self.mantra = mantra
        let todayStart = PrayerDay.sessionDayStart()   // the prayer day (Fajr to Fajr)
        _todaysSessions = Query(filter: #Predicate<SessionDataModel> { $0.startTime >= todayStart })
    }

    private var tasks: [TaskModel] { mantra.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        if tasks.isEmpty {
            Text("No tasks use this mantra.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
                Button("Delete", role: .destructive) { withAnimation { context.delete(task) }; deleting = nil }
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
        return ZikrCircleFace(title: task.isCountMode ? "\(task.goal)" : "\(task.goal) min",
                              icon: task.isCountMode ? "number" : "timer",
                              subtitle: subtitle, ring: .progress(min(fraction, 1)), done: done)
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

    /// A section per day, headed "Today · 249 counted" — the same look as Zikr History; swipe
    /// a session to delete it (confirmed), as there.
    @Environment(\.modelContext) private var context
    @State private var pendingDelete: SessionDataModel?
    @State private var expandedID: PersistentIdentifier?

    var body: some View {
        sections
            .alert("Delete this session?",
                   isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                   presenting: pendingDelete) { session in
                Button("Delete", role: .destructive) {
                    withAnimation {
                        context.delete(session)
                        try? context.save()
                    }
                    triggerSomeVibration(type: .medium)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { session in
                Text("\(session.totalCount) counts, \(session.startTime.formatted(date: .abbreviated, time: .shortened)). This can't be undone.")
            }
    }

    @ViewBuilder private var sections: some View {
        if mantra.sessions.isEmpty {
            Section("Sessions") {
                Text("No sessions with this mantra yet.").foregroundStyle(.secondary)
            }
        } else {
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.sessions) { session in
                        let id = session.persistentModelID
                        SessionRow(session: session, showsMantraName: false,
                                   expanded: expandedID == id, onDelete: { pendingDelete = session })
                            .onTapGesture {
                                triggerSomeVibration(type: .light)
                                withAnimation(.snappy(duration: 0.25)) { expandedID = expandedID == id ? nil : id }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { pendingDelete = session } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
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
}
