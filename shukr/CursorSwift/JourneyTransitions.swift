import SwiftUI
import QuartzCore

// Journey's two transitions (owner, 2026-10-16, after trying them on his phone: "1a. … 2a looks alright for the most
// part"), first built on a test screen (removed 2026-10-16; owner: "lets test on the real thing from now on"):
// 1A, transition D — the card's month opens in place on one dial: the month's tiles fly to their days and land as each
// day's fill, its name grows into the title, the card's surface grows into the page, the rings close day by day.
// 2A, Bradley's plan — a day's ring grows from its cell into the day page's ring, soft, then the grade colours draw in.
// "the back swipe should undo it the same way": a swipe from the left edge turns the same dial backwards under the finger.
//
// How it fits together: JourneyPage carries `.journeyMonthHost(month:log:stats:)`, which shows the card expanded
// (JourneyExpandedPage) as a layer over Journey's page and the day (JourneyDayPage) over that, and runs the dials. One small Animatable driver puts the
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
    /// A flying day's ring drawing closed, then its number, by its place among them (0 the first … 1 the last): the expanded
    /// card lands 80-odd days, and by day of the month the last ones' rings ran past the dial's end.
    static func ring(_ t: CGFloat, at p: CGFloat) -> CGFloat { let a = 0.6 + p * 0.18; return io(seg(t, a, a + 0.2)) }
    static func number(_ t: CGFloat, at p: CGFloat) -> CGFloat { let a = 0.6 + p * 0.18; return out(seg(t, a + 0.02, a + 0.2)) }
    /// Going back to the card, ring by ring (owner, 2026-10-17, his pick: "going back, the rings undraw ring by ring over a
    /// longer stretch (t 1.0 to 0.6) so it's about 20 a frame instead of 50 — same look, smoother start"): each ring a short
    /// window, the last drawn first, spread over the whole stretch. The forward windows overlap, so run backwards ~50 rings
    /// un-drew in each of the back's first frames (the ~35 ms start on his 13 Pro Max).
    static func ringBack(_ t: CGFloat, at p: CGFloat) -> CGFloat { let a = 0.6 + p * 0.32; return io(seg(t, a, a + 0.08)) }
    static func numberBack(_ t: CGFloat, at p: CGFloat) -> CGFloat { let a = 0.6 + p * 0.32; return out(seg(t, a + 0.01, a + 0.08)) }
    /// A flying month name's width at `size` (the card's and the labels' face: rounded, regular).
    @MainActor static func nameWidth(_ word: String, size: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return ceil((word as NSString).size(withAttributes: [.font: font]).width)
    }
    /// A card month name landing on its label: the label's own name takes over as the flying one goes.
    static func nameLand(_ t: CGFloat) -> CGFloat { out(seg(t, 0.72, 0.9)) }
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

    /// On in DEBUG builds, or with `-journeyFrameLog` / `-demoJourneyFlightRun` (a Release measurement on his phone): never in
    /// what ships — a 120 Hz link and a file write per run, and a run-loop observer on every wake of the app while it runs.
    static let on: Bool = {
        #if DEBUG
        return true
        #else
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-journeyFrameLog") || args.contains("-demoJourneyFlightRun") || args.contains("-demoJourneyYearRun")
        #endif
    }()

    @discardableResult func start(_ name: String) -> Int {
        JourneyPerf.began(name)   // the perf log's window too (JourneyPerf.swift)
        run += 1
        guard Self.on else { return run }
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

    /// A line about the host's state (a flight opened, closed, cleared; a swipe cancelled): when Journey stops taking taps,
    /// the log says what was still open (his phone, 2026-10-17: "best streak" dead until a relaunch).
    func note(_ what: String) {
        let line = "\(Date().formatted(.iso8601)) · \(what)"
        print("🎞️ \(line)")
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("journey-transitions.log")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
    }

    func stop(_ how: String = "", run: Int? = nil) {
        guard let l = link, run == nil || run == self.run else { return }
        l.invalidate(); link = nil
        // The observer only watches a run: left on, it woke with every turn of the main run loop for good.
        if let o = observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), o, .commonModes); observer = nil }
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
/// Who writes what (measurement, not state — every value is overwritten as it's laid out again):
/// - `card`, `grid`, `gridOffset`, `weekStarts`, `names`: the card's report modifiers (`journeyFlightCard` / `…Grid` /
///   `…MonthName`, below) → read by `tile(_:)` and `JourneyMonthFlight.expanded` (the card's tiles flying to the
///   calendar).
/// - `cells`, `labels`, `cardRows`: `resolve`, from the host's anchors (the calendar's week rows and month labels, the
///   card's rows) → read by the flights' landings and `tile(_:)` / `cardWeeksInView`.
/// - `yearGrids`, `yearNames`, `yearShowing`, `yearBack`: the year (`journeyFlightYearSquares` / `…YearName`;
///   JourneyExpandedPage's `toYear` / `fromYear`, cleared by the host's `close`) → read by
///   `JourneyMonthFlight.fromYear` and the host's ‹ / edge swipe.
/// - `topRing`: a picked day's ring at the top (JourneyFlightTopRing) → read by the day's flight.
/// - `expandedWeeks`, `expandedPick`: JourneyExpandedPage as it scrolls / picks → `follow()` (the card follows them).
/// - `cardShow` (JourneyHomeCard), `onFollow` (JourneyMonthHost's `openMonth`), `onWeeks` (`afterWeeks`): callbacks.
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
    /// The month page is showing its year: the host's ‹ and edge swipe then go back to the month (`yearBack`, the month
    /// page's own year → month flight; owner, 2026-10-17: "this back chevron from the year page. It should go back to the
    /// month page"), and only without one fade back to Journey.
    var yearShowing = false
    var yearBack: (() -> Void)?
    /// The month's day rings (global, the ring's own square at the page's scale).
    var cells: [Date: CGRect] = [:]
    /// The card's week rows laid out (their seven bars' rect, global), by week start.
    var cardRows: [Date: CGRect] = [:]
    /// The expanded card's month labels (their names, global): the card's month names fly to them.
    var labels: [Date: CGRect] = [:]
    /// A picked day's ring at the top (JourneyDayTop, global): the card's day flies from it.
    var topRing: (date: Date, frame: CGRect)?
    /// Called when the expanded card's weeks are next laid out (a flight waiting for its landing places).
    var onWeeks: (() -> Void)?

    /// Runs `go` once the expanded card's week rows are laid out — after a beat at the latest.
    func afterWeeks(_ go: @escaping () -> Void) {
        var done = false
        onWeeks = { if !done { done = true; go() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard !done else { return }
            done = true; self?.onWeeks = nil; go()
        }
    }

    // The card follows the expanded card's weeks (E6; owner, 2026-10-17, back from weeks scrolled far from today: "it just
    // kind of faded everything out and then faded everything in"): the card under the page is quietly scrolled to the week
    // in the middle of the expanded view (or its picked day's), and the host's flight takes its tiles from there — so the
    // way back always has tiles to morph into, and the card stays on those weeks after, as a scroll of yours would leave it.
    // Done once the expanded view has been still a moment, never per scroll frame: the way back starts at once.

    /// The card's grid quietly brought to the expanded view's weeks (JourneyHomeCard sets it); true if it moved.
    var cardShow: ((_ weeks: [Date], _ pick: Date?) -> Bool)?
    /// The host's side: the card to the weeks, then the flight's tiles from it; `done` after (JourneyMonthHost sets it).
    var onFollow: ((_ done: @escaping () -> Void) -> Void)?
    /// The expanded view's weeks on screen (oldest first) and its picked day's week, as it last reported them.
    var expandedWeeks: [Date] = []
    var expandedPick: Date?
    private var followWork: DispatchWorkItem?
    private var wanted = false
    private var flushes: [() -> Void] = []
    private var following = false

    /// The expanded view's weeks or pick changed: the card follows once they've been still a moment.
    func follow() {
        wanted = true
        followWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runFollow() }
        followWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Before a flight back: a follow still waiting runs now, then `go` (at once if none is).
    func flushFollow(_ go: @escaping () -> Void) {
        guard wanted || following else { go(); return }
        flushes.append(go)
        guard !following else { return }
        followWork?.cancel()
        runFollow()
    }

    /// Whether a flight back must wait for a follow (the edge swipe holds its dial at the page until it's done).
    var followPending: Bool { wanted || following }

    private func runFollow() {
        followWork = nil
        guard wanted, let onFollow else { wanted = false; finishFollow(); return }
        wanted = false
        following = true
        onFollow { [weak self] in self?.finishFollow() }
    }

    private func finishFollow() {
        following = false
        // A newer week came in meanwhile: a waiting flight back takes that one too.
        if wanted, !flushes.isEmpty { runFollow(); return }
        let f = flushes
        flushes = []
        f.forEach { $0() }
    }

    /// The page closed: nothing left to follow.
    func cancelFollow() {
        followWork?.cancel()
        followWork = nil
        wanted = false
        expandedWeeks = []
        expandedPick = nil
    }

    /// The card's week rows on screen now (oldest first): laid out and inside its grid, clear of the fade at its top — by
    /// the rows' own reports (the grid's visibility callback can lag: on a fresh launch its range read Nov – Feb over Aug – Oct).
    func cardWeeksInView() -> [Date] {
        cardRows.filter { $0.value.minY >= grid.minY + 8 && $0.value.maxY <= grid.maxY + 1 }.keys.sorted()
    }

    /// The card's middle week while it isn't resting at today (the ↗ opens the expanded view there); nil at today.
    func cardMiddle() -> Date? {
        let shown = cardWeeksInView()
        guard !shown.isEmpty, let last = weekStarts.last, !shown.contains(last) else { return nil }
        return shown[shown.count / 2]
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
        // Its row's own place when it's laid out: seven bars 6 pt apart across it, 11 pt tall.
        if let r = cardRows[weekStarts[row]] {
            let col = Calendar.current.dateComponents([.day], from: weekStarts[row], to: date).day ?? 0
            guard (0..<7).contains(col) else { return nil }
            let barW = (r.width - 6 * 6) / 7
            return CGRect(x: r.minX + CGFloat(col) * (barW + 6), y: r.midY - 5.5, width: barW, height: 11)
        }
        // Rows report themselves: one that didn't isn't laid out (off the grid) — never the arithmetic below for it.
        guard cardRows.isEmpty else { return nil }
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
        var labels: [Date: CGRect] = [:]
        var cardRows: [Date: CGRect] = [:]
        var weeks = 0
        for (part, a) in anchors {
            let r = proxy[a.anchor].offsetBy(dx: o.x, dy: o.y)
            switch part {
            case .label(let m): labels[m] = r
            case .cardWeek(let start): cardRows[start] = r
            case .week(let start):
                weeks += 1
                // The expanded card's week row (JourneyExpanded.swift): its seven rings across the rect, one ring tall.
                let side = JourneyDayRing.size * a.scale, colW = r.width / 7
                for i in 0..<7 {
                    guard let d = Calendar.current.date(byAdding: .day, value: i, to: start) else { continue }
                    let cx = r.minX + (CGFloat(i) + 0.5) * colW
                    cells[d] = CGRect(x: cx - side / 2, y: r.midY - side / 2, width: side, height: side)
                }
            }
        }
        self.cells = cells
        self.labels = labels
        self.cardRows = cardRows
        // A flight waiting runs once its landing (the expanded card's weeks) is laid out.
        if weeks > 0, let go = onWeeks { onWeeks = nil; DispatchQueue.main.async { go() } }
    }
}

