import SwiftUI

// Journey's year (owner, 2026-10-16; board/mocks/journey-v6/build-plan.md, decisions 2–3): the month page zoomed out — every
// year from the first one, the earliest on top, opening on this year; twelve small months each, drawn in the card's tiles as
// squares ("the card is essentially a mini year view in the layout of a traditional calendar"), each with its name and one
// quiet line; a small month with prayers opens it. Reached from the month's title, Month | Year, or a pinch.

/// The card's and the year's tiles (owner, 2026-10-17, tuned in his tile sheet; board/mocks/journey-v6/tile-colors-handoff.md):
/// in time a green, all five with a Qaza a grey-green, incomplete a grey, none the faintest — each a heat map of the day's
/// score on this user's own scale (`JourneyLog.tileRank`): their lowest day of a kind draws at `faintest`, their best full.
/// A kind never fades into the one below it (a weak Qaza day read as incomplete): its floor stays 0.06 above that kind.
/// The month's rings keep their own fills (JourneyDayRing).
enum JourneyTileColor {
    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> (Color, Double) {
        (Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1), a)
    }
    /// In time, With Qaza, Incomplete, None: each kind's color and its full strength.
    private static let light = [rgba(40, 167, 69, 0.80), rgba(104, 140, 110, 0.36), rgba(35, 38, 44, 0.23), rgba(35, 38, 44, 0.00)]
    private static let dark = [rgba(64, 200, 110, 0.85), rgba(120, 160, 128, 0.50), rgba(255, 255, 255, 0.20), rgba(255, 255, 255, 0.00)]
    /// The weakest a heat-mapped tile gets, of its kind's full strength (his "Faintest").
    private static let faintest = 0.41

    private static func index(_ kind: YourJourneyStats.Kind) -> Int {
        switch kind { case .allInTime: 0; case .allFive: 1; case .some: 2; case .none: 3 }
    }
    /// Per look, per kind: the least share of its strength a tile may fade to (the floor above the next kind down).
    private static let floors: [Bool: [Double]] = [false: bands(light), true: bands(dark)]
    private static func bands(_ c: [(Color, Double)]) -> [Double] {
        (0..<4).map { i in i == 3 || c[i].1 == 0 ? 1 : max(faintest, min(1, (c[i + 1].1 + 0.06) / c[i].1)) }
    }

    /// An unmarked day draws no fill, only this hairline, in both looks — so a long break still shows its slots and the card
    /// never looks unrendered (owner, 2026-10-17: "i want unmarked days to be invisible on both light and dark. maybe we use
    /// a very thin faint border so if someone is away for a while, their card doesnt look broken").
    static func outline(dark isDark: Bool) -> Color { isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.11) }
    static let outlineWidth: CGFloat = 0.75

    /// A kind at full strength (the year's key, and where nothing ranks it).
    static func of(_ kind: YourJourneyStats.Kind, dark isDark: Bool) -> Color {
        let (c, a) = (isDark ? dark : light)[index(kind)]
        return c.opacity(a)
    }
    /// A day's tile: its kind, as strong as its place on this user's scale (0 their lowest … 1 their best).
    static func of(_ kind: YourJourneyStats.Kind, rank: Double, dark isDark: Bool) -> Color {
        let i = index(kind)
        let (c, a) = (isDark ? dark : light)[i]
        guard kind != .none else { return c.opacity(a) }
        let low = floors[isDark]?[i] ?? 1
        return c.opacity(a * (low + (1 - low) * min(max(rank, 0), 1)))
    }
    /// A day from the log, as its tile draws.
    static func of(_ d: JourneyLog.Day, in log: JourneyLog, dark isDark: Bool) -> Color {
        of(d.tileKind, rank: log.tileRank(d), dark: isDark)
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
    /// Not state: it changed on every frame of a scroll and rebuilt the whole year each time (perf #3).
    @State private var frames = JourneyYearFrames()

    private var years: [Int] {
        let cal = Calendar.current
        let last = cal.component(.year, from: today)
        let first = log.firstDay.map { cal.component(.year, from: $0) } ?? last
        return Array(first...last)
    }

    static let space = "journeyYear"

    var body: some View {
        let _ = JourneyPerf.body("year")
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                key.journeyFlightWords(.page)   // the transitions: arrive as a month goes home (JourneyTransitions.swift)
                ForEach(years, id: \.self) { year($0).id($0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            // A tap anywhere that isn't a square or a month's name lets the picked day go.
            .contentShape(Rectangle())
            .onTapGesture { if picked != nil { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } } }
        }
        .defaultScrollAnchor(.bottom)   // opens on this year; earlier years above
        // From a month in an earlier year (the month rail reaches one in a move), on that year: its small month is where
        // the month's days fly home — off screen they had nowhere to land.
        .onAppear {
            let y = Calendar.current.component(.year, from: current)
            if y != years.last { proxy.scrollTo(y, anchor: .top) }
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { JourneyPerf.began("year scroll") }
            JourneyPerf.scrolling(phase.isScrolling)
        }
        .coordinateSpace(.named(Self.space))
        // Spread two fingers: the small month they started on opens (one with prayers); anywhere else, back to the month.
        .simultaneousGesture(MagnifyGesture().onEnded { v in
            guard v.magnification > 1.15 else { return }
            if let hit = frames.all.first(where: { $0.value.contains(v.startLocation) })?.key, log.month(hit).activeDays > 0 {
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
                    JourneyDayLine(day: day, log: log, canOpen: day.prayed > 0 && (date < today || log.day(date).allFive)) { onDay(date) }
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 20)
                .id(date)
                .transition(.opacity)
                // Goes with the year's words as a month flies out of it (the year dial): it sat over the weeks' numbers
                // for the flight's first frames (the organizer's check of E4).
                .journeyFlightWords(.page)
            }
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
                ForEach(months, id: \.self) { m in
                    JourneyYearMonth(start: m, log: log, today: today, picked: picked.flatMap { JourneyLog.monthStart($0) == m ? $0 : nil },
                                     dark: scheme == .dark, frames: frames, space: Self.space, onPick: onPick) { day in
                        JourneyPerf.began("year tap")
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == day ? nil : day }
                    } onMiss: {
                        // A tap on no day (an empty cell before the 1st or after the last) lets the picked day go, as the
                        // year's own tap does.
                        if picked != nil { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } }
                    }
                    .equatable()
                }
            }
        }
    }

    /// "9 days · score 83" (its average score) or "Away" for a month with nothing marked.
    static func line(_ m: JourneyLog.Month) -> String {
        guard m.activeDays > 0 else { return "Away" }
        let days = m.activeDays == 1 ? "1 day" : "\(m.activeDays) days"
        // The month's average score, the month page's own (owner, 2026-10-17: "change that to the month score … average
        // score of that month"; was the in-time %).
        guard let score = m.averageScore else { return days }
        return "\(days) · score \(score)"
    }
}

