//
//  ZikrRedesignMocks.swift
//  shukr
//
//  DEBUG only: mockups of the Zikr area redesign (audit for the owner, 2026-10-14), v3 in the language of the two places
//  the owner likes: NewTaskFlow (a light 30 pt heading + grey line, the soft grey search capsule, the dashed sage "new"
//  card, spaced small caps labels, soft grey 18 pt cards on a plain page) and the zikr card modal (ZikrCardEditor — the
//  real one opens from a zikr's card). Liquid Glass on the bar buttons and the floating Start. Drawn on the real data;
//  pausing is held in memory. `-zikrMock [azkar|zikr|history|history-zikr|tour]` opens them; `tour` plays the flow by
//  itself for a recording.
//

import SwiftUI
import SwiftData

/// Where the redesign mockups take over from the real Zikr tab's pages (`-zikrMockApp`: the real wheel, with its History
/// door, Azkar door and "N of M tasks done ›" leading to the mockups — owner: "feel how the navigation is").
enum ZikrMockStart { case azkar, history }

@MainActor @ViewBuilder func zikrRedesign<Real: View>(_ start: ZikrMockStart, @ViewBuilder real: () -> Real) -> some View {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-zikrMockApp") { ZikrMockPage(start: start) } else { real() }
    #else
    real()
    #endif
}

#if DEBUG

/// Pretend state (pausing isn't real yet) and the tour's script.
@MainActor @Observable final class ZikrMockState {
    static let shared = ZikrMockState()
    var paused: Set<UUID> = []
    var seededPause = false
    var historyQuery = ""
}

struct ZikrMockHost: ViewModifier {
    @State private var open = false
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $open) { ZikrMockRoot() }
            .task {   // a cover asked for on the first frame is dropped: a moment after launch
                guard ProcessInfo.processInfo.arguments.contains("-zikrMock") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                open = true
            }
    }
}

extension View {
    func zikrMockHost() -> some View { modifier(ZikrMockHost()) }
}

/// A mockup page pushed onto the real app's stack, with the mockups' own routes.
struct ZikrMockPage: View {
    let start: ZikrMockStart
    @Query private var zikrs: [MantraModel]
    var body: some View {
        Group {
            switch start {
            case .azkar: MockAzkarPage()
            case .history: MockHistoryPage(filter: nil)
            }
        }
        .fontDesign(.rounded)
        .navigationDestination(for: MockRoute.self) { route in
            switch route {
            case .zikr(let id):
                if let z = zikrs.first(where: { $0.persistentModelID == id }) { MockZikrPage(zikr: z) }
            case .history(let id):
                MockHistoryPage(filter: id)
            }
        }
    }
}

private enum MockRoute: Hashable {
    case zikr(PersistentIdentifier)
    case history(PersistentIdentifier?)
}

private struct ZikrMockRoot: View {
    @Query private var zikrs: [MantraModel]
    @State private var path: [MockRoute] = []
    @State private var started = false
    private var mainZikr: MantraModel? { zikrs.max(by: { $0.tasks.count < $1.tasks.count }) }
    var body: some View {
        NavigationStack(path: $path) {
            MockAzkarPage()
                .navigationDestination(for: MockRoute.self) { route in
                    switch route {
                    case .zikr(let id):
                        if let z = zikrs.first(where: { $0.persistentModelID == id }) { MockZikrPage(zikr: z) }
                    case .history(let id):
                        MockHistoryPage(filter: id)
                    }
                }
        }
        .fontDesign(.rounded)
        .task {
            guard !started else { return }
            started = true
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-zikrMock"), i + 1 < args.count, let z = mainZikr else { return }
            switch args[i + 1] {
            case "zikr", "zikr-card": path = [.zikr(z.persistentModelID)]
            case "history": path = [.history(nil)]
            case "history-zikr": path = [.history(z.persistentModelID)]
            case "tour": await tour(z)
            default: break
            }
        }
    }