/// What reports its place: a card week row's bars, an expanded week row's rings, an expanded month label.
enum JourneyFlightPart: Hashable { case week(Date), label(Date), cardWeek(Date) }
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
    /// The card's week row (its seven bars): where each bar is, read when a flight starts — the scroll offset can't say (the
    /// lazy grid's rows above the screen are estimated, so row × pitch − offset landed ~9 rows off on the sim).
    func journeyFlightCardWeek(_ start: Date) -> some View { journeyFlightPlace(.cardWeek(start)) }
    /// The expanded card's week row: one place for its seven days (each ring's square is worked out from it).
    func journeyFlightWeek(_ start: Date, scale: CGFloat) -> some View { journeyFlightPlace(.week(start), scale: scale) }
    /// The expanded card's month label (its name): the card's month name flies to it, and it shows once that lands.
    func journeyFlightLabel(_ month: Date) -> some View { journeyFlightPlace(.label(month)).modifier(JourneyFlightLabelLand(month: month)) }
}

// MARK: - What a running transition knows

/// One of the month's days as it opens: where its tile was on the card (nil: not in view, it grows in place), the tile's
/// colour and what it lands as.
struct JourneyFlightTile: Equatable {
    enum Fill: Equatable { case none, green, grey }
    let from: CGRect?
    let kind: YourJourneyStats.Kind
    let fill: Fill
    /// Its corner where it starts: the card's bar (JourneyHomeCard.corner), the year's square 2.5.
    var corner: CGFloat = JourneyHomeCard.corner
    /// Its shade where it starts (the card's and the year's heat map, JourneyTileColor).
    var rank: Double = 1
    /// Before the fresh start: dimmed the whole way, as it is at both ends.
    var counted = true
}

