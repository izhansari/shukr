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
    @State private var extraTap: JourneyExtraTap?
    /// The month rail (hold the names' column, as on the card): the month the finger's on.
    @State private var rail: Int?
    @State private var scrub = JourneyCardScrub()
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
    private var cell: CGFloat {
        let w = gridWidth > 0 ? gridWidth : UIScreen.main.bounds.width - 40
        return min(((w - Self.labelColumn) / 7).rounded(.down), JourneyDayRing.size)
    }

    var body: some View {
        let _ = JourneyPerf.body("expanded")
        ZStack {
            if showYear {
                JourneyYearView(log: log, today: today, current: focus ?? opened, onPick: { m in
                    triggerSomeVibration(type: .light)
                    fromYear(to: m)   // a small month's tap: back to the weeks with it in focus
                }, onSpread: { fromYear(to: nil) }, onDay: { open($0) })
                .modifier(JourneyYearFlightDriver(dials: yearDials, flight: nil, clearWhenIdle: true))
            } else {
                // The opening month's tiles landing from the card, under its rings.
                JourneyFlyingTiles()
                VStack(spacing: 0) {
                    top
                    hairline
                    grid
                    hairline
                    bottom
                }
            }
        }
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
        // Where the card's flight lands its words (the host runs once this is laid out).
        .journeyFlightTitleSlot(opened)
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
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Self.rowGap) {
                ForEach(stats.weeks) { week in
                    JourneyExpandedRow(week: week, log: log, today: today, cell: cell,
                                       focus: focus, picked: picked.flatMap { p in week.days.contains { $0?.date == p } ? p : nil },
                                       onDay: { pick($0) }, onMonth: { focusMonth($0) })
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

    private func toYear() {
        JourneyPerf.began("year opens")
        picked = nil
        JourneyFlightGeometry.shared.yearShowing = true
        // The host's ‹ and edge swipe: back to the weeks, not the card.
        JourneyFlightGeometry.shared.yearBack = { fromYear(to: nil) }
        withAnimation(.easeInOut(duration: CircleMotion.standard)) { showYear = true }
    }

    /// Back to the weeks from the year: ‹, the toggle or a spread as they were (no focus — only a tap focuses); a small
    /// month's tap with that month in focus, in the middle.
    private func fromYear(to m: Date?) {
        JourneyPerf.began("weeks from year")
        JourneyFlightGeometry.shared.yearShowing = false
        JourneyFlightGeometry.shared.yearBack = nil
        withAnimation(.easeInOut(duration: CircleMotion.standard)) {
            showYear = false
            picked = nil
            focus = m
        }
        if let m, let week = stats.weeks.first(where: { $0.month?.start == m })?.id {
            DispatchQueue.main.async {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { position.scrollTo(id: week, anchor: .center) }
            }
        }
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
    let log: JourneyLog
    let today: Date
    let cell: CGFloat
    let focus: Date?
    /// The picked day, if it's in this week.
    let picked: Date?
    let onDay: (Date) -> Void
    let onMonth: (Date) -> Void

    /// What the focus does to this row: nothing (-1, none), else which of its days are in it (bits 0–6) and whether its name
    /// is the focused month's (bit 7) — a focus moving between two other months leaves it as it was.
    private var focusMask: Int {
        guard let f = focus else { return -1 }
        var mask = week.month?.start == f ? 1 << 7 : 0
        for i in 0..<7 where JourneyLog.monthStart(Calendar.current.date(byAdding: .day, value: i, to: week.start) ?? week.start) == f {
            mask |= 1 << i
        }
        return mask
    }

    static func == (a: Self, b: Self) -> Bool {
        a.week.start == b.week.start && a.log.version == b.log.version && a.today == b.today && a.cell == b.cell
            && a.picked == b.picked && a.focusMask == b.focusMask
    }

    var body: some View {
        let _ = JourneyPerf.body("expandedRow")
        let cal = Calendar.current
        let scale = cell / JourneyDayRing.size
        let excused = Excused.Days()
        HStack(spacing: 0) {
            label
                .frame(width: JourneyExpandedPage.labelColumn - 8, height: cell, alignment: .topTrailing)
                .padding(.trailing, 8)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let date = cal.date(byAdding: .day, value: i, to: week.start) ?? week.start
                    let day = log.day(date)
                    let noRows = date < today && log.days[PrayerNotificationID.dayKey(date)] == nil && excused.excludes(date)
                    JourneyDayCell(day: day, date: date, today: today, first: log.firstDay, usesExcused: log.usesExcused,
                                   excusedNoRows: noRows)
                        .scaleEffect(scale)
                        .frame(width: cell, height: cell)
                        .journeyFlightCell(date, scale: scale)   // the card's tiles land on it (JourneyTransitions.swift)
                        .opacity(focus.map { JourneyLog.monthStart(date) == $0 ? 1 : 0.22 } ?? 1)
                        .overlay {
                            if picked == date {
                                Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: cell + 2, height: cell + 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onDay(date) }
                }
            }
            .journeyFlightWeek(week.start, scale: scale)   // one place for its seven days (the flights work them out)
        }
    }

    /// The month's name on the week holding its 1st, and how it went (owner: "the column label maybe gets some more data like
    /// what the year view labels for the months show"); marked while its month is in focus.
    @ViewBuilder private var label: some View {
        if let m = week.month {
            let on = focus == m.start
            let numbers = log.month(m.start)
            Button { onMonth(m.start) } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(name(m.start))
                        .font(.system(size: 13, weight: on ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                    if numbers.activeDays > 0 {
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
            .accessibilityLabel("\(m.start.formatted(.dateTime.month(.wide).year())), \(numbers.activeDays) days")
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
