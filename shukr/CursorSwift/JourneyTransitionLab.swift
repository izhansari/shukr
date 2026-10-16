import SwiftUI
import QuartzCore

// Journey's two transitions on a test screen (owner, 2026-10-16: "It doesn't have to be the actual Journey page. It can be
// a test version of it, just to get the transition right, so we can copy and paste that and plug it into what we're doing
// right now."). His picks: 1A, the card's month opens in place on one dial (transition D, board/mocks/journey-v6/
// transition-d.html), and 2A, Bradley's plan for a day: its ring grows into the day page's ring, soft, then the grade colours
// draw in. "the back swipe should undo it the same way": a swipe from the left edge turns the same dial backwards under the
// finger. Stand-ins for Journey's page and the month (copies of JourneyHomeCard's grid and JourneyMonthPage's layout); the
// day is the real JourneyDayPage (JourneyDayEntrance, JourneyDayRingSpot). Reached from My Dev Stuff or `-demoTransitionLab`.

// MARK: - Timing

/// The dials' lengths and beats in one place (to move into CircleMotion when this goes into Journey). Each dial runs
/// linearly; every beat eases on its own stretch of it (the mock's way).
enum LabMotion {
    /// Card → month: the mock's whole run at speed 1 (transition-d.html BASE).
    static let monthDuration: Double = 0.56
    /// Month → day: the ring's growth, then the grade colours drawing in.
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
}

// MARK: - Frame log

/// Logs each run's real frame pacing (measure before guessing): how long it took, frames drawn, the worst gap and how many
/// frames were late. Library/Caches/journey-transitions.log on the phone, and the console.
@MainActor final class LabFrameLog: NSObject {
    static let shared = LabFrameLog()
    private var link: CADisplayLink?
    private var name = ""
    private var began: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var worst: CFTimeInterval = 0
    private var late = 0
    private var expected: CFTimeInterval = 1 / 60.0
    /// The main run loop's longest busy spell during the run (main-thread work vs the renderer).
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

// MARK: - The screen

/// Opens the test screen over the Salah page (`-demoTransitionLab`; My Dev Stuff pushes it from Settings).
@MainActor @Observable final class JourneyLabPresenter {
    static let shared = JourneyLabPresenter()
    var open = false
}

/// Where things are on screen, read when a transition starts — never observed (no redraw on every scroll frame).
@MainActor final class LabGeometry {
    var card: CGRect = .zero
    /// The card's grid as it shows (its clip), and how far it's scrolled.
    var grid: CGRect = .zero
    var gridOffset: CGFloat = 0
    /// The month calendar's cells (global).
    var cells: [Date: CGRect] = [:]
}

/// A month opening: which, and the card's geometry frozen at the tap.
struct LabMonthFlight: Equatable {
    let start: Date
    /// Each of its days' tiles where they showed on the card (only those in view).
    let tiles: [Date: CGRect]
    /// The month's name on the card, if it was in view.
    let label: CGRect?
    let labelText: String
    let card: CGRect
}

/// A day opening: which, and where its ring left from.
struct LabDayFlight: Equatable {
    var date: Date
    var from: CGRect?
    var to: CGRect?
}

struct JourneyTransitionLab: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @State private var log = JourneyLog.last ?? JourneyLog()
    @State private var stats: YourJourneyStats?
    @State private var geo = LabGeometry()
    @State private var month: LabMonthFlight?
    @State private var monthDial: CGFloat = 0
    @State private var day: LabDayFlight?
    @State private var dayDial: CGFloat = 0
    /// The edge swipe: which dial and where it was when the finger came down.
    @State private var backDrag: (day: Bool, from: CGFloat)?

