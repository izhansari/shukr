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

    static var current: PrayerGoal {
        PrayerGoal(rawValue: UserDefaults.standard.object(forKey: key) as? Int ?? 1) ?? .prayed
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

    /// Settings' words (owner, 2026-10-19: "all five is vague. we mean kaza counts"; "change “on time” to “before closing”
    /// maybe? i think it's clearer").
    var title: String {
        switch self {
        case .prayed: "Made up counts"
        case .inWindow: "Before it ends"
        case .onTime: "Before closing"
        case .perfect: "Perfect"
        }
    }
    var line: String {
        switch self {
        case .prayed: "All five prayed, even made up later as Qaza."
        case .inWindow: "All five before their time runs out."
        case .onTime: "All five while they're green or yellow."
        case .perfect: "All five in their first 30 minutes."
        }
    }
    /// A day that met it, in a few words (the legend, the runs): "All five prayed", "All five Perfect" …
    var dayWords: String {
        switch self {
        case .prayed: "All five prayed"
        case .inWindow: "All five in time"
        case .onTime: "All five on time"
        case .perfect: "All five Perfect"
        }
    }

    /// A streak of days that met it, after "N days in a row, " (the milestones).
    var runWords: String {
        switch self {
        case .prayed: "all five prayed"
        case .inWindow: "all in time"
        case .onTime: "all on time"
        case .perfect: "all Perfect"
        }
    }
    /// After "all five prayers …" (a milestone's card).
    var prayersWords: String {
        switch self {
        case .prayed: "prayed"
        case .inWindow: "prayed in time"
        case .onTime: "prayed on time"
        case .perfect: "Perfect"
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

/// Your goal (Design, 2026-10-19; canvas board/mocks/your-goal v3 — owner: "I like this design … I just want to keep it
/// simple without the stats, just so it's not intimidating"; "no labels"; "copy inside should have motion that's simple but
/// clean … like a wheel selector"; then "we should match the plain settings look … the arc is super thick. let's match the
/// arc and ring of how the prayer would actually look in its window on salah page … moving the wheel up and down with
/// finger moves the dot proportionally"). Settings' plain grouped look: a light title over one grey line; the hero is a
/// prayer's window drawn as the Salah page draws one — green the first 30 minutes, yellow half of what's left, red to the
/// end (PrayerScoring), in the theme's band and arc — and the marked ring's hollow dot is the slider: drag it round, let go
/// and it springs to the end of its color. Inside, the goals sit on a wheel: it rolls as the dot crosses a color, and a
/// finger rolling it moves the dot. Under it the four goals in a Settings card, strictest first; Made up counts is only
/// there and at the wheel's last step (the dot rests at the end and turns grey: Qaza is after the window). No numbers.
struct PrayerGoalPage: View {
    @State private var goal = PrayerGoal.current
    /// The dot's place round the ring (degrees from the top), how grey it is (Made up counts), and the wheel's place
    /// (0 Perfect … 3 Made up counts). All three spring together.
    @State private var angle = PrayerGoalDial.rest(PrayerGoal.current)
    @State private var grey: Double = PrayerGoal.current == .prayed ? 1 : 0
    @State private var wheel = PrayerGoalDial.index(PrayerGoal.current)
    @State private var drag: PrayerGoalDial.Drag = .none
    @State private var wheelFrom = 0.0
    /// Each goal's streak and days met, counted once when the page opens (GoalPreview); nil until then.
    @State private var previews: [PrayerGoal: GoalPreview]?
    @State private var sinceFreshStart = false
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    // The app's page title (Give to Causes, Fresh start): 30 pt light rounded.
                    Text("Your goal").font(.system(size: 30, weight: .light, design: .rounded))
                    Text("What a day needs to keep your streak.").font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                PrayerGoalDial(angle: angle, grey: grey, wheel: wheel, drag: drag)
                    .frame(width: PrayerGoalDial.size, height: PrayerGoalDial.size)
                    .contentShape(Circle())
                    .gesture(dialDrag)
                    .padding(.top, 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your goal")
                    .accessibilityValue("\(goal.title). \(goal.line)")
                    .accessibilityAdjustableAction { direction in
                        let i = PrayerGoalDial.order.firstIndex(of: goal) ?? 1
                        let next = direction == .increment ? min(i + 1, PrayerGoalDial.order.count - 1) : max(i - 1, 0)
                        pick(PrayerGoalDial.order[next])
                    }

                preview.padding(.top, 10)

                list.padding(.top, 14)

                Text("Scores never change. Change it any time.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 14).padding(.bottom, 24)
            }
            .fontDesign(.rounded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: goal)
        .task {
            let container = context.container
            let ranges = Excused.ranges
            sinceFreshStart = FreshStart.dayKey != nil
            let counted = await GoalPreview.all(container: container, ranges: ranges)
            withAnimation(.easeOut(duration: 0.25)) { previews = counted }
        }
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in
            guard drag == .none, PrayerGoal.current != goal else { return }
            goal = PrayerGoal.current
            angle = PrayerGoalDial.rest(goal); grey = goal == .prayed ? 1 : 0; wheel = PrayerGoalDial.index(goal)
        }
    }

    /// One drag, two ways, decided where it starts: on the band the dot follows the finger round (its colors only); inside
    /// the ring the finger rolls the wheel and the dot moves with it, step for step. Let go: both spring to a goal.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let c = PrayerGoalDial.size / 2
                if drag == .none {
                    let fromCentre = hypot(v.startLocation.x - c, v.startLocation.y - c)
                    drag = fromCentre < PrayerGoalDial.radius - 26 ? .wheel : .ring
                    wheelFrom = wheel
                }
                switch drag {
                case .ring:
                    var a = atan2(v.location.x - c, -(v.location.y - c)) * 180 / .pi
                    if a < 0 { a += 360 }
                    // The top is where the window starts and ends: never wrap past it.
                    if a < PrayerGoalDial.minAngle || a > PrayerGoalDial.maxAngle { a = angle > 180 ? PrayerGoalDial.maxAngle : PrayerGoalDial.minAngle }
                    angle = a
                    if grey > 0 { withAnimation(.smooth(duration: 0.25)) { grey = 0 } }
                    // The wheel rolls once, calmly, when the goal under the dot changes — it used to follow the dot over the
                    // 10° past each color's start and flicked by (owner, 2026-10-19: "wheel switches real fast when dragging
                    // the ring dot").
                    let now = PrayerGoalDial.goal(at: a)
                    if now != goal {
                        goal = now
                        withAnimation(PrayerGoalDial.wheelRoll) { wheel = PrayerGoalDial.index(now) }
                    }
                case .wheel:
                    // Up rolls the next goal in from below, as a picker wheel does.
                    let p = min(max(wheelFrom - Double(v.translation.height) / PrayerGoalDial.step, 0), 3)
                    wheel = p
                    angle = PrayerGoalDial.angle(atWheel: p)
                    grey = max(0, p - 2)
                    let now = PrayerGoalDial.order[Int(p.rounded())]
                    if now != goal { goal = now }
                case .none: break
                }
            }
            .onEnded { _ in
                let g = drag == .wheel ? PrayerGoalDial.order[Int(wheel.rounded())] : PrayerGoalDial.goal(at: angle)
                drag = .none
                pick(g)
            }
    }

    private func pick(_ g: PrayerGoal) {
        goal = g
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            angle = PrayerGoalDial.rest(g)
            grey = g == .prayed ? 1 : 0
            wheel = PrayerGoalDial.index(g)
        }
        PrayerGoal.set(g)
    }

    /// The goal under the dot (or the wheel), as it would be (owner, 2026-10-19, UC9R + PBUP: how the streak would change and
    /// "add percentage of days met too … just choose something good"): the streak in light type, then the days that met it and
    /// the %. Quiet, one goal at a time, never a table (Design kept this page free of a scoreboard); always the same height, so
    /// the list below never moves.
    private var preview: some View {
        let p = previews?[goal]
        let streak = p.map { $0.streak == 0 ? "0-day streak" : $0.streak == 1 ? "1-day streak" : "\($0.streak)-day streak" } ?? " "
        let days: String = {
            guard let p, p.judged > 0 else { return " " }
            let base = "Met on \(p.met) of \(p.judged) days" + (p.rate.map { " · \($0)%" } ?? "")
            return base + (sinceFreshStart ? " since your fresh start" : "")
        }()
        return VStack(spacing: 3) {
            Text(streak)
                .font(.system(size: 19, weight: .light, design: .rounded))
                .contentTransition(.numericText(value: Double(p?.streak ?? 0)))
            Text(days)
                .font(.footnote).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText(value: Double(p?.met ?? 0)))
        }
        .animation(.snappy(duration: 0.25), value: goal)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(p == nil ? "" : "With \(goal.title): \(streak). \(days)")
    }

    /// The four goals in a Settings card, strictest first: a hollow dot in the color each one ends on, the name, a radio
    /// circle filled on yours.
    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(PrayerGoalDial.order.enumerated()), id: \.element) { i, option in
                Button { pick(option) } label: {
                    HStack(spacing: 14) {
                        Circle().strokeBorder(PrayerGoalDial.color(of: option), lineWidth: 2.4).frame(width: 13, height: 13)
                            .frame(width: 24)
                        Text(option.title).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        GoalRadio(on: option == goal)
                    }
                    .frame(minHeight: 50)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title). \(option.line)")
                .accessibilityAddTraits(option == goal ? .isSelected : [])
                if i < PrayerGoalDial.order.count - 1 { Divider().padding(.leading, 54) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal, 20)
    }
}

