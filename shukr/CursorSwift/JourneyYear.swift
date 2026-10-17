import SwiftUI

// Journey's year (owner, 2026-10-16; board/mocks/journey-v6/build-plan.md, decisions 2–3): the month page zoomed out — every
// year from the first one, the earliest on top, opening on this year; twelve small months each, drawn in the card's tiles as
// squares ("the card is essentially a mini year view in the layout of a traditional calendar"), each with its name and one
// quiet line; a small month with prayers opens it. Reached from the month's title, Month | Year, or a pinch.

/// The card's and the year's tiles in the month's own fills (owner, 2026-10-16, on the organizer's option B, "the card
/// takes the month's colors": "id rather this. and the year page can follow."): all five in time the ring's green fill, all
/// five with a Qaza the ring's grey fill, some fainter than that, none the faintest — so a tile reads as the day it opens.
enum JourneyTileColor {
    static func of(_ kind: YourJourneyStats.Kind, dark: Bool) -> Color {
        switch kind {
        case .allInTime: JourneyDayRing.green(dark).opacity(0.24)
        case .allFive: JourneyDayRing.greyFill(dark)
        // Tuned on the card (organizer's ask; Bradley found these fills faint): none still shows as a slot, some sits
        // halfway between it and all five.
        case .some: dark ? Color.white.opacity(0.072) : Color.black.opacity(0.09)
        case .none: dark ? Color.white.opacity(0.045) : Color.black.opacity(0.05)
        }
    }
}

struct JourneyYearView: View {
    let log: JourneyLog
    let today: Date
    /// The month the page was showing (outlined here as "where you were").
    let current: Date
    let onPick: (Date) -> Void
    /// A spread not over a month with prayers: back into the month the page was showing.
    var onSpread: () -> Void = {}
    /// A picked day's "Open ›": its day page.
    var onDay: (Date) -> Void = { _ in }
    /// A day's square tapped (owner, 2026-10-16: "make it work the same way that the card works, where tapping a tile shows
    /// that day information at the bottom, which we can then open into"): marked, its line at the bottom; again, cleared.
    @State private var picked: Date?
    @Environment(\.colorScheme) private var scheme
    /// Each small month's frame on screen, for a spread over it (build-plan C: "spread on a small month → that month").
    @State private var frames: [Date: CGRect] = [:]

    private var years: [Int] {
        let cal = Calendar.current
        let last = cal.component(.year, from: today)
        let first = log.firstDay.map { cal.component(.year, from: $0) } ?? last
        return Array(first...last)
    }

