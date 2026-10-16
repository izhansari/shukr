//
//  ZikrArea.swift
//  shukr
//
//  The Zikr area (owner, 2026-10-14: built from the redesign mockups and their rounds with Sami — "I wanna get this new
//  flow in today"). Places are pages: Your azkar (the daily goals in the wheel's order, paused goals, the other azkar)
//  and History (the month's reward hero, each day in its own flat card); things are sheets: a zikr (its goal's card —
//  chips, "50 a day", ring, sentence, 14 days — the card, its last 3 sessions, Start) and a session. Pausing a goal is
//  real (`TaskModel.pausedAt`, schema 2.9.0): off the wheel, reminders, widgets and Shortcuts. Its pages: `ZikrAreaPage` → `YourAzkarPage` / `ZikrHistoryHome`, `ZikrSheet`;
//  DEBUG `-zikrMock [azkar|zikr|zikr-card|goal|history|history-zikr|history-select|tour]` opens a page over the app (DEBUG
//  screenshots). The audit and flow board: board/mocks/zikr-redesign/artifact/.
//

import SwiftUI
import SwiftData
import WidgetKit

/// Which of the Zikr area's two places a door opens (the wheel's clock → History, books → Your azkar).
enum ZikrAreaStart {
    case azkar, history
    /// History filtered to one prayer day (Journey's day page, its zikr row).
    case day(Date)
}

/// The wheel's hold menu (owner, with his screenshot): Edit goal · Open zikr (the new page, not
/// the old stats sheet) · Reorder goals · Pause · Share goal… · Delete….
@MainActor @ViewBuilder func goalWheelMenu(_ task: TaskModel, onEdit: @escaping () -> Void, onOpenZikr: @escaping () -> Void,
                                              onReorder: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
    Button(action: onEdit) { Label("Edit task", systemImage: "pencil") }
    if task.mantra != nil { Button(action: onOpenZikr) { Label("Open zikr", systemImage: "circle.hexagonpath") } }
    Button {
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); onReorder() }
    } label: { Label("Reorder tasks", systemImage: "arrow.up.arrow.down") }
    Button { withAnimation(.snappy) { setGoalPaused(task, true) } } label: {
        Label("Pause", systemImage: "pause.circle")
    }
    Button {
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(task) }
    } label: { Label("Share task…", systemImage: "square.and.arrow.up") }
    Divider()
    Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
}

/// Pause or resume a daily goal (decision zikr-pause A): off the wheel, its reminder and the widgets while paused; its
/// history and best streak are kept.
@MainActor func setGoalPaused(_ t: TaskModel, _ on: Bool) {
    t.pausedAt = on ? Date() : nil
    guard let context = t.modelContext else { return }
    try? context.save()
    NotificationScheduler.reschedule(context: context, reason: on ? "goal paused" : "goal resumed")
    WidgetCenter.shared.reloadAllTimelines()
}

extension View {
    /// The wheel's "Open zikr": a zikr's page, pushed (owner, 2026-10-15).
    @MainActor @ViewBuilder func zikrSheet(_ item: Binding<MantraModel?>) -> some View {
        modifier(WheelZikrSheet(item: item))
    }
}

/// History's search text and the DEBUG screenshot routes' state.
@MainActor @Observable final class ZikrAreaState {
    static let shared = ZikrAreaState()
    var historyQuery = ""
    /// `-zikrMock history-select`: History opens in select mode with its first day picked (a screenshot).
    var startSelecting = false
}

#if DEBUG
struct ZikrScreenshotHost: ViewModifier {
    @State private var open = false
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $open) { ZikrScreenshotRoot() }
            .task {   // a cover asked for on the first frame is dropped: a moment after launch
                guard ProcessInfo.processInfo.arguments.contains("-zikrMock") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                open = true
            }
    }
}

#endif

extension View {
    /// DEBUG `-zikrMock <route>`: a Zikr page over the app for screenshots; nothing in release builds.
    @ViewBuilder func zikrScreenshotHost() -> some View {
        #if DEBUG
        modifier(ZikrScreenshotHost())
        #else
        self
        #endif
    }
}

/// Your azkar or History, pushed from the wheel's doors.
struct ZikrAreaPage: View {
    let start: ZikrAreaStart
    var body: some View {
        Group {
            switch start {
            case .azkar: YourAzkarPage()
            case .history: ZikrHistoryHome()
            case .day(let date): ZikrHistoryHome(initial: .day(date))
            }
        }
        .fontDesign(.rounded)
    }
}

#if DEBUG
private struct ZikrScreenshotRoot: View {
    @Query private var zikrs: [MantraModel]
    @State private var path: [Route] = []
    @State private var started = false
    private enum Route: Hashable { case history(ZikrHistoryHome.Filter?) }
    @State private var sheet: Dest?
    private var mainZikr: MantraModel? { zikrs.max(by: { $0.tasks.count < $1.tasks.count }) }
    var body: some View {
        NavigationStack(path: $path) {
            YourAzkarPage()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .history(let f): ZikrHistoryHome(initial: f)
                    }
                }
                .navigationDestination(item: $sheet) { ZikrPage(zikr: $0.zikr, focus: $0.focus) }
        }
        .fontDesign(.rounded)
        .task {
            guard !started else { return }
            started = true
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-zikrMock"), i + 1 < args.count, let z = mainZikr else { return }
            switch args[i + 1] {
            case "zikr", "zikr-card": sheet = .zikr(z, source: "root")
            case "history": path = [.history(nil)]
            case "history-zikr": path = [.history(.zikr(z.persistentModelID, z.name))]
            case "history-select": ZikrAreaState.shared.startSelecting = true; path = [.history(nil)]
            case "goal": if let t = z.tasks.sorted(by: { $0.sortOrder < $1.sortOrder }).first { sheet = .goal(t, source: "root") }
            case "tour": await tour(z)
            default: break
            }
        }
    }

    /// The flow, played by itself (a recording without the simulator's taps).
    private func tour(_ z: MantraModel) async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(3)
        sheet = .zikr(z, source: "root")
        await wait(3.5)
        sheet = nil
        await wait(1)
        path = [.history(nil)]
        await wait(4)
        path = []
        await wait(3)
    }
}
#endif

// MARK: - Shared bits

