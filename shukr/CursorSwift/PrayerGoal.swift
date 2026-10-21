import SwiftUI
import SwiftData

// The prayer goal (owner, 2026-10-18): "a setting where user can choose their goal. like for me my goal is to pray all perfect.
// some might be middle and perfect. some might be perfect middle and closing (in window). This is the real goal and the metric
// that matters most for people." It decides which days keep the streak and count as met (Journey's green days, its rate, the
// runs) — never a prayer's score or grade. Flipping it recounts history at the new bar (nothing stored: "i want it to be
// something the user can easily change and flip between"); the fresh start (FreshStart.swift) is where every count begins.
// The rule lives here only: PrayerViewModel.gradingCriteria, YourJourneyStats.streakDay and JourneyLog.Day all ask it.

/// Which prayers count toward the goal. Stored under the old hidden streak-mode key, whose values it keeps (1 = any mark,
/// 2 = in its window, 3 = Middle or better), so nobody's streak moves on update; Perfect is new.
enum PrayerGoal: Int, CaseIterable, Identifiable {
    case prayed = 1, inWindow = 2, onTime = 3, perfect = 4

    static let key = "prayerStreakMode"
    var id: Int { rawValue }

    /// The user's step. FirstRunSetup.migrateDefaults writes it on the first launch (new installs In its window, anyone
    /// already here Prayed), so the fallback below only covers a read before that.
    static var current: PrayerGoal {
        PrayerGoal(rawValue: UserDefaults.standard.object(forKey: key) as? Int ?? 2) ?? .inWindow
    }

    /// A prayer in this state meets the step (PrayerState: the one place that decides what a prayer is). A no-time mark
    /// is in its window but claims no third, so it meets Prayed and In its window, not Middle or the Opening.
    func meets(_ state: PrayerState) -> Bool {
        switch self {
        case .prayed: state.prayed
        case .inWindow: state.inTime
        case .onTime: state == .opening || state == .middle
        case .perfect: state == .opening
        }
    }

    /// The step one up and one down the ladder (the Sunday offer; owner, 2026-10-21: "one step up instead of two steps").
    var up: PrayerGoal? { PrayerGoal(rawValue: rawValue + 1) }
    var down: PrayerGoal? { PrayerGoal(rawValue: rawValue - 1) }

    /// After "N of 35 …": the week's and a prayer's counts in the step's words ("12 of 35 in their windows"). The Middle
    /// step reads "before Closing" (owner, 2026-10-21: "by the middle" "seems like it means before middle starts").
    var countWords: String {
        switch self {
        case .prayed: "prayed"
        case .inWindow: "in their windows"
        case .onTime: "before Closing"
        case .perfect: "in the Opening"
        }
    }
    /// The step's own name, as the ladder and the offer say it.
    var stepName: String {
        switch self {
        case .prayed: "Prayed"
        case .inWindow: "In its window"
        case .onTime: "the Middle"
        case .perfect: "the Opening"
        }
    }

    /// What the step asks, said whole, so a line about it reads as their goal, not a bare name (owner, 2026-10-21: "remind
    /// them of their goal so they don't find this phrase arbitrary"): "Your goal is every prayer in its window."
    var aim: String {
        switch self {
        case .prayed: "every prayer prayed, even if made up later"
        case .inWindow: "every prayer in its window"
        case .onTime: "every prayer before Closing"
        case .perfect: "every prayer in its Opening"
        }
    }

    /// The lowest score that meets it; nil: any mark (a Qaza too).
    var floor: Double? {
        switch self {
        case .prayed: nil
        case .inWindow: PrayerScoring.inWindowFloor
        case .onTime: 0.8
        case .perfect: 1
        }
    }

    /// A prayed prayer's score meets it (PrayerScoring.grade's own edges).
    func meets(score: Double) -> Bool {
        switch self {
        case .prayed: true
        case .inWindow: score >= PrayerScoring.inWindowFloor - 0.0001
        case .onTime: score >= 0.8
        case .perfect: score >= 0.9999
        }
    }

