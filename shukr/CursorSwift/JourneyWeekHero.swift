//
//  JourneyWeekHero.swift
//  shukr
//
//  Journey's hero as the prayer-metrics rethink has it (build plan phase 5, board/scoring-rethink/build-plan.md; Zoe's v3.4
//  demo, https://claude.ai/artifact/QDykE7fDLe5r3MBPXY21e6). The owner's pick, 2026-10-20 ("yeah do it", on Zoe's B · A · A):
//  the card is this week — a ring of 35 arcs, Sunday → Saturday — with "12 done" early in the week and "4 left for a strong
//  week" late in it, your usual week under it, the finished weeks banked below; the 16-week calendar is one tap down, behind
//  the card's ↗ (the same zoom it always had). Every count reads PrayerMetrics (Fable's data layer): no screen decides a
//  week on its own. Behind `MetricsLook.on` until he OKs the look.
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

extension PrayerState {
    /// A state's colour on a ring, through the one grade palette (PrayerScoring.color — phase 2 turns Closing to #C93B10
    /// there, so every ring follows). nil: not drawn in a colour (to come, not marked, excused).
    var ringColor: Color? {
        switch self {
        case .opening: PrayerScoring.color(for: 1)
        case .middle: PrayerScoring.color(for: 0.9)
        case .closing: PrayerScoring.color(for: 0.7)
        case .inTimeNoClock: MarkKind.inTimeColor
        case .madeUp: PrayerScoring.color(for: 0.4)
        default: nil
        }
    }
}

/// A week as 35 arcs, Sunday at the top, clockwise, a day's five together; the days' initials around it. Each prayer in its
/// state: prayed in its colour, not marked a faint track, to come dashed, excused frosted; a day with no record dotted.
struct JourneyWeekRing: View {
    let days: [PrayerMetrics.Day]
    /// Today's index in the week (its initial in ink), nil for a finished week.
    var today: Int?
    var lineWidth: CGFloat = 14
    var labels = true
    /// A picked prayer (day, prayer): it stays, a little wider; the rest step back.
    var picked: (day: Int, prayer: Int)? = nil
    @Environment(\.colorScheme) private var scheme

