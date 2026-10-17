import SwiftUI
import QuartzCore

// Journey's two transitions (owner, 2026-10-16, after trying them on his phone: "1a. … 2a looks alright for the most
// part"), moved out of the test screen (JourneyTransitionLab.swift):
// 1A, transition D — the card's month opens in place on one dial: the month's tiles fly to their days and land as each
// day's fill, its name grows into the title, the card's surface grows into the page, the rings close day by day.
// 2A, Bradley's plan — a day's ring grows from its cell into the day page's ring, soft, then the grade colours draw in.
// "the back swipe should undo it the same way": a swipe from the left edge turns the same dial backwards under the finger.
//
// How it fits together: JourneyPage carries `.journeyMonthHost(month:log:)`, which shows the month (JourneyMonthPage) as a
// layer over Journey's page and the day (JourneyDayPage) over that, and runs the dials. One small Animatable driver puts the
// dials into the environment on every frame (JourneyMonthDial, JourneyDayEntrance); only small leaf modifiers read
// them (`.journeyFlightTile`, `.journeyFlightWords`, `.journeyFlightCell`, …), so the pages themselves never redraw per frame.
// With no transition running every modifier is a no-op.

// MARK: - Timing

/// The dials' lengths and beats in one place. Each dial runs linearly; every beat eases on its own stretch of it (the mock's
/// way, board/mocks/journey-v6/transition-d.html).
enum JourneyMotion {
    /// Card → month: the mock's whole run at speed 1 (measured on his 13 Pro Max, Release: 580–598 ms, 68–70 frames at 120 Hz).
    static let monthDuration: Double = 0.56
    /// Month → day: the ring's growth, then the grade colours drawing in (his phone: 1.12–1.14 s, 133–134 frames).
    static let dayDuration: Double = 1.1
    /// Where the grown disc hands over to the page's own (day dial).
    static let dayLand: CGFloat = 0.5

    static func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max((t - a) / (b - a), 0), 1) }
    static func io(_ x: CGFloat) -> CGFloat { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func out(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }
    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    /// The card → month beats (the mock's): Journey's words lift away, the card's other weeks fade, one zoom carries the
    /// tiles and the name, the month's words arrive, the rings close day by day.
    static func zoom(_ t: CGFloat) -> CGFloat { io(seg(t, 0.05, 0.75)) }
    static func pageWords(_ t: CGFloat) -> CGFloat { out(seg(t, 0, 0.28)) }
    static func cardWords(_ t: CGFloat) -> CGFloat { 1 - out(seg(t, 0, 0.2)) }
    static func otherWeeks(_ t: CGFloat) -> CGFloat { (1 - 0.5 * out(seg(t, 0, 0.1))) * (1 - out(seg(t, 0.1, 0.5))) }
    static func monthWords(_ t: CGFloat) -> CGFloat { out(seg(t, 0.55, 0.95)) }
    static func tint(_ t: CGFloat) -> CGFloat { seg(t, 0.35, 0.8) }
    static func titleUnroll(_ t: CGFloat) -> CGFloat { out(seg(t, 0.3, 0.75)) }
    /// Day `n` of the month (1-based): its ring drawing closed, then its number.
    static func ring(_ t: CGFloat, day n: Int) -> CGFloat { let a = 0.6 + CGFloat(n - 1) * 0.006; return io(seg(t, a, a + 0.2)) }
    static func number(_ t: CGFloat, day n: Int) -> CGFloat { let a = 0.6 + CGFloat(n - 1) * 0.006; return out(seg(t, a + 0.02, a + 0.2)) }
    /// The month fading as a day opens (Bradley: "it fades out as the ring starts to grow").
    static func monthAway(_ dayDial: CGFloat) -> CGFloat { 1 - out(seg(dayDial, 0, 0.3)) }
}

// MARK: - Frame log

/// Logs each run's real frame pacing (measure before guessing): how long it took, frames drawn, the worst gap, late frames
/// and the main run loop's longest busy spell. Library/Caches/journey-transitions.log on the phone, and the console.
@MainActor final class JourneyFrameLog: NSObject {
    static let shared = JourneyFrameLog()
    private var link: CADisplayLink?
    private var name = ""
    private var began: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var worst: CFTimeInterval = 0
    private var late = 0
    private var expected: CFTimeInterval = 1 / 60.0
    private var observer: CFRunLoopObserver?
    private var wokeAt: CFTimeInterval = 0
    private var longestBusy: CFTimeInterval = 0

    func start(_ name: String) {
        link?.invalidate()
        self.name = name
        began = CACurrentMediaTime(); last = began
        frames = 0; worst = 0; late = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        longestBusy = 0; wokeAt = CACurrentMediaTime()
        if observer == nil {
            let o = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = CACurrentMediaTime()
                    if activity == .afterWaiting { self.wokeAt = now } else { self.longestBusy = max(self.longestBusy, now - self.wokeAt) }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
            observer = o
        }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        expected = max(l.targetTimestamp - l.timestamp, 1 / 120.0)
        if frames > 0 {
            let gap = now - last
            worst = max(worst, gap)
            if gap > expected * 1.5 { late += 1 }
        }
        frames += 1
        last = now
    }

