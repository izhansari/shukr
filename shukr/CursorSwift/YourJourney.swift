//
//  YourJourney.swift
//  shukr
//
//  Journey's first screen (Journey v6, owner 2026-10-16) and its pieces: Your journey's card, the three rows, the months,
//  the milestones and their celebration. Rules in board/mocks/journey/spec.md (Data rules, Milestones): active days only,
//  rates only over days shukr was used, a break of 7+ days folds into one "Away" line, excused prayers are never missed.
//

import SwiftUI
import SwiftData

/// Journey's first screen (Journey v6, owner 2026-10-16: "yeah this is it … this is gonna tie the knot on this page";
/// board/mocks/journey-v6): Your journey's card leads, then Prayer scores · To make up · Moments as three flat rows, the
/// months (a break folded into one "Away" line) and the milestones. Every piece is one we had, in a gentler order.

/// The card (Journey on one screen, D's card — owner, 2026-10-16, board/mocks/journey-v6/build-plan.md "A"): days you
/// marked a prayer; the grid a week a row (seven rounded bars, the card's colors), today's week at the bottom, scrolling up
/// to the first day with a fade at its top; month names (grey; no sage on Journey — owner, 2026-10-17) beside the week holding the 1st open that month; the
/// label says what's in view ("THE LAST 18 WEEKS", or the months once scrolled back). A tile's tap puts its day in the
/// three numbers' place; again, the numbers. Before the first mark: "0 days so far" and the line that says what will fill it.
struct JourneyHomeCard: View {
    let stats: YourJourneyStats
    /// The days themselves (the picked day's ring draws from it).
    var log = JourneyLog()
    /// A small phone: the number at 42 pt (the canvas's SE).
    var compact = false
    /// A little less room around its parts, so five rows fit under 12 weeks on a 6.3" phone.
    var tight = false
    var onDay: (Date) -> Void = { _ in }
    var opens: (Date) -> Bool = { _ in false }
    var onMonth: (Date) -> Void = { _ in }
    /// The ↗: the card expands (JourneyExpanded.swift) on the weeks it shows, no month in focus.
    var onExpand: (Date) -> Void = { _ in }
    /// One of the picked day's things tapped at the bottom (Journey opens it as the day page's back card does).
    var onExtra: (JourneyExtraTap) -> Void = { _ in }
    @State private var picked: Date?
    /// "best streak" tapped: its days lit, the grid at them (owner, 2026-10-17: "clicking this takes us to the area that
    /// shows those days with best streak") — the month's way with its numbers. Again, or a tile, lets it go.
    @State private var streakShown = false
    /// The grid's place (today's week at the bottom to start; `toToday`).
    @State private var position = ScrollPosition(edge: .bottom)
    /// A month scrub under way: the month it started from and the one it's at (indexes into `monthWeeks`).
    /// The month rail under way: the month the finger's on (an index into `monthWeeks`).
    @State private var rail: Int?
    /// Where the grid was when the streak lit (its top row; nil: resting at today), and whether to go back there.
    @State private var beforeStreak: (week: Date?, back: Bool) = (nil, false)
    /// A finger on the tiles (not observed: nothing redraws from it).
    @State private var scrub = JourneyCardScrub()
    /// What the grid shows: the first week row in view, how many fit, and whether it rests at today.
    @State private var view = (first: 0, count: 12, atEnd: true)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.journeyDayOpener) private var dayOpener

    /// A week row's pitch: an 11 pt bar and 3 pt between (the canvas).
    static let pitch: CGFloat = 14
    /// Room inside the grid's clip for a picked tile's ring.
    static let ringRoom: CGFloat = 4
    /// A bar's corner (owner, 2026-10-17: "decrease the corner rounding a little bit, like very little"; was 5).
    static let corner: CGFloat = 4
    /// The month names' column, wide enough for "May’26" (it ran into the first tile at 34).
    static let nameColumn: CGFloat = 40
    /// How long a finger rests on the tiles before moving it picks them (a tap is shorter; a drag before it scrolls).
    static let holdTime = 0.3
    private static let end = "journeyCardEnd"
    /// The grid's least height: 12 weeks and its top room.
    static let minGrid: CGFloat = 12 * pitch + 12

    var body: some View {
        let _ = JourneyPerf.body("card")
        let empty = stats.activeDays == 0
        let shown = picked.flatMap { stats.day(on: $0) }
        VStack(alignment: .leading, spacing: 0) {
            // A picked day takes the top (owner, 2026-10-17: "all the stuff that's in the bottom can move to the top"): its
            // ring with the score, the date, which day of the journey and its rank, its kind. The count stays underneath,
            // unseen, so the card never changes height.
            ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(stats.activeDays)").font(.system(size: compact ? 42 : 54, weight: .thin, design: .rounded))
                    .foregroundStyle(empty ? .secondary : .primary)
                Text(empty ? "days so far" : stats.activeDays == 1 ? "day you marked a prayer" : "days you marked a prayer")
                    .font(.system(size: compact ? 15 : 17, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.trailing, empty ? 0 : 28)   // room for the expand button
            .opacity(shown == nil ? 1 : 0)
                if let d = shown { dayTop(d).transition(.opacity) }
            }
            .journeyFlightWords(.card)   // the transitions: fades as a month opens (JourneyTransitions.swift)
            HStack {
                Text(rangeLabel)
                Spacer()
                // Where you stand now, in place of "a week a row" (owner, 2026-10-17: "that's kind of dead. Waste of space";
                // his pick of the ideas: the current streak — the card's best streak never said it).
                Text(stats.currentStreak > 0 ? "\(stats.currentStreak)-day streak" : "Start a streak today")
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .padding(.top, tight ? 12 : 18)
            .journeyFlightWords(.card)
            grid.padding(.top, 6)
            foot.journeyFlightWords(.card)
        }
        .padding(.top, tight ? 14 : 18).padding(.horizontal, 18).padding(.bottom, tight ? 10 : 14)
        // The way into the month, plain to see (owner, 2026-10-17: "a button in the top right of the card … diagonal
        // arrows, indicating expand … opens the tiles into the calendar month view"): the picked day's month, else the
        // month at the bottom of the grid's view (the latest with marks at or before it).
        .overlay(alignment: .topTrailing) {
            if !empty {
                Button {
                    guard let m = monthInView else { return }
                    triggerSomeVibration(type: .light)
                    onExpand(m)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, tight ? 6 : 10).padding(.trailing, 8)
                .accessibilityLabel("Open the month")
                .journeyFlightWords(.card)
            }
        }
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)).journeyFlightCardSurface())
        .journeyFlightCard()
    }

    /// The month the expand button opens: the picked day's, else the bottom row in view's — stepping back to one with marks.
    private var monthInView: Date? {
        let cal = Calendar.current
        var date: Date
        if let p = picked { date = p } else {
            guard !stats.weeks.isEmpty else { return nil }
            let i = min(max(view.first + view.count - 1, 0), stats.weeks.count - 1)
            date = min(cal.date(byAdding: .day, value: 6, to: stats.weeks[i].start) ?? stats.weeks[i].start, PrayerDay.start())
        }
        var m = JourneyLog.monthStart(date)
        for _ in 0..<36 {
            if log.month(m).activeDays > 0 { return m }
            guard let earlier = cal.date(byAdding: .month, value: -1, to: m) else { break }
            m = earlier
        }
        return nil
    }

    /// "THE LAST 18 WEEKS" at rest; once scrolled back, the months in view ("JUN – SEP 2026").
    private var rangeLabel: String {
        // Before the log is in (no weeks yet) the card says what it will show, never "THE LAST 1 WEEKS" (Frank's catch).
        if stats.weeks.isEmpty { return "THE LAST 12 WEEKS" }
        if view.atEnd {
            let n = min(view.count, stats.weeks.count)
            return n == 1 ? "THIS WEEK" : "THE LAST \(n) WEEKS"
        }
        let rows = stats.weeks
        let a = rows[min(max(view.first, 0), rows.count - 1)].start
        let lastRow = min(rows.count - 1, view.first + view.count - 1)
        let b = Calendar.current.date(byAdding: .day, value: 6, to: rows[max(lastRow, 0)].start) ?? a
        let cal = Calendar.current
        let from = a.formatted(.dateTime.month(.abbreviated)).uppercased()
            + (cal.component(.year, from: a) != cal.component(.year, from: b) ? " \(cal.component(.year, from: a))" : "")
        return "\(from) – \(b.formatted(.dateTime.month(.abbreviated)).uppercased()) \(cal.component(.year, from: b))"
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ScrollViewReader { proxy in
            LazyVStack(spacing: 3) {
                ForEach(Array(stats.weeks.enumerated()), id: \.element.id) { i, week in row(week, index: i).id(week.id) }
                // The ring's room below the last row, as a row of its own: the grid's true end, to scroll to.
                Color.clear.frame(height: Self.ringRoom - 3).id(Self.end)
            }
            .scrollTargetLayout()   // its rows are what the visibility and the scrub's scrolls go by
            // Journey opens on today's week at the bottom (owner, 2026-10-17: "opening journey page should show card
            // scrolled to bottom instead of how it opens with the furthest date at the top"): defaultScrollAnchor only
            // sets the first layout's offset, and the weeks arrive after it — so the grid stays pinned to today while
            // they do (`scrub.pinned`, the scroll geometry below).
            .onAppear {
                scrub.pinned = true; toToday()
                JourneyFlightGeometry.shared.cardShow = { show($0, pick: $1) }
            }
            .onChange(of: streakShown) { _, on in
                if !on {
                    // Turned off by its own tap: back to where you were (owner, 2026-10-17: "if I deselect it, I want to
                    // scroll back to the initial time period I was looking at"). Not after a scroll or a tile let it go.
                    guard beforeStreak.back else { return }
                    beforeStreak.back = false
                    withAnimation(.easeInOut(duration: 0.45)) {
                        if let w = beforeStreak.week { proxy.scrollTo(w, anchor: .top) }
                        else { proxy.scrollTo(Self.end, anchor: .bottom) }
                    }
                    return
                }
                guard let days = stats.bestStreakDays else { return }
                let mid = days.lowerBound.addingTimeInterval(days.upperBound.timeIntervalSince(days.lowerBound) / 2)
                guard let week = stats.weeks.last(where: { $0.start <= mid }) else { return }
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(week.id, anchor: .center) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { scrub.width = $0 }
            .padding(.top, 12)
            // Room for a picked tile's ring (drawn 3 pt outside its bar) on the right and below: the grid's clip cut it
            // (owner, 2026-10-17). The grid reaches 4 pt into the card's margin, so the bars stay where they were.
            .padding(.trailing, Self.ringRoom)
            }
        }
        .padding(.trailing, -Self.ringRoom)
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize)
        // The month column is a rail, the Zikr wheel's way (owner, 2026-10-17, with a recording of it: "if I hold it and
        // start dragging up, it moves the tile grid up as well. kind of like how it works here with the same kind of
        // API"): a finger held still on it a moment lifts it (a faint track, a pill naming the month), then where the
        // finger is along it is the month — the top your first, the bottom this one, as a scroll bar — a click each,
        // the grid following; let go, it's as it was. Hung on the grid, not a row (a row scrolled far off is let go by
        // the lazy stack, and its gesture with it); the grid's own scroll holds still meanwhile. A tap on a name still
        // opens its month, a quick drag there still scrolls, the tiles are theirs.
        .scrollDisabled(rail != nil)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { v in railChanged(v) }
            .onEnded { _ in railEnded() })
        .sensoryFeedback(.selection, trigger: rail)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrub.gridHeight = $0 }
        .background(alignment: .leading) {
            // The lifted rail: a faint track down the column.
            Capsule().fill(Color.primary.opacity(rail != nil ? 0.07 : 0))
                .frame(width: Self.nameColumn + 10)
                .padding(.leading, -7)
                .scaleEffect(rail != nil ? 1 : 0.96, anchor: .leading)
        }
        // At rest, a slim scroll bar down the column's edge says it can be taken hold of (owner, 2026-10-17: "we should
        // probably show that it's something that you can scroll … It looks very plain and unassuming"; his pick, A): a
        // hairline the rail's length, a thumb where the grid is in the whole history. It gives way to the lifted track.
        .background(alignment: .topLeading) {
            let h = max(scrub.gridHeight - 12, 1), n = max(stats.weeks.count, 1)
            let thumb = max(CGFloat(view.count) / CGFloat(n) * h, 14)
            let top = min(CGFloat(view.first) / CGFloat(n) * h, h - thumb)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(width: 2, height: h)
                Capsule().fill(Color.primary.opacity(0.3)).frame(width: 2, height: thumb).offset(y: max(top, 0))
            }
            .padding(.top, 6)
            .opacity(rail == nil && stats.weeks.count > view.count ? 1 : 0)
            .animation(.easeOut(duration: CircleMotion.quick), value: rail == nil)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let m = rail, monthWeeks.indices.contains(m), let start = stats.weeks.first(where: { $0.id == monthWeeks[m] })?.month?.start {
                let h = max(scrub.gridHeight, 1)
                Text(start.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline).fontDesign(.rounded)
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .fixedSize()
                    .offset(x: Self.nameColumn + 10, y: min(max((CGFloat(m) + 0.5) / CGFloat(monthWeeks.count) * h - 15, 0), h - 30))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        // A finger scrolling the grid lets a picked tile and a lit streak go (owner, 2026-10-17: "if a tile is selected,
        // but we start scrolling, it deselects that tile. Same for if we scroll away while the best streak is selected").
        // Only the finger's scroll: the streak's own scroll to its days is .animating, not .interacting.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { scrub.pinned = false; JourneyPerf.began("card scroll") }   // the finger's now: no more snapping to today
            JourneyPerf.scrolling(phase.isScrolling)
            guard phase == .interacting, picked != nil || streakShown else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil; streakShown = false }
        }
        // Which weeks are in view, as iOS has them — not the offset ÷ a row's pitch: the lazy stack only estimates the rows
        // it hasn't built, so with a long history the label read "SEP 2025 – JAN 2026" over Dec – Mar (sim, 2026-10-17),
        // and the scrub's start, the streak's way back and the expand button's month read the same wrong rows.
        .onScrollTargetVisibilityChange(idType: Date.self, threshold: 0.5) { ids in
            let index = ids.compactMap { id in stats.weeks.firstIndex { $0.id == id } }
            guard let lo = index.min(), let hi = index.max() else { return }
            let atEnd = hi == stats.weeks.count - 1
            if view.first != lo || view.count != hi - lo + 1 || view.atEnd != atEnd { view = (lo, hi - lo + 1, atEnd) }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentSize.height - (geo.contentOffset.y + geo.contentInsets.top) - geo.containerSize.height < 4
        } action: { _, atEnd in
            // Pinned to today and the weeks grew under it (they arrive after the first layout; on a return to Journey into
            // a copy of the page that started empty — logged on the sim, it settled at the first weeks): back to the end.
            if !atEnd, scrub.pinned, picked == nil, !streakShown { toToday() }
        }
        // A fade at the top: there are earlier weeks up there.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
                Color.black
            }
            .padding(.trailing, -Self.ringRoom)   // over the ring's room too
        }
        // 12 weeks is its natural height (what Journey's fit test measures), and it grows into any room that's left.
        .frame(minHeight: Self.minGrid, idealHeight: Self.minGrid, maxHeight: .infinity)
        .journeyFlightGrid(weekStarts: stats.weeks.map(\.start))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your weeks, a week a row")
    }

    /// A week's row (JourneyCardRow): redrawn only when its own days, its picked day, the streak's light or the look change —
    /// a pick, a scroll or the rail used to rebuild every row the lazy stack held (his phone, 2026-10-17: ~3,400 row bodies
    /// in one 3 s rail drag, 29 for one tap — perf #4). Its gestures call back here, where the state is.
    private func row(_ week: YourJourneyStats.Week, index i: Int) -> some View {
        let shownPick = picked.flatMap { p in week.days.contains { $0?.date == p } ? p : nil }
        return JourneyCardRow(week: week, index: i, weeks: stats.weeks.count, logVersion: log.version, picked: shownPick,
                              streakShown: streakShown, streak: stats.bestStreakDays, dark: scheme == .dark,
                              onName: { start in
                                  guard rail == nil, !scrub.railJustEnded else { return }
                                  triggerSomeVibration(type: .light)
                                  onMonth(start)
                              },
                              onTap: { p in
                                  // A tap near the picked tile (its bar and a few points round it) lets it go (owner, 2026-10-17:
                                  // "the intention of deselecting is very hard since user has to tap exactly on that tile").
                                  if let on = picked, let r = rect(of: on, fromRow: i), r.insetBy(dx: -5, dy: -4).contains(p) { tap(on); return }
                                  if let d = stats.weeks.indices.contains(i) ? stats.weeks[i].days[column(p.x)] : nil { tap(d.date) }
                              },
                              onDay: { tap($0) },
                              onHold: { state, p in held(state, p, fromRow: i) })
            .equatable()
    }

    /// The hold-and-drag pick: began — a firm tick, the tile under the finger; changed — each new tile, a soft tick. On the
    /// month column it does nothing (the names are buttons; the column is where a drag always scrolls).
    private func held(_ state: UIGestureRecognizer.State, _ p: CGPoint, fromRow i: Int) {
        switch state {
        case .began:
            JourneyPerf.began("card hold")
            scrub.scrubbing = true
            triggerSomeVibration(type: .medium)
            if let d = day(at: p, fromRow: i) { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = d.date; streakShown = false } }
        case .changed:
            guard scrub.scrubbing, let d = day(at: p, fromRow: i), d.date != picked else { return }
            triggerSomeVibration(type: .soft)
            picked = d.date
        default:
            scrub.scrubbing = false
        }
    }

    private func tap(_ date: Date) {
        JourneyPerf.began("card tap")
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == date ? nil : date; streakShown = false }
    }

    /// The months on the card, oldest first: each one's first week (the row with its name).
    private var monthWeeks: [Date] { stats.weeks.compactMap { $0.month == nil ? nil : $0.id } }
    /// How long a finger rests on the column before it's the rail (a tap, or a drag before it, isn't).
    private static let railHold = 0.22

    private func railChanged(_ v: DragGesture.Value) {
        let r = scrub
        r.railLast = v.location
        if r.railStart == nil {
            r.railStart = v.startLocation
            r.railMoved = false
            // The column only (the tiles have their own hold); and a month to go to.
            r.railOff = v.startLocation.x > Self.nameColumn + 6 || monthWeeks.isEmpty
            guard !r.railOff else { return }
            r.railHoldTask?.cancel()
            r.railHoldTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.railHold))
                guard !Task.isCancelled, r.railStart != nil, !r.railMoved else { return }
                r.pinned = false
                JourneyPerf.began("card rail")
                triggerSomeVibration(type: .medium)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil; streakShown = false }
                railTo(railIndex(r.railLast.y), lifting: true)
            }
            return
        }
        guard !r.railOff else { return }
        guard rail != nil else {
            // Moved before the hold: a scroll, the grid's.
            if hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y) > 10 { r.railMoved = true; r.railHoldTask?.cancel() }
            return
        }
        let m = railIndex(v.location.y)
        if m != rail { railTo(m, lifting: false) }
    }

    private func railEnded() {
        let r = scrub
        r.railHoldTask?.cancel()
        r.railStart = nil
        guard rail != nil else { return }
        // A month name under the finger as it lifts mustn't open its month.
        r.railJustEnded = true
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); r.railJustEnded = false }
        withAnimation(.snappy(duration: CircleMotion.quick)) { rail = nil }
    }

    /// The month at a height on the rail: the grid's height shared out among the months, oldest at the top.
    private func railIndex(_ y: CGFloat) -> Int {
        let n = monthWeeks.count
        let f = min(max(y / max(scrub.gridHeight, 1), 0), 0.999)
        return min(Int(f * CGFloat(n)), n - 1)
    }

    /// The month's first week (the row with its name) comes to the grid's middle — at the top the fade hid the name
    /// (owner, 2026-10-17: "if I go to January 2026, I don't even see it in the column … make it so that the label
    /// comes into the middle").
    private func railTo(_ m: Int, lifting: Bool) {
        let months = monthWeeks
        guard months.indices.contains(m) else { return }
        if lifting { withAnimation(.snappy(duration: CircleMotion.quick)) { rail = m } } else { rail = m }
        withAnimation(CircleMotion.wheelScrub) { position.scrollTo(id: months[m], anchor: .center) }
        // Again once it's landed: a far month's rows weren't built, so the first scroll went by the lazy stack's estimate
        // and stopped a month or so short (sim: the pill said October, the grid's top was November); now they're there.
        let r = scrub
        r.railSettle?.cancel()
        r.railSettle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, rail == m || rail == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(id: months[m], anchor: .center) }
        }
    }

    /// The expanded card's weeks (JourneyFlightGeometry.follow): the grid brought to them at once, under the expanded page,
    /// so the flight back has their tiles to land in — and it stays there after, as your own scroll would leave it (no pick,
    /// no streak, pinned to today only when they reach it). Their middle week (or the picked day's) in the middle; left as
    /// it is (false) when it already shows them all, or — more than it holds, pinched to tiles — that week near its middle.
    private func show(_ weeks: [Date], pick: Date?) -> Bool {
        // The weeks as the grid reports them now — this is called from a closure set at its first appearance, whose copy of
        // `stats` is the empty one from before the log was in.
        let geo = JourneyFlightGeometry.shared, all = geo.weekStarts
        guard let lo = weeks.first, let hi = weeks.last else { return false }
        let week = pick ?? weeks[weeks.count / 2]
        guard let i = all.firstIndex(of: week) else { return false }
        let shown = geo.cardWeeksInView()
        if let a = shown.first, let b = shown.last {
            if lo >= a, hi <= b { return false }
            if weeks.count > shown.count, let m = shown.firstIndex(of: week), abs(m - shown.count / 2) <= 1 { return false }
        }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            picked = nil
            streakShown = false
            beforeStreak = (nil, false)
        }
        // Down to today's week: the grid at rest there, as it opens.
        if hi == all.last || i >= all.count - max(shown.count / 2, 1) {
            scrub.pinned = true
            withTransaction(quiet) { position.scrollTo(edge: .bottom) }
            return true
        }
        scrub.pinned = false
        withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
        // Again a beat later: a far week's rows weren't built, and the lazy stack's estimate lands short (the rail's way).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
        }
        return true
    }

    /// The grid at today's week, at once — not while a tile is picked or the streak is lit.
    private func toToday() {
        guard picked == nil, !streakShown, !stats.weeks.isEmpty else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { position.scrollTo(edge: .bottom) }
    }

    /// A bar's slot across the row's bars (the row's width less the name column; bars 6 pt apart).
    private var slot: CGFloat { (scrub.width - Self.nameColumn - 6 + 6) / 7 }

    /// The bar column under x in a row's bars (past the end bars, the nearest).
    private func column(_ x: CGFloat) -> Int {
        guard scrub.width > 0 else { return 0 }
        return min(max(Int(((x + 3) / slot).rounded(.down)), 0), 6)
    }

    /// The day under a point in row `i`'s bars' space: rows `pitch` apart above and below it (each row's band reaching
    /// halfway to the next), then the column. Past the first or last week, the nearest — a held finger can run wide.
    private func day(at p: CGPoint, fromRow i: Int) -> YourJourneyStats.GridDay? {
        guard !stats.weeks.isEmpty else { return nil }
        let r = min(max(i + Int(((p.y + 1.5) / Self.pitch).rounded(.down)), 0), stats.weeks.count - 1)
        return stats.weeks[r].days[column(p.x)]
    }

    /// A day's bar in row `i`'s bars' space (nil: not on the card).
    private func rect(of date: Date, fromRow i: Int) -> CGRect? {
        guard scrub.width > 0, let r = stats.weeks.lastIndex(where: { $0.start <= date }) else { return nil }
        let col = Calendar.current.dateComponents([.day], from: stats.weeks[r].start, to: date).day ?? 0
        guard (0..<7).contains(col) else { return nil }
        return CGRect(x: CGFloat(col) * slot, y: CGFloat(r - i) * Self.pitch, width: slot - 6, height: 11)
    }

    /// Under the grid: the three numbers, or the picked day's line in their place (the card never grows).
    private var foot: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            ZStack {
                if stats.activeDays == 0 {
                    Text("Every prayer you mark shows up here.")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else if let date = picked, let day = stats.day(on: date) {
                    dayExtras(day).transition(.opacity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        figure("\(stats.prayersMarked)", "prayers marked").opacity(streakShown ? 0.35 : 1)
                        figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days").opacity(streakShown ? 0.35 : 1)
                        Button {
                            guard stats.bestStreakDays != nil else { return }
                            triggerSomeVibration(type: .light)
                            if streakShown {
                                beforeStreak.back = true
                            } else {
                                scrub.pinned = false
                                let top = stats.weeks.indices.contains(view.first) ? stats.weeks[view.first].id : nil
                                beforeStreak = (view.atEnd ? nil : top, false)
                            }
                            withAnimation(.easeInOut(duration: 0.3)) { streakShown.toggle() }
                        } label: {
                            figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days",
                                   streakShown ? streakSpan : "best streak")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows those days")
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: tight ? 40 : 46, alignment: .top)
            .padding(.top, tight ? 10 : 12)
        }
        .padding(.top, tight ? 10 : 12)
    }

    /// The picked day at the top (JourneyDayTop, shared with the month page); a tap opens the day.
    private func dayTop(_ d: YourJourneyStats.GridDay) -> some View {
        JourneyDayTop(day: d, log: log, compact: compact, canOpen: d.prayed > 0 && opens(d.date)) {
            // Its ring grows into the day page (Journey's host); a push without one.
            if let dayOpener { dayOpener.open(d.date) } else { onDay(d.date) }
        }
            .padding(.trailing, 28)   // the expand button's room
    }

    /// The picked day at the bottom (JourneyDayExtrasRow, shared with the month page).
    private func dayExtras(_ d: YourJourneyStats.GridDay) -> some View {
        JourneyDayExtrasRow(date: d.date, onExtra: onExtra)
    }

    /// The best streak's dates: "Sep 3 – 10", "Aug 28 – Sep 4", with the year when it isn't this one.
    private var streakSpan: String {
        guard let r = stats.bestStreakDays else { return "best streak" }
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: r.upperBound) == cal.component(.year, from: Date())
        let sameMonth = cal.isDate(r.lowerBound, equalTo: r.upperBound, toGranularity: .month)
        let a = r.lowerBound.formatted(.dateTime.month(.abbreviated).day())
        let b = sameMonth ? r.upperBound.formatted(.dateTime.day()) : r.upperBound.formatted(.dateTime.month(.abbreviated).day())
        return "\(a) – \(b)" + (thisYear ? "" : ", \(cal.component(.year, from: r.upperBound))")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption)
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

}