    private var today: Date { PrayerDay.start() }
    private var width: CGFloat { UIScreen.main.bounds.width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LabJourneyLayer(dial: monthDial, stats: stats ?? YourJourneyStats(log: JourneyLog(), today: today), log: log,
                            openMonth: month?.start, growFrom: month?.card, geo: geo, onMonth: { openMonth($0) })
                .allowsHitTesting(month == nil)
            if let month {
                LabMonthLayer(dial: monthDial, dayDial: dayDial, flight: month, log: log, today: today, geo: geo,
                              hiddenDay: day?.to == nil ? nil : day?.date, onReady: { runMonth(to: 1) }, onDay: { openDay($0) })
                    .allowsHitTesting(day == nil && monthDial == 1)
            }
            // The back swipe: the left edge turns the open dial backwards (the system's is off while one is open).
            if month != nil && day == nil {
                Color.clear.frame(width: 22).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeBack)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The day over it all, not in the stack: the day page reaches into the top edge, and inside the stack it pulled
        // the month up under the clock (first try).
        .overlay {
            if let day {
                LabDayLayer(dial: dayDial, flight: day, log: log)
                    .allowsHitTesting(dayDial == 1)
            }
        }
        .overlay(alignment: .leading) {
            // The back swipe, over the day too.
            if day != nil {
                Color.clear.frame(width: 22).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeBack)
                    .ignoresSafeArea()
            }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(month != nil)
        .toolbar {
            if month != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)) }
                        .accessibilityLabel("Back")
                }
            }
        }
        .task {
            await load()
            // `-demoTransitionLabRun [N]`: plays both transitions N times (default 3) with no finger — the frame log's runs,
            // on a phone nobody's holding.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoTransitionLabRun") {
                let n = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 3 : 3
                await autoRun(times: n)
            }
        }
    }

    private func autoRun(times: Int) async {
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(1.2)
        // The latest month on the card with a fortnight in it (the month before when this one's young), and its latest day
        // that opens.
        guard let stats else { return }
        let named = stats.weeks.compactMap { $0.month?.start }
        guard let latest = named.last else { return }
        let m = log.month(latest).activeDays >= 14 || named.count < 2 ? latest : named[named.count - 2]
        for _ in 0..<times {
            openMonth(m)
            await wait(LabMotion.monthDuration + 1.2)
            let days = JourneyLog.daysOf(month: m).filter { $0 < today && log.day($0).active }
            if let d = days.last {
                openDay(d)
                await wait(LabMotion.dayDuration + 1.6)
                back()
                await wait(LabMotion.dayDuration + 1)
            }
            back()
            await wait(LabMotion.monthDuration + 1.2)
        }
        print("🎞️ auto run done")
    }

    private func load() async {
        let container = context.container
        let built = await JourneyLog.load(container: container, ranges: Excused.ranges)
        log = built
        JourneyLog.last = built
        stats = YourJourneyStats(log: built, today: today)
    }

    // MARK: Card → month

    private func openMonth(_ start: Date) {
        guard month == nil, let stats else { return }
        triggerSomeVibration(type: .light)
        // The card's geometry now: each of the month's tiles where it shows (inside the grid's clip), and its name.
        let grid = geo.grid
        let pitch = JourneyHomeCard.pitch
        let barW = (grid.width - 34 - 6 * 7) / 7
        var tiles: [Date: CGRect] = [:]
        var label: CGRect?
        var labelText = ""
        for (row, week) in stats.weeks.enumerated() {
            let y = grid.minY + 12 + CGFloat(row) * pitch - geo.gridOffset
            if week.month?.start == start {
                labelText = week.month?.label ?? ""
                let r = CGRect(x: grid.minX, y: y, width: 34, height: 11)
                if grid.insetBy(dx: 0, dy: -2).contains(CGPoint(x: r.midX, y: r.midY)) { label = r }
            }
            for (col, d) in week.days.enumerated() {
                guard let d, JourneyLog.monthStart(d.date) == start else { continue }
                let r = CGRect(x: grid.minX + 40 + CGFloat(col) * (barW + 6), y: y, width: barW, height: 11)
                if r.minY >= grid.minY + 8, r.maxY <= grid.maxY + 1 { tiles[d.date] = r }
            }
        }
        monthDial = 0
        month = LabMonthFlight(start: start, tiles: tiles, label: label, labelText: labelText, card: geo.card)
        // The month layer calls onReady once its title is laid out; then the dial runs.
    }

    private func runMonth(to target: CGFloat, how: String = "") {
        let remaining = abs(target - monthDial)
        guard remaining > 0.001 else { if target == 0 { month = nil }; return }
        LabFrameLog.shared.start(target == 1 ? "card → month" : "month → card")
        withAnimation(.linear(duration: LabMotion.monthDuration * remaining)) { monthDial = target } completion: {
            LabFrameLog.shared.stop(how)
            if target == 0 { month = nil }
        }
    }

    // MARK: Month → day

    private func openDay(_ date: Date) {
        guard day == nil, date <= today, log.day(date).active, date < today || log.day(date).allFive else { return }
        triggerSomeVibration(type: .light)
        dayDial = 0
        day = LabDayFlight(date: date, from: geo.cells[date], to: nil)
        // The day page reports where its disc sits; the dial runs from there.
        let spot = JourneyDayRingSpot.shared
        spot.onReport = { reported, frame in
            guard reported == date, self.day?.to == nil else { return }
            self.day?.to = frame
            spot.onReport = nil
            DispatchQueue.main.async { runDay(to: 1) }
        }
        // Never reported (shouldn't happen): land where the day page puts its disc on a 17 Pro.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.day?.date == date, self.day?.to == nil else { return }
            spot.onReport = nil
            let d = CircleMotion.dayDiscDiameter
            self.day?.to = CGRect(x: (width - d) / 2, y: JourneyDayPage.ringTop, width: d, height: d)
            print("🎞️ day page never reported its disc; landing on the default")
            runDay(to: 1)
        }
    }

    private func runDay(to target: CGFloat, how: String = "") {
        let remaining = abs(target - dayDial)
        guard remaining > 0.001 else { if target == 0 { day = nil }; return }
        LabFrameLog.shared.start(target == 1 ? "month → day" : "day → month")
        withAnimation(.linear(duration: LabMotion.dayDuration * remaining)) { dayDial = target } completion: {
            LabFrameLog.shared.stop(how)
            if target == 0 { day = nil }
        }
    }

    /// Going back from a day: the ring shrinks into the day on the page now (it may have been paged), from where it sits.
    private func retargetDayForBack() {
        let spot = JourneyDayRingSpot.shared
        guard var d = day, let date = spot.date else { return }
        d.date = date
        d.from = geo.cells[date]
        d.to = spot.frame
        day = d
    }

    // MARK: Back

    private func back() {
        if day != nil { retargetDayForBack(); runDay(to: 0, how: "button") } else if month != nil { runMonth(to: 0, how: "button") }
    }

    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                if backDrag == nil {
                    let onDay = day != nil
                    if onDay { retargetDayForBack() }
                    backDrag = (onDay, onDay ? dayDial : monthDial)
                    LabFrameLog.shared.start(onDay ? "day → month (finger)" : "month → card (finger)")
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
                LabFrameLog.shared.stop()
                let goes = v.translation.width > width / 3 || v.predictedEndTranslation.width > width / 2
                if drag.day { runDay(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
                else { runMonth(to: goes ? 0 : 1, how: goes ? "let go" : "sprang back") }
            }
    }
}