    func stop(_ how: String = "") {
        guard let l = link else { return }
        l.invalidate(); link = nil
        let ms = (CACurrentMediaTime() - began) * 1000
        let line = String(format: "%@ %@%@: %.0f ms, %d frames at %.0f Hz, worst %.1f ms, %d late, main busy ≤ %.0f ms",
                          Date().formatted(.iso8601), name, how.isEmpty ? "" : " (\(how))", ms, frames, 1 / expected, worst * 1000, late,
                          longestBusy * 1000)
        print("🎞️ \(line)")
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("journey-transitions.log")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
    }
}

// MARK: - Where things are

/// Where the card's tiles and names, the month's cells and title are on screen, read when a transition starts or lands —
/// never observed (no redraw on every scroll frame). Each piece reports itself through its modifier.
@MainActor final class JourneyFlightGeometry {
    static let shared = JourneyFlightGeometry()
    var card: CGRect = .zero
    /// The card's grid as it shows (its clip): only tiles inside it fly; the rest grow in place.
    var grid: CGRect = .zero
    /// The grid's scroll offset and its rows' week starts (oldest first): a tile's place is worked out from them, as the
    /// card lays its rows out — never reported per tile (80-odd reporters in its lazy, bottom-anchored grid kept it laying
    /// out forever: 100 % CPU, the page never drew).
    var gridOffset: CGFloat = 0
    var weekStarts: [Date] = []
    var names: [Date: CGRect] = [:]
    /// The month's day rings (global, the ring's own square at the page's scale).
    var cells: [Date: CGRect] = [:]
    /// The month title's slot, and the month it names (the page may have been paged since it opened).
    var title: CGRect?
    var shownMonth: Date?
    /// Called when the title's slot is first laid out (a month waiting to open).
    var onTitle: (() -> Void)?

    /// Where a day's bar is on the card now, from the card's row layout (JourneyHomeCard.row: a 34 pt name column, then
    /// seven bars 11 pt tall with 6 pt between; rows `pitch` apart under 12 pt of top room).
    func tile(_ date: Date) -> CGRect? {
        guard grid.width > 0, let row = weekStarts.lastIndex(where: { $0 <= date }) else { return nil }
        let col = Calendar.current.dateComponents([.day], from: weekStarts[row], to: date).day ?? 0
        guard (0..<7).contains(col) else { return nil }
        let barW = (grid.width - 34 - 6 * 7) / 7
        let y = grid.minY + 12 + CGFloat(row) * JourneyHomeCard.pitch - gridOffset
        return CGRect(x: grid.minX + 34 + 6 + CGFloat(col) * (barW + 6), y: y, width: barW, height: 11)
    }

    /// Every piece's place from its anchor, in screen terms (JourneyMonthHost's resolver). Replaced wholesale, so a row the
    /// card's lazy grid let go of never leaves a stale frame behind.
    func resolve(_ anchors: [JourneyFlightPart: JourneyFlightAnchor], in proxy: GeometryProxy) {
        let o = proxy.frame(in: .global).origin
        var cells: [Date: CGRect] = [:]
        var title: CGRect?, shown: Date?
        for (part, a) in anchors {
            let r = proxy[a.anchor].offsetBy(dx: o.x, dy: o.y)
            switch part {
            case .cell(let d):
                // The ring's own square at the page's scale (the cell is laid out at 46 pt and scaled).
                let s = JourneyDayRing.size * a.scale
                cells[d] = CGRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s)
            case .title(let m): title = r; shown = m
            }
        }
        self.cells = cells
        self.title = title; shownMonth = shown ?? shownMonth
        if title != nil, let go = onTitle { onTitle = nil; DispatchQueue.main.async { go() } }
    }
}

/// What reports its place: the card and its grid, a tile, a month's name, a calendar day, the month's title.
enum JourneyFlightPart: Hashable { case cell(Date), title(Date) }
struct JourneyFlightAnchor { let anchor: Anchor<CGRect>; var scale: CGFloat = 1 }

/// The card's pieces write their place as they're laid out: a GeometryReader behind them writing into the unobserved store,
/// so it can't redraw anything. (Their anchors came through empty from inside the card's scroll view and Journey's
/// four-variant layout: every tile grew in place and "Sep" never flew.)
struct JourneyFlightReport: View {
    let write: @MainActor (CGRect) -> Void
    var body: some View {
        GeometryReader { g in
            let _ = write(g.frame(in: .global))
            Color.clear
        }
    }
}