/// One week of the card: its month's name (a button into the month), then its seven bars — each the day's tile color by
/// kind and rank, an unmarked day its hairline, the picked one ringed, the others dimmed while the best streak is lit. Equal
/// rows aren't redrawn (perf #4); the gestures are the card's, called back with the point in this row's bars' space.
struct JourneyCardRow: View, Equatable {
    let week: YourJourneyStats.Week
    let index: Int
    /// How many weeks the card has: a row's place among them (its callbacks work from it) changes with it.
    let weeks: Int
    /// The log the card was built from: a new one redraws every row once, so no row's taps work from an old copy of the
    /// card (an equal row keeps the closures it was built with — the helper's check).
    let logVersion: UUID
    /// The picked day, if it's in this week.
    let picked: Date?
    let streakShown: Bool
    let streak: ClosedRange<Date>?
    let dark: Bool
    let onName: (Date) -> Void
    let onTap: (CGPoint) -> Void
    /// A day's accessibility action (the row's gesture takes the finger's taps).
    let onDay: (Date) -> Void
    let onHold: (UIGestureRecognizer.State, CGPoint) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.index == b.index && a.weeks == b.weeks && a.logVersion == b.logVersion && a.picked == b.picked && a.dark == b.dark
            && a.streakShown == b.streakShown && (!a.streakShown || a.streak == b.streak)
            && a.week.start == b.week.start && a.week.days == b.week.days && a.week.month?.label == b.week.month?.label
    }

    var body: some View {
        let _ = JourneyPerf.body("row")
        HStack(spacing: 6) {
            Group {
                if let m = week.month {
                    Button { onName(m.start) } label: {
                        // Never past its column into the first tile ("Jul’26" ran over it — owner, 2026-10-17).
                        Text(m.label).font(.system(size: 12.5, weight: .regular, design: .rounded)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .journeyFlightMonthName(m.start)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(m.start.formatted(.dateTime.month(.wide).year()))")
                } else {
                    Color.clear
                }
            }
            // The names against the tiles (owner: "push the text so that it's right leaning"), the edge the scroll bar's.
            .frame(width: JourneyHomeCard.nameColumn, height: 11, alignment: .trailing)
            HStack(spacing: 6) {
                ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                    bar(day)
                }
            }
            .journeyFlightCardWeek(week.start)   // where its bars are, for the card's flights (JourneyTransitions.swift)
            .contentShape(Rectangle())
            .contentShape(Rectangle().inset(by: -1.5))   // the gaps between rows too
            // Every place is measured from the row the finger landed on, in its own space — never from where the lazy stack
            // says rows are: those reports came only when a row moved within the stack, so on his phone the card often
            // knew none or half the rows on screen ("Sometimes it doesn't do it … puts my finger higher … like I'm hitting
            // a wall" — journey-taps.log, 2026-10-17: rows=0 after opening, 8 of ~14 after a scroll).
            .onTapGesture { p in onTap(p) }
            // A finger resting 0.3 s picks under it as it moves, across rows (owner, 2026-10-17: "if I hold down on a tile,
            // I can move my finger to select other tiles nearby as I drag"; "not just a row … anything"). UIKit's long press:
            // a quick drag moves first, fails it, and the grid scrolls; once begun, the drag is the pick's. Each row has its
            // own and keeps the finger until it lifts — rows on screen are exactly `pitch` apart, so the row under the finger
            // is this one plus its offset.
            .gesture(JourneyHoldPick(hold: JourneyHomeCard.holdTime) { state, p, _ in onHold(state, p) })
        }
    }

    @ViewBuilder private func bar(_ day: YourJourneyStats.GridDay?) -> some View {
        let shape = RoundedRectangle(cornerRadius: JourneyHomeCard.corner, style: .continuous)
        if let day {
            // The card's colors by amount (owner: "make colors of the 12 week grid match your mockup") — one copy, shared
            // with the year's small months (JourneyTileColor, JourneyYear.swift).
            shape.fill(JourneyTileColor.of(day.kind, rank: day.rank, dark: dark))
                .overlay {
                    if day.kind == .none { shape.strokeBorder(JourneyTileColor.outline(dark: dark), lineWidth: JourneyTileColor.outlineWidth) }
                }
                .opacity(streakShown && !(streak?.contains(day.date) ?? false) ? 0.22 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 11)
                .journeyFlightTile(day.date)
                .overlay {
                    if picked == day.date {
                        RoundedRectangle(cornerRadius: JourneyHomeCard.corner + 2.5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                            .padding(-3)
                    }
                }
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onDay(day.date) }
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 11)   // before the first day, or still to come
        }
    }
}

