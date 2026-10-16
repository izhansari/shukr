import SwiftUI

// Journey's month (moved out of Journey.swift, 2026-10-16, so the calendar and Journey's page are separate files: the
// month page, its calendar of rings and one day's ring. Spec board/mocks/month-fifths/spec.md; the build
// board/mocks/journey-v6/build-plan.md).

struct JourneyMonthRoute: Hashable, Identifiable {
    let month: Date
    var id: Date { month }
}

// MARK: - A month

/// A month (Journey v6): its name with ‹ › to the next month with prayers, "N days you marked a prayer", its three numbers in
/// one flat row between hairlines, and the calendar of rings (JourneyDayRing) with its key; a day opens the day page. No grade
/// colours here (spec month-fifths: the switch and the ··· menu went with the rings).
struct JourneyMonthPage: View {
    let log: JourneyLog
    @State var start: Date
    @Environment(\.circleTheme) private var theme
    @State private var openDay: JourneyDayRoute?
    /// A number tapped (owner, 2026-10-16: "tapping the days all in time, days with all five and average score, do the same
    /// thing we used to have earlier"): only its days lit on the calendar; again, off; one at a time; a new month clears it.
    @State private var focus: JourneyHighlight?
    /// The finger's travel sideways on the calendar (owner, 2026-10-16: "swipe month to month with my finger on the
    /// calendar"): Journey's day pager, for months — the next month's calendar rides in 1:1, this one leaves at 90 %.
    @State private var dragOffset: CGFloat = 0
    @State private var dragHorizontal: Bool?

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

    private var pageWidth: CGFloat { UIScreen.main.bounds.width }
    /// The month `by` away among the months with marks (nil: none that way).
    private func neighbour(_ by: Int) -> Date? {
        let list = months
        guard let at = list.firstIndex(of: start), list.indices.contains(at + by) else { return nil }
        return list[at + by]
    }
    /// The month the title and numbers name: the neighbour once it's more than half in.
    private var shownMonth: Date {
        if dragOffset < -pageWidth / 2, let next = neighbour(1) { return next }
        if dragOffset > pageWidth / 2, let previous = neighbour(-1) { return previous }
        return start
    }

