import SwiftUI

// Journey's day ring (spec board/mocks/month-fifths/spec.md) and the route that opens the expanded card. The month page that
// lived here — its window of months, calendar and month rail — went when the card started expanding into the calendar
// (JourneyExpanded.swift; owner, 2026-10-17: "this would basically replace the calendar month view and the calendar year
// view").

struct JourneyMonthRoute: Hashable, Identifiable {
    let month: Date
    /// Opened on this month in focus (a month's name, This month); else the card's ↗ — the weeks it showed, no focus.
    var focus = true
    var id: Date { month }
}

// MARK: - A day's ring

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

    // The transitions' share (JourneyCellDraw: how much of its ring, number and fill to draw while a flight runs) is read
    // only by the small pieces below, never here: read here, a flight rebuilt every flying day's whole cell each frame
    // (~84 a frame, ~700 a flight back to the card on the sim).
    var body: some View {
        let _ = JourneyPerf.body("dayCell")
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
                        .modifier(JourneyCellDrawFade(part: .fill))
                    JourneyCellRing(closed: day.allInTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark),
                                    fifths: [])
                } else {
                    JourneyCellRing(closed: nil, fifths: (0..<5).map { fifthColor($0, today: isToday, dark: dark) })
                }
            }
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: JourneyDayRing.number, weight: isToday ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(future ? Color.secondary.opacity(0.55) : drawn || isToday ? Color.primary : Color.secondary.opacity(0.85))
                .offset(y: isToday ? -2.2 * JourneyDayRing.k : 0)
                .modifier(JourneyCellDrawFade(part: .number))
            if isToday {
                Circle().fill(Color.primary).frame(width: 3 * JourneyDayRing.k, height: 3 * JourneyDayRing.k)
                    .offset(y: 7.6 * JourneyDayRing.k)
                    .modifier(JourneyCellDrawFade(part: .number))
            } else if excusedAllDay {
                ExcusedDayBadge(size: 9.2 * JourneyDayRing.k).offset(y: 13 * JourneyDayRing.k)
                    .modifier(JourneyCellDrawFade(part: .number))
            }
        }
        .frame(width: JourneyDayRing.size, height: JourneyDayRing.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// A prayer's fifth: prayed (or excused) soft — today's a little stronger — missed a faint track; nothing for one to come.
    private func fifthColor(_ i: Int, today: Bool, dark: Bool) -> Color? {
        switch day.marks[i] {
        case .done, .excused: today ? JourneyDayRing.strong(dark) : JourneyDayRing.soft(dark)
        case .missed: JourneyDayRing.track(dark)
        case .toCome, .none: nil
        }
    }

    private var accessibility: String {
        let d = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard day.active else { return d }
        return "\(d): \(day.prayed) of 5 prayed" + (day.allInTime ? ", all in time" : "")
    }
}

/// A day cell's ring — one closed ring, or its fifths — drawn as far as the flight has it (JourneyCellDraw.ring).
private struct JourneyCellRing: View {
    let closed: Color?
    let fifths: [Color?]
    @Environment(\.journeyCellDraw) private var cellDraw

    var body: some View {
        let _ = JourneyPerf.body("cellRing")
        let drawn = cellDraw.ring
        ZStack {
            if let closed {
                Circle().trim(from: 0, to: drawn)
                    .stroke(closed, lineWidth: JourneyDayRing.band)
                    .rotationEffect(.degrees(-90))   // drawn closed from the top (the transitions)
            } else {
                ForEach(0..<5, id: \.self) { i in
                    if let color = fifths[i] {
                        let arc = JourneyDayRing.fifth(i)
                        Circle().trim(from: arc.from, to: arc.from + (arc.to - arc.from) * drawn)
                            .stroke(color, style: StrokeStyle(lineWidth: JourneyDayRing.band, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
        }
        .frame(width: JourneyDayRing.radius * 2, height: JourneyDayRing.radius * 2)
    }
}

/// A day cell's fill or number, faded as far as the flight has it (JourneyCellDraw.fill / .number).
private struct JourneyCellDrawFade: ViewModifier {
    enum Part { case fill, number }
    let part: Part
    @Environment(\.journeyCellDraw) private var cellDraw
    func body(content: Content) -> some View { content.opacity(part == .fill ? cellDraw.fill : cellDraw.number) }
}
