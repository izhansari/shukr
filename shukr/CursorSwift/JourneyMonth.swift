import SwiftUI

// Journey's month (moved out of Journey.swift, 2026-10-16, so the calendar and Journey's page are separate files: the
// month page, its calendar of rings and one day's ring. Spec board/mocks/month-fifths/spec.md; the build
// board/mocks/journey-v6/build-plan.md).

struct JourneyMonthRoute: Hashable, Identifiable {
    let month: Date
    var id: Date { month }
}

// MARK: - A month

/// A month (Journey v6): its name — a tap zooms out to the year — "N days you marked a prayer", its three numbers in one flat
/// row between hairlines, and the calendar of rings (JourneyDayRing) with its key; a day opens the day page. Months page up
/// and down (drag down for the month before); Month | Year at the bottom and a pinch switch to the year (JourneyYearView).
/// Owner, 2026-10-16 (build-plan.md, decisions 1–2): "the chevrons for back and forward a month needs to change. instead
/// indicate that the month name (title on month page) can be tapped with an updown sf symbol … when tapped it just zooms out
/// to the year view". No grade colours here (spec month-fifths).
struct JourneyMonthPage: View {
    let log: JourneyLog
    @State var start: Date
    @Environment(\.circleTheme) private var theme
    @State private var openDay: JourneyDayRoute?
    /// A number tapped (owner, 2026-10-16: "tapping the days all in time, days with all five and average score, do the same
    /// thing we used to have earlier"): only its days lit on the calendar; again, off; one at a time; a new month clears it.
    @State private var focus: JourneyHighlight?
    /// The finger's travel up or down on the calendar (owner, 2026-10-16: months page up and down — Sami's sideways swipe
    /// turned 90°): the month before rides in from the top 1:1, this one leaves at 90 %.
    @State private var dragOffset: CGFloat = 0
    @State private var dragVertical: Bool?
    /// The year, in place of the month (the title, Month | Year, or a pinch).
    @State private var showYear = false
    @Environment(\.journeyDayOpener) private var dayOpener

    init(log: JourneyLog, start: Date) {
        self.log = log
        _start = State(initialValue: start)
    }