/// Days flying between the card (or a year's small month) and the expanded card's rings, with the geometry frozen at the tap.
struct JourneyMonthFlight: Equatable {
    /// The month opened (focused, or this one) — or the year's month flying.
    let start: Date
    let tiles: [Date: JourneyFlightTile]
    let card: CGRect
    /// Each flying day's place among them (0 the first … 1 the last): its ring is drawn in by it.
    var order: [Date: CGFloat] = [:]
    /// The card's month names in view, each flying to its label, and their words (the card rows' labels, "Jul’26").
    var names: [Date: CGRect] = [:]
    var nameWords: [Date: String] = [:]
    /// Each name's size as the card draws it: 12.5 pt, less where its 11 pt row shrinks it (the row's minimumScaleFactor —
    /// ~9.5 pt on his phones). The flying name lands at it: at 12.5 it shrank and slid as the card's own took over (owner,
    /// 2026-10-17: "it doesn't feel very fluid … And it jumps at the end").
    var nameSizes: [Date: CGFloat] = [:]
    /// Each label's own word ("Nov ’25", where the card says "Nov"; "Jan" where it says "Jan’26"): the flying name turns
    /// from one into the other on the way, never swapping on the label as it lands or leaves.
    var labelWords: [Date: String] = [:]

    /// The flight for `start` from (or back to) its small month in the year: its squares where they are on screen now,
    /// worked out from its squares area (JourneyYearView: seven columns, 2.5 pt apart, square), and its name.
    @MainActor static func fromYear(_ start: Date, log: JourneyLog, today: Date) -> JourneyMonthFlight {
        let g = JourneyFlightGeometry.shared
        // The small month's squares where the year laid them out: the year's own geometry (JourneyYearSquares), never a copy.
        let lead = JourneyYearSquares.lead(of: start)
        let screen = UIScreen.main.bounds
        var tiles: [Date: JourneyFlightTile] = [:]
        let grid = g.yearGrids[start] ?? .zero
        for (i, date) in JourneyLog.daysOf(month: start).enumerated() {
            guard let first = log.firstDay, date >= first, date <= today else { continue }
            let d = log.day(date)
            let kind = d.tileKind
            let fill: JourneyFlightTile.Fill = d.allFive && date != today ? (d.metGoal ? .green : .grey) : .none
            let r = JourneyYearSquares.rect(of: i, lead: lead, in: grid)
            let from: CGRect? = grid.width > 0 && r.maxY > 60 && r.minY < screen.height - 40 ? r : nil
            tiles[date] = JourneyFlightTile(from: from, kind: kind, fill: fill, corner: JourneyYearSquares.corner, rank: log.tileRank(d),
                                            counted: d.counted)
        }
        return JourneyMonthFlight(start: start, tiles: tiles, card: .zero, order: order(of: tiles))
    }

    /// Each day's place among the flying ones, oldest first.
    static func order(of tiles: [Date: JourneyFlightTile]) -> [Date: CGFloat] {
        let dates = tiles.keys.sorted()
        var order: [Date: CGFloat] = [:]
        for (i, d) in dates.enumerated() { order[d] = dates.count > 1 ? CGFloat(i) / CGFloat(dates.count - 1) : 0 }
        return order
    }

    /// The card expanding (JourneyExpanded.swift): every day in view on the card flies to its ring, every month name in view
    /// to its label; `start` is the month opened (focused, or this one).
    @MainActor static func expanded(_ start: Date, log: JourneyLog, today: Date, weeks: [YourJourneyStats.Week]) -> JourneyMonthFlight {
        let g = JourneyFlightGeometry.shared
        let visible = g.grid.insetBy(dx: -1, dy: -1)
        let cal = Calendar.current
        var tiles: [Date: JourneyFlightTile] = [:]
        if let first = log.firstDay {
            for week in g.weekStarts {
                for i in 0..<7 {
                    guard let date = cal.date(byAdding: .day, value: i, to: week), date >= first, date <= today,
                          let r = g.tile(date), r.minY >= visible.minY + 8, r.maxY <= visible.maxY else { continue }
                    let d = log.day(date)
                    let fill: JourneyFlightTile.Fill = d.allFive && date != today ? (d.metGoal ? .green : .grey) : .none
                    tiles[date] = JourneyFlightTile(from: r, kind: d.tileKind, fill: fill, rank: log.tileRank(d), counted: d.counted)
                }
            }
        }
        let names = g.names.filter { visible.insetBy(dx: 0, dy: -2).contains(CGPoint(x: $0.value.midX, y: $0.value.midY)) }
        var words: [Date: String] = [:]
        for w in weeks { if let m = w.month, names[m.start] != nil { words[m.start] = m.label } }
        // The shrink from its reported width against the word's natural one (its height is the row's, not the text's).
        var sizes: [Date: CGFloat] = [:], labelWords: [Date: String] = [:]
        for (m, r) in names {
            let natural = JourneyMotion.nameWidth(words[m] ?? m.formatted(.dateTime.month(.abbreviated)), size: 12.5)
            sizes[m] = natural > 0 ? 12.5 * min(max(r.width / natural, 0.7), 1) : 12.5
            labelWords[m] = JourneyExpandedRow.name(m, today: today)
        }
        return JourneyMonthFlight(start: start, tiles: tiles, card: g.card, order: order(of: tiles), names: names, nameWords: words,
                                  nameSizes: sizes, labelWords: labelWords)
    }

}

/// What's open from the card (nil: nothing — every modifier a no-op). Changes only when a month or day opens or closes, so
/// its readers (the card's hidden tiles, every calendar cell) don't redraw per frame.
struct JourneyMonthOpen: Equatable {
    var flight: JourneyMonthFlight
    /// The day whose ring is flying to the day page (its cell draws none).
    var hiddenDay: Date?
}