// MARK: - Journey (stand-in)

/// Journey's page as it is (title, D's card, the rows), fading as the month opens: the page's words lift away first, then
/// the card's other weeks; the tapped month's tiles and name leave with the month (they're drawn by LabMonthLayer).
private struct LabJourneyLayer: View, Animatable {
    var dial: CGFloat
    let stats: YourJourneyStats
    let log: JourneyLog
    let openMonth: Date?
    /// The card's frame when its month was tapped: its surface grows from there into the page.
    let growFrom: CGRect?
    let geo: LabGeometry
    let onMonth: (Date) -> Void
    var animatableData: CGFloat { get { dial } set { dial = newValue } }

    var body: some View {
        let t = dial
        let z = LabMotion.io(LabMotion.seg(t, 0.05, 0.75))
        let jo = LabMotion.out(LabMotion.seg(t, 0, 0.28))
        let lift = LabMotion.out(LabMotion.seg(t, 0, 0.1))
        let others = (1 - 0.5 * lift) * (1 - LabMotion.out(LabMotion.seg(t, 0.1, 0.5)))
        let words = 1 - LabMotion.out(LabMotion.seg(t, 0, 0.2))
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Journey").font(.system(size: 38, weight: .regular, design: .rounded))
                Text("Transition test · tap a month's name")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(1 - jo).offset(y: 28 * jo)
            LabCard(stats: stats, openMonth: openMonth, gridOpacity: others, wordsOpacity: words, geo: geo, onMonth: onMonth)
                .padding(.top, 16)
            VStack(spacing: 0) {
                LabRow(symbol: "calendar", title: "This month", line: "Opens this month the same way") {
                    onMonth(JourneyLog.monthStart(PrayerDay.start()))
                }
                LabRow(symbol: "clock", title: "To make up", line: "A stand-in row") {}
                LabRow(symbol: "star", title: "Milestones", line: "A stand-in row", last: true) {}
            }
            .padding(.top, 10)
            .opacity(1 - jo).offset(y: 28 * jo)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The card's surface, growing into the page under everything (its shadow fading as it goes; the page's own surface
        // is the same colour, so only the shadow shows it).
        .background {
            if let growFrom {
                // Only while it's near the card's size: a blurred shadow re-drawn at full-screen size every frame starved the
                // renderer (sim, first run: 0.4–1.5 s with no frame).
                if z < 0.15 {
                    GlobalCanvas { o in
                        let r = LabMotion.lerp(growFrom, UIScreen.main.bounds, z)
                        NeuRaised(shape: RoundedRectangle(cornerRadius: LabMotion.lerp(26, 56, z), style: .continuous))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX - o.x, y: r.midY - o.y)
                            .opacity(Double(1 - LabMotion.seg(z, 0, 0.15)))
                    }
                }
            }
        }
    }
}

