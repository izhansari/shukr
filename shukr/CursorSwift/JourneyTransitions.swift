import SwiftUI
import QuartzCore

// Journey's two transitions (owner, 2026-10-16, after trying them on his phone: "1a. … 2a looks alright for the most
// part"), first built on a test screen (removed 2026-10-16; owner: "lets test on the real thing from now on"):
// 1A, transition D — the card's month opens in place on one dial: the month's tiles fly to their days and land as each
// day's fill, its name grows into the title, the card's surface grows into the page, the rings close day by day.
// 2A, Bradley's plan — a day's ring grows from its cell into the day page's ring, soft, then the grade colours draw in.
// "the back swipe should undo it the same way": a swipe from the left edge turns the same dial backwards under the finger.
//
// How it fits together: JourneyPage carries `.journeyMonthHost(month:log:)`, which shows the month (JourneyMonthPage) as a
// layer over Journey's page and the day (JourneyDayPage) over that, and runs the dials. One small Animatable driver puts the
// dials in an observable object (JourneyMonthDial) that a display link advances; the environment carries only that object,
// which stays the same all flight, so nothing is walked per frame; only small leaf modifiers read
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
    /// When in the run the worst gap ended (ms from the start): the start's one-off build, or the motion itself.
    private var worstAt: CFTimeInterval = 0
    private var late = 0
    private var expected: CFTimeInterval = 1 / 60.0
    private var observer: CFRunLoopObserver?
    private var wokeAt: CFTimeInterval = 0
    private var longestBusy: CFTimeInterval = 0
    /// Which run is being logged: an animation that ends after a new run began (a spring-back under the next swipe) doesn't
    /// stop the new one.
    private(set) var run = 0

    @discardableResult func start(_ name: String) -> Int {
        run += 1
        link?.invalidate()
        self.name = name
        began = CACurrentMediaTime(); last = began
        frames = 0; worst = 0; worstAt = 0; late = 0
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
        return run
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        expected = max(l.targetTimestamp - l.timestamp, 1 / 120.0)
        if frames > 0 {
            let gap = now - last
            if gap > worst { worst = gap; worstAt = now - began }
            if gap > expected * 1.5 { late += 1 }
        }
        frames += 1
        last = now
    }

    func stop(_ how: String = "", run: Int? = nil) {
        guard let l = link, run == nil || run == self.run else { return }
        l.invalidate(); link = nil
        let ms = (CACurrentMediaTime() - began) * 1000
        let line = String(format: "%@ %@%@: %.0f ms, %d frames at %.0f Hz, worst %.1f ms (ending %.0f ms in), %d late, main busy ≤ %.0f ms",
                          Date().formatted(.iso8601), name, how.isEmpty ? "" : " (\(how))", ms, frames, 1 / expected, worst * 1000,
                          worstAt * 1000, late, longestBusy * 1000)
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
    /// The year's small months: each one's squares area and its name (global), written as they're laid out.
    var yearGrids: [Date: CGRect] = [:]
    var yearNames: [Date: CGRect] = [:]
    /// The month page is showing its year (the host's ‹ then fades back to Journey: no days on screen to fly).
    var yearShowing = false
    /// The month's day rings (global, the ring's own square at the page's scale).
    var cells: [Date: CGRect] = [:]
    /// The month title's slot, and the month it names (the page may have been paged since it opened).
    var title: CGRect?
    var shownMonth: Date?
    /// Called when the title's slot is first laid out (a month waiting to open).
    var onTitle: (() -> Void)?

    /// Runs `go` once the month's title is laid out — at once if no host resolves it (a month page shown on its own).
    func afterTitle(_ go: @escaping () -> Void) {
        var done = false
        onTitle = { if !done { done = true; go() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard !done else { return }
            done = true; self?.onTitle = nil; go()
        }
    }

    /// Runs `go` once the year has laid out `month`'s small month (a frame or two after it's shown).
    func whenYearReady(_ month: Date, tries: Int = 0, _ go: @escaping () -> Void) {
        guard yearGrids[month] == nil, tries < 12 else { go(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in self?.whenYearReady(month, tries: tries + 1, go) }
    }

    /// Where a day's bar is on the card now, from the card's row layout (JourneyHomeCard.row: a `nameColumn` pt name column,
    /// then seven bars 11 pt tall with 6 pt between; rows `pitch` apart under 12 pt of top room).
    func tile(_ date: Date) -> CGRect? {
        guard grid.width > 0, let row = weekStarts.lastIndex(where: { $0 <= date }) else { return nil }
        let col = Calendar.current.dateComponents([.day], from: weekStarts[row], to: date).day ?? 0
        guard (0..<7).contains(col) else { return nil }
        let name = JourneyHomeCard.nameColumn
        let barW = (grid.width - name - 6 * 7) / 7   // the grid's frame, not the ring's room past it
        let y = grid.minY + 12 + CGFloat(row) * JourneyHomeCard.pitch - gridOffset
        return CGRect(x: grid.minX + name + 6 + CGFloat(col) * (barW + 6), y: y, width: barW, height: 11)
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
            case .days(let month):
                // The month's day grid (JourneyCalendar: seven equal columns, rows a day tall at the page's scale, 2 pt
                // apart, after the week's lead) → each day's ring square.
                let cal = Calendar.current
                let lead = ((cal.component(.weekday, from: month) - cal.firstWeekday) + 7) % 7
                let side = JourneyDayRing.size * a.scale, colW = r.width / 7
                for (i, d) in JourneyLog.daysOf(month: month).enumerated() {
                    let at = lead + i
                    let cx = r.minX + (CGFloat(at % 7) + 0.5) * colW
                    let cy = r.minY + CGFloat(at / 7) * (side + 2) + side / 2
                    cells[d] = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
                }
            case .title(let m): title = r; shown = m
            }
        }
        self.cells = cells
        self.title = title; shownMonth = shown ?? shownMonth
        if title != nil, let go = onTitle { onTitle = nil; DispatchQueue.main.async { go() } }
    }
}

