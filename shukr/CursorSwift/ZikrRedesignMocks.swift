//
//  ZikrRedesignMocks.swift
//  shukr
//
//  DEBUG only: mockups of the Zikr area redesign (audit for the owner, 2026-10-14). Round 7 (round 6 + the owner's and
//  Sami's notes: one raised card per section, no ≡, a goal's own page instead of the Start sheet). In Sami's design language
//  (board/mocks/design-library/README.md): the soft look (the Zikr page's surface, raised cards, rings in a groove), one
//  hero ring per page and quiet rows under it with small rings as data, search and filters in a bottom glass bar, a
//  zikr's page zooming out of the row you tapped, Start as a glass sheet (symbol in a ring → light title → grey line →
//  icon lines → soft pill + quiet line). Round 5's behaviour stays: the pages are Lists, so the gestures are the real
//  ones (hold-and-drag reorder, hold menus, swipe, the pace pill). Drawn on the real data; starting, editing, reordering
//  and deleting are real; pausing is held in memory. `-zikrMockApp` = the real wheel leading here;
//  `-zikrMock [azkar|zikr|zikr-card|history|history-zikr|tour]` opens them over the app.
//

import SwiftUI
import SwiftData

/// Where the redesign mockups take over from the real Zikr tab's pages (`-zikrMockApp`: the real wheel, with its History
/// door, Azkar door and "N of M tasks done ›" leading to the mockups — owner: "feel how the navigation is").
enum ZikrMockStart { case azkar, history }

@MainActor @ViewBuilder func zikrRedesign<Real: View>(_ start: ZikrMockStart, @ViewBuilder real: () -> Real) -> some View {
    #if DEBUG
    if ZikrMockFlag.on { ZikrMockPage(start: start) } else { real() }
    #else
    real()
    #endif
}

/// The wheel's side of the mockups (DailyTasksView): its hold menu, a paused goal off the wheel, a zikr's new page.
enum ZikrMockFlag {
    static var on: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-zikrMockApp")
        #else
        false
        #endif
    }
    /// A goal paused in the mockups (memory only) leaves the wheel.
    @MainActor static func paused(_ t: TaskModel) -> Bool {
        #if DEBUG
        on && ZikrMockState.shared.paused.contains(t.id)
        #else
        false
        #endif
    }
}

/// The wheel's hold menu in the mockups' words (owner, with his screenshot): Edit goal · Open zikr (the new page, not
/// the old stats sheet) · Reorder goals · Pause · Share goal… · Delete….
@MainActor @ViewBuilder func zikrMockWheelMenu(_ task: TaskModel, onEdit: @escaping () -> Void, onOpenZikr: @escaping () -> Void,
                                              onReorder: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
    #if DEBUG
    Button(action: onEdit) { Label("Edit goal", systemImage: "pencil") }
    if task.mantra != nil { Button(action: onOpenZikr) { Label("Open zikr", systemImage: "circle.hexagonpath") } }
    Button {
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); onReorder() }
    } label: { Label("Reorder goals", systemImage: "arrow.up.arrow.down") }
    Button { withAnimation(.snappy) { _ = ZikrMockState.shared.paused.insert(task.id) } } label: {
        Label("Pause", systemImage: "pause.circle")
    }
    Button {
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(task) }
    } label: { Label("Share goal…", systemImage: "square.and.arrow.up") }
    Divider()
    Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
    #else
    EmptyView()
    #endif
}

@MainActor @ViewBuilder func zikrMockZikrPage(_ zikr: MantraModel) -> some View {
    #if DEBUG
    MockZikrPage(zikr: zikr).fontDesign(.rounded)
    #else
    EmptyView()
    #endif
}

#if DEBUG

/// Pretend state (pausing isn't real yet) and the tour's script.
@MainActor @Observable final class ZikrMockState {
    static let shared = ZikrMockState()
    var paused: Set<UUID> = []
    var seededPause = false
    var historyQuery = ""
    /// `-zikrMock history-select`: History opens in select mode with its first day picked (a screenshot).
    var startSelecting = false
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

/// A mockup page pushed onto the real app's stack.
struct ZikrMockPage: View {
    let start: ZikrMockStart
    var body: some View {
        Group {
            switch start {
            case .azkar: MockAzkarPage()
            case .history: MockHistoryPage()
            }
        }
        .fontDesign(.rounded)
    }
}

private struct ZikrMockRoot: View {
    @Query private var zikrs: [MantraModel]
    @State private var path: [Route] = []
    @State private var started = false
    private enum Route: Hashable { case zikr(MantraModel), history(MockHistoryPage.Filter?), goal(TaskModel) }
    private var mainZikr: MantraModel? { zikrs.max(by: { $0.tasks.count < $1.tasks.count }) }
    var body: some View {
        NavigationStack(path: $path) {
            MockAzkarPage()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .zikr(let z): MockZikrPage(zikr: z)
                    case .history(let f): MockHistoryPage(initial: f)
                    case .goal(let t): MockGoalPage(task: t)
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
            case "zikr", "zikr-card": path = [.zikr(z)]
            case "history": path = [.history(nil)]
            case "history-zikr": path = [.history(.zikr(z.persistentModelID, z.name))]
            case "history-select": ZikrMockState.shared.startSelecting = true; path = [.history(nil)]
            case "goal": if let t = z.tasks.sorted(by: { $0.sortOrder < $1.sortOrder }).first { path = [.goal(t)] }
            case "tour": await tour(z)
            default: break
            }
        }
    }

    /// The flow, played by itself (a recording without the simulator's taps).
    private func tour(_ z: MantraModel) async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(3)
        path = [.zikr(z)]
        await wait(3.5)
        path.append(.history(.zikr(z.persistentModelID, z.name)))
        await wait(3.5)
        path = [.history(nil)]
        await wait(4)
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
    static func hours(_ s: TimeInterval) -> String {
        let h = Int(s / 3600)
        return h >= 1 ? "\(h) h" : "\(Int(s / 60)) min"
    }
}

