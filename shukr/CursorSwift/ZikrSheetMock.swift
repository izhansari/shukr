#if DEBUG
import SwiftUI

// A zikr's page as three tabs, mocked (owner, 2026-10-15): "make these three separate tabs … each one of these things gets
// the full attention rather than fighting for attention" — Zikr · Daily goals · History, in that order, switched from a
// thin Liquid Glass bar at the bottom (Memories' bar). Pushed from Your azkar: back ‹, then + (another daily goal, on its
// tab), share and ⋯ (the zikr's own things) on a see-through bar; the title over a hairline. The goal card is its own
// (owner: not History's month card): B (owner's favourite, the default) leads with the streak — or the days since, with
// none going — the best streak always under it; the last two weeks as small progress rings; the reminder inside it; the
// goal's edit / pause / delete behind its Edit menu (owner: the card is the page). Fake data only; the look, not the wiring.
// ⋯ → Mock-up holds the switches (card A / B, light / dark, a zikr without a goal).
// My Dev Stuff → Zikr page mock-up; DEBUG `-demoZikrSheetMock`.

struct ZikrSheetMockPage: View {
    enum Tab: String, CaseIterable, Identifiable {
        // "Details", not "Zikr" (owner: the whole page is the zikr's).
        case zikr = "Details", goals = "Daily goals", history = "History"
        var id: String { rawValue }
    }
    enum CardStyle: String, CaseIterable, Identifiable {
        case today = "A · Today first", streak = "B · Streak first"
        var id: String { rawValue }
    }

    @Environment(\.circleTheme) private var theme
    @Environment(\.colorScheme) private var phoneScheme
    @Namespace private var bar
    // Launch arguments for screenshots: `-zikrMockTab details|daily|history -zikrMockCard A -zikrMockLook dark -zikrMockNoGoal YES`.
    @State private var tab: Tab = Tab.allCases.first { $0.rawValue.lowercased().hasPrefix(UserDefaults.standard.string(forKey: "zikrMockTab") ?? "daily") } ?? .goals
    @State private var style: CardStyle = UserDefaults.standard.string(forKey: "zikrMockCard") == "A" ? .today : .streak
    @State private var dark: Bool? = UserDefaults.standard.string(forKey: "zikrMockLook").map { $0 == "dark" }
    @State private var hasGoals = !UserDefaults.standard.bool(forKey: "zikrMockNoGoal")
    @State private var goal: Int
    init(startGoal: Int = 0) { _goal = State(initialValue: startGoal) }

