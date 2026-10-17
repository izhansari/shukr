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
    /// turned 90°): every month in the window moves with it 1:1. Kept off the page's state, so a drag frame moves the
    /// months and redraws none of them.
    @State private var drag = JourneyMonthDrag()
    @State private var dragVertical: Bool?
    /// The month the title and numbers name while a drag has another month nearer the middle (nil: `start`).
    @State private var shownOverride: Date?
    /// The window's height (the room between the numbers and Month | Year).
    @State private var windowHeight: CGFloat = 0
    /// The year, in place of the month (the title, Month | Year, or a pinch).
    @State private var showYear = false
    /// Month ↔ year (owner, 2026-10-16: "i didnt see the transition for month to year"): the month's days fly home into its
    /// small month in the year and back, on this dial (1 = the month) — JourneyTransitions.swift's flight, aimed at the year.
    @State private var yearFlight: JourneyMonthFlight?
    @State private var yearDials = JourneyMonthDial()
    /// The year laid out but its flight not set yet (a frame or two): the month stays up and the year hidden — without it the
    /// whole year showed for a frame first.
    @State private var yearWaiting = false
    /// The days' size the page shows (1 / 0.9 / 0.8 / 0.7), picked by the still copy below.
    @State private var dayScale: CGFloat = 1
    /// A day picked on the calendar: its top in place of the month's numbers, its things at the bottom — the card's way
    /// (owner, 2026-10-17: "make this month calendar view be an extension of the card view … clicking on … a ring, shows us
    /// that same top area information and bottom area information").
    @State private var picked: Date?
    @State private var extraTap: JourneyExtraTap?
    @Environment(\.journeyDayOpener) private var dayOpener
    /// A day open over the month (its ring flew to the day page): the toolbar is the day's then.
    @Environment(\.journeyMonthOpen) private var monthOpen

    init(log: JourneyLog, start: Date) {
        self.log = log
        _start = State(initialValue: start)
        months = Self.monthsWithMarks(log)
    }

    /// The last list and the log it came from (a page is rebuilt whenever Journey's host redraws — at the start of every
    /// flight back — and this ran each time: ~75 ms on his 13 Pro Max).
    @MainActor private static var monthsCache: (key: [AnyHashable], months: [Date])?

    @MainActor private static func monthsWithMarks(_ log: JourneyLog) -> [Date] {
        let today = PrayerDay.start()
        let key: [AnyHashable] = [log.firstDay, log.days.count, today, log.month(JourneyLog.monthStart(today)).activeDays]
        if let c = monthsCache, c.key == key { return c.months }
        let months = computeMonths(log)
        monthsCache = (key, months)
        return months
    }

    private static func computeMonths(_ log: JourneyLog) -> [Date] {
        guard let first = log.firstDay else { return [] }
        var out: [Date] = []
        var m = JourneyLog.monthStart(first)
        let last = JourneyLog.monthStart(PrayerDay.start())
        while m <= last {
            if log.month(m).activeDays > 0 { out.append(m) }
            guard let next = Calendar.current.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return out
    }

    private var today: Date { PrayerDay.start() }
    /// The months with a marked day, oldest first (‹ › skip the empty ones — a break's months). Worked out once per page: as
    /// a computed property it ran every month since the first day through `log.month` each time it was read (a Time Profiler
    /// trace on his 13 Pro Max: the month page's biggest cost of its own).
    private let months: [Date]

    /// The month `by` away among the months with marks (nil: none that way).
    private func neighbour(_ by: Int) -> Date? {
        let list = months
        guard let at = list.firstIndex(of: start), list.indices.contains(at + by) else { return nil }
        return list[at + by]
    }
    /// The month the title and numbers name: the neighbour once it's more than half in.
    private var shownMonth: Date { shownOverride ?? start }

    var body: some View {
        ZStack {
            if showYear {
                JourneyYearView(log: log, today: today, current: start, onPick: { month in
                    triggerSomeVibration(type: .light)
                    toMonth(month)
                }, onSpread: {
                    toMonth(start)   // a spread elsewhere: back into the month
                }, onDay: { open($0) })
                // Idle, the year sees no flight (a card's or a day's never fades it); in a month ↔ year flight, this one.
                .modifier(JourneyYearFlightDriver(dials: yearDials, flight: yearFlight, clearWhenIdle: true))
                .opacity(yearWaiting ? 0 : 1)
            }
            // The open month's tiles landing (from the card or the year), under its rings and numbers.
            JourneyFlyingTiles()
            if !showYear || yearFlight != nil || yearWaiting {
                // Never a scroll (it took the up/down drag: a six-week month on a 17 Pro didn't fit and the page scrolled
                // instead of turning — Sami's check of 63c027c). The largest day size that fits the phone, down to 70 %.
                // The size is picked on a still, hidden copy and the page shown at it: a ViewThatFits on screen re-measured
                // all four sizes on every frame of a transition and rebuilt the three calendars each time (~75 rebuilds an
                // opening; his 13 Pro Max ran card → month at ~40 of 70 frames).
                ZStack(alignment: .top) {
                    ViewThatFits(in: .vertical) {
                        page(scale: 1, live: false).onAppear { dayScale = 1 }
                        page(scale: 0.9, live: false).onAppear { dayScale = 0.9 }
                        page(scale: 0.8, live: false).onAppear { dayScale = 0.8 }
                        page(scale: 0.7, live: false).onAppear { dayScale = 0.7 }
                    }
                    .modifier(JourneyFlightStill())
                    page(scale: dayScale)
                }
                .simultaneousGesture(MagnifyGesture().onEnded { v in
                    if v.magnification < 0.85 { toYear() }   // pinch in: the year
                })
                .allowsHitTesting(yearFlight == nil)
            }
        }
        .modifier(JourneyYearFlightDriver(dials: yearDials, flight: yearFlight, clearWhenIdle: false))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The bottom is the picked day's things (the card's bottom); room kept for it, so nothing moves as a day is picked.
        .safeAreaInset(edge: .bottom) {
            ZStack(alignment: .top) {
                if let p = picked, !showYear {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).transition(.opacity)   // its line over it
                    JourneyDayExtrasRow(date: p) { extraTap = $0 }
                        .padding(.top, 12)
                        .id(p)
                        .transition(.opacity)
                }
            }
            .frame(height: 58, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .journeyFlightWords(.month)
        }
        // Month | Year up on the back button's row, out of the bottom's way ("maybe we move the month and year switcher to
        // the top right in the top bar. To make space for a bottom area").
        // Always there and only faded: the bar's own glass behind it is off, so nothing of it shows but the switch, which
        // comes and goes with the month's words — it was an empty glass pill popping in at the end of card → month and
        // staying ~0.5 s after month → card, and the switch popping back when a day opened here closed (sim recording).
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { monthYearSwitch }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { monthYearSwitch }
            }
        }
        .modifier(JourneyExtrasPresenter(tap: $extraTap))
        .background(theme.surface.journeyFlightMonthSurface().ignoresSafeArea())   // clear while it opens over Journey
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
    }

    /// Out to the year: the year laid out under the month, the month's days go home into its small month there, the year's
    /// words and other months arrive (the card's opening, run backwards from the year).
    /// Month | Year in the bar. Not over a day opened from here (it opens in place, so the bar stays this page's): it
    /// fades out as the day comes in and back as it goes.
    private var monthYearSwitch: some View {
        let dayUp = monthOpen?.hiddenDay != nil
        return JourneySwitch(options: [("Month", "month"), ("Year", "year")],
                             selection: Binding(get: { showYear ? "year" : "month" },
                                                set: { v in if v == "year" { toYear() } else { toMonth(start) } }))
            .journeyFlightWords(.month)
            .opacity(dayUp ? 0 : 1)
            .allowsHitTesting(!dayUp)
            .animation(.easeInOut(duration: 0.3), value: dayUp)
    }

    private func toYear() {
        guard !showYear, yearFlight == nil else { return }
        JourneyPerf.began("year opens")   // the year's build: its own window (the flight's begins once it's ready)
        picked = nil   // the year has its own picks
        triggerSomeVibration(type: .light)
        let month = shownMonth
        // Fresh places for the year (the last time's may be stale), and the host's ‹ fades from here.
        JourneyFlightGeometry.shared.yearGrids = [:]
        JourneyFlightGeometry.shared.yearNames = [:]
        JourneyFlightGeometry.shared.yearShowing = true
        JourneyFlightGeometry.shared.yearBack = { toMonth(start) }   // the host's ‹ and edge swipe: back into this month
        yearWaiting = true
        showYear = true
        JourneyFlightGeometry.shared.whenYearReady(month) {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            yearDials.set(.month, 1)
            withTransaction(quiet) {
                start = month; yearFlight = .fromYear(month, log: log, today: today); yearWaiting = false
            }
            let run = JourneyFrameLog.shared.start("month → year")
            yearDials.animate(.month, to: 0, duration: JourneyMotion.monthDuration) {
                JourneyFrameLog.shared.stop(run: run)
                // The month's pages come down a beat after the days have landed, when nothing moves: at the landing frame
                // their teardown held the last frame for ~230 ms (sim).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { yearFlight = nil }
            }
        }
    }

    /// Into a month from the year: its small month's squares grow into its days, as from the card.
    private func toMonth(_ month: Date) {
        guard showYear, yearFlight == nil else { return }
        JourneyPerf.began("month from year")   // the month's build: its own window (the flight's begins at its title)
        var quiet = Transaction()
        quiet.disablesAnimations = true
        yearDials.set(.month, 0)
        withTransaction(quiet) { start = month; yearFlight = .fromYear(month, log: log, today: today) }
        JourneyFlightGeometry.shared.afterTitle {
            let run = JourneyFrameLog.shared.start("year → month")
            yearDials.animate(.month, to: 1, duration: JourneyMotion.monthDuration) {
                JourneyFrameLog.shared.stop(run: run)
                showYear = false
                yearFlight = nil
                JourneyFlightGeometry.shared.yearShowing = false
                JourneyFlightGeometry.shared.yearBack = nil
            }
        }
    }

    /// `live`: the page on screen. The still copy that picks the size (`dayScale`) lays out the same frame with no months in
    /// its window and measures nothing.
    private func page(scale: CGFloat, live: Bool = true) -> some View {
        JourneyPerf.body("monthPage")
        let shown = shownMonth
        let numbers = log.month(shown)
        let withQaza = JourneyLog.daysOf(month: shown).filter { JourneyHighlight.withQaza.matches(log.day($0)) }.count
        return VStack(alignment: .leading, spacing: 0) {
            // The month's name says it can be tapped (owner: "an updown sf symbol"): a tap zooms out to the year.
            Button {
                toYear()
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
            let dayShown = picked.map { YourJourneyStats.GridDay.of(log, $0) }
            ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(numbers.activeDays == 1 ? "1 day you marked a prayer" : "\(numbers.activeDays) days you marked a prayer")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                // The numbers carry the key's rings (owner, 2026-10-17, option 1: "I like that a lot"): the legend line under
                // the calendar went, its room to the months around this one. The middle number is the grey ring's days —
                // all five with a Qaza among them (it counted every day with all five).
                HStack(alignment: .top, spacing: 0) {
                    fact("\(numbers.allInTimeDays)", "days all in time", .allInTime) { keyRing(inTime: true) }
                    fact("\(withQaza)", "days with Qaza", .withQaza) { keyRing(inTime: false) }
                    // The best day's score and date in its place while it's lit (as Journey's card did) — out, then in: a
                    // crossfade drew "96" and "100" over each other (Bradley's check).
                    Group {
                        if case .bestScore(let best) = focus {
                            let days = JourneyLog.daysOf(month: shown).filter { focus?.matches(log.day($0)) == true }
                            fact("\(best)", days.count == 1 ? "best · \(days[0].formatted(.dateTime.month(.abbreviated).day()))"
                                                          : "best · \(days.count) days", focus) { EmptyView() }
                        } else {
                            fact(numbers.averageScore.map { "\($0)" } ?? "–", "average score",
                                 numbers.bestDay.map { .bestScore($0.score) }) { EmptyView() }
                        }
                    }
                    .id(focus.map { if case .bestScore = $0 { true } else { false } } ?? false)
                    .transition(CircleMotion.dayPickSwap)
                }
                // Close under its top line (owner, 2026-10-17: "a lot of space between the header's gray line and the
                // beginning of the legends stuff"; was 16 both ways).
                .padding(.top, 9).padding(.bottom, 13)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .padding(.top, 22)
            }
            // A picked day takes this place (the card's top): the month's line and numbers stay underneath, unseen, so the
            // calendar never moves.
            .opacity(dayShown == nil ? 1 : 0)
            .allowsHitTesting(dayShown == nil)
                if let d = dayShown {
                    JourneyDayTop(day: d, log: log, canOpen: d.prayed > 0 && opens(d.date)) { open(d.date) }
                        .padding(.top, 14)
                        .id(d.date)
                        .transition(.opacity)
                }
            }
            // The day's area ends on a line (owner, 2026-10-17: "let's put like separators or something. So that the top area
            // and the bottom area have like a dedicated space") — where the numbers' own bottom line sits, so it never moves.
            .overlay(alignment: .bottom) {
                if dayShown != nil { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).transition(.opacity) }
            }
            .id(shown)
            .transition(CircleMotion.dayPickSwap)
            .journeyFlightWords(.month)
            // The weekday letters stay put over the window; the months move under them.
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, Self.railGutter)
            .padding(.top, 18 * scale)
            .journeyFlightWords(.month)
            calendars(scale: scale, live: live).padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onChange(of: shown) { focus = nil; picked = nil }   // another month: its own days   // another month: its own days
    }

    static var weekdayLetters: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: The months in their window

    /// Room on the right for the month rail.
    static let railGutter: CGFloat = 30
    /// Between one month's last week and the next one's name.
    static let monthGap: CGFloat = 26
    /// The window's top and bottom fade: never over the month in the middle, which the window always has room for.
    static let edge: CGFloat = 24

    /// The least room above and below the month in the middle. Less than the fade: on an SE the fade only brushes the
    /// month's small name, never a week.
    static let room: CGFloat = 16

    /// The window needs this month at its tallest (six weeks) and a little room above and below; the neighbours show in
    /// whatever is left (a sliver on an SE — asking for more pushed the page's title under the back button there, and with
    /// the picked day's 58 pt row at the bottom it cut that row's words off the screen).
    static func windowNeeds(scale: CGFloat) -> CGFloat {
        JourneyCalendar.height(weeks: 6, scale: scale) + 2 * room
    }

    /// The months around this one, in place: this one in the middle of the window, its neighbours a gap above and below
    /// — their edges show, faded (owner, 2026-10-17: "I also want it so that the neighboring months are like kind of in
    /// view and faded out") — two each way so a turn never pops one in. The finger moves them all 1:1 (JourneyMonthDrag:
    /// only the panes' places read it, so a drag frame redraws no calendar).
    private func panes(scale: CGFloat) -> [(k: Int, month: Date, y: CGFloat, height: CGFloat)] {
        let window = windowHeight
        var out: [(k: Int, month: Date, y: CGFloat, height: CGFloat)] = []
        let h0 = JourneyCalendar.height(month: start, scale: scale)
        let y0 = ((window - h0) / 2).rounded()
        out.append((0, start, y0, h0))
        var y = y0 + h0
        for k in [1, 2] {
            guard let m = neighbour(k) else { break }
            let h = JourneyCalendar.height(month: m, scale: scale)
            out.append((k, m, y + Self.monthGap, h))
            y += Self.monthGap + h
        }
        y = y0
        for k in [-1, -2] {
            guard let m = neighbour(k) else { break }
            let h = JourneyCalendar.height(month: m, scale: scale)
            y -= Self.monthGap + h
            out.append((k, m, y, h))
        }
        return out
    }

    /// How far the months move to bring `k`'s month to the middle (where this one sits at rest).
    private func distance(to k: Int, scale: CGFloat) -> CGFloat? {
        guard let pane = panes(scale: scale).first(where: { $0.k == k }) else { return nil }
        let window = windowHeight
        return ((window - pane.height) / 2).rounded() - pane.y
    }

    private func calendars(scale: CGFloat, live: Bool) -> some View {
        Color.clear
            .frame(minHeight: Self.windowNeeds(scale: scale), maxHeight: .infinity)
            .padding(.trailing, Self.railGutter)
            .overlay(alignment: .top) {
                if live {
                    ZStack(alignment: .top) {
                        ForEach(panes(scale: scale), id: \.month) { pane in
                            JourneyCalendar(log: log, month: pane.month, today: today, scale: scale,
                                            current: pane.k == 0, highlight: pane.k == 0 ? focus : nil,
                                            picked: pane.k == 0 ? picked : nil) { pick($0) }
                                .frame(height: pane.height, alignment: .top)
                                .animation(.easeInOut(duration: 0.3), value: focus)
                                .modifier(JourneyMonthPaneSlot(drag: drag, y: pane.y, height: pane.height, window: windowHeight))
                                .allowsHitTesting(pane.k == 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // A faded neighbour's tap turns to it, as a swipe would (owner, 2026-10-17: "if I click on the faded
                    // out neighbors, it scrolls me to that month"). One catcher for the window, by where the tap lands: a
                    // catcher on each neighbour stayed where the pane was laid out, not where its offset drew it (a tap on
                    // September went to August; one below did nothing). The middle month's days keep their own taps.
                    .contentShape(Rectangle())
                    .onTapGesture { p in
                        guard let pane = panes(scale: scale).first(where: { $0.k != 0 && p.y >= $0.y && p.y <= $0.y + $0.height })
                        else { return }
                        turn(pane.k, scale: scale)
                    }
                    .padding(.trailing, Self.railGutter)
                    .clipped()
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.edge)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.edge)
                        }
                    }
                    .journeyFlightWords(.month)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                if live, abs(h - windowHeight) > 0.5 { windowHeight = h }
            }
            .contentShape(Rectangle())
            .gesture(swipe(scale: scale))
            .overlay(alignment: .trailing) {
                if live && months.count > 1 {
                    // The month rail (owner, 2026-10-17: "Yeah, I like A … we should definitely keep that somewhere"):
                    // a dot per month with marks, older above, as To make up's scrubber.
                    JourneyMonthRail(months: months, current: shownMonth, height: windowHeight) { month in
                        guard month != start else { return }
                        var quiet = Transaction()
                        quiet.disablesAnimations = true
                        withTransaction(quiet) {
                            drag.offset = 0
                            shownOverride = nil
                            start = month
                        }
                    }
                    .padding(.trailing, -12)
                    .journeyFlightWords(.month)
                }
            }
    }

    private func swipe(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if dragVertical == nil {
                    // Up or down only; the left edge stays the system's back swipe.
                    dragVertical = v.startLocation.x > 20 && abs(v.translation.height) > abs(v.translation.width)
                    if dragVertical == true { JourneyPerf.began("month drag") }
                }
                guard dragVertical == true else { return }
                let h = v.translation.height
                drag.offset = neighbour(h < 0 ? 1 : -1) != nil ? h : h * 0.15   // nothing that way: a little give
                // The title and numbers follow the month nearest the middle (once a neighbour is more than half in).
                let near: Date? = {
                    if h < 0, let d = distance(to: 1, scale: scale), -h > -d / 2 { return neighbour(1) }
                    if h > 0, let d = distance(to: -1, scale: scale), h > d / 2 { return neighbour(-1) }
                    return nil
                }()
                if near != shownOverride { shownOverride = near }
            }
            .onEnded { v in
                defer { dragVertical = nil }
                guard dragVertical == true else { return }
                let h = v.translation.height, projected = v.predictedEndTranslation.height
                let by = h < 0 ? 1 : -1   // drag up: the next month; down: the one before
                guard let d = distance(to: by, scale: scale), abs(h) > abs(d) / 4 || abs(projected) > abs(d) / 2 else {
                    withAnimation(CircleMotion.daySlideIn) { drag.offset = 0 }
                    shownOverride = nil
                    return
                }
                turn(by, scale: scale)
            }
    }

    /// The neighbour settles into the middle on the spring, then becomes this page's month (its calendar stays — no reload).
    private func turn(_ by: Int, scale: CGFloat) {
        guard let month = neighbour(by), let d = distance(to: by, scale: scale) else { return }
        JourneyPerf.began("month turn")
        triggerSomeVibration(type: .light)
        shownOverride = month
        withAnimation(CircleMotion.daySlideIn) { drag.offset = d } completion: {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                start = month
                drag.offset = 0
                shownOverride = nil
            }
        }
    }

    @Environment(\.colorScheme) private var scheme
    /// A number's ring (the key's swatch): a closed day ring in small, green all in time, soft with a grey fill with a Qaza.
    private func keyRing(inTime: Bool) -> some View {
        let dark = scheme == .dark
        return Circle().fill(inTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
            .padding(1.6)
            .overlay(Circle().stroke(inTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: 1.1))
            .frame(width: 10, height: 10)
    }

    /// A number; a tap lights its days (`kind`; nil: nothing to light). While another is on, it steps back.
    private func fact<G: View>(_ value: String, _ caption: String, _ kind: JourneyHighlight?,
                               @ViewBuilder glyph: () -> G) -> some View {
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
                HStack(spacing: 4) {
                    glyph()
                    Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(focus == nil || on ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(kind == nil ? "" : on ? "Shows every day again" : "Lights these days on the calendar")
    }

    /// A day tapped on the calendar: picked (its top and things show), again let go — as a card tile. Its top opens it.
    private func pick(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        JourneyPerf.began("month pick")
        triggerSomeVibration(type: .light)
        withAnimation(.easeOut(duration: CircleMotion.quick)) {
            picked = picked == date ? nil : date
            focus = nil
        }
    }

    /// A day page opens for a day that's over, or today once all five are marked.
    private func opens(_ date: Date) -> Bool {
        guard let first = log.firstDay, date >= first, date <= today else { return false }
        return date < today || log.day(date).allFive
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        // Today opens only once it's over — all five marked (owner, 2026-10-15: the day page "doesn't show up in journey
        // unless the day is over or all 5 have been marked, so it never shows current prayers").
        guard date < today || log.day(date).allFive else { return }
        // Opened from the card: the day's ring grows into the day page (JourneyTransitions.swift); else a push.
        if let dayOpener { dayOpener.open(date); return }
        // No tick: its callers (the day's top, the year's day line) are buttons that already ticked.
        openDay = JourneyDayRoute(date: date)
    }
}

// MARK: - The calendar

/// The month as a calendar of rings, one per day (JourneyDayRing; spec month-fifths): its name over its own weeks only (a
/// neighbour's last week sits right under its name, in view above or below the month in the middle).
private struct JourneyCalendar: View {
    let log: JourneyLog
    let month: Date
    let today: Date
    /// The days' size (1 = JourneyDayRing.size): smaller where the page wouldn't fit (an SE; a six-week month on a 17 Pro).
    var scale: CGFloat = 1
    /// The month in the middle (its name in ink; the neighbours' in grey).
    var current = true
    let highlight: JourneyHighlight?
    /// The day picked on the page (a ring round it, as the card's picked tile).
    var picked: Date? = nil
    let onDay: (Date) -> Void

    static let nameHeight: CGFloat = 21

    static func weeks(_ month: Date) -> Int {
        let cal = Calendar.current
        let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
        return (lead + JourneyLog.daysOf(month: month).count + 6) / 7
    }

    /// Its height (worked out, not measured, so the page's fit test never feeds on itself): the name and its weeks.
    static func height(weeks: Int, scale: CGFloat) -> CGFloat {
        nameHeight + 3 + CGFloat(weeks) * JourneyDayRing.size * scale + CGFloat(max(weeks - 1, 0)) * 2
    }
    static func height(month: Date, scale: CGFloat) -> CGFloat { height(weeks: weeks(month), scale: scale) }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    var body: some View {
        let _ = JourneyPerf.body("calendar")
        let cal = Calendar.current
        let days = JourneyLog.daysOf(month: month)
        let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
        // A past day an excused range covers with no rows at all (shukr wasn't opened during her period) is excused too: the
        // pause badge, as a day with rows (Bradley's check; the card already steps over such days, bd44ce4).
        let excused = Excused.Days()
        let excusedNoRows: (Date) -> Bool = { date in
            date < today && log.days[PrayerNotificationID.dayKey(date)] == nil && excused.excludes(date)
        }
        VStack(alignment: .leading, spacing: 0) {
            // The name sits just over its own days, the gap above it between months (owner, 2026-10-17: "make the label
            // come a little closer to its respective calendar … a little more breathing room between the two months"); a
            // neighbour's says how it went, as the year's small months do ("on the labels for these, let's also add some
            // sort of information").
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .rounded)).tracking(0.8)
                    .foregroundStyle(current ? Color.primary : Color.secondary)
                if !current, let line = Self.line(log.month(month)) {
                    Text(line).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(height: Self.nameHeight, alignment: .bottomLeading)
            .padding(.bottom, 3)
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
                        .overlay {
                            if picked == date {
                                Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: JourneyDayRing.size * scale + 2, height: JourneyDayRing.size * scale + 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onDay(date) }
                }
            }
            .journeyFlightDays(month, scale: scale)   // where its days are, for the transitions (JourneyTransitions.swift)
        }
    }

    /// "22 days · score 88" (the year's small months' line).
    static func line(_ m: JourneyLog.Month) -> String? {
        guard m.activeDays > 0 else { return nil }
        let days = m.activeDays == 1 ? "1 day" : "\(m.activeDays) days"
        return m.averageScore.map { "· \(days) · score \($0)" } ?? "· \(days)"
    }

    /// "SEPTEMBER", with the year when it isn't this one.
    private var name: String {
        let sameYear = Calendar.current.isDate(month, equalTo: today, toGranularity: .year)
        return (sameYear ? month.formatted(.dateTime.month(.wide)) : month.formatted(.dateTime.month(.wide).year())).uppercased()
    }
}