/// The This month row's measure (build-plan "B", canvas v6): touch and hold the row to choose; the choice sticks
/// (`journey.thisMonth`). Owner: "on time or better" is his pick, so it's the default — "Perfect or Middle" since the
/// grades became Perfect · Middle · Closing (2026-10-17); the case keeps its saved name `onTime`.
enum ThisMonthMeasure: String, CaseIterable, Identifiable {
    case inWindow, onTime, perfect, average
    static let key = "journey.thisMonth"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inWindow: "In their window"
        case .onTime: "Perfect or Middle"
        case .perfect: "Perfect"
        case .average: "Average score"
        }
    }
    /// What it counts, in the menu.
    var counts: String {
        switch self {
        case .inWindow: "Perfect, Middle and Closing"
        case .onTime: "Perfect and Middle"
        case .perfect: "Perfect only"
        case .average: "Every prayer by its score; a missed one is 0"
        }
    }
    func value(_ m: YourJourneyStats.ThisMonth) -> String {
        switch self {
        case .inWindow: "\(m.inWindow)%"
        case .onTime: "\(m.onTime)%"
        case .perfect: "\(m.perfect)%"
        case .average: "\(m.average)"
        }
    }
}

/// A picked day's line — the card's, and the year's (owner, 2026-10-16: "when the year is shown, let's make it work the
/// same way that the card works, where tapping a tile shows that day information at the bottom, which we can then open
/// into"). Two lines (owner, 2026-10-17: "we have enough space to use the two lines"): the date, then its kind and the day
/// page's score; on the right the day's ring as the month draws it — the door to
/// its day page ("instead of the open button … the representation of that same tile when it's on the calendar in the
/// month view. then clicking that circle takes us to that day view"). A plain push for now; a flight later (open item).
struct JourneyDayLine: View {
    let day: YourJourneyStats.GridDay
    let log: JourneyLog
    let canOpen: Bool
    let onOpen: () -> Void
    /// The ring's size here (the month's is 46).
    static let ring: CGFloat = 36