    /// The grade it reaches down to, in PrayerScoring's own words (Design's v7, owner 2026-10-19: "Perfect Middle Closing Qaza
    /// as the items"): Settings' row, Your Data and the goal page read it. Was "Made up counts / Before it ends / Before
    /// closing / Perfect".
    var title: String {
        switch self {
        case .prayed: PrayerScoring.Grade.qaza.rawValue
        case .inWindow: PrayerScoring.Grade.late.rawValue
        case .onTime: PrayerScoring.Grade.onTime.rawValue
        case .perfect: PrayerScoring.Grade.perfect.rawValue
        }
    }
    /// Its time, the goal page's second line ("I aim to complete my prayers…").
    var line: String {
        switch self {
        case .prayed: "Even made up later"
        case .inWindow: "Before it ends"
        case .onTime: "Before its last third"
        case .perfect: "In the first third of its time"
        }
    }
    /// The goal page's order: strictest first.
    static let strictestFirst: [PrayerGoal] = [.perfect, .onTime, .inWindow, .prayed]
    /// Where it stops counting on the welcome's window (the Prayer circle card): the Opening a third, Middle two thirds,
    /// Closing to the end, Qaza the end and grey (it's after the window).
    var arcEnd: Double {
        switch self {
        case .perfect: WelcomeWindow.edges.opening
        case .onTime: WelcomeWindow.edges.middle
        case .inWindow, .prayed: 1
        }
    }
    /// A day that met it, in a few words (the legend, the runs): "All five prayed", "All five in the Opening" …
    var dayWords: String {
        switch self {
        case .prayed: "All five prayed"
        case .inWindow: "All five in their windows"
        case .onTime: "All five before Closing"
        case .perfect: "All five in the Opening"
        }
    }

    /// A streak of days that met it, after "N days in a row, " (the milestones).
    var runWords: String {
        switch self {
        case .prayed: "all five prayed"
        case .inWindow: "all in their windows"
        case .onTime: "all before Closing"
        case .perfect: "all in the Opening"
        }
    }
    /// After "all five prayers …" (a milestone's card).
    var prayersWords: String {
        switch self {
        case .prayed: "prayed"
        case .inWindow: "prayed in their windows"
        case .onTime: "prayed before Closing"
        case .perfect: "in the Opening"
        }
    }

    /// Sets it and lets every count redo itself (no celebrations: PrayerStats.changed).
    @MainActor static func set(_ goal: PrayerGoal) {
        guard goal != current else { return }
        UserDefaults.standard.set(goal.rawValue, forKey: key)
        PrayerStats.changed()
    }
}

/// The two settings every count reads — the goal and the fresh start — and the one event when either changes.
enum PrayerStats {
    /// Posted after the goal or the fresh start changed: the Salah page recounts its streak silently, Journey and Prayer
    /// scores rebuild (their caches go). `.journeyChanged` follows, so the pages that already reload on it do.
    static let rulesChanged = Notification.Name("PrayerStats.rulesChanged")

    @MainActor static func changed() {
        MilestoneCelebration.shared.quietNext = true   // before anything can check
        UserDefaults.standard.set(PrayerDay.key(), forKey: changedDayKey)
        NotificationCenter.default.post(name: rulesChanged, object: nil)
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
    }

    /// The prayer day the goal or the fresh start last changed: the line under the circle skips its milestone tier then (a
    /// run the change itself made isn't news — audit #11).
    static let changedDayKey = "prayerStats.changedDay"
    static var changedToday: Bool { UserDefaults.standard.string(forKey: changedDayKey) == PrayerDay.key() }

    /// The first prayer day that counts: the fresh start's, or nil (all of them).
    static var countsFrom: Date? { FreshStart.start }

