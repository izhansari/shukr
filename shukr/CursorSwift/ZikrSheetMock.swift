#if DEBUG
import SwiftUI

// A zikr's sheet as three tabs, mocked (owner, 2026-10-15): "make these three separate tabs … each one of these things gets
// the full attention rather than fighting for attention" — Zikr · Daily goals · History, in that order. The goal card is
// its own (owner: not History's month card — "don't want someone to get confused if it looks too familiar"): today's
// count, the last two weeks as quiet dots (owner: keep seeing consistency at a glance, but not a row of rings), and the
// facts — streak, average time a day, last done. Fake data only; the look, not the wiring.
// The ⋯ menu holds the mock's switches (goal card A / B, light / dark, a zikr without a goal).
// My Dev Stuff → Zikr sheet mock-up; DEBUG `-demoZikrSheetMock`.

struct ZikrSheetMockPage: View {
    enum Tab: String, CaseIterable, Identifiable {
        case zikr = "Zikr", goals = "Daily goals", history = "History"
        var id: String { rawValue }
    }
    enum CardStyle: String, CaseIterable, Identifiable {
        case today = "A · Today first", streak = "B · Streak first"
        var id: String { rawValue }
    }

    @Environment(\.circleTheme) private var theme
    @Environment(\.colorScheme) private var phoneScheme
    // Launch arguments for screenshots: `-zikrMockTab zikr|goals|history -zikrMockCard B -zikrMockLook dark -zikrMockNoGoal YES`.
    @State private var tab: Tab = Tab.allCases.first { $0.rawValue.lowercased().hasPrefix(UserDefaults.standard.string(forKey: "zikrMockTab") ?? "daily") } ?? .goals
    @State private var style: CardStyle = UserDefaults.standard.string(forKey: "zikrMockCard") == "B" ? .streak : .today
    @State private var dark: Bool? = UserDefaults.standard.string(forKey: "zikrMockLook").map { $0 == "dark" }
    @State private var hasGoals = !UserDefaults.standard.bool(forKey: "zikrMockNoGoal")
    @State private var goal = 0