/// Whether any Journey flight is running (a dial animating): a reload that lands mid-flight waits for it (his phone,
/// 2026-10-17: back from the background, the new log rebuilt the page during a weeks → year flight — 14 late, 131 ms).
/// Who counts: `JourneyMonthDial` only (`began` / `ended`, fileprivate — its `animate` and `tick`). Who waits
/// (`whenIdle`): JourneyPage's `reload` (the log and the scores land after the flight) and the host's `follow`.
@MainActor enum JourneyFlights {
    private(set) static var running = 0
    private static var waiting: [() -> Void] = []
    private static var drained = 0
    /// Now if nothing's flying, else once every flight has landed (in order) — or after 2 s at the latest: no flight runs
    /// that long, so by then a count was lost somewhere, and a reload must never wait on it for good.
    static func whenIdle(_ go: @escaping () -> Void) {
        guard running > 0 else { go(); return }
        waiting.append(go)
        let round = drained
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard drained == round, !waiting.isEmpty else { return }
            running = 0
            drain()
        }
    }
    fileprivate static func began() { running += 1 }
    fileprivate static func ended() {
        running = max(running - 1, 0)
        if running == 0 { drain() }
    }
    private static func drain() {
        guard !waiting.isEmpty else { return }
        drained += 1
        let w = waiting
        waiting = []
        w.forEach { $0() }
    }
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
    /// Whether this trip began at the page (1 → 0): the back's own ring timing (JourneyMotion.ringBack). Only a dial that
    /// `staggersBack` (the host's: expanded → card); kept for the whole trip, so a finger turning round mid-swipe never
    /// jumps between the two timings.
    @ObservationIgnored private(set) var backward = false
    @ObservationIgnored private let staggersBack: Bool

    init(staggersBack: Bool = false) { self.staggersBack = staggersBack }

    func value(_ k: Key) -> CGFloat { k == .month ? dial : dayDial }

    /// Straight to a value (a finger, or a start): any run of that dial stops.
    func set(_ k: Key, _ v: CGFloat) {
        runs[k] = nil
        write(k, v)
    }

    /// Linearly to `to` over `duration` (the beats ease on their own stretches), then `done`.
    func animate(_ k: Key, to target: CGFloat, duration: Double, done: @escaping () -> Void) {
        runs[k] = (value(k), target, CACurrentMediaTime(), max(duration, 0.001), done)
        if ticker == nil {
            // Its owner gone mid-run (a page torn down during its flight): the link stops and the flight counts as landed —
            // else the link fired on for good and every reload waited on a flight that would never land (the organizer's
            // check of the reload deferral).
            ticker = JourneyDialTicker { [weak self] now in
                guard let self else { return false }
                self.tick(now)
                return true
            } orphaned: { JourneyFlights.ended() }
            JourneyFlights.began()
        }
    }

    private func write(_ k: Key, _ v: CGFloat) {
        if k == .month, staggersBack {
            if dial >= 1, v < 1 { backward = true } else if dial <= 0, v > 0 { backward = false }
        }
        if k == .month { if dial != v { dial = v } } else { if dayDial != v { dayDial = v } }
    }

    private func tick(_ now: CFTimeInterval) {
        var finished: [() -> Void] = []
        for (k, r) in runs {
            let p = min(max((now - r.start) / r.duration, 0), 1)
            write(k, r.from + (r.to - r.from) * CGFloat(p))
            if p >= 1 { runs[k] = nil; finished.append(r.done) }
        }
        let landed = runs.isEmpty && ticker != nil
        if landed { ticker?.stop(); ticker = nil }
        finished.forEach { $0() }
        if landed { JourneyFlights.ended() }   // after the landings' own work (a close, a teardown)
    }
}

/// The display link behind JourneyMonthDial (120 Hz where the phone can).
@MainActor final class JourneyDialTicker: NSObject {
    private var link: CADisplayLink?
    /// Each frame; false: its owner is gone.
    private let onTick: (CFTimeInterval) -> Bool
    private let orphaned: () -> Void
    init(_ onTick: @escaping (CFTimeInterval) -> Bool, orphaned: @escaping () -> Void = {}) {
        self.onTick = onTick
        self.orphaned = orphaned
        super.init()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func tick(_ l: CADisplayLink) {
        guard onTick(l.targetTimestamp) else { stop(); orphaned(); return }
    }
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
/// top) and its number's opacity. JourneyDayCell's pieces read it as three values, each only its own (`journeyCellRing`,
/// `…Number`, `…Fill`): one value read whole redrew every flying ring when only the fills turned off at the back's first
/// frame (~150 ring bodies in its first 0.1 s, sim); 1 / 1 / 1 without a transition.
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
    @Entry var journeyCellRing: CGFloat = 1
    @Entry var journeyCellNumber: Double = 1
    @Entry var journeyCellFill: Double = 1
    /// Set by the host: a day tapped on the month opens through it (the ring grows) instead of a push.
    @Entry var journeyDayOpener: JourneyDayOpener? = nil
    /// The day whose top ring is flying to the day page (its own ring draws none).
    @Entry var journeyTopRingFlying: Date? = nil
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
    /// A picked day's ring at the top (JourneyDayTop): reports where it is, hidden while it's flying to the day page.
    func journeyFlightTopRing(_ date: Date) -> some View { modifier(JourneyFlightTopRing(date: date)) }
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
    enum Part: Equatable { case cardSurface, tile(Date), name(Date), squares(Date) }
    let part: Part
    @Environment(\.journeyMonthOpen) private var e
    @Environment(\.journeyMonthDial) private var dial
    func body(content: Content) -> some View {
        let hidden: Bool = {
            guard let e else { return false }
            switch part {
            case .cardSurface: return true
            case .tile(let d): return e.flight.tiles[d] != nil
            case .squares(let m): return m == e.flight.start
            // A name stays until the dial moves: its flying copy is drawn from the next frame.
            case .name(let m): return e.flight.names[m] != nil && (dial?.dial ?? 1) > 0
            }
        }()
        content.opacity(hidden ? 0 : 1)
    }
}

// MARK: - The expanded card's pieces (JourneyExpanded.swift)

extension View {
    /// One day's ring (after its scale): tells the cell how much of its ring, number and fill to draw (JourneyCellDraw).
    func journeyFlightCell(_ date: Date, scale: CGFloat) -> some View { modifier(JourneyFlightCellModifier(date: date, scale: scale)) }
    /// The expanded card's surface: clear while it opens over Journey, the page's own once it's open.
    func journeyFlightMonthSurface() -> some View { modifier(JourneyFlightMonthSurface()) }
}

struct JourneyFlightCellModifier: ViewModifier {
    let date: Date
    let scale: CGFloat
    @Environment(\.journeyMonthOpen) private var open

    // One shape for every cell, whatever flight is open (or none): only the values change. Branching between a flying
    // day's modifier, an arriving one's and none gave each a new identity when the flight changed — every laid-out cell
    // was rebuilt at once (138 day bodies at a tap back from the year, sim).
    func body(content: Content) -> some View {
        content.modifier(JourneyFlightCellDraw(hidden: open?.hiddenDay == date,
                                               at: open.flatMap { $0.flight.tiles[date] == nil ? nil : ($0.flight.order[date] ?? 0) },
                                               flying: open != nil))
    }
}

/// A cell's share of a flight: a flying day draws its ring in by its place (`at`); one that didn't fly arrives with the
/// words; with no flight, all drawn. It reads the dial — every frame of a flight, for the cells it changes.
private struct JourneyFlightCellDraw: ViewModifier {
    let hidden: Bool
    let at: CGFloat?
    let flying: Bool
    @Environment(\.journeyMonthDial) private var e

