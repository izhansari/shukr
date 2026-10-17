import SwiftUI

// Journey's card, expanded (owner, 2026-10-17; board/journey-expand-plan.md): "I imagine it literally just expands the card so
// that the same tiles and rows turn into our view of the calendar … we just expanded the current compacted tiles to be a
// little larger to show rings in the same fashion that it's shown in the tiles with a little more insight on the month
// labels". The card's ↗ (a month name, This month) opens it in Journey's host (JourneyTransitions.swift) in place of the old
// month page: the card's top and bottom, and between them the same weeks — a week a row, seven columns — as rings.

struct JourneyExpandedPage: View {
    let log: JourneyLog
    let stats: YourJourneyStats
    /// The month it opened on, and whether it opened focused on it (a month name, This month) or not (the ↗: the weeks the
    /// card showed, today's at the bottom).
    let opened: Date
    let focusOnOpen: Bool

    /// The month in focus (only by a tap: a ring, or a month's name — owner, 2026-10-17: "only focus that month if a
    /// tile/ring in that month has been clicked … if we scroll away, it unfocuses"): its days full, the rest faded.
    @State private var focus: Date?
    /// The day picked (a ring's tap): its top and its things at the bottom, the card's way.
    @State private var picked: Date?
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var gridWidth: CGFloat = 0
    /// The year in place of the weeks (the toggle top right — owner: "leave this as an sf toggle button in top right").
    @State private var showYear = false
    /// The year's own dials (its flights, E4); idle, the year sees no flight — the card's dial at "open" faded its words out.
    @State private var yearDials = JourneyMonthDial()
    /// A month flying between the weeks and the year (1 = the weeks, 0 = the year); nil at rest.
    @State private var yearFlight: JourneyMonthFlight?
    /// The year laid out, its flight not set yet (a frame or two): the weeks stay up and the year hidden.
    @State private var yearWaiting = false
    /// The month the year opened on (its year shows; its small month is where the days go home).
    @State private var yearMonth: Date?
    @State private var extraTap: JourneyExtraTap?
    /// The month rail (hold the names' column, as on the card): the month the finger's on.
    @State private var rail: Int?
    @State private var scrub = JourneyCardScrub()
    /// Pinched in: the card's tiles in place of the rings, rows the card's pitch, so many more weeks show (owner, 2026-10-17:
    /// "we can still pinch it to make ting smaller into tiles on this expanded view"); spread, the rings again.
    @State private var tiles = false
    /// The week in the middle of the view (what a pinch keeps in place).
    @State private var middleWeek: Date?
    @Environment(\.journeyDayOpener) private var dayOpener
    @Environment(\.journeyMonthOpen) private var monthOpen
    @Environment(\.circleTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    init(log: JourneyLog, stats: YourJourneyStats, opened: Date, focusOnOpen: Bool) {
        self.log = log
        self.stats = stats
        self.opened = opened
        self.focusOnOpen = focusOnOpen
        _focus = State(initialValue: focusOnOpen ? opened : nil)
    }

    private var today: Date { PrayerDay.start() }

    /// The names' column: wide enough for "Jan’26" over "14 days" and "score 89".
    static let labelColumn: CGFloat = 54
    /// Rows this far apart beyond the ring itself.
    static let rowGap: CGFloat = 2
    /// A ring's side at this width: seven across what the names leave, never larger than the month page's.
    private var cell: CGFloat { min((cellsWidth / 7).rounded(.down), JourneyDayRing.size) }
    /// The days' width in a row (the row less the names' column).
    private var cellsWidth: CGFloat { (gridWidth > 0 ? gridWidth : UIScreen.main.bounds.width - 40) - Self.labelColumn }

    var body: some View {
        let _ = JourneyPerf.body("expanded")
        ZStack {
            if showYear {
                JourneyYearView(log: log, today: today, current: yearMonth ?? focus ?? opened, onPick: { m in
                    triggerSomeVibration(type: .light)
                    fromYear(to: m)   // a small month's tap: back to the weeks with it in focus
                }, onSpread: { fromYear(to: nil) }, onDay: { open($0) })
                // Idle, the year sees no flight (a card's or a day's never fades it); in a weeks ↔ year flight, this one.
                .modifier(JourneyYearFlightDriver(dials: yearDials, flight: yearFlight, clearWhenIdle: true))
                .opacity(yearWaiting ? 0 : 1)
            }
            // The landing tiles: the card's (opening), or a small month's squares to and from its rings (the year).
            JourneyFlyingTiles()
            // The weeks stay mounted under the year (hidden): a month tapped there is scrolled to before its flight starts
            // — rebuilt at the flight, the new scroll view took its default (today at the bottom) and the scroll was lost.
            VStack(spacing: 0) {
                top
                hairline
                grid
                hairline
                bottom
            }
            .opacity(showYear && yearFlight == nil && !yearWaiting ? 0 : 1)
            .allowsHitTesting(yearFlight == nil && !showYear)
        }
        // A weeks ↔ year flight drives the page's own pieces (its cells, words, the flying squares); at rest, the host's.
        .modifier(JourneyYearFlightDriver(dials: yearDials, flight: yearFlight, clearWhenIdle: false))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { yearToggle }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { yearToggle }
            }
        }
        .modifier(JourneyExtrasPresenter(tap: $extraTap))
        .background(theme.surface.journeyFlightMonthSurface().ignoresSafeArea())   // clear while it opens over Journey
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hairline: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 20).journeyFlightWords(.month)
    }

    // MARK: The top

    /// The card's top, grown: a picked day's, a focused month's numbers, else the count. One fixed room, so the weeks never
    /// move as it changes.
    private var top: some View {
        ZStack(alignment: .topLeading) {
            if let p = picked {
                let d = YourJourneyStats.GridDay.of(log, p)
                JourneyDayTop(day: d, log: log, canOpen: d.prayed > 0 && opens(p)) { open(p) }
                    .id(p)
                    .transition(.opacity)
            } else if let m = focus {
                JourneyMonthNumbers(log: log, month: m, today: today)
                    .id(m)
                    .transition(.opacity)
            } else {
                count.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 84, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .journeyFlightWords(.month)
    }

    private var count: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(stats.activeDays)").font(.system(size: 54, weight: .thin, design: .rounded))
                Text(stats.activeDays == 1 ? "day you marked a prayer" : "days you marked a prayer")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(stats.currentStreak > 0 ? "\(stats.currentStreak)-day streak" : "Start a streak today")
                .font(.system(size: 11, weight: .light, design: .rounded)).tracking(0.4)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: The weeks

    private var grid: some View {
        let cell = cell
        let monthWeeks = stats.weeks.compactMap { $0.month == nil ? nil : $0.id }
        let labels = Self.labelRows(stats.weeks)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: tiles ? JourneyHomeCard.pitch - 11 : Self.rowGap) {
                ForEach(Array(stats.weeks.enumerated()), id: \.element.id) { i, week in
                    JourneyExpandedRow(week: week, index: i, log: log, today: today, cell: cell, tiles: tiles,
                                       labelMonth: labels[week.id]?.month, labelBetween: labels[week.id]?.between ?? false,
                                       focus: focus, picked: picked.flatMap { p in week.days.contains { $0?.date == p } ? p : nil },
                                       onDay: { pick($0) }, onMonth: { focusMonth($0) },
                                       onHold: { state, p in held(state, p, fromRow: i) })
                        .equatable()
                        .id(week.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .scrollDisabled(rail != nil)
        .onScrollTargetVisibilityChange(idType: Date.self, threshold: 0.5) { ids in
            let sorted = ids.sorted()
            if !sorted.isEmpty { middleWeek = sorted[sorted.count / 2] }
        }
        // Pinch in: tiles; spread: rings — the week in the middle stays where it is through the morph.
        .simultaneousGesture(MagnifyGesture().onEnded { v in
            if v.magnification < 0.85, !tiles { setTiles(true) } else if v.magnification > 1.15, tiles { setTiles(false) }
        })
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }   // inside its padding: = the guess
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrub.gridHeight = $0 }
        .padding(.horizontal, 20)
        // A finger's scroll lets the focus and the pick go, as the card's tile does (owner: "the same way we unfocus the tile
        // on scrolling"); the rail's own scrolls aren't the finger's.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { JourneyPerf.began("expanded scroll") }
            JourneyPerf.scrolling(phase.isScrolling)
            guard phase == .interacting, rail == nil, picked != nil || focus != nil else { return }
            withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil; focus = nil }
        }
        // The names' column is a rail (the card's): held still a moment, the finger's height is the month.
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { v in railChanged(v, months: monthWeeks) }
            .onEnded { _ in railEnded() })
        .sensoryFeedback(.selection, trigger: rail)
        .overlay(alignment: .topLeading) { railPill(months: monthWeeks) }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 10)
            }
        }
        .onAppear { arrive() }
    }

    /// Which row carries each month's name: the middle of the rows the month's days fill (owner, 2026-10-17: "make it so the
    /// month labels rest in the middle of their month grids … aligned with the vertical center"), between the two middle rows
    /// when there's an even number. Keyed by the row's week.
    static func labelRows(_ weeks: [YourJourneyStats.Week]) -> [Date: (month: Date, between: Bool)] {
        let cal = Calendar.current
        var out: [Date: (month: Date, between: Bool)] = [:]
        for (first, week) in weeks.enumerated() {
            guard let m = week.month?.start,
                  let last = cal.date(byAdding: DateComponents(month: 1, day: -1), to: m) else { continue }
            // The row holding its last day (or the latest row: this month, still going).
            let end = weeks[first...].firstIndex { cal.date(byAdding: .day, value: 6, to: $0.start).map { $0 >= last } ?? false }
                ?? weeks.count - 1
            let rows = end - first + 1
            out[weeks[first + (rows - 1) / 2].id] = (m, rows % 2 == 0)
        }
        return out
    }

    private func setTiles(_ on: Bool) {
        JourneyPerf.began(on ? "expanded → tiles" : "expanded → rings")
        triggerSomeVibration(type: .light)
        let keep = middleWeek
        withAnimation(.smooth(duration: 0.45)) {
            tiles = on
            if let keep { position.scrollTo(id: keep, anchor: .center) }
        } completion: {
            // The rows changed size under that scroll and the lazy stack went by its estimates (a spread from tiles landed
            // months early — the helper's check): again, now they're built at their new size.
            guard let keep else { return }
            withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: keep, anchor: .center) }
        }
    }

    /// Opened on a month (a name, This month): that month in the middle; from the ↗, today's week at the bottom (the card's).
    private func arrive() {
        guard focusOnOpen, let week = stats.weeks.first(where: { $0.month?.start == opened })?.id else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
        // Far rows weren't built: the lazy stack's estimate lands short; again once they are (the card's rail).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
        }
    }

    // MARK: The bottom

    /// The card's bottom: a picked day's things, else the three numbers.
    private var bottom: some View {
        ZStack(alignment: .top) {
            if let p = picked {
                JourneyDayExtrasRow(date: p) { extraTap = $0 }
                    .id(p)
                    .transition(.opacity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    figure("\(stats.prayersMarked)", "prayers marked")
                    figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days")
                    figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days", "best streak")
                }
                .transition(.opacity)
            }
        }
        .frame(height: 58, alignment: .top)
        .padding(.top, 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .journeyFlightWords(.month)
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Picks

    /// A ring's tap: that day picked and its month in focus; again, both let go.
    private func pick(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        JourneyPerf.began("expanded pick")
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            if picked == date { picked = nil; focus = nil } else { picked = date; focus = JourneyLog.monthStart(date) }
        }
    }

    /// Hold, then move: each day under the finger picked, across rows (owner, 2026-10-17: "you know how in the compacted card
    /// we can drag around in the tiles and select a few tiles with the drag? I want to do the same thing when we're in the
    /// expanded view, whether it's in rings or tile fashion") — the card's way: a firm tick to begin, a soft one per new day,
    /// its month in focus with it. `p` is in row `i`'s days' space; rows on screen are exactly a pitch apart.
    private func held(_ state: UIGestureRecognizer.State, _ p: CGPoint, fromRow i: Int) {
        switch state {
        case .began:
            JourneyPerf.began("expanded hold")
            scrub.scrubbing = true
            triggerSomeVibration(type: .medium)
            if let d = day(at: p, fromRow: i) {
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = d; focus = JourneyLog.monthStart(d) }
            }
        case .changed:
            guard scrub.scrubbing, let d = day(at: p, fromRow: i), d != picked else { return }
            triggerSomeVibration(type: .soft)
            withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = d; focus = JourneyLog.monthStart(d) }
        default:
            scrub.scrubbing = false
        }
    }

    /// The day under a point in row `i`'s days' space (rows a pitch apart, each band reaching halfway to the next; the
    /// nearest column), if it's one that can be picked.
    private func day(at p: CGPoint, fromRow i: Int) -> Date? {
        guard !stats.weeks.isEmpty else { return nil }
        let height: CGFloat = tiles ? 11 : cell
        let gap: CGFloat = tiles ? JourneyHomeCard.pitch - 11 : Self.rowGap
        let spacing: CGFloat = tiles ? 6 : 0
        let row = min(max(i + Int(((p.y + gap / 2) / (height + gap)).rounded(.down)), 0), stats.weeks.count - 1)
        let slot = (cellsWidth + spacing) / 7
        let col = min(max(Int(((p.x + spacing / 2) / slot).rounded(.down)), 0), 6)
        guard let date = Calendar.current.date(byAdding: .day, value: col, to: stats.weeks[row].start),
              let first = log.firstDay, date >= first, date <= today else { return nil }
        return date
    }

    /// A month's name: that month in focus, no day (its numbers at the top); again, let go.
    private func focusMonth(_ m: Date) {
        guard rail == nil, !scrub.railJustEnded else { return }
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            picked = nil
            focus = focus == m ? nil : m
        }
    }

    private func opens(_ date: Date) -> Bool {
        guard let first = log.firstDay, date >= first, date <= today else { return false }
        return date < today || log.day(date).allFive
    }

    /// The day page, its ring flying from its cell (the host's opener).
    private func open(_ date: Date) {
        guard opens(date) else { return }
        dayOpener?.open(date)
    }

    // MARK: The year

    private var yearToggle: some View {
        let dayUp = monthOpen?.hiddenDay != nil
        return Button {
            triggerSomeVibration(type: .light)
            if showYear { fromYear(to: nil) } else { toYear() }
        } label: {
            Image(systemName: showYear ? "calendar" : "square.grid.3x3")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showYear ? "Weeks" : "Year")
        .journeyFlightWords(.month)
        .opacity(dayUp ? 0 : 1)
        .allowsHitTesting(!dayUp)
        .animation(.easeInOut(duration: 0.3), value: dayUp)
    }

    /// The month a weeks ↔ year flight carries: the one in focus, else the one in the middle of the weeks.
    private var flightMonth: Date {
        if let f = focus { return f }
        if let w = middleWeek, let mid = Calendar.current.date(byAdding: .day, value: 3, to: w) { return JourneyLog.monthStart(mid) }
        return opened
    }

    /// Out to the year (E4): the year laid out under the weeks, then that month's days fly home into its small month's
    /// squares while the year's words and other months arrive — the old month page's month → year, from the week rows.
    private func toYear() {
        guard !showYear, yearFlight == nil else { return }
        JourneyPerf.began("year opens")
        picked = nil
        let month = flightMonth
        let geo = JourneyFlightGeometry.shared
        geo.yearGrids = [:]
        geo.yearNames = [:]
        geo.yearShowing = true
        // The host's ‹ and edge swipe: back to the weeks, not the card.
        geo.yearBack = { fromYear(to: nil) }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            yearMonth = month
            yearWaiting = true
            showYear = true
        }
        geo.whenYearReady(month) {
            yearDials.set(.month, 1)
            withTransaction(quiet) { yearFlight = Self.flight(month, log: log, today: today); yearWaiting = false }
            let run = JourneyFrameLog.shared.start("weeks → year")
            yearDials.animate(.month, to: 0, duration: JourneyMotion.monthDuration) {
                JourneyFrameLog.shared.stop(run: run)
                // The weeks come down a beat after the days have landed, when nothing moves (the month page's way: at the
                // landing frame their teardown held the last frame).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withTransaction(quiet) { yearFlight = nil } }
            }
        }
    }

    /// Back to the weeks from the year: a small month's tap grows its squares into its rings, landing in focus in the
    /// middle; ‹, the toggle or a spread fly the middle month home as it was (no focus — only a tap focuses).
    private func fromYear(to m: Date?) {
        guard showYear, yearFlight == nil else { return }
        JourneyPerf.began("weeks from year")
        let month = m ?? flightMonth
        let geo = JourneyFlightGeometry.shared
        var quiet = Transaction()
        quiet.disablesAnimations = true
        yearDials.set(.month, 0)
        withTransaction(quiet) {
            picked = nil
            focus = m
            yearFlight = Self.flight(month, log: log, today: today)
        }
        // The month's middle week in the middle (its 1st's week there left most of it below).
        if let m, let mid = Calendar.current.date(byAdding: .day, value: 14, to: m),
           let week = stats.weeks.last(where: { $0.start <= mid })?.id {
            withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
        }
        // The rings' places come with the week rows laid out where the scroll put them (their anchors, resolved each
        // layout; the flying squares read them live).
        DispatchQueue.main.async { geo.title = nil; geo.afterTitle {
            let run = JourneyFrameLog.shared.start("year → weeks")
            yearDials.animate(.month, to: 1, duration: JourneyMotion.monthDuration) {
                JourneyFrameLog.shared.stop(run: run)
                withTransaction(quiet) {
                    showYear = false
                    yearFlight = nil
                    yearMonth = nil
                }
                geo.yearShowing = false
                geo.yearBack = nil
            }
        } }
    }

    /// A month's flight between its small month and its rings: the year's squares (where they are on screen now), its days'
    /// rings drawn in by their place in the month; the weeks' other days and words arrive with the dial.
    private static func flight(_ month: Date, log: JourneyLog, today: Date) -> JourneyMonthFlight {
        var f = JourneyMonthFlight.fromYear(month, log: log, today: today)
        let dates = f.tiles.keys.sorted()
        var order: [Date: CGFloat] = [:]
        for (i, d) in dates.enumerated() { order[d] = dates.count > 1 ? CGFloat(i) / CGFloat(dates.count - 1) : 0 }
        f.order = order
        return f
    }

    // MARK: The month rail (the card's: hold the names, the finger's height is the month)

    private static let railHold = 0.22

    private func railIndex(_ y: CGFloat, count n: Int) -> Int {
        let f = min(max(y / max(scrub.gridHeight, 1), 0), 0.999)
        return min(Int(f * CGFloat(n)), n - 1)
    }

    private func railChanged(_ v: DragGesture.Value, months: [Date]) {
        let r = scrub
        r.railLast = v.location
        if r.railStart == nil {
            r.railStart = v.startLocation
            r.railMoved = false
            r.railOff = v.startLocation.x > Self.labelColumn + 6 || months.isEmpty
            guard !r.railOff else { return }
            r.railHoldTask?.cancel()
            r.railHoldTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.railHold))
                guard !Task.isCancelled, r.railStart != nil, !r.railMoved else { return }
                JourneyPerf.began("expanded rail")
                triggerSomeVibration(type: .medium)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil; focus = nil }
                railTo(railIndex(r.railLast.y, count: months.count), months: months, lifting: true)
            }
            return
        }
        guard !r.railOff else { return }
        guard rail != nil else {
            if hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y) > 10 { r.railMoved = true; r.railHoldTask?.cancel() }
            return
        }
        let m = railIndex(v.location.y, count: months.count)
        if m != rail { railTo(m, months: months, lifting: false) }
    }

    private func railEnded() {
        let r = scrub
        r.railHoldTask?.cancel()
        r.railStart = nil
        guard rail != nil else { return }
        r.railJustEnded = true
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); r.railJustEnded = false }
        withAnimation(.snappy(duration: CircleMotion.quick)) { rail = nil }
    }

    private func railTo(_ m: Int, months: [Date], lifting: Bool) {
        guard months.indices.contains(m) else { return }
        if lifting { withAnimation(.snappy(duration: CircleMotion.quick)) { rail = m } } else { rail = m }
        withAnimation(CircleMotion.wheelScrub) { position.scrollTo(id: months[m], anchor: .center) }
        let r = scrub
        r.railSettle?.cancel()
        r.railSettle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, rail == m || rail == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(id: months[m], anchor: .center) }
        }
    }

    @ViewBuilder private func railPill(months: [Date]) -> some View {
        if let m = rail, months.indices.contains(m),
           let start = stats.weeks.first(where: { $0.id == months[m] })?.month?.start {
            let h = max(scrub.gridHeight, 1)
            Text(start.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline).fontDesign(.rounded)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                .fixedSize()
                .offset(x: Self.labelColumn + 30, y: min(max((CGFloat(m) + 0.5) / CGFloat(months.count) * h - 15, 0), h - 30))
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - A week of rings

/// One week, expanded: the month's name (and its line) beside the week holding its 1st, then seven rings (JourneyDayCell, the
/// month page's). Equal rows aren't redrawn (the card's rows' way): its days, its pick, whether the focus touches it, its size.
struct JourneyExpandedRow: View, Equatable {
    let week: YourJourneyStats.Week
    /// Its place among the weeks (a hold reaches rows above and below from it).
    let index: Int
    let log: JourneyLog
    let today: Date
    let cell: CGFloat
    /// The card's tiles in place of the rings (pinched in).
    let tiles: Bool
    /// The month whose name sits on this row (its middle row), and whether it sits halfway down to the next (an even number
    /// of rows).
    let labelMonth: Date?
    let labelBetween: Bool
    let focus: Date?
    /// The picked day, if it's in this week.
    let picked: Date?
    let onDay: (Date) -> Void
    let onMonth: (Date) -> Void
    /// A hold on its days, then the finger's moves (in its days' space).
    let onHold: (UIGestureRecognizer.State, CGPoint) -> Void

    /// What the focus does to this row: nothing (-1, none), else which of its days are in it (bits 0–6) and whether its name
    /// is the focused month's (bit 7) — a focus moving between two other months leaves it as it was.
    private var focusMask: Int {
        guard let f = focus else { return -1 }
        var mask = labelMonth == f ? 1 << 7 : 0
        for i in 0..<7 where JourneyLog.monthStart(Calendar.current.date(byAdding: .day, value: i, to: week.start) ?? week.start) == f {
            mask |= 1 << i
        }
        return mask
    }

    static func == (a: Self, b: Self) -> Bool {
        a.week.start == b.week.start && a.index == b.index && a.log.version == b.log.version && a.today == b.today && a.cell == b.cell
            && a.tiles == b.tiles && a.labelMonth == b.labelMonth && a.labelBetween == b.labelBetween
            && a.picked == b.picked && a.focusMask == b.focusMask
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = JourneyPerf.body("expandedRow")
        let cal = Calendar.current
        let scale = cell / JourneyDayRing.size
        let height = tiles ? 11 : cell
        let excused = Excused.Days()
        HStack(spacing: 0) {
            label
                // Centred on its row, or on the gap below it when the month's rows are even.
                .offset(y: labelBetween ? (height + (tiles ? JourneyHomeCard.pitch - 11 : JourneyExpandedPage.rowGap)) / 2 : 0)
                .frame(width: JourneyExpandedPage.labelColumn - 8, height: height, alignment: .trailing)
                .padding(.trailing, 8)
            HStack(spacing: tiles ? 6 : 0) {
                ForEach(0..<7, id: \.self) { i in
                    let date = cal.date(byAdding: .day, value: i, to: week.start) ?? week.start
                    let day = log.day(date)
                    let noRows = date < today && log.days[PrayerNotificationID.dayKey(date)] == nil && excused.excludes(date)
                    // The ring and the card's tile, one over the other: a pinch fades one into the other as the row
                    // resizes — the tiles of the compact card, grown, and back.
                    ZStack {
                        JourneyDayCell(day: day, date: date, today: today, first: log.firstDay, usesExcused: log.usesExcused,
                                       excusedNoRows: noRows)
                            .scaleEffect(scale * (tiles ? 0.4 : 1))
                            // A scale isn't layout: unframed, each ring kept its 46 pt and the 7th column ran off a 17 Pro
                            // (the helper's check); in tiles mode it takes no room at all.
                            .frame(width: tiles ? 0 : cell, height: tiles ? 0 : cell)
                            .opacity(tiles ? 0 : 1)
                        tile(week.days[i])
                            .opacity(tiles ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .journeyFlightCell(date, scale: scale)   // the card's tiles land on it (JourneyTransitions.swift)
                    .opacity(focus.map { JourneyLog.monthStart(date) == $0 ? 1 : 0.22 } ?? 1)
                    .overlay {
                        if picked == date {
                            if tiles {
                                RoundedRectangle(cornerRadius: JourneyHomeCard.corner + 2.5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                    .padding(-3)
                            } else {
                                Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: cell + 2, height: cell + 2)
                            }
                        }
                    }
                    .contentShape(Rectangle().inset(by: tiles ? -1.5 : 0))
                    .onTapGesture { onDay(date) }
                }
            }
            // A finger resting on the days picks under it as it moves, across rows (the card's JourneyHoldPick: a quick drag
            // moves first, fails it, and the weeks scroll).
            .gesture(JourneyHoldPick(hold: JourneyHomeCard.holdTime) { state, p, _ in onHold(state, p) })
            .journeyFlightWeek(week.start, scale: scale)   // one place for its seven days (the flights work them out)
        }
    }

    /// The card's tile for a day (JourneyCardRow's bar): its kind and heat, an unmarked day its hairline; nothing outside the
    /// journey.
    @ViewBuilder private func tile(_ day: YourJourneyStats.GridDay?) -> some View {
        let shape = RoundedRectangle(cornerRadius: JourneyHomeCard.corner, style: .continuous)
        if let day {
            let dark = scheme == .dark
            shape.fill(JourneyTileColor.of(day.kind, rank: day.rank, dark: dark))
                .overlay {
                    if day.kind == .none { shape.strokeBorder(JourneyTileColor.outline(dark: dark), lineWidth: JourneyTileColor.outlineWidth) }
                }
                .frame(height: 11)
        } else {
            Color.clear.frame(height: 11)
        }
    }

    /// The month's name on its middle row, and how it went (owner: "the column label maybe gets some more data like
    /// what the year view labels for the months show"); marked while its month is in focus.
    @ViewBuilder private var label: some View {
        if let start = labelMonth {
            let on = focus == start
            let numbers = log.month(start)
            Button { onMonth(start) } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(name(start))
                        .font(.system(size: 13, weight: on ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .journeyFlightLabel(start)   // the card's name lands here (JourneyTransitions.swift)
                    if numbers.activeDays > 0, !tiles {
                        Text(numbers.activeDays == 1 ? "1 day" : "\(numbers.activeDays) days")
                        if let score = numbers.averageScore { Text("score \(score)") }
                    }
                }
                .font(.system(size: 10.5, weight: .light, design: .rounded))
                .foregroundStyle(on ? Color.primary.opacity(0.7) : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(start.formatted(.dateTime.month(.wide).year())), \(numbers.activeDays) days")
            .journeyFlightWords(.month)
        } else {
            Color.clear
        }
    }

    /// "Sep", with its year when it isn't this one ("Feb ’25") — the weeks run across years (the helper's check: after the
    /// rail, "Feb · 22 days" was 2025's with nothing saying so).
    private func name(_ start: Date) -> String {
        let month = start.formatted(.dateTime.month(.abbreviated))
        let year = Calendar.current.component(.year, from: start)
        guard year != Calendar.current.component(.year, from: today) else { return month }
        return "\(month) ’\(String(format: "%02d", year % 100))"
    }
}

// MARK: - A month's numbers

/// A focused month's top (the old month page's): its name, then days all in time · days with Qaza · average score, the first
/// two with the key's rings.
struct JourneyMonthNumbers: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let m = log.month(month)
        let withQaza = JourneyLog.daysOf(month: month).filter { JourneyHighlight.withQaza.matches(log.day($0)) }.count
        VStack(alignment: .leading, spacing: 8) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 22, weight: .regular, design: .rounded))
            HStack(alignment: .top, spacing: 0) {
                fact("\(m.allInTimeDays)", "days all in time", ring: true)
                fact("\(withQaza)", "days with Qaza", ring: false)
                fact(m.averageScore.map { "\($0)" } ?? "–", "average score", ring: nil)
            }
        }
    }

    private func fact(_ value: String, _ caption: String, ring inTime: Bool?) -> some View {
        let dark = scheme == .dark
        return VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            HStack(spacing: 4) {
                if let inTime {
                    Circle().fill(inTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
                        .padding(1.6)
                        .overlay(Circle().stroke(inTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: 1.1))
                        .frame(width: 10, height: 10)
                }
                Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