    /// The flow, played by itself (a recording without the simulator's taps).
    private func tour(_ z: MantraModel) async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        let state = ZikrMockState.shared
        await wait(3)
        path = [.zikr(z.persistentModelID)]
        await wait(3)
        if let night = z.tasks.max(by: { $0.sortOrder < $1.sortOrder }) {
            withAnimation(.snappy) { _ = state.paused.insert(night.id) }
        }
        await wait(2.5)
        path.append(.history(z.persistentModelID))
        await wait(3)
        withAnimation { state.historyQuery = "Morning" }
        await wait(3)
        withAnimation { state.historyQuery = "" }
        path = [.history(nil)]
        await wait(3.5)
        path = []
        await wait(3)
    }
}

// MARK: - Shared bits

private enum MockFmt {
    static func count(_ n: Int) -> String { n.formatted(.number) }
    static func goal(_ t: TaskModel) -> String { t.isCountMode ? "\(count(t.goal)) a day" : "\(t.goal) min a day" }
    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    /// How long since (owner: "it's been 10 weeks since you did this, or it's been 3 days"), by prayer day.
    static func ago(_ d: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: PrayerDay.start(for: d), to: PrayerDay.start()).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<14: return "\(days) days ago"
        case ..<60: return "\(days / 7) weeks ago"
        case ..<365: return "\(days / 30) months ago"
        default: return days < 730 ? "a year ago" : "\(days / 365) years ago"
        }
    }
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}

/// The app's newer type scale for these pages: 15 pt rows, 12.5 pt detail (owner: big text reads naive).
private extension Font {
    static let mockRow = Font.system(size: 15, weight: .regular, design: .rounded)
    static let mockRowStrong = Font.system(size: 15, weight: .medium, design: .rounded)
    static let mockDetail = Font.system(size: 12.5, weight: .regular, design: .rounded)
    static let mockSection = Font.system(size: 12, weight: .semibold, design: .rounded)
}

/// A daily goal's ring: today's progress in sage, ✓ when done, the pause glyph when paused, the beads for no goal.
private struct MockGoalRing: View {
    var progress: Double = 0
    var paused = false
    var noGoal = false
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            if noGoal {
                Image(systemName: "circle.hexagonpath").font(.system(size: size * 0.5, weight: .light)).foregroundStyle(Color.sage)
            } else {
                Circle().stroke(Color.primary.opacity(0.09), lineWidth: 2.5)
                if paused {
                    Image(systemName: "pause.fill").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.tertiary)
                } else {
                    Circle().trim(from: 0, to: min(progress, 1))
                        .stroke(Color.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                    if progress >= 1 {
                        Image(systemName: "checkmark").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Color.sage)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// NewTaskFlow's pieces, shared by the three pages.
private enum Flow {
    static let card = Color.primary.opacity(0.045)

    static func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 30, weight: .light, design: .rounded)).multilineTextAlignment(.center)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
    }

    static func search(_ prompt: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: text).autocorrectionDisabled()
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .barGlass(Capsule())   // Liquid Glass wherever it can be (owner)
    }

    static func newCard(_ title: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.sage)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.sage.opacity(0.14)))
                Text(title).foregroundStyle(Color.sage)
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.sage.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])))
        }
        .buttonStyle(.plain)
    }

    /// A small caps label over a soft grey card of rows with hairlines between them.
    static func group<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.medium)).tracking(1.2)
                Spacer()
                if let trailing { Text(trailing).font(.caption).monospacedDigit() }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            VStack(spacing: 0) { rows() }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(card))
        }
    }

    static var divider: some View { Divider().padding(.leading, 16) }
}

/// A row in NewTaskFlow's look: name, a grey line, something on the right.
private struct FlowRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary).lineLimit(1)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.secondary.opacity(0.5)) }
}

// MARK: - The real rows in the redesign's look (owner, round 5: "more like the real deal")

/// Round 5: the pages are Lists again, so the real rows come with their real gestures — hold and drag to reorder,
/// hold for the options, swipe to delete, the pace pill — drawn as grey cards on the white page.
private extension View {
    func mockList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground).ignoresSafeArea())
            .listSectionSpacing(16)
            .fontDesign(.rounded)
    }
    /// A row with no card (the heading, the dashed "new" card, the zikr card).
    func bareRow() -> some View {
        // 4 pt in from the section's edge: its larger corner radius clipped an 18 pt card's corners.
        listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowSeparator(.hidden)
    }
}