/// JourneyHomeCard's look (YourJourney.swift): the number, the label row, the grid a week a row, the three numbers. Its
/// background, the month's tiles and its name hide while that month is open (the month layer draws them, moving).
private struct LabCard: View {
    let stats: YourJourneyStats
    let openMonth: Date?
    let gridOpacity: CGFloat
    let wordsOpacity: CGFloat
    let geo: LabGeometry
    let onMonth: (Date) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(stats.activeDays)").font(.system(size: 54, weight: .thin, design: .rounded))
                    Text("days you marked a prayer").font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("THE LAST WEEKS")
                    Spacer()
                    Text("a week a row")
                }
                .font(.system(size: 11, weight: .light, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            }
            .opacity(wordsOpacity)
            grid.padding(.top, 6).opacity(gridOpacity)
            HStack(alignment: .top, spacing: 0) {
                figure("\(stats.prayersMarked)", "prayers marked")
                figure(stats.inTimeRate.map { "\($0)%" } ?? "–", "in time, on those days")
                figure(stats.bestStreak == 1 ? "1 day" : "\(stats.bestStreak) days", "best streak")
            }
            .padding(.top, 24)
            .opacity(wordsOpacity)
        }
        .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 14)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)).opacity(openMonth == nil ? 1 : 0))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geo.card = $0 }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(stats.weeks) { week in row(week) }
            }
            .padding(.top, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { g in
            // Kept as it's read, not only on a change: at rest at the bottom the action never ran (the first try's "Oct"
            // left from the top of the card).
            let y = g.contentOffset.y + g.contentInsets.top
            MainActor.assumeIsolated { geo.gridOffset = y }
            return y
        } action: { _, y in geo.gridOffset = y }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geo.grid = $0 }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
                Color.black
            }
        }
        .frame(height: JourneyHomeCard.minGrid + 4 * JourneyHomeCard.pitch)
    }

    private func row(_ week: YourJourneyStats.Week) -> some View {
        HStack(spacing: 6) {
            Group {
                if let m = week.month {
                    Button { onMonth(m.start) } label: {
                        Text(m.label).font(.system(size: 12.5, weight: .regular, design: .rounded)).foregroundStyle(Color.sage)
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.plain)
                    .opacity(openMonth == m.start ? 0 : 1)
                } else {
                    Color.clear
                }
            }
            .frame(width: 34, height: 11, alignment: .leading)
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                let hidden = day.map { JourneyLog.monthStart($0.date) == openMonth } ?? true
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(day.map { LabCard.color($0.kind, dark: scheme == .dark) } ?? .clear)
                    .frame(maxWidth: .infinity).frame(height: 11)
                    .opacity(hidden ? 0 : 1)
            }
        }
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    /// JourneyHomeCard's colours.
    static func color(_ kind: YourJourneyStats.Kind, dark: Bool) -> Color {
        switch kind {
        case .none: return dark ? Color(red: 0x2E / 255, green: 0x30 / 255, blue: 0x35 / 255)
                                : Color(red: 126 / 255, green: 132 / 255, blue: 143 / 255).opacity(0.14)
        case .some: return dark ? Color(red: 0x55 / 255, green: 0x57 / 255, blue: 0x5D / 255)
                                : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.30)
        case .allFive: return dark ? Color(red: 0xA9 / 255, green: 0xAB / 255, blue: 0xB1 / 255)
                                   : Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255).opacity(0.62)
        case .allInTime: return dark ? Color(red: 0x4C / 255, green: 0x8E / 255, blue: 0x62 / 255)
                                     : Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255).opacity(0.55)
        }
    }
}

