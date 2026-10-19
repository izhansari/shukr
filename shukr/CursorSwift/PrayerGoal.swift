import SwiftUI

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
/// clean … like a wheel selector"). In the soft look: a light title over one grey line; the hero is a prayer's window as a
/// ring — green the first 30 minutes, yellow half of what's left, red to the end (PrayerScoring) — and the marked ring's
/// hollow dot is the slider: drag it round, let go and it springs to the end of its color. Inside, the goals sit on a wheel
/// that rolls as the dot crosses a color. Under it the four goals, strictest first; Made up counts is only here (the dot
/// rests at the end and turns grey: Qaza is after the window, so it isn't on the ring). No numbers.
struct PrayerGoalPage: View {
    @Environment(\.circleTheme) private var theme
    @State private var goal = PrayerGoal.current
    /// The dot's place round the ring, degrees from the top; and how grey it is (Made up counts). Both spring.
    @State private var angle = PrayerGoalDial.rest(PrayerGoal.current)
    @State private var grey: Double = PrayerGoal.current == .prayed ? 1 : 0
    @State private var dragging = false

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

                PrayerGoalDial(angle: angle, grey: grey, dragging: dragging)
                    .frame(width: PrayerGoalDial.size, height: PrayerGoalDial.size)
                    .contentShape(Circle())
                    .gesture(drag)
                    .padding(.top, 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your goal")
                    .accessibilityValue("\(goal.title). \(goal.line)")
                    .accessibilityAdjustableAction { direction in
                        let order = PrayerGoalDial.onRing, i = order.firstIndex(of: goal) ?? 1
                        let next = direction == .increment ? min(i + 1, order.count - 1) : max(i - 1, 0)
                        pick(order[next])
                    }

                list.padding(.top, 30)

                Text("Scores never change. Change it any time.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 22).padding(.bottom, 24)
            }
            .fontDesign(.rounded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: goal)
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in
            guard !dragging, PrayerGoal.current != goal else { return }
            goal = PrayerGoal.current; angle = PrayerGoalDial.rest(goal); grey = goal == .prayed ? 1 : 0
        }
    }

    /// The dot follows the finger round the ring (its colors only; Made up counts is the list's). Let go: it springs to the
    /// end of the color it's in, and that's the goal.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let c = PrayerGoalDial.size / 2
                var a = atan2(v.location.x - c, -(v.location.y - c)) * 180 / .pi
                if a < 0 { a += 360 }
                // The top is where the window starts and ends: never wrap past it.
                if a < PrayerGoalDial.minAngle || a > PrayerGoalDial.maxAngle { a = angle > 180 ? PrayerGoalDial.maxAngle : PrayerGoalDial.minAngle }
                if !dragging { dragging = true }
                angle = a
                if grey > 0 { withAnimation(.smooth(duration: 0.25)) { grey = 0 } }
                let now = PrayerGoalDial.goal(at: a)
                if now != goal { goal = now }
            }
            .onEnded { _ in
                dragging = false
                pick(PrayerGoalDial.goal(at: angle))
            }
    }

    private func pick(_ g: PrayerGoal) {
        goal = g
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            angle = PrayerGoalDial.rest(g)
            grey = g == .prayed ? 1 : 0
        }
        PrayerGoal.set(g)
    }

    /// The four goals, strictest first: a hollow dot in the color each one ends on, the name, the check on yours.
    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(PrayerGoalDial.order.enumerated()), id: \.element) { i, option in
                Button { pick(option) } label: {
                    HStack(spacing: 16) {
                        Circle().strokeBorder(PrayerGoalDial.color(of: option), lineWidth: 2.5).frame(width: 13, height: 13)
                        Text(option.title).font(.body).foregroundStyle(option == goal ? .primary : .secondary)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.sage)
                            .opacity(option == goal ? 1 : 0)
                    }
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title). \(option.line)")
                .accessibilityAddTraits(option == goal ? .isSelected : [])
                if i < PrayerGoalDial.order.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 28)
    }
}

