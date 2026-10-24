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
/// to the left than below your goal"). The strong tick is the finish line, always where it is: what the week asks less the
/// slack (32 of 35; the top on Prayed, every prayer). It sat on the not-marked pill while any were left ("put the strong
/// marker on top of the missed ones"), which moved it round the ring — on his data to 9 o'clock, reading as "strong is
/// halfway" (Fable's critique; owner, 2026-10-21: "alright do 1,2,3"). What's owed first is the line's and the tick's tap. All of it inside the Salah circle's raised band, the parts at the Salah arc's 6 pt,
/// the green with its glow. A tap on a pill or the tick picks it: the others
/// dim and the card's centre says what it counts. Was one track with a back end (16060f54), before that seven day arcs.
struct JourneyGoalRing: View, Animatable {
    enum Part: Int, CaseIterable { case met, toCome, below, notMarked, excused, tick }
    /// The counts, in `Part` order up to `.excused` (their sum is the ring's whole), then each part's opacity (a pick dims the
    /// rest), all one animatable value.
    var values: AnimatableNumbers
    /// How many may miss your goal in a strong week (0 on Prayed — every prayer).
    var slack: Int = PrayerMetrics.strongWeekSlack
    var lineWidth: CGFloat = 14
    /// The strong tick (off while Excused Mode is on: nothing is asked of the week then).
    var tickShown = true
    var onPick: (Part?) -> Void = { _ in }
    /// Hold and drag round the ring: the part under the finger, set (not toggled) as it passes (owner, 2026-10-22: "make
    /// it so we can hold and drag to select different pills … it keeps selecting strong" — the grid's hold, JourneyHoldPick).
    var onScrub: (Part) -> Void = { _ in }
    var animatableData: AnimatableNumbers {
        get { values }
        set { values = newValue }
    }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    @State private var size: CGSize = .zero
    /// The pager's pan, held off while the finger scrubs the ring (Journey is a pager page; the grid's hold did the same).
    @Environment(PagerLiveState.self) private var pagerLive: PagerLiveState?
    /// A hold is running (its release isn't a tap), and just ended (the tap that may follow the release is ignored).
    @State private var scrubbing = false
    @State private var scrubEnded = Date.distantPast
    /// The parts' own width inside the band (6 pt at the card's 11: the Salah arc's `AliveRingTuning.fine.band`).
    private var arcWidth: CGFloat { (lineWidth * 0.55).rounded() }