private struct LabRow: View {
    let symbol: String
    let title: String
    let line: String
    var last = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 21, weight: .light)).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .regular, design: .rounded))
                    Text(line).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sage)
            }
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) } }
    }
}

// MARK: - The month (stand-in)

/// Draws in screen terms: `place` is a rect in global space; the canvas knows its own origin.
private struct GlobalCanvas<Content: View>: View {
    @ViewBuilder let content: (CGPoint) -> Content
    var body: some View {
        GeometryReader { g in content(g.frame(in: .global).origin) }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// The month opened in place (D): the card's surface grows into the page, each of the month's tiles flies to its day and
/// lands as that day's fill, the name grows into the title, the month's words arrive, the rings close day by day. JourneyMonthPage's
/// layout (title, "N days", the three numbers, the calendar, its key). As a day opens it fades away (Bradley: "it fades out
/// as the ring starts to grow").
private struct LabMonthLayer: View, Animatable {
    var dial: CGFloat
    var dayDial: CGFloat
    let flight: LabMonthFlight
    let log: JourneyLog
    let today: Date
    let geo: LabGeometry
    let hiddenDay: Date?
    let onReady: () -> Void
    let onDay: (Date) -> Void
    @State private var title: CGRect?
    @State private var started = false
    @Environment(\.colorScheme) private var scheme
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(dial, dayDial) }
        set { dial = newValue.first; dayDial = newValue.second }
    }