/// What reports its place: the card and its grid, a tile, a month's name, a calendar day, the month's title.
enum JourneyFlightPart: Hashable { case days(Date), title(Date) }
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
    /// Its corner where it starts: the card's bar 5, the year's square 2.5.
    var corner: CGFloat = 5
    /// Its shade where it starts (the card's and the year's heat map, JourneyTileColor).
    var rank: Double = 1
}

/// A month opening from the card: which, and the card's geometry frozen at the tap.
struct JourneyMonthFlight: Equatable {
    let start: Date
    let tiles: [Date: JourneyFlightTile]
    /// The month's name on the card, if it was in view.
    let label: CGRect?
    let card: CGRect
    /// The name where it starts: the card's 12.5 pt grey, or the year's 15 pt ink (no sage on Journey — owner, 2026-10-17).
    var labelSize: CGFloat = 12.5
    var labelGrey = true

    /// The flight for `start` from (or back to) its small month in the year: its squares where they are on screen now,
    /// worked out from its squares area (JourneyYearView: seven columns, 2.5 pt apart, square), and its name.
    @MainActor static func fromYear(_ start: Date, log: JourneyLog, today: Date) -> JourneyMonthFlight {
        let g = JourneyFlightGeometry.shared
        let cal = Calendar.current
        let lead = ((cal.component(.weekday, from: start) - cal.firstWeekday) + 7) % 7
        let screen = UIScreen.main.bounds
        var tiles: [Date: JourneyFlightTile] = [:]
        let grid = g.yearGrids[start] ?? .zero
        let gap: CGFloat = 2.5, side = (grid.width - 6 * gap) / 7
        for (i, date) in JourneyLog.daysOf(month: start).enumerated() {
            guard let first = log.firstDay, date >= first, date <= today else { continue }
            let d = log.day(date)
            let kind = d.tileKind
            let fill: JourneyFlightTile.Fill = d.allFive && date != today ? (d.allInTime ? .green : .grey) : .none
            let at = lead + i
            let r = CGRect(x: grid.minX + CGFloat(at % 7) * (side + gap), y: grid.minY + CGFloat(at / 7) * (side + gap), width: side, height: side)
            let from: CGRect? = grid.width > 0 && r.maxY > 60 && r.minY < screen.height - 40 ? r : nil
            tiles[date] = JourneyFlightTile(from: from, kind: kind, fill: fill, corner: 2.5, rank: log.tileRank(d))
        }
        return JourneyMonthFlight(start: start, tiles: tiles, label: g.yearNames[start], card: .zero,
                                  labelSize: 15, labelGrey: false)
    }

