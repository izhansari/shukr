import SwiftUI

// Journey's year (owner, 2026-10-16; board/mocks/journey-v6/build-plan.md, decisions 2–3): the month page zoomed out — every
// year from the first one, the earliest on top, opening on this year; twelve small months each, drawn in the card's tiles as
// squares ("the card is essentially a mini year view in the layout of a traditional calendar"), each with its name and one
// quiet line; a small month with prayers opens it. Reached from the month's title, Month | Year, or a pinch.

/// The card's colours by how much of a day was prayed (YourJourney's grid: monochrome by amount, green only for all five in
/// time). Kept in step with `JourneyHomeCard`'s own copy.
enum JourneyTileColor {
    static func of(_ kind: YourJourneyStats.Kind, dark: Bool) -> Color {
        switch kind {
        case .none: dark ? Color(red: 0x2E / 255, green: 0x30 / 255, blue: 0x35 / 255)
                         : Color(red: 126 / 255, green: 132 / 255, blue: 143 / 255).opacity(0.14)
        case .some: dark ? Color(red: 0x55 / 255, green: 0x57 / 255, blue: 0x5D / 255)
                         : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.30)
        case .allFive: dark ? Color(red: 0xA9 / 255, green: 0xAB / 255, blue: 0xB1 / 255)
                            : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.62)
        case .allInTime: dark ? Color(red: 0x4C / 255, green: 0x8E / 255, blue: 0x62 / 255)
                              : Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255).opacity(0.55)
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
                key
                ForEach(years, id: \.self) { year($0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
        return Button {
            if numbers.activeDays > 0 { onPick(start) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(start.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(thisMonth ? Color.sage : numbers.activeDays == 0 && !future && !before ? Color.secondary : Color.primary)
                Text(line).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.5), count: 7), spacing: 2.5) {
                    ForEach(0..<lead, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                    ForEach(days, id: \.self) { day in square(day) }
                    // Every small month six weeks tall, so the names in a row line up.
                    ForEach(0..<max(0, 42 - lead - days.count), id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                }
                .padding(.top, 3)
            }
            .padding(6)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[start] = $0 }
            .overlay {
                if start == current {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sage.opacity(0.55), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(numbers.activeDays == 0)
        .accessibilityLabel("\(start.formatted(.dateTime.month(.wide).year())), \(line)")
    }

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
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if day == today { RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.2) }
            }
    }
}