/// A small month: its name, one quiet line, its days as squares (no sage on Journey — owner, 2026-10-17). Its own view, equal
/// while its days, its picked day and the look are (perf #3: a pick ran every small month's body, ~27 a tap).
private struct JourneyYearMonth: View, Equatable {
    let start: Date
    let log: JourneyLog
    let today: Date
    /// The picked day, if it's in this month.
    let picked: Date?
    let dark: Bool
    let frames: JourneyYearFrames
    let space: String
    let onPick: (Date) -> Void
    let onDay: (Date) -> Void
    let onMiss: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.start == b.start && a.picked == b.picked && a.dark == b.dark && a.today == b.today && a.log.version == b.log.version
    }

    var body: some View {
        let _ = JourneyPerf.body("yearMonth")
        let cal = Calendar.current
        let numbers = log.month(start)
        let future = start > today
        let before = log.firstDay.map { start < JourneyLog.monthStart($0) } ?? true
        let line = future || before ? " " : JourneyYearView.line(numbers)
        let lead = ((cal.component(.weekday, from: start) - cal.firstWeekday) + 7) % 7
        let days = JourneyLog.daysOf(month: start)
        VStack(alignment: .leading, spacing: 3) {
            // The name (and its line) opens the month; the squares are taps of their own.
            Button {
                if numbers.activeDays > 0 { onPick(start) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(start.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(numbers.activeDays == 0 && !future && !before ? Color.secondary : Color.primary)
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
            // Its days as one picture, not ~40 views each with its own tap (perf #3: a pick redrew all ~1,500 squares).
            JourneyYearSquares(start: start, lead: lead, days: days, log: log, today: today, picked: picked, dark: dark,
                               onTap: onDay, onMiss: onMiss)
                .journeyFlightYearSquares(start)   // its days fly in and out of these (JourneyTransitions.swift)
                .padding(.top, 3)
        }
        .padding(6)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { [frames, start] in frames.all[start] = $0 }
        // No outline round the month you came from (owner, 2026-10-17: "there's like an outline on the month that we came
        // from … I think we can just get rid of that outline … It doesn't really do anything for us").
    }
}

/// The year's small months' frames, written as they move and read only by a spread (never observed).
final class JourneyYearFrames { var all: [Date: CGRect] = [:] }

/// A small month's squares, drawn as one picture: seven columns 2.5 pt apart, square, six weeks tall whatever the month (so
/// the names in a row line up) — the layout JourneyMonthFlight.fromYear works its squares out from. Each day the card's
/// tile color (its hairline when unmarked); today outlined; the picked day ringed. A tap goes to the day under it, a
/// square's tap covering half the gap each side (it fills its cell and never reaches the next day). Redrawn only when its
/// own picked day, the look or the log changes.
struct JourneyYearSquares: View {
    let start: Date
    let lead: Int
    let days: [Date]
    let log: JourneyLog
    let today: Date
    let picked: Date?
    let dark: Bool
    let onTap: (Date) -> Void
    /// A tap on no day (an empty cell, a day before the first or still to come).
    var onMiss: () -> Void = {}
    /// Its width, for a tap's cell (never observed).
    @State private var width = JourneyFrameBox()

    static let gap: CGFloat = 2.5

    var body: some View {
        let _ = JourneyPerf.body("yearSquares")
        let first = log.firstDay
        JourneyYearSquaresFrame {
            Canvas { ctx, size in
                let side = (size.width - 6 * Self.gap) / 7
                func cell(_ at: Int) -> CGRect {
                    CGRect(x: CGFloat(at % 7) * (side + Self.gap), y: CGFloat(at / 7) * (side + Self.gap), width: side, height: side)
                }
                func shape(_ r: CGRect, _ corner: CGFloat) -> Path { Path(roundedRect: r, cornerRadius: corner, style: .continuous) }
                /// A strokeBorder: the line inside the shape's edge.
                func border(_ r: CGRect, _ corner: CGFloat, _ color: Color, _ width: CGFloat) {
                    let h = width / 2
                    ctx.stroke(shape(r.insetBy(dx: h, dy: h), max(corner - h, 0)), with: .color(color), lineWidth: width)
                }
                for (i, day) in days.enumerated() {
                    let r = cell(lead + i)
                    let future = day > today
                    let before = first.map { day < $0 } ?? true
                    if future || before {
                        if future { ctx.fill(shape(r, 2.5), with: .color(Color.primary.opacity(0.04))) }
                    } else {
                        let d = log.day(day)
                        ctx.fill(shape(r, 2.5), with: .color(JourneyTileColor.of(d, in: log, dark: dark)))
                        if !d.active { border(r, 2.5, JourneyTileColor.outline(dark: dark), JourneyTileColor.outlineWidth) }
                    }
                    if day == today { border(r, 2.5, Color.primary.opacity(0.8), 1.2) }
                }
            }
        }
        // Picked: the card's mark, a ring 2 pt round the square — outside the picture (a canvas clips to its frame: the ring
        // lost its outer side on the first and last columns — the helper's check), over its neighbours.
        .overlay(alignment: .topLeading) {
            if let p = picked, let i = days.firstIndex(of: p) {
                let w = width.frame.width, side = max((w - 6 * Self.gap) / 7, 0), at = lead + i
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.3)
                    .frame(width: side + 4, height: side + 4)
                    .offset(x: CGFloat(at % 7) * (side + Self.gap) - 2, y: CGFloat(at / 7) * (side + Self.gap) - 2)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { [width] in width.frame.size.width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { p in
            guard let day = day(at: p) else { onMiss(); return }
            let future = day > today
            let before = first.map { day < $0 } ?? true
            guard !future, !before else { onMiss(); return }
            onTap(day)
        }
        .accessibilityHidden(true)   // the month's name (its button, with its line) speaks for it
    }

    /// The day whose cell (its square and half the gap round it) holds `p`.
    private func day(at p: CGPoint) -> Date? {
        let w = width.frame.width
        guard w > 0 else { return nil }
        let pitch = (w + Self.gap) / 7   // a square and a gap
        let col = Int(((p.x + Self.gap / 2) / pitch).rounded(.down)), row = Int(((p.y + Self.gap / 2) / pitch).rounded(.down))
        guard (0..<7).contains(col), (0..<6).contains(row) else { return nil }
        let i = row * 7 + col - lead
        return days.indices.contains(i) ? days[i] : nil
    }
}

/// Seven square columns 2.5 pt apart, six rows: as tall as the width makes them, in one layout pass.
private struct JourneyYearSquaresFrame: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 120
        let side = max((w - 6 * JourneyYearSquares.gap) / 7, 0)
        return CGSize(width: w, height: 6 * side + 5 * JourneyYearSquares.gap)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}