    func body(content: Content) -> some View {
        let t = e?.dial ?? 1
        let back = e?.backward == true
        let draw: JourneyCellDraw = if let at {
            JourneyCellDraw(ring: hidden ? 0 : back ? JourneyMotion.ringBack(t, at: at) : JourneyMotion.ring(t, at: at),
                            number: Double(back ? JourneyMotion.numberBack(t, at: at) : JourneyMotion.number(t, at: at)),
                            fill: hidden || t < 1 ? 0 : 1)
        } else if hidden {
            JourneyCellDraw(ring: 0, number: 1, fill: 0)
        } else {
            .full
        }
        content
            .environment(\.journeyCellRing, draw.ring)
            .environment(\.journeyCellNumber, draw.number)
            .environment(\.journeyCellFill, draw.fill)
            .opacity(flying && at == nil ? Double(JourneyMotion.monthWords(t)) : 1)
    }
}

/// An expanded label's name: hidden while the card's name flies to it, then taking over from it.
private struct JourneyFlightLabelLand: ViewModifier {
    let month: Date
    @Environment(\.journeyMonthDial) private var e
    @Environment(\.journeyMonthOpen) private var open
    func body(content: Content) -> some View {
        let flying = open?.flight.names[month] != nil
        content.opacity(flying ? Double(JourneyMotion.nameLand(e?.dial ?? 1)) : 1)
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
              ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    guard t < 1 else { return }
                    for (date, tile) in open.flight.tiles where open.hiddenDay != date {
                        let from = JourneyTileColor.of(tile.kind, rank: tile.rank, dark: dark)
                        // Its landing cell isn't placed yet (the month's first frame): it sits on its card bar, where it
                        // starts — drawn there, not skipped (skipped, the month's tiles left the card a frame early).
                        guard let cell = cells[date] else {
                            if let start = tile.from {
                                // The expanded card's row for it isn't laid out (scrolled away): it fades where it is.
                                ctx.opacity = Double(1 - z) * (tile.counted ? 1 : JourneyTileColor.beforeFreshStart)
                                let path = Path(roundedRect: start.offsetBy(dx: -o.x, dy: -o.y), cornerRadius: tile.corner, style: .continuous)
                                ctx.fill(path, with: .color(from))
                                if tile.kind == .none { outline(ctx, path, dark: dark, fade: 0) }
                            }
                            continue
                        }
                        let scale = cell.height / JourneyDayRing.size
                        let disc = JourneyDayRing.fill * 2 * scale
                        let end = CGRect(x: cell.midX - disc / 2, y: cell.midY - disc / 2, width: disc, height: disc)
                        let start = tile.from ?? end.insetBy(dx: disc * 0.2, dy: disc * 0.2)
                        let r = JourneyMotion.lerp(start, end, z).offsetBy(dx: -o.x, dy: -o.y)
                        let corner = JourneyMotion.lerp(tile.corner, disc / 2, z)
                        let color: Color = switch tile.fill {
                        case .green: from.mix(with: JourneyDayRing.green(dark).opacity(0.24), by: Double(tint))
                        case .grey: from.mix(with: JourneyDayRing.greyFill(dark), by: Double(tint))
                        case .none: from.opacity(Double(1 - tint))
                        }
                        ctx.opacity = (tile.from == nil ? Double(z) : 1) * (tile.counted ? 1 : JourneyTileColor.beforeFreshStart)
                        let path = Path(roundedRect: r, cornerRadius: corner, style: .continuous)
                        ctx.fill(path, with: .color(color))
                        // An unmarked day is its hairline outline on the card (and in the year); the month draws nothing
                        // for it, so the outline flies with the others and fades as theirs turn to their fills — it used
                        // to vanish at the start and pop back at the end (owner, 2026-10-17: "the borders of those tiles,
                        // they just disappear and reappear when changing between the views").
                        if tile.kind == .none { outline(ctx, path, dark: dark, fade: tint) }
                    }
                }
                // The expanded card's month names: each card name slides and grows to its label, its label's own name
                // taking over as it lands (JourneyFlightLabelLand); one with no label laid out fades where it is.
                if t < 1 {
                    let labels = JourneyFlightGeometry.shared.labels
                    ForEach(Array(open.flight.names.keys), id: \.self) { m in
                        if let from = open.flight.names[m] {
                            let to = labels[m]
                            let r = to.map { JourneyMotion.lerp(from, $0, z) } ?? from
                            let card = open.flight.nameWords[m] ?? m.formatted(.dateTime.month(.abbreviated))
                            let label = to == nil ? card : open.flight.labelWords[m] ?? card
                            let size = JourneyMotion.lerp(open.flight.nameSizes[m] ?? 12.5, 13, to == nil ? 0 : z)
                            // By its right edge, as both columns set their names. One word the other's start ("Jun" / "Jun ’25",
                            // "Jan’26" / "Jan"): the shared part slides as one word and only the rest fades, its width given back
                            // as it goes (crossfaded, the two overlapped into a smudge for a few frames).
                            let long = label.count >= card.count ? label : card, short = long == label ? card : label
                            let w = long == label ? z : 1 - z   // how much of the longer word shows
                            Group {
                                if long != short, long.hasPrefix(short) {
                                    let rest = String(long.dropFirst(short.count))
                                    let shortW = JourneyMotion.nameWidth(short, size: size)
                                    let end = r.maxX - JourneyMotion.nameWidth(rest, size: size) * w
                                    HStack(spacing: 0) {
                                        Text(short)
                                        Text(rest).opacity(Double(JourneyMotion.seg(w, 0.3, 1)))
                                    }
                                    .fixedSize()
                                    .frame(width: 160, alignment: .leading)
                                    .position(x: end - shortW + 80 - o.x, y: r.midY - o.y)
                                } else {
                                    let mix = Double(JourneyMotion.seg(z, 0.3, 0.7))   // 0 the card's word … 1 the label's
                                    ZStack(alignment: .trailing) {
                                        Text(card).opacity(label == card ? 1 : 1 - mix)
                                        if label != card { Text(label).opacity(mix) }
                                    }
                                    .fixedSize()
                                    .frame(width: 160, alignment: .trailing)
                                    .position(x: r.maxX - 80 - o.x, y: r.midY - o.y)
                                }
                            }
                            .font(.system(size: size, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .opacity(Double(to == nil ? 1 - z : 1 - JourneyMotion.nameLand(t)))
                        }
                    }
                }
              }
            }
        }
    }
}

