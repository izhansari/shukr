//
//  ZikrRedesignMocks.swift
//  shukr
//
//  DEBUG only: mockups of the Zikr area redesign (audit for the owner, 2026-10-14). Round 6, in Sami's design language
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
            case .history: MockHistoryPage(filter: nil)
            }
        }
        .fontDesign(.rounded)
    }
}

private struct ZikrMockRoot: View {
    @Query private var zikrs: [MantraModel]
    @State private var path: [Route] = []
    @State private var started = false
    private enum Route: Hashable { case zikr(MantraModel), history(PersistentIdentifier?) }
    private var mainZikr: MantraModel? { zikrs.max(by: { $0.tasks.count < $1.tasks.count }) }
    var body: some View {
        NavigationStack(path: $path) {
            MockAzkarPage()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .zikr(let z): MockZikrPage(zikr: z)
                    case .history(let id): MockHistoryPage(filter: id)
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
            case "history-zikr": path = [.history(z.persistentModelID)]
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
        path.append(.history(z.persistentModelID))
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

/// Round 6's pieces: the soft look (README 1–3), the dashed add row and the glass search (5, the gap's "paging in glass").
private enum Soft {
    static let radius: CGFloat = 20

    /// A raised card, the size of a list row (inset from the screen and from its neighbours).
    struct Card: View {
        var body: some View {
            NeuRaised(shape: RoundedRectangle(cornerRadius: Soft.radius, style: .continuous), radius: 6, offset: 3)
                .padding(.horizontal, 16).padding(.vertical, 5)
        }
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
}

private extension View {
    /// The soft page: a plain List (so rows keep the real gestures) on the Zikr page's surface.
    func softList() -> some View { modifier(SoftListStyle()) }
    /// A row drawn as its own raised card.
    func softCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 15, leading: 30, bottom: 15, trailing: 30))
            .listRowSeparator(.hidden)
            .listRowBackground(Soft.Card())
    }
    /// The insets of a card row without its background (SessionRow paints its own).
    func softCardInsets() -> some View {
        listRowInsets(EdgeInsets(top: 15, leading: 30, bottom: 15, trailing: 30)).listRowSeparator(.hidden)
    }
    /// A row with no card (the title, the hero, the dashed add row, labels).
    func bareRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
    /// The page's title moves into the bar once it has scrolled under it (owner: it was lost on scrolling).
    func titleInBar(_ title: String, shown: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { _, under in
            withAnimation(.easeOut(duration: 0.15)) { shown.wrappedValue = under }
        }
        .navigationTitle(shown.wrappedValue ? title : "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SoftListStyle: ViewModifier {
    @Environment(\.circleTheme) private var theme
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .background(theme.surface.ignoresSafeArea())
            .fontDesign(.rounded)
    }
}

/// A small label over a group of cards (README: small caps), with an optional figure on the right.
private struct SoftLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.medium)).tracking(1.2)
            Spacer()
            if let trailing { Text(trailing).font(.caption).monospacedDigit() }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .bareRow(top: 16, bottom: 0)
    }
}