/// The ring, the dot and the wheel of words, drawn from two values that animate (the dot's angle and its grey), so a
/// spring moves them all together, frame by frame.
struct PrayerGoalDial: View, Animatable {
    var angle: Double
    var grey: Double
    var dragging: Bool
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, grey) }
        set { angle = newValue.first; grey = newValue.second }
    }
    @Environment(\.circleTheme) private var theme

    static let size: CGFloat = 300
    static let minAngle = 10.0, maxAngle = 352.0
    /// A prayer's window clockwise from the top, drawn for about a three-hour window: Perfect the first 30 minutes, Middle
    /// half of what's left, Closing the rest (PrayerScoring.score). Degrees.
    static let zones: [(from: Double, to: Double, score: Double)] = [(4, 62, 1), (62, 208, 0.9), (208, 356, 0.7)]
    static let order: [PrayerGoal] = [.perfect, .onTime, .inWindow, .prayed]
    static let onRing: [PrayerGoal] = [.perfect, .onTime, .inWindow]
    /// Where the dot rests for a goal: just inside the end of its color (Made up counts: the end, grey).
    static func rest(_ g: PrayerGoal) -> Double {
        switch g { case .perfect: 58; case .onTime: 204; case .inWindow, .prayed: maxAngle }
    }
    static func goal(at a: Double) -> PrayerGoal { a <= zones[0].to ? .perfect : a <= zones[1].to ? .onTime : .inWindow }
    static func color(of g: PrayerGoal) -> Color {
        switch g { case .perfect: PrayerScoring.color(for: 1); case .onTime: PrayerScoring.color(for: 0.9)
        case .inWindow: PrayerScoring.color(for: 0.7); case .prayed: PrayerScoring.color(for: PrayerScoring.qaza) }
    }
    /// Just past a boundary the color blends from the last one over 10° (fluid as it moves, pure where it rests).
    private static let blend = 10.0

    private var dotColor: Color {
        var c = PrayerScoring.color(for: Self.zones[0].score)
        for (i, z) in Self.zones.enumerated() {
            if angle > z.from { c = PrayerScoring.color(for: z.score) }
            if i > 0, angle > z.from, angle < z.from + Self.blend {
                c = PrayerScoring.color(for: Self.zones[i - 1].score).mix(with: c, by: (angle - z.from) / Self.blend)
            }
        }
        return c.mix(with: PrayerScoring.color(for: PrayerScoring.qaza), by: grey)
    }
    /// The wheel's place: 0 Perfect … 2 Before it ends, 3 Made up counts — it rolls one step as the dot crosses a color
    /// (over the same 10° the color blends), and one more as it turns grey.
    private var wheel: Double {
        var p = 0.0
        for z in Self.zones.dropFirst() {
            let t = min(max((angle - z.from) / Self.blend, 0), 1)
            p += t * t * (3 - 2 * t)
        }
        return p + grey
    }

    var body: some View {
        let s = Self.size, r = s / 2 - 22, band: CGFloat = 14
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: band + 10).frame(width: r * 2, height: r * 2)
            ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, z in
                let color = PrayerScoring.color(for: z.score)
                let lit = min(z.to, angle)
                arc(z.from + 0.8, z.to - 0.8, r).stroke(color.opacity(0.18), lineWidth: band)
                if lit > z.from + 0.8 { arc(z.from + 0.8, lit, r).stroke(color, lineWidth: band) }
            }
            // The marked ring's hollow dot.
            Circle()
                .fill(theme.surface)
                .overlay(Circle().strokeBorder(dotColor, lineWidth: 4.5))
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .scaleEffect(dragging ? 1.15 : 1)
                .offset(x: r * sin(angle * .pi / 180), y: -r * cos(angle * .pi / 180))
            words.frame(width: r * 2 - 70, height: r * 2 - 40)
        }
        .frame(width: s, height: s)
        .animation(.snappy(duration: 0.2), value: dragging)
    }

    private func arc(_ from: Double, _ to: Double, _ r: CGFloat) -> some Shape {
        Circle().trim(from: from / 360, to: to / 360)
            .rotation(.degrees(-90))
            .size(width: r * 2, height: r * 2)
            .offset(x: Self.size / 2 - r, y: Self.size / 2 - r)
    }

    /// The four goals on a drum, like the Clock app's wheel: the one in the middle at full size with its line, the next
    /// ones turned away and faint above and below, fading out at the top and bottom.
    private var words: some View {
        ZStack {
            ForEach(Array(Self.order.enumerated()), id: \.element) { i, g in
                let d = Double(i) - wheel, near = abs(d)
                VStack(spacing: 6) {
                    Text(g.title).font(.system(size: 24, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(g.line).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(max(0, 1 - near * 1.8))
                }
                .rotation3DEffect(.degrees(-d * 50), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .offset(y: d * 74)
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