/// An unmarked tile's hairline (JourneyTileColor.outline), `fade` 0 (full) … 1 (gone).
private func outline(_ ctx: GraphicsContext, _ path: Path, dark: Bool, fade: CGFloat) {
    guard fade < 1 else { return }
    ctx.stroke(path, with: .color(JourneyTileColor.outline(dark: dark).opacity(Double(1 - fade))), lineWidth: JourneyTileColor.outlineWidth)
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
            .modifier(JourneyFlightHide(part: .squares(start)))
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

    /// The picked day's top ring (JourneyDayFifths on the card): each prayed fifth in ink, the rest a faint track.
    static func top(day: JourneyLog.Day) -> JourneyFlightRingSpec {
        JourneyFlightRingSpec(fifths: day.marks.map { mark in
            mark.done ? Color.primary.opacity(0.72) : mark == .excused ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12)
        }, closed: false)
    }

    /// The month's F2 look for a day (JourneyDayCell): closed and green / soft, or its fifths.
    static func month(day: JourneyLog.Day, today: Bool, dark: Bool) -> JourneyFlightRingSpec {
        let dim = day.counted ? 1 : JourneyTileColor.beforeFreshStart   // before the fresh start, as its cell
        if day.allFive && !today {
            // A closed ring is one colour drawn at full and faded as a group, so where its fifths meet nothing darkens.
            return JourneyFlightRingSpec(fifths: [], closed: true,
                                         closedColor: day.metGoal ? JourneyDayRing.green(dark) : (dark ? .white : .black),
                                         closedOpacity: (day.metGoal ? 0.6 : (dark ? 0.40 : 0.36)) * dim)
        }
        let fifths: [Color?] = day.marks.map { mark in
            let c: Color? = switch mark {
            case .done, .excused: today ? JourneyDayRing.strong(dark) : JourneyDayRing.soft(dark)
            case .missed: JourneyDayRing.track(dark)
            case .toCome, .none: nil
            }
            return c?.opacity(dim)
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
    /// From the card's picked day (its top ring), not a month's cell.
    var fromTop = false
}

/// The picked day's top ring: where it is, and its fifths cut out while its day's ring flies — the score inside stays with
/// the card (hiding the whole ring popped the number back a frame after the ring landed).
private struct JourneyFlightTopRing: ViewModifier {
    let date: Date
    @Environment(\.journeyTopRingFlying) private var flying
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                JourneyFlightGeometry.shared.topRing = (date, $0)
            }
            .mask {
                GeometryReader { g in
                    // JourneyDayFifths' ring at this size.
                    let k = min(g.size.width, g.size.height) / JourneyDayRing.size
                    let r = JourneyDayRing.radius * k
                    ZStack {
                        Rectangle()
                        Circle().stroke(lineWidth: JourneyDayRing.band * k * 1.15 + 1.5)
                            .frame(width: r * 2, height: r * 2)
                            .position(x: g.size.width / 2, y: g.size.height / 2)
                            .blendMode(.destinationOut)
                            .opacity(flying == date ? 1 : 0)
                    }
                    .compositingGroup()
                }
            }
    }
}

extension View {
    /// Journey's page shows its months and their days through here: a month opened from the card (or This month) opens in
    /// place on the dial, a day on that month grows from its ring, and the left edge turns either back.
    func journeyMonthHost(month: Binding<JourneyMonthRoute?>, log: JourneyLog, stats: YourJourneyStats?) -> some View {
        modifier(JourneyMonthHost(month: month, log: log, stats: stats))
    }
}

struct JourneyMonthHost: ViewModifier {
    @Binding var month: JourneyMonthRoute?
    let log: JourneyLog
    /// Journey's numbers (the expanded card's top and bottom, its weeks).
    let stats: YourJourneyStats?
    @State private var flight: JourneyMonthFlight?
    @State private var day: JourneyDayFlight?
    /// The dials (one object all flight; the leaf pieces read it). Taps wait for a flight to land through a leaf gate that
    /// reads them (JourneyHitGate): a settled flag here redrew the host — and rebuilt the month page — on the first frame of
    /// every flight back (a ~60 ms start on his 13 Pro Max).
    @State private var dials = JourneyMonthDial(staggersBack: true)
    /// The edge swipe: which dial and where it was when the finger came down.
    @State private var backDrag: (day: Bool, from: CGFloat)?
    /// The edge swipe claims only a drag that starts sideways; one that starts up or down is the month's paging, left alone.
    @State private var edgeSideways: Bool?
    /// The edge swipe's finger is down (reset by SwiftUI however the gesture ends — onEnded isn't called when it's cancelled).
    @GestureState private var edgeHeld = false
    @State private var openerID = UUID()
    @State private var cardOpenerID = UUID()
    /// Back from the year: Journey shown at rest under the month layer, which fades out over it.
    @State private var fadingOut = false
    @State private var outFade: CGFloat = 0
    /// Landed back on the card: the card is Journey's again at once, the expanded page (hidden) comes down a beat later —
    /// taken down on the landing frame, its rows' teardown was that frame (~70 ms on the sim).
    @State private var leaving = false