    /// A prayer day (its start) counts toward streaks, rates, ranks and runs.
    static func counts(_ dayStart: Date) -> Bool {
        guard let from = countsFrom else { return true }
        return dayStart >= from
    }
}

/// Settings' row (Journey section): the goal's name.
struct PrayerGoalSettingsRow: View {
    @State private var goal = PrayerGoal.current
    var body: some View {
        NavigationLink { PrayerGoalPage() } label: {
            HStack(spacing: 12) {
                Image(systemName: "target").frame(width: 24)
                Text("Your goal").lineLimit(1)
                Spacer(minLength: 8)
                Text(goal.title).foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in goal = PrayerGoal.current }
        .onAppear { goal = PrayerGoal.current }
    }
}

/// Your goal (Design's v7, 2026-10-19; spec board/mocks/your-goal/spec.md, canvas tab v7 S1 — owner: "Let's try using the
/// graphic that we have in the onboarding setup with that demo of the prayer ring … as the display of our goal"; "there's no
/// more spinning the dial thing"; "I want them to have to press a save button that only turns on when it's necessary"; "Maybe
/// say 'I aim to complete my prayers...' Perfect Middle Closing Qaza as the items"; "close out the list and leave only the
/// selected option with a bit of text above it"). Settings' plain grouped look: the title and the streaks sentence; the
/// welcome's Prayer circle card, its arc ending where the goal being tried stops counting (Qaza grey) round your CURRENT
/// streak; the four goals strictest first, each with its time; Save (onboarding's, live only when the goal tried differs),
/// and one line under it saying what your streak would become. Save closes out the list to your pick, rolls the number,
/// swells the arc once, then opens the list back out — the page never leaves on its own. Tried and dropped: the dial (a ring, its dot as a slider, a wheel of words) and
/// Cancel.
struct PrayerGoalPage: View {
    /// The goal being tried — only Save makes it yours.
    @State private var goal = PrayerGoal.current
    /// Yours, as saved: its radio keeps an outline of its own while you try others.
    @State private var current = PrayerGoal.current
    /// The arc's end and grey, animated between goals (PrayerGoal.arcEnd).
    @State private var arcEnd = PrayerGoal.current.arcEnd
    @State private var arcGrey: Double = PrayerGoal.current == .prayed ? 1 : 0
    @State private var arcSwell: Double = 0
    /// The number in the ring: your saved goal's streak (it moves only on Save).
    @State private var shownStreak: Int?
    /// Each goal's streak, counted once when the page opens (GoalPreview); nil until then.
    @State private var previews: [PrayerGoal: GoalPreview]?
    /// Save's moment is playing: the list closes out to the pick; nothing takes a tap.
    @State private var saving = false
    @State private var checkDrawn: CGFloat = 0
    @State private var savedTick = 0
    /// The line under Save as it was when Save was tapped: it fades out with those words.
    @State private var savedLine = ""
    /// The back button and swipe are off during the moment (NavPopGuard) — the button stays where it is: hiding it collapsed
    /// the bar and the page jumped up ~40 pt (Design's check of fb59050f).
    @State private var navLocked = false
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    // The app's page title (Give to Causes, Fresh start): 30 pt light rounded.
                    Text("Your goal").font(.system(size: 30, weight: .light, design: .rounded))
                    Text(MetricsLook.on
                         ? "Your streak is strong weeks in a row: every prayer prayed, with at most three below your goal. Changing your goal recounts your past weeks."
                         : "Your streak grows by a day each time all five prayers meet your goal. Changing your goal recounts your past days. Your prayers' scores stay the same.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                PrayerCircleCard(ringSize: 140, ringPadding: 16) {
                    WelcomeSweep(gone: arcEnd, grey: arcGrey, swell: arcSwell, size: 140, endsPure: true)
                        .overlay { streakInRing }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Prayer circle, \(goal.title). Current streak \(Self.streakWords(shownStreak ?? 0)).")

                header.padding(.top, 18)
                list.padding(.top, 7)
                    .padding(.bottom, 24)
            }
            .fontDesign(.rounded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { saveBar }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // Back never saves; during Save's moment nothing is touched, the back button and swipe included.
        .background { NavPopGuard(locked: navLocked) }
        .allowsHitTesting(!saving)
        .sensoryFeedback(.selection, trigger: goal)
        .sensoryFeedback(.success, trigger: savedTick)
        .task {
            let container = context.container
            let ranges = Excused.ranges
            let counted = await GoalPreview.all(container: container, ranges: ranges)
            withAnimation(.easeOut(duration: 0.25)) {
                previews = counted
                shownStreak = counted[current].map(Self.streakOf) ?? 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in
            // Changed elsewhere (a restore, another device): follow it, unless another goal is being tried here.
            guard !saving else { return }
            let was = current
            current = PrayerGoal.current
            guard goal == was, current != goal else { return }
            pick(current)
        }
    }

    /// Your current streak in the ring (your saved goal's — what "current" says), and its word.
    private var streakInRing: some View {
        VStack(spacing: 0) {
            Text("\(shownStreak ?? 0)")
                .font(.system(size: 36, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shownStreak ?? 0)))
            Text(MetricsLook.on ? ((shownStreak ?? 0) == 1 ? "strong week" : "strong weeks") : "current streak")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(shownStreak == nil ? 0 : 1)
    }

    /// The list's header, the Settings header spot; at Save it says what the one row left means.
    private var header: some View {
        // Out, then in (they overlapped as a crossfade).
        ZStack(alignment: .leading) {
            Text("I aim to complete my prayers…").opacity(saving ? 0 : 1)
                .animation(saving ? .easeOut(duration: 0.14) : .easeOut(duration: 0.24).delay(0.16), value: saving)
            Text("Your goal is now").opacity(saving ? 1 : 0)
                .animation(saving ? .easeOut(duration: 0.24).delay(0.16) : .easeOut(duration: 0.14), value: saving)
        }
        .font(.footnote).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
    }

    /// The four goals in a Settings card, strictest first: a radio (sage on the one tried, an ink outline on yours), the
    /// grade's name over its time. At Save the others go and the card closes round your pick.
    private var list: some View {
        let rows = saving && !reduceMotion ? [goal] : PrayerGoal.strictestFirst
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { i, option in
                Button { pick(option) } label: {
                    HStack(spacing: 14) {
                        GoalRadio(on: option == goal, current: option == current && !saving)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title).foregroundStyle(.primary)
                            Text(option.line).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(minHeight: 56)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Reduce Motion: the others fade where they are, nothing moves.
                .opacity(saving && reduceMotion && option != goal ? 0 : 1)
                // Going: out at once. Coming back: in once your pick has glided back to its place (they overlapped).
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.3)),
                                        removal: .opacity.animation(.easeOut(duration: 0.2))))
                .accessibilityLabel("\(option.title). \(option.line)")
                .accessibilityAddTraits(option == goal ? .isSelected : [])
                .accessibilityHint(option == current ? "Your goal now" : "")
                if i < rows.count - 1 { Divider().padding(.leading, 52) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal, 20)
    }