    var body: some View {
        let t = dial
        let z = LabMotion.io(LabMotion.seg(t, 0.05, 0.75))
        let words = LabMotion.out(LabMotion.seg(t, 0.55, 0.95))
        let away = 1 - LabMotion.out(LabMotion.seg(dayDial, 0, 0.3))   // a day opening
        let numbers = log.month(flight.start)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                titleView(z: z, t: t)
                VStack(alignment: .leading, spacing: 0) {
                    Text(numbers.activeDays == 1 ? "1 day you marked a prayer" : "\(numbers.activeDays) days you marked a prayer")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack(alignment: .top, spacing: 0) {
                        fact("\(numbers.allInTimeDays)", "days all in time")
                        fact("\(numbers.allFiveDays)", "days with all five")
                        fact(numbers.averageScore.map { "\($0)" } ?? "–", "average score")
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                    .padding(.top, 22)
                }
                .opacity(words).offset(y: LabMotion.lerp(8, 0, words))
                calendar(t: t, z: z, words: words).padding(.top, 24)
                Text("Tap a day to open it.")
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .opacity(words)
            }
            .padding(.horizontal, 20)
            .opacity(away)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // "Sep" grows into "September 2026": the same letters, the rest of the name unrolling after them, sage to the page's ink.
    private func titleView(z: CGFloat, t: CGFloat) -> some View {
        let full = flight.start.formatted(.dateTime.month(.wide).year())
        let font = UIFont.systemFont(ofSize: 30, weight: .regular)
        let rounded = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 30)
        let short = flight.start.formatted(.dateTime.month(.abbreviated))
        let shortW = (short as NSString).size(withAttributes: [.font: rounded]).width + 1
        let fullW = (full as NSString).size(withAttributes: [.font: rounded]).width + 2
        let unroll = LabMotion.out(LabMotion.seg(t, 0.3, 0.75))
        let k = LabMotion.lerp(12.5 / 30, 1, z)
        let from = flight.label
        let dx = from.flatMap { f in title.map { f.minX - $0.minX } } ?? 0
        let dy = from.flatMap { f in title.map { f.midY - $0.midY } } ?? 0
        // Measured on its slot, never on the moving text: the text's own frame includes its scale and offset, so measuring
        // it fed back into them every frame (the first tries froze for 0.4–1.5 s).
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                title = frame
                if !started { started = true; DispatchQueue.main.async { onReady() } }
            }
            .overlay(alignment: .leading) {
                Text(full)
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.sage.mix(with: Color.primary, by: Double(z)))
                    .lineLimit(1).fixedSize()
                    .mask(alignment: .leading) { Rectangle().frame(width: LabMotion.lerp(shortW, fullW, unroll)) }
                    .scaleEffect(k, anchor: .leading)
                    .offset(x: (1 - z) * dx, y: (1 - z) * dy)
                    // No label on screen (scrolled off the card): the title fades in with the words instead.
                    .opacity(title == nil ? 0 : from == nil ? LabMotion.out(LabMotion.seg(t, 0.3, 0.8)) : 1)
            }
    }

    private func fact(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func calendar(t: CGFloat, z: CGFloat, words: CGFloat) -> some View {
        let cal = Calendar.current
        let days = JourneyLog.daysOf(month: flight.start)
        let lead = ((cal.component(.weekday, from: flight.start) - cal.firstWeekday) + 7) % 7
        let slots: [Date?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        let rows = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        let letters = Array(symbols[first...] + symbols[..<first])
        let dark = scheme == .dark
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .opacity(words)
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            if i < row.count, let date = row[i] {
                                let n = cal.component(.day, from: date)
                                let a = 0.6 + CGFloat(n - 1) * 0.006
                                let grid = gridDay(date)
                                LabMonthCell(day: log.day(date), date: date, today: today, first: log.firstDay,
                                             usesExcused: log.usesExcused,
                                             ring: LabMotion.io(LabMotion.seg(t, a, a + 0.2)),
                                             number: LabMotion.out(LabMotion.seg(t, a + 0.02, a + 0.2)),
                                             tile: grid.map { (from: flight.tiles[date], color: LabCard.color($0.kind, dark: dark)) },
                                             z: z, tint: LabMotion.seg(t, 0.35, 0.8), hidden: hiddenDay == date)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: JourneyDayRing.size)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onDay(date) }
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geo.cells[date] = $0 }
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: JourneyDayRing.size)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                key(inTime: true, "All five in time")
                key(inTime: false, "All five")
            }
            .font(.system(size: 11, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
            .frame(maxWidth: .infinity)
            .opacity(words)
        }
    }

    private func gridDay(_ date: Date) -> YourJourneyStats.GridDay? {
        guard let first = log.firstDay, date >= first, date <= today else { return nil }
        let d = log.day(date)
        let kind: YourJourneyStats.Kind = d.allInTime ? .allInTime : d.allFive ? .allFive : d.active ? .some : .none
        return YourJourneyStats.GridDay(date: date, kind: kind, prayed: d.prayed, inTime: d.inTime, excused: d.excused > 0)
    }

    private func key(inTime: Bool, _ title: String) -> some View {
        let dark = scheme == .dark
        return HStack(spacing: 5) {
            Circle().fill(inTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark))
                .padding(1.6)
                .overlay(Circle().stroke(inTime ? JourneyDayRing.green(dark).opacity(0.6) : JourneyDayRing.soft(dark), lineWidth: 1.1))
                .frame(width: 12, height: 12)
            Text(title)
        }
    }
}