    private static let space = "journeyYear"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                key.journeyFlightWords(.page)   // the transitions: arrive as a month goes home (JourneyTransitions.swift)
                ForEach(years, id: \.self) { year($0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            // A tap anywhere that isn't a square or a month's name lets the picked day go.
            .contentShape(Rectangle())
            .onTapGesture { if picked != nil { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } } }
        }
        .defaultScrollAnchor(.bottom)   // opens on this year; earlier years above
        .scrollIndicators(.hidden)
        .coordinateSpace(.named(Self.space))
        // Spread two fingers: the small month they started on opens (one with prayers); anywhere else, back to the month.
        .simultaneousGesture(MagnifyGesture().onEnded { v in
            guard v.magnification > 1.15 else { return }
            if let hit = frames.first(where: { $0.value.contains(v.startLocation) })?.key, log.month(hit).activeDays > 0 {
                onPick(hit)
            } else {
                onSpread()
            }
        })
        // Years scrolling up fade out under the back button instead of running into it.
        .mask { VStack(spacing: 0) { LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 28); Color.black } }
        // The picked day's line at the bottom, above Month | Year — the card's own line.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let date = picked {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    let day = YourJourneyStats.GridDay.of(log, date)
                    JourneyDayLine(day: day, canOpen: day.prayed > 0 && (date < today || log.day(date).allFive)) { onDay(date) }
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 20)
                .id(date)
                .transition(.opacity)
            }
        }
    }

    private var key: some View {
        HStack(spacing: 14) {
            swatch(.allInTime, "All five in time")
            swatch(.allFive, "All five")
            swatch(.some, "Some")
        }
        .font(.system(size: 11.5, weight: .light, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func swatch(_ kind: YourJourneyStats.Kind, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(JourneyTileColor.of(kind, dark: scheme == .dark)).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func year(_ y: Int) -> some View {
        let cal = Calendar.current
        let months = (1...12).compactMap { cal.date(from: DateComponents(year: y, month: $0, day: 1)) }
        let days = months.reduce(0) { $0 + log.month($1).activeDays }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(y)).font(.system(size: 30, weight: .regular, design: .rounded))
                Text(days == 1 ? "1 day you marked a prayer" : "\(days) days you marked a prayer")
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            .journeyFlightWords(.page)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), alignment: .leading, spacing: 18) {
                ForEach(months, id: \.self) { mini($0) }
            }
        }
    }

    /// A small month: its name (sage when it's this month), one quiet line, its days as squares.
    private func mini(_ start: Date) -> some View {
        let cal = Calendar.current
        let numbers = log.month(start)
        let thisMonth = start == JourneyLog.monthStart(today)
        let future = start > today
        let before = log.firstDay.map { start < JourneyLog.monthStart($0) } ?? true
        let line = future || before ? " " : Self.line(numbers)
        let lead = ((cal.component(.weekday, from: start) - cal.firstWeekday) + 7) % 7
        let days = JourneyLog.daysOf(month: start)
        return VStack(alignment: .leading, spacing: 3) {
            // The name (and its line) opens the month; the squares are taps of their own.
            Button {
                if numbers.activeDays > 0 { onPick(start) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(start.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(thisMonth ? Color.sage : numbers.activeDays == 0 && !future && !before ? Color.secondary : Color.primary)
                        .journeyFlightYearName(start)
                        .journeyFlightWords(.page)
                    Text(line).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                        .journeyFlightWords(.page)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(numbers.activeDays == 0)
            .accessibilityLabel("\(start.formatted(.dateTime.month(.wide).year())), \(line)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 7), spacing: Self.gap) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(days, id: \.self) { day in square(day) }
                // Every small month six weeks tall, so the names in a row line up.
                ForEach(0..<max(0, 42 - lead - days.count), id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
            }
            .journeyFlightYearSquares(start)   // its days fly in and out of these (JourneyTransitions.swift)
            .padding(.top, 3)
        }
        .padding(6)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[start] = $0 }
        .overlay {
            if start == current {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sage.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The squares' spacing: a square's tap covers half the gap each side, so it fills its grid cell and never reaches the
    /// next day.
    private static let gap: CGFloat = 2.5

    /// "9 days · 84%" (in time, of the prayers due on those days) or "Away" for a month with nothing marked.
    private static func line(_ m: JourneyLog.Month) -> String {
        guard m.activeDays > 0 else { return "Away" }
        let days = m.activeDays == 1 ? "1 day" : "\(m.activeDays) days"
        guard m.due > 0 else { return days }
        let pct = Int((Double(m.inTime) / Double(m.due) * 100).rounded())
        return "\(days) · \(pct)%"
    }

    private func square(_ day: Date) -> some View {
        let future = day > today
        let before = log.firstDay.map { day < $0 } ?? true
        let fill: Color = future || before ? Color.primary.opacity(future ? 0.04 : 0) : JourneyTileColor.of(YourJourneyStats.kind(log.day(day)), dark: scheme == .dark)
        let on = picked == day
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if day == today { RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.2) }
            }
            // Picked: the card's mark, a ring round the square.
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.3)
                        .padding(-2)
                }
            }
            .zIndex(on ? 1 : 0)
            .contentShape(Rectangle().inset(by: -Self.gap / 2))
            .onTapGesture {
                guard !future, !before else { return }
                triggerSomeVibration(type: .light)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = on ? nil : day }
            }
            .accessibilityAddTraits(.isButton)
    }
}