private extension Flow {
    /// A section's small caps label (List headers are title case on 26).
    static func header(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.medium)).tracking(1.2)
            Spacer()
            if let trailing { Text(trailing).font(.caption).monospacedDigit() }
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// Started from any of the pages: the app closes what covers the wheel and the wheel starts it (the real path).
@MainActor private func startGoal(_ t: TaskModel, resume: Bool) {
    ZikrFocus.start(t.id.uuidString, resume: resume)
}
/// "last 3 days ago" on a goal not started today (owner: how long since you did this).
@MainActor private func lastDone(_ t: TaskModel, _ today: [SessionDataModel]) -> String? {
    let p = t.progress(in: today)
    guard p.count == 0, p.seconds < 1 else { return nil }
    return t.sessions.map(\.startTime).max().map { "last \(MockFmt.ago($0))" } ?? "not started yet"
}
@MainActor private func partDone(_ t: TaskModel, _ today: [SessionDataModel]) -> Bool {
    let p = t.progress(in: today)
    return !t.isCompleted(with: p) && (p.count > 0 || p.seconds >= 1)
}

/// A daily goal's hold menu, the same on every page: TaskMenu's, with Pause (pretend) in it.
private struct GoalMenu: View {
    let task: TaskModel
    let today: [SessionDataModel]
    let onEdit: () -> Void
    var onOpenZikr: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var state = ZikrMockState.shared
    var body: some View {
        let paused = state.paused.contains(task.id)
        if !paused {
            Button { startGoal(task, resume: partDone(task, today)) } label: { Label("Start", systemImage: "play.fill") }
        }
        Button(action: onEdit) { Label("Edit goal", systemImage: "pencil") }
        if let onOpenZikr { Button(action: onOpenZikr) { Label("Open zikr", systemImage: "circle.hexagonpath") } }
        Button {
            withAnimation(.snappy) { if paused { state.paused.remove(task.id) } else { state.paused.insert(task.id) } }
        } label: { Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.circle" : "pause.circle") }
        Button {
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(task) }
        } label: { Label("Share goal…", systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
    }
}

/// A paused goal: the pause ring, its name, what's kept, Resume.
private struct PausedGoalRow: View {
    let task: TaskModel
    var showsZikr = true
    @State private var state = ZikrMockState.shared
    var body: some View {
        let best = task.streak().best
        HStack(spacing: 12) {
            MockGoalRing(paused: true, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(showsZikr ? task.title : (task.customName ?? MockFmt.goal(task))).lineLimit(1)
                Text("Paused · history kept" + (best > 1 ? " · best \(best)" : ""))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { withAnimation(.snappy) { _ = state.paused.remove(task.id) } } label: {
                Text("Resume").font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().strokeBorder(Color.sage.opacity(0.7), lineWidth: 1.2))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// "Delete “Morning Durood”?" — the real delete.
private struct DeleteGoalAlert: ViewModifier {
    @Binding var task: TaskModel?
    @Environment(\.modelContext) private var context
    func body(content: Content) -> some View {
        content.alert(task.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "",
                      isPresented: Binding(get: { task != nil }, set: { if !$0 { task = nil } }),
                      presenting: task) { t in
            Button("Delete Goal", role: .destructive) {
                withAnimation { TaskModel.delete(t, in: context) }
                task = nil
            }
            Button("Cancel", role: .cancel) { task = nil }
        } message: { _ in
            Text("Its reminder goes too. The sessions you've counted stay in your history.")
        }
    }
}

// MARK: - Azkar (Azkar + Your tasks in one place)

private struct MockAzkarPage: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var zikrs: [MantraModel]
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @State private var state = ZikrMockState.shared
    @State private var query = ""
    @State private var showBuiltIns = false
    @State private var today: [SessionDataModel] = []
    @State private var openZikr: MantraModel?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var newGoalFor: MantraModel?
    @State private var newZikr = false

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private func matches(_ z: MantraModel?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        guard let z else { return false }
        return [z.name, z.fullText, z.notes].contains { $0.localizedCaseInsensitiveContains(q) }
            || z.tasks.contains { $0.title.localizedCaseInsensitiveContains(q) }
    }
    /// The wheel's order (sortOrder), paused ones left out.
    private var live: [TaskModel] { tasks.filter { !state.paused.contains($0.id) } }
    private var liveShown: [TaskModel] { live.filter { matches($0.mantra) } }
    private var pausedShown: [TaskModel] { tasks.filter { state.paused.contains($0.id) && matches($0.mantra) } }
    private var other: [MantraModel] {
        zikrs.filter { $0.tasks.isEmpty && !$0.isBuiltIn && matches($0) }.sorted { $0.totalCount > $1.totalCount }
    }
    private var builtIns: [MantraModel] { zikrs.filter { $0.tasks.isEmpty && $0.isBuiltIn && matches($0) } }
    private var doneToday: Int { live.filter { $0.isCompleted(with: $0.progress(in: today)) }.count }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Flow.heading("Your azkar", live.isEmpty ? "Everything you say, and how often"
                                  : "\(doneToday) of \(live.count) daily goals done today")
                    Flow.newCard("A new zikr") { newZikr = true }
                }
                .bareRow()
            }
            if !liveShown.isEmpty {
                Section {
                    ForEach(liveShown) { t in
                        // Tap → its zikr (the goal, the card, its sessions); hold → the options, or drag to reorder.
                        Button { openZikr = t.mantra } label: { TaskRow(task: t, sessions: today, note: lastDone(t, today)) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                GoalMenu(task: t, today: today, onEdit: { editing = t },
                                         onOpenZikr: { openZikr = t.mantra }, onDelete: { toDelete = t })
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { toDelete = t } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                            }
                            .listRowBackground(Flow.card)
                    }
                    .onMove(perform: searching ? nil : move)
                } header: {
                    Flow.header("Daily goals")
                } footer: {
                    if !searching { Text("The wheel's order. Hold and drag to change it; hold for options.") }
                }
            }
            if !pausedShown.isEmpty {
                Section {
                    ForEach(pausedShown) { t in
                        Button { openZikr = t.mantra } label: { PausedGoalRow(task: t) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                GoalMenu(task: t, today: today, onEdit: { editing = t },
                                         onOpenZikr: { openZikr = t.mantra }, onDelete: { toDelete = t })
                            }
                            .listRowBackground(Flow.card)
                    }
                } header: { Flow.header("Paused") }
            }
            if !other.isEmpty {
                Section { ForEach(other) { zikrRow($0) } } header: { Flow.header("Other azkar") }
            }
            if !builtIns.isEmpty {
                Section {
                    Button { withAnimation(.snappy) { showBuiltIns.toggle() } } label: {
                        HStack {
                            Text(showBuiltIns ? "Hide the built-in azkar" : "Show \(builtIns.count) built-in azkar")
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.5)).rotationEffect(.degrees(showBuiltIns ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Flow.card)
                    if showBuiltIns { ForEach(builtIns) { zikrRow($0) } }
                } header: { Flow.header("Built-in") }
            }
        }
        .mockList()
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search in a Liquid Glass bar at the bottom (owner, decision zikr-search-place A)
            Flow.search("Search your azkar", $query).padding(.horizontal, 16).padding(.bottom, 6)
        })
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openZikr) { MockZikrPage(zikr: $0) }
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(item: $newGoalFor) { NewTaskFlow(locked: $0) }
        .newZikrCard(isPresented: $newZikr)
        .modifier(DeleteGoalAlert(task: $toDelete))
        .onAppear { today = ZikrReminders.todaysSessions(context) }
        .onChange(of: editing) { _, _ in today = ZikrReminders.todaysSessions(context) }
        .task {
            // The Paused group with something in it: the least-used goal (pretend).
            guard !state.seededPause, tasks.count > 2,
                  let t = tasks.min(by: { $0.sessions.count < $1.sessions.count }) else { return }
            state.seededPause = true
            state.paused.insert(t.id)
        }
    }

    /// A zikr without a goal: the Azkar list's own row (its words, count and pace); hold → make it a daily goal.
    private func zikrRow(_ z: MantraModel) -> some View {
        Button { openZikr = z } label: { ZikrListRow(mantra: z) }
            .buttonStyle(.plain)
            .contextMenu {
                Button { openZikr = z } label: { Label("Open", systemImage: "circle.hexagonpath") }
                Button { newGoalFor = z } label: { Label("Make it a daily goal", systemImage: "target") }
            }
            .listRowBackground(Flow.card)
    }

    /// The real reorder (the wheel follows sortOrder); paused goals keep their places.
    private func move(from source: IndexSet, to destination: Int) {
        var order = live
        order.move(fromOffsets: source, toOffset: destination)
        var next = order.makeIterator()
        let full = tasks.map { state.paused.contains($0.id) ? $0 : (next.next() ?? $0) }
        for (i, t) in full.enumerated() where t.sortOrder != i { t.sortOrder = i }
        try? context.save()
    }
}