/// Round 7's pieces (Sami's review of round 6): the soft look with ONE raised card per section (rows inside it, no lines
/// between them — the Salah list's card, 02 / 03), heroes bare or in their own card, the dashed add row, the glass search.
private enum Soft {
    static let radius: CGFloat = 22

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

    static func addRow(_ title: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sage)
                    .frame(width: 30, height: 30).background(Circle().fill(Color.sage.opacity(0.14)))
                Text(title).foregroundStyle(Color.sage)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Soft.radius, style: .continuous)
                .strokeBorder(Color.sage.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A light title + one grey line (README 4), left-aligned over the hero.
    static func title(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .light, design: .rounded))
            Text(line).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func chevron() -> some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
    }
}

/// One raised card holding a section's rows (Sami: "one raised card per section, no lines between rows").
private struct SoftCard<Content: View>: View {
    var padding: CGFloat = 6
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, padding)
            .background(NeuRaised(shape: RoundedRectangle(cornerRadius: Soft.radius, style: .continuous), radius: 8, offset: 4))
    }
}

/// A row inside a SoftCard.
private extension View {
    func cardRow() -> some View { padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle()) }
    /// The page's title moves into the bar once it has scrolled under it (owner: it was lost on scrolling).
    func titleInBar(_ title: String, shown: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, under in
            withAnimation(.easeOut(duration: 0.15)) { shown.wrappedValue = under }
        }
        .navigationTitle(shown.wrappedValue ? title : "")
        .navigationBarTitleDisplayMode(.inline)
    }
    /// The soft page behind a ScrollView: the Zikr page's surface.
    func softPage() -> some View { modifier(SoftPage()) }
    /// A plain List on the soft page: the session lists are regular flat rows with swipe (owner: no shadow per row).
    func softList() -> some View {
        listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 1).softPage()
    }
    /// A List row with no background or lines (the title, the hero, a card, a label).
    func bareRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
    /// A regular flat list row on the soft page, a faint line between rows.
    func flatRow() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.primary.opacity(0.1))
    }
}

private struct SoftPage: ViewModifier {
    @Environment(\.circleTheme) private var theme
    func body(content: Content) -> some View {
        content.background(theme.surface.ignoresSafeArea()).fontDesign(.rounded)
    }
}

/// A small label over a card (README: small caps), with an optional figure on the right.
private struct SoftLabel: View {
    let title: String
    var trailing: String? = nil
    var inset: CGFloat = 16
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.medium)).tracking(1.2)
            Spacer()
            if let trailing { Text(trailing).font(.caption).monospacedDigit() }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, inset)
        .padding(.top, 8)
    }
}

/// A small ring as a data glyph (README, the gap: "rings as data glyphs"): a raised band like the wheel's, progress in
/// sage on it, ✓ when done, the pause glyph when paused, or a symbol (a zikr without a goal).
private struct SoftRing: View {
    var progress: Double = 0
    var paused = false
    var symbol: String? = nil
    var size: CGFloat = 30
    @Environment(\.circleTheme) private var theme
    var body: some View {
        let band = max(2.2, size * 0.1)
        ZStack {
            Circle().stroke(theme.surface, lineWidth: band)
                .shadow(color: theme.shade, radius: 1.5, x: 1, y: 1)
                .shadow(color: theme.light, radius: 1.5, x: -1, y: -1)
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.36, weight: .light)).foregroundStyle(.secondary)
            } else if paused {
                Image(systemName: "pause.fill").font(.system(size: size * 0.28, weight: .semibold)).foregroundStyle(.tertiary)
            } else {
                Circle().trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: band, lineCap: .round)).rotationEffect(.degrees(-90))
                if progress >= 1, size >= 20 {
                    Image(systemName: "checkmark").font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Color.sage)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The hero (README 1–2): a big soft ring cut into parts — a goal each, or a day each — lit in sage by how much was done.