/// The month's pieces (its cells and title) travel as anchor preferences and are resolved once, at the host. Not onGeometryChange: inside JourneyPage's
/// ViewThatFits every measuring pass fired it again and scheduled another (the real Journey sat at 100 % CPU and never drew;
/// the team line without the hooks: 14 %).
struct JourneyFlightAnchors: PreferenceKey {
    static var defaultValue: [JourneyFlightPart: JourneyFlightAnchor] { [:] }
    static func reduce(value: inout [JourneyFlightPart: JourneyFlightAnchor], nextValue: () -> [JourneyFlightPart: JourneyFlightAnchor]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    fileprivate func journeyFlightPlace(_ part: JourneyFlightPart, scale: CGFloat = 1) -> some View {
        anchorPreference(key: JourneyFlightAnchors.self, value: .bounds) { [part: JourneyFlightAnchor(anchor: $0, scale: scale)] }
    }
}

// MARK: - What a running transition knows

/// One of the month's days as it opens: where its tile was on the card (nil: not in view, it grows in place), the tile's
/// colour and what it lands as.
struct JourneyFlightTile: Equatable {
    enum Fill: Equatable { case none, green, grey }
    let from: CGRect?
    let kind: YourJourneyStats.Kind
    let fill: Fill
}

/// A month opening from the card: which, and the card's geometry frozen at the tap.
struct JourneyMonthFlight: Equatable {
    let start: Date
    let tiles: [Date: JourneyFlightTile]
    /// The month's name on the card, if it was in view.
    let label: CGRect?
    let card: CGRect

    /// The flight for `start` from where the card's pieces are now.
    @MainActor static func make(_ start: Date, log: JourneyLog, today: Date) -> JourneyMonthFlight {
        let g = JourneyFlightGeometry.shared
        let visible = g.grid.insetBy(dx: -1, dy: -1)
        var tiles: [Date: JourneyFlightTile] = [:]
        for date in JourneyLog.daysOf(month: start) {
            guard let first = log.firstDay, date >= first, date <= today else { continue }
            let d = log.day(date)
            let kind: YourJourneyStats.Kind = d.allInTime ? .allInTime : d.allFive ? .allFive : d.active ? .some : .none
            let fill: JourneyFlightTile.Fill = d.allFive && date != today ? (d.allInTime ? .green : .grey) : .none
            // A tile partly under the grid's top fade or outside its clip doesn't fly (it would appear outside the card).
            let from = g.tile(date).flatMap { r in r.minY >= visible.minY + 8 && r.maxY <= visible.maxY ? r : nil }
            tiles[date] = JourneyFlightTile(from: from, kind: kind, fill: fill)
        }
        let label = g.names[start].flatMap { r in visible.insetBy(dx: 0, dy: -2).contains(CGPoint(x: r.midX, y: r.midY)) ? r : nil }
        return JourneyMonthFlight(start: start, tiles: tiles, label: label, card: g.card)
    }
}

/// What's open from the card (nil: nothing — every modifier a no-op). Changes only when a month or day opens or closes, so
/// its readers (the card's hidden tiles, every calendar cell) don't redraw per frame.
struct JourneyMonthOpen: Equatable {
    var flight: JourneyMonthFlight
    /// The day whose ring is flying to the day page (its cell draws none).
    var hiddenDay: Date?
}

/// The dials on this frame: read only by the few pieces that move (the open month's own cells, the fades, the title, the
/// flying ring). Splitting it from JourneyMonthOpen took a real tap from ~185 cell redraws a frame to the month's own ~30.
struct JourneyMonthDial: Equatable {
    var dial: CGFloat
    /// A day opening over the month (0 none … 1 open).
    var dayDial: CGFloat = 0
}

/// The host's way to open a day. Equal by its id: a bare closure in the environment can't be compared, so every dial
/// change looked like a new value and redrew the whole month page each frame (measured: ~90 cell redraws a frame).
struct JourneyDayOpener: Equatable {
    let id: UUID
    let open: (Date) -> Void
    static func == (a: JourneyDayOpener, b: JourneyDayOpener) -> Bool { a.id == b.id }
}

/// One calendar day's share of the entrance: its ring drawn so far (each fifth from its start, or the closed ring from the
/// top) and its number's opacity. JourneyDayCell reads it; 1 / 1 without a transition.
struct JourneyCellDraw: Equatable {
    var ring: CGFloat = 1
    var number: Double = 1
    /// Its own fill disc (0 while its tile is landing as it, or while its ring flies to the day page).
    var fill: Double = 1
    static let full = JourneyCellDraw()
}

extension EnvironmentValues {
    @Entry var journeyMonthOpen: JourneyMonthOpen? = nil
    @Entry var journeyMonthDial: JourneyMonthDial? = nil
    @Entry var journeyCellDraw: JourneyCellDraw = .full
    /// Set by the host: a day tapped on the month opens through it (the ring grows) instead of a push.
    @Entry var journeyDayOpener: JourneyDayOpener? = nil
}

// MARK: - The card's pieces (YourJourney.swift, Journey.swift)

extension View {
    /// The card: reports where it is (its surface grows from there).
    func journeyFlightCard() -> some View { background { JourneyFlightReport { JourneyFlightGeometry.shared.card = $0 } } }
    /// The card's raised surface: hidden while its month is open (the growing one takes its place).
    func journeyFlightCardSurface() -> some View { modifier(JourneyFlightHide(part: .cardSurface)) }
    /// The card's grid (its ScrollView): reports its clip, its scroll offset and its rows' weeks, and fades the other weeks
    /// as a month opens.
    func journeyFlightGrid(weekStarts: [Date]) -> some View {
        background { JourneyFlightReport { JourneyFlightGeometry.shared.grid = $0 } }
            .onScrollGeometryChange(for: CGFloat.self) { g in
                // Kept as it's read: at rest at the bottom the action never runs (the lab's first "Oct" left from the top).
                let y = g.contentOffset.y + g.contentInsets.top
                MainActor.assumeIsolated { JourneyFlightGeometry.shared.gridOffset = y }
                return y
            } action: { _, y in JourneyFlightGeometry.shared.gridOffset = y }
            .onAppear { JourneyFlightGeometry.shared.weekStarts = weekStarts }
            .onChange(of: weekStarts) { _, w in JourneyFlightGeometry.shared.weekStarts = w }
            .modifier(JourneyFlightFade(part: .grid))
    }
    /// A day's tile on the card: hidden while its month is open (it's flying). It reports nothing (see `tile(_:)`).
    func journeyFlightTile(_ date: Date) -> some View { modifier(JourneyFlightHide(part: .tile(date))) }
    /// A month's sage name on the card: reports where it is, hidden while that month is open (it became the title).
    func journeyFlightMonthName(_ start: Date) -> some View {
        background { JourneyFlightReport { JourneyFlightGeometry.shared.names[start] = $0 } }
            .modifier(JourneyFlightHide(part: .name(start)))
    }
    /// Words that fade as a month opens (Journey's header and rows, the card's own words) or arrive with it (the month's).
    func journeyFlightWords(_ part: JourneyFlightFade.Part) -> some View { modifier(JourneyFlightFade(part: part)) }
}

struct JourneyFlightFade: ViewModifier {
    enum Part { case page, card, grid, month }
    let part: Part
    @Environment(\.journeyMonthDial) private var e
    func body(content: Content) -> some View {
        let t = e?.dial ?? 1
        let (opacity, lift): (CGFloat, CGFloat) = switch part {
        case .page: e == nil ? (1, 0) : (1 - JourneyMotion.pageWords(t), 28 * JourneyMotion.pageWords(t))
        case .card: e == nil ? (1, 0) : (JourneyMotion.cardWords(t), 0)
        case .grid: e == nil ? (1, 0) : (JourneyMotion.otherWeeks(t), 0)
        case .month: e == nil ? (1, 0) : (JourneyMotion.monthWords(t), JourneyMotion.lerp(8, 0, JourneyMotion.monthWords(t)))
        }
        content.opacity(Double(opacity)).offset(y: lift)
    }
}

struct JourneyFlightHide: ViewModifier {
    enum Part: Equatable { case cardSurface, tile(Date), name(Date) }
    let part: Part
    @Environment(\.journeyMonthOpen) private var e
    func body(content: Content) -> some View {
        let hidden: Bool = {
            guard let e else { return false }
            switch part {
            case .cardSurface: return true
            case .tile(let d): return JourneyLog.monthStart(d) == e.flight.start
            case .name(let m): return m == e.flight.start
            }
        }()
        content.opacity(hidden ? 0 : 1)
    }
}

// MARK: - The month's pieces (JourneyMonth.swift)

extension View {
    /// The month's title: "Sep" on the card grows into it (scale, place, sage to ink, the rest of the name unrolling).
    func journeyFlightTitle(_ shown: Date) -> some View { modifier(JourneyFlightTitle(shown: shown)) }
    /// One day of the calendar (after its scale): reports its ring's square, draws its tile landing behind it, and tells the
    /// cell how much of its ring and number to draw (JourneyCellDraw).
    func journeyFlightCell(_ date: Date, scale: CGFloat) -> some View { modifier(JourneyFlightCellModifier(date: date, scale: scale)) }
    /// The month page's surface: clear while it opens over Journey, the page's own once it's open.
    func journeyFlightMonthSurface() -> some View { modifier(JourneyFlightMonthSurface()) }
}

struct JourneyFlightTitle: ViewModifier {
    let shown: Date
    @Environment(\.journeyMonthDial) private var e
    @Environment(\.journeyMonthOpen) private var open

