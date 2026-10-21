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


/// This week as one ring toward a strong week (owner, 2026-10-21, pick B on https://claude.ai/artifact/T1hh4B26y7iP93z1h8Ypj4:
/// "it's simple and easy. and we can fill the back end with arc showing the prayer that don't fit the goal (either missed or
/// prayed at lower than goal)"). From the top, clockwise: the prayers that met your goal, green. From the top, back the other
/// way: the ones that didn't — missed (still to make up) darker, prayed below your goal lighter. The gap between is what's
/// still to come. A tick where the back may reach for a strong week (the slack, 3 in from the end): past it, the week can't
/// be strong. Each part one round run, never broken at the joins (owner, on the first drawing: "it's like broken at the
/// divides"). Was seven day arcs with an accordion (Zoe, 2026-10-20 / 21).
struct JourneyGoalRing: View, Animatable {
    var met: Double
    var missed: Double
    var below: Double
    /// What the week asks (35, fewer with excused prayers): the ring's whole.
    let asked: Int
    /// How many may miss your goal in a strong week: the back reaches the tick at this (0 on Prayed — every prayer).
    var slack: Int = PrayerMetrics.strongWeekSlack
    var lineWidth: CGFloat = 14
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(met, AnimatablePair(missed, below)) }
        set { met = newValue.first; missed = newValue.second.first; below = newValue.second.second }
    }
    @Environment(\.colorScheme) private var scheme

    /// Room outside the band for the tick's word.
    static let labelRoom: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let r = side / 2 - lineWidth / 2 - Self.labelRoom
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink = scheme == .dark ? Color.white : Color.black
            let unit = 360 / Double(max(asked, 1))
            func arc(_ from: Double, _ to: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
                return p
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(ink.opacity(0.07)), lineWidth: lineWidth)
            // Round ends inside their share: drawn short by the cap's angle at each end.
            let cap = Double(lineWidth / 2 / r) * 180 / .pi
            func run(_ from: Double, _ to: Double, _ color: Color) {
                guard to - from > 0.05 else { return }
                let a0 = from + cap, a1 = max(to - cap, a0 + 0.01)
                ctx.stroke(arc(a0, a1), with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            run(0, met * unit, .green)
            // The back, one run: below your goal (lighter) under, missed (darker) over it nearest the top, so they meet in a
            // round join, not a gap.
            run(360 - (missed + below) * unit, 360, ink.opacity(0.22))
            run(360 - missed * unit, 360, ink.opacity(0.45))
            // The strong-week tick, across the band, its word outside (none on Prayed: a strong week there is all of it —
            // Fable's check).
            if slack > 0, asked > slack {
                let at = (360 - Double(slack) * unit - 90) * .pi / 180
                func p(_ rr: CGFloat) -> CGPoint { CGPoint(x: c.x + rr * cos(at), y: c.y + rr * sin(at)) }
                var tick = Path()
                tick.move(to: p(r - lineWidth / 2 - 3))
                tick.addLine(to: p(r + lineWidth / 2 + 3))
                ctx.stroke(tick, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let word = ctx.resolve(Text("strong").font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(0.5)))
                ctx.draw(word, at: p(r + lineWidth / 2 + 11), anchor: .center)
            }
        }
        .accessibilityHidden(true)
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

    var body: some View {
        let ringSide: CGFloat = compact ? 196 : (tight ? 216 : 232)
        let lineWidth: CGFloat = compact ? 12 : 14
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
                JourneyGoalRing(met: Double(w?.met ?? 0), missed: Double(w?.notMarked ?? 0), below: Double(w?.belowStep ?? 0),
                                asked: w?.asked ?? 35, slack: w.map(Self.slack) ?? PrayerMetrics.strongWeekSlack, lineWidth: lineWidth)
                    .frame(width: ringSide, height: ringSide)
                    .animation(.smooth(duration: CircleMotion.quick), value: model?.week)
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
            Text(model.map(Self.line) ?? " ")
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3).minimumScaleFactor(0.85)
                .frame(height: 60)
                .padding(.horizontal, 6)
                .padding(.top, tight ? 8 : 12)
                .contentTransition(.opacity)
                .animation(.smooth(duration: CircleMotion.quick), value: model.map(Self.line))
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
        .sheet(item: $filling) { f in
            NoRecordPickSheet(day: f.day) { chosen in
                NoRecordDays.fill(f.day, picked: chosen, viewModel: viewModel)
                noRecord = question()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in read() }
        .accessibilityElement(children: .contain)
    }

    /// "15 of 35" over your goal's words ("in their windows"); a week that asks nothing, "–".
    @ViewBuilder private var centre: some View {
        let w = model?.week
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(w.map { $0.asked == 0 ? "–" : "\($0.met)" } ?? " ")
                    .font(.system(size: compact ? 44 : 50, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let w, w.asked > 0 {
                    Text("of \(w.asked)")
                        .font(.system(size: compact ? 18 : 20, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(w.map { $0.asked == 0 ? "excused this week" : $0.goal.countWords } ?? " ")
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: (compact ? 196 : 232) * 0.62)
        .animation(.smooth(duration: CircleMotion.quick), value: w?.met)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(w.map { $0.asked == 0 ? "Excused this week" : "This week: \($0.met) of \($0.asked) \($0.goal.countWords)" } ?? "")
        .allowsHitTesting(false)
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