    var body: some View {
        // Fits on a phone as it is (no scroll to fight the sideways drag); a scroll only when it doesn't (large type).
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openDay) { JourneyDayPage(date: $0.date, firstDay: log.firstDay) }
    }

    private var page: some View {
        let shown = shownMonth
        let numbers = log.month(shown)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(shown.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .id(shown)
                    .transition(CircleMotion.dayPickSwap)
                Spacer(minLength: 8)
                step("chevron.left", by: -1, label: "Previous month")
                step("chevron.right", by: 1, label: "Next month")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(numbers.activeDays == 1 ? "1 day you marked a prayer" : "\(numbers.activeDays) days you marked a prayer")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                HStack(alignment: .top, spacing: 0) {
                    fact("\(numbers.allInTimeDays)", "days all in time", .allInTime)
                    fact("\(numbers.allFiveDays)", "days with all five", .allFive)
                    // The best day's score and date in its place while it's lit (as Journey's card did).
                    if case .bestScore(let best) = focus {
                        let days = JourneyLog.daysOf(month: shown).filter { focus?.matches(log.day($0)) == true }
                        fact("\(best)", days.count == 1 ? "best · \(days[0].formatted(.dateTime.month(.abbreviated).day()))"
                                                      : "best · \(days.count) days", focus)
                    } else {
                        fact(numbers.averageScore.map { "\($0)" } ?? "–", "average score",
                             numbers.bestDay.map { .bestScore($0.score) })
                    }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                .padding(.top, 22)
            }
            .id(shown)
            .transition(CircleMotion.dayPickSwap)
            calendars.padding(.top, 24)
            Text("Tap a day to open it.")
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .onChange(of: shown) { focus = nil }   // another month: its own days
    }

    /// The month's calendar between its neighbours, a page apart, moving with the finger (Journey's day pager: the one
    /// coming in rides 1:1, the one going out at 90 %, each fading and shrinking a little with its distance — never overlapping).
    private var calendars: some View {
        let panes: [(k: Int, month: Date)] = [-1, 0, 1].compactMap { k in k == 0 ? (0, start) : neighbour(k).map { (k, $0) } }
        return ZStack(alignment: .top) {
            ForEach(panes, id: \.month) { pane in
                let place = calendarPlace(pane.k)
                JourneyCalendar(log: log, month: pane.month, today: today,
                                highlight: pane.k == 0 ? focus : nil) { open($0) }
                    .animation(.easeInOut(duration: 0.3), value: focus)
                    .modifier(DayPaneMotion(away: place.away))
                    .offset(x: place.x)
                    .allowsHitTesting(pane.k == 0)
            }
        }
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    private func calendarPlace(_ k: Int) -> (x: CGFloat, away: CGFloat) {
        let w = pageWidth
        let x: CGFloat
        if k == 0 {
            x = dragOffset * 0.9
        } else {
            let incoming = (k > 0 && dragOffset < 0) || (k < 0 && dragOffset > 0)
            x = CGFloat(k) * w + (incoming ? dragOffset : 0)
        }
        return (x, min(abs(x) / w, 1))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if dragHorizontal == nil {
                    // The left edge stays the system's back swipe.
                    dragHorizontal = v.startLocation.x > 20 && abs(v.translation.width) > abs(v.translation.height)
                }
                guard dragHorizontal == true else { return }
                let w = v.translation.width
                dragOffset = neighbour(w < 0 ? 1 : -1) != nil ? w : w * 0.15   // nothing that way: a little give
            }
            .onEnded { v in
                defer { dragHorizontal = nil }
                guard dragHorizontal == true else { return }
                let w = v.translation.width, projected = v.predictedEndTranslation.width
                let by = w < 0 ? 1 : -1
                guard neighbour(by) != nil, abs(w) > pageWidth / 4 || abs(projected) > pageWidth / 2 else {
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
        withAnimation(CircleMotion.daySlideIn) { dragOffset = by > 0 ? -pageWidth : pageWidth } completion: {
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
                    .contentTransition(.numericText())
                Text(caption).font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .opacity(focus == nil || on ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(kind == nil ? "" : on ? "Shows every day again" : "Lights these days on the calendar")
    }

    /// A small raised disc with a plain chevron (owner: not the sage arrows); flat and faint when there's no month that way.
    /// It turns the month as the swipe does.
    private func step(_ symbol: String, by: Int, label: String) -> some View {
        let enabled = neighbour(by) != nil
        return Button {
            turn(by)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.3))
                .frame(width: 34, height: 34)
                .background { if enabled { NeuRaised(shape: Circle(), radius: 2.5, offset: 1.2) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func open(_ date: Date) {
        guard let first = log.firstDay, date >= first, date <= today else { return }
        // Today opens only once it's over — all five marked (owner, 2026-10-15: the day page "doesn't show up in journey
        // unless the day is over or all 5 have been marked, so it never shows current prayers").
        guard date < today || log.day(date).allFive else { return }
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
    let highlight: JourneyHighlight?
    let onDay: (Date) -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    var body: some View {
        let cal = Calendar.current
        let days = JourneyLog.daysOf(month: month)
        let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
        let hasExcused = log.usesExcused && days.contains { log.day($0).marks.contains(.excused) }
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: JourneyDayRing.size) }
                ForEach(days, id: \.self) { date in
                    let day = log.day(date)
                    JourneyDayCell(day: day, date: date, today: today, first: log.firstDay, usesExcused: log.usesExcused)
                        .opacity(highlight.map { $0.matches(day) ? 1 : 0.22 } ?? 1)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onDay(date) }
                }
            }
            HStack(spacing: 16) {
                key(keyRing(inTime: true), "All five in time")
                key(keyRing(inTime: false), "All five")
                if hasExcused { key(ExcusedDayBadge(size: 10), "Excused") }
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 14)   // ~20 pt under the calendar with the stack's 6 (the canvas; Frank's check)
            .frame(maxWidth: .infinity)
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

    private func key<V: View>(_ swatch: V, _ title: String) -> some View {
        HStack(spacing: 5) { swatch.frame(width: 12, height: 12); Text(title) }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let future = date > today
        let before = first.map { date < $0 } ?? true
        let isToday = date == today
        let dark = scheme == .dark
        let excusedAllDay = usesExcused && day.excusedDay && !day.active
        let drawn = !future && !before && day.active
        ZStack {
            if drawn {
                if day.allFive && !isToday {
                    Circle().fill(day.allInTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
                        .frame(width: JourneyDayRing.fill * 2, height: JourneyDayRing.fill * 2)
                    Circle()
                        .stroke(day.allInTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: JourneyDayRing.band)
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
            if isToday {
                Circle().fill(Color.primary).frame(width: 3 * JourneyDayRing.k, height: 3 * JourneyDayRing.k)
                    .offset(y: 7.6 * JourneyDayRing.k)
            } else if excusedAllDay {
                ExcusedDayBadge(size: 9.2 * JourneyDayRing.k).offset(y: 13 * JourneyDayRing.k)
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
            Circle().trim(from: arc.from, to: arc.to)
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