    func body(content: Content) -> some View {
        let t = e?.dial ?? 1
        let z = e == nil ? 1 : JourneyMotion.zoom(t)
        let slot = JourneyFlightGeometry.shared.title
        let from = open?.flight.label
        let font = UIFont.systemFont(ofSize: 30, weight: .regular)
        let rounded = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 30)
        let short = (shown.formatted(.dateTime.month(.abbreviated)) as NSString).size(withAttributes: [.font: rounded]).width + 1
        let width = e == nil ? 10_000 : JourneyMotion.lerp(short, slot?.width ?? short, JourneyMotion.titleUnroll(t))
        let dx = from.flatMap { f in slot.map { f.minX - $0.minX } } ?? 0
        let dy = from.flatMap { f in slot.map { f.midY - $0.midY } } ?? 0
        let k = JourneyMotion.lerp(12.5 / 30, 1, z)
        // Placed by a hidden copy, never by the moving one: a frame read inside its own scale and offset feeds back into
        // them every frame (the lab's first try froze for 0.4–1.5 s).
        content.hidden()
            .journeyFlightPlace(.title(shown))
            .overlay(alignment: .leading) {
                content
                    .foregroundStyle(e == nil ? Color.primary : Color.sage.mix(with: Color.primary, by: Double(z)))
                    .mask(alignment: .leading) { Rectangle().frame(width: max(width, 1)) }
                    .scaleEffect(k, anchor: .leading)
                    .offset(x: (1 - z) * dx, y: (1 - z) * dy)
                    // No name on screen (scrolled off the card): the title fades in with the words instead.
                    .opacity(e == nil ? 1 : slot == nil ? 0 : from == nil ? Double(JourneyMotion.out(JourneyMotion.seg(t, 0.3, 0.8))) : 1)
            }
    }
}