    /// The flight for `start` from where the card's pieces are now.
    @MainActor static func make(_ start: Date, log: JourneyLog, today: Date) -> JourneyMonthFlight {
        let g = JourneyFlightGeometry.shared
        let visible = g.grid.insetBy(dx: -1, dy: -1)
        var tiles: [Date: JourneyFlightTile] = [:]
        for date in JourneyLog.daysOf(month: start) {
            guard let first = log.firstDay, date >= first, date <= today else { continue }
            let d = log.day(date)
            let kind = d.tileKind
            let fill: JourneyFlightTile.Fill = d.allFive && date != today ? (d.allInTime ? .green : .grey) : .none
            // A tile partly under the grid's top fade or outside its clip doesn't fly (it would appear outside the card).
            let from = g.tile(date).flatMap { r in r.minY >= visible.minY + 8 && r.maxY <= visible.maxY ? r : nil }
            tiles[date] = JourneyFlightTile(from: from, kind: kind, fill: fill, rank: log.tileRank(d))
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

/// The dials: read only by the few pieces that move (the open month's own cells, the fades, the title, the flying ring).
/// An observable object put in the environment once per flight, advanced by a display link — not a value set in the
/// environment every frame: that made SwiftUI walk all of Journey, the month and its calendars every frame (his 13 Pro Max,
/// a Time Profiler trace of the real Journey: AttributeGraph's update and propagate-dirty the top of the main thread).
@MainActor @Observable final class JourneyMonthDial {
    /// Card (or year) → month: 0 the card, 1 the month.
    var dial: CGFloat = 0
    /// A day opening over the month (0 none … 1 open).
    var dayDial: CGFloat = 0

    enum Key { case month, day }
    @ObservationIgnored private var runs: [Key: (from: CGFloat, to: CGFloat, start: CFTimeInterval, duration: Double, done: () -> Void)] = [:]
    @ObservationIgnored private var ticker: JourneyDialTicker?

    func value(_ k: Key) -> CGFloat { k == .month ? dial : dayDial }

    /// Straight to a value (a finger, or a start): any run of that dial stops.
    func set(_ k: Key, _ v: CGFloat) {
        runs[k] = nil
        write(k, v)
    }

    /// Linearly to `to` over `duration` (the beats ease on their own stretches), then `done`.
    func animate(_ k: Key, to target: CGFloat, duration: Double, done: @escaping () -> Void) {
        runs[k] = (value(k), target, CACurrentMediaTime(), max(duration, 0.001), done)
        if ticker == nil { ticker = JourneyDialTicker { [weak self] now in self?.tick(now) } }
    }

    private func write(_ k: Key, _ v: CGFloat) {
        if k == .month { if dial != v { dial = v } } else { if dayDial != v { dayDial = v } }
    }

    private func tick(_ now: CFTimeInterval) {
        var finished: [() -> Void] = []
        for (k, r) in runs {
            let p = min(max((now - r.start) / r.duration, 0), 1)
            write(k, r.from + (r.to - r.from) * CGFloat(p))
            if p >= 1 { runs[k] = nil; finished.append(r.done) }
        }
        if runs.isEmpty { ticker?.stop(); ticker = nil }
        finished.forEach { $0() }
    }
}

/// The display link behind JourneyMonthDial (120 Hz where the phone can).
@MainActor final class JourneyDialTicker: NSObject {
    private var link: CADisplayLink?
    private let onTick: (CFTimeInterval) -> Void
    init(_ onTick: @escaping (CFTimeInterval) -> Void) {
        self.onTick = onTick
        super.init()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func tick(_ l: CADisplayLink) { onTick(l.targetTimestamp) }
    func stop() { link?.invalidate(); link = nil }
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
    /// A month's name on the card: reports where it is, hidden while that month is open (it became the title).
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
    /// The month's title: "Sep" on the card grows into it (scale, place, grey to ink, the rest of the name unrolling).
    func journeyFlightTitle(_ shown: Date) -> some View { modifier(JourneyFlightTitle(shown: shown)) }
    /// One day of the calendar (after its scale): tells the cell how much of its ring, number and fill to draw
    /// (JourneyCellDraw).
    func journeyFlightCell(_ date: Date, scale: CGFloat) -> some View { modifier(JourneyFlightCellModifier(date: date, scale: scale)) }
    /// The month page's surface: clear while it opens over Journey, the page's own once it's open.
    func journeyFlightMonthSurface() -> some View { modifier(JourneyFlightMonthSurface()) }
    /// A month's grid of days: one place for all of them (each day's square is worked out from it). One anchor a calendar,
    /// not one a day: the anchors' merging was ~42 ms of every year open on his 13 Pro Max (the organizer's trace).
    func journeyFlightDays(_ month: Date, scale: CGFloat) -> some View { journeyFlightPlace(.days(month), scale: scale) }
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
        let k = JourneyMotion.lerp((open?.flight.labelSize ?? 12.5) / 30, 1, z)
        // Placed by a hidden copy, never by the moving one: a frame read inside its own scale and offset feeds back into
        // them every frame (the lab's first try froze for 0.4–1.5 s).
        content.hidden()
            .journeyFlightPlace(.title(shown))
            .overlay(alignment: .leading) {
                content
                    .foregroundStyle(e == nil ? Color.primary
                                     : ((open?.flight.labelGrey ?? true) ? Color.secondary : Color.primary).mix(with: Color.primary, by: Double(z)))
                    // Scaled, not sized: a mask whose frame changed every frame re-laid the page out every frame.
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: slot?.width ?? 400)
                            .scaleEffect(x: e == nil ? 1 : min(max(width, 1) / max(slot?.width ?? 400, 1), 1), anchor: .leading)
                    }
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
        content.environment(\.journeyCellDraw, draw)
    }

}

/// Every landing tile of the open month in one Canvas, under the month's rings and numbers: the card's bar (or the year's
/// square) sliding and growing to its day's fill disc, rounding as it goes, its colour turning to the fill's (or fading where
/// the day has none). One drawing, no layout: drawn per cell (a GeometryReader behind each, its tile a new size every frame),
/// the page was laid out every frame and its four-size layout rebuilt all three calendars each time (~75 rebuilds an opening).
struct JourneyFlyingTiles: View {
    @Environment(\.journeyMonthDial) private var e
    @Environment(\.journeyMonthOpen) private var open
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = e?.dial ?? 1
        // Mounted all the while a month is open, drawing nothing at rest: inserted on the first frame of a flight back, it
        // cost that frame ~60 ms on his 13 Pro Max.
        if let open {
            let z = JourneyMotion.zoom(t), tint = JourneyMotion.tint(t)
            let dark = scheme == .dark
            let cells = JourneyFlightGeometry.shared.cells
            JourneyGlobalCanvas { o in
                Canvas { ctx, _ in
                    guard t < 1 else { return }
                    for (date, tile) in open.flight.tiles where open.hiddenDay != date {
                        guard let cell = cells[date] else { continue }
                        let scale = cell.height / JourneyDayRing.size
                        let disc = JourneyDayRing.fill * 2 * scale
                        let end = CGRect(x: cell.midX - disc / 2, y: cell.midY - disc / 2, width: disc, height: disc)
                        let start = tile.from ?? end.insetBy(dx: disc * 0.2, dy: disc * 0.2)
                        let r = JourneyMotion.lerp(start, end, z).offsetBy(dx: -o.x, dy: -o.y)
                        let corner = JourneyMotion.lerp(tile.corner, disc / 2, z)
                        let from = JourneyTileColor.of(tile.kind, rank: tile.rank, dark: dark)
                        let color: Color = switch tile.fill {
                        case .green: from.mix(with: JourneyDayRing.green(dark).opacity(0.24), by: Double(tint))
                        case .grey: from.mix(with: JourneyDayRing.greyFill(dark), by: Double(tint))
                        case .none: from.opacity(Double(1 - tint))
                        }
                        ctx.opacity = tile.from == nil ? Double(z) : 1
                        ctx.fill(Path(roundedRect: r, cornerRadius: corner, style: .continuous), with: .color(color))
                    }
                }
            }
        }
    }
}

struct JourneyFlightMonthSurface: ViewModifier {
    @Environment(\.journeyMonthDial) private var e
    func body(content: Content) -> some View { content.opacity(e.map { $0.dial >= 1 ? 1 : 0 } ?? 1) }
}

// MARK: - Month ↔ year (JourneyMonth.swift, JourneyYear.swift)

extension View {
    /// A small month's squares in the year: reports where they are, hides them while that month flies in or out of them,
    /// and fades with the year's other months.
    func journeyFlightYearSquares(_ start: Date) -> some View {
        background { JourneyFlightReport { JourneyFlightGeometry.shared.yearGrids[start] = $0 } }
            .modifier(JourneyFlightHide(part: .name(start)))
            .modifier(JourneyFlightFade(part: .grid))
    }
    /// A small month's name in the year: reports where it is, hidden while the month's title flies from or back to it.
    func journeyFlightYearName(_ start: Date) -> some View {
        background { JourneyFlightReport { JourneyFlightGeometry.shared.yearNames[start] = $0 } }
            .modifier(JourneyFlightHide(part: .name(start)))
    }
}

/// The month page's own dial for month ↔ year: while it runs, it is what's open and how far (the month's days, title and
/// words read it exactly as they read the card's); idle, the month inherits the host's and the year (`clearWhenIdle`)
/// sees nothing open — so the year never fades or hides for a card flight.
struct JourneyYearFlightDriver: ViewModifier {
    let dials: JourneyMonthDial
    let flight: JourneyMonthFlight?
    let clearWhenIdle: Bool
    @Environment(\.journeyMonthOpen) private var hostOpen
    @Environment(\.journeyMonthDial) private var hostDial

