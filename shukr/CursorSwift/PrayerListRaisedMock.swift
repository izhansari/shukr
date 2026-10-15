#if DEBUG
import SwiftUI

// The raised list, mocked (owner, 2026-10-14): "what if we make the whole list raised, but raising the current prayer just
// a little bit more off of it … completely rounded on all the edges and corners, and the current prayer sharing the same
// borders". The whole list is one raised card with capsule-round corners; the prayer on now is a full-width capsule band
// of it, raised a step more, rounded all round (owner) — at the top or bottom it traces the card's corner, alone it is the
// whole card. A Light / Dark switch (owner). Sample data, every case:
// Fajr / Asr / Isha on now, the done rows folded or shown, one prayer left, just marked with its buttons.
// My Dev Stuff → Raised list mock-up; DEBUG `-demoRaisedListMock`.

struct RaisedListMockPage: View {
    @Environment(\.circleTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var phoneScheme
    @State private var lift: Lift = .subtle
    /// Light or dark, to see both (owner); starts on the phone's.
    @State private var dark: Bool?

    /// How much more the band is raised than the card.
    enum Lift: String, CaseIterable, Identifiable {
        case subtle, medium, strong
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var radius: CGFloat { switch self { case .subtle: 3; case .medium: 5; case .strong: 8 } }
        var offset: CGFloat { switch self { case .subtle: 1.5; case .medium: 2.5; case .strong: 4 } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Picker("Lift", selection: $lift) {
                    ForEach(Lift.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                Picker("Look", selection: Binding(get: { dark ?? (phoneScheme == .dark) }, set: { dark = $0 })) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                ForEach(RaisedListMock.scenarios) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(s.title).font(.footnote).fontDesign(.rounded).foregroundStyle(.secondary).padding(.leading, 8)
                        RaisedListMockCard(rows: s.rows, lift: lift)
                    }
                    .frame(width: 290)   // a long title wraps; the card stays centred
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surface.ignoresSafeArea())
        .environment(\.colorScheme, (dark ?? (phoneScheme == .dark)) ? .dark : .light)
        .toolbarColorScheme((dark ?? (phoneScheme == .dark)) ? .dark : .light, for: .navigationBar)   // the title follows too
        .navigationTitle("Raised list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
    }
}

enum RaisedListMock {
    enum State {
        case done(Color)
        case now(left: String)
        case coming
        /// Just marked from the list: G's buttons.
        case marked(Color)
    }
    struct Row: Identifiable {
        let name: String
        let time: String
        let state: State
        var id: String { name }
    }
    struct Scenario: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    private static let fajr = ("Fajr", "6:11 AM"), dhuhr = ("Dhuhr", "1:02 PM"), asr = ("Asr", "4:12 PM"),
                        maghrib = ("Maghrib", "6:41 PM"), isha = ("Isha", "7:51 PM")
    private static func row(_ p: (String, String), _ s: State) -> Row { Row(name: p.0, time: p.1, state: s) }

    static let scenarios: [Scenario] = [
        Scenario(title: "Fajr on now — the top band", rows: [
            row(fajr, .now(left: "52 min left")), row(dhuhr, .coming), row(asr, .coming), row(maghrib, .coming), row(isha, .coming)]),
        Scenario(title: "Asr on now, done folded — the usual: the top band", rows: [
            row(asr, .now(left: "1 hr 48 min left")), row(maghrib, .coming), row(isha, .coming)]),
        Scenario(title: "Asr on now, \"2 done\" open — a middle band", rows: [
            row(fajr, .done(.green)), row(dhuhr, .done(.yellow)), row(asr, .now(left: "1 hr 48 min left")),
            row(maghrib, .coming), row(isha, .coming)]),
        Scenario(title: "Isha on now, \"4 done\" open — the bottom band", rows: [
            row(fajr, .done(.green)), row(dhuhr, .done(.yellow)), row(asr, .done(.green)), row(maghrib, .done(.red)),
            row(isha, .now(left: "3 hr 20 min left"))]),
        Scenario(title: "Only Isha left — the band is the whole card", rows: [
            row(isha, .now(left: "3 hr 20 min left"))]),
        Scenario(title: "Asr just marked from the list — its buttons", rows: [
            row(asr, .marked(.yellow)), row(maghrib, .coming), row(isha, .coming)]),
    ]
}

/// One list: the raised card, the band on it.
struct RaisedListMockCard: View {
    let rows: [RaisedListMock.Row]
    let lift: RaisedListMockPage.Lift
    /// A row's height: the band is a capsule of it, and the card's corners are its half (owner: "round it out more so that
    /// it matches" the raised row), so a top / bottom band traces the card's own corner exactly.
    static let rowHeight: CGFloat = 38   // tighter (owner: "kill some of the spacing"; was 44)
    private static let radius: CGFloat = rowHeight / 2

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                RaisedListMockRow(row: r)
                    .background {
                        if isBand(r) {
                            // Rounded all round (owner: the inner corners too), sharing the card's edges.
                            NeuRaised(shape: Capsule(), radius: lift.radius, offset: lift.offset)
                        }
                    }
                    .zIndex(isBand(r) ? 1 : 0)   // its shadow falls on the rows round it
            }
        }
        .frame(width: 290)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: Self.radius, style: .circular)))
    }

    private func isBand(_ r: RaisedListMock.Row) -> Bool {
        switch r.state { case .now, .marked: true; default: false }
    }
}

/// A row as the list draws it (dot, name, time), from sample data.
struct RaisedListMockRow: View {
    let row: RaisedListMock.Row

    var body: some View {
        HStack(spacing: 10) {
            dot.frame(width: 24, height: 24, alignment: .leading)
            Text(row.name).font(.system(size: 15)).fontDesign(.rounded).fontWeight(nameWeight).foregroundStyle(nameStyle)   // 15 pt (owner; was 16)
            if case .marked = row.state {
                PrayerRowActionButton(symbol: "pencil", label: "Edit", size: 26, style: .bare) {}.padding(.leading, -6)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: RaisedListMockCard.rowHeight)
    }

    @ViewBuilder private var dot: some View {
        switch row.state {
        case .done(let c), .marked(let c):
            PrayerStatusDot(style: .muted, done: true, future: false, scoreColor: c, pulse: 0)
        case .now:
            PrayerStatusDot(style: .muted, done: false, future: false, scoreColor: .gray, pulse: 0)
        case .coming:
            PrayerStatusDot(style: .muted, done: false, future: true, scoreColor: .gray, pulse: 0)
        }
    }
    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .now(let left):
            Text(left).font(.footnote).fontDesign(.rounded).foregroundStyle(.secondary)
        case .marked:
            HStack(spacing: 8) {
                PrayerRowActionButton(symbol: "circle.hexagonpath", label: "Tasbih", style: .pressed) {}
                PrayerRowActionButton(symbol: "camera", label: "Photo", style: .pressed) {}
            }
        default:
            Text(row.time).font(.footnote).fontDesign(.rounded).fontWeight(.light)
                .foregroundStyle(Color.secondary.opacity(isComing ? 0.6 : 1))
        }
    }
    private var isComing: Bool { if case .coming = row.state { true } else { false } }
    private var isNow: Bool { if case .now = row.state { true } else { false } }
    private var nameWeight: Font.Weight { isNow || isComing ? .regular : .light }
    private var nameStyle: AnyShapeStyle {
        isNow ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(isComing ? 0.6 : 1))
    }
}
#endif