// MARK: - A zikr

/// The zikr card as the modal shows it (owner: "we poured a lot of our heart and soul into that"): the name and its lock,
/// the tabs down the left, the words and notes in the inner box, count in sets at the foot. A tap opens the real modal.
private struct ModalLookCard: View {
    let zikr: MantraModel
    let open: () -> Void
    var body: some View {
        let full = zikr.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = zikr.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(zikr.name).font(.system(size: 24, weight: .light, design: .rounded)).lineLimit(1)
                    if zikr.isBuiltIn { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.tertiary) }
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 34, height: 34).barGlass(Circle())
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text").foregroundStyle(Color.sage)
                            .frame(width: 32, height: 32).background(Circle().fill(Color.sage.opacity(0.14)))
                        tab("waveform", has: zikr.audioData != nil)
                        tab("photo", has: zikr.imageData != nil)
                    }
                    VStack(spacing: 10) {
                        if full.isEmpty && notes.isEmpty {
                            Text("No words or notes yet. Tap to add them.").font(.footnote).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if !full.isEmpty { ZikrFullText(text: full, arabicSize: 22, otherSize: 15).frame(maxWidth: .infinity) }
                        if !full.isEmpty && !notes.isEmpty { Divider() }
                        if !notes.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "doc.text").foregroundStyle(.tertiary)
                                BulletedNotes(text: notes).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 124)   // as tall as the tabs beside it (no gap under it)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground)))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Flow.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func tab(_ symbol: String, has: Bool) -> some View {
        Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                if has { Circle().fill(Color.sage).frame(width: 6, height: 6).offset(x: -4, y: 6) }
            }
    }
}