/// The finger's travel on the month window: only the panes' places read it.
@Observable final class JourneyMonthDrag {
    var offset: CGFloat = 0
}

/// A month's place in the window as the finger moves it: its rest place plus the drag, dimmer the further it sits from the
/// middle (the month in the middle full, a neighbour's edge at about 40 %).
private struct JourneyMonthPaneSlot: ViewModifier {
    let drag: JourneyMonthDrag
    let y: CGFloat
    let height: CGFloat
    let window: CGFloat

    func body(content: Content) -> some View {
        let at = y + drag.offset
        let off = abs(at + height / 2 - window / 2) / max(window / 2, 1)
        content
            .opacity(1 - 0.6 * min(off, 1))
            .offset(y: at)
    }
}

/// The month rail (To make up's scrubber, turned for months: owner, 2026-10-17, option A): a dot per month with marks down
/// the window's right edge, older above (where they come from), the month on show bigger and named at rest, a year's first
/// month carrying its year; a finger on it runs through the months, a tick each, a pill naming the month under it.
private struct JourneyMonthRail: View {
    /// Oldest first.
    let months: [Date]
    let current: Date
    let height: CGFloat
    let pick: (Date) -> Void
    @State private var scrubbing: Date?

    private let pad: CGFloat = 10
    private var slot: CGFloat { min(14, max(4, (height - 2 * pad) / CGFloat(max(months.count, 1)))) }