    var body: some View {
        let date = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        // The kind in his words (owner, 2026-10-17: "Complete · With Qaza · Incomplete"), and the day page's own score.
        let what: String = day.prayed == 0 ? (day.excused ? "Excused" : "No prayers marked")
            // No "3 of 5": the ring beside it says which (owner: "you'll know which prayer it was that you didn't complete").
            : day.unfinished ? "So far"
            : day.kind == .allInTime ? "Complete"
            : day.kind == .allFive ? "With Qaza"
            : "Incomplete"   // the score is in the ring
        let number = log.dayNumber(day.date)
        // The whole line opens the day (owner, 2026-10-17: "Clicking the whole bottom row should open the selected
        // prayers day ring page").
        return Button {
            guard canOpen else { return }
            triggerSomeVibration(type: .light)
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    // Which day of the journey it was (owner: "this is day number 225"), beside the card's "325 days".
                    Text(number.map { "\(date) · day \($0)" } ?? date)
                        .font(.system(size: 15, weight: .regular, design: .rounded)).foregroundStyle(.primary)
                    Text(what).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                JourneyDayFifths(day: log.day(day.date), center: day.prayed > 0 ? "\(day.score)" : "–")
                    .frame(width: Self.ring, height: Self.ring)
                    .opacity(canOpen ? 1 : 0.45)   // a day that doesn't open (nothing marked, today still going): quiet
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(canOpen ? "Opens that day" : "")
        .padding(.top, 4)
    }
}

/// A day's five prayers as fifths, no color (owner, 2026-10-17: "show the fifths. That way they can clearly see the makeup
/// of that day. And we won't use color here"): prayed (or excused) drawn, the rest a faint track; its date's number inside.
struct JourneyDayFifths: View {
    let day: JourneyLog.Day
    /// What sits inside: the day's score (not its date — the date is right beside it, owner 2026-10-17).
    let center: String
    /// Each prayed fifth in its grade's colour (the one-day map's ring — owner, 2026-10-17: "put colors on the fifths");
    /// else plain ink (the card: "we won't use color here").
    var colored = false
    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let k = side / JourneyDayRing.size
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    let arc = JourneyDayRing.fifth(i)
                    let mark = day.marks[i]
                    Circle().trim(from: arc.from, to: arc.to)
                        .stroke(mark.done ? (colored ? PrayerScoring.color(for: mark.score) : Color.primary.opacity(0.72))
                                : mark == .excused ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: JourneyDayRing.band * k * 1.15, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: JourneyDayRing.radius * 2 * k, height: JourneyDayRing.radius * 2 * k)
                }
                Text(center)
                    .font(.system(size: JourneyDayRing.number * k * 1.25, weight: .light, design: .rounded)).monospacedDigit()
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// A plain row (the canvas's list row): a symbol, a title over a grey line, a value, and a neutral ›.
struct JourneyHomeRow<Symbol: View, Value: View>: View {
    let title: String
    let line: String
    var last = false
    /// The row's height (the canvas: 58, 52 on a small phone); nil: its padding.
    var height: CGFloat? = nil
    var quiet = false
    @ViewBuilder let symbol: () -> Symbol
    @ViewBuilder let value: () -> Value
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 13) {
                symbol().frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .light, design: .rounded))
                    Text(line)
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .opacity(quiet ? 0.8 : 1)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                value()
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("›").font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(.tertiary)   // neutral, not sage (owner, 2026-10-16)
            }
            .padding(.vertical, height == nil ? 13 : 0)
            .frame(height: height)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Prayer scores' row value: its lifetime score in a small pressed ring (PrayerScores.prayedScore — the page's own number).