    private var isDark: Bool { dark ?? (phoneScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabSwitch.padding(.top, 14).padding(.bottom, 18)
            ScrollView {
                Group {
                    switch tab {
                    case .zikr: zikrTab
                    case .goals: hasGoals ? AnyView(goalsTab) : AnyView(noGoalTab)
                    case .history: historyTab
                    }
                }
                .id(tab)
                .transition(.opacity)
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            // Only a goal can be started (the other tabs would leave "start what?").
            if tab == .goals && hasGoals { startPill.transition(.opacity) }
        }
        .background(theme.surface.ignoresSafeArea())
        // Pushed from Your azkar (owner): the system back top left, then share and ⋯ top right.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share leads (owner: "promotes people to share their zikrs … the act of zikr in our Muslim community").
                ShareLink(item: "Sallallahu ta'ala ala habibihi Muhammadin wa ala alihi wa sahabihi wa sallam — durood, from shukr") {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    // Only the zikr's own things; the goal's live on its tab.
                    Button {} label: { Label("Edit the zikr", systemImage: "text.book.closed") }
                    Button(role: .destructive) {} label: { Label("Delete the zikr…", systemImage: "trash") }
                    Section("Mock-up") {
                        Picker("Goal card", selection: $style) { ForEach(CardStyle.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Look", selection: Binding(get: { isDark }, set: { dark = $0 })) {
                            Text("Light").tag(false); Text("Dark").tag(true)
                        }
                        Toggle("Has daily goals", isOn: $hasGoals)
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .animation(.easeOut(duration: 0.2), value: tab)
    }

    // MARK: Header and tabs

    private var header: some View {
        Text("durood").font(.system(size: 34, weight: .light, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }

    /// The Give page's capsule switch, three wide.
    private var tabSwitch: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let on = tab == t
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background { if on { NeuRaised(shape: Capsule(), radius: 3, offset: 1.5) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(NeuPressed(shape: Capsule(), radius: 3, offset: 2))
        .padding(.horizontal, 20)
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: Zikr

    private var zikrTab: some View {
        VStack(spacing: 16) {
            ZikrMockCard()
            // About the zikr itself, not a goal (owner).
            HStack(spacing: 0) {
                stat("3,390", "counted all time")
                stat("915", "this month")
                stat("3.4s", "each, usually")
            }
            .padding(.vertical, 14)
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), radius: 4, offset: 2))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Daily goals

    private var goalsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The goals as chips (one fewer word than the old "2 daily goals" line: the chips are the count).
            HStack(spacing: 8) {
                ForEach(Array(GoalMock.all.enumerated()), id: \.offset) { i, g in
                    let on = goal == i
                    Button { withAnimation(.snappy(duration: 0.25)) { goal = i } } label: {
                        Text(g.name).font(.subheadline.weight(on ? .medium : .regular))
                            .foregroundStyle(on ? Color.sage : .secondary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Group {
                switch style {
                case .today: GoalCardToday(g: GoalMock.all[goal])
                case .streak: GoalCardStreak(g: GoalMock.all[goal])
                }
            }
            .id(goal)
            .transition(.opacity)
            goalActions.padding(.top, 6)
        }
    }

    /// The goal's own things, on its tab (owner: not in ⋯): reminder, edit, pause; then another goal; delete last.
    private var goalActions: some View {
        let g = GoalMock.all[goal]
        return VStack(spacing: 14) {
            VStack(spacing: 0) {
                actionRow("bell", "Reminder", value: g.reminder ?? "Add", sage: g.reminder != nil)
                Divider().padding(.leading, 50).opacity(0.5)
                actionRow("pencil", "Edit goal", value: "\(g.goal) a day")
                Divider().padding(.leading, 50).opacity(0.5)
                actionRow("pause", "Pause this goal", value: nil)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.045)))
            Label("Add another daily goal", systemImage: "plus").font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
            Text("Delete this goal").font(.subheadline).foregroundStyle(.red.opacity(0.8))
        }
    }

    private func actionRow(_ symbol: String, _ title: String, value: String?, sage: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .light)).foregroundStyle(.secondary).frame(width: 22)
            Text(title).font(.body)
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(sage ? AnyShapeStyle(Color.sage) : AnyShapeStyle(.secondary)) }
            Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).frame(height: 50)
    }

    private var noGoalTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "target").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text("No daily goal yet").font(.system(size: 20, weight: .light, design: .rounded))
            Text("A daily goal puts durood on your wheel each day, with a streak to keep.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Add a daily goal").font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                .padding(.horizontal, 18).frame(height: 40)
                .overlay(Capsule().strokeBorder(Color.sage.opacity(0.6), lineWidth: 1))
                .padding(.top, 6)
        }
        .padding(.vertical, 36).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }

    private var startPill: some View {
        VStack(spacing: 10) {
            // Edit goal is a row on the tab now (not under Start).
            Text("Start \(GoalMock.all[goal].name) · ~3 min")
                .font(.headline.weight(.medium)).foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Capsule().fill(Color.sage.opacity(0.16)))
                .background(Capsule().fill(theme.surface))
                .overlay(Capsule().strokeBorder(Color.sage.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 16)
        .background(LinearGradient(colors: [theme.surface.opacity(0), theme.surface, theme.surface],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    // MARK: History

    private var historyTab: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                ForEach(Array(SessionMock.all.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Divider().padding(.leading, 18).opacity(0.5) }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.day).font(.body)
                            Text(s.time + (s.goal.map { " · \($0)" } ?? "")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(s.count).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                            Text(s.pace).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                }
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(0.045)))
            // A preview of History, not a second one (owner): the rest is the History page.
            HStack(spacing: 4) {
                Text("All 23 sessions in History")
                Image(systemName: "chevron.right").font(.caption.weight(.medium))
            }
            .font(.subheadline).foregroundStyle(Color.sage)
        }
    }
}