    /// Try a goal: the arc sweeps steadily to where it stops counting, its colour turning as it crosses each boundary.
    private func pick(_ g: PrayerGoal) {
        goal = g
        let distance = abs(g.arcEnd - arcEnd)
        let sweep = reduceMotion ? Animation.easeOut(duration: 0.2) : .easeInOut(duration: 0.35 + 1.1 * distance)
        withAnimation(sweep) { arcEnd = g.arcEnd }
        withAnimation(.easeInOut(duration: 0.3)) { arcGrey = g == .prayed ? 1 : 0 }
    }

    /// What Save would do to your streak, in one line (its height always kept).
    private var whatIf: String {
        guard goal != current, let previews, let n = previews[goal].map(Self.streakOf),
              let m = previews[current].map(Self.streakOf) else {
            return "Tap a goal to see what your streak would be."
        }
        if n == m { return "Switching to \(goal.title) keeps your streak at \(Self.streakWords(m))." }
        if n == 0 { return "Switching to \(goal.title) starts your streak over." }
        return "Switching to \(goal.title) makes your streak \(Self.streakWords(n))."
    }

    /// The streak this page shows: strong weeks with the rethink (MetricsLook), else days.
    private static func streakOf(_ p: GoalPreview) -> Int { MetricsLook.on ? p.weeks : p.streak }
    private static func streakWords(_ k: Int) -> String {
        MetricsLook.on ? (k == 1 ? "1 strong week" : "\(k) strong weeks") : (k == 1 ? "1 day" : "\(k) days")
    }