struct JourneyMiniRing: View {
    let score: Int
    var body: some View {
        ZStack {
            NeuPressed(shape: Circle(), radius: 2.5, offset: 1.5)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.primary.opacity(0.65), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Text("\(score)").font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.primary)
        }
        .frame(width: 38, height: 38)
    }
}

/// The section labels: "MONTHS" with "% in time" on the right, "MILESTONES".
struct JourneySectionLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .light, design: .rounded)).tracking(1).foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Milestones, from Journey's row (one screen: the list left the page — build-plan "A"): every one earned, newest first;
/// a tap opens its frosted card, and its day.
struct JourneyMilestonesPage: View {
    let milestones: [JourneyMilestone]
    let firstDay: Date?
    let opens: (Date?) -> Bool
    @Environment(\.circleTheme) private var theme
    @State private var card: JourneyMilestone?
    @State private var openDay: JourneyDayRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Milestones").font(.system(size: 38, weight: .regular, design: .rounded))
                    Text(milestones.count == 1 ? "1 earned" : "\(milestones.count) earned")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                JourneyMilestonesList(milestones: milestones, title: nil) { card = $0 }.padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .infoModal(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } }),
                   title: card?.text ?? "", symbol: card?.symbol ?? "flag", tint: .secondary) {
            if let m = card {
                JourneyMilestoneCard(milestone: m, onDay: opens(m.day) ? {
                    let day = m.day
                    card = nil
                    if let day { openDay = JourneyDayRoute(date: day) }
                } : nil)
            }
        }
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: firstDay) }
    }
}

/// Earned once, dated, newest first; a hollow dot each (the canvas).
struct JourneyMilestonesList: View {
    let milestones: [JourneyMilestone]
    /// The section label (nil on the Milestones page, whose title says it).
    var title: String? = "MILESTONES"
    /// A tap: its card (JourneyMilestoneCard).
    var onTap: (JourneyMilestone) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { JourneySectionLabel(title: title) }
            VStack(spacing: 0) {
                ForEach(milestones) { m in
                    Button { triggerSomeVibration(type: .light); onTap(m) } label: {
                    HStack(spacing: 14) {
                        Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.text).font(.system(size: 15, weight: .light, design: .rounded))
                            Text(m.detail ?? m.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.system(size: 12, weight: .light, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Shows how it was earned")
                }
            }
        }
    }
}

/// A day's other things, as counts: notes, photos, prayers with a place (the map), zikr time — the day page's own rules
/// (DayFacts), without its place-name lookups.
struct JourneyDayExtras {
    var date: Date?
    var notes: [DayFacts.Note] = []
    var photoKeys: [String] = []
    var places = 0
    var zikrSeconds: TimeInterval = 0
    /// Whole minutes ("<1" for a little).
    var zikrMinutes: String {
        let m = Int((zikrSeconds / 60).rounded())
        return zikrSeconds > 0 && m < 1 ? "<1" : "\(m)"
    }

    @MainActor static func load(_ date: Date, in context: ModelContext) -> JourneyDayExtras {
        var e = JourneyDayExtras(date: date)
        let key = PrayerNotificationID.dayKey(date)
        let all = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: date)))) ?? []
        var kept: [String: PrayerModel] = [:]   // one per prayer, a completed row winning (the day page's)
        for row in all where row.dayKey == key && JourneyLog.names.contains(row.name) && (!(kept[row.name]?.isCompleted ?? false) || row.isCompleted) {
            kept[row.name] = row
        }
        let done = JourneyLog.names.compactMap { kept[$0] }.filter(\.isCompleted)   // Fajr → Isha
        e.notes = done.compactMap { row in DayFacts.note(row).map { DayFacts.Note(name: row.displayName, text: $0) } }
        e.photoKeys = done.map { PrayerPhotos.key(dayKey: $0.dayKey, name: $0.name) }.filter(PrayerPhotos.has)
        e.places = done.filter { DayFacts.spot($0) != nil }.count
        let from = date.addingTimeInterval(-86_400), to = date.addingTimeInterval(2 * 86_400)
        let near = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= from && $0.startTime < to }))) ?? []
        e.zikrSeconds = near.filter { PrayerDay.start(for: $0.startTime) == date }.reduce(0) { $0 + $1.secondsPassed }
        return e
    }
}

/// A picked day's top — the card's, and the month page's (owner, 2026-10-17: the month "should be the same way here now"):
/// its ring (prayed fifths, no color; the score inside), the date, "Day 225 · 105th of 280", its kind. A tap opens the day.
struct JourneyDayTop: View {
    let day: YourJourneyStats.GridDay
    let log: JourneyLog
    var compact = false
    let canOpen: Bool
    let onOpen: () -> Void

