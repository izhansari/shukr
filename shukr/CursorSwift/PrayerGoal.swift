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

    /// The step's name on the ladder (outstanding row 10, owner's go 2026-10-21: "Prayed · In its window · Middle · Opening"):
    /// Settings' row, Journey's row, Your Data and the goal page read it. Was the grade it reaches down to ("Qaza / Closing /
    /// Middle / Opening", Design's v7, 2026-10-19).
    var title: String {
        switch self {
        case .prayed: "Prayed"
        case .inWindow: "In its window"
        case .onTime: "Middle"
        case .perfect: "Opening"
        }
    }
    /// What the step asks of each prayer: the dial's grey line on the goal page.
    var line: String {
        switch self {
        case .prayed: "Prayed, even if made up later"
        case .inWindow: "Prayed before its window ends"
        case .onTime: "Prayed before its last third"
        case .perfect: "Prayed in the first third of its window"
        }
    }
    /// The goal page's order: strictest first.
    static let strictestFirst: [PrayerGoal] = [.perfect, .onTime, .inWindow, .prayed]
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

/// Your goal (owner, 2026-10-21; spec board/mocks/your-goal-v2/spec.md, drawn by Zoe, canvas
/// https://claude.ai/artifact/XWVw6Pz8pzbVUtBiMs9UDJ): the title and the rule in his words; the editor's dial with no
/// clock (GoalHero.swift), its dot parked where the step tried stops counting — tap a step and it glides there, or drag the
/// dial ("option to drag the dial"); the four steps; what the step would have made of last week (GoalLastWeek.swift); and
/// "Aim for <step>" ("when they click the button, they feel like they're agreeing to something"), live only off your goal.
/// The page never leaves on its own. Tried and dropped: v7's Prayer circle card over a radio list with the streak in the
/// ring and a "what if" line under Save (round 1), three rings over a list ("so ugly … looks really boring"), a line of
/// "you'd have had 25 of 35" (round 2's Y3), "Fill in Friday" under the chips ("dont wanna send the user down a rabit hole").
struct PrayerGoalPage: View {
    /// The goal being tried — only the button makes it yours.
    @State private var goal = PrayerGoal.current
    /// Yours, as saved: a small dot under its step while you try others.
    @State private var current = PrayerGoal.current
    /// The dial's place, in windows (PrayerGoal.edge): it glides between steps and follows a drag.
    @State private var dial = PrayerGoal.current.edge
    @State private var dragFrom: Double?
    /// Each goal counted once when the page opens (GoalPreview); nil until then.
    @State private var previews: [PrayerGoal: GoalPreview]?
    @State private var excusedOpen = false
    /// The button's moment is playing: nothing takes a tap.
    @State private var saving = false
    /// Fresh start's bottom glow, blooming as "Aim for" is pressed and fading as the moment ends (owner, 2026-10-22: "make it
    /// so that the button causes the same bottom glow we use on fresh start").
    @State private var glow = 0.0
    @State private var checkDrawn: CGFloat = 0
    @State private var savedTick = 0
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
                    // The same for every step, verbatim (owner, 2026-10-21; no closing period, as he wrote it).
                    Text("Set a goal for how early you aim to pray. Don\u{2019}t miss a prayer, and keep nearly all at your goal: that\u{2019}s a strong week")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                GoalKnobBox(goal: goal, value: dial, line: goal.line, height: 300)
                    .contentShape(Rectangle())
                    // Over the page's scroll: a drag in the box turns the dial.
                    .highPriorityGesture(dialDrag)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your goal dial, \(goal.title)")
                    .accessibilityValue(goal.line)
                    .accessibilityAdjustableAction { direction in
                        let steps = PrayerGoal.strictestFirst
                        guard let i = steps.firstIndex(of: goal) else { return }
                        let j = direction == .increment ? min(i + 1, steps.count - 1) : max(i - 1, 0)
                        pick(steps[j])
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                GoalStepRow(goal: goal, current: current, pick: pick)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                GoalLastWeek(week: previews?[goal]?.lastWeek, ready: previews != nil, goal: goal) { excusedOpen = true }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
            }
            .fontDesign(.rounded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { saveBar }
        .background {
            ZStack {
                Color(.systemGroupedBackground)
                SageGlow(strength: glow, bloom: glow > 0.5)
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        // Back never saves; during the moment nothing is touched, the back button and swipe included.
        .background { NavPopGuard(locked: navLocked) }
        .allowsHitTesting(!saving)
        .sensoryFeedback(.selection, trigger: goal)
        .sensoryFeedback(.success, trigger: savedTick)
        .sheet(isPresented: $excusedOpen) {
            if let week = previews?[goal]?.lastWeek { GoalExcusedSheet(week: week) }
        }
        .task {
            let container = context.container
            let ranges = Excused.ranges
            let counted = await GoalPreview.all(container: container, ranges: ranges)
            withAnimation(.easeOut(duration: 0.25)) { previews = counted }
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

    /// Finger up → later edges come up from below (the editor's way round); the nearest step goes live as you pass it (the
    /// selection buzz, the step row follows); let go → it settles on that step.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragFrom == nil { dragFrom = dial }
                dial = min(max((dragFrom ?? dial) - Double(v.translation.height) / 380, 0.2), 1.45)
                let near = PrayerGoal.nearest(to: dial)
                if near != goal { goal = near }
            }
            .onEnded { _ in
                dragFrom = nil
                pick(goal)
            }
    }

    /// Try a goal: the dial glides to where it stops counting.
    private func pick(_ g: PrayerGoal) {
        goal = g
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.84)) { dial = g.edge }
    }