    init(counts: [Int], picked: Part?, slack: Int, lineWidth: CGFloat, tickShown: Bool = true,
         onPick: @escaping (Part?) -> Void = { _ in }, onScrub: @escaping (Part) -> Void = { _ in }) {
        let alphas = Part.allCases.map { picked == nil || picked == $0 ? 1.0 : 0.22 }
        values = AnimatableNumbers(v: counts.map(Double.init) + alphas)
        self.slack = slack
        self.lineWidth = lineWidth
        self.tickShown = tickShown
        self.onPick = onPick
        self.onScrub = onScrub
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
    static func layout(_ n: (Part) -> Double, slack: Int, tick tickShown: Bool = true) -> Layout {
        let total = max(Part.allCases.dropLast().reduce(0) { $0 + n($1) }, 0.0001)
        var runs: [(Part, Double, Double)] = []
        var u = 0.0
        for p in [Part.met, .toCome] {
            runs.append((p, u, u + n(p)))
            u += n(p)
        }
        u = total
        for p in [Part.excused, .below, .notMarked] {
            runs.append((p, u - n(p), u))
            u -= n(p)
        }
        let asked = total - n(.excused)
        let tick: Double? = tickShown && asked > Double(slack) ? asked - Double(slack) : nil
        // On a pill (the not-marked one reaching past the line): a tap on the band there is the pill's, the tick's its word.
        let onPill = tick.map { t in runs.contains { $0.0 == .notMarked && $0.1 < t && t < $0.2 } } ?? false
        return Layout(total: total, runs: runs, tick: tick, tickOnPill: onPill)
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
            let L = Self.layout(count, slack: slack, tick: tickShown)
            let unit = 360 / L.total
            let cap = Double(arcWidth / 2 / r) * 180 / .pi, gap = Double(Self.gap / r) * 180 / .pi
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
                return arc(s, e + 0.01).strokedPath(StrokeStyle(lineWidth: arcWidth - inset, lineCap: .round))
            }
            for run in L.runs where run.to - run.from > 0.02 {
                let a = alpha(run.part)
                switch run.part {
                case .met:
                    // The Salah arc's green and its soft glow.
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: .green.opacity(AliveRingTuning.fine.glow * a), radius: 6))
                        layer.fill(pill(run.from, run.to), with: .color(.green.opacity(a)))
                    }
                case .toCome:
                    // A hairline, not a pill: from past the green (or the top) to the back's first pill.
                    let s = run.from * unit + gap / 2, e = run.to * unit - gap / 2
                    guard e > s else { continue }
                    ctx.stroke(arc(s, e), with: .color(Color.secondary.opacity(UpcomingTrack.opacity * a)),
                               style: UpcomingTrack.style(diameter: 2 * r))
                case .below:
                    ctx.fill(pill(run.from, run.to), with: .color(ink.opacity(0.22 * a)))
                case .notMarked:
                    ctx.stroke(pill(run.from, run.to, inset: 1.2), with: .color(Color.secondary.opacity(0.6 * a)), lineWidth: 1.2)
                case .excused:
                    let shape = pill(run.from, run.to, inset: 1.2)
                    ctx.drawLayer { layer in
                        layer.clip(to: shape)
                        var hatch = Path()
                        let box = shape.boundingRect.insetBy(dx: -6, dy: -6)
                        var x = box.minX - box.height
                        while x < box.maxX {
                            hatch.move(to: CGPoint(x: x, y: box.minY)); hatch.addLine(to: CGPoint(x: x + box.height, y: box.maxY))
                            hatch.move(to: CGPoint(x: x + box.height, y: box.minY)); hatch.addLine(to: CGPoint(x: x, y: box.maxY))
                            x += 4
                        }
                        layer.stroke(hatch, with: .color(Self.frost.opacity(0.8 * a)), lineWidth: 0.7)
                    }
                    ctx.stroke(shape, with: .color(Self.frost.opacity(a)), lineWidth: 1.2)
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
        .gesture(SpatialTapGesture().onEnded { tap in
            guard !scrubbing, Date().timeIntervalSince(scrubEnded) > 0.3 else { return }
            onPick(hit(at: tap.location, scrub: false))
        })
        .gesture(JourneyHoldPick(hold: JourneyHomeCard.holdTime) { state, p, _ in held(state, p) })
        .padding(-Self.spill)
        .background { band }
        .accessibilityHidden(true)
    }

    /// The Salah circle's own band under the parts (owner, 2026-10-21, A on the soft-ring pictures: "mimic our soft ring
    /// style … complements or looks very similar to the Salah ring"): the soft look's raised surface (NeuRingTrack's shade
    /// and light), or Today's grey band. Round the ring's middle, at the card's width.
    private var band: some View {
        Group {
            if theme.track.lifted {
                Circle().stroke(theme.surface, lineWidth: lineWidth)
                    .shadow(color: theme.shade, radius: 4, x: 2, y: 2)
                    .shadow(color: theme.light, radius: 6, x: -2, y: -2)
            } else {
                Circle().stroke(Color(.secondarySystemFill), lineWidth: lineWidth)
            }
        }
        .padding(Self.labelRoom + lineWidth / 2)
        .allowsHitTesting(false)
    }

    /// The hold: the pager's pan off and the part under the finger picked; each new part as the finger passes it (a soft buzz);
    /// let go, the pager back and the pick stays.
    private func held(_ state: UIGestureRecognizer.State, _ p: CGPoint) {
        switch state {
        case .began:
            scrubbing = true
            if pagerLive?.pagerLocked == false { pagerLive?.pagerLocked = true }
            triggerSomeVibration(type: .medium)
            if let part = hit(at: p, scrub: true) { onScrub(part) }
        case .changed:
            guard scrubbing, let part = hit(at: p, scrub: true) else { return }
            onScrub(part)
        default:
            guard scrubbing else { return }
            scrubbing = false
            scrubEnded = Date()
            if pagerLive?.pagerLocked == true { pagerLive?.pagerLocked = false }
        }
    }

    /// What's under the finger. The band is the parts' (owner, 2026-10-22: tapping the not-marked pill "keeps selecting
    /// strong" — the tick took any touch within a finger of it, on the band too); the tick is only its word, outside the band.
    /// A tap off the band and the word: nothing (the ring back). A scrub goes by the angle alone, however far the finger
    /// drifts in or out, so it keeps tracking round the ring.
    private func hit(at point: CGPoint, scrub: Bool) -> Part? {
        let r = Self.radius(size, lineWidth: lineWidth)
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let d = (dx * dx + dy * dy).squareRoot()
        var deg = atan2(dx, -dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        let L = Self.layout(count, slack: slack, tick: tickShown)
        let unit = 360 / L.total
        let outer = r + lineWidth / 2
        if let t = L.tick, d > outer + 4, d < outer + 34 {
            var off = abs(deg - t * unit).truncatingRemainder(dividingBy: 360)
            off = min(off, 360 - off)
            if off * .pi / 180 * r < 22 { return .tick }
        }
        if !scrub, abs(d - r) > lineWidth / 2 + 14 { return nil }
        let u = deg / unit
        return L.runs.first { u >= $0.from && u < $0.to && $0.to - $0.from > 0.5 }?.part
    }
}