private struct MockZikrPage: View {
    let zikr: MantraModel
    @Environment(\.modelContext) private var context
    @State private var state = ZikrMockState.shared
    @State private var card: ZikrCardRequest?
    @State private var today: [SessionDataModel] = []
    @State private var asking: TaskModel?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var addingGoal = false
    @State private var showAll = false
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?

    private var sessions: [SessionDataModel] { zikr.sessions.sorted { $0.startTime > $1.startTime } }
    private var goals: [TaskModel] { zikr.tasks.sorted { $0.sortOrder < $1.sortOrder } }
    /// Start's goal: the first one still to do today, else the first.
    private var nextGoal: TaskModel? {
        let live = goals.filter { !state.paused.contains($0.id) }
        return live.first { !$0.isCompleted(with: $0.progress(in: today)) } ?? live.first
    }
    /// The last few prayer days' sessions, a section each as History groups them.
    private var recentDays: [(key: String, date: Date, items: [SessionDataModel])] {
        var order: [String] = [], groups: [String: [SessionDataModel]] = [:], dates: [String: Date] = [:]
        for s in sessions {
            let k = PrayerDay.key(for: s.startTime)
            if groups[k] == nil {
                guard order.count < 3 else { break }
                order.append(k); dates[k] = PrayerDay.start(for: s.startTime)
            }
            groups[k, default: []].append(s)
        }
        return order.map { ($0, dates[$0] ?? Date(), groups[$0] ?? []) }
    }