private enum ZikrFmt {
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
    /// "3h 12m" · "48m" · "52s": the short form for History's ring and card.
    static func compact(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return m >= 1 ? "\(m)m" : "\(Int(s))s"
    }
    /// "1 h 12 min" · "23 min" · "40 s": time spent in all.
    static func spent(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min" }
        return m >= 1 ? "\(m) min" : "\(Int(s)) s"
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
    /// Parts from this one on are still to come (greyed out); the ones before are days already entered.
    var future: Int? = nil
    /// The part a finger is on (History's ring), drawn bolder.
    var highlight: Int? = nil
    /// A heat map (History's month, owner 2026-10-15): each lit part's strength, 0…1 — the sage deepens with it.
    var heat: [Double]? = nil
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
                let toCome = future.map { i >= $0 } ?? false
                Circle().trim(from: a, to: b)
                    .stroke(Color.primary.opacity(toCome ? 0.03 : (future != nil ? 0.13 : 0.07)),
                            style: StrokeStyle(lineWidth: highlight == i ? 7 : 4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                if f > 0 {
                    // One day picked out: it stands bold, the others step back.
                    let dim = highlight != nil && highlight != i
                    let strength = heat.map { $0.indices.contains(i) ? $0[i] : 1 } ?? (f >= 1 ? 1 : 0.6)
                    Circle().trim(from: a, to: a + (b - a) * min(f, 1))
                        .stroke(Color.sage.opacity(dim ? 0.3 * strength : strength), style: StrokeStyle(lineWidth: highlight == i ? 9 : 5, lineCap: n == 1 ? .round : .butt))
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
/// "12 of 50 today · 71% in 2 weeks" / "done today · 71% in 2 weeks" / "0 of 50 · not started yet": the last two weeks'
/// consistency in place of "last 4 days ago" (owner, 2026-10-15: how good you are at it lately, at a glance).
@MainActor private func goalLine(_ t: TaskModel, _ today: [SessionDataModel]) -> String {
    let p = t.progress(in: today)
    let of = t.isCountMode ? "\(p.count) of \(ZikrFmt.count(t.goal))" : "\(Int(p.seconds / 60)) of \(t.goal) min"
    let head = t.isCompleted(with: p) ? "done today" : (p.count > 0 || p.seconds >= 1 ? of + " today" : of)
    guard !t.sessions.isEmpty else { return head + " · not started yet" }
    return head + " · \(goalConsistency(t))% in 2 weeks"
}
/// The last 14 prayer days (today included), each day's share of the goal (capped at 1), averaged — the goal card's
/// "N% consistent" and the row's line.
@MainActor func goalConsistency(_ t: TaskModel) -> Int {
    let cal = Calendar.current, todayStart = PrayerDay.start()
    guard let from = cal.date(byAdding: .day, value: -13, to: todayStart) else { return 0 }
    var byDay: [String: [SessionDataModel]] = [:]
    for s in t.sessions where s.startTime >= from { byDay[PrayerDay.key(for: s.startTime), default: []].append(s) }
    let total = byDay.values.reduce(0.0) { $0 + min(fraction(t, $1), 1) }
    return Int((total / 14 * 100).rounded())
}
/// "3 min": the time a goal still needs today at your pace (a minutes goal: what's left of it), as Your azkar's header.
@MainActor private func timeLeft(_ t: TaskModel, _ p: TaskProgress) -> String? {
    guard let s = t.secondsLeft(p), s >= 1 else { return nil }
    return zikrEstimateString(s).replacingOccurrences(of: "~", with: "")
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
    return "\(zikrDurationString(seconds)) · \(ZikrFmt.count(count)) counted"
}

/// Where a tap on a zikr or a goal goes: its zikr's sheet (focused on that goal), zooming out of the row tapped
/// (README, the gap: "going deeper should feel like zooming in").
private struct Dest: Identifiable, Hashable {
    let zikr: MantraModel
    var focus: TaskModel? = nil
    let source: String
    var id: String { source }
    static func zikr(_ z: MantraModel, source: String) -> Dest { Dest(zikr: z, source: source) }
    static func goal(_ t: TaskModel, source: String) -> Dest? { t.mantra.map { Dest(zikr: $0, focus: t, source: source) } }
}
private extension View {
    /// A zikr's sheet, and its "All sessions in History": the sheet closes and History is pushed on this page's stack,
    /// filtered (or, on History itself, `onHistory` just sets the filter).
    func zikrSheets(_ item: Binding<Dest?>, zoom: Namespace.ID,
                    onHistory: ((ZikrHistoryHome.Filter) -> Void)? = nil) -> some View {
        modifier(ZikrSheets(item: item, zoom: zoom, onHistory: onHistory))
    }
}
private struct ZikrSheets: ViewModifier {
    @Binding var item: Dest?
    let zoom: Namespace.ID
    let onHistory: ((ZikrHistoryHome.Filter) -> Void)?
    func body(content: Content) -> some View {
        // Pushed (owner, 2026-10-15: a back chevron, not ✕), zooming out of the row tapped.
        content
            .navigationDestination(item: $item) { dest in
                ZikrPage(zikr: dest.zikr, focus: dest.focus, onHistory: onHistory)
                    .navigationTransition(.zoom(sourceID: dest.source, in: zoom))
            }
    }
}

/// The wheel's hold menu → "Open zikr": the same page, pushed on the Zikr tab's stack.
private struct WheelZikrSheet: ViewModifier {
    @Binding var item: MantraModel?
    func body(content: Content) -> some View {
        content.navigationDestination(item: $item) { ZikrPage(zikr: $0) }
    }
}

/// One daily goal as a row: its ring leads, the name, today's line (+ a bell when it has a reminder), the streak, ›.
/// No ≡ (Sami: hold-to-drag works without it; one footnote says so).
private struct GoalRow: View {
    let task: TaskModel
    let today: [SessionDataModel]
    var showsZikr = true
    @State private var state = ZikrAreaState.shared
    var body: some View {
        let paused = task.pausedAt != nil
        let streak = task.streak()
        HStack(spacing: 14) {
            SoftRing(progress: fraction(task, today), paused: paused, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(showsZikr ? task.title : (task.customName ?? ZikrFmt.goal(task))).lineLimit(1)
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
                Button { withAnimation(.snappy) { setGoalPaused(task, false) } } label: {
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
    /// The new task's "Which zikr?": the one picked shows a sage ✓ instead of ›.
    var picked = false
    var body: some View {
        // The time spent on it in all, not the pace (owner: "we don't need to see how many seconds each").
        let (spent, last) = zikr.sessionTotals
        let parts = [zikr.totalCount > 0 ? "\(ZikrFmt.count(zikr.totalCount)) counted" : nil,
                     spent >= 1 ? ZikrFmt.spent(spent) : nil,
                     last.map { "last \(ZikrFmt.ago($0))" }].compactMap { $0 }
        HStack(spacing: 14) {
            SoftRing(symbol: zikr.isBuiltIn ? "book.closed" : "circle.hexagonpath", size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(zikr.name).lineLimit(1)
                Text(parts.isEmpty ? "not said yet" : parts.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !zikr.notes.isEmpty { Image(systemName: "note.text").font(.caption).foregroundStyle(.tertiary) }
            if picked {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.sage)
            } else {
                Soft.chevron()
            }
        }
        .contentShape(Rectangle())
    }
}

/// New task's "Which zikr?" (NewTaskFlow): Your azkar's own label, card and rows, so the two read alike (owner).
struct ZikrPickSection: View {
    let title: String
    let zikrs: [MantraModel]
    let picked: MantraModel?
    let onPick: (MantraModel) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SoftLabel(title: title)
            SoftCard {
                ForEach(zikrs) { z in
                    Button { onPick(z) } label: { ZikrRow(zikr: z, picked: picked == z).cardRow() }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}
/// Your azkar's glass search capsule, for the new task's list.
struct ZikrPickSearch: View {
    @Binding var text: String
    var prompt = "Search azkar"
    var body: some View { Soft.search(prompt, $text) }
}

/// A daily goal's hold menu, the same everywhere: Start (without opening its page) · Edit goal · Open zikr · Pause ·
/// Share · Delete.
private struct GoalMenu: View {
    let task: TaskModel
    let today: [SessionDataModel]
    let onEdit: () -> Void
    var onOpenZikr: (() -> Void)? = nil
    let onDelete: () -> Void
    /// Start: the page asks Continue / Start over when the goal is part-done today (owner: the same everywhere).
    var onStart: (() -> Void)? = nil
    @State private var state = ZikrAreaState.shared
    var body: some View {
        let paused = task.pausedAt != nil
        if !paused {
            Button { if let onStart { onStart() } else { startGoal(task, resume: false) } } label: { Label("Start", systemImage: "play.fill") }
        }
        Button(action: onEdit) { Label("Edit task", systemImage: "pencil") }
        if let onOpenZikr { Button(action: onOpenZikr) { Label("Open zikr", systemImage: "circle.hexagonpath") } }
        Button {
            withAnimation(.snappy) { setGoalPaused(task, !paused) }
        } label: { Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.circle" : "pause.circle") }
        Button {
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(task) }
        } label: { Label("Share task…", systemImage: "square.and.arrow.up") }
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
            Button("Delete Task", role: .destructive) {
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

/// "Start Morning Durood? 1 of 50 today." → Continue from N · Start over · Cancel (the wheel's question, everywhere).
private struct ResumeAsk: ViewModifier {
    @Binding var task: TaskModel?
    let today: [SessionDataModel]
    let start: (TaskModel, Bool) -> Void
    func body(content: Content) -> some View {
        content.alert(task.map { "Start \($0.title)?" } ?? "",
                      isPresented: Binding(get: { task != nil }, set: { if !$0 { task = nil } }),
                      presenting: task) { g in
            let p = g.progress(in: today)
            Button(g.isCountMode ? "Continue from \(p.count)" : "Continue from \(zikrDurationString(p.seconds))") {
                task = nil; start(g, true)
            }
            Button("Start over") { task = nil; start(g, false) }
            Button("Cancel", role: .cancel) { task = nil }
        } message: { g in
            let p = g.progress(in: today)
            Text(g.isCountMode ? "\(p.count) of \(g.goal) today." : "\(Int(p.seconds / 60)) of \(g.goal) min today.")
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
            Text("Its count comes off your totals and today's tasks. This can't be undone.")
        }
    }
}

/// Sessions as regular flat rows under a label per day (owner: "flat instead and keep them like regular list items"),
/// inside the page's List so swipe-to-delete works: tap → the session's page, hold → its menu, swipe → delete, the pace as
/// quiet text you can tap to feel (only the text pulses).
private struct DayRows: View {
    let days: [(key: String, date: Date, items: [SessionDataModel])]
    /// A day's totals from all its sessions when only some are shown (a zikr's last 3 — the cold test caught "10 counted"
    /// there against History's 60 for the same day).
    var fullDays: [String: [SessionDataModel]]? = nil
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
                Text(ZikrFmt.day(day.date).uppercased()).font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Button(all ? "Deselect day" : "Select day") {
                    triggerSomeVibration(type: .light)
                    if all { selection.wrappedValue.subtract(ids) } else { selection.wrappedValue.formUnion(ids) }
                }
                .font(.caption.weight(.medium)).foregroundStyle(Color.sage).buttonStyle(.borderless)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        } else {
            SoftLabel(title: ZikrFmt.day(day.date), trailing: dayTotals(fullDays?[day.key] ?? day.items))
        }
    }
}

/// A day's sessions sit in their own flat card (owner: the day headers got lost among flat rows): each row draws its
/// piece — rounded on top for the first, at the bottom for the last — a soft lighter panel, no shadow, a faint line
/// between rows.
/// A session row's piece of its day's card (History; the day page's Zikr card too).
struct DayPiece: View {
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
                Text(["\(sessions.count) session\(sessions.count == 1 ? "" : "s")", "\(ZikrFmt.count(count)) counted",
                      last.map { "last \(ZikrFmt.ago($0))" }].compactMap { $0 }.joined(separator: " · "))
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

private struct YourAzkarPage: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var zikrs: [MantraModel]
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @Namespace private var zoom
    @State private var state = ZikrAreaState.shared
    @State private var query = ""
    @State private var showBuiltIns = false
    @State private var today: [SessionDataModel] = []
    @State private var open: Dest?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var newGoalFor: MantraModel?
    @State private var newZikr = false
    @State private var askingResume: TaskModel?
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
    private var live: [TaskModel] { tasks.filter { $0.pausedAt == nil } }
    private var liveShown: [TaskModel] { live.filter { matches($0.mantra) } }
    private var pausedShown: [TaskModel] { tasks.filter { $0.pausedAt != nil && matches($0.mantra) } }
    private var other: [MantraModel] {
        zikrs.filter { $0.tasks.isEmpty && !$0.isBuiltIn && matches($0) }.sorted { $0.totalCount > $1.totalCount }
    }
    private var builtIns: [MantraModel] { zikrs.filter { $0.tasks.isEmpty && $0.isBuiltIn && matches($0) } }

    var body: some View {
        let parts = live.map { fraction($0, today) }
        let done = parts.filter { $0 >= 1 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Soft.title("Your azkar", "\(zikrs.filter { !$0.isBuiltIn }.count) azkar · \(live.count) task\(live.count == 1 ? "" : "s")"
                           + (tasks.count > live.count ? " · \(tasks.count - live.count) paused" : ""))
                if !live.isEmpty && !searching { hero(parts: parts, done: done) }
                if !liveShown.isEmpty {
                    SoftLabel(title: "Tasks", trailing: "in the wheel's order")
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
                                .contextMenu { GoalMenu(task: t, today: today, onEdit: { editing = t }, onDelete: { toDelete = t },
                                                        onStart: { askStart(t) }) }
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
                Text("Hold a task for options, or hold and drag it to change the wheel's order.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .softPage()
        .titleInBar("Your azkar", shown: $titleShown)
        // A new zikr: the bar's own + (owner: an SF symbol top right in Liquid Glass, green — as Give to Causes' +;
        // the bar's button, so iOS 26 draws the glass).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newZikr = true } label: { Image(systemName: "plus") }
                    .tint(Color.sage)
                    .accessibilityLabel("A new zikr")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search in a Liquid Glass bar at the bottom (owner, decision zikr-search-place A)
            Soft.search("Search your azkar", $query).padding(.horizontal, 16).padding(.bottom, 6)
        })
        .zikrSheets($open, zoom: zoom)
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(item: $newGoalFor) { NewTaskFlow(locked: $0) }
        .newZikrCard(isPresented: $newZikr)
        .modifier(DeleteGoalAlert(task: $toDelete))
        .modifier(ResumeAsk(task: $askingResume, today: today) { g, resume in startGoal(g, resume: resume) })
        .onAppear { today = ZikrReminders.todaysSessions(context) }
        .onChange(of: editing) { _, _ in today = ZikrReminders.todaysSessions(context) }
    }

    private func askStart(_ t: TaskModel) {
        if partDone(t, today) { askingResume = t } else { startGoal(t, resume: false) }
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
                                 onDelete: { toDelete = t }, onStart: { askStart(t) })
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
                // The time left for today's goals at your own pace (owner), as the wheel's line works it out.
                let secondsLeft = live.filter { !$0.isCompleted(with: $0.progress(in: today)) }
                    .compactMap { $0.secondsLeft($0.progress(in: today)) }.reduce(0, +)
                if left > 0, secondsLeft > 0 {
                    Text("about " + zikrEstimateString(secondsLeft).replacingOccurrences(of: "~", with: "") + " left")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                // The ring's key only until a goal is done (Sami: good once).
                if done == 0 {
                    Text("Each part of the ring is one task.").font(.footnote).foregroundStyle(.secondary)
                } else if bestStreak > 1 {
                    Text("Your longest streak now: \(bestStreak) days").font(.footnote).foregroundStyle(.secondary)
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
                Button { newGoalFor = z } label: { Label("Make it a task", systemImage: "target") }
            }
    }

    /// The real reorder (the wheel follows sortOrder); paused goals keep their places.
    private func move(from source: IndexSet, to destination: Int) {
        var order = live
        order.move(fromOffsets: source, toOffset: destination)
        var next = order.makeIterator()
        let full = tasks.map { $0.pausedAt != nil ? $0 : (next.next() ?? $0) }
        for (i, t) in full.enumerated() where t.sortOrder != i { t.sortOrder = i }
        try? context.save()
    }
}

// MARK: - A zikr's page (owner, 2026-10-15: pushed, three tabs — "each one of these things gets the full attention rather
// than fighting for attention"; built from the mock-up he tuned over several rounds)

/// A zikr's page, pushed from wherever it's tapped (back ‹ top left): its name pinned over a hairline, the page scrolling
/// under it; share and ⋯ top right; three tabs in a thin Liquid Glass bar at the bottom — Details (the zikr: its card and
/// its numbers as the results screen shows them) · Daily goals (its goals' chips + a +, the picked goal's card shaped like
/// its row in Your azkar, the reminder and Edit under it) · History (its last 20 sessions, "All N in History ›"). Opens on
/// Daily goals when the zikr has any, else Details.
private struct ZikrPage: View {
    let zikr: MantraModel
    var focus: TaskModel? = nil
    /// Opened from History: "All N in History" goes back there with its filter set instead of pushing another History.
    var onHistory: ((ZikrHistoryHome.Filter) -> Void)? = nil

    enum Tab: String, CaseIterable, Identifiable {
        // "Details", not "Zikr" (owner: the whole page is the zikr's).
        case details = "Details", goals = "Tasks", history = "History"
        var id: String { rawValue }
    }
    /// History's goal filter (a zikr with more than one goal).
    enum HistoryPick: Hashable { case all, goal(UUID), noGoal }

    @Environment(\.circleTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Namespace private var bar
    @State private var tab: Tab
    @State private var card: ZikrCardRequest?
    @State private var today: [SessionDataModel] = []
    @State private var picked: TaskModel?
    @State private var editing: TaskModel?
    @State private var toDelete: TaskModel?
    @State private var addingGoal = false
    @State private var reminding: TaskModel?
    /// Start on a goal part-done today: Continue / Start over (ResumeAsk); else a plain "Start …?".
    @State private var askingResume: TaskModel?
    @State private var askingStart: TaskModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var sessionToOpen: SessionDataModel?
    @State private var historyPick: HistoryPick = .all
    @State private var pushedHistory: ZikrHistoryHome.Filter?
    @State private var showingPerTasbeeh = false

    init(zikr: MantraModel, focus: TaskModel? = nil, onHistory: ((ZikrHistoryHome.Filter) -> Void)? = nil) {
        self.zikr = zikr
        self.focus = focus
        self.onHistory = onHistory
        _tab = State(initialValue: focus != nil || !zikr.tasks.isEmpty ? .goals : .details)
    }

    private var sessions: [SessionDataModel] { zikr.sessions.sorted { $0.startTime > $1.startTime } }
    private var goals: [TaskModel] { zikr.tasks.sorted { $0.sortOrder < $1.sortOrder } }
    /// The card's goal: the chip picked, else the one opened, else the first still to do today, else the first.
    private var goal: TaskModel? {
        if let picked, goals.contains(picked) { return picked }
        if let focus, goals.contains(focus) { return focus }
        return goals.first { !$0.isCompleted(with: $0.progress(in: today)) } ?? goals.first
    }

    var body: some View {
        ScrollView {
            Group {
                switch tab {
                case .details: detailsTab
                case .goals: goalsTab
                case .history: historyTab
                }
            }
            .id(tab)
            .transition(.opacity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .modifier(PinnedTitle { header })
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar.padding(.horizontal, 16).padding(.bottom, 4) }
        .softPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share leads (owner: "promotes people to share their zikrs … the act of zikr in our Muslim community"):
                // on Daily goals the goal (it opens in their shukr), elsewhere the zikr's words.
                if tab == .goals, let g = goal {
                    Button { TaskSharing.share(g) } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share task")
                } else {
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share zikr")
                }
                Menu {
                    Button { card = ZikrCardRequest(mantra: zikr) } label: { Label("Edit the zikr", systemImage: "text.book.closed") }
                    Button { addingGoal = true } label: { Label(goals.isEmpty ? "Make it a task" : "Another task", systemImage: "plus") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .animation(.easeOut(duration: 0.2), value: tab)
        .zikrCardEditor($card, allowDelete: false)
        .sheet(item: $editing) { NewTaskFlow(editing: $0) }
        .sheet(isPresented: $addingGoal) { NewTaskFlow(locked: zikr) }
        .sheet(item: $sessionToOpen) { SessionPage(session: $0) }
        .sheet(item: $reminding) { t in
            // The real Remind me sheet on its own; Save writes the goal's reminder and replans the notifications.
            TaskReminderSheet(draft: ReminderDraft(t), onCancel: { reminding = nil }) { picked in
                picked.apply(to: t)
                try? context.save()
                NotificationScheduler.reschedule(context: context, reason: "task reminder")
                reminding = nil
            }
        }
        .navigationDestination(item: $pushedHistory) { ZikrHistoryHome(initial: $0) }
        .modifier(DeleteGoalAlert(task: $toDelete))
        .modifier(DeleteSessionAlert(session: $sessionToDelete))
        .modifier(ResumeAsk(task: $askingResume, today: today) { g, resume in start(g, resume: resume) })
        .alert(askingStart.map { "Start \($0.title)?" } ?? "",
               isPresented: Binding(get: { askingStart != nil }, set: { if !$0 { askingStart = nil } }),
               presenting: askingStart) { g in
            Button("Start") { askingStart = nil; start(g, resume: false) }
            Button("Cancel", role: .cancel) { askingStart = nil }
        } message: { g in
            let done = g.isCompleted(with: g.progress(in: today))
            Text(done ? "Done today. Another session adds to it." : (timeLeft(g, g.progress(in: today)).map { "About \($0)." } ?? ""))
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

    private var shareText: String {
        let words = zikr.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (words.isEmpty ? zikr.name : "\(words)\n\n— \(zikr.name)") + "\n\nCounted with shukr"
    }

    // MARK: Title and tabs

    /// The name, then a hairline between it and the page (owner).
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(zikr.name).font(.system(size: 30, weight: .light, design: .rounded)).lineLimit(2)
                .padding(.horizontal, 20)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
        .padding(.top, 2)
    }

    /// Memories' bottom bar, the page's width: a thin Liquid Glass capsule, the picked tab on a sliding pill.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(.snappy(duration: 0.3)) { tab = t } } label: {
                    Text(t.rawValue)
                        .font(.system(size: 15, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background {
                            if tab == t { Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "pill", in: bar) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(4)
        .barGlass(Capsule())
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: Details

    private var detailsTab: some View {
        VStack(spacing: 18) {
            ModalLookCard(zikr: zikr) { card = ZikrCardRequest(mantra: zikr, pane: $0) }
            if zikr.totalCount > 0 { record } else {
                Text("Not said yet").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    /// The results screen's bento (owner: "copy the confirmation page … the count, the time, and the rate"): all the time
    /// spent and everything counted, small with their symbols; the rate tall beside them, a tap flips per count ⇄ per
    /// tasbeeh (100 counts).
    private var record: some View {
        let spent = zikr.sessionTotals.seconds
        let each = zikr.secondsPerCount
        return HStack(spacing: 10) {
            VStack(spacing: 10) {
                statTile("gauge.with.needle", ZikrFmt.spent(spent), "time spent, all time")
                statTile("circle.hexagonpath", ZikrFmt.count(zikr.totalCount), "counted, all time")
            }
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(CircleMotion.label) { showingPerTasbeeh.toggle() }
            } label: {
                VStack(spacing: 2) {
                    Text("rate").font(.caption).foregroundStyle(.secondary)
                    Text(each.map { showingPerTasbeeh ? zikrDurationString($0 * 100) : String(format: "%.1fs", $0) } ?? "—")
                        .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(showingPerTasbeeh ? "per tasbeeh (100)" : "per count").font(.caption2).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ThemedRaised(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 6, offset: 3))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary).padding(11)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(each == nil)
        }
        .frame(height: 52 * 2 + 10)
    }

    private func statTile(_ icon: String, _ value: String, _ caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.55)
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(ThemedRaised(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 6, offset: 3))
    }

    // MARK: Daily goals

    @ViewBuilder private var goalsTab: some View {
        if let g = goal {
            VStack(alignment: .leading, spacing: 10) {
                // How many there are (owner: nowhere said it), in History's MOST SAID type.
                Text("\(goals.count) TASK\(goals.count == 1 ? "" : "S")")
                    .font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.secondary).padding(.leading, 4)
                goalChips
                Color.clear.frame(height: 2)
                ZikrGoalCard(goal: g, today: today) { ask(g) }
                    .id(g.id)
                    .transition(.opacity)
                goalFoot(g).padding(.horizontal, 6).padding(.top, 4)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "target").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                Text("No task yet").font(.system(size: 20, weight: .light, design: .rounded))
                Text("A task puts \(zikr.name) on your wheel each day, with a streak to keep.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { addingGoal = true } label: {
                    Text("Add a task").font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                        .padding(.horizontal, 18).frame(height: 40)
                        .overlay(Capsule().strokeBorder(Color.sage.opacity(0.6), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.vertical, 36).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
        }
    }

    /// The goals as chips (the picked one in sage, scrolling sideways when there are many — owner: "what if they have 10"),
    /// then a + (owner: add another right where the goals are).
    private var goalChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(goals) { g in
                    let on = g.id == goal?.id
                    Button { withAnimation(.snappy(duration: 0.25)) { picked = g } } label: {
                        Text(g.title).font(.subheadline.weight(on ? .medium : .regular)).lineLimit(1)
                            .foregroundStyle(on ? Color.sage : .secondary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                Button { addingGoal = true } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Another task")
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: picked?.id)
    }

    /// Under the card (owner: outside it): the reminder — sage, a tap opens it — and Edit (edit · reminder · pause ·
    /// share · delete; owner: the card is the page, these behind a button).
    private func goalFoot(_ g: TaskModel) -> some View {
        let paused = g.pausedAt != nil
        let when = ZikrReminders.summary(g)
        return HStack {
            Button { reminding = g } label: {
                HStack(spacing: 6) {
                    Label(when.map { "Reminder · \($0)" } ?? "Add a reminder", systemImage: when != nil ? "bell.fill" : "bell")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.subheadline).foregroundStyle(Color.sage).lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Menu {
                Button { editing = g } label: { Label("Edit task", systemImage: "pencil") }
                Button { reminding = g } label: { Label(when == nil ? "Add a reminder" : "Change reminder", systemImage: "bell") }
                Button { withAnimation(.snappy) { setGoalPaused(g, !paused) } } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.circle" : "pause.circle")
                }
                Button {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(0.35)); TaskSharing.share(g) }
                } label: { Label("Share task…", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { toDelete = g } label: { Label("Delete task…", systemImage: "trash") }
            } label: {
                Text("Edit").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(NeuRaised(shape: Capsule(), radius: 3, offset: 1.5))
            }
            .tint(.primary)
        }
    }

    /// The card's TODAY ring: part done → Continue / Start over; else "Start …?" (owner: a tap asks).
    private func ask(_ g: TaskModel) {
        if g.pausedAt != nil { withAnimation(.snappy) { setGoalPaused(g, false) }; return }
        if partDone(g, today) { askingResume = g } else { askingStart = g }
    }

    /// The page goes, then the wheel starts it.
    private func start(_ g: TaskModel, resume: Bool) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            startGoal(g, resume: resume)
        }
    }

    // MARK: History

    private var historyShown: [SessionDataModel] {
        switch historyPick {
        case .all: sessions
        case .goal(let id): sessions.filter { $0.task?.id == id }
        case .noGoal: sessions.filter { $0.task == nil }
        }
    }

    @ViewBuilder private var historyTab: some View {
        if sessions.isEmpty {
            Text("No sessions yet").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // Several goals: which one each session was for (owner) — chips to narrow it, and each row names its goal.
                if goals.count > 1 { historyChips }
                let shown = Array(historyShown.prefix(20))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
                        SessionRow(session: s, showsMantraName: false, onOpen: { sessionToOpen = s },
                                   onDelete: { sessionToDelete = s }, rowBackground: AnyView(Color.clear), quiet: true,
                                   showsDay: true,
                                   goalName: goals.count > 1 && historyPick == .all ? (s.task?.title ?? "no task") : nil)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground).opacity(0.55)))
                // A preview of History, not a second one (owner): the rest is the History page.
                Button { goToHistory() } label: {
                    HStack(spacing: 4) {
                        Text("All \(sessions.count) session\(sessions.count == 1 ? "" : "s") in History")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline).foregroundStyle(Color.sage)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var historyChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", .all)
                ForEach(goals) { chip($0.title, .goal($0.id)) }
                if sessions.contains(where: { $0.task == nil }) { chip("No task", .noGoal) }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: historyPick)
    }

    private func chip(_ title: String, _ pick: HistoryPick) -> some View {
        let on = historyPick == pick
        return Button { withAnimation(.snappy(duration: 0.25)) { historyPick = pick } } label: {
            Text(title).font(.subheadline.weight(on ? .medium : .regular)).lineLimit(1)
                .foregroundStyle(on ? Color.sage : .secondary)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func goToHistory() {
        let f = ZikrHistoryHome.Filter.zikr(zikr.persistentModelID, zikr.name)
        if let onHistory {
            dismiss()
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.4)); onHistory(f) }
        } else {
            pushedHistory = f
        }
    }
}

/// A goal's card, shaped like its row in Your azkar so the page reads as that row opened up (owner): its ring on the left
/// (today, soft — a tap asks to start), its name and today's line beside it; then how the last two weeks went — "9 of 14
/// days", a tap flips to how consistent that is and back after 3 s (the Salah ring's rule) — the 14 days as small rings
/// (a finger picks one and slides along; its numbers under the row, gone 3 s after lifting); then streak · best, last
/// done, the usual time a day.
private struct ZikrGoalCard: View {
    let goal: TaskModel
    let today: [SessionDataModel]
    let onRing: () -> Void
    @State private var picked: Int?
    @State private var touching = false
    @State private var showConsistency = false
    @State private var revert: Task<Void, Never>?
    @State private var dayRevert: Task<Void, Never>?
    @State private var rowBox: CGSize = .zero
    /// The Salah ring's flip (mainCircle `flipSeconds`).
    private static let flipSeconds: Double = 3

    struct Day { let date: Date; let count: Int; let seconds: TimeInterval; let fraction: Double }

    private var days: [Day] {
        let cal = Calendar.current, todayStart = PrayerDay.start()
        let mine = goal.sessions
        return (0..<14).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .day, value: -back, to: todayStart),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let those = mine.filter { $0.startTime >= start && $0.startTime < end }
            return Day(date: start, count: those.reduce(0) { $0 + $1.totalCount },
                       seconds: those.reduce(0) { $0 + $1.secondsPassed }, fraction: fraction(goal, those))
        }
    }

    var body: some View {
        let days = days
        let met = days.filter { $0.fraction >= 1 }.count
        let consistency = goalConsistency(goal)
        let s = goal.streak()
        let paused = goal.pausedAt != nil
        VStack(alignment: .leading, spacing: 16) {
            top(paused: paused)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            // How the last two weeks went; a tap flips to the consistency.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(showConsistency ? "\(consistency)%" : "\(met) of \(days.count)")
                        .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                    Text(showConsistency ? "consistent" : "days")
                        .font(.system(size: 19, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Text(showConsistency ? "of each day's goal, last two weeks" : "goal met, last two weeks")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .contentTransition(.opacity)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            VStack(spacing: 8) {
                dayRow(days)
                if let picked, days.indices.contains(picked) {
                    Text(dayLine(days[picked])).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                line(s.current > 0 ? "flame.fill" : "flame",
                     s.current > 0 ? "\(s.current) day streak · best \(max(s.best, s.current))"
                                   : (s.best > 0 ? "No streak going · best \(s.best)" : "No streak yet"),
                     sage: s.current > 0)
                line("calendar", goal.sessions.map(\.startTime).max().map { "Last done \(ZikrFmt.ago($0))" } ?? "Not started yet")
                if let usual { line("clock", "Usually \(ZikrFmt.spent(usual)) a day") }
            }
        }
        .padding(16)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
        .onChange(of: touching) { _, on in
            dayRevert?.cancel()
            guard !on, picked != nil else { return }
            dayRevert = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.flipSeconds))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { picked = nil }
            }
        }
    }

    /// The row's shape: the ring, the name, today's line.
    private func top(paused: Bool) -> some View {
        let p = goal.progress(in: today)
        let f = fraction(goal, today)
        let done = f >= 1
        return HStack(spacing: 14) {
            Button(action: { triggerSomeVibration(type: .light); onRing() }) {
                GoalTodayRing(progress: paused ? 0 : f, size: 70) {
                    VStack(spacing: 0) {
                        Text("TODAY").font(.system(size: 7.5, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary)
                        if paused {
                            Image(systemName: "pause.fill").font(.system(size: 16, weight: .light)).foregroundStyle(.secondary)
                        } else if done {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .light)).foregroundStyle(Color.sage)
                        } else {
                            Text(goal.isCountMode ? ZikrFmt.count(p.count) : "\(Int(p.seconds / 60))")
                                .font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(goal.isCountMode ? "of \(ZikrFmt.count(goal.goal))" : "of \(goal.goal) min")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused ? "Paused. Resume" : "Today. Start")
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title).font(.system(size: 20, weight: .light, design: .rounded)).lineLimit(2)
                Text(paused ? "Paused · your history is kept" : todayLine(p, done: done))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func todayLine(_ p: TaskProgress, done: Bool) -> String {
        if done { return "Done today · \(ZikrFmt.goal(goal))" }
        if let left = timeLeft(goal, p) { return "\(ZikrFmt.goal(goal)) · about \(left) left" }
        return ZikrFmt.goal(goal)
    }

    /// The 14 days as small rings; one drag over the row: touch picks a day, sliding moves it (owner), a tick per day.
    private func dayRow(_ days: [Day]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let isToday = i == days.count - 1
                VStack(spacing: 5) {
                    Text(d.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: isToday || picked == i ? .semibold : .regular))
                        .foregroundStyle(isToday || picked == i ? .primary : .tertiary)
                    ZStack {
                        Circle().stroke(Color.primary.opacity(isToday ? 0.24 : 0.17), lineWidth: isToday ? 2.6 : 2.2)
                        if d.fraction > 0 {
                            Circle().trim(from: 0, to: min(d.fraction, 1))
                                .stroke(Color.sage.opacity(d.fraction >= 1 ? 1 : 0.55),
                                        style: StrokeStyle(lineWidth: isToday ? 2.6 : 2.2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(width: 14, height: 14)
                    .padding(4)
                    .background { if picked == i { Circle().fill(Color.primary.opacity(0.1)) } }
                    .scaleEffect(picked == i ? 1.12 : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { rowBox = $0 }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                touching = true
                guard rowBox.width > 0, !days.isEmpty else { return }
                let i = min(max(Int(v.location.x / (rowBox.width / CGFloat(days.count))), 0), days.count - 1)
                if picked != i { withAnimation(.snappy(duration: 0.15)) { picked = i } }
            }
            .onEnded { _ in touching = false })
        .sensoryFeedback(.selection, trigger: picked)
    }

    /// "Mon, Oct 5 · 30 of 50 · 1m 42s".
    private func dayLine(_ d: Day) -> String {
        let day = ZikrFmt.day(d.date)
        guard d.count > 0 || d.seconds >= 1 else { return "\(day) · not done" }
        let amount = goal.isCountMode ? "\(ZikrFmt.count(d.count)) of \(ZikrFmt.count(goal.goal))"
                                      : "\(Int(d.seconds / 60)) of \(goal.goal) min"
        return "\(day) · \(amount) · \(zikrDurationString(d.seconds))"
    }

    /// The usual time on a day you did this goal, over all its days.
    private var usual: TimeInterval? {
        var byDay: [String: TimeInterval] = [:]
        for s in goal.sessions { byDay[PrayerDay.key(for: s.startTime), default: 0] += s.secondsPassed }
        let total = byDay.values.reduce(0, +)
        return byDay.isEmpty || total < 1 ? nil : total / Double(byDay.count)
    }

    /// The Salah ring's rule: a tap flips, back after 3 s; a tap while flipped goes back at once.
    private func flip() {
        triggerSomeVibration(type: .light)
        revert?.cancel()
        if showConsistency { withAnimation(.snappy) { showConsistency = false }; return }
        withAnimation(.snappy) { showConsistency = true }
        revert = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.flipSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showConsistency = false }
        }
    }

    private func line(_ symbol: String, _ text: String, sage: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.subheadline).frame(width: 20)
                .foregroundStyle(sage ? AnyShapeStyle(Color.sage) : AnyShapeStyle(.secondary))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// `SoftRing` at the card's size: a raised band in the surface, today's progress in sage on it.
private struct GoalTodayRing<Center: View>: View {
    let progress: Double
    var size: CGFloat = 70
    @ViewBuilder var center: () -> Center
    @Environment(\.circleTheme) private var theme
    var body: some View {
        let band = size * 0.09
        ZStack {
            Circle().stroke(theme.surface, lineWidth: band)
                .shadow(color: theme.shade, radius: 2.5, x: 1.5, y: 1.5)
                .shadow(color: theme.light, radius: 3, x: -1.5, y: -1.5)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.sage, style: StrokeStyle(lineWidth: band * 0.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .padding(band / 2)
    }
}

/// The page's name, pinned: iOS 26's `safeAreaBar` (the page scrolls under it, softened at the edge), the page's surface
/// before.
private struct PinnedTitle<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar
    @Environment(\.circleTheme) private var theme
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top) { bar() }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { bar().background(theme.surface) }
        }
    }
}

// MARK: - A zikr

/// The zikr's card in its sheet, in the modal's look but for looking, not editing (owner: tapping the waveform should
/// play the memo, not open the editor; "I like how you put the little pencil inside"): the tabs down the left switch the
/// box in place — the words and notes (scrolling inside a fixed box, so a long note never stretches the sheet), the
/// voice memo (play, 0.75×, loop), the photo (tap to see it whole) — and only ✎ opens the editor, on the tab you're on.
private struct ModalLookCard: View {
    let zikr: MantraModel
    /// The editor, opened on this tab.
    let edit: (MantraCardFields.Pane) -> Void
    @State private var pane: MantraCardFields.Pane = .words
    @State private var engine = ZikrAudio()
    @State private var photo: UIImage?
    @State private var viewing = false
    static let boxHeight: CGFloat = 150

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 14) {
                tab(.words, "doc.text", has: false)
                tab(.memo, "waveform", has: zikr.audioData != nil)
                tab(.photo, "photo", has: zikr.imageData != nil)
            }
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch pane {
                    case .words: words
                    case .memo: memo
                    case .photo: photoPane
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.boxHeight)
                .transition(.opacity)
                Button { engine.stopPlaying(); edit(pane) } label: {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 32, height: 32).barGlass(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Edit")
            }
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
        .task(id: blobKey(zikr.imageData)) { photo = await decodedImage(zikr.imageData) }
        .onDisappear { engine.stopPlaying() }
        .onChange(of: pane) { _, _ in engine.stopPlaying() }
        .fullScreenCover(isPresented: $viewing) { if let photo { ZikrPhotoViewer(image: photo) } }
    }

    /// A tab: sage and filled when it's the one showing; a sage dot when the memo / photo has something in it.
    private func tab(_ p: MantraCardFields.Pane, _ symbol: String, has: Bool) -> some View {
        let on = pane == p
        return Button { triggerSomeVibration(type: .light); withAnimation(.easeOut(duration: 0.15)) { pane = p } } label: {
            Image(systemName: symbol).foregroundStyle(on ? Color.sage : .secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? Color.sage.opacity(0.14) : .clear))
                .overlay(alignment: .topTrailing) {
                    if has && !on { Circle().fill(Color.sage).frame(width: 6, height: 6).offset(x: -4, y: 6) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.label)
    }

    /// The words and the notes; a long note scrolls inside the box (its foot fades so it reads as more below).
    @ViewBuilder private var words: some View {
        let full = zikr.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = zikr.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if full.isEmpty && notes.isEmpty {
            empty("doc.text", "No words or notes yet", "Add them", .words)
        } else {
            ScrollView {
                VStack(spacing: 10) {
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
                .padding(14).padding(.bottom, 26)   // clear of ✎
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82),
                                         .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    /// The voice memo, played right here: the ring play button, when it was recorded (or where it is), 0.75× and loop.
    @ViewBuilder private var memo: some View {
        if let data = zikr.audioData {
            VStack(spacing: 10) {
                Button { engine.togglePlay(data) } label: {
                    RingPlayButton(playing: engine.state == .playing, progress: engine.progress, size: 54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play voice memo")
                Text(memoLine(data)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip("0.75×", on: engine.slow) { engine.slow.toggle() }
                    chip(nil, symbol: "repeat", on: engine.loop) { engine.loop.toggle() }
                }
            }
        } else {
            empty("waveform", "No voice memo yet", "Record one", .memo)
        }
    }

    /// The photo, whole in the box; a tap shows it full screen.
    @ViewBuilder private var photoPane: some View {
        if zikr.imageData != nil {
            if let photo {
                Button { ZikrPhotoViewer.open { viewing = true } } label: {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show photo")
            } else {
                ProgressView()
            }
        } else {
            empty("photo", "No photo yet", "Add one", .photo)
        }
    }

    private func empty(_ symbol: String, _ line: String, _ action: String, _ p: MantraCardFields.Pane) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
            Text(line).font(.footnote).foregroundStyle(.secondary)
            Button(action) { edit(p) }.font(.footnote.weight(.medium)).foregroundStyle(Color.sage).buttonStyle(.plain)
        }
    }

    private func memoLine(_ data: Data) -> String {
        func mmss(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
        if engine.state == .playing || engine.state == .paused { return "\(mmss(engine.elapsed)) / \(mmss(engine.duration))" }
        if let d = ZikrAudio.recordedDate(of: data) { return "Recorded " + d.formatted(.dateTime.month(.abbreviated).day()) }
        return "Voice memo"
    }

    private func chip(_ title: String?, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if let symbol { Image(systemName: symbol) } else { Text(title ?? "") } }
                .font(.caption.weight(.medium))
                .foregroundStyle(on ? Color.sage : Color.secondary)
                .padding(.horizontal, 9).frame(height: 26)
                .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History

/// The month in History's top card (owner, 2026-10-14: time first — "my best day might have 10,000 count but five
/// minutes"): each prayer day's time and count, the month's totals, the best day by time, the most-said azkar by time.
private struct MonthStory {
    struct Day { var seconds: TimeInterval = 0; var count = 0 }
    var monthName = ""
    var days: [Day] = []           // the month's prayer days; 0 = the 1st
    var dates: [Date] = []
    var today: Int?                // today's index (days after it are still to come)
    var seconds: TimeInterval = 0
    var count = 0
    var bestDay: (seconds: TimeInterval, date: Date)?
    var top: [(name: String, seconds: TimeInterval, count: Int)] = []
    var activeDays: Int { days.filter { $0.seconds >= 1 || $0.count > 0 }.count }
    var averageSeconds: TimeInterval { activeDays > 0 ? seconds / Double(activeDays) : 0 }

    init(_ sessions: [SessionDataModel]) {
        let cal = Calendar.current, todayStart = PrayerDay.start()
        guard let month = cal.dateInterval(of: .month, for: todayStart),
              let range = cal.range(of: .day, in: .month, for: todayStart) else { return }
        monthName = todayStart.formatted(.dateTime.month(.wide))
        days = Array(repeating: Day(), count: range.count)
        dates = (0..<range.count).compactMap { cal.date(byAdding: .day, value: $0, to: month.start) }
        today = cal.component(.day, from: todayStart) - 1
        var byName: [String: (seconds: TimeInterval, count: Int)] = [:]
        for s in sessions {
            // By prayer day, as the rest of History (the ring and "N of M days" agree).
            let day = PrayerDay.start(for: s.startTime)
            guard month.contains(day) else { continue }
            let i = cal.component(.day, from: day) - 1
            guard days.indices.contains(i) else { continue }
            days[i].seconds += s.secondsPassed; days[i].count += s.totalCount
            seconds += s.secondsPassed; count += s.totalCount
            let name = s.mantra?.name ?? "Freestyle"
            byName[name, default: (0, 0)].seconds += s.secondsPassed
            byName[name, default: (0, 0)].count += s.totalCount
        }
        if let b = days.indices.max(by: { days[$0].seconds < days[$1].seconds }), days[b].seconds >= 1, dates.indices.contains(b) {
            bestDay = (days[b].seconds, dates[b])
        }
        top = byName.sorted { $0.value.seconds > $1.value.seconds }.prefix(3).map { ($0.key, $0.value.seconds, $0.value.count) }
    }
}

/// History's top card (owner): the month as a ring of days — entered days solid, the days to come greyed — with the time
/// spent in the middle ("3h 12m · over 4 days"); a tap shows the count for a few seconds (the rows follow); a finger along
/// the ring reads one day. Right: the best day by time, "4 of 14 days", the average time on a day you did zikr. The most-
/// said azkar by time under it; a tap there flips just the rows to counts.
private struct MonthHero: View {
    let s: MonthStory
    @State private var showCount = false
    @State private var rowsCount = false
    @State private var scrub: Int?
    /// A day shown for a moment (a tap on Best day lights it on the ring).
    @State private var pointed: Int?
    @State private var revert: Task<Void, Never>?
    private var shownDay: Int? { scrub ?? pointed }
    private let ringSize: CGFloat = 126
    /// Each day against the month's best (owner: see which days were better): by time, or by count while the count shows.
    /// Eased a little (^0.7) so a short day still reads; the faintest lit day stays at 0.16.
    private var heat: [Double] {
        let values = s.days.map { showCount ? Double($0.count) : $0.seconds }
        let top = values.max() ?? 0
        guard top > 0 else { return values.map { _ in 1 } }
        return values.map { 0.16 + 0.84 * pow($0 / top, 0.7) }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                SegmentRing(parts: s.days.map { $0.seconds >= 1 || $0.count > 0 ? 1 : 0 }, size: ringSize,
                            future: s.today.map { $0 + 1 }, highlight: shownDay, heat: heat) { center }
                    .contentShape(Circle())
                    .onTapGesture { flipToCount() }
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { v in scrub = day(at: v.location) }
                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrub = nil } })
                    .sensoryFeedback(.selection, trigger: scrub)
                VStack(alignment: .leading, spacing: 8) {
                    if let b = s.bestDay {
                        let on = pointed != nil
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Best day").font(.footnote).foregroundStyle(on ? Color.sage : .secondary)
                            Text("\(ZikrFmt.compact(b.seconds)) · \(b.date.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
                                .foregroundStyle(on ? Color.sage : .primary)
                        }
                        // Selected: sage on a soft sage pill, as long as its day is lit on the ring.
                        .padding(.horizontal, on ? 8 : 0).padding(.vertical, on ? 4 : 0)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.sage.opacity(on ? 0.14 : 0)))
                        .padding(.horizontal, on ? -8 : 0).padding(.vertical, on ? -4 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture { point(at: b.date) }   // lights that day on the ring; a second tap lets go
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let t = s.today { Text("\(s.activeDays) of \(t + 1) days") }
                        if s.activeDays > 0 { Text("Avg \(ZikrFmt.compact(s.averageSeconds)) a day") }
                    }
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            if !s.top.isEmpty, s.seconds >= 1 || s.count > 0 {
                let counting = showCount || rowsCount
                VStack(spacing: 10) {
                    // Says what the shares are of (owner: else the percentages changing would confuse).
                    HStack {
                        Text("MOST SAID").font(.caption.weight(.medium)).tracking(1.2)
                        Spacer()
                        // MOST SAID's type (small caps, medium, tracked), a size down (owner).
                        Text(counting ? "BY COUNT" : "BY TIME").font(.caption2.weight(.medium)).tracking(1.2)
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(.secondary)
                    ForEach(Array(s.top.enumerated()), id: \.offset) { _, t in
                        let share = counting ? Double(t.count) / Double(max(s.count, 1)) : t.seconds / max(s.seconds, 1)
                        HStack(spacing: 12) {
                            SoftRing(progress: share, size: 24)
                            Text(t.name).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(counting ? ZikrFmt.count(t.count) : ZikrFmt.compact(t.seconds)) · \(Int((share * 100).rounded()))%")
                                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(.top, 2)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { rowsCount.toggle() } }
            }
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }

    /// The month's time (or count), or the day under the finger.
    @ViewBuilder private var center: some View {
        VStack(spacing: 1) {
            if let d = shownDay, s.days.indices.contains(d), s.dates.indices.contains(d) {
                let day = s.days[d]
                // A day with counts but no time recorded (a 1-count session) shows its count, not "—".
                let byCount = showCount || (day.seconds < 1 && day.count > 0)
                Text(s.dates[d].formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(byCount ? ZikrFmt.count(day.count) : (day.seconds >= 1 ? ZikrFmt.compact(day.seconds) : "—"))
                    .font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                Text(byCount ? "counted" : (d > (s.today ?? 0) ? "to come" : "of zikr"))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(showCount ? ZikrFmt.count(s.count) : ZikrFmt.compact(s.seconds))
                    .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(showCount ? "counted" : "over \(s.activeDays) day\(s.activeDays == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("in \(s.monthName)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .minimumScaleFactor(0.6).lineLimit(1)
        .padding(.horizontal, 16)
    }

    /// A tap: the count for a few seconds, then back to time (the app's rings flip the same way).
    private func flipToCount() {
        triggerSomeVibration(type: .light)
        revert?.cancel()
        // A tap while the count shows goes straight back to time (owner: the second tap did nothing).
        if showCount { withAnimation(.snappy) { showCount = false }; return }
        withAnimation(.snappy) { showCount = true }
        revert = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showCount = false }
        }
    }

    /// Best day: a tap selects its day (lit on the ring, the text in sage) until tapped again (owner).
    private func point(at date: Date) {
        guard let i = s.dates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: date) }) else { return }
        triggerSomeVibration(type: .light)
        withAnimation(.snappy) { pointed = pointed == nil ? i : nil }
    }

    /// The day under a point on the ring (the 1st at the top, clockwise), up to today.
    private func day(at p: CGPoint) -> Int? {
        let side = ringSize + 20, c = side / 2
        var angle = atan2(p.x - c, c - p.y)
        if angle < 0 { angle += 2 * .pi }
        let n = s.days.count
        guard n > 0 else { return nil }
        return min(Int(angle / (2 * .pi) * Double(n)), n - 1)
    }
}

private struct ZikrHistoryHome: View {
    /// Opened filtered: a goal's or a zikr's page shows its sessions here (owner: "make the history page filtered to show
    /// the same stuff it would show here").
    var initial: Filter? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]
    @Query private var zikrs: [MantraModel]
    @Namespace private var zoom
    @State private var state = ZikrAreaState.shared
    @State private var open: Dest?
    @State private var sessionToOpen: SessionDataModel?
    @State private var sessionToDelete: SessionDataModel?
    @State private var selecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var confirmDelete = false
    @State private var titleShown = false
    /// The month card's numbers, worked out once per change of the sessions or the filter, not on every redraw (scrolling
    /// moves the title into the bar, typing searches).
    @State private var monthStory: MonthStory?
    /// One filter at a time, as Give to Causes' (owner: search, or a filter for common things — no chips).
    enum Filter: Hashable {
        case goals, freestyle, zikr(PersistentIdentifier, String), goal(PersistentIdentifier, String), week, month, days30
        /// One prayer day (its `PrayerDay.start`), from Journey.
        case day(Date)
        var title: String {
            switch self {
            case .day(let date): date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            case .goal(_, let name): name
            case .goals: "Tasks"
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
            case .week, .month, .days30, .day: "calendar"
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
            case .day(let date)?: return PrayerDay.start(for: s.startTime) == date
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
        let story = monthStory ?? MonthStory(base)
        List {
            Section {
                // Select is a mode on this same page (owner, as Photos / Mail): the title and the card stay put, only the
                // edges change — circles on the rows, Delete in the glass bar, Done / Cancel in the bar.
                Soft.title(active.map { $0.title } ?? "History",
                           "All time: \(ZikrFmt.count(base.count)) sessions · \(ZikrFmt.count(base.reduce(0) { $0 + $1.totalCount })) counted · \(ZikrFmt.hours(base.reduce(0) { $0 + $1.secondsPassed }))")
                    .bareRow(top: 0)
                if state.historyQuery.isEmpty { MonthHero(s: story).bareRow(top: 8, bottom: 4) }
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
                        Text(selection.isEmpty ? "Delete"
                             : "Delete \(selection.count) session\(selection.count == 1 ? "" : "s")")
                            .font(.body.weight(.medium)).foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)
                            .frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .barGlass(Capsule())
                    .disabled(selection.isEmpty)
                } else {
                    Soft.search("A zikr, a task, \"Friday\"", Binding(get: { state.historyQuery }, set: { state.historyQuery = $0 }))
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
            // While selecting, Cancel stands where back was: you can't fall out of History mid-selection.
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { withAnimation(.snappy) { selecting = false }; selection.removeAll() }
                }
            }
        }
        .navigationBarBackButtonHidden(selecting)
        .zikrSheets($open, zoom: zoom, onHistory: { f in withAnimation(.snappy) { active = f } })
        .sheet(item: $sessionToOpen) { s in
            SessionPage(session: s, onOpenZikr: s.mantra.map { m in {
                sessionToOpen = nil
                Task { @MainActor in try? await Task.sleep(for: .seconds(0.45)); open = .zikr(m, source: "s-\(s.id)") }
            } })
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
            Text("Their counts come off your totals and today's tasks. This can't be undone.")
        }
        .onChange(of: sessionToOpen) { _, open in if open != nil { PaceCoordinator.stopAll() } }
        // Recount the month card only when what it's about changes.
        .onChange(of: sessions.count) { _, _ in monthStory = MonthStory(filtered) }
        .onChange(of: active) { _, _ in monthStory = MonthStory(filtered) }
        .onAppear {
            if let initial, active == nil { active = initial }
            monthStory = MonthStory(filtered)
            if state.startSelecting, let day = byDay(Array(shown.prefix(20))).first {
                state.startSelecting = false
                selecting = true
                selection = Set(day.items.prefix(2).map(\.persistentModelID))
            }
        }
    }

    /// Whose streak (the cold test met four unlabelled ones): any zikr, or the zikr / goal History is filtered to.
    private func streakLabel(_ n: Int) -> String {
        switch active {
        case .zikr(_, let name)?: return "Longest \(name) streak: \(n) days"
        case .goal(_, let name)?: return "Longest \(name) streak: \(n) days"
        default: return "Longest streak, any zikr: \(n) days"
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
            Menu {
                ForEach(usedGoals) { t in option(.goal(t.persistentModelID, t.title)) }
            } label: { Label("A task", systemImage: "target") }
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