/// A stand-in for Your azkar's row: the page is pushed from it (owner), so the back chevron is the system's.
struct ZikrSheetMockLauncher: View {
    @State private var pushed = UserDefaults.standard.string(forKey: "zikrMockTab") != nil
    var body: some View {
        List {
            Section("Daily goals") {
                NavigationLink("durood · Morning Durood") { ZikrSheetMockPage() }
                NavigationLink("durood · Night Durood") { ZikrSheetMockPage() }
            }
        }
        .navigationTitle("Your azkar")
        .navigationDestination(isPresented: $pushed) { ZikrSheetMockPage() }
    }
}

// MARK: - Sample data

struct GoalMock {
    let name: String
    let goal: Int
    let today: Int
    /// The last 14 prayer days' counts, oldest first; the last is today.
    let days: [Int]
    let streak: Int
    let best: Int
    let average: String
    let lastDone: String
    let reminder: String?

    static let all = [
        GoalMock(name: "Morning Durood", goal: 50, today: 20, days: [50, 50, 50, 30, 50, 50, 50, 0, 50, 50, 50, 0, 0, 20],
                 streak: 0, best: 17, average: "2m 50s", lastDone: "Sat", reminder: "After Fajr"),
        GoalMock(name: "Night Durood", goal: 100, today: 0, days: [100, 100, 60, 100, 100, 100, 0, 100, 100, 100, 100, 100, 100, 0],
                 streak: 6, best: 9, average: "5m 10s", lastDone: "Yesterday", reminder: nil),
    ]
    /// Each of the 14 days' prayer-day dates, for the tap read-out.
    static func date(_ i: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: i - 13, to: Date()) ?? Date()
    }
}

struct SessionMock {
    let day: String, time: String, goal: String?, count: String, pace: String
    static let all = [
        SessionMock(day: "Sat, Oct 10", time: "6:45 PM", goal: "Morning Durood", count: "50", pace: "1m 42s · 2.0s each"),
        SessionMock(day: "Fri, Oct 9", time: "9:12 PM", goal: "Night Durood", count: "100", pace: "5m 31s · 3.3s each"),
        SessionMock(day: "Fri, Oct 9", time: "6:20 AM", goal: "Morning Durood", count: "50", pace: "2m 58s · 3.6s each"),
        SessionMock(day: "Thu, Oct 8", time: "1:04 PM", goal: nil, count: "33", pace: "1m 10s · 2.1s each"),
        SessionMock(day: "Wed, Oct 7", time: "6:31 AM", goal: "Morning Durood", count: "50", pace: "3m 05s · 3.7s each"),
    ]
}

// MARK: - Two weeks as dots

/// The last two weeks, one quiet dot a day (owner: consistency at a glance, not a row of rings): full sage = met, a
/// lighter sage by how far = part done, faint = none; today a ring filling with today's count. A tap reads a day.
struct GoalDaysMock: View {
    let g: GoalMock
    @Binding var picked: Int?
    var dot: CGFloat = 14
    var rows = 2

    var body: some View {
        let perRow = g.days.count / rows
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<perRow, id: \.self) { c in
                        let i = r * perRow + c
                        VStack(spacing: 5) {
                            if r == 0 || rows == 1 {
                                Text(GoalMock.date(i).formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .opacity(rows == 1 ? 1 : (r == 0 ? 1 : 0))
                            }
                            day(i)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy(duration: 0.2)) { picked = picked == i ? nil : i }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func day(_ i: Int) -> some View {
        let isToday = i == g.days.count - 1
        let f = Double(g.days[i]) / Double(max(g.goal, 1))
        let on = picked == i
        ZStack {
            if isToday {
                Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1.5)
                Circle().trim(from: 0, to: min(f, 1))
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(-90))
            } else if f >= 1 {
                Circle().fill(Color.sage)
            } else if f > 0 {
                Circle().fill(Color.sage.opacity(0.2 + 0.4 * f))
            } else {
                Circle().fill(Color.primary.opacity(0.08)).padding(dot * 0.22)
            }
        }
        .frame(width: dot, height: dot)
        .padding(3)
        .overlay { if on { Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1) } }
    }
}