    var body: some View {
        List {
            Section { ModalLookCard(zikr: zikr) { card = ZikrCardRequest(mantra: zikr) }.bareRow() }
            if zikr.totalCount > 0 { Section { recordStrip.bareRow() } }
            if !goals.isEmpty {
                Section {
                    ForEach(goals) { g in
                        Group {
                            if state.paused.contains(g.id) {
                                PausedGoalRow(task: g, showsZikr: false)
                            } else {
                                // Tap → "Start …?" (Continue / Start over when part-done), as the zikr page does now.
                                Button { triggerSomeVibration(type: .light); asking = g } label: {
                                    TaskRow(task: g, sessions: today, showsZikr: false, showsHandle: false, note: lastDone(g, today))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contextMenu {
                            GoalMenu(task: g, today: today, onEdit: { editing = g }, onDelete: { toDelete = g })
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { toDelete = g } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                        }
                        .listRowBackground(Flow.card)
                    }
                } header: {
                    Flow.header(goals.count > 1 ? "Daily goals" : "Daily goal")
                } footer: {
                    Text("Tap a goal to start it; hold it for options.")
                }
            }
            Section {
                Flow.newCard(goals.isEmpty ? "Make it a daily goal" : "Another daily goal") { addingGoal = true }.bareRow()
            }
            ForEach(Array(recentDays.enumerated()), id: \.element.key) { i, day in
                Section {
                    ForEach(day.items) { s in
                        SessionRow(session: s, showsMantraName: false,
                                   onOpen: { sessionToOpen = s }, onDelete: { sessionToDelete = s },
                                   rowBackground: Flow.card)
                    }
                    if i == recentDays.count - 1 {
                        Button { showAll = true } label: {
                            HStack {
                                Text("All \(sessions.count) sessions")
                                Spacer()
                                Chevron()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Flow.card)
                    }
                } header: {
                    Flow.header(MockFmt.day(day.date), trailing: dayTotals(day.items))
                }
            }
        }
        .mockList()
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {
            // Start floats in Liquid Glass, always in reach: the next goal still to do.
            if let g = nextGoal {
                Button { asking = g } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 13))
                        Text("Start").font(.system(.body, design: .rounded, weight: .medium))
                    }
                    .foregroundStyle(Color.sage)
                    .padding(.horizontal, 34).frame(height: 50)
                }
                .buttonStyle(.plain)
                .barGlass(Capsule())
                .padding(.bottom, 6)
            }
        })
        .zikrCardEditor($card, allowDelete: false)
        .navigationDestination(isPresented: $showAll) { MockHistoryPage(filter: zikr.persistentModelID) }
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(isPresented: $addingGoal) { NewTaskFlow(locked: zikr) }
        .sheet(item: $sessionToOpen) { SessionPage(session: $0) }
        .modifier(DeleteGoalAlert(task: $toDelete))
        .modifier(DeleteSessionAlert(session: $sessionToDelete))
        .alert(asking.map { "Start \($0.title)?" } ?? "",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { task in
            let p = task.progress(in: today)
            if partDone(task, today) {
                Button(task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))") {
                    asking = nil; startGoal(task, resume: true)
                }
                Button("Start over") { asking = nil; startGoal(task, resume: false) }
            } else {
                Button("Start") { asking = nil; startGoal(task, resume: false) }
            }
            Button("Cancel", role: .cancel) { asking = nil }
        } message: { task in
            let p = task.progress(in: today)
            Text(task.isCompleted(with: p) ? "Done today. Start another session?"
                 : task.isCountMode ? "\(p.count) of \(task.goal) today." : "\(Int(p.seconds / 60)) of \(task.goal) min today.")
        }
        .onAppear { today = ZikrReminders.todaysSessions(context) }
        .onChange(of: editing) { _, _ in today = ZikrReminders.todaysSessions(context) }
        .onChange(of: sessionToOpen) { _, open in if open != nil { PaceCoordinator.stopAll() } }
        .task {   // `-zikrMock zikr-card`: the real card modal over the page
            guard ProcessInfo.processInfo.arguments.contains("zikr-card") else { return }
            try? await Task.sleep(for: .seconds(1.2))
            card = ZikrCardRequest(mantra: zikr)
        }
    }

    private var recordStrip: some View {
        // Sami's review: one number leads, as Give to Causes' total and the goal page's 33 do; the rest is one quiet
        // line (four equal cells gave nothing to look at first).
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let month = sessions.filter { $0.startTime >= monthStart }.reduce(0) { $0 + $1.totalCount }
        let last = sessions.first?.startTime
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MockFmt.count(zikr.totalCount)).font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
            Text("counted").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(MockFmt.count(month)) this month · \(sessions.count) sessions")
                Text([zikr.secondsPerCount.map { String(format: "%.1f s each", $0) }, last.map { "last \(MockFmt.ago($0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
            }
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Flow.card))
    }
}