    var body: some View {
        let _ = JourneyPerf.body("dayTop")
        let d = day
        let date = d.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let number = log.dayNumber(d.date).map { "Day \($0)" }
        let rank = log.dayRank(d.date).map { "\(Self.ordinal($0)) of \(log.rankedDays)" }
        let second = d.unfinished ? [number, "today, so far"] : [number, rank]
        let kind = d.prayed == 0 ? (d.excused ? "Excused" : "No prayers marked")
            : d.unfinished ? "Still going" : d.kind == .allInTime ? "Complete" : d.kind == .allFive ? "With Qaza" : "Incomplete"
        let ring: CGFloat = compact ? 46 : 54
        return Button {
            guard canOpen else { return }
            triggerSomeVibration(type: .light)
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                JourneyDayFifths(day: log.day(d.date), center: d.prayed > 0 ? "\(d.score)" : "–")
                    .frame(width: ring, height: ring)
                    .journeyFlightTopRing(d.date)   // the card's day flies from it (JourneyTransitions.swift)
                VStack(alignment: .leading, spacing: 1) {
                    Text(date).font(.system(size: compact ? 15 : 17, weight: .regular, design: .rounded))
                    Text(second.compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: compact ? 12.5 : 13.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    Text(kind).font(.system(size: compact ? 12.5 : 13.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(canOpen ? "Opens that day" : "")
    }

    /// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        let suffix = (11...13).contains(tens) ? "th" : ones == 1 ? "st" : ones == 2 ? "nd" : ones == 3 ? "rd" : "th"
        return "\(n)\(suffix)"
    }
}

/// A picked day's other things — notes, photos, places on the map, zikr — every one, a 0 too, so an empty one reads as
/// none rather than missing (owner, 2026-10-17: "show them all so the user knows for certain they didnt do zikr that day
/// and its not a bug"). Counted once the pick settles; each opens itself where the day page's back card opens it ("tapping
/// the bottom area should show the tapped item"); a 0 opens nothing. The card's bottom and the month page's.
struct JourneyDayExtrasRow: View {
    let date: Date
    let onExtra: (JourneyExtraTap) -> Void
    @State private var extras = JourneyDayExtras()
    @State private var photos = JourneyFrameBox()
    @Environment(\.modelContext) private var context

    var body: some View {
        let _ = JourneyPerf.body("extras")
        let e = extras.date == date ? extras : nil
        HStack(alignment: .top, spacing: 0) {
            extra("text.quote", e.map { "\($0.notes.count)" }, e?.notes.count == 1 ? "note" : "notes", !(e?.notes.isEmpty ?? true)) {
                if let n = e?.notes, !n.isEmpty { onExtra(.notes(n)) }
            }
            extra("photo.on.rectangle", e.map { "\($0.photoKeys.count)" }, e?.photoKeys.count == 1 ? "photo" : "photos",
                  !(e?.photoKeys.isEmpty ?? true)) {
                if let k = e?.photoKeys, !k.isEmpty { onExtra(.photos(k, photos.frame)) }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { photos.frame = $0 }
            extra("map", e.map { "\($0.places)" }, "on the map", e?.places ?? 0 > 0) {
                if e?.places ?? 0 > 0 { onExtra(.map(date)) }
            }
            extra("circle.hexagonpath", e.map { $0.zikrMinutes }, "min of zikr", e?.zikrSeconds ?? 0 > 0) {
                if e?.zikrSeconds ?? 0 > 0 { onExtra(.zikr(date)) }
            }
        }
        .task(id: date) {
            // A held finger crossing days doesn't count every one it passes.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            extras = JourneyPerf.time("extras.load") { JourneyDayExtras.load(date, in: context) }
        }
    }

    private func extra(_ symbol: String, _ value: String?, _ caption: String, _ has: Bool, _ open: @escaping () -> Void) -> some View {
        Button {
            guard has else { return }
            triggerSomeVibration(type: .light)
            open()
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .light))
                    Text(value ?? " ").font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
                }
                Text(caption)
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(has ? Color.primary : Color.secondary)
            .opacity(has ? 1 : 0.55)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!has)
    }
}

/// A place on screen kept without redrawing anything (the photos count's: the pile opens out of it).
final class JourneyFrameBox { var frame: CGRect = .zero }

/// Opens a picked day's things where the day page's back card opens them: notes in the frosted notes card, photos the
/// day's pile (rising out of the count, fading away), on the map the day's map, zikr History locked to that day. Set
/// `tap` and it opens. Journey's page and the month page each carry one.
struct JourneyExtrasPresenter: ViewModifier {
    @Binding var tap: JourneyExtraTap?
    @State private var dayNotes: [DayFacts.Note]?
    @State private var dayPile: DayPileRoute?
    @State private var mapDay: Date?
    @State private var zikrDay: Date?

    func body(content: Content) -> some View {
        content
            .onChange(of: tap == nil) {
                guard let t = tap else { return }
                tap = nil
                switch t {
                case .notes(let n): dayNotes = n
                case .photos(let keys, let from):
                    // No system slide: the pile rises on its own (from), the page behind fading in place.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { dayPile = DayPileRoute(keys: keys, from: from) }
                case .map(let d): mapDay = d
                case .zikr(let d): zikrDay = d
                }
            }
            .infoModal(isPresented: Binding(get: { dayNotes != nil }, set: { if !$0 { dayNotes = nil } }),
                       title: dayNotes?.count == 1 ? "Note" : "Notes", symbol: "text.quote", tint: .secondary) {
                DayNotesInfo(notes: dayNotes ?? [])
            }
            // Grows out of the photos count from a screen below it (owner: "i like how pile comes up from bottom of
            // page"), its blurred page fading in place; it leaves by a plain fade, card and page together ("just make it
            // be a simple fade out").
            .fullScreenCover(item: $dayPile) { route in
                PrayerPhotoViewer(key: route.keys[0], pile: route.keys,
                                  from: route.from.offsetBy(dx: 0, dy: UIScreen.main.bounds.height), fadeOut: true) {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { dayPile = nil }
                }
                .presentationBackground(.clear)
            }
            .fullScreenCover(isPresented: Binding(get: { mapDay != nil }, set: { if !$0 { mapDay = nil } })) {
                LocationMapContentView(dayOnly: mapDay ?? PrayerDay.start())
            }
            .navigationDestination(item: $zikrDay) { ZikrAreaPage(start: .dayOnly($0)) }
    }
}

/// One of a picked day's things, tapped on the card.
enum JourneyExtraTap {
    case notes([DayFacts.Note])
    case photos([String], CGRect)
    case map(Date)
    case zikr(Date)
}

/// A finger on the card's tiles: whether a hold is picking, the rows' width (the bars' slots come from it), and each built
/// row's top in the rows' space, by week.
@MainActor final class JourneyCardScrub {
    var scrubbing = false
    var width: CGFloat = 0
    /// The month rail: where the finger came down and is, whether it moved before the hold, whether it started off the
    /// column, the hold's timer, a lift just now (a name under it mustn't open), the grid's height (the rail's length).
    var railStart: CGPoint?
    var railLast: CGPoint = .zero
    var railMoved = false
    var railOff = false
    var railHoldTask: Task<Void, Never>?
    var railSettle: Task<Void, Never>?
    var railJustEnded = false
    var gridHeight: CGFloat = 0
    /// The grid stays at today until a finger scrolls it or the streak takes it elsewhere (Journey opening on today:
    /// "exiting the page and coming back still opens with the top most tiles in view").
    var pinned = true
    /// The photos count's place on screen (the day's pile opens out of it).
    var photosFrame: CGRect = .zero
}

/// iOS's long press as a SwiftUI gesture, reporting the finger in the view's own space: it begins after `hold` seconds with
/// the finger still (within 10 pt), then follows it. A finger that moves first fails it, so a scroll view around it scrolls.
struct JourneyHoldPick: UIGestureRecognizerRepresentable {
    let hold: Double
    /// The finger in the view's own space, and (for the log) the screen's.
    let onChange: (UIGestureRecognizer.State, CGPoint, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = hold
        g.allowableMovement = 10
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        onChange(recognizer.state, context.converter.location(in: .local), context.converter.location(in: .global))
    }
}

/// Everything Your journey shows, from Journey's log (prayer days; excused prayers never missed, never in a rate).
struct YourJourneyStats {
    enum Kind { case allInTime, allFive, some, none }

    var activeDays = 0
    var prayersMarked = 0
    /// In time over due, on active days only; nil before any prayer was due.
    var inTimeRate: Int?
    /// The longest run of days with every prayer in time (excused days skip, today waits until it's over).
    var bestStreak = 0
    /// The streak going now: days with every prayer in time up to today (excused days skip; today waits until it's over).
    var currentStreak = 0
    /// The best streak's first and last day (the latest of equal ones; its excused days inside it).
    var bestStreakDays: ClosedRange<Date>?
    /// The last 84 prayer days, oldest first, today last.
    /// A day on the card: its color and its line.
    struct GridDay: Equatable {
        let date: Date; let kind: Kind; let prayed: Int; let inTime: Int; let excused: Bool
        /// Its place on this user's scale of its kind (the tile's shade, JourneyTileColor).
        var rank: Double = 1
        /// The day page's number (the five ÷ 5): the picked day's line shows it, so the two always agree.
        var score: Int = 0
        /// Today before its last prayer.
        var unfinished = false
        /// A day from the log (the card's and the year's squares build theirs here).
        static func of(_ log: JourneyLog, _ date: Date) -> GridDay {
            of(log, log.day(date), date)
        }
        static func of(_ log: JourneyLog, _ d: JourneyLog.Day, _ date: Date) -> GridDay {
            GridDay(date: date, kind: d.tileKind, prayed: d.prayed, inTime: d.inTime, excused: d.marks.contains(.excused),
                    rank: log.tileRank(d), score: d.dayScore, unfinished: d.unfinished)
        }
    }
    /// A week a row, from the week of the first day to today's (nil: before the first day, or still to come); the week
    /// holding a month's 1st (or the first day) carries that month's name — "Jan’26" on January and on the first month.
    struct Week: Identifiable {
        let start: Date
        let days: [GridDay?]
        let month: (start: Date, label: String)?
        var id: Date { start }
    }
    var weeks: [Week] = []
    func day(on date: Date) -> GridDay? {
        let cal = Calendar.current
        for w in weeks.reversed() where w.start <= date {
            let i = cal.dateComponents([.day], from: w.start, to: date).day ?? 0
            return w.days.indices.contains(i) ? w.days[i] : nil
        }
        return nil
    }
    /// This month so far, four ways (every prayer whose time has come; nil before any is due) — the This month row.
    struct ThisMonth { let inWindow: Int; let onTime: Int; let perfect: Int; let average: Int }
    var thisMonth: ThisMonth?

    struct MonthRow: Identifiable {
        let id: String
        /// The month it opens (an Away row: the month it began in).
        let month: Date
        let title: String
        let note: String?
        /// % in time on that month's active days; nil for an Away row.
        let rate: Int?
        /// Where it sorts (newest first): the month's start, or the break's first day.
        let at: Date
    }
    var monthRows: [MonthRow] = []
    /// Every milestone earned, newest first.
    var milestones: [JourneyMilestone] = []

    /// A day all excused: every prayer excused, or no rows at all on a day an excused range touches (the app wasn't opened —
    /// Bradley's Excused.streakDay steps over it too). Neither adds to a streak nor breaks it, and isn't "away".
    static func excusedAll(_ d: JourneyLog.Day, on date: Date, in log: JourneyLog, _ excused: Excused.Days) -> Bool {
        d.marks.allSatisfy { $0 == .excused } || (log.days[d.key] == nil && excused.excludes(date))
    }

    static func kind(_ d: JourneyLog.Day) -> Kind {
        guard d.active else { return .none }
        let excused = d.marks.filter { $0 == .excused }.count
        if d.inTime + excused == 5 { return .allInTime }
        if d.prayed + excused == 5 { return .allFive }
        return .some
    }

    /// The months with a marked day, and every break (≥ 7 days in a row with no mark; a fully excused day isn't away).
    private mutating func buildMonths(log: JourneyLog, first: Date, today: Date, excused: Excused.Days) {
        let cal = Calendar.current
        var perMonth: [Date: (inTime: Int, due: Int, days: Int)] = [:]
        var rows: [MonthRow] = []
        var gapStart: Date?
        var gapLength = 0
        func closeGap(endingBefore day: Date) {
            defer { gapStart = nil; gapLength = 0 }
            guard let start = gapStart, gapLength >= 7, let end = cal.date(byAdding: .day, value: -1, to: day) else { return }
            let fmt = Date.FormatStyle.dateTime.month(.abbreviated).day()
            let length = gapLength >= 14 ? "\(Int((Double(gapLength) / 7).rounded())) weeks" : "\(gapLength) days"
            rows.append(MonthRow(id: "away-\(PrayerNotificationID.dayKey(start))", month: JourneyLog.monthStart(start), title: "Away",
                                 note: "\(start.formatted(fmt)) – \(end.formatted(fmt)) · \(length)", rate: nil, at: start))
        }
        var date = first
        while date <= today {
            let d = log.day(date)
            let excusedAll = Self.excusedAll(d, on: date, in: log, excused)
            if d.active {
                closeGap(endingBefore: date)
                let m = JourneyLog.monthStart(date)
                perMonth[m, default: (0, 0, 0)].inTime += d.inTime
                perMonth[m, default: (0, 0, 0)].due += d.due
                perMonth[m, default: (0, 0, 0)].days += 1
            } else if excusedAll {
                closeGap(endingBefore: date)
            } else if date < today || !d.marks.contains(.toCome) {
                if gapStart == nil { gapStart = date }
                gapLength += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        if let next = cal.date(byAdding: .day, value: 1, to: today) { closeGap(endingBefore: next) }

        for (m, t) in perMonth where t.due > 0 {
            let rate = Int((Double(t.inTime) / Double(t.due) * 100).rounded())
            rows.append(MonthRow(id: "month-\(PrayerNotificationID.dayKey(m))", month: m,
                                 title: m.formatted(.dateTime.month(.wide).year()),
                                 note: t.days == 1 ? "1 day" : "\(t.days) days", rate: rate, at: m))
        }
        monthRows = rows.sorted { $0.at > $1.at }
    }

    init(log: JourneyLog, today: Date, excused: Excused.Days = Excused.Days()) {
        let cal = Calendar.current
        var inTime = 0, due = 0
        for d in log.days.values where d.active {
            activeDays += 1
            prayersMarked += d.prayed
            inTime += d.inTime
            due += d.due
        }
        if due > 0 { inTimeRate = Int((Double(inTime) / Double(due) * 100).rounded()) }

        if let first = log.firstDay {
            let firstDay = cal.startOfDay(for: first)
            var weekStart = cal.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
            var labelled = false
            while weekStart <= today {
                var days: [GridDay?] = []
                var month: (start: Date, label: String)?
                for k in 0..<7 {
                    guard let date = cal.date(byAdding: .day, value: k, to: weekStart) else { days.append(nil); continue }
                    if month == nil, cal.component(.day, from: date) == 1 || date == firstDay, date >= firstDay {
                        let short = date.formatted(.dateTime.month(.abbreviated))
                        let year = !labelled || cal.component(.month, from: date) == 1
                            ? "’" + String(cal.component(.year, from: date) % 100) : ""
                        month = (JourneyLog.monthStart(date), short + year)
                        labelled = true
                    }
                    guard date >= firstDay, date <= today else { days.append(nil); continue }
                    days.append(GridDay.of(log, date))
                }
                weeks.append(Week(start: weekStart, days: days, month: month))
                guard let next = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
                weekStart = next
            }
        }
        // This month, on time or better (owner's This month row): every prayer whose time has come.
        var window = 0, onTime = 0, perfect = 0, owed = 0, scoreSum = 0.0
        for date in JourneyLog.daysOf(month: JourneyLog.monthStart(today)) where date <= today {
            for mark in log.day(date).marks {
                if case .done(let score) = mark {
                    owed += 1
                    scoreSum += score
                    switch PrayerScoring.grade(for: score) {
                    case .perfect: perfect += 1; onTime += 1; window += 1
                    case .onTime: onTime += 1; window += 1
                    case .late: window += 1
                    case .qaza: break
                    }
                } else if mark == .missed {
                    owed += 1
                }
            }
        }
        if owed > 0 {
            func pct(_ n: Int) -> Int { Int((Double(n) / Double(owed) * 100).rounded()) }
            thisMonth = ThisMonth(inWindow: pct(window), onTime: pct(onTime), perfect: pct(perfect),
                                  average: Int((scoreSum / Double(owed) * 100).rounded()))
        }

        milestones = JourneyMilestone.earned(log: log, today: today, excused: excused)
        if let first = log.firstDay {
            buildMonths(log: log, first: cal.startOfDay(for: first), today: today, excused: excused)
            var run = 0
            var runStart: Date?
            var date = cal.startOfDay(for: first)
            while date <= today {
                let d = log.day(date)
                if Self.excusedAll(d, on: date, in: log, excused) {
                    // An excused day neither counts nor breaks.
                } else if Self.kind(d) == .allInTime {
                    if run == 0 { runStart = date }
                    run += 1
                    if run >= bestStreak, let s = runStart { bestStreak = run; bestStreakDays = s...date }
                } else if !(date == today && d.marks.contains(.toCome)) {
                    run = 0
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
            currentStreak = run
        }
    }
}

// MARK: - Milestones

/// A milestone's card, in the frosted ⓘ card (InfoModal): what it is, when, how it was earned, and its day.
struct JourneyMilestoneCard: View {
    let milestone: JourneyMilestone
    /// Its day page (nil: none to open — today's still going, or a year since day one).
    var onDay: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(milestone.about)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            InfoModalRow(symbol: "calendar", title: "When",
                         text: milestone.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            if let how = milestone.how {
                InfoModalRow(symbol: "checkmark.circle", title: "How", text: how)
            }
            if let onDay {
                Button { triggerSomeVibration(type: .light); onDay() } label: {
                    Text("See that day ›")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Earned once, dated (spec "Milestones", owner 2026-10-16: "a milestone for each one" — every prayer, not only Fajr).
/// One walk over the log from day one; the same rules as the page (prayer days, excused never missed, a run skips a fully
/// excused day and waits on an unfinished today).
struct JourneyMilestone: Identifiable, Equatable {
    enum Tone { case count, inTime, quiet }   // the mockup's dots: dark, green, grey
    let id: String
    var text: String
    let date: Date
    let tone: Tone
    /// The line under it in place of the date ("Jan 5 – Feb 17, 2025" for the best streak).
    var detail: String? = nil
    /// Within a day, the later-earned one sits higher (newest first).
    var order = 0
    /// Its card (a tap — owner, 2026-10-16: "click on a milestone to learn more about it"): a symbol, what it is, how it was
    /// earned, and the day it opens (nil: none — a year since day one).
    var symbol = "flag"
    var about = ""
    var how: String? = nil
    var day: Date? = nil

    /// Days all in time in a row worth a milestone (DayInsight's own list).
    static let runs: [Int] = [7, 14, 21, 30, 40, 50, 60, 90, 100, 150, 200, 250, 300, 365]
    /// Every hundred prayers (owner, 2026-10-16: "yeah, sure, that's fine"); the list keeps the 100th, the 500th, every
    /// thousandth and only the latest of the rest, so it reads as achievements, not a counter.
    static func keepsTotal(_ n: Int) -> Bool { n == 100 || n == 500 || n % 1000 == 0 }
    static let perPrayer: [Int] = [100, 500]

    static func earned(log: JourneyLog, today: Date, excused: Excused.Days = Excused.Days()) -> [JourneyMilestone] {
        guard let firstDay = log.firstDay else { return [] }
        let cal = Calendar.current
        var out: [JourneyMilestone] = []
        func add(_ id: String, _ text: String, _ date: Date, _ tone: Tone,
                 symbol: String = "flag", about: String = "", how: String? = nil, day: Date? = nil) {
            guard !out.contains(where: { $0.id == id }) else { return }
            out.append(JourneyMilestone(id: id, text: text, date: date, tone: tone, order: out.count,
                                        symbol: symbol, about: about, how: how, day: day ?? date))
        }
        /// "Isha, prayed 8:18 PM" — the prayer that earned it.
        func prayed(_ d: JourneyLog.Day, _ i: Int) -> String {
            let name = d.slots[i]?.jumuah == true ? "Jumu'ah" : JourneyLog.names[i]
            return name + (d.slots[i]?.markedAt.map { ", prayed " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
        }
        let span = Date.FormatStyle.dateTime.month(.abbreviated).day()
        func ordinal(_ n: Int) -> String {
            let f = NumberFormatter(); f.numberStyle = .ordinal
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        }

        var total = 0
        var perName: [Int] = Array(repeating: 0, count: 5)
        var run = 0, best = 0, bestAtRunStart = 0
        var runLastDay: Date?
        var runFirstDay: Date?
        var gap = 0
        var masjidDone = false, jumuahDone = false, perfectDone = false

        func closeRun() {
            // A run that beat the best before it: "N days in a row, all in time" — "your best" while it still is.
            // Keyed by the run's first day: a best still growing is one milestone, celebrated once, not one a day.
            if run >= 3, run > bestAtRunStart, let last = runLastDay, let firstOfRun = runFirstDay {
                out.removeAll { $0.id == "run.\(run)" && cal.isDate($0.date, inSameDayAs: last) }   // the same news twice
                add("best.\(PrayerNotificationID.dayKey(firstOfRun))", "\(run) days in a row, all in time", last, .inTime,
                    symbol: "trophy", about: "A new best: more days in a row with all five prayed in time than ever before.",
                    how: "\(run) days, \(firstOfRun.formatted(span)) – \(last.formatted(span))")
                if let k = out.firstIndex(where: { $0.id == "best.\(PrayerNotificationID.dayKey(firstOfRun))" }) {
                    let sameYear = cal.component(.year, from: firstOfRun) == cal.component(.year, from: last)
                    let from = firstOfRun.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
                    out[k].detail = "\(from) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
                }
            }
            run = 0
            bestAtRunStart = best
            runLastDay = nil
            runFirstDay = nil
        }

        var date = cal.startOfDay(for: firstDay)
        while date <= today {
            let d = log.day(date)
            let excusedAll = YourJourneyStats.excusedAll(d, on: date, in: log, excused)
            let unfinishedToday = date == today && d.marks.contains(.toCome)

            if d.active {
                if gap >= 7, let left = cal.date(byAdding: .day, value: -gap, to: date),
                   let lastAway = cal.date(byAdding: .day, value: -1, to: date) {
                    add("back.\(d.key)", "Welcome back", date, .quiet, symbol: "arrow.uturn.left",
                        about: "Your first prayer marked after \(gap) days away.",
                        how: "Away \(left.formatted(span)) – \(lastAway.formatted(span))")
                }
                gap = 0
                // Day one: the first prayer marked, by when it was marked.
                if out.isEmpty {
                    let first = (0..<5).filter { d.marks[$0].done }
                        .min { (d.slots[$0]?.markedAt ?? .distantFuture) < (d.slots[$1]?.markedAt ?? .distantFuture) }
                    if let i = first {
                        add("dayOne", "Day one", date, .quiet, symbol: "sparkles",
                            about: "The first prayer you marked in shukr.", how: prayed(d, i))
                    }
                }
                for i in 0..<5 where d.marks[i].done {
                    total += 1
                    perName[i] += 1
                    if total % 100 == 0 {
                        add("total.\(total)", "\(ordinal(total)) prayer", date, .count, symbol: "number",
                            about: "\(total) prayers marked since day one.", how: prayed(d, i))
                    }
                    if Self.perPrayer.contains(perName[i]) {
                        add("\(JourneyLog.names[i]).\(perName[i])", "\(ordinal(perName[i])) \(JourneyLog.names[i])", date, .count,
                            symbol: "number", about: "\(perName[i]) \(JourneyLog.names[i]) prayers marked since day one.",
                            how: prayed(d, i))
                    }
                    let slot = d.slots[i]
                    if !jumuahDone, slot?.jumuah == true {
                        jumuahDone = true
                        masjidDone = true   // the first Jumu'ah is also the first prayer at a masjid: once is enough
                        add("jumuah", "First Jumu'ah at a masjid", date, .count, symbol: "building.columns",
                            about: "Your first Friday prayer marked at a masjid.",
                            how: slot?.masjid.map { "At \($0)" } ?? prayed(d, i))
                    } else if !masjidDone, let m = slot?.masjid {
                        masjidDone = true
                        add("masjid", "First prayer at a masjid: \(m)", date, .count, symbol: "building.columns",
                            about: "The first prayer you marked at a masjid.", how: "\(prayed(d, i)), at \(m)")
                    }
                }
                if !perfectDone, d.marks.allSatisfy({ ($0.score ?? 0) >= 0.9999 }) {
                    perfectDone = true
                    add("perfect", "A perfect day: all five Perfect", date, .inTime, symbol: "star",
                        about: "All five prayers prayed in their first 30 minutes on one day, each scored 100.")
                }
            } else if excusedAll {
                gap = 0
            } else if !unfinishedToday {
                gap += 1
            }

            // Days all in time in a row.
            if excusedAll {
                // neither counts nor breaks
            } else if YourJourneyStats.kind(d) == .allInTime {
                run += 1
                if run == 1 { runFirstDay = date }
                runLastDay = date
                best = max(best, run)
                if Self.runs.contains(run) {
                    add("run.\(run)", run == 7 ? "A full week, all in time" : "\(run) days in a row, all in time", date, .inTime,
                        symbol: "calendar", about: "\(run) days in a row with all five prayers prayed in time.",
                        how: runFirstDay.map { "\($0.formatted(span)) – \(date.formatted(span))" })
                }
            } else if !unfinishedToday {
                closeRun()
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        closeRun()

        // Every hundred prayers: the round ones stay, of the rest only the latest.
        let latestTotal = out.last(where: { $0.id.hasPrefix("total.") })?.id
        out.removeAll { m in
            guard m.id.hasPrefix("total."), m.id != latestTotal, let n = Int(m.id.dropFirst(6)) else { return false }
            return !Self.keepsTotal(n)
        }

        // One Welcome back, the latest return (Frank's check on the owner's data: one per break read as a log of breaks, not
        // achievements; spec: "earned once, dated"). Each return still gets its moment (its own id) when it happens.
        if let latest = out.last(where: { $0.id.hasPrefix("back.") })?.id {
            out.removeAll { $0.id.hasPrefix("back.") && $0.id != latest }
        }

        // Years since day one.
        var years = 1
        while let anniversary = cal.date(byAdding: .year, value: years, to: cal.startOfDay(for: firstDay)), anniversary <= today {
            add("year.\(years)", years == 1 ? "One year since day one" : "\(years) years since day one", anniversary, .quiet,
                symbol: "calendar.badge.clock", about: "Day one was \(firstDay.formatted(.dateTime.month(.wide).day().year())).")
            if let k = out.firstIndex(where: { $0.id == "year.\(years)" }) { out[k].day = nil }   // no day page for an anniversary
            years += 1
        }

        // The latest best is "Your best streak: N days" over its dates (the canvas); the ones it beat stay as they were.
        if let i = out.lastIndex(where: { $0.id.hasPrefix("best.") }) {
            let n = out[i].text.split(separator: " ").first.map(String.init) ?? ""
            out[i].text = "Your best streak: \(n) days"
            out[i].about = "Your longest streak of days with all five prayed in time." 
        }
        return out.sorted { ($0.date, $0.order) > ($1.date, $1.order) }
    }
}

// MARK: - The celebration

/// Milestones are celebrated as they happen, with the first prayer's own celebration (spec decisions: "celebrated as
/// they happen, reusing the first-prayer celebration"; owner 2026-10-16): the green edge glow and its card, in the
/// milestone's words. Checked after a mark on the Salah page and whenever the app comes to the front (a mark from the
/// widget, the watch or a past day). The first check ever records what's already earned without a word (no flood on
/// the update); each milestone is celebrated once, even if a prayer is unmarked and marked again.
@MainActor @Observable final class MilestoneCelebration {
    static let shared = MilestoneCelebration()
    static let seenKey = "journey.milestones.seen"
    static let seenVersionKey = "journey.milestones.seenVersion"
    /// Bumped when a kind of milestone is added (2: every hundred prayers): the first check after an update records what's
    /// already earned of it without a word — never a run of "200th … 800th" celebrations (Sami's trap, acceptance-2 2b).
    static let seenVersion = 2
    private(set) var showing: JourneyMilestone?
    @ObservationIgnored private var queue: [JourneyMilestone] = []
    @ObservationIgnored private var checking = false

    /// After a mark: wait out the mark's own flourish (as the first mark's card, 2.4 s).
    func check(container: ModelContainer, delay: Double = 2.4) {
        guard !checking else { return }
        checking = true
        let ranges = Excused.ranges
        Task {
            defer { checking = false }
            let log = await JourneyLog.load(container: container, ranges: ranges)
            let earned = JourneyMilestone.earned(log: log, today: PrayerDay.start())
            let defaults = UserDefaults.standard
            let ids = earned.map(\.id)
            #if DEBUG
            // `-demoMilestoneCelebration`: the newest milestone left unseen, so the next check celebrates it (the pictures).
            if ProcessInfo.processInfo.arguments.contains("-demoMilestoneCelebration") {
                defaults.set(Array(ids.dropFirst()), forKey: Self.seenKey)
                defaults.set(Self.seenVersion, forKey: Self.seenVersionKey)
            }
            #endif
            guard let seen = defaults.stringArray(forKey: Self.seenKey),
                  defaults.integer(forKey: Self.seenVersionKey) >= Self.seenVersion else {
                let before = defaults.stringArray(forKey: Self.seenKey) ?? []
                defaults.set(Array(Set(before + ids)), forKey: Self.seenKey)
                defaults.set(Self.seenVersion, forKey: Self.seenVersionKey)
                return
            }
            let new = earned.filter { !seen.contains($0.id) }
            guard !new.isEmpty else { return }
            defaults.set(Array(Set(seen + ids)), forKey: Self.seenKey)
            try? await Task.sleep(for: .seconds(delay))
            // Never over the tour or the first mark's own card (that one is Day one's celebration).
            guard TourRuntime.shared.step == nil, !TourRuntime.shared.active else { return }
            queue.append(contentsOf: new.reversed())   // oldest first
            if showing == nil { next() }
        }
    }

    /// Continue: the next one, if a mark earned two (the 100th prayer and the 100th Asr).
    func next() {
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            showing = queue.isEmpty ? nil : queue.removeFirst()
        }
    }
}

/// Over the Salah page, beside the tour's layer: the first mark's glow and card, in a milestone's words.
struct MilestoneCelebrationLayer: View {
    let covered: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var celebration: MilestoneCelebration { MilestoneCelebration.shared }

    var body: some View {
        ZStack {
            if let m = celebration.showing, !covered {
                TourOverlay(step: .celebrate,
                            page: TourPage(headline: m.text, subline: "Added to Your journey.", primary: TourCopy.continueButton),
                            onPrimary: { celebration.next() })
                    .id(m.id)
                    .transition(.opacity)
                    .onAppear { AccessibilityNotification.Announcement(m.text).post() }
                if !reduceMotion { FirstMarkGlow().id("glow-" + m.id).allowsHitTesting(false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            celebration.check(container: context.container, delay: 1.0)
        }
    }
}