    /// Save — onboarding's PrimaryButton look, faded and off until the goal tried differs from yours — and the line under
    /// it. At Save the check draws in and it says "Saved".
    private var saveBar: some View {
        let changed = goal != current
        return VStack(spacing: 0) {
            Button(action: save) {
                HStack(spacing: 7) {
                    if saving {
                        SaveCheck(drawn: checkDrawn).frame(width: 17, height: 13)
                    }
                    Text(saving ? "Saved" : "Save")
                }
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(Capsule().fill(Color.sage.opacity(0.14)))
                .overlay(Capsule().stroke(Color.sage.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // "✓ Saved" at full strength: disabled, it drew at the faded look (save() ignores a second tap).
            .opacity(changed || saving ? 1 : 0.4)
            .disabled(!changed && !saving)
            .padding(.horizontal, 24)
            Text(saving ? savedLine : whatIf)
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 24)
                .frame(height: 40)
                .opacity(saving ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: saving)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: whatIf)
        }
        .animation(.easeInOut(duration: 0.2), value: changed)
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
    }

    /// Save's moment (about 1.7 s): a success buzz, the check draws in, the list closes out to your pick under "Your goal is
    /// now", the number rolls to the new streak, the arc swells once; then the list opens back out and the page stays.
    /// Reduce Motion: crossfades only.
    private func save() {
        guard goal != current, !saving else { return }
        let newStreak = previews?[goal].map(Self.streakOf)
        savedLine = whatIf
        navLocked = true
        PrayerGoal.set(goal)
        current = goal
        savedTick += 1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)) { saving = true }
        withAnimation(.easeOut(duration: 0.3)) { checkDrawn = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.15))
            if reduceMotion { shownStreak = newStreak ?? shownStreak } else {
                withAnimation(.smooth(duration: 0.5)) { shownStreak = newStreak ?? shownStreak }
            }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(0.25))
                withAnimation(.easeOut(duration: 0.25)) { arcSwell = 1 }
                try? await Task.sleep(for: .seconds(0.25))
                withAnimation(.easeInOut(duration: 0.3)) { arcSwell = 0 }
                try? await Task.sleep(for: .seconds(0.8))
            } else {
                try? await Task.sleep(for: .seconds(1.35))
            }
            // It stays (owner, 2026-10-19: "i don't want it to exit the page on its own"): the list opens back out round
            // your new goal, the header comes back, Save turns back off.
            navLocked = false
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)) { saving = false }
            checkDrawn = 0
        }
    }
}

/// Save's check, drawn in as it says "Saved".
private struct SaveCheck: Shape {
    var drawn: CGFloat
    var animatableData: CGFloat { get { drawn } set { drawn = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.11, y: r.minY + r.height * 0.54))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY - r.height * 0.14))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.11, y: r.minY + r.height * 0.14))
        return p.trimmedPath(from: 0, to: drawn).strokedPath(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
    }
}