/// The ring, the dot and the wheel of words, drawn from values that animate (the dot's angle, its grey, the wheel's place),
/// so a spring moves them all together, frame by frame.
struct PrayerGoalDial: View, Animatable {
    var angle: Double
    var grey: Double
    var wheel: Double
    var drag: Drag
    enum Drag { case none, ring, wheel }
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(angle, AnimatablePair(grey, wheel)) }
        set { angle = newValue.first; grey = newValue.second.first; wheel = newValue.second.second }
    }
    @Environment(\.circleTheme) private var theme

    static let size: CGFloat = 290
    /// The ring's radius: a little larger than the Salah page's 200 pt circle (room for the wheel), the same band, arc and
    /// dot.
    static let radius: CGFloat = 118
    /// The wheel's roll to the dot's goal while the dot is dragged round the ring.
    static let wheelRoll = Animation.smooth(duration: 0.45)
    /// How far a finger moves the wheel one goal.
    static let step: Double = 64
    static let minAngle = 8.0, maxAngle = 352.0
    /// A prayer's window clockwise from the top, drawn for about a three-hour window: Perfect the first 30 minutes, Middle
    /// half of what's left, Closing the rest (PrayerScoring.score). Degrees; small gaps between them, as the day's fifths.
    static let zones: [(from: Double, to: Double, score: Double)] = [(4, 62, 1), (62, 208, 0.9), (208, 356, 0.7)]
    static let gap = 2.4
    static let order: [PrayerGoal] = [.perfect, .onTime, .inWindow, .prayed]
    static func index(_ g: PrayerGoal) -> Double { Double(order.firstIndex(of: g) ?? 1) }
    /// Where the dot rests for a goal: just inside the end of its color (Made up counts: the end, grey).
    static func rest(_ g: PrayerGoal) -> Double {
        switch g { case .perfect: 58; case .onTime: 204; case .inWindow, .prayed: maxAngle }
    }
    static func goal(at a: Double) -> PrayerGoal { a <= zones[0].to ? .perfect : a <= zones[1].to ? .onTime : .inWindow }
    /// The dot's place for the wheel's: straight between the goals' rests (the end for Made up counts).
    static func angle(atWheel p: Double) -> Double {
        let rests = [rest(.perfect), rest(.onTime), rest(.inWindow)]
        if p >= 2 { return rests[2] }
        let i = Int(p), t = p - Double(i)
        return rests[i] + (rests[i + 1] - rests[i]) * t
    }
    static func color(of g: PrayerGoal) -> Color {
        switch g { case .perfect: PrayerScoring.color(for: 1); case .onTime: PrayerScoring.color(for: 0.9)
        case .inWindow: PrayerScoring.color(for: 0.7); case .prayed: PrayerScoring.color(for: PrayerScoring.qaza) }
    }
    /// Just past a boundary the dot's color blends from the last one over 10° (fluid as it moves, pure where it rests).
    private static let blend = 10.0

    /// The dot's color: from the ring under it, or — while a finger rolls the wheel — from the goals the wheel is between;
    /// then toward grey for Made up counts.
    private var dotColor: Color {
        var c: Color
        if drag == .wheel {
            let i = min(Int(wheel), 2), t = min(max(wheel - Double(i), 0), 1)
            c = Self.color(of: Self.order[i]).mix(with: Self.color(of: Self.order[min(i + 1, 2)]), by: i < 2 ? t : 0)
        } else {
            c = PrayerScoring.color(for: Self.zones[0].score)
            for (i, z) in Self.zones.enumerated() where i > 0 && angle > z.from {
                c = PrayerScoring.color(for: z.score)
                if angle < z.from + Self.blend {
                    c = PrayerScoring.color(for: Self.zones[i - 1].score).mix(with: c, by: (angle - z.from) / Self.blend)
                }
            }
        }
        return c.mix(with: PrayerScoring.color(for: PrayerScoring.qaza), by: grey)
    }

    var body: some View {
        let r = Self.radius, d = r * 2
        ZStack {
            track.frame(width: d, height: d)
            // The day ring's thickness: half the prayer arc's band (owner, 2026-10-19: "change color ring thickness on goal page
            // to match thickness of rings shows on the day ring. it's too thick rn").
            let band = theme.arc.width * 0.5
            ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, z in
                let color = PrayerScoring.color(for: z.score)
                let a0 = z.from + Self.gap / 2, a1 = z.to - Self.gap / 2, lit = min(a1, angle)
                arc(a0, a1).stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: band, lineCap: theme.arc.cap))
                    .frame(width: d, height: d)
                if lit > a0 + 0.5 {
                    arc(a0, lit).stroke(color, style: StrokeStyle(lineWidth: band, lineCap: theme.arc.cap))
                        .frame(width: d, height: d)
                        .shadow(color: color.opacity(theme.arc.glow), radius: 6)
                }
            }
            // The marked ring's hollow dot (PrayerCompletionFX: 12 pt at 200, a 2.4 pt rim), a touch bigger as a slider.
            Circle()
                .fill(Color(.systemGroupedBackground))
                .overlay(Circle().strokeBorder(dotColor, lineWidth: 2.8))
                .frame(width: 15, height: 15)
                .scaleEffect(drag == .none ? 1 : 1.35)
                .offset(x: r * sin(angle * .pi / 180), y: -r * cos(angle * .pi / 180))
            words.frame(width: d - 56, height: d - 30)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.snappy(duration: 0.2), value: drag)
    }

    /// The Salah page's track in the theme: the soft raised band, or the plain grey one.
    @ViewBuilder private var track: some View {
        if theme.track.lifted {
            Circle()
                .stroke(lineWidth: theme.track.width)
                .foregroundStyle(theme.surface)
                .shadow(color: theme.shade, radius: 4, x: 2, y: 2)
                .shadow(color: theme.light, radius: 6, x: -2, y: -2)
        } else {
            Circle().stroke(theme.track.fill, lineWidth: theme.track.width)
        }
    }

    private func arc(_ from: Double, _ to: Double) -> some Shape {
        Circle().trim(from: from / 360, to: to / 360).rotation(.degrees(-90))
    }

    /// The four goals on a drum, like the Clock app's wheel: the one in the middle at full size with its line, the next
    /// ones turned away and faint above and below, fading out at the top and bottom.
    private var words: some View {
        ZStack {
            ForEach(Array(Self.order.enumerated()), id: \.element) { i, g in
                let d = Double(i) - wheel, near = abs(d)
                VStack(spacing: 6) {
                    Text(g.title).font(.system(size: 23, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(g.line).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(max(0, 1 - near * 1.8))
                }
                .rotation3DEffect(.degrees(-d * 50), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .offset(y: d * 70)
                .opacity(max(0, 1 - near * 0.8))
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // the fade spans the wheel's box, not just the words in it
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.24),
                                     .init(color: .black, location: 0.76), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}


/// Your goal's preview, per goal (owner, 2026-10-19, UC9R + PBUP): the streak you'd have now and how many of your marked days
/// met it — from the fresh start if there is one, else all your history. Counted the way Journey counts (its card's rate and
/// the Salah page's streak): YourJourneyStats.streakDay for each goal, an excused day steps over, today never breaks the
/// streak, a day still going isn't judged for the rate, which shows from 3 judged days. Once, off the main thread, for all
/// four, so moving the dot only reads it.
struct GoalPreview: Equatable {
    var streak = 0
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

    nonisolated static func count(log: JourneyLog, today: Date, excused: Excused.Days) -> [PrayerGoal: GoalPreview] {
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
            out[goal] = p
        }
        return out
    }
}


/// A goal's radio circle on the goal page's list (owner, 2026-10-19: "checkmarks just appear. make those check marks radio
/// buttons instead"): a quiet ring; yours turns sage and its dot springs in, the old one's shrinks away.
struct GoalRadio: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.sage : Color.secondary.opacity(0.4), lineWidth: 1.6)
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