/// "Sat, Oct 10 · 50 of 50 · 1m 42s", or the hint.
private func dayLine(_ g: GoalMock, _ i: Int?) -> String {
    guard let i else { return "Tap a day" }
    let d = GoalMock.date(i).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    let n = g.days[i]
    if n == 0 { return "\(d) · not done" }
    let secs = Int(Double(n) * 3.4)
    return "\(d) · \(n) of \(g.goal) · \(secs / 60)m \(String(format: "%02d", secs % 60))s"
}

// MARK: - Goal card A · Today first

/// Today big and plain at the top (the number, not a ring — History's card leads with a ring), the two weeks as a
/// little calendar, then three facts side by side in pressed wells.
struct GoalCardToday: View {
    let g: GoalMock
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(g.today)").font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                        Text("of \(g.goal)").font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(g.today >= g.goal ? "done today" : "today · about \(g.today > 0 ? "2" : "3") min to go")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(spacing: 10) {
                GoalDaysMock(g: g, picked: $picked)
                Text(dayLine(g, picked)).font(.caption).foregroundStyle(picked == nil ? .tertiary : .secondary)
                    .monospacedDigit().contentTransition(.opacity)
            }
            .padding(.vertical, 14).padding(.horizontal, 8)
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 4, offset: 2))
            HStack(spacing: 10) {
                fact("flame", g.streak > 0 ? "\(g.streak)" : "0", "day streak", "best \(g.best)")
                fact("clock", g.average, "a day", "on average")
                fact("calendar", g.lastDone, "last done", nil)
            }
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }

    private func fact(_ symbol: String, _ value: String, _ label: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .light, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(sub ?? " ").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 3, offset: 1.5))
    }
}

// MARK: - Goal card B · Streak first

/// The streak leads (what a daily goal is for), today a small ring beside it, the two weeks in one row of dots, the
/// facts as two plain lines.
struct GoalCardStreak: View {
    let g: GoalMock
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: g.streak > 0 ? "flame.fill" : "flame")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(g.streak > 0 ? Color.sage : .secondary)
                        Text("\(g.streak) day streak").font(.system(size: 28, weight: .light, design: .rounded))
                    }
                    Text(g.streak > 0 ? "best \(g.best) · keep it today" : "best \(g.best) · start a new one today")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
                    Circle().trim(from: 0, to: min(Double(g.today) / Double(g.goal), 1))
                        .stroke(Color.sage, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(g.today)").font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
                        Text("of \(g.goal)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 62, height: 62)
            }
            VStack(spacing: 8) {
                GoalDaysMock(g: g, picked: $picked, dot: 11, rows: 1)
                Text(dayLine(g, picked)).font(.caption).foregroundStyle(picked == nil ? .tertiary : .secondary)
                    .monospacedDigit()
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 8) {
                line("clock", "About \(g.average) a day, on average")
                line("calendar", "Last done \(g.lastDone)")
            }
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }

    private func line(_ symbol: String, _ text: String, sage: Bool = false) -> some View {
        Label(text, systemImage: symbol).font(.subheadline)
            .foregroundStyle(sage ? AnyShapeStyle(Color.sage) : AnyShapeStyle(.secondary))
    }
}

// MARK: - The zikr's card (as the real one: tabs down its left)

struct ZikrMockCard: View {
    @State private var pane = 0
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 18) {
                ForEach(Array(["doc.text", "waveform", "photo"].enumerated()), id: \.offset) { i, s in
                    Image(systemName: s).font(.system(size: 18, weight: .light))
                        .foregroundStyle(pane == i ? Color.sage : .secondary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(pane == i ? Color.sage.opacity(0.16) : .clear))
                        .onTapGesture { pane = i }
                }
            }
            ZStack(alignment: .bottomTrailing) {
                Text(pane == 0 ? "Sallallahu ta'ala ala habibihi Muhammadin wa ala alihi wa sahabihi wa sallam"
                     : pane == 1 ? "Voice memo · Sep 29 · 0:42" : "No photo yet")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(16)
                Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36).background(NeuRaised(shape: Circle(), radius: 3, offset: 1.5))
                    .padding(10)
            }
            .frame(height: 170)
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 4, offset: 2))
        }
        .padding(14)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }
}
#endif