struct JourneyFlightCellModifier: ViewModifier {
    let date: Date
    let scale: CGFloat
    @Environment(\.journeyMonthOpen) private var open

    func body(content: Content) -> some View {
        let mine = open.map { JourneyLog.monthStart(date) == $0.flight.start } ?? false
        let hidden = open?.hiddenDay == date
        Group {
            if mine, let open, let tile = open.flight.tiles[date] {
                content.modifier(JourneyFlightCellDial(date: date, scale: scale, tile: tile, hidden: hidden))
            } else if mine {
                content.modifier(JourneyFlightCellDial(date: date, scale: scale, tile: nil, hidden: hidden))
            } else {
                content.environment(\.journeyCellDraw, hidden ? JourneyCellDraw(ring: 0, number: 1, fill: 0) : .full)
            }
        }
        .journeyFlightPlace(.cell(date), scale: scale)
    }
}

/// The open month's own cells: these read the dial, every frame of the opening.
private struct JourneyFlightCellDial: ViewModifier {
    let date: Date
    let scale: CGFloat
    let tile: JourneyFlightTile?
    let hidden: Bool
    @Environment(\.journeyMonthDial) private var e
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let n = Calendar.current.component(.day, from: date)
        let t = e?.dial ?? 1
        let draw = JourneyCellDraw(ring: hidden ? 0 : JourneyMotion.ring(t, day: n),
                                   number: Double(JourneyMotion.number(t, day: n)),
                                   fill: hidden || t < 1 ? 0 : 1)
        content
            .environment(\.journeyCellDraw, draw)
            .background {
                if let tile, !hidden, t < 1 {
                    GeometryReader { g in tileFlight(tile, me: g.frame(in: .global), z: JourneyMotion.zoom(t), tint: JourneyMotion.tint(t)) }
                }
            }
    }

    /// The card's bar sliding and growing to this day's fill disc, rounding as it goes, its colour turning to the fill's (or
    /// fading where the day has none).
    private func tileFlight(_ tile: JourneyFlightTile, me: CGRect, z: CGFloat, tint: CGFloat) -> some View {
        let dark = scheme == .dark
        let disc = JourneyDayRing.fill * 2 * scale
        let end = CGRect(x: me.midX - disc / 2, y: me.midY - disc / 2, width: disc, height: disc)
        let start = tile.from ?? end.insetBy(dx: disc * 0.2, dy: disc * 0.2)
        let r = JourneyMotion.lerp(start, end, z)
        let corner = JourneyMotion.lerp(5, disc / 2, z)
        let from = JourneyTileColor.of(tile.kind, dark: dark)
        let color: Color = switch tile.fill {
        case .green: from.mix(with: JourneyDayRing.green(dark).opacity(0.24), by: Double(tint))
        case .grey: from.mix(with: JourneyDayRing.greyFill(dark), by: Double(tint))
        case .none: from.opacity(Double(1 - tint))
        }
        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX - me.minX, y: r.midY - me.minY)
            .opacity(tile.from == nil ? Double(z) : 1)
    }
}

struct JourneyFlightMonthSurface: ViewModifier {
    @Environment(\.journeyMonthDial) private var e
    func body(content: Content) -> some View { content.opacity(e.map { $0.dial >= 1 ? 1 : 0 } ?? 1) }
}

// MARK: - A ring that changes size (the month's F2 ring ↔ the day page's)

/// What a ring draws: each fifth's colour (nil: nothing), whether it's one closed ring, and its fill.
struct JourneyFlightRingSpec {
    var fifths: [Color?]
    var closed: Bool
    var closedColor: Color = .clear
    var closedOpacity: Double = 1

    /// The month's F2 look for a day (JourneyDayCell): closed and green / soft, or its fifths.
    static func month(day: JourneyLog.Day, today: Bool, dark: Bool) -> JourneyFlightRingSpec {
        if day.allFive && !today {
            // A closed ring is one colour drawn at full and faded as a group, so where its fifths meet nothing darkens.
            return JourneyFlightRingSpec(fifths: [], closed: true,
                                         closedColor: day.allInTime ? JourneyDayRing.green(dark) : (dark ? .white : .black),
                                         closedOpacity: day.allInTime ? 0.6 : (dark ? 0.40 : 0.36))
        }
        let fifths: [Color?] = day.marks.map { mark in
            switch mark {
            case .done, .excused: today ? JourneyDayRing.strong(dark) : JourneyDayRing.soft(dark)
            case .missed: JourneyDayRing.track(dark)
            case .toCome, .none: nil
            }
        }
        return JourneyFlightRingSpec(fifths: fifths, closed: false)
    }
}