/// A day's time and count, as History's header flips between them — both at once here.
@MainActor private func dayTotals(_ items: [SessionDataModel]) -> String {
    let seconds = items.reduce(0) { $0 + $1.secondsPassed }
    let count = items.reduce(0) { $0 + $1.totalCount }
    return "\(zikrDurationString(seconds)) · \(MockFmt.count(count)) counted"
}

/// "Delete this session?" — the real delete (counts come off totals and today's goals).
private struct DeleteSessionAlert: ViewModifier {
    @Binding var session: SessionDataModel?
    @Environment(\.modelContext) private var context
    func body(content: Content) -> some View {
        content.alert("Delete this session?", isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } })) {
            Button("Delete", role: .destructive) {
                if let s = session { SessionDeletion.delete([s], in: context) }
                session = nil
            }
            Button("Cancel", role: .cancel) { session = nil }
        } message: {
            Text("Its count comes off your totals and today's goals. This can't be undone.")
        }
    }
}

/// Sami's review: rows under the floating Start fade out (iOS 26's soft scroll edge) — in v3 "Morning Durood goal" read
/// through the glass.
private struct SoftBottomEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectStyle(.soft, for: .bottom) } else { content }
    }
}

/// Start's bar: on iOS 26 a safe-area BAR (`safeAreaBar`), which the soft scroll edge fades the rows under — a plain
/// `safeAreaInset` gets no edge effect.
private struct BottomBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.safeAreaBar(edge: .bottom, content: bar) }
        else { content.safeAreaInset(edge: .bottom, content: bar) }
    }
}

// MARK: - History

