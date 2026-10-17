import SwiftUI
import SwiftData
import MapKit

// Prayer scores (Journey phase 3, owner 2026-10-16; board/mocks/journey/spec.md "Prayer scores, lifetime" + "Final"; the
// canvas mock v9 drawn from his own data). One lifetime page, no 7 / 30 / 12 switch: every prayer ever marked is a dot on
// its window's colour bar and the picture keeps adding up. All five: the ring (the score when you pray), two lines (how
// often · the 7 / 30 day trend), one sentence, five rows best → worst. Tap a row: it moves up to the top and that prayer
// opens under it (its chart large, the four grades as chips that focus the chart, an insight, To make up, photos, where).
// Rules: active days only (a day with a mark); excused prayers are never due; the score when you pray leaves misses out,
// the rows' rank counts a miss as 0; a trend shows only with 5+ days on both sides.

/// Everything the page shows, read once off the main thread (`load`). Plain values.
struct PrayerScores {
    enum Grade: String, CaseIterable, Identifiable {
        case perfect = "Perfect", onTime = "On time", late = "Late", qaza = "Qaza"
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .perfect: PrayerScoring.color(for: 1)
            case .onTime: PrayerScoring.color(for: 0.9)
            case .late: PrayerScoring.color(for: 0.7)
            case .qaza: PrayerScoring.color(for: PrayerScoring.qaza)
            }
        }
        static func of(_ score: Double) -> Grade {
            switch PrayerScoring.grade(for: score) {
            case .perfect: .perfect
            case .onTime: .onTime
            case .late: .late
            case .qaza: .qaza
            }
        }
    }

    struct Prayer {
        let name: String
        /// The average score of the prayers prayed, 0…100 (misses left out): "how well, when you pray it".
        var prayedScore: Int?
        /// The same, unrounded: it orders a tie of the rounded numbers.
        var prayedRaw: Double?
        /// The average score of the prayers due, a miss counting 0: the rows' rank.
        var lifeScore = 0
        var prayed = 0, due = 0, missed = 0
        var grades: [Grade: Int] = [:]
        /// Where in its window each prayer was marked: 0 = the start, 1 = the end, > 1 = after it (Qaza, capped 1.3).
        var positions: [Double] = []
        /// Where Perfect ends and Late starts, as a share of its usual window (its colour bar).
        var bands: (perfect: Double, late: Double) = (0.3, 0.65)
        /// "Usually 29 minutes after it starts." over the last 30 days (5+ marks), nil otherwise.
        var usual: String?
        var bestStreak = 0
        var masjid = 0
        var topMasjid: (name: String, count: Int)?
        var pins: [CLLocationCoordinate2D] = []
        var photos = 0
        var notes = 0
    }

    /// A score now against the same number of days with shukr before (nil: under 5 days on either side).
    struct Trend {
        let now: Int
        let before: Int
        var change: Int { now - before }
    }

    var prayers: [String: Prayer] = [:]
    var since: Date?
    var prayedScore: Int?
    var prayed = 0, due = 0
    var trend7: [String: Trend] = [:]
    var trend30: [String: Trend] = [:]

    static let names = JourneyLog.names
    /// Best → worst by the score when prayed — one score everywhere (owner, 2026-10-16: "just make it always be for the
    /// ones that we prayed"; Frank's check: the ring said 77 over a row saying 59 for the same prayer). Nothing prayed: last.
    var ranked: [String] { Self.names.sorted { (prayers[$0]?.prayedRaw ?? -1) > (prayers[$1]?.prayedRaw ?? -1) } }

    @MainActor static var last: PrayerScores?

    static func load(container: ModelContainer, ranges: [ExcusedRange], now: Date = Date()) async -> PrayerScores {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let log = JourneyLog.build(in: context, ranges: ranges, now: now)
            return build(log: log, context: context, now: now)
        }.value
    }

    static func build(log: JourneyLog, context: ModelContext, now: Date) -> PrayerScores {
        var out = PrayerScores()
        let days = log.days.values.filter(\.active).sorted { $0.date < $1.date }
        out.since = days.first?.date
        let today = Calendar.current.startOfDay(for: now)
        let recent30 = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today

        // Places: the completed rows' masjid names and spots, one per prayer per day.
        var places: [String: (mosque: String?, spot: CLLocationCoordinate2D?)] = [:]
        if let rows = try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted })) {
            for row in rows where names.contains(row.name) {
                let spot = row.latPrayedAt.flatMap { lat in row.longPrayedAt.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
                places[row.dayKey + row.name] = (row.mosqueName?.isEmpty == false ? row.mosqueName : nil, spot)
            }
        }

        // Photos as Moments lists them (one source, so "N photos ›" and the page it opens agree).
        let photoNames = PrayerPhotos.all().map(\.name)
        var allScores: [Double] = []
        for (i, name) in names.enumerated() {
            var p = Prayer(name: name)
            var scores: [Double] = [], dueScores: [Double] = [], windows: [TimeInterval] = []
            var recent: [Double] = [], recentStarts: [TimeInterval] = [], recentEnds: [TimeInterval] = []
            var streak = 0
            var mosques: [String: Int] = [:]
            for day in days {
                let mark = day.marks[i]
                switch mark {
                case .done(let s):
                    p.prayed += 1
                    scores.append(s); dueScores.append(s)
                    p.grades[Grade.of(s), default: 0] += 1
                    if let slot = day.slots[i] {
                        let length = slot.end.timeIntervalSince(slot.start)
                        if length > 0 { windows.append(length) }
                        if let at = slot.markedAt, length > 0 {
                            let pos = at.timeIntervalSince(slot.start) / length
                            p.positions.append(min(max(pos, 0), 1.3))
                            if day.date >= recent30 {
                                recent.append(pos)
                                recentStarts.append(at.timeIntervalSince(slot.start))
                                recentEnds.append(slot.end.timeIntervalSince(at))
                            }
                        }
                    }
                    if mark.inTime { streak += 1; p.bestStreak = max(p.bestStreak, streak) } else { streak = 0 }
                    let photoKey = PrayerPhotos.key(dayKey: day.key, name: name)
                    _ = photoKey
                    if PrayerPhotos.note(photoKey) != nil { p.notes += 1 }
                    if let place = places[day.key + name] {
                        if let m = place.mosque { p.masjid += 1; mosques[m, default: 0] += 1 }
                        if let spot = place.spot { p.pins.append(spot) }
                    }
                case .missed:
                    p.missed += 1
                    dueScores.append(0)
                    streak = 0
                case .excused, .toCome, .none:
                    break   // never due; doesn't break a streak
                }
            }
            p.photos = photoNames.filter { $0 == name }.count
            p.due = dueScores.count
            p.prayedRaw = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            p.prayedScore = p.prayedRaw.map { Int(($0 * 100).rounded()) }
            p.lifeScore = dueScores.isEmpty ? 0 : Int((dueScores.reduce(0, +) / Double(dueScores.count) * 100).rounded())
            p.topMasjid = mosques.max { $0.value < $1.value }.map { ($0.key, $0.value) }
            if let window = median(windows), window > 0 {
                let perfect = min(0.9, PrayerScoring.earlyWindow / window)
                p.bands = (perfect, perfect + (1 - perfect) / 2)
            }
            p.usual = usualLine(positions: recent, fromStart: recentStarts, toEnd: recentEnds)
            out.prayers[name] = p
            allScores += scores
            out.prayed += p.prayed
            out.due += p.due
        }
        out.prayedScore = allScores.isEmpty ? nil : Int((allScores.reduce(0, +) / Double(allScores.count) * 100).rounded())
        out.trend7 = trends(days: days, last: 7, today: today)
        out.trend30 = trends(days: days, last: 30, today: today)
        return out
    }

    /// The last `n` calendar days against the same number of days with shukr just before them; nil keys when either side
    /// has under 5 days.
    private static func trends(days: [JourneyLog.Day], last n: Int, today: Date) -> [String: Trend] {
        guard let from = Calendar.current.date(byAdding: .day, value: -(n - 1), to: today) else { return [:] }
        let nowDays = days.filter { $0.date >= from }
        let earlier = days.filter { $0.date < from }
        let beforeDays = Array(earlier.suffix(nowDays.count))
        guard nowDays.count >= 5, beforeDays.count >= 5 else { return [:] }
        func score(_ ds: [JourneyLog.Day], _ i: Int?) -> Int? {
            var due: [Double] = []
            for d in ds {
                for k in (i.map { [$0] } ?? Array(0..<5)) {
                    let m = d.marks[k]
                    if m.done || m == .missed { due.append(m.score ?? 0) }
                }
            }
            return due.isEmpty ? nil : Int((due.reduce(0, +) / Double(due.count) * 100).rounded())
        }
        var out: [String: Trend] = [:]
        for (i, name) in names.enumerated() {
            if let a = score(nowDays, i), let b = score(beforeDays, i) { out[name] = Trend(now: a, before: b) }
        }
        if let a = score(nowDays, nil), let b = score(beforeDays, nil) { out["all"] = Trend(now: a, before: b) }
        return out
    }

    /// The spec's "Usually …": the median place in the window decides the end it's measured from.
    private static func usualLine(positions: [Double], fromStart: [TimeInterval], toEnd: [TimeInterval]) -> String? {
        guard positions.count >= 5, let mid = median(positions) else { return nil }
        if mid < 0.5, let m = median(fromStart) { return "Usually \(minutes(m)) after it starts." }
        if mid <= 1, let m = median(toEnd.filter { $0 >= 0 }) { return "Usually \(minutes(m)) before it ends." }
        if let m = median(toEnd.filter { $0 < 0 }.map { -$0 }) { return "Usually prayed \(minutes(m)) after it ends." }
        return nil
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted(), c = s.count
        return c % 2 == 1 ? s[c / 2] : (s[c / 2 - 1] + s[c / 2]) / 2
    }

    // MARK: Words

    /// All five's sentence: the strongest (top row) and the one that needs you most (missed most often); the latest-prayed
    /// (bottom row) in grey when that's another prayer.
    var sentence: (line: String, sub: String?)? {
        let order = ranked.filter { (prayers[$0]?.prayed ?? 0) >= 5 }
        guard let top = order.first, let bottom = order.last, order.count >= 2 else { return nil }
        let share = { (n: String) -> Double in let p = prayers[n]; return Double(p?.prayed ?? 0) / Double(max(1, p?.due ?? 0)) }
        guard let needs = order.min(by: { share($0) < share($1) }) else { return nil }
        let sub = bottom == needs || bottom == top ? nil : "\(bottom) is your latest when you pray it"
        return ("\(top) is your strongest. \(needs) needs you most.", sub)
    }

    /// One true thing about a prayer, in a fixed order (spec: best-timed → longest streak → most at a masjid → mostly
    /// Perfect when in time → most prayed); nil when nothing is clearly true.
    func insight(_ name: String) -> (symbol: String, line: String, sub: String)? {
        guard let p = prayers[name], p.prayed >= 5 else { return nil }
        let others = Self.names.filter { $0 != name }.compactMap { prayers[$0] }
        if let s = p.prayedScore, others.allSatisfy({ ($0.prayedScore ?? 0) < s || $0.prayed < 5 }) {
            return ("star", "Historically your best-timed prayer: \(s) when you pray it.", "Higher than any other prayer when prayed")
        }
        if p.bestStreak >= 7, others.allSatisfy({ $0.bestStreak < p.bestStreak }) {
            return ("flame", "Your most steady prayer: a \(p.bestStreak)-day streak, your longest.", "In time, day after day you used shukr")
        }
        if p.masjid >= 3, others.allSatisfy({ $0.masjid < p.masjid }) {
            let at = p.topMasjid.map { "\($0.count) at \($0.name)" } ?? ""
            return ("building.columns", "Your masjid prayer: \(p.masjid) \(name)s at a masjid.", at)
        }
        let perfect = p.grades[.perfect] ?? 0, inTime = perfect + (p.grades[.onTime] ?? 0) + (p.grades[.late] ?? 0)
        if inTime >= 10, perfect * 2 > inTime {
            return ("sparkles", "When you pray \(name) in time, it's usually Perfect: \(perfect) of \(inTime).", "Right after the adhan")
        }
        if p.due > 0, others.allSatisfy({ $0.due == 0 || Double($0.prayed) / Double($0.due) < Double(p.prayed) / Double(p.due) }) {
            return ("checkmark.circle", "Your most prayed: \(p.prayed) of \(p.due).", "More often than any other prayer")
        }
        if p.bestStreak >= 3 {
            return ("flame", "Your best streak: \(p.bestStreak) days in a row.", "In time, day after day you used shukr")
        }
        return nil
    }
}