/// Five arcs, Fajr at the top, clockwise. `gap` is each fifth's inset at either end in turns (F2: 7° = 0.0194; DayRing:
/// 0.014). A closed ring opens from 0. `drawn` trims each fifth from its start.
struct JourneyFlightRing: View {
    let spec: JourneyFlightRingSpec
    var drawn: CGFloat = 1
    var band: CGFloat = JourneyDayRing.band
    var gap: CGFloat = 7.0 / 360
    var closedGap: CGFloat = 0

    var body: some View {
        let style = StrokeStyle(lineWidth: band, lineCap: .round)
        ZStack {
            if spec.closed {
                if closedGap < 0.0005 {
                    Circle().trim(from: 0, to: drawn).stroke(spec.closedColor, style: style)
                } else {
                    ForEach(0..<5, id: \.self) { i in arc(i, gap: closedGap).stroke(spec.closedColor, style: style) }
                }
            } else {
                ForEach(0..<5, id: \.self) { i in
                    if spec.fifths.indices.contains(i), let c = spec.fifths[i] { arc(i, gap: gap).stroke(c, style: style) }
                }
            }
        }
        .compositingGroup()
        .opacity(spec.closed ? spec.closedOpacity : 1)
        .rotationEffect(.degrees(-90))
    }

    private func arc(_ i: Int, gap: CGFloat) -> some Shape {
        let from = CGFloat(i) / 5 + gap
        let full = CGFloat(i + 1) / 5 - gap
        return Circle().trim(from: from, to: from + (full - from) * drawn)
    }
}