/// One day of the month (JourneyDayCell's F2 look, spec month-fifths) with its tile flying in: the card's bar slides and
/// grows from where it was to this day's fill disc (rounding as it goes, its colour turning to the fill's, or fading where
/// the day has none), then its ring draws closed and its number comes in.
private struct LabMonthCell: View {
    let day: JourneyLog.Day
    let date: Date
    let today: Date
    let first: Date?
    let usesExcused: Bool
    /// 0…1: the ring drawn, the number in.
    let ring: CGFloat
    let number: CGFloat
    /// Its tile on the card (nil frame: not in view there, so it grows in place).
    let tile: (from: CGRect?, color: Color)?
    let z: CGFloat
    let tint: CGFloat
    /// Its ring is flying to the day page.
    let hidden: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let future = date > today
        let before = first.map { date < $0 } ?? true
        let isToday = date == today
        let dark = scheme == .dark
        let drawn = !future && !before && day.active
        let closed = drawn && day.allFive && !isToday
        let fill: Color? = closed ? (day.allInTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark)) : nil
        ZStack {
            if drawn && !hidden {
                LabRing(spec: .month(day: day, today: isToday, dark: dark), drawn: ring)
                    .frame(width: JourneyDayRing.radius * 2, height: JourneyDayRing.radius * 2)
            }
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: JourneyDayRing.number, weight: isToday ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(future ? Color.secondary.opacity(0.55) : drawn || isToday ? Color.primary : Color.secondary.opacity(0.85))
                .offset(y: isToday ? -2.2 * JourneyDayRing.k : 0)
                .opacity(number)
            if isToday {
                Circle().fill(Color.primary).frame(width: 3 * JourneyDayRing.k, height: 3 * JourneyDayRing.k)
                    .offset(y: 7.6 * JourneyDayRing.k)
                    .opacity(number)
            } else if usesExcused && day.excusedDay && !day.active {
                ExcusedDayBadge(size: 9.2 * JourneyDayRing.k).offset(y: 13 * JourneyDayRing.k).opacity(number)
            }
        }
        .frame(width: JourneyDayRing.size, height: JourneyDayRing.size)
        .background {
            if let tile, !hidden {
                GeometryReader { g in
                    let me = g.frame(in: .global)
                    let disc = JourneyDayRing.fill * 2
                    let end = CGRect(x: me.midX - disc / 2, y: me.midY - disc / 2, width: disc, height: disc)
                    let start = tile.from ?? end.insetBy(dx: disc * 0.2, dy: disc * 0.2)
                    let r = LabMotion.lerp(start, end, z)
                    let corner = LabMotion.lerp(5, disc / 2, z)
                    let color: Color = fill.map { tile.color.mix(with: $0, by: Double(tint)) } ?? tile.color.opacity(Double(1 - tint))
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(color)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX - me.minX, y: r.midY - me.minY)
                        .opacity(tile.from == nil ? Double(z) : 1)
                }
            }
        }
    }
}

// MARK: - A ring that changes size (the month's F2 ring ↔ the day page's)

/// What a ring draws: each fifth's colour (nil: nothing), whether it's one closed ring, and its fill.
struct LabRingSpec {
    var fifths: [Color?]
    var closed: Bool
    var closedColor: Color = .clear
    var closedOpacity: Double = 1