    private var today: Date { PrayerDay.start() }
    /// The months with a marked day, oldest first (‹ › skip the empty ones — a break's months).
    private var months: [Date] {
        guard let first = log.firstDay else { return [] }
        var out: [Date] = []
        var m = JourneyLog.monthStart(first)
        let last = JourneyLog.monthStart(today)
        while m <= last {
            if log.month(m).activeDays > 0 { out.append(m) }
            guard let next = Calendar.current.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return out
    }

    /// The month `by` away among the months with marks (nil: none that way).
    private func neighbour(_ by: Int) -> Date? {
        let list = months
        guard let at = list.firstIndex(of: start), list.indices.contains(at + by) else { return nil }
        return list[at + by]
    }
    /// The month the title and numbers name: the neighbour once it's more than half in.
    private var shownMonth: Date {
        if dragOffset < -travel / 2, let next = neighbour(1) { return next }
        if dragOffset > travel / 2, let previous = neighbour(-1) { return previous }
        return start
    }

    var body: some View {
        ZStack {
            if showYear {
                JourneyYearView(log: log, today: today, current: start, onPick: { month in
                    triggerSomeVibration(type: .light)
                    withAnimation(Self.zoom) { start = month; showYear = false }
                }, onSpread: {
                    withAnimation(Self.zoom) { showYear = false }   // a spread elsewhere: back into the month
                }, onDay: { open($0) })
                .transition(.opacity.combined(with: .scale(scale: 1.08)))
            } else {
                // Never a scroll (it took the up/down drag: a six-week month on a 17 Pro didn't fit and the page scrolled
                // instead of turning — Sami's check of 63c027c). The largest day size that fits the phone, down to 70 %.
                ViewThatFits(in: .vertical) {
                    page(scale: 1)
                    page(scale: 0.9)
                    page(scale: 0.8)
                    page(scale: 0.7)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .simultaneousGesture(MagnifyGesture().onEnded { v in
                    if v.magnification < 0.85 { withAnimation(Self.zoom) { showYear = true } }   // pinch in: the year
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            JourneySwitch(options: [("Month", "month"), ("Year", "year")],
                          selection: Binding(get: { showYear ? "year" : "month" },
                                             set: { v in withAnimation(Self.zoom) { showYear = v == "year" } }))
                .padding(.bottom, 6)
                .journeyFlightWords(.month)
        }
        .background(theme.surface.journeyFlightMonthSurface().ignoresSafeArea())   // clear while it opens over Journey
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
    }

    /// Month ↔ year: a calm zoom (the month shrinks away as the year settles in, and back).
    private static let zoom = Animation.easeInOut(duration: 0.35)

    private func page(scale: CGFloat) -> some View {
        let shown = shownMonth
        let numbers = log.month(shown)
        return VStack(alignment: .leading, spacing: 0) {
            // The month's name says it can be tapped (owner: "an updown sf symbol"): a tap zooms out to the year.
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(Self.zoom) { showYear = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(shown.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 30, weight: .regular, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .id(shown)
                        .transition(CircleMotion.dayPickSwap)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .journeyFlightTitle(shown)   // "Sep" on the card grows into it (JourneyTransitions.swift)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the year")
            VStack(alignment: .leading, spacing: 0) {
                Text(numbers.activeDays == 1 ? "1 day you marked a prayer" : "\(numbers.activeDays) days you marked a prayer")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                HStack(alignment: .top, spacing: 0) {
                    fact("\(numbers.allInTimeDays)", "days all in time", .allInTime)
                    fact("\(numbers.allFiveDays)", "days with all five", .allFive)
                    // The best day's score and date in its place while it's lit (as Journey's card did) — out, then in: a
                    // crossfade drew "96" and "100" over each other (Bradley's check).
                    Group {
                        if case .bestScore(let best) = focus {
                            let days = JourneyLog.daysOf(month: shown).filter { focus?.matches(log.day($0)) == true }
                            fact("\(best)", days.count == 1 ? "best · \(days[0].formatted(.dateTime.month(.abbreviated).day()))"
                                                          : "best · \(days.count) days", focus)
                        } else {
                            fact(numbers.averageScore.map { "\($0)" } ?? "–", "average score",
                                 numbers.bestDay.map { .bestScore($0.score) })
                        }
                    }
                    .id(focus.map { if case .bestScore = $0 { true } else { false } } ?? false)
                    .transition(CircleMotion.dayPickSwap)
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .padding(.top, 22)
            }
            .id(shown)
            .transition(CircleMotion.dayPickSwap)
            .journeyFlightWords(.month)
            calendars(scale: scale).padding(.top, 24 * scale)
            Text("Tap a day to open it.")
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .journeyFlightWords(.month)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .onChange(of: shown) { focus = nil }   // another month: its own days
    }

    /// The month's calendar between its neighbours, a page apart, moving with the finger (Journey's day pager: the one
    /// coming in rides 1:1, the one going out at 90 %, each fading and shrinking a little with its distance — never overlapping).
    private func calendars(scale: CGFloat) -> some View {
        let panes: [(k: Int, month: Date)] = [-1, 0, 1].compactMap { k in k == 0 ? (0, start) : neighbour(k).map { (k, $0) } }
        let height = JourneyCalendar.height(scale: scale)
        return ZStack(alignment: .top) {
            ForEach(panes, id: \.month) { pane in
                let place = calendarPlace(pane.k, height: height)
                JourneyCalendar(log: log, month: pane.month, today: today, scale: scale,
                                highlight: pane.k == 0 ? focus : nil,
                                onKey: { kind in
                                    triggerSomeVibration(type: .light)
                                    withAnimation(.easeOut(duration: CircleMotion.quick)) { focus = focus == kind ? nil : kind }
                                }) { open($0) }
                    .frame(height: height, alignment: .top)
                    .animation(.easeInOut(duration: 0.3), value: focus)
                    .modifier(DayPaneMotion(away: place.away))
                    .offset(y: place.y)
                    .allowsHitTesting(pane.k == 0)
            }
        }
        // Every month six weeks tall (as the year's small months): the page never changes height as a month swaps in.
        .frame(height: height, alignment: .top)
        .clipped()   // this month's own height: the neighbours wait a travel above and below, out of sight
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    /// How far a neighbour waits: the calendar's height and some room, out of sight above and below.
    private var travel: CGFloat { JourneyCalendar.height(scale: 1) + 60 }

    /// One travel at every scale (the drag's turn settles at `travel`), so the month coming in lands exactly in place.
    private func calendarPlace(_ k: Int, height: CGFloat) -> (y: CGFloat, away: CGFloat) {
        let h = travel
        let y: CGFloat
        if k == 0 {
            y = dragOffset * 0.9
        } else {
            let incoming = (k > 0 && dragOffset < 0) || (k < 0 && dragOffset > 0)
            y = CGFloat(k) * h + (incoming ? dragOffset : 0)
        }
        return (y, min(abs(y) / h, 1))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if dragVertical == nil {
                    // Up or down only; the left edge stays the system's back swipe.
                    dragVertical = v.startLocation.x > 20 && abs(v.translation.height) > abs(v.translation.width)
                }
                guard dragVertical == true else { return }
                let h = v.translation.height
                dragOffset = neighbour(h < 0 ? 1 : -1) != nil ? h : h * 0.15   // nothing that way: a little give
            }
            .onEnded { v in
                defer { dragVertical = nil }
                guard dragVertical == true else { return }
                let h = v.translation.height, projected = v.predictedEndTranslation.height
                let by = h < 0 ? 1 : -1   // drag up: the next month; down: the one before
                guard neighbour(by) != nil, abs(h) > travel / 4 || abs(projected) > travel / 2 else {
                    withAnimation(CircleMotion.daySlideIn) { dragOffset = 0 }
                    return
                }
                turn(by)
            }
    }

    /// The neighbour settles in on the spring, then becomes this page's month (its calendar stays — no reload).
    private func turn(_ by: Int) {
        guard let month = neighbour(by) else { return }
        triggerSomeVibration(type: .light)
        withAnimation(CircleMotion.daySlideIn) { dragOffset = by > 0 ? -travel : travel } completion: {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                start = month
                dragOffset = 0
            }
        }
    }

    /// A number; a tap lights its days (`kind`; nil: nothing to light). While another is on, it steps back.
    private func fact(_ value: String, _ caption: String, _ kind: JourneyHighlight?) -> some View {
        let on: Bool = {
            switch (focus, kind) {
            case (.bestScore?, .bestScore?): true
            case let (f?, k?): f == k
            default: false
            }
        }()
        return Button {
            guard let kind else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeOut(duration: CircleMotion.quick)) { focus = on ? nil : kind }
        } label: {
            VStack(spacing: 2) {
                Text(value).font(.system(size: 30, weight: .thin, design: .rounded)).monospacedDigit()
                // One size every month (a scale factor shrank September's and not August's, and the divider jumped while
                // paging — Bradley's check): 11 pt fits "days with all five" in a third of an SE.
                Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .opacity(focus == nil || on ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(kind == nil ? "" : on ? "Shows every day again" : "Lights these days on the calendar")
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        // Today opens only once it's over — all five marked (owner, 2026-10-15: the day page "doesn't show up in journey
        // unless the day is over or all 5 have been marked, so it never shows current prayers").
        guard date < today || log.day(date).allFive else { return }
        // Opened from the card: the day's ring grows into the day page (JourneyTransitions.swift); else a push.
        if let dayOpener { dayOpener.open(date); return }
        triggerSomeVibration(type: .light)
        openDay = JourneyDayRoute(date: date)
    }
}

// MARK: - The calendar

/// The month as a calendar of rings, one per day (JourneyDayRing; spec month-fifths).
private struct JourneyCalendar: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    /// The days' size (1 = JourneyDayRing.size): smaller where the page wouldn't fit (an SE; a six-week month on a 17 Pro).
    var scale: CGFloat = 1
    let highlight: JourneyHighlight?
    /// A legend item tapped: light only its days (again, all).
    var onKey: (JourneyHighlight) -> Void = { _ in }
    let onDay: (Date) -> Void

    /// Its height for a scale: the weekday letters, six weeks of days, the key (worked out, not measured, so the page's
    /// fit test never feeds on itself).
    static func height(scale: CGFloat) -> CGFloat {
        let letters: CGFloat = 14, rows = 6 * JourneyDayRing.size * scale + 5 * 2, key: CGFloat = 14 + 14
        return letters + 6 + rows + 6 + key
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    var body: some View {
        let cal = Calendar.current
        let days = JourneyLog.daysOf(month: month)
        let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
        // A past day an excused range covers with no rows at all (shukr wasn't opened during her period) is excused too: the
        // pause badge, as a day with rows (Bradley's check; the card already steps over such days, bd44ce4).
        let excused = Excused.Days()
        let excusedNoRows: (Date) -> Bool = { date in
            date < today && log.days[PrayerNotificationID.dayKey(date)] == nil && excused.excludes(date)
        }
        let hasExcused = days.contains { (log.usesExcused && log.day($0).marks.contains(.excused)) || excusedNoRows($0) }
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .journeyFlightWords(.month)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: JourneyDayRing.size * scale) }
                ForEach(days, id: \.self) { date in
                    let day = log.day(date)
                    JourneyDayCell(day: day, date: date, today: today, first: log.firstDay, usesExcused: log.usesExcused,
                                   excusedNoRows: excusedNoRows(date))
                        .scaleEffect(scale)
                        .frame(height: JourneyDayRing.size * scale)
                        .journeyFlightCell(date, scale: scale)   // the transitions (JourneyTransitions.swift)
                        .opacity(highlight.map { $0.matches(day) ? 1 : 0.22 } ?? 1)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onDay(date) }
                }
                // Six weeks always, so every month is the same height and the key never moves.
                ForEach(0..<max(0, 42 - lead - days.count), id: \.self) { _ in Color.clear.frame(height: JourneyDayRing.size * scale) }
            }
            HStack(spacing: 16) {
                // Owner, 2026-10-16: "change it to say in time with kaza and complete. And tapping any one focuses those rings."
                key(keyRing(inTime: true), "In time", .allInTime)
                key(keyRing(inTime: false), "With Qaza", .withQaza)
                key(keyFifths, "Incomplete", .incomplete)
                if hasExcused { key(ExcusedDayBadge(size: 10), "Excused") }
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 14)   // ~20 pt under the calendar with the stack's 6 (the canvas; Frank's check)
            .frame(maxWidth: .infinity)
            .journeyFlightWords(.month)
        }
    }

    private var weekdayLetters: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    @Environment(\.colorScheme) private var scheme
    /// The key's swatch: a closed day ring in small (green all in time; soft with a grey fill when one was a Qaza).
    private func keyRing(inTime: Bool) -> some View {
        let dark = scheme == .dark
        return Circle().fill(inTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
            .padding(1.6)
            .overlay(Circle().stroke(inTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: 1.1))
    }

    /// The key's "Incomplete": a ring of five fifths, the same size as the other two rings and in a prayed fifth's color
    /// (owner, 2026-10-16: "in the legend add the fifths as a ring saying "incomplete"", then on his phone: "this is hard
    /// to see and ring looks smaller than the others. copy the size of the outer rings … just use a color thats the same
    /// as a filled fifth"). The calendar's own unfinished days keep Bradley's strengths.
    private var keyFifths: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let arc = JourneyDayRing.fifth(i)
                Circle().trim(from: arc.from, to: arc.to)
                    .stroke(JourneyDayRing.soft(scheme == .dark), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    /// A legend item: a tap lights its days on the calendar; while another one (or a number) is on, it steps back.
    private func key<V: View>(_ swatch: V, _ title: String, _ kind: JourneyHighlight? = nil) -> some View {
        let on = kind != nil && highlight == kind
        return Button { if let kind { onKey(kind) } } label: {
            // A bigger hit area without growing the legend: the calendar's height is worked out (JourneyCalendar.height),
            // and padding here pushed the key under its clip (the owner saw it cut in half).
            HStack(spacing: 5) { swatch.frame(width: 12, height: 12); Text(title) }
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .disabled(kind == nil)   // Excused: a label only
        .opacity(highlight == nil || on ? 1 : 0.4)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(kind == nil ? "" : on ? "Shows every day again" : "Lights these days on the calendar")
    }
}

/// One day as a ring (spec board/mocks/month-fifths/spec.md, locked 2026-10-16 — owner: "It's F2 and thinner at 1.8"),
/// drawn in a 44-unit square scaled to `JourneyDayRing.size`: everything due prayed → a closed ring with a fill (green, all
/// in time — Late counts, excused counts as done; soft with a grey fill when one was a Qaza); not finished → its fifths, Fajr
/// at the top, clockwise, a prayed fifth soft and a missed one a faint track; today keeps its fifths until it's over (nothing
/// for prayers still to come) with a dot under its number. The fifths are what the day page's ring grows from.
enum JourneyDayRing {
    static let size: CGFloat = 46
    static let k = size / 44
    static let radius = 15.5 * k, band = 1.8 * k, fill = 12.1 * k, number = 12.5 * k
    /// Each fifth 72°, a 14° gap between them.
    static func fifth(_ i: Int) -> (from: CGFloat, to: CGFloat) { (CGFloat(i * 72 + 7) / 360, CGFloat((i + 1) * 72 - 7) / 360) }
    static func green(_ dark: Bool) -> Color { dark ? Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255) : Color(red: 0x28 / 255, green: 0xA7 / 255, blue: 0x45 / 255) }
    static func soft(_ dark: Bool) -> Color { dark ? .white.opacity(0.40) : .black.opacity(0.36) }
    static func strong(_ dark: Bool) -> Color { dark ? .white.opacity(0.78) : .black.opacity(0.70) }
    static func track(_ dark: Bool) -> Color { dark ? .white.opacity(0.14) : .black.opacity(0.12) }
    static func greyFill(_ dark: Bool) -> Color { dark ? .white.opacity(0.10) : .black.opacity(0.14) }
}

private struct JourneyDayCell: View {
    let day: JourneyLog.Day
    let date: Date
    let today: Date
    let first: Date?
    let usesExcused: Bool
    /// No rows, but an excused range covers it: excused all day.
    var excusedNoRows = false
    @Environment(\.colorScheme) private var scheme
    /// The transitions (JourneyTransitions.swift): how much of its ring, number and fill to draw while the month opens or
    /// a day's ring flies from it; all of it otherwise.
    @Environment(\.journeyCellDraw) private var cellDraw

    var body: some View {
        let future = date > today
        let before = first.map { date < $0 } ?? true
        let isToday = date == today
        let dark = scheme == .dark
        let excusedAllDay = (usesExcused && day.excusedDay && !day.active) || excusedNoRows
        let drawn = !future && !before && day.active
        ZStack {
            if drawn {
                if day.allFive && !isToday {
                    Circle().fill(day.allInTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
                        .frame(width: JourneyDayRing.fill * 2, height: JourneyDayRing.fill * 2)
                        .opacity(cellDraw.fill)
                    Circle().trim(from: 0, to: cellDraw.ring)
                        .stroke(day.allInTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: JourneyDayRing.band)
                        .rotationEffect(.degrees(-90))   // drawn closed from the top (the transitions)
                        .frame(width: JourneyDayRing.radius * 2, height: JourneyDayRing.radius * 2)
                } else {
                    ForEach(0..<5, id: \.self) { i in fifth(i, today: isToday, dark: dark) }
                }
            }
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: JourneyDayRing.number, weight: isToday ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(future ? Color.secondary.opacity(0.55) : drawn || isToday ? Color.primary : Color.secondary.opacity(0.85))
                .offset(y: isToday ? -2.2 * JourneyDayRing.k : 0)
                .opacity(cellDraw.number)
            if isToday {
                Circle().fill(Color.primary).frame(width: 3 * JourneyDayRing.k, height: 3 * JourneyDayRing.k)
                    .offset(y: 7.6 * JourneyDayRing.k)
                    .opacity(cellDraw.number)
            } else if excusedAllDay {
                ExcusedDayBadge(size: 9.2 * JourneyDayRing.k).offset(y: 13 * JourneyDayRing.k).opacity(cellDraw.number)
            }
        }
        .frame(width: JourneyDayRing.size, height: JourneyDayRing.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// A prayer's fifth: prayed (or excused) soft — today's a little stronger — missed a faint track; nothing for one to come.
    @ViewBuilder private func fifth(_ i: Int, today: Bool, dark: Bool) -> some View {
        let mark = day.marks[i]
        let color: Color? = switch mark {
        case .done, .excused: today ? JourneyDayRing.strong(dark) : JourneyDayRing.soft(dark)
        case .missed: JourneyDayRing.track(dark)
        case .toCome, .none: nil
        }
        if let color {
            let arc = JourneyDayRing.fifth(i)
            Circle().trim(from: arc.from, to: arc.from + (arc.to - arc.from) * cellDraw.ring)
                .stroke(color, style: StrokeStyle(lineWidth: JourneyDayRing.band, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: JourneyDayRing.radius * 2, height: JourneyDayRing.radius * 2)
        }
    }

    private var accessibility: String {
        let d = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard day.active else { return d }
        return "\(d): \(day.prayed) of 5 prayed" + (day.allInTime ? ", all in time" : "")
    }
}