/// Draws in screen terms: rects in global space; the canvas knows its own origin.
struct JourneyGlobalCanvas<Content: View>: View {
    @ViewBuilder let content: (CGPoint) -> Content
    var body: some View {
        GeometryReader { g in content(g.frame(in: .global).origin) }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - The host (Journey.swift)

/// A day opening over the month: which, where its ring left from and where it lands.
struct JourneyDayFlight: Equatable {
    var date: Date
    var from: CGRect?
    var to: CGRect?
}

extension View {
    /// Journey's page shows its months and their days through here: a month opened from the card (or This month) opens in
    /// place on the dial, a day on that month grows from its ring, and the left edge turns either back.
    func journeyMonthHost(month: Binding<JourneyMonthRoute?>, log: JourneyLog) -> some View {
        modifier(JourneyMonthHost(month: month, log: log))
    }
}

struct JourneyMonthHost: ViewModifier {
    @Binding var month: JourneyMonthRoute?
    let log: JourneyLog
    @State private var flight: JourneyMonthFlight?
    @State private var monthDial: CGFloat = 0
    @State private var day: JourneyDayFlight?
    @State private var dayDial: CGFloat = 0
    /// The edge swipe: which dial and where it was when the finger came down.
    @State private var backDrag: (day: Bool, from: CGFloat)?
    @State private var openerID = UUID()

    private var today: Date { PrayerDay.start() }
    private var width: CGFloat { UIScreen.main.bounds.width }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .allowsHitTesting(flight == nil)
                .background { if let flight { JourneyGrowingSurface(card: flight.card) } }
            if let flight {
                JourneyMonthPage(log: log, start: flight.start)
                    .modifier(JourneyMonthAway())
                    .environment(\.journeyDayOpener, JourneyDayOpener(id: openerID, open: { openDay($0) }))
                    .allowsHitTesting(day == nil && monthDial == 1)
            }
            if flight != nil && day == nil { edgeStrip }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .backgroundPreferenceValue(JourneyFlightAnchors.self) { anchors in
            GeometryReader { proxy in
                let _ = JourneyFlightGeometry.shared.resolve(anchors, in: proxy)
                Color.clear
            }
        }
        // The day over it all, not in the stack: the day page reaches into the top edge, and inside the stack it pulled the
        // month up under the clock (the lab's first try).
        .overlay {
            if let day {
                ZStack {
                    JourneyDayPage(date: day.date, firstDay: log.firstDay)
                        .allowsHitTesting(dayDial == 1)
                    if let to = day.to { JourneyFlyingDayRing(flight: day, to: to, log: log) }
                }
            }
        }
        .overlay(alignment: .leading) { if day != nil { edgeStrip } }
        .modifier(JourneyEntranceDriver(monthDial: monthDial, dayDial: dayDial, flight: flight, day: day))
        .environment(\.journeyMonthOpen, flight.map { JourneyMonthOpen(flight: $0, hiddenDay: day?.to == nil ? nil : day?.date) })
        .navigationBarBackButtonHidden(flight != nil)
        .toolbar {
            if flight != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)) }
                        .accessibilityLabel("Back")
                }
            }
        }
        .onChange(of: month) { _, route in
            if let route, flight == nil { openMonth(route.month) }
        }
    }

    private var edgeStrip: some View {
        Color.clear.frame(width: 22).frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(edgeBack)
            .ignoresSafeArea()
    }

    // MARK: Card → month

    private func openMonth(_ start: Date) {
        triggerSomeVibration(type: .light)
        let geo = JourneyFlightGeometry.shared
        geo.title = nil
        monthDial = 0
        flight = JourneyMonthFlight.make(start, log: log, today: today)
        // The dial runs once the month's title is laid out (the title flies to it).
        geo.onTitle = { runMonth(to: 1) }
    }

    private func runMonth(to target: CGFloat, how: String = "") {
        let remaining = abs(target - monthDial)
        guard remaining > 0.001 else { if target == 0 { close() }; return }
        JourneyFrameLog.shared.start(target == 1 ? "card → month" : "month → card")
        withAnimation(.linear(duration: JourneyMotion.monthDuration * remaining)) { monthDial = target } completion: {
            JourneyFrameLog.shared.stop(how)
            if target == 0 { close() }
        }
    }

    private func close() {
        flight = nil
        month = nil
    }

    /// Going back: the tiles land on the month the page shows now (it may have been paged), from where the card is now.
    private func retargetMonthForBack() {
        let geo = JourneyFlightGeometry.shared
        guard let shown = geo.shownMonth, shown != flight?.start else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { flight = JourneyMonthFlight.make(shown, log: log, today: today) }
    }

    // MARK: Month → day

    private func openDay(_ date: Date) {
        guard day == nil, date <= today, log.day(date).active, date < today || log.day(date).allFive else { return }
        triggerSomeVibration(type: .light)
        dayDial = 0
        day = JourneyDayFlight(date: date, from: JourneyFlightGeometry.shared.cells[date], to: nil)
        // The dial runs once the day page has laid out its disc (where to land) and read its rows (its heavy first moment:
        // Bradley's check of the lab — a real tap logged a 177 ms stall while the page loaded mid-flight).
        let spot = JourneyDayRingSpot.shared
        var landed: CGRect?
        var loaded = false
        func go() {
            guard let landed, loaded, self.day?.date == date, self.day?.to == nil else { return }
            spot.onReport = nil; spot.onLoaded = nil
            self.day?.to = landed
            DispatchQueue.main.async { runDay(to: 1) }
        }
        spot.onReport = { reported, frame in if reported == date { landed = frame; go() } }
        spot.onLoaded = { reported in if reported == date { loaded = true; go() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.day?.date == date, self.day?.to == nil else { return }
            spot.onReport = nil; spot.onLoaded = nil
            let d = CircleMotion.dayDiscDiameter
            self.day?.to = landed ?? CGRect(x: (width - d) / 2, y: JourneyDayPage.ringTop, width: d, height: d)
            runDay(to: 1)
        }
    }

    private func runDay(to target: CGFloat, how: String = "") {
        let remaining = abs(target - dayDial)
        guard remaining > 0.001 else { if target == 0 { day = nil }; return }
        JourneyFrameLog.shared.start(target == 1 ? "month → day" : "day → month")
        withAnimation(.linear(duration: JourneyMotion.dayDuration * remaining)) { dayDial = target } completion: {
            JourneyFrameLog.shared.stop(how)
            if target == 0 { day = nil }
        }
    }

    /// Going back from a day: the ring shrinks into the day on the page now (it may have been paged), from where it sits.
    private func retargetDayForBack() {
        let spot = JourneyDayRingSpot.shared
        guard var d = day, let date = spot.date else { return }
        d.date = date
        d.from = JourneyFlightGeometry.shared.cells[date]
        d.to = spot.frame
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { day = d }
    }

    // MARK: Back

    private func back() {
        if day != nil { retargetDayForBack(); runDay(to: 0, how: "button") }
        else if flight != nil { retargetMonthForBack(); runMonth(to: 0, how: "button") }
    }

    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                if backDrag == nil {
                    let onDay = day != nil
                    if onDay { retargetDayForBack() } else { retargetMonthForBack() }
                    backDrag = (onDay, onDay ? dayDial : monthDial)
                    JourneyFrameLog.shared.start(onDay ? "day → month (finger)" : "month → card (finger)")
                }
                guard let drag = backDrag else { return }
                let dial = min(max(drag.from - max(v.translation.width, 0) / width, 0), 1)
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { if drag.day { dayDial = dial } else { monthDial = dial } }
            }
            .onEnded { v in
                guard let drag = backDrag else { return }
                backDrag = nil
                JourneyFrameLog.shared.stop()
                let goes = v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2
                if drag.day { runDay(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
                else { runMonth(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
            }
    }
}

/// Puts the dials into the environment on every frame of their animation — the only view that redraws per frame; the
/// pages under it redraw only their small readers.
private struct JourneyEntranceDriver: ViewModifier, Animatable {
    var monthDial: CGFloat
    var dayDial: CGFloat
    let flight: JourneyMonthFlight?
    let day: JourneyDayFlight?
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(monthDial, dayDial) }
        set { monthDial = newValue.first; dayDial = newValue.second }
    }

    func body(content: Content) -> some View {
        let dials = flight.map { _ in JourneyMonthDial(dial: monthDial, dayDial: day == nil ? 0 : dayDial) }
        let land = JourneyMotion.dayLand
        let t = dayDial
        let dayEntrance: JourneyDayEntrance? = day == nil || t >= 1 ? nil : JourneyDayEntrance(
            page: Double(JourneyMotion.out(JourneyMotion.seg(t, 0, 0.3))),
            disc: t >= land ? 1 : 0,
            drawn: JourneyMotion.io(JourneyMotion.seg(t, land - 0.05, 1)),
            rest: Double(JourneyMotion.out(JourneyMotion.seg(t, 0.7, 1))))
        content
            .environment(\.journeyMonthDial, dials)
            .environment(\.journeyDayEntrance, dayEntrance)
    }
}