/// Your goal's preview, per goal (owner, 2026-10-19, UC9R + PBUP): the streak you'd have now and how many of your marked days
/// met it — from the fresh start if there is one, else all your history. Counted the way Journey counts (its card's rate and
/// the Salah page's streak): YourJourneyStats.streakDay for each goal, an excused day steps over, today never breaks the
/// streak, a day still going isn't judged for the rate, which shows from 3 judged days. Once, off the main thread, for all
/// four, so moving the dot only reads it.
struct GoalPreview: Equatable {
    var streak = 0
    /// Strong weeks in a row at this goal (PrayerMetrics.strongWeeks, as the Salah bar counts them with MetricsLook).
    var weeks = 0
    var met = 0
    var judged = 0
    var rate: Int? { judged >= 3 ? Int((Double(met) / Double(judged) * 100).rounded()) : nil }

    @MainActor static func all(container: ModelContainer, ranges: [ExcusedRange]) async -> [PrayerGoal: GoalPreview] {
        let today = PrayerDay.start()
        let log = await JourneyLog.load(container: container, ranges: ranges)
        return await Task.detached(priority: .userInitiated) {
            count(log: log, today: today, excused: Excused.Days(ranges))
        }.value
    }

    nonisolated static func count(log: JourneyLog, today: Date, excused: Excused.Days, now: Date = Date()) -> [PrayerGoal: GoalPreview] {
        var out: [PrayerGoal: GoalPreview] = [:]
        let cal = Calendar.current
        for goal in PrayerGoal.allCases {
            var p = GoalPreview()
            for d in log.days.values where d.active && d.counted && !d.unfinished {
                p.judged += 1
                if YourJourneyStats.streakDay(d, goal: goal) { p.met += 1 }
            }
            if let first = log.firstDay {
                var run = 0
                var date = cal.startOfDay(for: max(first, log.countsFrom ?? first))
                while date <= today {
                    let d = log.day(date)
                    if YourJourneyStats.excusedAll(d, on: date, in: log, excused) {
                        // An excused day neither counts nor breaks.
                    } else if YourJourneyStats.streakDay(d, goal: goal) {
                        run += 1
                    } else if date != today {
                        run = 0
                    }
                    guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                    date = next
                }
                p.streak = run
            }
            var atGoal = log
            atGoal.goal = goal
            p.weeks = PrayerMetrics.strongWeeks(in: atGoal, excused: excused, now: now).current
            out[goal] = p
        }
        return out
    }
}


/// A goal's radio circle on the goal page's list (owner, 2026-10-19: "checkmarks just appear. make those check marks radio
/// buttons instead"): a quiet ring; yours turns sage and its dot springs in, the old one's shrinks away.
struct GoalRadio: View {
    let on: Bool
    /// Your saved goal: an ink outline while another is tried, so you can see which one you have (owner, 2026-10-19:
    /// "put diff color outline on the radio button of our current goal so we know as we change").
    var current = false
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.sage : current ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.4),
                                  lineWidth: current && !on ? 2 : 1.6)
            Circle().fill(Color.sage)
                .padding(5)
                .scaleEffect(on ? 1 : 0.2)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: on)
        .accessibilityHidden(true)
    }
}

/// The navigation stack's back button and swipe, switched off and on in UIKit without hiding anything (hiding the back button
/// collapsed the bar and moved the page). Back on when it goes away, whatever.
private struct NavPopGuard: UIViewControllerRepresentable {
    let locked: Bool
    func makeUIViewController(context: Context) -> Holder { Holder() }
    func updateUIViewController(_ vc: Holder, context: Context) { vc.locked = locked }
    static func dismantleUIViewController(_ vc: Holder, coordinator: ()) { vc.locked = false }

    final class Holder: UIViewController {
        var locked = false { didSet { apply() } }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); set(false) }
        private func apply() { set(locked) }
        private func set(_ on: Bool) {
            guard let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = !on
            nav.navigationBar.isUserInteractionEnabled = !on
        }
    }
}