    var body: some View {
        let here = scrubbing ?? current
        VStack(spacing: 0) {
            ForEach(months.indices, id: \.self) { i in
                let m = months[i]
                let on = m == here
                Circle()
                    .fill(Color.primary.opacity(on ? 0.55 : 0.18))
                    .frame(width: on ? 7 : 5, height: on ? 7 : 5)
                    .frame(width: 24, height: slot)
                    .overlay(alignment: .trailing) {
                        if scrubbing == nil, let mark = mark(i, on: on) {
                            Text(mark)
                                .font(.system(size: 10, weight: on ? .regular : .light, design: .rounded))
                                .foregroundStyle(on ? .primary : .secondary)
                                .fixedSize()
                                .offset(x: -19)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(.vertical, pad)
        .background(Capsule().fill(Color.primary.opacity(scrubbing != nil ? 0.07 : 0)))
        .scaleEffect(scrubbing != nil ? 1.15 : 1, anchor: .trailing)
        .overlay(alignment: .topTrailing) {
            if let scrubbing, let index = months.firstIndex(of: scrubbing) {
                Text(scrubbing.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .fixedSize()
                    .offset(x: -40, y: pad + slot * CGFloat(index) + slot / 2 - 15)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle().inset(by: -12))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if scrubbing == nil { JourneyPerf.began("month rail") }
                    let index = min(max(Int((value.location.y - pad) / slot), 0), months.count - 1)
                    guard months[index] != scrubbing else { return }
                    triggerSomeVibration(type: .light)
                    withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = months[index] }
                    pick(months[index])
                }
                .onEnded { _ in withAnimation(.snappy(duration: CircleMotion.quick)) { scrubbing = nil } }
        )
        .animation(.snappy(duration: CircleMotion.quick), value: here)
        .accessibilityHidden(true)
    }

    /// Beside a dot at rest: the month on show ("Sep"), else the year where one starts ("2025": a year's first month with
    /// marks, and the oldest when it isn't this year).
    private func mark(_ i: Int, on: Bool) -> String? {
        let m = months[i]
        if on { return m.formatted(.dateTime.month(.abbreviated)) }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: m)
        let before = i == 0 ? calendar.component(.year, from: Date()) : calendar.component(.year, from: months[i - 1])
        return year != before ? String(year) : nil
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

/// A day as the month draws it: its ring of fifths (or the closed ring of a day with all five), its number, today's dot.
/// Also the picked day's door on the card and in the year (JourneyDayLine).
struct JourneyDayCell: View {
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