/// The month fading as a day opens over it.
private struct JourneyMonthAway: ViewModifier {
    @Environment(\.journeyMonthDial) private var e
    func body(content: Content) -> some View { content.opacity(Double(e.map { JourneyMotion.monthAway($0.dayDial) } ?? 1)) }
}

/// The card's surface growing into the page under everything, its shadow fading while it's still near the card's size (a
/// blurred shadow re-drawn at full-screen size every frame starved the renderer in the lab).
private struct JourneyGrowingSurface: View {
    let card: CGRect
    @Environment(\.journeyMonthDial) private var e
    var body: some View {
        let z = JourneyMotion.zoom(e?.dial ?? 1)
        if z < 0.15 {
            JourneyGlobalCanvas { o in
                let r = JourneyMotion.lerp(card, UIScreen.main.bounds, z)
                NeuRaised(shape: RoundedRectangle(cornerRadius: JourneyMotion.lerp(26, 56, z), style: .continuous))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX - o.x, y: r.midY - o.y)
                    .opacity(Double(1 - JourneyMotion.seg(z, 0, 0.15)))
            }
        }
    }
}

/// The tapped day's ring growing from its cell to the day page's ring: soft, its fill fading, a closed ring opening its gaps
/// as it lands, the raised disc growing with it and handing over to the page's own; then it fades as the colours draw in.
private struct JourneyFlyingDayRing: View {
    let flight: JourneyDayFlight
    let to: CGRect
    let log: JourneyLog
    @Environment(\.journeyMonthDial) private var e
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme

    var body: some View {
        let t = e?.dayDial ?? 1
        if t < 1 {
            JourneyGlobalCanvas { o in ring(o: o, t: t) }
        }
    }

    @ViewBuilder private func ring(o: CGPoint, t: CGFloat) -> some View {
        let land = JourneyMotion.dayLand
        let z = JourneyMotion.io(JourneyMotion.seg(t, 0, land))
        let soft = 1 - JourneyMotion.seg(t, land, 0.85)
        let landed = t >= land
        let dark = scheme == .dark
        let day = log.day(flight.date)
        // Today flies as the month draws it: strong fifths, never closed (Bradley's check).
        let spec = JourneyFlightRingSpec.month(day: day, today: flight.date == PrayerDay.start(), dark: dark)
        // From its cell's size (the month page draws days at 1 / 0.9 / 0.8 / 0.7).
        let cell = (flight.from?.height ?? JourneyDayRing.size) / JourneyDayRing.size
        let fromCentre = flight.from.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: to.midX, y: to.midY)
        let centre = JourneyMotion.lerp(fromCentre, CGPoint(x: to.midX, y: to.midY), z)
        // From a day not on the month (paged to another month): it only fades, at the page's size.
        let k = flight.from == nil ? 1 : z
        let radius = JourneyMotion.lerp(JourneyDayRing.radius * cell, 100, k)
        let band = JourneyMotion.lerp(JourneyDayRing.band * cell, theme.arc.width * 0.5, k)
        let gap = JourneyMotion.lerp(7.0 / 360, 0.014, k)
        let closedGap = JourneyMotion.lerp(0, 0.014, JourneyMotion.seg(k, 0.5, 1))
        let disc = JourneyMotion.lerp(JourneyDayRing.fill * 2 * cell, CircleMotion.dayDiscDiameter, k)
        let fill: Color? = spec.closed ? (day.allInTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark)) : nil
        ZStack {
            if !landed {
                NeuRaised(shape: Circle(), radius: 9 * k, offset: 4.5 * k)
                    .frame(width: disc, height: disc)
                    .opacity(Double(JourneyMotion.out(JourneyMotion.seg(k, 0.05, 0.6))))
            }
            if let fill {
                Circle().fill(fill).frame(width: disc, height: disc).opacity(Double(1 - JourneyMotion.seg(k, 0, 0.6)))
            }
            JourneyFlightRing(spec: spec, band: band, gap: gap, closedGap: closedGap)
                .frame(width: radius * 2, height: radius * 2)
                .opacity(Double(soft))
        }
        .position(x: centre.x - o.x, y: centre.y - o.y)
        .opacity(flight.from == nil ? Double(min(z * 2, 1)) : 1)
    }
}