    /// "Aim for <step>" — onboarding's PrimaryButton look, faded and off on your goal. At a tap the check draws in and it says
    /// "Saved".
    private var saveBar: some View {
        let changed = goal != current
        return Button(action: save) {
            // Out, then in: "Aim for Middle" never sits over "Aim for Prayed".
            OutThenIn(value: saving ? "Saved" : "Aim for \(goal.stepLabel)") { label in
                HStack(spacing: 7) {
                    if label == "Saved" {
                        SaveCheck(drawn: checkDrawn).frame(width: 17, height: 13)
                    }
                    Text(label)
                }
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
        .animation(.easeInOut(duration: 0.2), value: changed)
        .animation(.easeInOut(duration: 0.25), value: saving)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Clear while the glow is up, so it rises behind the button as on Fresh start (the bar's own page colour cut it off).
        .background(Color(.systemGroupedBackground).opacity(1 - glow))
    }

    /// The moment (about 1.2 s): a success buzz, the check draws in, "Saved"; then the button fades back off on your new
    /// goal and the page stays (owner, 2026-10-19: "i don't want it to exit the page on its own").
    private func save() {
        guard goal != current, !saving else { return }
        navLocked = true
        PrayerGoal.set(goal)
        current = goal
        savedTick += 1
        saving = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) { glow = 1 }
        // The check draws in once "Saved" has come in.
        withAnimation(.easeOut(duration: 0.3).delay(0.14)) { checkDrawn = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            navLocked = false
            saving = false
            withAnimation(.easeInOut(duration: 0.8)) { glow = 0 }
            try? await Task.sleep(for: .seconds(0.15))
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
    /// Your last finished week counted at this goal (the page's "At this goal, last week"); nil before a full week — one
    /// that started on or after your first day (and the fresh start), so days before you used shukr never read as excused.
    var lastWeek: PrayerMetrics.Week?
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
            if let began = [log.firstDay, log.countsFrom].compactMap({ $0 }).max().map(cal.startOfDay) {
                p.lastWeek = PrayerMetrics.weeks(in: atGoal, excused: excused, now: now)
                    .last { $0.finished && $0.start >= began }
            }
            out[goal] = p
        }
        return out
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