/// A small ring as a data glyph (README, the gap: "rings as data glyphs"): a raised band like the wheel's, today's
/// progress in sage on it, ✓ when done, the pause glyph when paused, or a symbol (a zikr without a goal).
private struct SoftRing: View {
    var progress: Double = 0
    var paused = false
    var symbol: String? = nil
    var size: CGFloat = 30
    @Environment(\.circleTheme) private var theme
    var body: some View {
        let band = max(2.5, size * 0.1)
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
                if progress >= 1 {
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
                        .stroke(Color.sage.opacity(f >= 1 ? 1 : 0.6), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
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
@MainActor private func fraction(_ t: TaskModel, _ today: [SessionDataModel]) -> Double {
    let p = t.progress(in: today)
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

/// A zikr's page zooms out of the row you tapped (README, the gap: "going deeper should feel like zooming in").
private struct ZoomTarget: Hashable {
    let zikr: MantraModel
    let source: String
}

/// One daily goal as a card row: its ring leads, the name, today's line, its reminder, the streak, the ≡ and chevron.
private struct GoalRow: View {
    let task: TaskModel
    let today: [SessionDataModel]
    var showsZikr = true
    var showsHandle = true
    @State private var state = ZikrMockState.shared
    var body: some View {
        let paused = state.paused.contains(task.id)
        let streak = task.streak()
        HStack(spacing: 14) {
            SoftRing(progress: fraction(task, today), paused: paused, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(showsZikr ? task.title : (task.customName ?? MockFmt.goal(task))).lineLimit(1)
                Text(paused ? "Paused · history kept" + (streak.best > 1 ? " · best \(streak.best)" : "") : goalLine(task, today))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                if !paused, let r = ZikrReminders.summary(task) {
                    HStack(spacing: 4) { Image(systemName: "bell.fill"); Text(r).lineLimit(1) }
                        .font(.caption2.weight(.medium)).foregroundStyle(Color.sage)
                }
            }
            Spacer(minLength: 4)
            if paused {
                Button { withAnimation(.snappy) { _ = state.paused.remove(task.id) } } label: {
                    Text("Resume").font(.footnote.weight(.medium)).foregroundStyle(Color.sage)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().strokeBorder(Color.sage.opacity(0.7), lineWidth: 1.1))
                }
                .buttonStyle(.borderless)
            } else {
                if streak.current > 0 { TaskStreakBadge(streak: streak) }
                if showsHandle { Image(systemName: "line.3.horizontal").font(.system(size: 14)).foregroundStyle(.tertiary) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
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
            SoftRing(symbol: zikr.isBuiltIn ? "book.closed" : "circle.hexagonpath", size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(zikr.name).lineLimit(1)
                Text(parts.isEmpty ? "not said yet" : parts.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !zikr.notes.isEmpty { Image(systemName: "note.text").font(.caption).foregroundStyle(.tertiary) }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
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

// MARK: - Start: a glass sheet (README 9, the template of 21 / 23)

private struct StartGoalSheet: View {
    let task: TaskModel
    let today: [SessionDataModel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = task.progress(in: today)
        let done = task.isCompleted(with: p)
        let part = partDone(task, today)
        let streak = task.streak()
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Color.sage.opacity(0.18), lineWidth: 1.2)
                Circle().trim(from: 0, to: min(fraction(task, today), 1))
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: done ? "checkmark" : "play.fill")
                    .font(.system(size: done ? 22 : 18, weight: .light)).foregroundStyle(Color.sage)
                    .offset(x: done ? 0 : 2)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 26)
            Text(task.title)
                .font(.system(.title2, design: .rounded, weight: .light))
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 16)
            Text(done ? "Done for today. Another session adds to it." : goalLine(task, today))
                .font(.system(.callout, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                line("target", MockFmt.goal(task) + (task.estimateNote(p).map { " · \($0)" } ?? ""))
                if streak.current > 0 || streak.best > 1 {
                    line("flame", streak.current > 0 ? "\(streak.current)-day streak" + (streak.best > streak.current ? " · best \(streak.best)" : " · your best")
                                                     : "best streak \(streak.best) days")
                }
                if let r = ZikrReminders.summary(task) { line("bell", r) }
            }
            .padding(.horizontal, 36).padding(.top, 14)
            Spacer(minLength: 16)
            // One soft pill, one quiet line (README 6).
            PrimaryButton(title: part ? (task.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))")
                                      : "Start") { go(resume: part) }
            Button(part ? "Start over" : "Not now") { part ? go(resume: false) : dismiss() }
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 10).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fontDesign(.rounded)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .modifier(GlassSheet())
    }

    private func go(resume: Bool) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))   // after the sheet has gone
            startGoal(task, resume: resume)
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .light)).foregroundStyle(Color.sage).frame(width: 20)
            Text(text).font(.system(.subheadline, design: .rounded, weight: .light)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

/// iOS 26 gives a partial sheet Liquid Glass by itself; before 26, the material (as TopUpSheet).
private struct GlassSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content } else { content.presentationBackground(.regularMaterial) }
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
    @State private var open: ZoomTarget?
    @State private var starting: TaskModel?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var newGoalFor: MantraModel?
    @State private var newZikr = false
    @State private var titleShown = false

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
        List {
            Section {
                Soft.title("Your azkar", "\(zikrs.filter { !$0.isBuiltIn }.count) azkar · \(live.count) daily goals")
                    .bareRow(top: 0)
                if !live.isEmpty && !searching { hero(parts: parts, done: done).bareRow() }
                Soft.addRow("A new zikr") { newZikr = true }.bareRow(top: 10)
            }
            if !liveShown.isEmpty {
                Section {
                    SoftLabel(title: "Daily goals", trailing: "in the wheel's order")
                    ForEach(liveShown) { t in
                        // Tap → Start (a glass sheet); hold → the options, or drag to reorder.
                        Button { starting = t } label: { GoalRow(task: t, today: today) }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: "goal-\(t.id)", in: zoom)
                            .contextMenu {
                                GoalMenu(task: t, today: today, onEdit: { editing = t },
                                         onOpenZikr: { if let z = t.mantra { open = ZoomTarget(zikr: z, source: "goal-\(t.id)") } },
                                         onDelete: { toDelete = t })
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { toDelete = t } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                            }
                            .softCardRow()
                    }
                    .onMove(perform: searching ? nil : move)
                }
            }
            if !pausedShown.isEmpty {
                Section {
                    SoftLabel(title: "Paused")
                    ForEach(pausedShown) { t in
                        Button { if let z = t.mantra { open = ZoomTarget(zikr: z, source: "goal-\(t.id)") } } label: {
                            GoalRow(task: t, today: today, showsHandle: false)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: "goal-\(t.id)", in: zoom)
                        .contextMenu {
                            GoalMenu(task: t, today: today, onEdit: { editing = t }, onDelete: { toDelete = t })
                        }
                        .softCardRow()
                    }
                }
            }
            if !other.isEmpty {
                Section {
                    SoftLabel(title: "Other azkar")
                    ForEach(other) { zikrRow($0) }
                }
            }
            if !builtIns.isEmpty {
                Section {
                    SoftLabel(title: "Built-in")
                    Button { withAnimation(.snappy) { showBuiltIns.toggle() } } label: {
                        HStack {
                            Text(showBuiltIns ? "Hide the built-in azkar" : "Show \(builtIns.count) built-in azkar").foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary).rotationEffect(.degrees(showBuiltIns ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .softCardRow()
                    if showBuiltIns { ForEach(builtIns) { zikrRow($0) } }
                }
            }
            Text("Tap a goal to start it. Hold it for options, or hold and drag to change the wheel's order.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).bareRow(top: 14, bottom: 24)
        }
        .softList()
        .titleInBar("Your azkar", shown: $titleShown)
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search in a Liquid Glass bar at the bottom (owner, decision zikr-search-place A)
            Soft.search("Search your azkar", $query).padding(.horizontal, 16).padding(.bottom, 6)
        })
        .navigationDestination(item: $open) { target in
            MockZikrPage(zikr: target.zikr).navigationTransition(.zoom(sourceID: target.source, in: zoom))
        }
        .sheet(item: $starting) { StartGoalSheet(task: $0, today: today) }
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
                Text(bestStreak > 1 ? "Your longest run now: \(bestStreak) days" : "Each part of the ring is one goal.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// A zikr without a goal; hold → open it or make it a daily goal.
    private func zikrRow(_ z: MantraModel) -> some View {
        Button { open = ZoomTarget(zikr: z, source: "zikr-\(z.id)") } label: { ZikrRow(zikr: z) }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "zikr-\(z.id)", in: zoom)
            .contextMenu {
                Button { open = ZoomTarget(zikr: z, source: "zikr-\(z.id)") } label: { Label("Open", systemImage: "circle.hexagonpath") }
                Button { newGoalFor = z } label: { Label("Make it a daily goal", systemImage: "target") }
            }
            .softCardRow()
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
    @State private var state = ZikrMockState.shared
    @State private var card: ZikrCardRequest?
    @State private var today: [SessionDataModel] = []
    @State private var starting: TaskModel?
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
    /// The last few prayer days' sessions, as History groups them.
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
            Section {
                ModalLookCard(zikr: zikr) { card = ZikrCardRequest(mantra: zikr) }.bareRow(top: 4, bottom: 10)
                if zikr.totalCount > 0 { recordStrip.bareRow(bottom: 4) }
            }
            if !goals.isEmpty {
                Section {
                    SoftLabel(title: goals.count > 1 ? "Daily goals" : "Daily goal")
                    ForEach(goals) { g in
                        Button { if !state.paused.contains(g.id) { starting = g } } label: {
                            GoalRow(task: g, today: today, showsZikr: false, showsHandle: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            GoalMenu(task: g, today: today, onEdit: { editing = g }, onDelete: { toDelete = g })
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { toDelete = g } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                        }
                        .softCardRow()
                    }
                }
            }
            Section {
                Soft.addRow(goals.isEmpty ? "Make it a daily goal" : "Another daily goal") { addingGoal = true }.bareRow(top: 10)
            }
            ForEach(Array(recentDays.enumerated()), id: \.element.key) { i, day in
                Section {
                    SoftLabel(title: MockFmt.day(day.date), trailing: dayTotals(day.items))
                    ForEach(day.items) { s in
                        SessionRow(session: s, showsMantraName: false,
                                   onOpen: { sessionToOpen = s }, onDelete: { sessionToDelete = s },
                                   rowBackground: AnyView(Soft.Card()))
                            .softCardInsets()
                    }
                    if i == recentDays.count - 1 {
                        Button { showAll = true } label: {
                            HStack {
                                Text("All \(sessions.count) sessions")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .softCardRow()
                    }
                }
            }
            Color.clear.frame(height: 70).bareRow()   // room above Start
        }
        .softList()
        .titleInBar(zikr.name, shown: $titleShown)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {
            // Start floats in Liquid Glass, always in reach: the next goal still to do.
            if let g = nextGoal {
                Button { starting = g } label: {
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
        .sheet(item: $starting) { StartGoalSheet(task: $0, today: today) }
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: Soft.radius, style: .continuous), radius: 6, offset: 3))
    }
}

/// A day's time and count, as History's header flips between them — both at once here.
@MainActor private func dayTotals(_ items: [SessionDataModel]) -> String {
    let seconds = items.reduce(0) { $0 + $1.secondsPassed }
    let count = items.reduce(0) { $0 + $1.totalCount }
    return "\(zikrDurationString(seconds)) · \(MockFmt.count(count)) counted"
}

/// Sami's review: rows under the floating Start fade out (iOS 26's soft scroll edge).
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
    let filter: PersistentIdentifier?
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]
    @Query private var zikrs: [MantraModel]
    @Namespace private var zoom
    @State private var state = ZikrMockState.shared
    @State private var open: ZoomTarget?
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var selecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var confirmDelete = false
    @State private var titleShown = false
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

    /// The filter's sessions (the hero follows the filter; search only narrows the list).
    private var filtered: [SessionDataModel] {
        let cal = Calendar.current, now = Date()
        return sessions.filter { s in
            switch active {
            case .goals?: return s.task != nil
            case .freestyle?: return s.mantra == nil
            case .zikr(let id, _)?: return s.mantra?.persistentModelID == id
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
        let base = filtered
        let story = MonthStory(base)
        List {
            Section {
                Soft.title(active.map { $0.title } ?? "History",
                           "\(MockFmt.count(base.count)) sessions · \(MockFmt.count(base.reduce(0) { $0 + $1.totalCount })) counted, all time")
                    .bareRow(top: 0)
                if state.historyQuery.isEmpty { hero(story).bareRow(top: 8, bottom: 6) }
            }
            ForEach(days, id: \.key) { day in
                Section {
                    SoftLabel(title: MockFmt.day(day.date), trailing: dayTotals(day.items))
                    ForEach(day.items) { s in row(s) }
                }
            }
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
                        Text(selection.isEmpty ? "Delete" : "Delete (\(selection.count))")
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
                    withAnimation { selecting.toggle() }
                    if !selecting { selection.removeAll() } else { PaceCoordinator.stopAll() }
                }
            }
        }
        .navigationDestination(item: $open) { target in
            MockZikrPage(zikr: target.zikr).navigationTransition(.zoom(sourceID: target.source, in: zoom))
        }
        .sheet(item: $sessionToOpen) { s in
            SessionPage(session: s, onOpenZikr: s.mantra.map { m in { open = ZoomTarget(zikr: m, source: "s-\(s.id)") } })
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

    /// History's own row: the zikr, the time, the kind and goal, the moon, the count, the time and the pace pill (tap it
    /// to feel the pace); tap → the session's page, hold → its options, swipe → delete.
    @ViewBuilder private func row(_ s: SessionDataModel) -> some View {
        let r = SessionRow(session: s, tappable: !selecting,
                           onMantra: s.mantra.map { m in { open = ZoomTarget(zikr: m, source: "s-\(s.id)") } },
                           onOpen: { sessionToOpen = s }, onDelete: { sessionToDelete = s },
                           rowBackground: AnyView(Soft.Card()))
            .matchedTransitionSource(id: "s-\(s.id)", in: zoom)
        if selecting {
            SelectableRow(selected: $selection, id: s.persistentModelID) { r }.softCardRow()
        } else {
            r.softCardInsets()
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