    /// Where a point (in the ring's own frame of `side`) falls: the day and prayer under it, nil off the band.
    static func hit(_ p: CGPoint, side: CGFloat, lineWidth: CGFloat, labels: Bool = true) -> (day: Int, prayer: Int)? {
        let r = side / 2 - lineWidth / 2 - (labels ? 16 : 0)
        let dx = p.x - side / 2, dy = p.y - side / 2
        guard abs(hypot(dx, dy) - r) <= lineWidth / 2 + 12 else { return nil }
        var turn = atan2(dx, -dy) / (2 * .pi) * 360   // 0 at the top, clockwise
        if turn < 0 { turn += 360 }
        let dayArc = 360.0 / 7, dayGap = 6.0, span = (dayArc - dayGap) / 5
        let day = min(Int(turn / dayArc), 6)
        let within = turn - Double(day) * dayArc - dayGap / 2
        return (day, min(max(Int(within / span), 0), 4))
    }

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let room: CGFloat = labels ? 16 : 0
            let r = side / 2 - lineWidth / 2 - room
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let dayArc = 360.0 / 7, dayGap = 6.0, prayerGap = 1.6
            let span = (dayArc - dayGap) / 5
            let ink = scheme == .dark ? Color.white : Color.black
            for (i, day) in days.enumerated() {
                for j in 0..<5 {
                    let a0 = Double(i) * dayArc + dayGap / 2 + Double(j) * span + prayerGap / 2 - 90
                    let a1 = a0 + span - prayerGap
                    var p = Path()
                    p.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
                    guard let states = day.states else {
                        // No record: dotted, faint (unknown, never "missed").
                        var ctx = ctx
                        if let pk = picked, !(pk.day == i && pk.prayer == j) { ctx.opacity = 0.3 }
                        ctx.stroke(p, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: lineWidth * 0.42, lineCap: .round, dash: [0.1, 6]))
                        continue
                    }
                    let s = states[j]
                    let isPicked = picked.map { $0.day == i && $0.prayer == j } ?? false
                    var ctx = ctx
                    if picked != nil && !isPicked { ctx.opacity = 0.3 }
                    let width = isPicked ? lineWidth * 1.35 : lineWidth
                    if let color = s.ringColor {
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                    } else if isPicked {
                        ctx.stroke(p, with: .color(ink.opacity(0.4)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                    } else {
                        switch s {
                        case .toCome:   // a calm track (dashes read as ticks at this size — Zoe's sim check)
                            ctx.stroke(p, with: .color(ink.opacity(0.07)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        case .excused:
                            ctx.stroke(p, with: .color(Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.38)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        default:   // not marked: owed, so it shows a little more than what's to come
                            ctx.stroke(p, with: .color(ink.opacity(0.17)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        }
                    }
                }
                if labels {
                    let mid = (Double(i) * dayArc + dayArc / 2 - 90) * .pi / 180
                    let lr = r + lineWidth / 2 + 9
                    let initial = Calendar.current.veryShortStandaloneWeekdaySymbols[(Calendar.current.firstWeekday - 1 + i) % 7]
                    let text = ctx.resolve(Text(initial).font(.system(size: 10.5, weight: i == today ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(i == today ? ink.opacity(0.85) : ink.opacity(0.35)))
                    ctx.draw(text, at: CGPoint(x: c.x + lr * cos(mid), y: c.y + lr * sin(mid)), anchor: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Journey's card as this week (MetricsLook): the ring, its count, your usual week, the last finished weeks banked.
struct JourneyWeekCard: View {
    let log: JourneyLog
    var compact = false
    var tight = false
    /// The ↗: the calendar (JourneyExpanded.swift), as the old card's was.
    var onExpand: (Date) -> Void = { _ in }
    /// A picked prayer tapped again: its day's page (only for a day that opens).
    var onDay: (Date) -> Void = { _ in }
    var opens: (Date) -> Bool = { _ in false }
    /// A prayer tapped on the ring (owner, 2026-10-20: "journey hero should allow clicking on to the individual prayer in
    /// the ring"): it shows in the middle; again, its day.
    @State private var picked: (day: Int, prayer: Int)?
    /// The most recent day with no record to ask about (NoRecordDays.next — Frank's flow), and the day the Pick sheet is
    /// open for. The question sits in the banked weeks' slot: the card never changes height for it.
    @State private var noRecord: Date?
    @State private var filling: FillDay?
    struct FillDay: Identifiable { let day: Date; var id: Date { day } }
    @Environment(\.modelContext) private var context
    @Environment(PrayerViewModel.self) private var viewModel

    /// What the card shows, read when the log changes (never per frame).
    struct Model: Equatable {
        let week: PrayerMetrics.Week
        let banked: [PrayerMetrics.Week]
        let usual: Int?
        let todayIndex: Int
    }
    @State private var model: Model?
    /// The latest read (an older one landing after it is dropped).
    @State private var readToken = 0
    /// The ring's place on screen (global), for the calendar's flight.
    @State private var ringFrame: CGRect = .zero

    var body: some View {
        let ringSide: CGFloat = compact ? 196 : (tight ? 216 : 232)
        VStack(spacing: 0) {
            HStack {
                Text(rangeLabel)
                Spacer()
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .journeyFlightWords(.card)
            ZStack {
                JourneyWeekRing(days: model?.week.days ?? Self.placeholder, today: model?.todayIndex, lineWidth: compact ? 12 : 14,
                                picked: picked)
                    .frame(width: ringSide, height: ringSide)
                    .contentShape(Circle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        tapped(JourneyWeekRing.hit(tap.location, side: ringSide, lineWidth: compact ? 12 : 14))
                    })
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ringFrame = $0; reportFlight() }
                    .animation(.smooth(duration: CircleMotion.quick), value: model?.week)
                centre.allowsHitTesting(false)   // a tap in the middle reaches the ring's (it lets a pick go)
            }
            .padding(.top, tight ? 2 : 6)
            .journeyFlightWords(.card)
            // Your usual week, never last week (plan-v3 §9.4: Strava's weekly card made normal weeks feel bad). Its slot is
            // kept before there are 3 weeks to judge by, so nothing moves when it arrives.
            Text(model?.usual.map { "Your usual week: \($0)" } ?? " ")
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, tight ? 4 : 8)
                .journeyFlightWords(.card)
            ZStack(alignment: .top) {
                banked.opacity(noRecord == nil ? 1 : 0)
                if let day = noRecord { noRecordQuestion(day).transition(.opacity) }
            }
            .animation(.smooth(duration: CircleMotion.quick), value: noRecord)
            .padding(.top, tight ? 8 : 12)
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
        .task(id: log.version) { read(); noRecord = NoRecordDays.next(in: context) }
        .sheet(item: $filling) { f in
            NoRecordPickSheet(day: f.day) { chosen in
                NoRecordDays.fill(f.day, picked: chosen, viewModel: viewModel)
                noRecord = NoRecordDays.next(in: context)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in read() }
        .accessibilityElement(children: .contain)
    }

    /// The week's words (Koo & Fishbach, plan-v3 §9.2): what's done Sunday–Wednesday, what's left Thursday on.
    /// A tap on the ring: an arc picks its prayer (the same one again opens its day); the middle lets it go.
    private func tapped(_ hit: (day: Int, prayer: Int)?) {
        guard let hit, model != nil else {
            if picked != nil { withAnimation(.smooth(duration: CircleMotion.quick)) { picked = nil } }
            return
        }
        // A day with no record only toggles (its day page has little to show; the no-record card is where it's filled in —
        // Frank's check: the hint and the tap agree).
        if let p = picked, p.day == hit.day, p.prayer == hit.prayer, let day = model?.week.days[hit.day], fillable(day) {
            // A dotted day picked again: fill it in, as the question's "Pick which" does.
            triggerSomeVibration(type: .light)
            filling = FillDay(day: day.date)
            return
        }
        if let p = picked, p.day == hit.day, p.prayer == hit.prayer, let day = model?.week.days[hit.day],
           day.states != nil, opens(day.date) {
            let date = day.date
            triggerSomeVibration(type: .light)
            onDay(date)
            return
        }
        triggerSomeVibration(type: .soft)
        withAnimation(.smooth(duration: CircleMotion.quick)) {
            picked = (picked?.day == hit.day && picked?.prayer == hit.prayer) ? nil : hit
        }
    }

    /// A dotted day that can be filled in: before today and on or after the first mark ever (Frank's check: a new user's
    /// days before the app have no rows either — never invite filling those; NoRecordDays.next starts there too).
    private func fillable(_ day: PrayerMetrics.Day) -> Bool {
        day.states == nil && day.date < PrayerDay.start() && (log.firstDay.map { day.date >= $0 } ?? false)
    }

    /// The picked prayer's words: "Asr" over "Tue · Middle · 4:52 PM".
    private func pickedWords(_ m: Model, _ p: (day: Int, prayer: Int)) -> (title: String, line: String, opens: Bool, fills: Bool) {
        let day = m.week.days[p.day]
        let name = JourneyLog.names[p.prayer]
        let weekday = day.date.formatted(.dateTime.weekday(.abbreviated))
        let state: String
        switch day.states?[p.prayer] {
        case .none: state = "no record"
        case .some(.opening): state = "Opening"
        case .some(.middle): state = "Middle"
        case .some(.closing): state = "Closing"
        case .some(.madeUp): state = "made up"
        case .some(.notMarked): state = "not marked"
        case .some(.excused): state = "excused"
        case .some(.toCome): state = "to come"
        case .some: state = "in its time"
        }
        let at = log.day(day.date).slots[p.prayer]?.markedAt
        let time = at.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return (name, "\(weekday) · \(state)\(time)", opens(day.date) && day.states != nil, fillable(day))
    }

    @ViewBuilder private var centre: some View {
        if let m = model, let p = picked {
            let w = pickedWords(m, p)
            VStack(spacing: 2) {
                Text(w.title)
                    .font(.system(size: compact ? 34 : 40, weight: .thin, design: .rounded))
                Text(w.line)
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(w.opens ? "Tap it again for the day" : w.fills ? "Tap it again to fill it in" : " ")
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: (compact ? 196 : 232) * 0.66)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else if let m = model {
            let w = m.week
            let late = m.todayIndex >= 4
            // A day with no record can still be filled in this week ("Pick which"), so only what's below the bar or owed
            // decides it (Fable's check, 2026-10-20); a finished week's `strong` already asks for no gaps.
            let canBeStrong = w.madeUp + w.notMarked <= PrayerMetrics.strongWeekSlack
            let (number, words): (String, String) =
                w.asked == 0 ? ("–", "excused this week")   // nothing asked (Excused Mode, or before a fresh start)
                : w.left == 0 ? ("\(w.inTime) of \(w.asked)", w.madeUp == 0 && w.inTime == w.asked ? "a complete week" : "in their time")
                : late ? ("\(w.left) left", canBeStrong ? "for a strong week" : "this week")
                : ("\(w.done) done", "this week")
            VStack(spacing: 2) {
                Text(number)
                    .font(.system(size: compact ? 40 : 46, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(words)
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .animation(.smooth(duration: CircleMotion.quick), value: number)
            .frame(maxWidth: (compact ? 196 : 232) * 0.62)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("This week: \(number), \(words)")
        }
    }

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
                    withAnimation(.smooth(duration: CircleMotion.quick)) { noRecord = NoRecordDays.next(in: context) }
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

    /// The last two finished weeks, newest first: past tense, quiet, a ✓ only when it was strong or complete.
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
                    Text("Week of \(w.start.formatted(.dateTime.month(.abbreviated).day()))")
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
        let count = "\(w.inTime) of \(w.asked)"
        if w.complete { return "\(count) · complete week ✓" }
        if w.strong { return "\(count) · strong ✓" }
        return count
    }

    private var rangeLabel: String {
        guard let w = model?.week, let end = Calendar.current.date(byAdding: .day, value: 6, to: w.start) else { return "THIS WEEK" }
        let a = w.start.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = Calendar.current.isDate(w.start, equalTo: end, toGranularity: .month)
        let b = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "THIS WEEK · \(a) – \(b)".uppercased()
    }

    /// This week's days as the calendar's flight takes them (JourneyFlightGeometry.ringTiles): a small square on each day's
    /// arc, the flight's "tile", flying to the day's ring in the calendar and back. Its weeks: just this one.
    private func reportFlight() {
        guard let w = model?.week, ringFrame.width > 0 else { return }
        let g = JourneyFlightGeometry.shared
        let lw: CGFloat = compact ? 12 : 14
        let r = ringFrame.width / 2 - lw / 2 - 16
        let c = CGPoint(x: ringFrame.midX, y: ringFrame.midY)
        var tiles: [Date: CGRect] = [:]
        for (i, day) in w.days.enumerated() {
            let mid = (Double(i) * 360 / 7 + 180 / 7 - 90) * .pi / 180
            let p = CGPoint(x: c.x + r * cos(mid), y: c.y + r * sin(mid))
            tiles[Calendar.current.startOfDay(for: day.date)] = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
        }
        g.ringTiles = tiles
        g.grid = ringFrame
        g.weekStarts = [w.start]
    }

    private static let placeholder: [PrayerMetrics.Day] = (0..<7).map {
        PrayerMetrics.Day(key: "\($0)", date: .distantPast, states: Array(repeating: .toCome, count: 5))
    }

    /// Every week since day one (~100 for him) is walked for the banked rows and the usual week: off the main thread, as
    /// JourneyStore reads the log (Fable's check: Journey's open was a 71–80 ms trace already). The ring shows its empty
    /// track until it lands, the same size, so nothing moves.
    private func read() {
        readToken += 1
        let mine = readToken, log = log, excused = Excused.Days(), now = Date()
        Task.detached(priority: .userInitiated) {
            let next = Self.model(log: log, excused: excused, now: now)
            await MainActor.run {
                guard mine == readToken else { return }
                if next != model {
                    if next.week.start != model?.week.start { picked = nil }
                    model = next; reportFlight()
                }
            }
        }
    }

    nonisolated private static func model(log: JourneyLog, excused: Excused.Days, now: Date) -> Model {
        let all = PrayerMetrics.weeks(in: log, excused: excused, now: now)
        let week = all.last(where: \.isCurrent) ?? PrayerMetrics.week(containing: now, in: log, excused: excused, now: now)
        let finished = all.filter { !$0.isCurrent }
        let today = Calendar.current.dateComponents([.day], from: week.start, to: PrayerDay.start(for: now)).day ?? 0
        return Model(week: week, banked: Array(finished.suffix(2).reversed()),
                     usual: PrayerMetrics.usualWeek(in: log, excused: excused, now: now), todayIndex: min(max(today, 0), 6))
    }
}
