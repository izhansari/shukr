//
//  JourneyWeekHero.swift
//  shukr
//
//  Journey's hero as the prayer-metrics rethink has it: this week as one ring toward a strong week (owner, 2026-10-21, pick B
//  on Frank's canvas https://claude.ai/artifact/T1hh4B26y7iP93z1h8Ypj4, after his "i wanna get it to a quality level first
//  thats clear and easy"), the seven days as dots under it, one line, the finished weeks banked; the 16-week calendar is one
//  tap down, behind the card's ↗. Every count reads PrayerMetrics (Fable's data layer): no screen decides a week on its own.
//  Behind `MetricsLook.on` until he OKs the look.
//

import SwiftUI

/// The prayer-metrics rethink's new looks, while he tries them (owner, 2026-10-20: "His OK on each look before it ships").
/// On in DEBUG builds (his phones run them) unless turned off; off in Release until he says.
enum MetricsLook {
    static let key = "metrics.v34.look"
    static var on: Bool {
        #if DEBUG
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
        #else
        false
        #endif
    }
}

/// Several numbers as one animatable value (one missing on a side counts as 0): a chart's columns, a ring's days.
struct AnimatableNumbers: VectorArithmetic {
    var v: [Double]
    static var zero: AnimatableNumbers { AnimatableNumbers(v: []) }
    private static func zip(_ a: AnimatableNumbers, _ b: AnimatableNumbers, _ f: (Double, Double) -> Double) -> AnimatableNumbers {
        let n = max(a.v.count, b.v.count)
        return AnimatableNumbers(v: (0..<n).map { f($0 < a.v.count ? a.v[$0] : 0, $0 < b.v.count ? b.v[$0] : 0) })
    }
    static func + (a: AnimatableNumbers, b: AnimatableNumbers) -> AnimatableNumbers { zip(a, b, +) }
    static func - (a: AnimatableNumbers, b: AnimatableNumbers) -> AnimatableNumbers { zip(a, b, -) }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
    /// The `i`th, never below 0 (a spring's overshoot).
    subscript(_ i: Int) -> Double { i < v.count ? max(0, v[i]) : 0 }
}


/// This week as one ring toward a strong week, each kind of prayer its own pill with a gap between, no shared track (owner,
/// 2026-10-21, on https://claude.ai/artifact/XowC56NDXsAUPk2NzcvbGt: "different arcs pills instead of sharing a common track …
/// no overlap of the different pills"). From the top going right: green for the prayers that met your goal, then a dashed
/// hairline for those still to come, the Salah ring's own upcoming dashes ("matching what our future prayers show inside of
/// the Salah ring"). From the top going left: excused (frost, crosshatched), below your goal (light grey), then one hollow pill,
/// "not marked": the missed prayers and the days with no record together (owner, 2026-10-21, option B: "one hollow pill called
/// not marked" — simpler to read, and it never calls a day with no record missed), past below ("put the pill of missed further
/// to the left than below your goal"). The strong tick sits on it while any are left ("put the strong marker on top of the
/// missed ones … the user knows that they have to make up the missed ones"), else where the back may reach for a strong week
/// (3 in from the end; none on Prayed). A tap on a pill or the tick picks it: the others
/// dim and the card's centre says what it counts. Was one track with a back end (16060f54), before that seven day arcs.
struct JourneyGoalRing: View, Animatable {
    enum Part: Int, CaseIterable { case met, toCome, below, notMarked, excused, tick }
    /// The counts, in `Part` order up to `.excused` (their sum is the ring's whole), then each part's opacity (a pick dims the
    /// rest), all one animatable value.
    var values: AnimatableNumbers
    /// How many may miss your goal in a strong week (0 on Prayed — every prayer).
    var slack: Int = PrayerMetrics.strongWeekSlack
    var lineWidth: CGFloat = 14
    var onPick: (Part?) -> Void = { _ in }
    var animatableData: AnimatableNumbers {
        get { values }
        set { values = newValue }
    }
    @Environment(\.colorScheme) private var scheme
    @State private var size: CGSize = .zero

    init(counts: [Int], picked: Part?, slack: Int, lineWidth: CGFloat, onPick: @escaping (Part?) -> Void = { _ in }) {
        let alphas = Part.allCases.map { picked == nil || picked == $0 ? 1.0 : 0.22 }
        values = AnimatableNumbers(v: counts.map(Double.init) + alphas)
        self.slack = slack
        self.lineWidth = lineWidth
        self.onPick = onPick
    }