// MARK: - The page

struct PrayerScoresPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var data = PrayerScores.last ?? PrayerScores()
    @State private var loadToken = 0

    // The transition's state (A = all five, B = one prayer). The picked row is one view the whole way: the others fade, then
    // fold to nothing, so it rises into the top slot; back, they unfold, then fade in. Nothing is ever drawn twice.
    /// The prayer whose row stays (set before the others fold, cleared after they're back).
    @State private var selected: String?
    /// The prayer the ring and the lines show (swapped while they're faded out).
    @State private var shown: String?
    @State private var othersFaded = false
    @State private var folded = false
    @State private var linesFaded = false
    @State private var detailShown = false
    @State private var busy = false
    @State private var focus: PrayerScores.Grade?
    @State private var showMakeUp = false
    @State private var showMoments = false
    @State private var showMap = false
    #if DEBUG
    @MainActor static var demoPick: String?
    #endif

    private static let rowHeight: CGFloat = 62

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ring.padding(.top, 12)
                // The overview's two grey lines went (owner: "We can get rid of the two gray lines … keep it with just the
                // ring. And the one-liner"); an open prayer keeps its own.
                if shown != nil { lines.padding(.top, 14) }
                sentence
                rows.padding(.top, folded ? 10 : 18)
                if selected != nil { detail }
                footnote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationTitle("Prayer scores")
        .navigationBarTitleDisplayMode(.inline)
        // A prayer opens in place, not as a page: while one is open, ‹ closes it back to Prayer scores (owner,
        // 2026-10-17: "clicking the back chevron is kind of annoying because it takes us back to the card page instead
        // of just exiting out of that current prayers page"). The system's ‹ comes back once it's closed.
        .navigationBarBackButtonHidden(selected != nil)
        .toolbar {
            if selected != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back to Prayer scores")
                }
            }
        }
        .navigationDestination(isPresented: $showMakeUp) {
            JourneyMakeUpPage(month: JourneyLog.monthStart(PrayerDay.start()), startOnly: shown)
        }
        .navigationDestination(isPresented: $showMoments) { MemoriesPage(onlyPrayer: shown) }
        .sheet(isPresented: $showMap) {
            if let s = shown, let p = data.prayers[s] { PrayerScoresMap(name: s, pins: p.pins) }
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in reload() }
        #if DEBUG
        .task {
            guard let pick = Self.demoPick else { return }
            Self.demoPick = nil
            try? await Task.sleep(for: .seconds(1.2))
            open(pick)
        }
        #endif
    }

    private func reload() {
        loadToken += 1
        let token = loadToken, container = context.container, ranges = Excused.ranges
        Task {
            let built = await PrayerScores.load(container: container, ranges: ranges)
            guard token == loadToken else { return }
            data = built
            PrayerScores.last = built
        }
    }

    // MARK: A ⇄ B

    private func motion(_ animation: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : animation }

    /// Waits `seconds` (shorter when Reduce Motion is on).
    private func beat(_ seconds: Double) async { try? await Task.sleep(for: .seconds(reduceMotion ? 0.12 : seconds)) }

    private func open(_ name: String) {
        guard !busy, selected == nil else { return }
        busy = true
        triggerSomeVibration(type: .light)
        selected = name
        Task { @MainActor in
            // 1 · the other rows, the picked row's small chart, the ring's words and the lines fade where they are.
            withAnimation(motion(.easeOut(duration: 0.18))) {
                othersFaded = true
                linesFaded = true
            }
            await beat(0.22)   // fully out before anything swaps
            // 2 · the others fold away; the picked row rises into the top slot. The ring's words swap while they're out.
            withAnimation(motion(.smooth(duration: 0.45))) {
                shown = name
                folded = true
            }
            // 3 · the ring's words come back as the row lands (the ring sat empty ~0.8 s — Frank), then its page under it.
            await beat(0.18)
            withAnimation(motion(.easeOut(duration: 0.25))) { linesFaded = false }
            await beat(0.14)
            withAnimation(motion(.easeOut(duration: 0.3))) { detailShown = true }
            await beat(0.4)
            busy = false
        }
    }

    private func close() {
        guard !busy, selected != nil else { return }
        busy = true
        triggerSomeVibration(type: .light)
        Task { @MainActor in
            withAnimation(motion(.easeIn(duration: 0.18))) {
                detailShown = false
                linesFaded = true
            }
            await beat(0.22)   // fully out before the words swap (one faint frame read "Asr · 75" — Frank)
            focus = nil
            withAnimation(motion(.smooth(duration: 0.45))) {
                shown = nil
                folded = false
            }
            await beat(0.34)
            withAnimation(motion(.easeOut(duration: 0.22))) {
                othersFaded = false
                linesFaded = false
            }
            await beat(0.24)
            selected = nil
            busy = false
        }
    }

    // MARK: The ring and its lines

    private var ringScore: Int? { shown.flatMap { data.prayers[$0]?.prayedScore } ?? (shown == nil ? data.prayedScore : nil) }

    /// The five prayers as fifths, Fajr at the top going round, each in its own average's grade colour, the score in the
    /// middle (owner, 2026-10-17, from Frank's mock: "I like your fifth string idea, but I only want to use what I just
    /// sent you, that picture for the top"). A prayer open: its fifth stays, the others fade, its name over its score. A
    /// tap on a fifth is a tap on that prayer's row ("clicking on any one of the fifths is the same as if we clicked on the
    /// list item").
    private var ring: some View {
        let size: CGFloat = 192, band: CGFloat = 9
        return ZStack {
            ForEach(0..<5, id: \.self) { i in
                let name = JourneyLog.names[i]
                let arc = JourneyDayRing.fifth(i)
                let score = data.prayers[name]?.prayedScore
                Circle().trim(from: arc.from, to: arc.to)
                    .stroke(score.map { PrayerScoring.color(for: Double($0) / 100) } ?? Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: band, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(shown == nil || shown == name ? 1 : 0.18)
            }
            .padding(band)
            VStack(spacing: 1) {
                if shown != nil {
                    Text(shown ?? " ")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .opacity(linesFaded ? 0 : 1)
                }
                Text(ringScore.map { "\($0)" } ?? "–")
                    .font(.system(size: 54, weight: .thin, design: .rounded)).monospacedDigit()
                    .contentTransition(.identity)
                    .opacity(linesFaded ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(SpatialTapGesture().onEnded { tap in
            // The fifth under the finger: its angle from the top, clockwise.
            let dx = tap.location.x - size / 2, dy = tap.location.y - size / 2
            var angle = atan2(dx, -dy) * 180 / .pi
            if angle < 0 { angle += 360 }
            let name = JourneyLog.names[min(Int(angle / 72), 4)]
            guard data.prayers[name] != nil else { return }
            if selected == nil { open(name) } else { close() }
        })
        .accessibilityElement(children: .combine)
    }

    /// Two lines under the ring, on both pages: what it covers / when you usually pray it, then the 7 / 30 day trend.
    private var lines: some View {
        VStack(spacing: 5) {
            if let s = shown, let p = data.prayers[s] {
                Text(p.usual.map { $0.replacingOccurrences(of: "Usually", with: "Lately, usually") }
                     ?? "Not enough yet to say when you usually pray it.")
                    .font(.system(size: 14, weight: .light, design: .rounded))
            } else {
                Text("\(data.prayed.formatted()) of \(data.due.formatted()) prayed\(sinceWords.map { " · since \($0)" } ?? "")")
                    .font(.system(size: 13.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            trendLine(shown ?? "all")
        }
        .multilineTextAlignment(.center)
        .opacity(linesFaded ? 0 : 1)
    }

    private var sinceWords: String? { data.since?.formatted(.dateTime.month(.abbreviated).year()) }

    @ViewBuilder private func trendLine(_ key: String) -> some View {
        let parts = [("Last 7 days", data.trend7[key]), ("last 30 days", data.trend30[key])].compactMap { label, t in t.map { (label, $0) } }
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    if i > 0 { Text("·").foregroundStyle(.secondary) }
                    HStack(spacing: 4) {
                        Text(part.0).foregroundStyle(.secondary)
                        Text(Self.change(part.1.change)).foregroundStyle(.primary)
                    }
                }
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
        }
    }

    static func change(_ d: Int) -> String { abs(d) < 3 ? "steady" : d > 0 ? "↑\(d)" : "↓\(-d)" }

    @ViewBuilder private var sentence: some View {
        if let s = data.sentence {
            VStack(spacing: 3) {
                Text(s.line).font(.system(size: 17, weight: .light, design: .rounded))
                if let sub = s.sub { Text(sub).font(.system(size: 13.5, weight: .light, design: .rounded)).foregroundStyle(.secondary) }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 14)
            .opacity(othersFaded || linesFaded ? 0 : 1)   // fades with the rows, both ways
            .frame(height: folded ? 0 : nil, alignment: .top)
            .clipped()
        }
    }

    // MARK: The rows

    private var rows: some View {
        let per = PrayerScoresChart.perDot(data.ranked.compactMap { data.prayers[$0] }, big: false)
        return VStack(spacing: 0) {
            ForEach(data.ranked, id: \.self) { name in
                let isPicked = selected == name
                let hidden = selected != nil && !isPicked
                row(name, per: per, picked: isPicked)
                    .frame(height: hidden && folded ? 0 : Self.rowHeight, alignment: .top)
                    .clipped()
                    .opacity(hidden && othersFaded ? 0 : 1)
                    .allowsHitTesting(!hidden)
            }
        }
    }

    private func row(_ name: String, per: Int, picked: Bool) -> some View {
        let p = data.prayers[name]
        return Button {
            if selected == nil { open(name) } else if picked { close() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: prayerIcon(for: name))
                    .font(.system(size: 19, weight: .light)).foregroundStyle(picked ? .primary : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    // One weight and one colour always: changing either as the move starts dropped the name for the
                    // whole rise (seen frame by frame, 2026-10-16).
                    Text(name).font(.system(size: 16, weight: .light, design: .rounded))
                    Text(p.map { p in p.prayedScore.map { "\($0) · \(Int((Double(p.prayed) / Double(max(1, p.due)) * 100).rounded()))% prayed" } ?? "Not enough yet" } ?? " ")
                        .font(.system(size: 12.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                .frame(width: 104, alignment: .leading)
                Group {
                    if let p, !p.positions.isEmpty {
                        PrayerScoresChart(prayer: p, per: per, big: false, focus: nil)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 46)
                .opacity(picked && (othersFaded || detailShown) ? 0 : 1)
                Image(systemName: picked ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                    .opacity(picked && folded ? 0 : 1)
            }
            .frame(height: Self.rowHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).opacity(picked && folded ? 0 : 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(picked ? "Back to all five prayers" : "Opens \(name)'s scores")
    }

    // MARK: One prayer

    @ViewBuilder private var detail: some View {
        if let s = selected, let p = data.prayers[s] {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    HStack {
                        Spacer()
                        let per = PrayerScoresChart.perDot([p], big: true)
                        Text("1 dot = \(per) prayer\(per == 1 ? "" : "s")")
                            .font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                    PrayerScoresChart(prayer: p, per: PrayerScoresChart.perDot([p], big: true), big: true, focus: focus)
                        .frame(height: 150)
                }
                .stagger(detailShown, 0)
                chartLine(p).padding(.top, 10).stagger(detailShown, 1)
                chips(p).padding(.top, 12).stagger(detailShown, 1)
                VStack(spacing: 0) {
                    if let i = data.insight(s) {
                        listRow(symbol: i.symbol, title: i.line, sub: i.sub, door: false) {}
                    }
                    if p.missed > 0 {
                        listRow(symbol: "clock", title: "\(p.missed) to make up", sub: "Unmarked on days you used shukr", door: true) { showMakeUp = true }
                    }
                    if p.photos > 0 {
                        listRow(symbol: "photo.on.rectangle", title: p.photos == 1 ? "1 photo" : "\(p.photos) photos",
                                sub: p.notes > 0 ? "\(p.notes) with a note" : "Your moments", door: true) { showMoments = true }
                    }
                    if !p.pins.isEmpty {
                        listRow(symbol: "mappin.and.ellipse", title: "Where you pray it",
                                sub: p.topMasjid.map { "Most at a masjid: \($0.name) (\($0.count))" } ?? "\(p.pins.count) with a place",
                                door: true) { showMap = true }
                    }
                }
                .padding(.top, 18)
                .stagger(detailShown, 2)
            }
            .padding(.top, 8)
        }
    }

    private func chartLine(_ p: PrayerScores.Prayer) -> some View {
        Group {
            if let f = focus {
                Text("\(p.grades[f] ?? 0) \(f.rawValue)").fontWeight(.regular)
                + Text(" of \(p.prayed) prayed").foregroundStyle(.secondary)
            } else {
                Text("\(p.prayed) prayed").foregroundStyle(.primary)
                + Text("\(sinceWords.map { " since \($0)" } ?? "") · \(p.missed) missed").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15, weight: .light, design: .rounded))
        .contentTransition(.opacity)
    }

    private func chips(_ p: PrayerScores.Prayer) -> some View {
        HStack(spacing: 8) {
            ForEach(PrayerScores.Grade.allCases) { g in
                let on = focus == g
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.25)) { focus = on ? nil : g }
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(g.color.opacity(0.75)).frame(width: 9, height: 9)
                            Text("\(p.grades[g] ?? 0)").font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
                        }
                        Text(g.rawValue).font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if on { NeuPressed(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 3, offset: 2) }
                        else { NeuRaised(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 3.5, offset: 1.8) }
                    }
                    .opacity(focus != nil && !on ? 0.55 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.grades[g] ?? 0) \(g.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func listRow(symbol: String, title: String, sub: String, door: Bool, action: @escaping () -> Void) -> some View {
        if door {
            Button {
                triggerSomeVibration(type: .light)
                action()
            } label: { listRowBody(symbol: symbol, title: title, sub: sub, door: true) }
            .buttonStyle(.plain)
        } else {
            listRowBody(symbol: symbol, title: title, sub: sub, door: false).accessibilityElement(children: .combine)
        }
    }

    private func listRowBody(symbol: String, title: String, sub: String, door: Bool) -> some View {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .light, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if door { Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sage) }
            }
            .padding(.vertical, 12)
            .frame(minHeight: 62)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
    }

    @ViewBuilder private var footnote: some View {
        let per = PrayerScoresChart.perDot(data.ranked.compactMap { data.prayers[$0] }, big: false)
        Text("Each dot = \(per) prayer\(per == 1 ? "" : "s"), on its window's color bar · past the end = Qaza")
            .font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 18)
            .opacity(othersFaded ? 0 : 1)
            .frame(height: folded ? 0 : nil)
            .clipped()
    }
}

private extension View {
    /// Fades in and rises a few points, one group after another down the page (step 3 of the way in); out together.
    func stagger(_ shown: Bool, _ index: Int) -> some View {
        self.opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(shown ? .easeOut(duration: 0.3).delay(Double(index) * 0.06) : .easeIn(duration: 0.18), value: shown)
    }
}

// MARK: - The chart

/// A prayer's lifetime as neat blocks of dots on its window's colour bar (owner: "clean, tidy, organized"): 14 slots across
/// the window, each slot a block a few dots wide, one dot standing for `per` prayers so the tallest block fits; Qaza is its
/// own block past the end. A focused grade keeps its stretch of the bar and its dots dark and fades the rest.
struct PrayerScoresChart: View {
    let prayer: PrayerScores.Prayer
    let per: Int
    let big: Bool
    let focus: PrayerScores.Grade?

    static let slots = 14

    private struct Metrics {
        let r: CGFloat, step: CGFloat, bandH: CGFloat, labels: CGFloat
        init(big: Bool) {
            r = big ? 2.6 : 1.6
            step = r * 2 + (big ? 1.4 : 1)
            bandH = big ? 8 : 4
            labels = big ? 20 : 0
        }
    }

    /// Prayers per dot so the fullest block of these prayers fits its height (the same for every row compared).
    static func perDot(_ prayers: [PrayerScores.Prayer], big: Bool, width: CGFloat? = nil, height: CGFloat? = nil) -> Int {
        let m = Metrics(big: big)
        let w = width ?? (big ? 354 : 190), h = height ?? (big ? 150 : 46)
        let windowW = w * 0.74, slotW = windowW / CGFloat(slots)
        let wide = max(1, Int((slotW - 1) / m.step)), tall = max(1, Int((h - m.labels - m.bandH - 6) / m.step))
        var fullest = 0
        for p in prayers {
            var counts = Array(repeating: 0, count: slots)
            for v in p.positions where v <= 1 { counts[min(slots - 1, max(0, Int(v * Double(slots))))] += 1 }
            fullest = max(fullest, counts.max() ?? 0)
        }
        return max(1, Int((Double(fullest) / Double(wide * tall)).rounded(.up)))
    }

    var body: some View {
        Canvas { ctx, size in
            let m = Metrics(big: big)
            let x0: CGFloat = 2, end = size.width * 0.74, after = size.width * 0.86
            let base = size.height - m.labels - m.bandH - 4
            let slotW = (end - x0) / CGFloat(Self.slots)
            let wide = max(1, Int((slotW - 1) / m.step)), tall = max(1, Int((base - 2) / m.step))
            let ink = Color.primary
            func zone(_ v: Double) -> PrayerScores.Grade { v < prayer.bands.perfect ? .perfect : v < prayer.bands.late ? .onTime : .late }
            func dim(_ g: PrayerScores.Grade) -> Double { focus == nil ? 1 : focus == g ? 1 : 0.15 }

            // The window's colour bar: Perfect · On time · Late, then a dashed stretch for after the end.
            let xPerfect = x0 + CGFloat(prayer.bands.perfect) * (end - x0), xLate = x0 + CGFloat(prayer.bands.late) * (end - x0)
            let barY = base + 2
            func bar(_ from: CGFloat, _ to: CGFloat, _ g: PrayerScores.Grade, _ base: Double) {
                let rect = CGRect(x: from, y: barY, width: max(0, to - from), height: m.bandH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: m.bandH / 2), with: .color(g.color.opacity(base * (focus == nil ? 1 : focus == g ? 1.8 : 0.35))))
            }
            bar(x0, xPerfect, .perfect, 0.38)
            bar(xPerfect, xLate, .onTime, 0.42)
            bar(xLate, end, .late, 0.32)
            var dash = Path()
            dash.move(to: CGPoint(x: end + 4, y: barY + m.bandH / 2))
            dash.addLine(to: CGPoint(x: after + (big ? 8 : 4), y: barY + m.bandH / 2))
            ctx.stroke(dash, with: .color(Color.secondary.opacity(focus == .qaza ? 0.7 : 0.35)),
                       style: StrokeStyle(lineWidth: big ? 2 : 1.4, dash: [2, 4]))

            // Blocks inside the window.
            var counts = Array(repeating: 0, count: Self.slots)
            var qaza = 0
            for v in prayer.positions {
                if v > 1 { qaza += 1 } else { counts[min(Self.slots - 1, max(0, Int(v * Double(Self.slots))))] += 1 }
            }
            let dotOpacity = big ? 0.8 : 0.72
            for (k, n) in counts.enumerated() where n > 0 {
                let dots = min(wide * tall, max(1, Int((Double(n) / Double(per)).rounded())))
                let left = x0 + CGFloat(k) * slotW + (slotW - CGFloat(wide) * m.step) / 2 + m.r
                let g = zone((Double(k) + 0.5) / Double(Self.slots))
                for i in 0..<dots {
                    let c = CGPoint(x: left + CGFloat(i % wide) * m.step, y: base - m.r - CGFloat(i / wide) * m.step)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - m.r, y: c.y - m.r, width: m.r * 2, height: m.r * 2)),
                             with: .color(ink.opacity(dotOpacity * dim(g))))
                }
            }
            // Qaza: its own block past the end, filled bottom-up then rightward.
            if qaza > 0 {
                let dots = max(1, Int((Double(qaza) / Double(per)).rounded()))
                let qx = end + m.r * 2 + 2
                for i in 0..<dots {
                    let c = CGPoint(x: qx + CGFloat(i / tall) * m.step, y: base - m.r - CGFloat(i % tall) * m.step)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - m.r, y: c.y - m.r, width: m.r * 2, height: m.r * 2)),
                             with: .color(ink.opacity(dotOpacity * (focus == nil ? 0.55 : focus == .qaza ? 1 : 0.15))))
                }
            }
            if big {
                let y = barY + m.bandH + 12
                let style = Font.system(size: 12, weight: .light, design: .rounded)
                ctx.draw(Text("starts").font(style).foregroundStyle(.secondary), at: CGPoint(x: x0, y: y), anchor: .leading)
                ctx.draw(Text("ends").font(style).foregroundStyle(.secondary), at: CGPoint(x: end, y: y), anchor: .trailing)
                ctx.draw(Text("Qaza").font(style).foregroundStyle(.secondary), at: CGPoint(x: (end + after) / 2 + 6, y: y), anchor: .center)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let g = PrayerScores.Grade.allCases.map { "\(prayer.grades[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
        return "\(prayer.name): \(prayer.prayed) prayed. \(g)."
    }
}

// MARK: - Where you pray it

/// Every spot a prayer was marked, on a map (a sheet; the prayer's pins only).
private struct PrayerScoresMap: View {
    let name: String
    let pins: [CLLocationCoordinate2D]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map(initialPosition: Self.usualArea(pins)) {
                ForEach(Array(pins.enumerated()), id: \.offset) { _, spot in
                    Annotation("", coordinate: spot) {
                        Circle().fill(Color.sage).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    }
                }
            }
            .mapControls { MapCompass() }
            .navigationTitle("Where you pray \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Framed on where most of its pins are (the pins near the middle one), not every pin ever: one trip abroad opened
    /// the map on an ocean. The rest are a zoom out away.
    static func usualArea(_ pins: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !pins.isEmpty else { return .automatic }
        let lat = pins.map(\.latitude).sorted()[pins.count / 2], lon = pins.map(\.longitude).sorted()[pins.count / 2]
        let near = pins.filter { abs($0.latitude - lat) < 0.5 && abs($0.longitude - lon) < 0.5 }
        let lats = near.map(\.latitude), lons = near.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return .automatic }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (maxLat - minLat) * 1.4), longitudeDelta: max(0.02, (maxLon - minLon) * 1.4))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
