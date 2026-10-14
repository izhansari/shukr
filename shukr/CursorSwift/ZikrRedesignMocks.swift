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

#if DEBUG
import SwiftUI
import SwiftData

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

@MainActor private func todaysSessions(_ t: TaskModel) -> [SessionDataModel] {
    let start = PrayerDay.start()
    return t.sessions.filter { $0.startTime >= start }
}
@MainActor private func todayProgress(_ t: TaskModel) -> Double {
    let p = t.progress(in: todaysSessions(t))
    return t.isCountMode ? Double(p.count) / Double(max(t.goal, 1)) : p.seconds / Double(max(t.goal, 1) * 60)
}

// MARK: - Azkar (Azkar + Your tasks in one place)

private struct MockAzkarPage: View {
    @Query(sort: \MantraModel.name) private var zikrs: [MantraModel]
    @Query(sort: \TaskModel.sortOrder) private var tasks: [TaskModel]
    @State private var state = ZikrMockState.shared
    @State private var query = ""
    @State private var showBuiltIns = false

    private func matches(_ z: MantraModel) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [z.name, z.fullText, z.notes].contains { $0.localizedCaseInsensitiveContains(q) }
            || z.tasks.contains { $0.title.localizedCaseInsensitiveContains(q) }
    }
    private var live: [TaskModel] { tasks.filter { !state.paused.contains($0.id) } }
    private var daily: [MantraModel] {
        var seen = Set<PersistentIdentifier>(), out: [MantraModel] = []
        for t in live {
            if let z = t.mantra, !seen.contains(z.persistentModelID), matches(z) { seen.insert(z.persistentModelID); out.append(z) }
        }
        return out
    }
    private var paused: [MantraModel] {
        let dailyIDs = Set(daily.map(\.persistentModelID))
        return zikrs.filter { z in !dailyIDs.contains(z.persistentModelID) && z.tasks.contains { state.paused.contains($0.id) } && matches(z) }
    }
    private var other: [MantraModel] {
        zikrs.filter { $0.tasks.isEmpty && !$0.isBuiltIn && matches($0) }.sorted { $0.totalCount > $1.totalCount }
    }
    private var builtIns: [MantraModel] { zikrs.filter { $0.tasks.isEmpty && $0.isBuiltIn && matches($0) } }
    private var doneToday: Int { live.filter { todayProgress($0) >= 1 }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Flow.heading("Your azkar", live.isEmpty ? "Everything you say, and how often"
                              : "\(doneToday) of \(live.count) daily goals done today")
                Flow.newCard("A new zikr")
                if !daily.isEmpty { Flow.group("Daily") { rows(daily) } }
                if !paused.isEmpty { Flow.group("Paused") { rows(paused) } }
                if !other.isEmpty { Flow.group("Other azkar") { rows(other) } }
                if !builtIns.isEmpty {
                    Flow.group("Built-in") {
                        Button { withAnimation(.snappy) { showBuiltIns.toggle() } } label: {
                            FlowRow(title: showBuiltIns ? "Hide the built-in azkar" : "Show \(builtIns.count) built-in azkar") {
                                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.secondary.opacity(0.5)).rotationEffect(.degrees(showBuiltIns ? 180 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        if showBuiltIns { Flow.divider; rows(builtIns) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search in a Liquid Glass bar at the bottom (owner, decision zikr-search-place A)
            Flow.search("Search your azkar", $query).padding(.horizontal, 16).padding(.bottom, 6)
        })
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The Paused group with something in it: the least-used goal (pretend).
            guard !state.seededPause, tasks.count > 2,
                  let t = tasks.min(by: { $0.sessions.count < $1.sessions.count }) else { return }
            state.seededPause = true
            state.paused.insert(t.id)
        }
    }

    @ViewBuilder private func rows(_ list: [MantraModel]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { i, z in
            if i > 0 { Flow.divider }
            NavigationLink(value: MockRoute.zikr(z.persistentModelID)) { row(z) }.buttonStyle(.plain)
        }
    }

    private func row(_ z: MantraModel) -> some View {
        let goals = z.tasks.sorted { $0.sortOrder < $1.sortOrder }
        let liveGoals = goals.filter { !state.paused.contains($0.id) }
        let last = z.sessions.map(\.startTime).max()
        let progress = liveGoals.isEmpty ? 0 : liveGoals.map(todayProgress).reduce(0, +) / Double(liveGoals.count)
        var detail: [String] = []
        if liveGoals.count > 1 { detail.append("\(liveGoals.count) daily goals") }
        else if let g = liveGoals.first { detail.append(MockFmt.goal(g)) }
        else if !goals.isEmpty { detail.append("Paused") }
        else if z.totalCount > 0 { detail.append("\(MockFmt.count(z.totalCount)) counted") }
        if let last { detail.append("last \(MockFmt.ago(last))") }
        // Sami's review: the ring leads, as on Your tasks (on the right it read as a checkbox to tick), and every row
        // ends in the same chevron, as "Which zikr?" does.
        return HStack(spacing: 0) {
            if !goals.isEmpty {
                MockGoalRing(progress: progress, paused: liveGoals.isEmpty, size: 24).padding(.leading, 16)
            }
            FlowRow(title: z.name, detail: detail.joined(separator: " · ")) { Chevron() }
        }
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
    @State private var state = ZikrMockState.shared
    @State private var card: ZikrCardRequest?

    private var sessions: [SessionDataModel] { zikr.sessions.sorted { $0.startTime > $1.startTime } }
    private var goals: [TaskModel] { zikr.tasks.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ModalLookCard(zikr: zikr) { card = ZikrCardRequest(mantra: zikr) }
                if zikr.totalCount > 0 { recordStrip }
                Flow.group(goals.count > 1 ? "Daily goals" : "Daily goal") {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                        if i > 0 { Flow.divider }
                        goalRow(g)
                    }
                }
                Flow.newCard(goals.isEmpty ? "Make it a daily goal" : "Another daily goal")
                if !sessions.isEmpty {
                    Flow.group("Recent") {
                        ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { i, s in
                            if i > 0 { Flow.divider }
                            sessionRow(s)
                        }
                        Flow.divider
                        NavigationLink(value: MockRoute.history(zikr.persistentModelID)) {
                            FlowRow(title: "All \(sessions.count) sessions") { Chevron() }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 90)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {
            // Start floats in Liquid Glass, always in reach.
            Button {} label: {
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
        })
        .zikrCardEditor($card, allowDelete: false)
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
        let counted = sessions.filter { $0.totalCount > 0 }
        let pace = counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1.secondsPassed } / Double(counted.reduce(0) { $0 + $1.totalCount })
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MockFmt.count(zikr.totalCount)).font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
            Text("counted").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(MockFmt.count(month)) this month")
                Text(String(format: "%.1f s each", pace))   // "last …" is on each goal's row already
            }
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Flow.card))
    }

    @ViewBuilder private func goalRow(_ g: TaskModel) -> some View {
        let isPaused = state.paused.contains(g.id)
        let s = g.streak()
        let p = todayProgress(g)
        HStack(spacing: 12) {
            // The ring leads, as on the azkar list and Your tasks (Sami's review).
            MockGoalRing(progress: p, paused: isPaused, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.customName.map { "\($0) · \(MockFmt.goal(g))" } ?? MockFmt.goal(g)).lineLimit(1)
                Text(line(g, p, s, isPaused)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !isPaused, let r = ZikrReminders.summary(g) {
                    Label(r, systemImage: "bell").font(.footnote).foregroundStyle(Color.sage)
                }
            }
            Spacer(minLength: 8)
            if isPaused {
                Button { withAnimation(.snappy) { _ = state.paused.remove(g.id) } } label: {
                    Text("Resume").font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().strokeBorder(Color.sage.opacity(0.7), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
        .contextMenu {
            Button { } label: { Label("Start", systemImage: "play.fill") }
            Button { } label: { Label("Edit goal", systemImage: "pencil") }
            Button { withAnimation(.snappy) { if isPaused { state.paused.remove(g.id) } else { state.paused.insert(g.id) } } } label: {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.circle" : "pause.circle")
            }
        }
    }

    private func line(_ g: TaskModel, _ p: Double, _ s: TaskStreak, _ paused: Bool) -> String {
        var parts: [String] = []
        if paused {
            parts.append("Paused · history kept")
        } else if p >= 1 {
            parts.append("Done today")
        } else if p > 0 {
            let done = g.progress(in: todaysSessions(g))
            parts.append(g.isCountMode ? "\(done.count) of \(g.goal) today" : "\(Int(done.seconds / 60)) of \(g.goal) min today")
        } else if let last = g.sessions.map(\.startTime).max() {
            parts.append("last \(MockFmt.ago(last))")
        } else {
            parts.append("not started yet")
        }
        if !paused, s.current > 1 { parts.append("\(s.current)-day streak") }
        if s.best > 1 { parts.append("best \(s.best)") }
        return parts.joined(separator: " · ")
    }

    private func sessionRow(_ s: SessionDataModel) -> some View {
        FlowRow(title: MockFmt.day(s.startTime), detail: sessionDetail(s)) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(MockFmt.count(s.totalCount)).monospacedDigit()
                Text(MockFmt.duration(s.secondsPassed)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

@MainActor private func sessionDetail(_ s: SessionDataModel) -> String {
    var parts = [s.startTime.formatted(date: .omitted, time: .shortened)]
    if let t = s.task { parts.append(t.title + " goal") }
    if s.endedAsleep { parts.append("fell asleep") }
    return parts.joined(separator: " · ")
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
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]
    @Query private var zikrs: [MantraModel]
    @State private var state = ZikrMockState.shared
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
        for s in shown.prefix(120) {
            let k = PrayerDay.key(for: s.startTime)
            if groups[k] == nil { order.append(k); dates[k] = PrayerDay.start(for: s.startTime) }
            groups[k, default: []].append(s)
        }
        return order.map { ($0, dates[$0] ?? Date(), groups[$0] ?? []) }
    }
    private var usedZikrs: [MantraModel] { zikrs.filter { !$0.sessions.isEmpty }.sorted { $0.sessions.count > $1.sessions.count } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Flow.heading("History", "\(MockFmt.count(shown.count)) sessions · \(MockFmt.count(shown.reduce(0) { $0 + $1.totalCount })) counted")
                ForEach(days, id: \.key) { day in
                    Flow.group(MockFmt.day(day.date), trailing: MockFmt.count(day.items.reduce(0) { $0 + $1.totalCount }) + " counted") {
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { Flow.divider }
                            FlowRow(title: s.mantra?.name ?? "Freestyle", detail: sessionDetail(s)) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(MockFmt.count(s.totalCount)).monospacedDigit()
                                    Text(MockFmt.duration(s.secondsPassed)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
        .modifier(SoftBottomEdge())
        .modifier(BottomBar {   // search + filter in a Liquid Glass bar at the bottom (decision zikr-search-place A)
            HStack(spacing: 10) {
                Flow.search("A zikr, a goal, \"Friday\"", Binding(get: { state.historyQuery }, set: { state.historyQuery = $0 }))
                filterMenu
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        })
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Select") {} } }
        .onAppear {
            if let filter, let z = zikrs.first(where: { $0.persistentModelID == filter }) { active = .zikr(z.persistentModelID, z.name) }
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