/// Journey's card as this week (MetricsLook): the ring toward a strong week, its count in your goal's words, one line, the
/// seven days, the last finished weeks banked.
extension VerticalAlignment {
    /// The week ring's centre (bare): Journey lines it up with the Salah circle's centre.
    private enum JourneyRing: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] } }
    static let journeyRing = VerticalAlignment(JourneyRing.self)
}

struct JourneyWeekCard: View {
    let log: JourneyLog
    var compact = false
    var tight = false
    /// The ↗: the calendar (JourneyExpanded.swift), as the old card's was.
    var onExpand: (Date) -> Void = { _ in }
    /// A day's dot tapped: its day page (owner, 2026-10-21: "tapping those days can just push the day ring page for now").
    var onDay: (Date) -> Void = { _ in }
    var opens: (Date) -> Bool = { _ in false }
    /// The not-marked pill's "Make up ›": To make up on this week (owner, 2026-10-21: "i have no door into making up prayers
    /// from the ring" — D, the same page on its This week line).
    var onMakeUp: () -> Void = {}
    /// On the page, not in a card (owner, 2026-10-23: Journey laid out like the Salah page — one ring, the goal as a pill,
    /// past weeks as one line): no raised card, no range line, no ↗ (the "Last week ›" line opens Your weeks).
    var bare = false
    /// The goal pill under the line (bare only): its name, and what a tap does (the goal dial).
    var goal: PrayerGoal? = nil
    var onGoal: () -> Void = {}
    /// Bare, with the rows pulled up over it: only the ring and its days stay (the rest fades under the rows' card).
    var quiet = false
    /// The most recent day with no record to ask about (NoRecordDays.next — Frank's flow), and the day the Pick sheet is
    /// open for. The question sits in the banked weeks' slot: the card never changes height for it.
    @State private var noRecord: [Date] = []
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
        /// Excused Mode is on now: the week asks nothing until it ends (owner, 2026-10-21, A) — no tick, no make-up or
        /// fill-in asks, no "Did you pray?".
        var excusedNow = false
        /// Strong weeks in a row (PrayerMetrics.strongRun, the Salah bar's count): the header names it from 1.
        var streak = 0
        struct Owed: Equatable { let day: Date; let name: String }
    }
    @State private var model: Model?
    /// The latest read (an older one landing after it is dropped).
    @State private var readToken = 0
    /// Each day's dot on screen (global), for the calendar's flight.
    @State private var dotFrames: [Int: CGRect] = [:]
    /// The ring's part last tapped: the centre says what it counts until it's tapped again (or the ring off a pill).
    @State private var picked: JourneyGoalRing.Part?
    /// The ring's centre and the days' bottom, in the card's own space (bare: JourneyRowsLayout.daysBelowRing).
    @State private var ringMidY: CGFloat = 0
    @State private var daysMaxY: CGFloat = 0
    private static let space = "journeyWeekHero"

    var body: some View {
        // Bare, on the page: near the Salah circle's size (its centre is lined up with it; any bigger and the words under it
        // run into the bottom bar).
        let ringSide: CGFloat = bare ? 226 : (compact ? 196 : (tight ? 216 : 232))
        let lineWidth: CGFloat = compact ? 9.5 : 11   // owner, 2026-10-21: "a little bit thinner. They're really thick right now" (was 12 : 14)
        VStack(spacing: 0) {
            if !bare {
            HStack {
                Text(rangeLabel)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 36)   // clear of the ↗
            }
            .font(.system(size: 13, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .journeyFlightWords(.card)
            }
            ZStack {
                let w = model?.week
                JourneyGoalRing(counts: ringCounts(w), picked: picked, slack: w.map(Self.slack) ?? PrayerMetrics.strongWeekSlack,
                                lineWidth: lineWidth, tickShown: !excusedNow) { part in
                    if part != nil || picked != nil { triggerSomeVibration(type: .light) }
                    picked = part == picked ? nil : part
                } onScrub: { part in
                    guard part != picked else { return }
                    triggerSomeVibration(type: .soft)
                    picked = part
                }
                    .frame(width: ringSide, height: ringSide)
                    .animation(.smooth(duration: CircleMotion.quick), value: model?.week)
                    .animation(.smooth(duration: 0.2), value: picked)
                centre
            }
            .padding(.top, tight ? 2 : 6)
            // On the page: the ring's centre is what the page lines up with the Salah circle's (JourneyPage.ringPage).
            .alignmentGuide(.journeyRing) { $0[VerticalAlignment.center] }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midY } action: { ringMidY = $0 }
            .journeyFlightWords(.card)
            dots
                .padding(.top, tight ? 4 : 8)
                // Bare: how far the days' bottom is under the ring's centre — Journey's rows come up to just under it.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: { daysMaxY = $0 }
                .journeyFlightWords(.card)
            // One line: what keeps the week strong, or that it can't be now (owner, 2026-10-21: "you have to also account for
            // the messaging for when they miss their strong week"). Three lines' room always (the mid-week line's), centred:
            // nothing moves when it changes.
            Group {
                if let door = makeUpDoor {
                    // The not-marked pill picked with prayers to make up: what to fill in (if any) over the way to make up,
                    // the day page's grey capsule (DayMakeUpPill) in ink — Journey has no sage.
                    VStack(spacing: 6) {
                        if let fill = door.fill {
                            Text(fill).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Button {
                            triggerSomeVibration(type: .light)
                            onMakeUp()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Make up \(door.count)")
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                            }
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Make up \(door.count). Opens To make up on this week.")
                    }
                } else {
                    Text(lineNow ?? " ")
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.85)
                }
            }
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(height: 60)
                .padding(.horizontal, 6)
                .padding(.top, tight ? 8 : 12)
                .contentTransition(.opacity)
                .animation(.smooth(duration: CircleMotion.quick), value: lineNow)
                .opacity(quiet ? 0 : 1)
                .journeyFlightWords(.card)
            if bare, let goal {
                // The goal, a pill you can tap to change it (owner, 2026-10-23: "the year goal thing should be like an
                // indicator somewhere that allows us to, you know, tweak the goal instead of being like a list item") —
                // where the Zikr page's "Pick a zikr" sits.
                Button {
                    triggerSomeVibration(type: .light)
                    onGoal()
                } label: {
                    HStack(spacing: 4) {
                        Text("Aiming for \(goal.stepLabel)")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    }
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your goal: \(goal.title). Change it.")
                .padding(.top, 4)
                .opacity(quiet ? 0 : 1)
                .allowsHitTesting(!quiet)
                .journeyFlightWords(.card)
            }
            ZStack(alignment: .top) {
                Group { if bare { lastWeek } else { banked } }.opacity(asking.isEmpty ? 1 : 0)
                if !asking.isEmpty { noRecordQuestion(asking).transition(.opacity) }
            }
            .opacity(quiet ? 0 : 1)
            .allowsHitTesting(!quiet)
            .animation(.smooth(duration: CircleMotion.quick), value: asking)
            .padding(.top, tight ? 6 : 10)
            .journeyFlightWords(.card)
        }
        .padding(.top, bare ? 0 : (tight ? 14 : 18)).padding(.horizontal, 18).padding(.bottom, tight ? 8 : 10)
        .coordinateSpace(name: Self.space)
        .onChange(of: daysMaxY - ringMidY) { _, below in
            if bare, below > 0, abs(JourneyRowsLayout.shared.daysBelowRing - below) > 0.5 { JourneyRowsLayout.shared.daysBelowRing = below }
        }
        .overlay(alignment: .topTrailing) {
            if !bare {
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
        }
        .background {
            if !bare { NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)).journeyFlightCardSurface() }
        }
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

    private var excusedNow: Bool { model?.excusedNow ?? false }
    /// The days the no-record question asks about, unless Excused Mode is on.
    private var asking: [Date] { excusedNow ? [] : noRecord }

    /// The not-marked pill picked while this week has missed prayers: the way to make them up, with the days to fill in
    /// (they aren't on To make up — no rows) said over it.
    private var makeUpDoor: (count: Int, fill: String?)? {
        guard picked == .notMarked, let m = model, !m.excusedNow, !m.owed.isEmpty else { return nil }
        let days = m.week.days.filter(\.noRecord).map(\.date)
        return (m.owed.count, days.isEmpty ? nil : "\(Self.dayList(days)): fill \(days.count == 1 ? "it" : "them") in")
    }

    /// The line under the days: a picked part's own (when it has one), else the week's. While Excused Mode is on, the week's
    /// (a part's line would ask to make up or fill in).
    private var lineNow: String? {
        guard let m = model else { return nil }
        if let p = picked, !m.excusedNow {
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
                : steps.count == 1 ? steps[0] + " for a strong week"
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
    /// any still unmarked hollow (fainter for a day still wholly to come) (owner, 2026-10-21: "switch to hollow gray for unmarked and filled light gray for marked
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
                            // Today: a dot under its letter, the calendar's way (owner, 2026-10-22: "put a white dot under
                            // the Letter indicating today"; white in dark, ink in light). An overlay: nothing moves.
                            .overlay(alignment: .bottom) {
                                if i == model?.todayIndex {
                                    Circle().fill(Color.primary).frame(width: 4, height: 4).offset(y: 7)
                                }
                            }
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
        } else if let states = day?.states, states.allSatisfy({ $0 == .toCome || $0 == .excused }) {
            // A day still to come: fainter than today or a day with a miss, which are both hollow too (Fable's critique:
            // today with three missed looked like Thursday to Saturday).
            Circle().strokeBorder(Self.edge.opacity(0.4), lineWidth: 1)
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
    /// - something owed: what to make up, for a strong week (days with no record are the question's) ("keep" read as already strong at 0 —
    ///   Fable's critique, row 5);
    /// - already enough: "A strong week, so far";
    /// - else the rule: "Don't miss a prayer, and keep 32 at your goal: that's a strong week" (Sunday: "A new week. "
    ///   first; on Prayed only "Don't miss a prayer").
    static func line(_ m: Model) -> String {
        let w = m.week
        // Owner, 2026-10-21, A (over "Excused prayers are left out" and no line): it asked "Fill in Sunday…" while excused.
        if m.excusedNow { return "Excused Mode is on. Your week picks up when it ends." }
        guard w.asked > 0 else { return "Excused prayers are left out" }
        let target = max(w.asked - slack(w), 0)
        if !w.stillPossible {
            return PrayerMetrics.midweekLine(w) ?? "This one won't be a strong week. A new one starts Sunday."
        }
        // Made up, a missed prayer is below the goal (above Prayed): when that takes all the spare, every other prayer has
        // to meet it — say so (Fable's critique, row 6; owner, 2026-10-21: "do 6"). Then "missed" alone keeps it to 3 lines.
        let noSpare = !m.owed.isEmpty && slack(w) > 0 && w.belowStep + w.notMarked >= slack(w)
        let make = m.owed.first.map { first in
            m.owed.count == 1 ? "make up \(possessive(first.day)) \(first.name)"
                : "make up \(m.owed.count) missed" + (noSpare ? "" : " prayers")
        }
        // Only the make-up ask: days with no record are the question's (one place each — Fable's item 7, A), and after its
        // Not now nothing asks about them that week; their dotted dots still open the fill-in.
        let ask = make ?? ""
        let then = noSpare ? ", then pray the rest \(w.goal.countWords)" : ""
        if !ask.isEmpty { return ask.prefix(1).uppercased() + ask.dropFirst() + then + " for a strong week" }
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

    /// The day to ask about, if any: NoRecordDays.next, but it steps aside after it's been shown on 3 visits to Journey without
    /// an answer (owner, 2026-10-20: "Let the no-record question step aside after 3 opens"), and stays quiet until a newer day
    /// has no record (that one gets its own 3). The day can still be filled from its dotted dot. Counted once per visit.
    private func question() -> [Date] {
        // This week's days (the card is this week's); on a Sunday, yesterday's too, so Saturday still gets its ask — not
        // "Fri, Sun, Mon, Tue" reaching into a banked week.
        let all = NoRecordDays.all(in: context)
        let today = PrayerDay.start()
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let days = all.filter { $0 >= weekStart || Calendar.current.isDate($0, inSameDayAs: yesterday) }
        guard let day = days.first else { return [] }
        let d = UserDefaults.standard
        let key = PrayerNotificationID.dayKey(day)
        if let quiet = d.string(forKey: Self.quietKey), key <= quiet { return [] }   // "YYYY-MM-DD" keys sort by date
        var shown = d.integer(forKey: Self.shownKey + key)
        if !visitCounted {
            visitCounted = true
            shown += 1
            d.set(shown, forKey: Self.shownKey + key)
        }
        if shown > Self.visits {
            d.set(key, forKey: Self.quietKey)
            return []
        }
        return days.reversed()   // oldest first, as the question names them
    }
    private static let visits = 3
    private static let shownKey = "noRecord.shown."
    private static let quietKey = "noRecord.quietThrough"

    /// The week's days with no record, asked once (plan-v3 §3: a day with nothing logged is no record, never missed), in the
    /// banked weeks' place: a well pressed into the card holding the dotted days, "Sun – Tue have no record", "Did you pray?",
    /// Not now and a Fill in pill (owner, 2026-10-21, 3 of the asking pictures: the old two text lines had "no visual
    /// hierarchy and it doesn't even look like anything calling the user"). Fill in opens the newest day's five (then the next
    /// asks); Not now quiets them all for the week (Fable's item 7, A — it walked back a day per tap). Its own height, inside
    /// the banked rows' slot, so nothing moves.
    private func noRecordQuestion(_ days: [Date]) -> some View {
        VStack(alignment: .leading, spacing: tight ? 6 : 8) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(0..<min(days.count, 3), id: \.self) { _ in
                        Circle().inset(by: 0.7).stroke(Self.edge, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 3.2]))
                            .frame(width: 12, height: 12)
                    }
                }
                Text(Self.noRecordTitle(days))
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 14) {
                Text("Did you pray?")
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    NoRecordDays.dismiss(days)
                    withAnimation(.smooth(duration: CircleMotion.quick)) { noRecord = question() }
                } label: {
                    Text("Not now").font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .frame(minHeight: 30).contentShape(Rectangle())
                }
                Button {
                    triggerSomeVibration(type: .light)
                    if let newest = days.last { filling = FillDay(day: newest) }
                } label: {
                    // The day page's grey capsule (DayMakeUpPill), in ink: Journey has no sage.
                    HStack(spacing: 4) {
                        Text("Fill in")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                    }
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .contentShape(Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: tight ? 66 : 74)
        .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .accessibilityElement(children: .contain)
    }

    /// "Yesterday has no record", "Mon and Tue have no record", "Sun – Tue have no record" (three or more in a row).
    private static func noRecordTitle(_ days: [Date]) -> String {
        guard days.count > 1 else { return "\(days.first.map { NoRecordDays.name(of: $0) } ?? "") has no record" }
        let cal = Calendar.current
        let names = days.map { $0.formatted(.dateTime.weekday(.abbreviated)) }
        let inRow = zip(days, days.dropFirst()).allSatisfy { cal.dateComponents([.day], from: $0, to: $1).day == 1 }
        let list = days.count >= 3 && inRow ? "\(names[0]) – \(names[names.count - 1])"
            : days.count == 2 ? "\(names[0]) and \(names[1])" : names.joined(separator: ", ")
        return "\(list) have no record"
    }

    /// The last two finished weeks, newest first: past tense, quiet, "strong" only when it was (canvas row B, Sunday).
    /// Bare: the last finished week as one quiet line, the way into Your weeks (the card's ↗ was).
    private var lastWeek: some View {
        Button {
            triggerSomeVibration(type: .light)
            onExpand(JourneyLog.monthStart(PrayerDay.start()))
        } label: {
            HStack(spacing: 4) {
                if let w = model?.banked.first {
                    Text("Last week · \(bankedWords(w))")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                } else {
                    Text(model == nil ? " " : "Your weeks")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                }
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open your weeks")
        // The question's room (it takes this slot): no layout shift when it comes.
        .frame(maxWidth: .infinity, minHeight: (tight ? 34 : 38) * 2, alignment: .top)
    }

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

    /// "This week · Oct 18 – 24", and from one strong week in a row, "· 3 strong weeks in a row" (Fable's critique, row 9;
    /// owner, 2026-10-21: "do item 9") — Journey, the home of your history, shows the streak the Salah bar counts. Nothing at 0.
    private var rangeLabel: String {
        guard let m = model else { return "This week" }
        let streak = m.streak == 0 ? "" : m.streak == 1 ? " · 1 strong week in a row" : " · \(m.streak) strong weeks in a row"
        return "This week · \(Self.range(m.week.start))" + streak
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
        let mine = readToken, log = log, excused = Excused.Days(), now = Date(), on = Excused.isActive
        Task.detached(priority: .userInitiated) {
            var next = Self.model(log: log, excused: excused, now: now)
            next.excusedNow = on
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
                     owed: owed, fillable: fillable, streak: PrayerMetrics.strongRun(in: all).current)
    }
}