    /// Room outside the band for the tick's word.
    static let labelRoom: CGFloat = 16
    /// The canvas reaches this far past the ring's frame (layout unchanged), so the word never clips where the tick sits at
    /// the side ("trong" at 10 o'clock on a 15-prayer week).
    static let spill: CGFloat = 26
    /// The gap between two pills, along the band.
    static let gap: CGFloat = 6
    static let frost = Color(red: 0.55, green: 0.62, blue: 0.75)

    private func count(_ p: Part) -> Double { values[p.rawValue] }
    private func alpha(_ p: Part) -> Double { min(values[Part.excused.rawValue + 1 + p.rawValue], 1) }

    /// Each part's stretch in prayers from the top, clockwise (the back counted from the end), and where the tick sits.
    struct Layout {
        var total: Double
        var runs: [(part: Part, from: Double, to: Double)]
        var tick: Double?
        /// The tick sits on the not-marked pill: a tap on the band there is the pill's, the tick's is its word.
        var tickOnPill = false
    }
    static func layout(_ n: (Part) -> Double, slack: Int) -> Layout {
        let total = max(Part.allCases.dropLast().reduce(0) { $0 + n($1) }, 0.0001)
        var runs: [(Part, Double, Double)] = []
        var at: [Part: Double] = [:]
        var u = 0.0
        for p in [Part.met, .toCome] {
            runs.append((p, u, u + n(p)))
            at[p] = u + n(p) / 2
            u += n(p)
        }
        u = total
        for p in [Part.excused, .below, .notMarked] {
            runs.append((p, u - n(p), u))
            at[p] = u - n(p) / 2
            u -= n(p)
        }
        let asked = total - n(.excused)
        let tick: Double? = n(.notMarked) > 0.5 ? at[.notMarked]
            : (slack > 0 && asked > Double(slack)) ? total - n(.excused) - Double(slack) : nil
        return Layout(total: total, runs: runs, tick: tick, tickOnPill: n(.notMarked) > 0.5)
    }

    /// The band's radius in a canvas of this size.
    private static func radius(_ size: CGSize, lineWidth: CGFloat) -> CGFloat {
        (min(size.width, size.height) - 2 * spill) / 2 - lineWidth / 2 - labelRoom
    }