private struct MockHistoryPage: View {
    let filter: PersistentIdentifier?
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]
    @Query private var zikrs: [MantraModel]
    @State private var state = ZikrMockState.shared
    @State private var openZikr: MantraModel?
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var selecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var confirmDelete = false
    /// One filter at a time, as Give to Causes' (owner: search, or a filter for common things — no chips).
    enum Filter: Hashable {
        case goals, freestyle, zikr(PersistentIdentifier, String), week, month, days30
        var title: String {
            switch self {
            case .goals: "Daily goals"
            case .freestyle: "Freestyle"
            case .zikr(_, let name): name
            case .week: "This week"
            case .month: "This month"
            case .days30: "Last 30 days"
            }
        }
        var symbol: String {
            switch self {
            case .goals: "target"
            case .freestyle: "infinity"
            case .zikr: "circle.hexagonpath"
            case .week, .month, .days30: "calendar"
            }
        }
    }
    @State private var active: Filter?

    private var shown: [SessionDataModel] {
        let q = state.historyQuery.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current, now = Date()
        return sessions.filter { s in
            switch active {
            case .goals?: if s.task == nil { return false }
            case .freestyle?: if s.mantra != nil { return false }
            case .zikr(let id, _)?: if s.mantra?.persistentModelID != id { return false }
            case .week?: if s.startTime < (cal.date(byAdding: .day, value: -7, to: now) ?? now) { return false }
            case .month?: if s.startTime < (cal.dateInterval(of: .month, for: now)?.start ?? now) { return false }
            case .days30?: if s.startTime < (cal.date(byAdding: .day, value: -30, to: now) ?? now) { return false }
            case nil: break
            }
            guard !q.isEmpty else { return true }
            let words = [s.mantra?.name ?? "Freestyle", s.task?.title ?? "", s.mantra?.notes ?? "",
                         s.startTime.formatted(.dateTime.weekday(.wide)), s.startTime.formatted(.dateTime.month(.wide))]
            return words.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    private var days: [(key: String, date: Date, items: [SessionDataModel])] {
        var order: [String] = [], groups: [String: [SessionDataModel]] = [:], dates: [String: Date] = [:]
        for s in shown.prefix(150) {
            let k = PrayerDay.key(for: s.startTime)
            if groups[k] == nil { order.append(k); dates[k] = PrayerDay.start(for: s.startTime) }
            groups[k, default: []].append(s)
        }
        return order.map { ($0, dates[$0] ?? Date(), groups[$0] ?? []) }
    }
    private var usedZikrs: [MantraModel] { zikrs.filter { !$0.sessions.isEmpty }.sorted { $0.sessions.count > $1.sessions.count } }

    var body: some View {
        List {
            Section {
                Flow.heading("History", "\(MockFmt.count(shown.count)) sessions · \(MockFmt.count(shown.reduce(0) { $0 + $1.totalCount })) counted")
                    .frame(maxWidth: .infinity)
                    .bareRow()
            }
            ForEach(days, id: \.key) { day in
                Section {
                    ForEach(day.items) { s in row(s) }
                } header: {
                    Flow.header(MockFmt.day(day.date), trailing: dayTotals(day.items))
                }
            }
        }
        .mockList()
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search + filter in a Liquid Glass bar at the bottom (decision zikr-search-place A)
            HStack(spacing: 10) {
                if selecting {
                    // Select mode: the bar holds Delete instead (History's bottom-bar Delete, in glass).
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text(selection.isEmpty ? "Delete" : "Delete (\(selection.count))")
                            .font(.body.weight(.medium)).foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)
                            .frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .barGlass(Capsule())
                    .disabled(selection.isEmpty)
                } else {
                    Flow.search("A zikr, a goal, \"Friday\"", Binding(get: { state.historyQuery }, set: { state.historyQuery = $0 }))
                    filterMenu
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        })
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation { selecting.toggle() }
                    if !selecting { selection.removeAll() } else { PaceCoordinator.stopAll() }
                }
            }
        }
        .navigationDestination(item: $openZikr) { MockZikrPage(zikr: $0) }
        .sheet(item: $sessionToOpen) { s in
            SessionPage(session: s, onOpenZikr: s.mantra.map { m in { openZikr = m } })
        }
        .modifier(DeleteSessionAlert(session: $sessionToDelete))
        .alert(selection.count == 1 ? "Delete 1 session?" : "Delete \(selection.count) sessions?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let doomed = shown.filter { selection.contains($0.persistentModelID) }
                withAnimation { SessionDeletion.delete(doomed, in: context) }
                selection.removeAll()
                selecting = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their counts come off your totals and today's goals. This can't be undone.")
        }
        .onChange(of: sessionToOpen) { _, open in if open != nil { PaceCoordinator.stopAll() } }
        .onAppear {
            if let filter, let z = zikrs.first(where: { $0.persistentModelID == filter }) { active = .zikr(z.persistentModelID, z.name) }
        }
    }

    /// History's own row: the zikr, the time, the kind and goal, the moon, the count, the time and the pace pill (tap it
    /// to feel the pace); tap → the session's page, hold → its options, swipe → delete.
    @ViewBuilder private func row(_ s: SessionDataModel) -> some View {
        let r = SessionRow(session: s, tappable: !selecting,
                           onMantra: s.mantra.map { m in { openZikr = m } },
                           onOpen: { sessionToOpen = s }, onDelete: { sessionToDelete = s },
                           rowBackground: Flow.card)
        if selecting {
            SelectableRow(selected: $selection, id: s.persistentModelID) { r }.listRowBackground(Flow.card)
        } else {
            r
        }
    }

    /// Give to Causes' filter beside the search: a plain filter glyph, a sage pill with its name while one is on.
    private var filterMenu: some View {
        Menu {
            if active != nil {
                Button { withAnimation(.snappy) { active = nil } } label: { Label("Show all", systemImage: "xmark.circle") }
            }
            Section("Kind") { option(.goals); option(.freestyle) }
            Section("When") { option(.week); option(.month); option(.days30) }
            Menu {
                ForEach(usedZikrs) { z in option(.zikr(z.persistentModelID, z.name)) }
            } label: { Label("A zikr", systemImage: "circle.hexagonpath") }
        } label: {
            if let active {
                HStack(spacing: 5) {
                    Image(systemName: active.symbol).font(.caption)
                    Text(active.title).font(.subheadline).lineLimit(1)
                }
                .fontWeight(.semibold).foregroundStyle(Color.sage)
                .padding(.horizontal, 12).frame(height: 44)
                .barGlass(Capsule())
                .frame(maxWidth: 150)
            } else {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .barGlass(Circle())
            }
        }
    }

    private func option(_ f: Filter) -> some View {
        Button { withAnimation(.snappy) { active = f } } label: {
            if active == f { Label(f.title, systemImage: "checkmark") } else { Label(f.title, systemImage: f.symbol) }
        }
    }
}
#endif