    func body(content: Content) -> some View {
        content
            .environment(\.journeyMonthOpen, flight.map { JourneyMonthOpen(flight: $0) } ?? (clearWhenIdle ? nil : hostOpen))
            .environment(\.journeyMonthDial, flight != nil ? dials : (clearWhenIdle ? nil : hostDial))
    }
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
    @State private var day: JourneyDayFlight?
    /// The dials (one object all flight; the leaf pieces read it). Taps wait for a flight to land through a leaf gate that
    /// reads them (JourneyHitGate): a settled flag here redrew the host — and rebuilt the month page — on the first frame of
    /// every flight back (a ~60 ms start on his 13 Pro Max).
    @State private var dials = JourneyMonthDial()
    /// The edge swipe: which dial and where it was when the finger came down.
    @State private var backDrag: (day: Bool, from: CGFloat)?
    /// The edge swipe claims only a drag that starts sideways; one that starts up or down is the month's paging, left alone.
    @State private var edgeSideways: Bool?
    @State private var openerID = UUID()
    /// Back from the year: Journey shown at rest under the month layer, which fades out over it.
    @State private var fadingOut = false
    @State private var outFade: CGFloat = 0

    private var today: Date { PrayerDay.start() }
    private var width: CGFloat { UIScreen.main.bounds.width }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .allowsHitTesting(flight == nil)
                .modifier(JourneyFlightClear(active: fadingOut))
            // Over Journey's page (its own background is opaque — under it, the card had no shadow all flight and it popped
            // back on the last frame: Sami's check of 7174d7c7), drawn only outside the card's shape.
            if let flight { JourneyGrowingSurface(card: flight.card) }
            if let flight {
                JourneyMonthPage(log: log, start: flight.start)
                    .modifier(JourneyMonthAway())
                    .environment(\.journeyDayOpener, JourneyDayOpener(id: openerID, open: { openDay($0) }))
                    .modifier(JourneyHitGate(dials: dials, key: .month, open: day == nil && !fadingOut))
                    .opacity(1 - outFade)
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
                        .modifier(JourneyHitGate(dials: dials, key: .day, open: true))
                    if let to = day.to { JourneyFlyingDayRing(flight: day, to: to, log: log) }
                }
            }
        }
        .overlay(alignment: .leading) { if day != nil { edgeStrip } }
        .environment(\.journeyMonthDial, flight == nil ? nil : dials)
        .environment(\.journeyDayEntrance, day == nil ? nil : JourneyDayEntrance(source: dials))
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
        .task { await autoRun() }
    }

    /// `-demoJourneyFlightRun [N]`: the real Journey's flights N times with no finger (default 5) — card → month → a day →
    /// back → back — for the frame log on a phone in Release (the real pages, not a stand-in).
    private func autoRun() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoJourneyFlightRun") else { return }
        let n = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 5 : 5
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(3)
        let latest = JourneyLog.monthStart(today)
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: latest) ?? latest
        let log = JourneyLog.last ?? log   // the task's copy of the host was taken before the log loaded
        let m = log.month(latest).activeDays >= 14 ? latest : previous
        for _ in 0..<n {
            month = JourneyMonthRoute(month: m)
            await wait(JourneyMotion.monthDuration + 1.2)
            if let d = JourneyLog.daysOf(month: m).filter({ $0 < today && log.day($0).active }).last {
                openDay(d)
                await wait(JourneyMotion.dayDuration + 1.6)
                back()
                await wait(JourneyMotion.dayDuration + 1)
            }
            back()
            await wait(JourneyMotion.monthDuration + 1.2)
        }
        print("🎞️ journey auto run done")
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
        dials.set(.month, 0)
        flight = JourneyMonthFlight.make(start, log: log, today: today)
        // The dial runs once the month's title is laid out (the title flies to it).
        geo.onTitle = { runMonth(to: 1) }
    }

    private func runMonth(to target: CGFloat, how: String = "") {
        let remaining = abs(target - dials.dial)
        guard remaining > 0.001 else { if target == 0 { close() }; return }
        let run = JourneyFrameLog.shared.start(target == 1 ? "card → month" : "month → card")
        dials.animate(.month, to: target, duration: JourneyMotion.monthDuration * Double(remaining)) {
            JourneyFrameLog.shared.stop(how, run: run)
            if target == 0 { close() }
        }
    }

    private func close() {
        flight = nil
        month = nil
        JourneyFlightGeometry.shared.yearShowing = false
    }

    /// Back while the month page shows its year: Journey at rest underneath, the month layer fading out over it (no days on
    /// screen to fly). A plain removal transition dropped the year in one frame and faded only Journey in.
    private func fadeFromYear() {
        guard !fadingOut else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { fadingOut = true }
        withAnimation(.easeOut(duration: CircleMotion.standard)) { outFade = 1 } completion: {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                close()
                outFade = 0
                fadingOut = false
            }
        }
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
        let log = JourneyLog.last ?? log   // the auto run's copy of the host was taken before the log loaded
        guard day == nil, date <= today, log.day(date).active, date < today || log.day(date).allFive else { return }
        triggerSomeVibration(type: .light)
        dials.set(.day, 0)
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
        let remaining = abs(target - dials.dayDial)
        guard remaining > 0.001 else { if target == 0 { day = nil }; return }
        let run = JourneyFrameLog.shared.start(target == 1 ? "month → day" : "day → month")
        dials.animate(.day, to: target, duration: JourneyMotion.dayDuration * Double(remaining)) {
            JourneyFrameLog.shared.stop(how, run: run)
            if target == 0 { day = nil; dials.set(.day, 0) }
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

    /// The ‹: on the next turn of the run loop, outside the toolbar button's own transaction — a tap near the edge of its
    /// circle ran the action with animations off and the month cut straight to Journey (Sami's check of 7174d7c7: the same
    /// spot flew or cut from run to run).
    private func back() {
        DispatchQueue.main.async {
            if day != nil { retargetDayForBack(); runDay(to: 0, how: "button") }
            else if flight != nil && JourneyFlightGeometry.shared.yearShowing { fadeFromYear() }
            else if flight != nil { retargetMonthForBack(); runMonth(to: 0, how: "button") }
        }
    }

    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                if edgeSideways == nil { edgeSideways = abs(v.translation.width) >= abs(v.translation.height) }
                guard edgeSideways == true, day != nil || !JourneyFlightGeometry.shared.yearShowing else { return }
                if backDrag == nil {
                    let onDay = day != nil
                    if onDay { retargetDayForBack() } else { retargetMonthForBack() }
                    backDrag = (onDay, onDay ? dials.dayDial : dials.dial)
                    JourneyFrameLog.shared.start(onDay ? "day → month (finger)" : "month → card (finger)")
                }
                guard let drag = backDrag else { return }
                let dial = min(max(drag.from - max(v.translation.width, 0) / width, 0), 1)
                dials.set(drag.day ? .day : .month, dial)
            }
            .onEnded { v in
                defer { edgeSideways = nil }
                if backDrag == nil, edgeSideways == true, day == nil, JourneyFlightGeometry.shared.yearShowing,
                   v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2 {
                    fadeFromYear()   // the year: a swipe from the edge fades back to Journey
                    return
                }
                guard let drag = backDrag else { return }
                backDrag = nil
                JourneyFrameLog.shared.stop()
                let goes = v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2
                if drag.day { runDay(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
                else { runMonth(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
            }
    }
}

/// A hidden copy that only measures (the month page's size picker): never animates, never reports a place, takes no taps.
struct JourneyFlightStill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.journeyMonthOpen, nil)
            .environment(\.journeyMonthDial, nil)
            .transformPreference(JourneyFlightAnchors.self) { $0 = [:] }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Taps through only once a flight has landed — read from the live dial here, so the host never redraws for it.
private struct JourneyHitGate: ViewModifier {
    let dials: JourneyMonthDial
    let key: JourneyMonthDial.Key
    let open: Bool
    func body(content: Content) -> some View { content.allowsHitTesting(open && dials.value(key) >= 1) }
}

/// Journey's page as at rest: no month open as far as its pieces know (the back from the year).
private struct JourneyFlightClear: ViewModifier {
    let active: Bool
    @Environment(\.journeyMonthOpen) private var open
    @Environment(\.journeyMonthDial) private var dial
    func body(content: Content) -> some View {
        content
            .environment(\.journeyMonthOpen, active ? nil : open)
            .environment(\.journeyMonthDial, active ? nil : dial)
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
                let shape = RoundedRectangle(cornerRadius: JourneyMotion.lerp(26, 56, z), style: .continuous)
                NeuRaised(shape: shape)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX - o.x, y: r.midY - o.y)
                    .opacity(Double(1 - JourneyMotion.seg(z, 0, 0.15)))
                    // Only its shadow: the card's own words and weeks show through where the surface is.
                    .mask {
                        ZStack {
                            Rectangle()
                            shape.frame(width: r.width, height: r.height).position(x: r.midX - o.x, y: r.midY - o.y)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
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