    /// The month's F2 look for a day (JourneyDayCell): closed and green / soft, or its fifths.
    static func month(day: JourneyLog.Day, today: Bool, dark: Bool) -> LabRingSpec {
        if day.allFive && !today {
            // A closed ring is one colour drawn at full and faded as a group, so where its fifths meet nothing darkens.
            return LabRingSpec(fifths: [], closed: true,
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
        return LabRingSpec(fifths: fifths, closed: false)
    }
}

/// Five arcs, Fajr at the top, clockwise. `gap` is each fifth's inset at either end in turns (F2: 7° = 0.0194; DayRing:
/// 0.014). A closed ring opens from 0. `drawn` trims each fifth from its start (the month's rings closing).
private struct LabRing: View {
    let spec: LabRingSpec
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

// MARK: - The day

/// The real day page, opened over the month: its surface comes in as the month fades, the tapped day's ring grows from its
/// cell to the page's ring (soft, its fill fading, a closed ring opening its gaps as it lands), the raised disc grows with
/// it and hands over to the page's own, then DayRing draws its grade colours in, fifth by fifth, and the rest arrives
/// (Bradley's plan, 2026-10-16). Back: the same dial, the other way.
private struct LabDayLayer: View, Animatable {
    var dial: CGFloat
    let flight: LabDayFlight
    let log: JourneyLog
    @Environment(\.colorScheme) private var scheme
    @Environment(\.circleTheme) private var theme
    var animatableData: CGFloat { get { dial } set { dial = newValue } }

    var body: some View {
        let t = dial
        let land = LabMotion.dayLand
        let z = LabMotion.io(LabMotion.seg(t, 0, land))
        let page = LabMotion.out(LabMotion.seg(t, 0, 0.3))
        let drawn = LabMotion.io(LabMotion.seg(t, land - 0.05, 1))
        let soft = 1 - LabMotion.seg(t, land, 0.85)
        let rest = LabMotion.out(LabMotion.seg(t, 0.7, 1))
        let landed = t >= land
        ZStack {
            JourneyDayPage(date: flight.date, firstDay: log.firstDay)
                .environment(\.journeyDayEntrance, t >= 1 ? nil : JourneyDayEntrance(page: page, disc: landed ? 1 : 0, drawn: drawn, rest: rest))
            if t < 1, let to = flight.to {
                GlobalCanvas { o in flyingRing(o: o, to: to, z: z, soft: soft, landed: landed) }
            }
        }
    }

    @ViewBuilder private func flyingRing(o: CGPoint, to: CGRect, z: CGFloat, soft: CGFloat, landed: Bool) -> some View {
        let dark = scheme == .dark
        let day = log.day(flight.date)
        let spec = LabRingSpec.month(day: day, today: false, dark: dark)
        let fromCentre = flight.from.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: to.midX, y: to.midY)
        let centre = LabMotion.lerp(fromCentre, CGPoint(x: to.midX, y: to.midY), z)
        // From a missing cell (paged to a day of another month) it only fades, at the page's size.
        let k = flight.from == nil ? 1 : z
        let radius = LabMotion.lerp(JourneyDayRing.radius, 100, k)
        let band = LabMotion.lerp(JourneyDayRing.band, theme.arc.width * 0.5, k)
        let gap = LabMotion.lerp(7.0 / 360, 0.014, k)
        let closedGap = LabMotion.lerp(0, 0.014, LabMotion.seg(k, 0.5, 1))
        let disc = LabMotion.lerp(JourneyDayRing.fill * 2, CircleMotion.dayDiscDiameter, k)
        let fill: Color? = spec.closed ? (day.allInTime ? JourneyDayRing.green(dark).opacity(0.24) : JourneyDayRing.greyFill(dark)) : nil
        ZStack {
            if !landed {
                NeuRaised(shape: Circle(), radius: 9 * k, offset: 4.5 * k)
                    .frame(width: disc, height: disc)
                    .opacity(Double(LabMotion.out(LabMotion.seg(k, 0.05, 0.6))))
            }
            if let fill {
                Circle().fill(fill).frame(width: disc, height: disc).opacity(Double(1 - LabMotion.seg(k, 0, 0.6)))
            }
            LabRing(spec: spec, band: band, gap: gap, closedGap: closedGap)
                .frame(width: radius * 2, height: radius * 2)
                .opacity(Double(soft))
        }
        .position(x: centre.x - o.x, y: centre.y - o.y)
        .opacity(flight.from == nil ? Double(min(z * 2, 1)) : 1)
    }
}