    private var isDark: Bool { dark ?? (phoneScheme == .dark) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        // The title stays; the page scrolls on under it (owner), softened at the edge.
        .modifier(ScrollsUnder(edge: .top) { header })
        // The tabs, the width of the page (owner); no Start pill (owner: "it just looks strange").
        .modifier(ScrollsUnder(edge: .bottom) { tabBar.padding(.horizontal, 16).padding(.bottom, 4) })
        .background(theme.surface.ignoresSafeArea())
        // Pushed from Your azkar (owner): the system back top left; the bar see-through (owner).
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share leads the zikr's things (owner: "promotes people to share their zikrs").
                ShareLink(item: "Sallallahu ta'ala ala habibihi Muhammadin wa ala alihi wa sahabihi wa sallam — durood, from shukr") {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    // Only the zikr's own things; a goal's are on its card.
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

    /// The title, then a hairline between it and the page (owner).
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("durood").font(.system(size: 34, weight: .light, design: .rounded))
                .padding(.horizontal, 20)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
        .padding(.top, 2)
    }

    /// Memories' bottom bar: a thin Liquid Glass capsule, the picked one on a sliding pill (owner: "traditional iOS liquid
    /// glass", not thick).
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(.snappy(duration: 0.3)) { tab = t } } label: {
                    Text(t.rawValue)
                        .font(.system(size: 15, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if tab == t {
                                Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "pill", in: bar)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .barGlass(Capsule())
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
        VStack(alignment: .leading, spacing: 10) {
            // How many there are (owner: nowhere said it), in History's MOST SAID type.
            Text("\(GoalMock.all.count) DAILY GOALS").font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.secondary)
                .padding(.leading, 4)
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
                // Another daily goal, right where the goals are (owner: a + after the chips, not top right).
                Button {} label: {
                    Image(systemName: "plus").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add another daily goal")
            }
            Color.clear.frame(height: 4)
            // The card is the page (owner): nothing under it.
            Group {
                switch style {
                case .today: GoalCardToday(g: GoalMock.all[goal])
                case .streak: GoalCardStreak(g: GoalMock.all[goal])
                }
            }
            .id(goal)
            .transition(.opacity)
        }
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
    /// The goal tapped (its page opens on it); a screenshot argument pushes the first at once.
    @State private var pushed: Int? = UserDefaults.standard.string(forKey: "zikrMockTab") != nil ? 0 : nil
    var body: some View {
        List {
            Section("Daily goals") {
                ForEach(Array(GoalMock.all.enumerated()), id: \.offset) { i, g in
                    Button { pushed = i } label: {
                        HStack {
                            Text("durood · \(g.name)").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle("Your azkar")
        .navigationDestination(item: $pushed) { ZikrSheetMockPage(startGoal: $0) }
    }
}

/// A bar the page scrolls under: iOS 26's `safeAreaBar` (the scroll edge effect softens what passes beneath), the bar
/// material before (Settings' `OverListHeader`).
private struct ScrollsUnder<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    @ViewBuilder let bar: () -> Bar
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: edge) { bar() }
        } else {
            content.safeAreaInset(edge: edge, spacing: 0) { bar().background(.bar) }
        }
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
    /// Prayer days since it was last done (with no streak going).
    var daysSince: Int { (days.lastIndex { $0 >= goal }).map { days.count - 1 - $0 } ?? 14 }
    /// Days the goal was met, of the 14.
    var met: Int { days.filter { $0 >= goal }.count }
    /// Each day's share of its goal (capped at 1), averaged over the 14 — partial days count for what they got.
    var consistency: Int { Int((days.map { min(Double($0) / Double(max(goal, 1)), 1) }.reduce(0, +) / Double(days.count) * 100).rounded()) }
    var lastDoneText: String { daysSince == 0 ? "today" : daysSince == 1 ? "yesterday" : "\(daysSince) days ago" }

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

// MARK: - Two weeks as rings

/// The last two weeks, a small progress ring a day (owner: "just clearer to tell how far I got on the task that day"):
/// filled by that day's count against the goal, ✓-full in sage when met, an empty track when missed; today a touch
/// bolder. A tap reads a day.
struct GoalDaysMock: View {
    let g: GoalMock
    @Binding var picked: Int?
    var size: CGFloat = 18
    var rows = 2

    var body: some View {
        let perRow = g.days.count / rows
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<perRow, id: \.self) { c in
                        let i = r * perRow + c
                        VStack(spacing: 5) {
                            if r == 0 {
                                Text(GoalMock.date(i).formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2).foregroundStyle(i == g.days.count - 1 ? .primary : .tertiary)
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

    private func day(_ i: Int) -> some View {
        let isToday = i == g.days.count - 1
        let f = min(Double(g.days[i]) / Double(max(g.goal, 1)), 1)
        let width: CGFloat = isToday ? 2.6 : 2.2
        return ZStack {
            Circle().stroke(Color.primary.opacity(isToday ? 0.24 : 0.17), lineWidth: width)
            if f > 0 {
                Circle().trim(from: 0, to: f)
                    .stroke(Color.sage.opacity(f >= 1 ? 1 : 0.55), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .padding(4)
        .background { if picked == i { Circle().fill(Color.primary.opacity(0.1)) } }
    }
}

/// "Sat, Oct 10 · 50 of 50 · 2m 50s", or the hint.
private func dayLine(_ g: GoalMock, _ i: Int?) -> String {
    guard let i else { return "Tap a day" }
    let d = GoalMock.date(i).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    let n = g.days[i]
    if n == 0 { return "\(d) · not done" }
    let secs = Int(Double(n) * 3.4)
    return "\(d) · \(n) of \(g.goal) · \(secs / 60)m \(String(format: "%02d", secs % 60))s"
}

/// The goal's reminder and its Edit menu, inside the card (owner: edit / pause / delete behind a button, the card is
/// the page; the reminder can sit in the card).
private struct GoalCardFoot: View {
    let g: GoalMock
    var body: some View {
        HStack {
            // Sage = tap: it opens the reminder (owner's critique: green that did nothing).
            Button {} label: {
                HStack(spacing: 6) {
                    Label(g.reminder.map { "Reminder · \($0)" } ?? "Add a reminder", systemImage: g.reminder != nil ? "bell.fill" : "bell")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.subheadline).foregroundStyle(Color.sage)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button {} label: { Label("Edit goal", systemImage: "pencil") }
                Button {} label: { Label(g.reminder == nil ? "Add a reminder" : "Change reminder", systemImage: "bell") }
                Button {} label: { Label("Pause this goal", systemImage: "pause") }
                Button(role: .destructive) {} label: { Label("Delete goal…", systemImage: "trash") }
            } label: {
                Text("Edit").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(NeuRaised(shape: Capsule(), radius: 3, offset: 1.5))
            }
            .tint(.primary)
        }
    }
}

// MARK: - Goal card A · Today first

/// Today big and plain at the top, the two weeks as a little calendar of rings, then the streak (or days since), the
/// average a day and the best streak in wells.
struct GoalCardToday: View {
    let g: GoalMock
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(g.today)").font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                    Text("of \(g.goal)").font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Text(g.today >= g.goal ? "done today" : "today · about \(g.today > 0 ? "2" : "3") min to go")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                GoalDaysMock(g: g, picked: $picked)
                Text(dayLine(g, picked)).font(.caption).foregroundStyle(picked == nil ? .tertiary : .secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 14).padding(.horizontal, 8)
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 4, offset: 2))
            HStack(spacing: 10) {
                // A streak going shows; else how long since (owner: "last done" says nothing with a streak).
                if g.streak > 0 { fact("flame.fill", "\(g.streak)", "day streak") }
                else { fact("calendar", "\(g.daysSince)", g.daysSince == 1 ? "day since" : "days since") }
                fact("clock", g.average, "a day, usually")
                fact("trophy", "\(g.best)", "best streak")   // always somewhere (owner)
            }
            GoalCardFoot(g: g)
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
    }

    private func fact(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .light, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 3, offset: 1.5))
    }
}

// MARK: - Goal card B · Streak first

/// How the last two weeks went leads ("9 of 14 days" — countable on the rings under it); a tap flips it to how
/// consistent that is, back by itself after 3 s as the Salah ring's flip (a second tap goes back at once). Today a bigger
/// ring labelled TODAY: a tap asks to start the goal. A day's ring tapped: its numbers under the row (owner: "I liked it
/// better when its relative data came underneath"), gone again after 3 s. Then streak · best, last done, the usual
/// time; the reminder (tappable) and Edit at its foot.
struct GoalCardStreak: View {
    let g: GoalMock
    @State private var picked: Int?
    @State private var showConsistency = false
    @State private var askStart = false
    @State private var revert: Task<Void, Never>?
    @State private var dayRevert: Task<Void, Never>?
    /// The Salah ring's flip (mainCircle `flipSeconds`).
    private static let flipSeconds: Double = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                headline
                    .contentShape(Rectangle())
                    .onTapGesture { flipHeadline() }
                Spacer()
                todayRing
            }
            VStack(spacing: 8) {
                GoalDaysMock(g: g, picked: $picked, size: 14, rows: 1)
                if let picked {
                    Text(dayLine(g, picked)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .transition(.opacity)
                }
            }
            .onChange(of: picked) { _, day in
                dayRevert?.cancel()
                guard day != nil else { return }
                dayRevert = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.flipSeconds))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { picked = nil }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                line(g.streak > 0 ? "flame.fill" : "flame",
                     g.streak > 0 ? "\(g.streak) day streak · best \(g.best)" : "No streak going · best \(g.best)",
                     sage: g.streak > 0)
                line("calendar", "Last done \(g.lastDoneText)")
                line("clock", "Usually \(g.average) a day")
            }
            Divider().opacity(0.5)
            GoalCardFoot(g: g)
        }
        .padding(18)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), radius: 8, offset: 4))
        // The app's "Start …?" (a zikr's page): part done → Continue / Start over.
        .alert("Start \(g.name)?", isPresented: $askStart) {
            if g.today > 0 && g.today < g.goal {
                Button("Continue · \(g.goal - g.today) to go") {}
                Button("Start over") {}
            } else {
                Button("Start") {}
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(g.today > 0 && g.today < g.goal ? "You're at \(g.today) of \(g.goal) today." : "\(g.goal) today, about 3 min.")
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(showConsistency ? "\(g.consistency)%" : "\(g.met) of \(g.days.count)")
                    .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                Text(showConsistency ? "consistent" : "days")
                    .font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(showConsistency ? "of each day's goal, last two weeks" : "goal met, last two weeks")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .contentTransition(.opacity)
    }

    private var todayRing: some View {
        Button { triggerSomeVibration(type: .light); askStart = true } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: min(Double(g.today) / Double(g.goal), 1))
                        .stroke(Color.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(g.today)").font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit()
                        Text("of \(g.goal)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
                Text("TODAY").font(.caption2.weight(.medium)).tracking(1.1).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today, \(g.today) of \(g.goal). Start")
    }

    /// The Salah ring's rule: a tap flips, back after 3 s; a tap while flipped goes back at once.
    private func flipHeadline() {
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