private struct SegmentRing<Center: View>: View {
    let parts: [Double]
    var size: CGFloat = 150
    @ViewBuilder var center: () -> Center
    @Environment(\.circleTheme) private var theme
    var body: some View {
        let n = max(parts.count, 1)
        let gap = n > 1 ? min(0.014, 0.35 / Double(n)) : 0
        ZStack {
            Circle().stroke(theme.surface, lineWidth: 10)
                .shadow(color: theme.shade, radius: 4, x: 2, y: 2)
                .shadow(color: theme.light, radius: 6, x: -2, y: -2)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, f in
                let a = Double(i) / Double(n) + gap / 2, b = Double(i + 1) / Double(n) - gap / 2
                Circle().trim(from: a, to: b)
                    .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                if f > 0 {
                    Circle().trim(from: a, to: a + (b - a) * min(f, 1))
                        .stroke(Color.sage.opacity(f >= 1 ? 1 : 0.6), style: StrokeStyle(lineWidth: 5, lineCap: n == 1 ? .round : .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            center()
        }
        .frame(width: size, height: size)
        .padding(10)
    }
}

/// Started from any of the pages: the app closes what covers the wheel and the wheel starts it (the real path).
@MainActor private func startGoal(_ t: TaskModel, resume: Bool) {
    ZikrFocus.start(t.id.uuidString, resume: resume)
}
@MainActor private func partDone(_ t: TaskModel, _ today: [SessionDataModel]) -> Bool {
    let p = t.progress(in: today)
    return !t.isCompleted(with: p) && (p.count > 0 || p.seconds >= 1)
}
@MainActor private func fraction(_ t: TaskModel, _ sessions: [SessionDataModel]) -> Double {
    let p = t.progress(in: sessions)
    return t.isCountMode ? Double(p.count) / Double(max(t.goal, 1)) : p.seconds / Double(max(t.goal, 1) * 60)
}
/// "12 of 50 today" / "done today" / "0 of 50 · last 3 days ago".
@MainActor private func goalLine(_ t: TaskModel, _ today: [SessionDataModel]) -> String {
    let p = t.progress(in: today)
    if t.isCompleted(with: p) { return "done today" }
    let of = t.isCountMode ? "\(p.count) of \(MockFmt.count(t.goal))" : "\(Int(p.seconds / 60)) of \(t.goal) min"
    if p.count > 0 || p.seconds >= 1 { return of + " today" }
    return of + " · " + (t.sessions.map(\.startTime).max().map { "last \(MockFmt.ago($0))" } ?? "not started yet")
}
/// Sessions grouped by prayer day, newest first; `limit` days at most.
@MainActor private func byDay(_ sessions: [SessionDataModel], limit: Int = .max) -> [(key: String, date: Date, items: [SessionDataModel])] {
    var order: [String] = [], groups: [String: [SessionDataModel]] = [:], dates: [String: Date] = [:]
    for s in sessions {
        let k = PrayerDay.key(for: s.startTime)
        if groups[k] == nil {
            guard order.count < limit else { break }
            order.append(k); dates[k] = PrayerDay.start(for: s.startTime)
        }
        groups[k, default: []].append(s)
    }
    return order.map { ($0, dates[$0] ?? Date(), groups[$0] ?? []) }
}
/// A day's time and count, as History's header flips between them — both at once here.
@MainActor private func dayTotals(_ items: [SessionDataModel]) -> String {
    let seconds = items.reduce(0) { $0 + $1.secondsPassed }
    let count = items.reduce(0) { $0 + $1.totalCount }
    return "\(zikrDurationString(seconds)) · \(MockFmt.count(count)) counted"
}

/// Where a tap goes: a zikr's page or a goal's page, zooming out of the row tapped (README, the gap: "going deeper should
/// feel like zooming in").
private enum Dest: Hashable {
    case zikr(MantraModel, source: String)
    case goal(TaskModel, source: String)
    var source: String {
        switch self { case .zikr(_, let s), .goal(_, let s): s }
    }
}
private extension View {
    func mockDestinations(_ item: Binding<Dest?>, zoom: Namespace.ID) -> some View {
        navigationDestination(item: item) { dest in
            Group {
                switch dest {
                case .zikr(let z, _): MockZikrPage(zikr: z)
                case .goal(let t, _): MockGoalPage(task: t)
                }
            }
            .navigationTransition(.zoom(sourceID: dest.source, in: zoom))
        }
    }
}

/// One daily goal as a row: its ring leads, the name, today's line (+ a bell when it has a reminder), the streak, ›.
/// No ≡ (Sami: hold-to-drag works without it; one footnote says so).
private struct GoalRow: View {
    let task: TaskModel
    let today: [SessionDataModel]
    var showsZikr = true
    @State private var state = ZikrMockState.shared
    var body: some View {
        let paused = state.paused.contains(task.id)
        let streak = task.streak()
        HStack(spacing: 14) {
            SoftRing(progress: fraction(task, today), paused: paused, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(showsZikr ? task.title : (task.customName ?? MockFmt.goal(task))).lineLimit(1)
                HStack(spacing: 5) {
                    Text(paused ? "Paused · history kept" : goalLine(task, today)).lineLimit(1)
                    if !paused, task.reminderKind != nil {
                        Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(Color.sage)
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if paused {
                Button { withAnimation(.snappy) { _ = state.paused.remove(task.id) } } label: {
                    Text("Resume").font(.footnote.weight(.medium)).foregroundStyle(Color.sage)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().strokeBorder(Color.sage.opacity(0.7), lineWidth: 1.1))
                }
                .buttonStyle(.borderless)
            } else if streak.current > 0 {
                TaskStreakBadge(streak: streak)
            }
            Soft.chevron()
        }
        .contentShape(Rectangle())
    }
}

/// A zikr without a goal: a ring with the beads, its name, its count, pace and when last said.
private struct ZikrRow: View {
    let zikr: MantraModel
    var body: some View {
        let last = zikr.sessions.map(\.startTime).max()
        let parts = [zikr.totalCount > 0 ? "\(MockFmt.count(zikr.totalCount)) counted" : nil,
                     zikr.secondsPerCount.map { String(format: "%.1fs each", $0) },
                     last.map { "last \(MockFmt.ago($0))" }].compactMap { $0 }
        HStack(spacing: 14) {
            SoftRing(symbol: zikr.isBuiltIn ? "book.closed" : "circle.hexagonpath", size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(zikr.name).lineLimit(1)
                Text(parts.isEmpty ? "not said yet" : parts.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !zikr.notes.isEmpty { Image(systemName: "note.text").font(.caption).foregroundStyle(.tertiary) }
            Soft.chevron()
        }
        .contentShape(Rectangle())
    }
}

/// A daily goal's hold menu, the same everywhere: Start (without opening its page) · Edit goal · Open zikr · Pause ·
/// Share · Delete.
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

/// "Delete “Morning Durood”?" — the real delete.
private struct DeleteGoalAlert: ViewModifier {
    @Binding var task: TaskModel?
    var then: () -> Void = {}
    @Environment(\.modelContext) private var context
    func body(content: Content) -> some View {
        content.alert(task.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "",
                      isPresented: Binding(get: { task != nil }, set: { if !$0 { task = nil } }),
                      presenting: task) { t in
            Button("Delete Goal", role: .destructive) {
                then()   // a goal's own page leaves first
                withAnimation { TaskModel.delete(t, in: context) }
                task = nil
            }
            Button("Cancel", role: .cancel) { task = nil }
        } message: { _ in
            Text("Its reminder goes too. The sessions you've counted stay in your history.")
        }
    }
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

/// Sessions as regular flat rows under a label per day (owner: "flat instead and keep them like regular list items"),
/// inside the page's List so swipe-to-delete works: tap → the session's page, hold → its menu, swipe → delete, the pace as
/// quiet text you can tap to feel (only the text pulses).
private struct DayRows: View {
    let days: [(key: String, date: Date, items: [SessionDataModel])]
    var showsName = true
    var tappable = true
    var selection: Binding<Set<PersistentIdentifier>>? = nil
    var zoom: Namespace.ID? = nil
    let onOpen: (SessionDataModel) -> Void
    var onZikr: ((SessionDataModel) -> Void)? = nil
    let onDelete: (SessionDataModel) -> Void
    var body: some View {
        ForEach(days, id: \.key) { day in
            Section {
                dayHeader(day).bareRow(top: 16, bottom: 6)
                ForEach(Array(day.items.enumerated()), id: \.element.id) { i, s in
                    let first = i == 0, last = i == day.items.count - 1
                    let row = SessionRow(session: s, showsMantraName: showsName, tappable: tappable,
                                         onMantra: (onZikr != nil && s.mantra != nil) ? { onZikr?(s) } : nil,
                                         onOpen: { onOpen(s) }, onDelete: { onDelete(s) },
                                         rowBackground: AnyView(DayPiece(first: first, last: last)), quiet: true)
                    Group {
                        if let selection, !tappable {
                            // Select mode: the row stays in its day's card, a sage circle leads it, a tap picks it.
                            let on = selection.wrappedValue.contains(s.persistentModelID)
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(on ? Color.sage : Color(.tertiaryLabel))
                                row
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                triggerSomeVibration(type: .light)
                                if on { selection.wrappedValue.remove(s.persistentModelID) } else { selection.wrappedValue.insert(s.persistentModelID) }
                            }
                        } else {
                            row
                        }
                    }
                    .modifier(ZoomSource(id: "s-\(s.id)", zoom: zoom))
                    .listRowInsets(EdgeInsets(top: first ? 14 : 10, leading: 32, bottom: last ? 14 : 10, trailing: 32))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DayPiece(first: first, last: last))
                }
            }
            .listSectionSeparator(.hidden)
        }
    }

    /// The day, its time and count — in select mode, "Select day" / "Deselect day" instead (picks all of that day).
    @ViewBuilder private func dayHeader(_ day: (key: String, date: Date, items: [SessionDataModel])) -> some View {
        if let selection, !tappable {
            let ids = Set(day.items.map(\.persistentModelID))
            let all = ids.isSubset(of: selection.wrappedValue)
            HStack {
                Text(MockFmt.day(day.date).uppercased()).font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Button(all ? "Deselect day" : "Select day") {
                    triggerSomeVibration(type: .light)
                    if all { selection.wrappedValue.subtract(ids) } else { selection.wrappedValue.formUnion(ids) }
                }
                .font(.caption.weight(.medium)).foregroundStyle(Color.sage).buttonStyle(.borderless)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        } else {
            SoftLabel(title: MockFmt.day(day.date), trailing: dayTotals(day.items))
        }
    }
}

/// A day's sessions sit in their own flat card (owner: the day headers got lost among flat rows): each row draws its
/// piece — rounded on top for the first, at the bottom for the last — a soft lighter panel, no shadow, a faint line
/// between rows.
private struct DayPiece: View {
    let first: Bool
    let last: Bool
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: first ? 18 : 0, bottomLeadingRadius: last ? 18 : 0,
                               bottomTrailingRadius: last ? 18 : 0, topTrailingRadius: first ? 18 : 0, style: .continuous)
            .fill(Color(.systemBackground).opacity(0.55))
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.horizontal, 16) }
            }
            .padding(.horizontal, 16)
    }
}
private extension View {
    /// A single row in its own flat card ("All N sessions").
    func pieceRow() -> some View {
        listRowInsets(EdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(DayPiece(first: true, last: true))
    }
}

/// "History · 39 sessions · last 11 days ago ›": a goal's or a zikr's way into History, filtered to it.
private struct HistoryLink: View {
    let sessions: [SessionDataModel]
    var body: some View {
        let count = sessions.reduce(0) { $0 + $1.totalCount }
        let last = sessions.map(\.startTime).max()
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                Text(["\(sessions.count) session\(sessions.count == 1 ? "" : "s")", "\(MockFmt.count(count)) counted",
                      last.map { "last \(MockFmt.ago($0))" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Soft.chevron()
        }
        .contentShape(Rectangle())
    }
}

private struct ZoomSource: ViewModifier {
    let id: String
    let zoom: Namespace.ID?
    func body(content: Content) -> some View {
        if let zoom { content.matchedTransitionSource(id: id, in: zoom) } else { content }
    }
}

/// Sami's review: rows under the floating bar fade out (iOS 26's soft scroll edge).
private struct SoftBottomEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectStyle(.soft, for: .bottom) } else { content }
    }
}

/// The bottom bar: on iOS 26 a safe-area BAR (`safeAreaBar`), which the soft scroll edge fades the rows under.
private struct BottomBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.safeAreaBar(edge: .bottom, content: bar) }
        else { content.safeAreaInset(edge: .bottom, content: bar) }
    }
}