    private var today: Date { PrayerDay.start() }
    private var width: CGFloat { UIScreen.main.bounds.width }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .allowsHitTesting((flight == nil || leaving) && day == nil)
                .modifier(JourneyFlightClear(active: fadingOut))
                // The card's picked day opens here too: its top ring grows into the day page (owner, 2026-10-17: the
                // card's top → day "a ring flight instead of the plain push"), as a month's day does from its cell.
                .environment(\.journeyDayOpener, JourneyDayOpener(id: cardOpenerID, open: { openDay($0, fromTop: true) }))
                .environment(\.journeyTopRingFlying, day?.fromTop == true && day?.to != nil ? day?.date : nil)
            // Over Journey's page (its own background is opaque — under it, the card had no shadow all flight and it popped
            // back on the last frame: Sami's check of 7174d7c7), drawn only outside the card's shape.
            if let flight, !leaving { JourneyGrowingSurface(card: flight.card) }
            if let flight {
                // The card, expanded (JourneyExpanded.swift; owner, 2026-10-17): it took the month page's place.
                JourneyExpandedPage(log: log, stats: stats ?? YourJourneyStats(log: JourneyLog(), today: today),
                                    opened: flight.start, focusOnOpen: month?.focus ?? true)
                    .modifier(JourneyMonthAway())
                    .environment(\.journeyDayOpener, JourneyDayOpener(id: openerID, open: { openDay($0) }))
                    .modifier(JourneyHitGate(dials: dials, key: .month, open: day == nil && !fadingOut && !leaving))
                    .opacity(leaving ? 0 : 1 - outFade)
                    // Its own flight and dials, leaving or not (the card's go at the landing): nothing in it changes as it
                    // comes down.
                    .environment(\.journeyMonthOpen, JourneyMonthOpen(flight: flight, hiddenDay: day?.to == nil ? nil : day?.date))
                    .environment(\.journeyMonthDial, dials)
            }
            if flight != nil && !leaving && day == nil { edgeStrip }
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
                // Its own dials: from the card no month is open, and the host's environment has none then.
                .environment(\.journeyMonthDial, dials)
            }
        }
        .overlay(alignment: .leading) { if day != nil { edgeStrip } }
        .onChange(of: edgeHeld) { _, held in if !held { edgeLetGo() } }
        .environment(\.journeyMonthDial, flight == nil || leaving ? nil : dials)
        .environment(\.journeyDayEntrance, day == nil ? nil : JourneyDayEntrance(source: dials))
        .environment(\.journeyMonthOpen, leaving ? nil : flight.map { JourneyMonthOpen(flight: $0, hiddenDay: day?.to == nil ? nil : day?.date) })
        .modifier(JourneyHostBar(showsBack: (flight != nil && !leaving) || day != nil, back: back))
        .onChange(of: month) { _, route in
            guard let route, flight == nil || leaving else { return }
            if leaving { finishLeaving() }
            openMonth(route.month)
        }
        .task { await autoRun() }
    }

    /// `-demoJourneyFlightRun [N]`: the real Journey's flights N times with no finger (default 5) — card → month → a day →
    /// back → back — for the frame log on a phone in Release (the real pages, not a stand-in).
    private func autoRun() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoJourneyYearRun") {
            // The expanded card toggles its year itself (JourneyExpandedPage.yearRun); the host only opens it.
            try? await Task.sleep(for: .seconds(3))
            month = JourneyMonthRoute(month: JourneyLog.monthStart(today), focus: false)
            return
        }
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
        JourneyPerf.began("expanded opens")   // the page's build: its own window (the flight's begins once its weeks are in)
        triggerSomeVibration(type: .light)
        let geo = JourneyFlightGeometry.shared
        dials.set(.month, 0)
        flight = JourneyMonthFlight.expanded(start, log: log, today: today, weeks: stats?.weeks ?? [])
        geo.onFollow = { done in follow(done: done) }
        // The dial runs once the expanded card's weeks are laid out (where the tiles land) — at the latest after a beat.
        geo.afterWeeks { runMonth(to: 1) }
    }

    private func runMonth(to target: CGFloat, how: String = "") {
        // Back from the page at rest: the flight's pieces switch over one turn before it moves — the dial a hair under 1,
        // where nothing on screen differs (rings whole, each tile's disc on its own fill) — so that first update (every
        // flying cell and fade waking, the fills handed to the canvas, its first draw: the back's one slow frame, ~35 ms on
        // his 13 Pro Max, the same with any one of them taken out) lands while the page still stands, not mid-motion.
        if target == 0, dials.dial >= 1 {
            dials.set(.month, 0.9999)
            DispatchQueue.main.async { runMonth(to: 0, how: how) }
            return
        }
        let remaining = abs(target - dials.dial)
        guard remaining > 0.001 else { if target == 0 { close() }; return }
        let run = JourneyFrameLog.shared.start(target == 1 ? "card → expanded" : "expanded → card")
        dials.animate(.month, to: target, duration: JourneyMotion.monthDuration * Double(remaining)) {
            JourneyFrameLog.shared.stop(how, run: run)
            if target == 0 { close() }
        }
    }

    /// The card to the expanded view's week, then the flight's tiles from the card as it now shows (E6,
    /// JourneyFlightGeometry.follow) — once nothing's in the air (the opening, a year flight), and only while the page is
    /// open and still. A quiet swap: the page is over the card, nothing on screen moves.
    private func follow(done: @escaping () -> Void) {
        JourneyFlights.whenIdle {
            let geo = JourneyFlightGeometry.shared
            guard let f = flight, !leaving, day == nil, dials.dial > 0.999,
                  geo.cardShow?(geo.expandedWeeks, geo.expandedPick) == true else { done(); return }
            // The card's quiet scroll laid out and its rows reported (a far week is scrolled to twice: the lazy stack's
            // estimate lands short the first time).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                guard flight?.start == f.start, !leaving, day == nil, dials.dial > 0.999 else { done(); return }
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) {
                    flight = JourneyMonthFlight.expanded(f.start, log: JourneyLog.last ?? log, today: today, weeks: stats?.weeks ?? [])
                }
                done()
            }
        }
    }

    private func close() {
        month = nil
        JourneyFlightGeometry.shared.cancelFollow()
        JourneyFlightGeometry.shared.yearShowing = false
        JourneyFlightGeometry.shared.yearBack = nil
        guard flight != nil, !leaving else { return }
        JourneyFrameLog.shared.note("host: landed on the card")
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if leaving { finishLeaving() } }
    }

    private func finishLeaving() {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            flight = nil
            leaving = false
        }
        JourneyFrameLog.shared.note("host: calendar taken down")
    }

    /// Back while the month page shows its year: into the month it came from (its own flight), else Journey.
    private func fromYear() {
        if let back = JourneyFlightGeometry.shared.yearBack { back() } else { fadeFromYear() }
    }

    /// Back while the month page shows its year and can't fly into a month: Journey at rest underneath, the month layer fading out over it (no days on
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

    // MARK: Month → day

    private func openDay(_ date: Date, fromTop: Bool = false) {
        let log = JourneyLog.last ?? log   // the auto run's copy of the host was taken before the log loaded
        guard day == nil, date <= today, log.day(date).active, date < today || log.day(date).allFive else { return }
        JourneyPerf.began("day opens")   // the day page's build and load: its own window (the flight's begins once it's in)
        // No tick here: every way in (the card's and the month's top, the year's day line) is a button that already ticked —
        // two light ticks for one tap read as a glitch (the organizer's check of d79f2837).
        dials.set(.day, 0)
        day = JourneyDayFlight(date: date, from: from(date, top: fromTop), to: nil, fromTop: fromTop)
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

    /// Where a day's ring flies from: the month's cell, or the card's top ring if it shows that day (nil: it only fades).
    private func from(_ date: Date, top: Bool) -> CGRect? {
        let geo = JourneyFlightGeometry.shared
        guard top else { return geo.cells[date] }
        return geo.topRing?.date == date ? geo.topRing?.frame : nil
    }

    private func runDay(to target: CGFloat, how: String = "") {
        let remaining = abs(target - dials.dayDial)
        guard remaining > 0.001 else { if target == 0 { day = nil }; return }
        let what = day?.fromTop == true ? "card" : "weeks"
        let run = JourneyFrameLog.shared.start(target == 1 ? "\(what) → day" : "day → \(what)")
        dials.animate(.day, to: target, duration: JourneyMotion.dayDuration * Double(remaining)) {
            JourneyFrameLog.shared.stop(how, run: run)
            if target == 0 { day = nil; dials.set(.day, 0) }
        }
    }

    /// The edge swipe let go without its onEnded: iOS took the touch (its own back swipe at the screen's edge, a banner, the
    /// app leaving). The dial stayed where the finger left it — at the card, the card looked at rest while the flight, never
    /// closed, kept every tap off Journey (his phone, 2026-10-17: "best streak" did nothing until a relaunch; the swipe's
    /// frame-log line, written at its end, never came). It finishes as a let-go would, to the nearer end. A turn later, so a
    /// normal end's onEnded has run first.
    private func edgeLetGo() {
        DispatchQueue.main.async {
            edgeSideways = nil
            guard let drag = backDrag else { return }
            backDrag = nil
            JourneyFrameLog.shared.stop()
            JourneyFrameLog.shared.note(String(format: "host: edge swipe cancelled at %.2f (%@)", drag.day ? dials.dayDial : dials.dial,
                                               drag.day ? "day" : "calendar"))
            if drag.day {
                let goes = dials.dayDial < 0.5
                runDay(to: goes ? 0 : 1, how: goes ? "cancelled, went" : "cancelled, sprang back")
            } else {
                let goes = dials.dial < 0.5
                JourneyFlightGeometry.shared.flushFollow { runMonth(to: goes ? 0 : 1, how: goes ? "cancelled, went" : "cancelled, sprang back") }
            }
        }
    }

    /// Going back from a day: the ring shrinks into the day on the page now (it may have been paged), from where it sits.
    private func retargetDayForBack() {
        let spot = JourneyDayRingSpot.shared
        guard var d = day, let date = spot.date else { return }
        d.date = date
        d.from = from(date, top: d.fromTop)
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
            else if flight != nil && JourneyFlightGeometry.shared.yearShowing { fromYear() }
            // A follow still waiting (the page scrolled a moment ago) first: the card to its weeks, the tiles from there.
            else if flight != nil { JourneyFlightGeometry.shared.flushFollow { runMonth(to: 0, how: "button") } }
        }
    }

    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($edgeHeld) { _, held, _ in held = true }
            .onChanged { v in
                if edgeSideways == nil { edgeSideways = abs(v.translation.width) >= abs(v.translation.height) }
                guard edgeSideways == true, day != nil || !JourneyFlightGeometry.shared.yearShowing else { return }
                if backDrag == nil {
                    let onDay = day != nil
                    if onDay { retargetDayForBack() } else { JourneyFlightGeometry.shared.flushFollow {} }
                    backDrag = (onDay, onDay ? dials.dayDial : dials.dial)
                    JourneyFrameLog.shared.start(onDay ? "day → weeks (finger)" : "expanded → card (finger)")
                }
                guard let drag = backDrag else { return }
                // The page holds still while a follow finishes (a few frames): the flight's tiles aren't set yet.
                if !drag.day, JourneyFlightGeometry.shared.followPending { return }
                let dial = min(max(drag.from - max(v.translation.width, 0) / width, 0), 1)
                dials.set(drag.day ? .day : .month, dial)
            }
            .onEnded { v in
                defer { edgeSideways = nil }
                if backDrag == nil, edgeSideways == true, day == nil, JourneyFlightGeometry.shared.yearShowing,
                   v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2 {
                    fromYear()   // the year: a swipe from the edge goes back to its month
                    return
                }
                guard let drag = backDrag else { return }
                backDrag = nil
                JourneyFrameLog.shared.stop()
                let goes = v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2
                if drag.day { runDay(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
                else { JourneyFlightGeometry.shared.flushFollow { runMonth(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") } }
            }
    }
}

/// The host's ‹: the system bar's (its own back button hidden meanwhile).
private struct JourneyHostBar: ViewModifier {
    let showsBack: Bool
    let back: () -> Void
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(showsBack)
            .toolbar {
                if showsBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)) }
                            .accessibilityLabel("Back")
                    }
                }
            }
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
        let spec = flight.fromTop ? .top(day: day)
            : JourneyFlightRingSpec.month(day: day, today: flight.date == PrayerDay.start(), dark: dark)
        // From its cell's size (the month page draws days at 1 / 0.9 / 0.8 / 0.7), or the top ring's (46 / 54).
        let cell = (flight.from?.height ?? JourneyDayRing.size) / JourneyDayRing.size
        let startBand = JourneyDayRing.band * cell * (flight.fromTop ? 1.15 : 1)   // JourneyDayFifths' band
        let fromCentre = flight.from.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: to.midX, y: to.midY)
        let centre = JourneyMotion.lerp(fromCentre, CGPoint(x: to.midX, y: to.midY), z)
        // From a day not on the month (paged to another month): it only fades, at the page's size.
        let k = flight.from == nil ? 1 : z
        let radius = JourneyMotion.lerp(JourneyDayRing.radius * cell, 100, k)
        let band = JourneyMotion.lerp(startBand, theme.arc.width * 0.5, k)
        let gap = JourneyMotion.lerp(7.0 / 360, 0.014, k)
        let closedGap = JourneyMotion.lerp(0, 0.014, JourneyMotion.seg(k, 0.5, 1))
        let disc = JourneyMotion.lerp(JourneyDayRing.fill * 2 * cell, CircleMotion.dayDiscDiameter, k)
        let fill: Color? = spec.closed ? (day.metGoal ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
            .opacity(day.counted ? 1 : JourneyTileColor.beforeFreshStart) : nil
        ZStack {
            if !landed {
                NeuRaised(shape: Circle(), radius: 9 * k, offset: 4.5 * k)
                    .frame(width: disc, height: disc)
                    // The card's top ring has no disc: near it the disc is gone (a grey one sat behind the ring as it landed).
                    .opacity(Double(JourneyMotion.out(JourneyMotion.seg(k, flight.fromTop ? 0.35 : 0.05, 0.6))))
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