    var body: some View {
        Canvas { ctx, size in
            let r = Self.radius(size, lineWidth: lineWidth)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink = scheme == .dark ? Color.white : Color.black
            let L = Self.layout(count, slack: slack)
            let unit = 360 / L.total
            let cap = Double(lineWidth / 2 / r) * 180 / .pi, gap = Double(Self.gap / r) * 180 / .pi
            func arc(_ from: Double, _ to: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
                return p
            }
            /// A pill over prayers `u0 ..< u1`: its round ends inside its share, a gap's half short at each end; a single
            /// prayer (or less, mid-animation) is a dot.
            func pill(_ u0: Double, _ u1: Double, inset: CGFloat = 0) -> Path {
                var s = u0 * unit + gap / 2 + cap, e = u1 * unit - gap / 2 - cap
                if e < s { s = (u0 + u1) / 2 * unit; e = s }
                return arc(s, e + 0.01).strokedPath(StrokeStyle(lineWidth: lineWidth - inset, lineCap: .round))
            }
            for run in L.runs where run.to - run.from > 0.02 {
                let a = alpha(run.part)
                switch run.part {
                case .met:
                    ctx.fill(pill(run.from, run.to), with: .color(.green.opacity(a)))
                case .toCome:
                    // A hairline, not a pill: from past the green (or the top) to the back's first pill.
                    let s = run.from * unit + gap / 2, e = run.to * unit - gap / 2
                    guard e > s else { continue }
                    ctx.stroke(arc(s, e), with: .color(Color.secondary.opacity(UpcomingTrack.opacity * a)),
                               style: UpcomingTrack.style(diameter: 2 * r))
                case .below:
                    ctx.fill(pill(run.from, run.to), with: .color(ink.opacity(0.22 * a)))
                case .notMarked:
                    ctx.stroke(pill(run.from, run.to, inset: 1.5), with: .color(Color.secondary.opacity(0.6 * a)), lineWidth: 1.4)
                case .excused:
                    let shape = pill(run.from, run.to, inset: 1.5)
                    ctx.drawLayer { layer in
                        layer.clip(to: shape)
                        var hatch = Path()
                        let box = shape.boundingRect.insetBy(dx: -6, dy: -6)
                        var x = box.minX - box.height
                        while x < box.maxX {
                            hatch.move(to: CGPoint(x: x, y: box.minY)); hatch.addLine(to: CGPoint(x: x + box.height, y: box.maxY))
                            hatch.move(to: CGPoint(x: x + box.height, y: box.minY)); hatch.addLine(to: CGPoint(x: x, y: box.maxY))
                            x += 5
                        }
                        layer.stroke(hatch, with: .color(Self.frost.opacity(0.8 * a)), lineWidth: 0.8)
                    }
                    ctx.stroke(shape, with: .color(Self.frost.opacity(a)), lineWidth: 1.4)
                case .tick: break
                }
            }
            // The strong tick, across the band, its word outside.
            if let t = L.tick {
                let at = (t * unit - 90) * .pi / 180, a = alpha(.tick)
                func p(_ rr: CGFloat) -> CGPoint { CGPoint(x: c.x + rr * cos(at), y: c.y + rr * sin(at)) }
                var tick = Path()
                tick.move(to: p(r - lineWidth / 2 - 3))
                tick.addLine(to: p(r + lineWidth / 2 + 3))
                ctx.stroke(tick, with: .color(ink.opacity(0.8 * a)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let word = ctx.resolve(Text("strong").font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(0.5 * a)))
                // Its inner edge faces the band, whichever way the tick points.
                ctx.draw(word, at: p(r + lineWidth / 2 + 5), anchor: UnitPoint(x: 0.5 - 0.5 * cos(at), y: 0.5 - 0.5 * sin(at)))
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { pick(at: $0.location) })
        .padding(-Self.spill)
        .accessibilityHidden(true)
    }

    /// What's under a tap: the tick (within a finger of it; on a pill, only its word outside the band — a single missed prayer
    /// is no wider than the tick's finger), a pill, the hairline — or nothing (inside or outside the band), which puts the
    /// ring back.
    private func pick(at point: CGPoint) {
        let r = Self.radius(size, lineWidth: lineWidth)
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let d = (dx * dx + dy * dy).squareRoot()
        var deg = atan2(dx, -dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        let L = Self.layout(count, slack: slack)
        let unit = 360 / L.total
        if let t = L.tick, d > r - lineWidth / 2 - 16, d < r + lineWidth / 2 + 30 {
            var off = abs(deg - t * unit).truncatingRemainder(dividingBy: 360)
            off = min(off, 360 - off)
            if off * .pi / 180 * r < 16, !L.tickOnPill || d > r + lineWidth / 2 { return onPick(.tick) }
        }
        guard abs(d - r) < lineWidth / 2 + 16 else { return onPick(nil) }
        let u = deg / unit
        let hit = L.runs.first { u >= $0.from && u < $0.to && $0.to - $0.from > 0.5 }
        onPick(hit?.part)
    }
}

/// Journey's card as this week (MetricsLook): the ring toward a strong week, its count in your goal's words, one line, the
/// seven days, the last finished weeks banked.
struct JourneyWeekCard: View {
    let log: JourneyLog
    var compact = false
    var tight = false
    /// The ↗: the calendar (JourneyExpanded.swift), as the old card's was.
    var onExpand: (Date) -> Void = { _ in }
    /// A day's dot tapped: its day page (owner, 2026-10-21: "tapping those days can just push the day ring page for now").
    var onDay: (Date) -> Void = { _ in }
    var opens: (Date) -> Bool = { _ in false }
    /// The most recent day with no record to ask about (NoRecordDays.next — Frank's flow), and the day the Pick sheet is
    /// open for. The question sits in the banked weeks' slot: the card never changes height for it.
    @State private var noRecord: Date?
    /// This visit to Journey has been counted for the question's 3 (once per page, not per redraw).
    @State private var visitCounted = false
    @State private var filling: FillDay?
    struct FillDay: Identifiable { let day: Date; var id: Date { day } }
    @Environment(\.modelContext) private var context
    @Environment(PrayerViewModel.self) private var viewModel

    /// What the card shows, read when the log changes (never per frame).
    struct Model: Equatable {
        let week: PrayerMetrics.Week
        let banked: [PrayerMetrics.Week]
        let todayIndex: Int
        /// This week's missed prayers, oldest first: (its prayer day, its name).
        let owed: [Owed]
        /// This week's days with no record that can be filled in (on or after the first mark ever, before today).
        let fillable: [Date]
        struct Owed: Equatable { let day: Date; let name: String }
    }
    @State private var model: Model?
    /// The latest read (an older one landing after it is dropped).
    @State private var readToken = 0
    /// Each day's dot on screen (global), for the calendar's flight.
    @State private var dotFrames: [Int: CGRect] = [:]
    /// The ring's part last tapped: the centre says what it counts until it's tapped again (or the ring off a pill).
    @State private var picked: JourneyGoalRing.Part?

    var body: some View {
        let ringSide: CGFloat = compact ? 196 : (tight ? 216 : 232)
        let lineWidth: CGFloat = compact ? 9.5 : 11   // owner, 2026-10-21: "a little bit thinner. They're really thick right now" (was 12 : 14)
        VStack(spacing: 0) {
            HStack {
                Text(rangeLabel)
                Spacer()
            }
            .font(.system(size: 13, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .journeyFlightWords(.card)
            ZStack {
                let w = model?.week
                JourneyGoalRing(counts: ringCounts(w), picked: picked, slack: w.map(Self.slack) ?? PrayerMetrics.strongWeekSlack,
                                lineWidth: lineWidth) { part in
                    if part != nil || picked != nil { triggerSomeVibration(type: .light) }
                    picked = part == picked ? nil : part
                }
                    .frame(width: ringSide, height: ringSide)
                    .animation(.smooth(duration: CircleMotion.quick), value: model?.week)
                    .animation(.smooth(duration: 0.2), value: picked)
                centre
            }
            .padding(.top, tight ? 2 : 6)
            .journeyFlightWords(.card)
            dots
                .padding(.top, tight ? 4 : 8)
                .journeyFlightWords(.card)
            // One line: what keeps the week strong, or that it can't be now (owner, 2026-10-21: "you have to also account for
            // the messaging for when they miss their strong week"). Three lines' room always (the mid-week line's), centred:
            // nothing moves when it changes.
            Text(lineNow ?? " ")
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3).minimumScaleFactor(0.85)
                .frame(height: 60)
                .padding(.horizontal, 6)
                .padding(.top, tight ? 8 : 12)
                .contentTransition(.opacity)
                .animation(.smooth(duration: CircleMotion.quick), value: lineNow)
                .journeyFlightWords(.card)
            ZStack(alignment: .top) {
                banked.opacity(noRecord == nil ? 1 : 0)
                if let day = noRecord { noRecordQuestion(day).transition(.opacity) }
            }
            .animation(.smooth(duration: CircleMotion.quick), value: noRecord)
            .padding(.top, tight ? 6 : 10)
            .journeyFlightWords(.card)
        }
        .padding(.top, tight ? 14 : 18).padding(.horizontal, 18).padding(.bottom, tight ? 8 : 10)
        .overlay(alignment: .topTrailing) {
            Button {
                triggerSomeVibration(type: .light)
                onExpand(JourneyLog.monthStart(PrayerDay.start()))
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, tight ? 4 : 8).padding(.trailing, 8)
            .accessibilityLabel("Open your weeks")
            .journeyFlightWords(.card)
        }
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)).journeyFlightCardSurface())
        .journeyFlightCard()
        .onAppear {
            JourneyFlightGeometry.shared.cardShow = nil   // no grid here to scroll back to after the calendar
            reportFlight()
        }
        .task(id: log.version) { read(); noRecord = question() }
        .onChange(of: model?.week) { _, w in
            // A part the week no longer has puts the ring back.
            if let p = picked, p != .tick, ringCounts(w)[p.rawValue] == 0 { picked = nil }
        }
        .sheet(item: $filling) { f in
            NoRecordPickSheet(day: f.day) { chosen in
                NoRecordDays.fill(f.day, picked: chosen, viewModel: viewModel)
                noRecord = question()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in read() }
        .accessibilityElement(children: .contain)
    }

    /// The line under the days: a picked part's own (when it has one), else the week's.
    private var lineNow: String? {
        guard let m = model else { return nil }
        if let p = picked {
            let hint = Self.pickWords(p, week: m.week, counts: ringCounts(m.week), owed: m.owed).hint
            if !hint.isEmpty { return hint }
        }
        return Self.line(m)
    }

    /// The ring's parts, in `JourneyGoalRing.Part` order: met, still to come, below your goal, not marked (missed, and a day
    /// with no record's five), excused. Days before the first mark ever ask nothing and aren't excused: they're left off the ring.
    private func ringCounts(_ w: PrayerMetrics.Week?) -> [Int] {
        guard let w else { return [0, 35, 0, 0, 0] }
        let before = w.days.filter(beforeFirst).count * 5
        return [w.met, w.toCome, w.belowStep, w.notMarked + w.noRecordDays * 5, max(w.excused - before, 0)]
    }

    /// "15 of 35" over your goal's words ("in their windows"); a week that asks nothing, "–". A part of the ring picked: its
    /// count and its words; its line takes the card's line under the days (inside the ring it ran into the pills).
    @ViewBuilder private var centre: some View {
        let w = model?.week
        let pick = w.flatMap { w in picked.map { Self.pickWords($0, week: w, counts: ringCounts(w), owed: model?.owed ?? []) } }
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(pick?.number ?? w.map { $0.asked == 0 ? "–" : "\($0.met)" } ?? " ")
                    .font(.system(size: compact ? 44 : 50, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let w, w.asked > 0, pick == nil {
                    Text("of \(w.asked)")
                        .font(.system(size: compact ? 18 : 20, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(pick?.words ?? w.map { $0.asked == 0 ? "excused this week" : $0.goal.countWords } ?? " ")
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: (compact ? 196 : 232) * 0.62)
        .animation(.smooth(duration: CircleMotion.quick), value: w?.met)
        .animation(.smooth(duration: 0.2), value: picked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pick.map { "\($0.number) \($0.words). \($0.hint)" }
            ?? w.map { $0.asked == 0 ? "Excused this week" : "This week: \($0.met) of \($0.asked) \($0.goal.countWords)" } ?? "")
        .allowsHitTesting(false)
    }

    /// What a tapped part of the ring says (owner, 2026-10-21, on the mock: "click on each portion to see the copy inside
    /// change"). No "up to 3" under below your goal: with a prayer missed it reads as if 3 were still allowed, against the
    /// ring (his comment on the mock).
    static func pickWords(_ part: JourneyGoalRing.Part, week w: PrayerMetrics.Week, counts: [Int], owed: [Model.Owed])
        -> (number: String, words: String, hint: String) {
        let target = max(w.asked - slack(w), 0)
        let missedDays = owed.map(\.day).reduce(into: [Date]()) { if !$0.contains($1) { $0.append($1) } }
        let noRecordDays = w.days.filter(\.noRecord).map(\.date)
        let n = counts.indices.contains(part.rawValue) ? counts[part.rawValue] : 0
        switch part {
        case .met:
            return ("\(n)", w.goal.countWords,
                    w.finished ? (w.strong ? "A strong week" : "Not a strong week")
                    : !w.stillPossible ? "This one can't be strong now"
                    : slack(w) == 0 ? "Don't miss a prayer for a strong week" : "Keep \(target) at your goal for a strong week")
        case .toCome:
            return ("\(n)", "still to come", "")
        case .below:
            let not = w.goal == .inWindow ? (n == 1 ? "not in its window" : "not in their windows") : "not \(w.goal.countWords)"
            return ("\(n)", "below your goal", "Prayed, \(not)")
        case .notMarked:
            // What each kind needs, in the day order: "Sun – Tue: fill them in. Today: make up 2."
            var steps: [String] = []
            if !noRecordDays.isEmpty { steps.append("\(dayList(noRecordDays)): fill \(noRecordDays.count == 1 ? "it" : "them") in") }
            if !missedDays.isEmpty { steps.append("\(dayList(missedDays)): make up \(owed.count == 1 ? owed[0].name : "\(owed.count)")") }
            let what = w.finished ? "Not marked that week"
                : !w.stillPossible ? steps.joined(separator: ". ") + ". A new week starts Sunday."
                : steps.count == 1 ? steps[0] + " to keep the week strong"
                : steps.joined(separator: ". ") + "."
            return ("\(n)", "not marked", what)
        case .excused:
            return ("\(n)", "excused", "Left out of the week")
        case .tick:
            let rule = slack(w) == 0 ? "Don't miss a prayer" : "Don't miss a prayer, and keep nearly all at your goal"
            return ("\(target)", "for a strong week",
                    w.finished ? rule
                    : !w.stillPossible ? "This one can't be strong now. A new week starts Sunday."
                    : w.notMarked > 0 && w.noRecordDays > 0
                        ? "Fill in \(dayList(noRecordDays)) and make up \(w.notMarked) first. A strong week has none missed."
                    : w.notMarked > 0 ? "Make up the \(w.notMarked) missed first. A strong week has none missed."
                    : w.noRecordDays > 0 ? "Fill in \(dayList(noRecordDays)) first. A strong week has every day on record."
                    : rule)
        }
    }

    /// "Today", "Wed", "Mon and Wed", "Sun – Tue" (three or more in a row), "Mon, Wed, Fri".
    private static func dayList(_ days: [Date]) -> String {
        let cal = Calendar.current, today = PrayerDay.start()
        let names = days.map { cal.isDate($0, inSameDayAs: today) ? "Today" : $0.formatted(.dateTime.weekday(.abbreviated)) }
        guard names.count > 1 else { return names.first ?? "" }
        let inRow = zip(days, days.dropFirst()).allSatisfy { cal.dateComponents([.day], from: $0, to: $1).day == 1 }
        if names.count >= 3, inRow { return "\(names[0]) – \(names[names.count - 1])" }
        if names.count == 2 { return "\(names[0]) and \(names[1])" }
        return names.joined(separator: ", ")
    }

    /// The seven days under the ring: a day with every prayer marked filled light grey, the Salah list's done dot; one with
    /// any still unmarked hollow (owner, 2026-10-21: "switch to hollow gray for unmarked and filled light gray for marked
    /// (matching the color of our salah list mark)"); no record dotted; all excused frosted. Today's initial in ink. A tap
    /// pushes the day's page (a dotted day: its Pick sheet).
    private var dots: some View {
        HStack(spacing: compact ? 12 : 14) {
            ForEach(0..<7, id: \.self) { i in
                let day = model?.week.days[i]
                Button { tappedDay(i) } label: {
                    VStack(spacing: 4) {
                        dot(day)
                            .frame(width: 16, height: 16)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                dotFrames[i] = $0
                                reportFlight()
                            }
                        Text(initial(i))
                            .font(.system(size: 10.5, weight: i == model?.todayIndex ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(i == model?.todayIndex ? Color.primary.opacity(0.85) : Color.secondary)
                    }
                    .frame(width: 24, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.map { "\($0.date.formatted(.dateTime.weekday(.wide))), \(beforeFirst($0) ? "before you started" : Self.dayWords($0))" } ?? "")
            }
        }
    }

    private static let edge = Color.secondary.opacity(0.5)
    private static let frost = Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.38)

    /// A day before the first mark ever (the app wasn't in use yet): it asks nothing, like an excused day, but isn't one.
    private func beforeFirst(_ day: PrayerMetrics.Day) -> Bool {
        log.firstDay.map { day.date < Calendar.current.startOfDay(for: $0) } ?? false
    }

    @ViewBuilder private func dot(_ day: PrayerMetrics.Day?) -> some View {
        if let day, beforeFirst(day) {
            // Not frost (that's Excused Mode): a small faint dot, nothing asked.
            Circle().fill(Color.secondary.opacity(0.18)).padding(5)
        } else if let day, day.states == nil {
            Circle().inset(by: 0.7).stroke(Self.edge, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 3.6]))
        } else if let states = day?.states, states.allSatisfy({ $0 == .excused }) {
            Circle().fill(Self.frost)
        } else if let day, Self.allMarked(day) {
            ZStack {
                Circle().strokeBorder(Self.edge, lineWidth: 1)
                Circle().fill(Color.gray.opacity(0.35)).padding(1)   // the Salah list's muted done dot
            }
        } else {
            Circle().strokeBorder(Self.edge, lineWidth: 1)
        }
    }

    /// Every prayer it asked marked (prayed, made up or with no time; an excused one isn't asked) and none still to come.
    static func allMarked(_ day: PrayerMetrics.Day) -> Bool {
        guard let states = day.states else { return false }
        return states.contains(where: \.prayed) && states.allSatisfy { $0.prayed || $0 == .excused }
    }

    private static func dayWords(_ day: PrayerMetrics.Day) -> String {
        guard let states = day.states else { return "no record" }
        if states.allSatisfy({ $0 == .excused }) { return "excused" }
        if states.allSatisfy({ $0 == .toCome }) { return "to come" }
        let prayed = states.filter(\.prayed).count, due = states.filter { $0 != .excused }.count
        let toCome = states.filter { $0 == .toCome }.count
        return toCome > 0 ? "\(prayed) prayed, \(toCome) to come" : "\(prayed) of \(due) prayed"
    }

    private func initial(_ i: Int) -> String {
        Calendar.current.veryShortStandaloneWeekdaySymbols[(Calendar.current.firstWeekday - 1 + i) % 7]
    }

    private func tappedDay(_ i: Int) {
        guard let day = model?.week.days[i] else { return }
        if day.states == nil, model?.fillable.contains(day.date) == true {
            triggerSomeVibration(type: .light)
            filling = FillDay(day: day.date)
        } else if day.states != nil, opens(day.date) {
            triggerSomeVibration(type: .light)
            onDay(day.date)
        }
    }

    /// The line under the days, the first that's true:
    /// - out of reach: the mid-week line (it names the goal; owner, 2026-10-21: "explain in regards to their goal");
    /// - something owed: what to make up, then what to fill in, to keep the week strong;
    /// - already enough: "A strong week, so far";
    /// - else the rule: "Don't miss a prayer, and keep 32 at your goal: that's a strong week" (Sunday: "A new week. "
    ///   first; on Prayed only "Don't miss a prayer").
    static func line(_ m: Model) -> String {
        let w = m.week
        guard w.asked > 0 else { return "Excused prayers are left out" }
        let target = max(w.asked - slack(w), 0)
        if !w.stillPossible {
            return PrayerMetrics.midweekLine(w) ?? "This one won't be a strong week. A new one starts Sunday."
        }
        if let first = m.owed.first {
            return m.owed.count == 1 ? "Make up \(possessive(first.day)) \(first.name) to keep the week strong"
                : "Make up \(m.owed.count) missed prayers to keep the week strong"
        }
        if let day = m.fillable.first {
            return m.fillable.count == 1 ? "Fill in \(dayName(day)) to keep the week strong"
                : "Fill in \(m.fillable.count) days to keep the week strong"
        }
        if w.met >= target { return "A strong week, so far" }
        // The rule's own words (owner, 2026-10-21, on Your goal: "Don't miss a prayer, and keep nearly all at your goal:
        // that's a strong week"), with the hero's number; on Prayed "don't miss a prayer" is the whole of it.
        let rule = slack(w) == 0 ? "Don't miss a prayer" : "Don't miss a prayer, and keep \(target) at your goal"
        return (m.todayIndex == 0 ? "A new week. " : "") + "\(rule): that's a strong week"
    }

    /// How many may miss the goal in a strong week: the slack above Prayed; on Prayed none (every prayer prayed — Fable's
    /// check: belowStep is always 0 there, so strong means all of it).
    static func slack(_ w: PrayerMetrics.Week) -> Int { w.goal == .prayed ? 0 : PrayerMetrics.strongWeekSlack }

    /// "today's", "yesterday's", "Monday's".
    private static func possessive(_ day: Date) -> String {
        let cal = Calendar.current, today = PrayerDay.start()
        if cal.isDate(day, inSameDayAs: today) { return "today's" }
        if let y = cal.date(byAdding: .day, value: -1, to: today), cal.isDate(day, inSameDayAs: y) { return "yesterday's" }
        return day.formatted(.dateTime.weekday(.wide)) + "'s"
    }
    private static func dayName(_ day: Date) -> String {
        let cal = Calendar.current, today = PrayerDay.start()
        if let y = cal.date(byAdding: .day, value: -1, to: today), cal.isDate(day, inSameDayAs: y) { return "yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    /// The day to ask about, if any: NoRecordDays.next, but it steps aside after it's been shown on 3 visits to Journey without
    /// an answer (owner, 2026-10-20: "Let the no-record question step aside after 3 opens"), and stays quiet until a newer day
    /// has no record (that one gets its own 3). The day can still be filled from its dotted dot. Counted once per visit.
    private func question() -> Date? {
        guard let day = NoRecordDays.next(in: context) else { return nil }
        let d = UserDefaults.standard
        let key = PrayerNotificationID.dayKey(day)
        if let quiet = d.string(forKey: Self.quietKey), key <= quiet { return nil }   // "YYYY-MM-DD" keys sort by date
        var shown = d.integer(forKey: Self.shownKey + key)
        if !visitCounted {
            visitCounted = true
            shown += 1
            d.set(shown, forKey: Self.shownKey + key)
        }
        if shown > Self.visits {
            d.set(key, forKey: Self.quietKey)
            return nil
        }
        return day
    }
    private static let visits = 3
    private static let shownKey = "noRecord.shown."
    private static let quietKey = "noRecord.quietThrough"

    /// "Yesterday has no record. Did you pray?" (plan-v3 §3: a day with nothing logged is no record, never missed), in the
    /// banked weeks' place. "Pick which" opens the day's five; "Not now" isn't asked again for that day.
    private func noRecordQuestion(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(NoRecordDays.name(of: day)) has no record. Did you pray?")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.85)
            HStack(spacing: 18) {
                Button {
                    triggerSomeVibration(type: .light)
                    filling = FillDay(day: day)
                } label: {
                    Text("Pick which").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.primary)
                }
                Button {
                    NoRecordDays.dismiss(day)
                    withAnimation(.smooth(duration: CircleMotion.quick)) { noRecord = question() }
                } label: {
                    Text("Not now").font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, tight ? 6 : 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).offset(y: tight ? -6 : -8) }
    }

    /// The last two finished weeks, newest first: past tense, quiet, "strong" only when it was (canvas row B, Sunday).
    private var banked: some View {
        VStack(spacing: 0) {
            if let m = model, m.banked.isEmpty {
                Text("Finished weeks show here")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, tight ? 8 : 10)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
            }
            ForEach(Array((model?.banked ?? []).enumerated()), id: \.offset) { i, w in
                HStack {
                    Text(Self.range(w.start))
                    Spacer(minLength: 8)
                    Text(bankedWords(w)).multilineTextAlignment(.trailing)
                }
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.vertical, tight ? 8 : 10)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
                .accessibilityElement(children: .combine)
            }
        }
        // Two rows' room always (no layout shift as weeks arrive).
        .frame(minHeight: (tight ? 34 : 38) * 2, alignment: .top)
    }

    private func bankedWords(_ w: PrayerMetrics.Week) -> String {
        if w.excusedWeek { return "Excused" }
        let count = "\(w.met) of \(w.asked)"
        if w.complete { return "\(count) · complete" }
        if w.strong { return "\(count) · strong" }
        return count
    }

    /// "Oct 18 – 24" (across a month: "Oct 25 – Nov 1").
    private static func range(_ start: Date) -> String {
        guard let end = Calendar.current.date(byAdding: .day, value: 6, to: start) else { return "" }
        let a = start.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        return "\(a) – \(sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var rangeLabel: String {
        guard let w = model?.week else { return "This week" }
        return "This week · \(Self.range(w.start))"
    }

    /// This week's days as the calendar's flight takes them (JourneyFlightGeometry.ringTiles): each day's dot, flying to the
    /// day's ring in the calendar and back. Its weeks: just this one.
    private func reportFlight() {
        guard let w = model?.week, dotFrames.count == 7 else { return }
        let g = JourneyFlightGeometry.shared
        var tiles: [Date: CGRect] = [:]
        for (i, day) in w.days.enumerated() {
            if let f = dotFrames[i] { tiles[Calendar.current.startOfDay(for: day.date)] = f }
        }
        g.ringTiles = tiles
        let all = dotFrames.values.reduce(CGRect.null) { $0.union($1) }
        g.grid = all
        g.weekStarts = [w.start]
    }

    /// Every week since day one (~100 for him) is walked for the banked rows: off the main thread, as JourneyStore reads the
    /// log (Fable's check: Journey's open was a 71–80 ms trace already). The ring shows its empty track until it lands, the
    /// same size, so nothing moves.
    private func read() {
        readToken += 1
        let mine = readToken, log = log, excused = Excused.Days(), now = Date()
        Task.detached(priority: .userInitiated) {
            let next = Self.model(log: log, excused: excused, now: now)
            await MainActor.run {
                guard mine == readToken else { return }
                if next != model { model = next; reportFlight() }
            }
        }
    }

    nonisolated private static func model(log: JourneyLog, excused: Excused.Days, now: Date) -> Model {
        let all = PrayerMetrics.weeks(in: log, excused: excused, now: now)
        let week = all.last(where: \.isCurrent) ?? PrayerMetrics.week(containing: now, in: log, excused: excused, now: now)
        let finished = all.filter { !$0.isCurrent }
        let todayStart = PrayerDay.start(for: now)
        let today = Calendar.current.dateComponents([.day], from: week.start, to: todayStart).day ?? 0
        var owed: [Model.Owed] = []
        for day in week.days {
            guard let states = day.states else { continue }
            for (j, s) in states.enumerated() where s == .notMarked { owed.append(Model.Owed(day: day.date, name: JourneyLog.names[j])) }
        }
        let fillable = week.days.filter { day in
            day.states == nil && day.date < todayStart && (log.firstDay.map { day.date >= $0 } ?? false)
        }.map(\.date)
        return Model(week: week, banked: Array(finished.suffix(2).reversed()), todayIndex: min(max(today, 0), 6),
                     owed: owed, fillable: fillable)
    }
}