// MARK: - Your azkar (Azkar + Your tasks in one place)

private struct MockAzkarPage: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var zikrs: [MantraModel]
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @Namespace private var zoom
    @State private var state = ZikrMockState.shared
    @State private var query = ""
    @State private var showBuiltIns = false
    @State private var today: [SessionDataModel] = []
    @State private var open: Dest?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var newGoalFor: MantraModel?
    @State private var newZikr = false
    @State private var titleShown = false
    private let rowHeight: CGFloat = 62

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

    var body: some View {
        let parts = live.map { fraction($0, today) }
        let done = parts.filter { $0 >= 1 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Soft.title("Your azkar", "\(zikrs.filter { !$0.isBuiltIn }.count) azkar · \(live.count) daily goals")
                if !live.isEmpty && !searching { hero(parts: parts, done: done) }
                Soft.addRow("A new zikr") { newZikr = true }
                if !liveShown.isEmpty {
                    SoftLabel(title: "Daily goals", trailing: "in the wheel's order")
                    SoftCard { goalList }
                }
                if !pausedShown.isEmpty {
                    SoftLabel(title: "Paused")
                    SoftCard {
                        ForEach(pausedShown) { t in
                            Button { open = .goal(t, source: "goal-\(t.id)") } label: { GoalRow(task: t, today: today) }
                                .buttonStyle(.plain)
                                .cardRow()
                                .matchedTransitionSource(id: "goal-\(t.id)", in: zoom)
                                .contextMenu { GoalMenu(task: t, today: today, onEdit: { editing = t }, onDelete: { toDelete = t }) }
                        }
                    }
                }
                if !other.isEmpty {
                    SoftLabel(title: "Other azkar")
                    SoftCard { ForEach(other) { zikrRow($0) } }
                }
                if !builtIns.isEmpty {
                    SoftLabel(title: "Built-in")
                    SoftCard {
                        Button { withAnimation(.snappy) { showBuiltIns.toggle() } } label: {
                            HStack {
                                Text(showBuiltIns ? "Hide the built-in azkar" : "Show \(builtIns.count) built-in azkar").foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary).rotationEffect(.degrees(showBuiltIns ? 180 : 0))
                            }
                            .cardRow()
                        }
                        .buttonStyle(.plain)
                        if showBuiltIns { ForEach(builtIns) { zikrRow($0) } }
                    }
                }
                Text("Hold a goal for options, or hold and drag it to change the wheel's order.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .softPage()
        .titleInBar("Your azkar", shown: $titleShown)
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search in a Liquid Glass bar at the bottom (owner, decision zikr-search-place A)
            Soft.search("Search your azkar", $query).padding(.horizontal, 16).padding(.bottom, 6)
        })
        .mockDestinations($open, zoom: zoom)
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

    /// The daily goals: a List that doesn't scroll, inside the card (its rows keep hold-and-drag reorder and swipe; a List
    /// clips each row's shadow, so the card is drawn round it instead). Its height is the rows' (Sami: it collapses else).
    private var goalList: some View {
        List {
            ForEach(liveShown) { t in
                Button { open = .goal(t, source: "goal-\(t.id)") } label: { GoalRow(task: t, today: today) }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "goal-\(t.id)", in: zoom)
                    .contextMenu {
                        GoalMenu(task: t, today: today, onEdit: { editing = t },
                                 onOpenZikr: { if let z = t.mantra { open = .zikr(z, source: "goal-\(t.id)") } },
                                 onDelete: { toDelete = t })
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { toDelete = t } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    }
                    .frame(height: rowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove(perform: searching ? nil : move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, rowHeight)
        .frame(height: CGFloat(liveShown.count) * rowHeight)
    }

    /// The hero: today's goals as one ring, a part each, and how many are done in the middle (README 1–2).
    private func hero(parts: [Double], done: Int) -> some View {
        let left = parts.count - done
        let bestStreak = live.map { $0.streak().current }.max() ?? 0
        return HStack(spacing: 18) {
            SegmentRing(parts: parts, size: 118) {
                VStack(spacing: 0) {
                    Text("\(done)").font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                    Text("of \(parts.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(left == 0 ? "All done today" : "\(left) to go today")
                    .font(.system(size: 19, weight: .light, design: .rounded))
                // The ring's key only until a goal is done (Sami: good once).
                if done == 0 {
                    Text("Each part of the ring is one goal.").font(.footnote).foregroundStyle(.secondary)
                } else if bestStreak > 1 {
                    Text("Your longest run now: \(bestStreak) days").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A zikr without a goal; hold → open it or make it a daily goal.
    private func zikrRow(_ z: MantraModel) -> some View {
        Button { open = .zikr(z, source: "zikr-\(z.id)") } label: { ZikrRow(zikr: z).cardRow() }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "zikr-\(z.id)", in: zoom)
            .contextMenu {
                Button { open = .zikr(z, source: "zikr-\(z.id)") } label: { Label("Open", systemImage: "circle.hexagonpath") }
                Button { newGoalFor = z } label: { Label("Make it a daily goal", systemImage: "target") }
            }
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

// MARK: - A goal (owner: "I'd rather it lead to a page … to edit the goal … or see the stats of it")

/// Sami's order: the goal's ring (today) with the streak under it and its last 14 days as small rings · its zikr (a quiet
/// row, so the zikr isn't orphaned) · its recent sessions · ONE soft Start pill with "Edit goal" as its quiet line;
/// Reminder · Pause · Share · Delete in the ⋯ top right.
private struct MockGoalPage: View {
    let task: TaskModel
    @Environment(\.circleTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Namespace private var zoom
    @State private var state = ZikrMockState.shared
    @State private var today: [SessionDataModel] = []
    @State private var open: Dest?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var showAll = false
    @State private var titleShown = false

    private var sessions: [SessionDataModel] { task.sessions.sorted { $0.startTime > $1.startTime } }
    /// The last 14 prayer days, oldest first: how much of the goal each one did.
    private var last14: [(date: Date, fraction: Double)] {
        let cal = Calendar.current, todayStart = PrayerDay.start()
        return (0..<14).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .day, value: -back, to: todayStart),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let those = task.sessions.filter { $0.startTime >= start && $0.startTime < end }
            return (start, fraction(task, those))
        }
    }

    var body: some View {
        let p = task.progress(in: today)
        let f = fraction(task, today)
        let paused = state.paused.contains(task.id)
        let streak = task.streak()
        List {
            Section { VStack(alignment: .leading, spacing: 14) {
                Soft.title(task.title, MockFmt.goal(task) + (ZikrReminders.summary(task).map { " · \($0)" } ?? ""))
                // The hero: today's ring, the streak, the last two weeks.
                VStack(spacing: 14) {
                    SegmentRing(parts: [f], size: 150) {
                        VStack(spacing: 0) {
                            if paused {
                                Image(systemName: "pause.fill").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                                Text("paused").font(.caption).foregroundStyle(.secondary)
                            } else if f >= 1 {
                                Image(systemName: "checkmark").font(.system(size: 30, weight: .light)).foregroundStyle(Color.sage)
                                Text("done today").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(task.isCountMode ? MockFmt.count(p.count) : "\(Int(p.seconds / 60))")
                                    .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                                Text(task.isCountMode ? "of \(MockFmt.count(task.goal)) today" : "of \(task.goal) min today")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(streakLine(streak)).font(.system(size: 17, weight: .light, design: .rounded))
                    HStack(spacing: 0) {
                        ForEach(Array(last14.enumerated()), id: \.offset) { i, d in
                            VStack(spacing: 5) {
                                SoftRing(progress: d.fraction, size: 15)
                                Text(d.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 9, weight: i == 13 ? .semibold : .regular))
                                    .foregroundStyle(i == 13 ? .primary : .tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 18).padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
                // Its zikr: a quiet row (Sami: so the zikr isn't orphaned).
                if let z = task.mantra {
                    Button { open = .zikr(z, source: "goal-zikr") } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.hexagonpath").font(.system(size: 14, weight: .light)).foregroundStyle(.secondary)
                            Text(z.name).lineLimit(1)
                            Spacer()
                            Text("the zikr").font(.footnote).foregroundStyle(.tertiary)
                            Soft.chevron()
                        }
                        .padding(.horizontal, 4).padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "goal-zikr", in: zoom)
                }
            }.bareRow(top: 0) }
            Section {
                // One History row, not a second session list (owner): History opens filtered to this goal.
                if !sessions.isEmpty {
                    Button { showAll = true } label: { HistoryLink(sessions: sessions) }
                        .buttonStyle(.plain)
                        .pieceRow()
                }
                Color.clear.frame(height: 90).bareRow()
            }
            .listSectionSeparator(.hidden)
        }
        .softList()
        .titleInBar(task.title, shown: $titleShown)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {
            // ONE soft pill, its quiet line (README 6).
            VStack(spacing: 6) {
                if !paused {
                    PrimaryButton(title: partDone(task, today)
                                  ? (task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))")
                                  : (f >= 1 ? "Start another session" : "Start")) {
                        startGoal(task, resume: partDone(task, today))
                    }
                } else {
                    PrimaryButton(title: "Resume this goal") { withAnimation(.snappy) { _ = state.paused.remove(task.id) } }
                }
                Button("Edit goal") { editing = task }.font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 24).padding(.bottom, 4)
            // The pill is see-through: the page's surface fades in behind the bar so rows don't read through it.
            .background(LinearGradient(stops: [.init(color: theme.surface.opacity(0), location: 0),
                                               .init(color: theme.surface, location: 0.35)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        })
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = task } label: { Label(task.reminderKind == nil ? "Add a reminder" : "Reminder", systemImage: "bell") }
                    Button {
                        withAnimation(.snappy) { if paused { state.paused.remove(task.id) } else { state.paused.insert(task.id) } }
                    } label: { Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.circle" : "pause.circle") }
                    Button {
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(task) }
                    } label: { Label("Share goal…", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { toDelete = task } label: { Label("Delete…", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .mockDestinations($open, zoom: zoom)
        .navigationDestination(isPresented: $showAll) { MockHistoryPage(initial: .goal(task.persistentModelID, task.title)) }
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(item: $sessionToOpen) { SessionPage(session: $0) }
        .modifier(DeleteGoalAlert(task: $toDelete, then: { dismiss() }))
        .modifier(DeleteSessionAlert(session: $sessionToDelete))
        .onAppear { today = ZikrReminders.todaysSessions(context) }
        .onChange(of: editing) { _, _ in today = ZikrReminders.todaysSessions(context) }
        .onChange(of: sessionToOpen) { _, open in if open != nil { PaceCoordinator.stopAll() } }
    }

    private func streakLine(_ s: TaskStreak) -> String {
        if s.current > 1 { return "\(s.current) days in a row" + (s.current >= s.best ? ", your best" : " · best \(s.best)") }
        if s.best > 1 { return "Best run: \(s.best) days" }
        return "Every day you meet it lights a ring below"
    }
}

// MARK: - A zikr

/// The zikr card as the modal shows it (owner: "we poured a lot of our heart and soul into that"), raised off the page:
/// the name and its lock, the tabs down the left, the words and notes in the inner box. A tap opens the real modal.
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
                    .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
                }
            }
            .padding(16)
            .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
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
    @Namespace private var zoom
    @State private var state = ZikrMockState.shared
    @State private var card: ZikrCardRequest?
    @State private var today: [SessionDataModel] = []
    @State private var open: Dest?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var addingGoal = false
    @State private var showAll = false
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var titleShown = false

    private var sessions: [SessionDataModel] { zikr.sessions.sorted { $0.startTime > $1.startTime } }
    private var goals: [TaskModel] { zikr.tasks.sorted { $0.sortOrder < $1.sortOrder } }
    /// Start's goal: the first one still to do today, else the first.
    private var nextGoal: TaskModel? {
        let live = goals.filter { !state.paused.contains($0.id) }
        return live.first { !$0.isCompleted(with: $0.progress(in: today)) } ?? live.first
    }

    var body: some View {
        List {
            Section { VStack(alignment: .leading, spacing: 14) {
                ModalLookCard(zikr: zikr) { card = ZikrCardRequest(mantra: zikr) }
                if zikr.totalCount > 0 { recordStrip }
                if !goals.isEmpty {
                    SoftLabel(title: goals.count > 1 ? "Daily goals" : "Daily goal")
                    SoftCard {
                        ForEach(goals) { g in
                            Button { open = .goal(g, source: "goal-\(g.id)") } label: {
                                GoalRow(task: g, today: today, showsZikr: false).cardRow()
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: "goal-\(g.id)", in: zoom)
                            .contextMenu {
                                GoalMenu(task: g, today: today, onEdit: { editing = g }, onDelete: { toDelete = g })
                            }
                        }
                    }
                }
                Soft.addRow(goals.isEmpty ? "Make it a daily goal" : "Another daily goal") { addingGoal = true }
            }.bareRow(top: 4) }
            Section {
                // One History row (as on a goal's page): History opens filtered to this zikr.
                if !sessions.isEmpty {
                    Button { showAll = true } label: { HistoryLink(sessions: sessions) }
                        .buttonStyle(.plain)
                        .pieceRow()
                }
                Color.clear.frame(height: 70).bareRow()   // room above Start
            }
            .listSectionSeparator(.hidden)
        }
        .softList()
        .titleInBar(zikr.name, shown: $titleShown)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {
            // Start floats in Liquid Glass, always in reach: the next goal still to do.
            if let g = nextGoal {
                Button { startGoal(g, resume: partDone(g, today)) } label: {
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
        .mockDestinations($open, zoom: zoom)
        .navigationDestination(isPresented: $showAll) { MockHistoryPage(initial: .zikr(zikr.persistentModelID, zikr.name)) }
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(isPresented: $addingGoal) { NewTaskFlow(locked: zikr) }
        .sheet(item: $sessionToOpen) { SessionPage(session: $0) }
        .modifier(DeleteGoalAlert(task: $toDelete))
        .modifier(DeleteSessionAlert(session: $sessionToDelete))
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
        // One number leads, the rest is one quiet line each (Sami's review).
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
        .padding(.horizontal, 4)
    }
}

// MARK: - History

/// What the hero says about the month (owner: "reward user … wow i did that yay me"; "we got so much data and they
/// don't see it").
private struct MonthStory {
    var count = 0
    var lastMonthCount = 0
    var lastMonthName = ""
    var dayParts: [Double] = []        // the month's days, lit when you said zikr that day
    var activeDays = 0
    var streak = 0
    var bestStreak = 0
    var allTimeSeconds: TimeInterval = 0
    var bestDay: (count: Int, date: Date)?
    var top: [(name: String, count: Int)] = []

    init(_ sessions: [SessionDataModel]) {
        let cal = Calendar.current, now = Date()
        guard let month = cal.dateInterval(of: .month, for: now),
              let last = cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: -1, to: now) ?? now),
              let days = cal.range(of: .day, in: .month, for: now) else { return }
        lastMonthName = last.start.formatted(.dateTime.month(.wide))
        var perDay: [Int: Int] = [:], byName: [String: Int] = [:]
        var dayKeys = Set<String>()
        for s in sessions {
            allTimeSeconds += s.secondsPassed
            dayKeys.insert(PrayerDay.key(for: s.startTime))
            if month.contains(s.startTime) {
                count += s.totalCount
                perDay[cal.component(.day, from: s.startTime), default: 0] += s.totalCount
                byName[s.mantra?.name ?? "Freestyle", default: 0] += s.totalCount
            } else if last.contains(s.startTime) {
                lastMonthCount += s.totalCount
            }
        }
        dayParts = days.map { perDay[$0].map { $0 > 0 ? 1 : 0 } ?? 0 }
        activeDays = perDay.values.filter { $0 > 0 }.count
        if let best = perDay.max(by: { $0.value < $1.value }), best.value > 0,
           let d = cal.date(bySetting: .day, value: best.key, of: month.start) {
            bestDay = (best.value, d)
        }
        top = byName.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
        // Days in a row (prayer days): up to today, or up to yesterday while today is still open.
        func key(_ offset: Int) -> String { PrayerDay.key(for: cal.date(byAdding: .day, value: -offset, to: PrayerDay.start()) ?? now) }
        var i = dayKeys.contains(key(0)) ? 0 : 1
        while dayKeys.contains(key(i)) { streak += 1; i += 1 }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var run = 0, prev: Date?
        for k in dayKeys.sorted() {
            guard let d = f.date(from: k) else { continue }
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            bestStreak = max(bestStreak, run); prev = d
        }
    }

    /// The one reward sentence: the biggest true thing.
    var reward: String {
        if lastMonthCount > 0 && count > lastMonthCount { return "Already more than all of \(lastMonthName)" }
        if streak >= 3 { return "\(streak) days in a row" + (streak >= bestStreak ? " — your longest yet" : "") }
        if let b = bestDay, b.count > 0 { return "Your best day: \(MockFmt.count(b.count)) on \(b.date.formatted(.dateTime.month(.abbreviated).day()))" }
        return "Every day you say zikr lights up a part of the ring"
    }
}

private struct MockHistoryPage: View {
    /// Opened filtered: a goal's or a zikr's page shows its sessions here (owner: "make the history page filtered to show
    /// the same stuff it would show here").
    var initial: Filter? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]
    @Query private var zikrs: [MantraModel]
    @Namespace private var zoom
    @State private var state = ZikrMockState.shared
    @State private var open: Dest?
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var selecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var confirmDelete = false
    @State private var titleShown = false
    /// One filter at a time, as Give to Causes' (owner: search, or a filter for common things — no chips).
    enum Filter: Hashable {
        case goals, freestyle, zikr(PersistentIdentifier, String), goal(PersistentIdentifier, String), week, month, days30
        var title: String {
            switch self {
            case .goal(_, let name): name
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
            case .goals, .goal: "target"
            case .freestyle: "infinity"
            case .zikr: "circle.hexagonpath"
            case .week, .month, .days30: "calendar"
            }
        }
    }
    @State private var active: Filter?

    /// The filter's sessions (the hero follows the filter; search only narrows the list).
    private var filtered: [SessionDataModel] {
        let cal = Calendar.current, now = Date()
        return sessions.filter { s in
            switch active {
            case .goals?: return s.task != nil
            case .freestyle?: return s.mantra == nil
            case .zikr(let id, _)?: return s.mantra?.persistentModelID == id
            case .goal(let id, _)?: return s.task?.persistentModelID == id
            case .week?: return s.startTime >= (cal.date(byAdding: .day, value: -7, to: now) ?? now)
            case .month?: return s.startTime >= (cal.dateInterval(of: .month, for: now)?.start ?? now)
            case .days30?: return s.startTime >= (cal.date(byAdding: .day, value: -30, to: now) ?? now)
            case nil: return true
            }
        }
    }
    private var shown: [SessionDataModel] {
        let q = state.historyQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return filtered }
        return filtered.filter { s in
            [s.mantra?.name ?? "Freestyle", s.task?.title ?? "", s.mantra?.notes ?? "",
             s.startTime.formatted(.dateTime.weekday(.wide)), s.startTime.formatted(.dateTime.month(.wide))]
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    private var usedZikrs: [MantraModel] { zikrs.filter { !$0.sessions.isEmpty }.sorted { $0.sessions.count > $1.sessions.count } }
    private var usedGoals: [TaskModel] { zikrs.flatMap(\.tasks).filter { !$0.sessions.isEmpty }.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        let base = filtered
        let story = MonthStory(base)
        List {
            Section {
                if selecting {
                    // Select mode is its own moment: the hero folds away, the title says what you're doing.
                    let picked = shown.filter { selection.contains($0.persistentModelID) }
                    Soft.title("Select sessions", picked.isEmpty ? "Tap sessions, or a day to pick all of it"
                               : "\(picked.count) selected · \(MockFmt.count(picked.reduce(0) { $0 + $1.totalCount })) counted")
                        .bareRow(top: 0)
                } else {
                    Soft.title(active.map { $0.title } ?? "History",
                               "\(MockFmt.count(base.count)) sessions · \(MockFmt.count(base.reduce(0) { $0 + $1.totalCount })) counted, all time")
                        .bareRow(top: 0)
                    if state.historyQuery.isEmpty { hero(story).bareRow(top: 8, bottom: 4) }
                }
            }
            DayRows(days: byDay(Array(shown.prefix(150))), tappable: !selecting,
                    selection: $selection, zoom: zoom,
                    onOpen: { sessionToOpen = $0 },
                    onZikr: { s in if let m = s.mantra { open = .zikr(m, source: "s-\(s.id)") } },
                    onDelete: { sessionToDelete = $0 })
            Color.clear.frame(height: 20).bareRow()
        }
        .softList()
        .titleInBar(active.map { $0.title } ?? "History", shown: $titleShown)
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search + filter in a Liquid Glass bar at the bottom (decision zikr-search-place A)
            HStack(spacing: 10) {
                if selecting {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text(selection.isEmpty ? "Select sessions to delete"
                             : "Delete \(selection.count) session\(selection.count == 1 ? "" : "s")")
                            .font(.body.weight(.medium)).foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)
                            .frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .barGlass(Capsule())
                    .disabled(selection.isEmpty)
                } else {
                    Soft.search("A zikr, a goal, \"Friday\"", Binding(get: { state.historyQuery }, set: { state.historyQuery = $0 }))
                    filterMenu
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        })
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation(.snappy) { selecting.toggle() }
                    if !selecting { selection.removeAll() } else { PaceCoordinator.stopAll() }
                }
            }
        }
        .mockDestinations($open, zoom: zoom)
        .sheet(item: $sessionToOpen) { s in
            SessionPage(session: s, onOpenZikr: s.mantra.map { m in { open = .zikr(m, source: "s-\(s.id)") } })
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
            if let initial, active == nil { active = initial }
            if state.startSelecting, let day = byDay(Array(shown.prefix(20))).first {
                state.startSelecting = false
                selecting = true
                selection = Set(day.items.prefix(2).map(\.persistentModelID))
            }
        }
    }

    /// The reward (owner): the month as one ring — a part per day, lit on the days you said zikr — the month's count in
    /// the middle, one sentence about the biggest true thing, then the month's most-said azkar as small rings.
    private func hero(_ s: MonthStory) -> some View {
        let month = Date().formatted(.dateTime.month(.wide))
        return VStack(spacing: 14) {
            HStack(spacing: 18) {
                SegmentRing(parts: s.dayParts, size: 126) {
                    VStack(spacing: 0) {
                        Text(MockFmt.count(s.count)).font(.system(size: 30, weight: .light, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        Text("in \(month)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.reward).font(.system(size: 18, weight: .light, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(s.activeDays) day\(s.activeDays == 1 ? "" : "s") this month")
                        if s.bestStreak > 1 { Text("Longest run \(s.bestStreak) days") }
                        Text("\(MockFmt.hours(s.allTimeSeconds)) of zikr, all time")
                    }
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            if !s.top.isEmpty, s.count > 0 {
                VStack(spacing: 10) {
                    ForEach(Array(s.top.enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 12) {
                            SoftRing(progress: Double(t.count) / Double(max(s.count, 1)), size: 24)
                            Text(t.name).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(MockFmt.count(t.count)) · \(Int((Double(t.count) / Double(max(s.count, 1)) * 100).rounded()))%")
                                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
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
            Menu {
                ForEach(usedGoals) { t in option(.goal(t.persistentModelID, t.title)) }
            } label: { Label("A daily goal", systemImage: "target") }
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
