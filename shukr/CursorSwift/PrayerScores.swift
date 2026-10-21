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
        case perfect, onTime, late, qaza
        var id: String { rawValue }
        /// Its word, from PrayerScoring (the one place the grade words live): Perfect · Middle · Closing · Qaza.
        var word: String {
            switch self {
            case .perfect: PrayerScoring.Grade.perfect.rawValue
            case .onTime: PrayerScoring.Grade.onTime.rawValue
            case .late: PrayerScoring.Grade.late.rawValue
            case .qaza: PrayerScoring.Grade.qaza.rawValue
            }
        }
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
        /// Its prayers to make up in the span, the fresh start or not: owed prayers are kept (owner, 2026-10-18: "keep qaza
        /// forsure").
        var owed = 0
        var grades: [Grade: Int] = [:]
        /// Where in its window each prayer was marked: 0 = the start, 1 = the end, > 1 = after it (Qaza, capped 1.3).
        var positions: [Double] = []
        /// Where Perfect ends and Late starts, as a share of its usual window (its colour bar).
        var bands: (perfect: Double, late: Double) = (0.3, 0.65)
        /// Its usual window's length (the median of its prayed days'), for a histogram slot's minutes.
        var window: TimeInterval?
        /// "Usually 29 minutes after it starts." over the last 30 days (5+ marks), nil otherwise.
        var usual: String?
        /// "Usually 18 minutes after it starts": the median time since its window began, over the span's in-window marks
        /// (owner, 2026-10-20: "one metric that really helps with performance … is how much time elapsed since the start …
        /// something we can compare against with every one of the like prayer"; the clock time "doesn't mean anything about
        /// my performance because the times of prayers shift").
        var sinceStart: String?
        /// Season-proof (owner, 2026-10-20: "Make the usual line season-proof (place in the window)"): the median place in its
        /// window (0 as it begins, 1 as it ends) over the span's in-window marks — the same habit reads the same in a 2.5 h
        /// winter Dhuhr and a 4 h summer one (Frank's note: minutes drift with the seasons). nil under 5 marks.
        var usualShare: Double?
        var bestStreak = 0
        var masjid = 0
        var topMasjid: (name: String, count: Int)?
        var pins: [CLLocationCoordinate2D] = []
        var photos = 0
        var notes = 0
        /// Prayed in its window (Opening, Middle or Closing) — the rows' "in its time X of Y".
        var inTime: Int { (grades[.perfect] ?? 0) + (grades[.onTime] ?? 0) + (grades[.late] ?? 0) }
        /// In its time over what was due (the obligation bar), nil with nothing due.
        var inTimeShare: Double? { due > 0 ? Double(inTime) / Double(due) : nil }
    }

    /// A score now against the same number of days with shukr before (nil: under 5 days on either side).
    struct Trend {
        let now: Int
        let before: Int
        var change: Int { now - before }
    }

    /// The days the page covers (owner, 2026-10-17: "toggles it from an all-time view to a 30-day view or a seven-day
    /// view"; "we can do all time, 30 days, 7 days").
    enum Span: String, CaseIterable {
        case all, days30 = "30", days7 = "7"
        var days: Int? { switch self { case .all: nil; case .days30: 30; case .days7: 7 } }
        var title: String { switch self { case .all: "All time"; case .days30: "30 days"; case .days7: "7 days" } }
        /// Under the ring's number.
        var ringLabel: String { switch self { case .all: "average\nlifetime score"; case .days30: "average score\nlast 30 days"; case .days7: "average score\nlast 7 days" } }
    }
    var span = Span.all
    /// The fresh start, when it cuts into this span (All time: whenever there is one): the page counts from it and says so
    /// ("since Oct 17") — a lifetime number after a fresh start would be the discouraging stat it's there to clear (owner,
    /// 2026-10-18, his pick: "average lifetime score" counts from the reset).
    var countsFrom: Date?
    /// The goal the streak lines were counted at (PrayerGoal).
    var goal = PrayerGoal.prayed

    /// Under the ring's number: the span's words, or "since Oct 17" when the fresh start cuts into it.
    /// The date is said once, on the line under the chart ("since Oct 17"; a fact once per screen — audit #13).
    var ringLabel: String {
        countsFrom == nil ? span.ringLabel : "average score"
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
    /// With the rethink, by in its time over due — the number each row shows (Fable's review, owner's yes 2026-10-21: "rank the
    /// rows and the sentence by in its time"); a tie by more in time, then the day's order.
    var ranked: [String] {
        if MetricsLook.on {
            return Self.names.enumerated().sorted { a, b in
                let pa = prayers[a.element], pb = prayers[b.element]
                let sa = pa?.inTimeShare ?? -1, sb = pb?.inTimeShare ?? -1
                if sa != sb { return sa > sb }
                if (pa?.inTime ?? 0) != (pb?.inTime ?? 0) { return (pa?.inTime ?? 0) > (pb?.inTime ?? 0) }
                return a.offset < b.offset
            }.map(\.element)
        }
        return Self.names.sorted { (prayers[$0]?.prayedRaw ?? -1) > (prayers[$1]?.prayedRaw ?? -1) }
    }


    /// Read off the main thread, at the goal and from the fresh start as they are now (PrayerStats).
    static func load(container: ModelContainer, ranges: [ExcusedRange], now: Date = Date(), span: Span = .all,
                     countsFrom: Date? = PrayerStats.countsFrom, goal: PrayerGoal = .current) async -> PrayerScores {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let log = JourneyLog.build(in: context, ranges: ranges, now: now)
            return build(log: log, context: context, now: now, span: span, countsFrom: countsFrom, goal: goal)
        }.value
    }

    static func build(log: JourneyLog, context: ModelContext, now: Date, span: Span = .all,
                      countsFrom: Date? = nil, goal: PrayerGoal = .prayed) -> PrayerScores {
        var out = PrayerScores()
        out.span = span
        out.goal = goal
        let today = Calendar.current.startOfDay(for: now)
        // Only the days from the fresh start count (PrayerStats): the span, the trends, the streaks — nothing reaches back
        // past it.
        let allDays = log.days.values.filter { d in d.active && (countsFrom.map { d.date >= $0 } ?? true) }
            .sorted { $0.date < $1.date }
        // The span's days only (the trends below still compare across all of them), clipped to the fresh start.
        let spanFrom = span.days.flatMap { Calendar.current.date(byAdding: .day, value: -($0 - 1), to: today) }
        if let f = countsFrom, span == .all || spanFrom.map({ f > $0 }) == true { out.countsFrom = f }
        let days = spanFrom.map { f in allDays.filter { $0.date >= f } } ?? allDays
        // To make up counts every miss in the span, from before the fresh start too — unless it cleared them (as To make up).
        let owedFrom = FreshStart.makeUpFrom
        let owedDays = log.days.values.filter { d in
            d.active && (spanFrom.map { d.date >= $0 } ?? true) && (owedFrom.map { d.date >= $0 } ?? true)
        }
        out.since = days.first?.date
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
            var inWindowStarts: [TimeInterval] = [], inWindowShares: [Double] = []
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
                            if pos <= 1 { inWindowStarts.append(at.timeIntervalSince(slot.start)); inWindowShares.append(max(pos, 0)) }
                            if day.date >= recent30 {
                                recent.append(pos)
                                recentStarts.append(at.timeIntervalSince(slot.start))
                                recentEnds.append(slot.end.timeIntervalSince(at))
                            }
                        }
                    }
                    // The goal's streak (PrayerGoal): a day this prayer met it adds one, else it breaks.
                    if goal.meets(score: s) { streak += 1; p.bestStreak = max(p.bestStreak, streak) } else { streak = 0 }
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
            p.owed = owedDays.filter { $0.marks[i] == .missed }.count
            p.due = dueScores.count
            p.prayedRaw = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            p.prayedScore = p.prayedRaw.map { Int(($0 * 100).rounded()) }
            p.lifeScore = dueScores.isEmpty ? 0 : Int((dueScores.reduce(0, +) / Double(dueScores.count) * 100).rounded())
            p.topMasjid = mosques.max { $0.value < $1.value }.map { ($0.key, $0.value) }
            p.window = median(windows)
            // The chart's bar in thirds, as the score (Opening · Middle · Closing) — the same for every prayer now.
            p.bands = (PrayerScoring.openingShare, 2 * PrayerScoring.openingShare)
            p.usual = usualLine(positions: recent, fromStart: recentStarts, toEnd: recentEnds)
            if inWindowStarts.count >= 5, let m = median(inWindowStarts) { p.sinceStart = "Usually \(elapsed(m)) after it starts" }
            if inWindowShares.count >= 5 { p.usualShare = median(inWindowShares) }
            out.prayers[name] = p
            allScores += scores
            out.prayed += p.prayed
            out.due += p.due
        }
        out.prayedScore = allScores.isEmpty ? nil : Int((allScores.reduce(0, +) / Double(allScores.count) * 100).rounded())
        out.trend7 = trends(days: allDays, last: 7, today: today)
        out.trend30 = trends(days: allDays, last: 30, today: today)
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

    /// "Usually a third of the way in · about 26 minutes in today": the place (season-proof), then what it is on today's window
    /// (`today`: today's window length, nil when there isn't one).
    static func placeLine(_ share: Double, today: TimeInterval?) -> String {
        // In words, not a percent (Frank's check: "37%" reads like a score on a page that just lost its numbers).
        let place: String = switch share {
        case ..<0.12: "near its start"
        case ..<0.29: "a quarter of the way in"
        case ..<0.42: "a third of the way in"
        case ..<0.58: "halfway in"
        case ..<0.71: "two-thirds of the way in"
        case ..<0.88: "three-quarters of the way in"
        default: "near its end"
        }
        var line = "Usually \(place)"
        if let today, today > 0 { line += " · about \(elapsed(share * today)) in today" }
        return line
    }

    /// "28 minutes", "2 h 14 min" (Dhuhr's "134 minutes" read badly — Zoe's sim check).
    static func elapsed(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
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
        if MetricsLook.on {
            // In its time over due, as the rows: the top row is the strongest, the bottom one needs you most; the one you
            // pray deepest into its window in grey (its usual place, season-proof).
            let order = ranked.filter { (prayers[$0]?.due ?? 0) >= 5 }
            guard let top = order.first, let needs = order.last, order.count >= 2 else { return nil }
            guard prayers[needs]?.inTimeShare != prayers[top]?.inTimeShare else { return ("All \(order.count == 5 ? "five" : "\(order.count)") in their windows alike.", nil) }   // only those with 5+ due (Frank)
            let latest = order.filter { prayers[$0]?.usualShare != nil }.max { (prayers[$0]?.usualShare ?? 0) < (prayers[$1]?.usualShare ?? 0) }
            let sub = latest.flatMap { $0 == top || $0 == needs ? nil : "You pray \($0) latest in its window" }
            return ("\(top) is your strongest. \(needs) needs you most.", sub)
        }
        let order = ranked.filter { (prayers[$0]?.prayed ?? 0) >= 5 }
        guard let top = order.first, let bottom = order.last, order.count >= 2 else { return nil }
        let share = { (n: String) -> Double in let p = prayers[n]; return Double(p?.prayed ?? 0) / Double(max(1, p?.due ?? 0)) }
        // The least prayed needs you most; when they're all prayed as often (a clean week), the lowest score does — never
        // the strongest one twice ("Maghrib is your strongest. Maghrib needs you most." on a 7-day view).
        guard let leastPrayed = order.min(by: { share($0) < share($1) }) else { return nil }
        let needs = share(leastPrayed) < share(top) ? leastPrayed : bottom
        guard needs != top else { return ("\(top) is your strongest.", nil) }
        let sub = bottom == needs || bottom == top ? nil : "\(bottom) is your latest when you pray it"
        return ("\(top) is your strongest. \(needs) needs you most.", sub)
    }

    /// One true thing about a prayer, in a fixed order (spec: best-timed → longest streak → most at a masjid → mostly
    /// Perfect when in time → most prayed); nil when nothing is clearly true.
    /// What a prayer's streak counts, in the goal's words ("In time" only when that's the goal).
    private var streakWords: String {
        switch goal {
        case .prayed: "Prayed, day after day you used shukr"
        case .inWindow: "In its window, day after day you used shukr"
        case .onTime: "By the Middle, day after day you used shukr"
        case .perfect: "In the Opening, day after day you used shukr"
        }
    }

    func insight(_ name: String) -> (symbol: String, line: String, sub: String)? {
        guard let p = prayers[name], p.prayed >= 5 else { return nil }
        let others = Self.names.filter { $0 != name }.compactMap { prayers[$0] }
        // A score (0–100) isn't shown with the rethink (MetricsLook).
        if !MetricsLook.on, let s = p.prayedScore, others.allSatisfy({ ($0.prayedScore ?? 0) < s || $0.prayed < 5 }) {
            let when = countsFrom == nil ? "Historically your" : "Since your fresh start, your"
            return ("star", "\(when) best-timed prayer: \(s) when you pray it.", "Higher than any other prayer when prayed")
        }
        // No per-prayer day streak with the rethink: it skipped days without a record and the streak is weekly now (Fable's
        // review, owner's yes 2026-10-21: "drop the old streak insight").
        if !MetricsLook.on, p.bestStreak >= 7, others.allSatisfy({ $0.bestStreak < p.bestStreak }) {
            return ("flame", "Your most steady prayer: a \(p.bestStreak)-day streak, your longest.", streakWords)
        }
        if p.masjid >= 3, others.allSatisfy({ $0.masjid < p.masjid }) {
            let at = p.topMasjid.map { "\($0.count) at \($0.name)" } ?? ""
            return ("building.columns", "Your masjid prayer: \(p.masjid) \(name)s at a masjid.", at)
        }
        let perfect = p.grades[.perfect] ?? 0, inTime = perfect + (p.grades[.onTime] ?? 0) + (p.grades[.late] ?? 0)
        if inTime >= 10, perfect * 2 > inTime {
            return ("sparkles", "When you pray \(name) in its window, it's usually \(PrayerScoring.Grade.perfect.rawValue): \(perfect) of \(inTime).", "Right after the adhan")
        }
        if p.due > 0, others.allSatisfy({ $0.due == 0 || Double($0.prayed) / Double($0.due) < Double(p.prayed) / Double(p.due) }) {
            return ("checkmark.circle", "Your most prayed: \(p.prayed) of \(p.due).", "More often than any other prayer")
        }
        if !MetricsLook.on, p.bestStreak >= 3 {
            return ("flame", "Your best streak: \(p.bestStreak) days in a row.", streakWords)
        }
        return nil
    }
}

// MARK: - The page

struct PrayerScoresPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("prayerScores.span") private var spanRaw = PrayerScores.Span.all.rawValue
    private var span: PrayerScores.Span { PrayerScores.Span(rawValue: spanRaw) ?? .all }
    @State private var data = JourneyStore.shared.scoresBySpan[PrayerScores.Span(rawValue: UserDefaults.standard.string(forKey: "prayerScores.span") ?? "") ?? .all]
        ?? JourneyStore.shared.scoresBySpan[.all] ?? PrayerScores()
    @State private var loadToken = 0

    // The transition's state (A = all five, B = one prayer). The picked row is one view the whole way: the others fade, then
    // fold to nothing, so it rises into the top slot; back, they unfold, then fade in. Nothing is ever drawn twice.
    /// The prayer whose row stays (set before the others fold, cleared after they're back).
    @State private var selected: String?
    /// The picked row's name and score line, flown up into the header as the others fold (the same text, moving and
    /// growing — owner, 2026-10-17: "I want it to look like those same elements are going up into that area").
    @Namespace private var hero
    /// The prayer the ring and the lines show (swapped while they're faded out).
    @State private var shown: String?
    @State private var othersFaded = false
    @State private var folded = false
    @State private var linesFaded = false
    /// The ring's number and its label (they come back as the row lands; the lines under the title wait for it to land).
    @State private var ringFaded = false
    @State private var detailShown = false
    @State private var busy = false
    /// One open prayer giving way to another (a fifth tapped while one's open): the header's name and line, the ring's
    /// words and the lines fade, the prayer swaps, they come back — no close and open. The newest tap wins.
    @State private var swapping = false
    @State private var swapToken = 0
    /// A fifth tapped while a prayer was still opening or closing: switched to once that's done.
    @State private var pendingSwitch: String?
    /// The open prayer's histogram slot under the finger (0…13 its window, `PrayerScoresChart.qazaSlot` the Qaza block): its
    /// line in place of the usual ones (owner, 2026-10-17: "drag my finger on the histogram dots, kind of the same function as
    /// the row tiles … display that prayer's information under the header").
    @State private var slotPick: Int?
    @State private var chartWidth: CGFloat = 0
    @State private var focus: PrayerScores.Grade?
    @State private var showMakeUp = false
    @State private var showMoments = false
    @State private var showMap = false
    /// The way back on a dial (ScoresBack): ‹ runs it, a finger on the left edge holds it.
    @State private var dial = JourneyMonthDial()
    @State private var dialing = false
    /// Past the dial's ring swap: the ring shows all five's number again.
    @State private var dialRingAll = false
    /// The prayer the ring last unfolded: it folds back into its own fifth after `shown` lets go.
    @State private var ringOpen: String?
    @State private var heroFrames = ScoresHeroFrames()
    @State private var edgeSideways: Bool?
    @State private var dragFrom: CGFloat?
    /// A finger on the edge (back to false on a cancel too, which never reaches onEnded).
    @GestureState private var edgeHeld = false
    private var backDial: JourneyMonthDial? { dialing ? dial : nil }
    #if DEBUG
    @MainActor static var demoPick: String?
    #endif

    private static let rowHeight: CGFloat = 62
    /// The prayer-metrics rethink (MetricsLook): each prayer's last 7 days, the page's counts instead of its scores.
    private var recent: YourPrayersRecent { .shared }
    /// "Your prayers" (MetricsLook) or "Prayer scores".
    private var pageTitle: String { MetricsLook.on ? "Your prayers" : "Prayer scores" }

    var body: some View {
        let _ = JourneyPerf.body("scores")
        ScrollView {
            VStack(spacing: 0) {
                // Over the switch: the picked name and line fly up past it into the header and back (owner, 2026-10-17:
                // "looks strange cuz it goes up and behind the switcher").
                header.padding(.top, 4).zIndex(1)
                spanSwitch.padding(.top, 10)
                rows.modifier(ScoresBackRowsTop(folded: folded, dial: backDial))
                if selected != nil { detail.modifier(ScoresBackFade(part: .outFirst, rest: 1, dial: backDial)) }
                footnote
            }
            .padding(.horizontal, 16)
            // A tap anywhere off the chart lets its slot go (the chart's own tap wins on the chart; buttons keep theirs).
            .contentShape(Rectangle())
            .onTapGesture { if slotPick != nil { withAnimation(.easeOut(duration: 0.15)) { slotPick = nil } } }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        // An open prayer takes the page's title: "Prayer scores" waits in the bar (owner, 2026-10-17: "maybe the title
        // prayer scores goes in the top bar").
        .navigationTitle(shown != nil ? pageTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        // A prayer opens in place, not as a page: while one is open, ‹ closes it back to Prayer scores (owner,
        // 2026-10-17: "clicking the back chevron is kind of annoying because it takes us back to the card page instead
        // of just exiting out of that current prayers page"). The system's ‹ comes back once it's closed.
        .navigationBarBackButtonHidden(selected != nil)
        // With ‹ ours, the system's edge swipe is off: a swipe from the left edge closes the prayer as ‹ does (owner,
        // 2026-10-17: "i want to swipe from edge to go back to the full prayer list"), under the finger — the dial follows it
        // and lets go to all five or back (owner, 2026-10-18: "feels fluid, like how we did in the Journey page"). Closed,
        // the system's is back.
        .overlay(alignment: .leading) {
            if selected != nil {
                Color.clear.frame(width: 22).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeBack)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: edgeHeld) { _, held in if !held { edgeLetGo(nil) } }
        .background { if dialing { ScoresBackWatch(dial: dial) { all in if dialRingAll != all { dialRingAll = all } } } }
        .toolbar {
            if selected != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back to \(pageTitle)")
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
        .task(id: JourneyStore.shared.log?.version) { if MetricsLook.on { recent.read(JourneyStore.shared.log) } }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in
            if MetricsLook.on { recent.read(JourneyStore.shared.log, force: true) }
        }
        .onChange(of: spanRaw) { switchSpan() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in reload() }
        // A goal or fresh-start change empties the kept spans (JourneyStore); the .journeyChanged after it reloads, once.
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
            let span = self.span
            let t = JourneyPerf.now
            let built = await PrayerScores.load(container: container, ranges: ranges, span: span)
            JourneyPerf.took("scores.load", since: t)
            guard token == loadToken else { return }
            data = built
            JourneyStore.shared.scoresBySpan[span] = built
        }
    }

    // MARK: The span

    /// All time · 30 days · 7 days (owner, 2026-10-18: "Clicking between the switchers … doesn't do anything" — it changed,
    /// all at once): what's shown stays until the new span's numbers are in (kept, or read — never a blank between), then
    /// moves to them in one go: the numbers roll, the fifths and charts cross-fade, the rows re-rank in place. Inside a
    /// prayer, the fifths' quick swap (its lines and page out and back) with the ring's number rolling.
    private func switchSpan() {
        JourneyPerf.began("scores span")
        slotPick = nil
        let span = self.span
        loadToken += 1
        let token = loadToken
        let cached = JourneyStore.shared.scoresBySpan[span]
        Task { @MainActor in
            let next: PrayerScores
            if let cached { next = cached } else { next = await read(span) }
            guard token == loadToken, span == self.span else { return }
            show(next)
            // A kept span is read again: the log may have moved since (it lands quietly, as a reload does).
            if cached != nil { reload() }
        }
    }

    private func read(_ span: PrayerScores.Span) async -> PrayerScores {
        let container = context.container, ranges = Excused.ranges
        let t = JourneyPerf.now
        let built = await PrayerScores.load(container: container, ranges: ranges, span: span)
        JourneyPerf.took("scores.load", since: t)
        JourneyStore.shared.scoresBySpan[span] = built
        return built
    }

    private func show(_ next: PrayerScores) {
        // Mid open or close: as it was (its own motion is running).
        guard !busy, !dialing else { data = next; return }
        guard selected != nil else {
            withAnimation(motion(.smooth(duration: 0.4))) { data = next }
            return
        }
        // Open: everything stays and moves to the new span in one go — numbers roll, the ring's dot turns, the chart's
        // columns grow or drain, rows that come or go slide in or out (owner, 2026-10-21: "it just takes everything out goes
        // blank and puts it back in. lets shift or add things nicely"; was: out 0.12, swap, in 0.2).
        withAnimation(motion(.smooth(duration: 0.45))) {
            data = next
            focus = nil
            slotPick = nil
        }
    }

    // MARK: A ⇄ B

    private func motion(_ animation: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : animation }

    /// Waits `seconds` (shorter when Reduce Motion is on).
    private func beat(_ seconds: Double) async { try? await Task.sleep(for: .seconds(reduceMotion ? 0.12 : seconds)) }

    private func open(_ name: String) {
        guard !busy, selected == nil else { return }
        busy = true
        JourneyPerf.began("scores open")
        triggerSomeVibration(type: .light)
        selected = name
        Task { @MainActor in
            // 0 · the tap builds the prayer's page below (hidden) and the bar's ‹: a beat for that frame to land before
            // anything moves (built in the fade's first frame, it was the open's worst gap — 49 ms on the sim).
            try? await Task.sleep(for: .milliseconds(30))
            // 1 · the other rows, the picked row's small chart, the ring's words and the lines fade where they are.
            withAnimation(motion(.easeOut(duration: 0.18))) {
                othersFaded = true
                linesFaded = true
                ringFaded = true
            }
            await beat(0.22)   // fully out before anything swaps
            // 2 · the others fold away; the picked row rises into the top slot. The ring's words swap while they're out.
            withAnimation(motion(.smooth(duration: 0.45))) {
                shown = name
                ringOpen = name
                folded = true
            }
            // 3 · the ring's words come back as the row lands (the ring sat empty ~0.8 s — Frank); the lines under the title
            // once the name and its line have landed over them (in with them, they ran through the line still flying up),
            // then its page under it.
            await beat(0.18)
            withAnimation(motion(.easeOut(duration: 0.25))) { ringFaded = false }
            await beat(0.2)
            withAnimation(motion(.easeOut(duration: 0.25))) { linesFaded = false }
            await beat(0.1)
            withAnimation(motion(.easeOut(duration: 0.3))) { detailShown = true }
            await beat(0.3)
            busy = false
            if let next = pendingSwitch { pendingSwitch = nil; switchTo(next) }
        }
    }

    /// From one open prayer straight to another (owner, 2026-10-17: "I want tapping the fifths to be a quicker move from
    /// prayer to prayer"): ~0.3 s, never through the list. Mid-open, it waits for the open to land; a newer tap replaces an
    /// older one at every step.
    private func switchTo(_ name: String) {
        // MetricsLook: any prayer with data opens, as from all five (Frank's check).
        guard MetricsLook.on ? data.prayers[name] != nil : data.prayers[name]?.prayedScore != nil else { return }
        guard !busy else { pendingSwitch = name; return }
        guard selected != nil, name != selected || swapping else { return }
        swapToken += 1
        let token = swapToken
        triggerSomeVibration(type: .light)
        JourneyPerf.began("scores switch")
        Task { @MainActor in
            withAnimation(motion(.easeOut(duration: 0.12))) {
                swapping = true
                linesFaded = true
                ringFaded = true
                detailShown = false
            }
            await beat(0.13)
            guard token == swapToken else { return }   // a newer tap took over
            focus = nil
            slotPick = nil
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                selected = name
                shown = name
                ringOpen = name
            }
            withAnimation(motion(.easeOut(duration: 0.18))) {
                swapping = false
                linesFaded = false
                ringFaded = false
                detailShown = true
            }
        }
    }

    /// ‹: the way back on the dial, the whole way (ScoresBack).
    private func close() {
        guard !busy, selected != nil, !swapping else { return }
        beginBack()
        runBack(to: 0, how: "button")
    }

    /// The way back starts: the dial at the prayer, its pieces reading it from here.
    private func beginBack() {
        pendingSwitch = nil
        slotPick = nil
        busy = true
        JourneyPerf.began("scores close")
        triggerSomeVibration(type: .light)
        dial.set(.month, 1)
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            focus = nil
            dialing = true
        }
    }

    private func runBack(to target: CGFloat, how: String) {
        let remaining = abs(target - dial.dial)
        guard remaining > 0.001 else { if target == 0 { landBack() } else { stayOpen() }; return }
        let run = JourneyFrameLog.shared.start(target == 0 ? "prayer → scores" : "prayer stays")
        dial.animate(.month, to: target, duration: ScoresBack.duration * (reduceMotion ? 0.4 : 1) * Double(remaining)) {
            JourneyFrameLog.shared.stop(how, run: run)
            if target == 0 { landBack() } else { stayOpen() }
        }
    }

    /// All five: the row's own pieces take over exactly where the flying ones landed (its measured place), the page's state
    /// is all five's, and the dial lets go — one quiet change, nothing moves.
    private func landBack() {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            selected = nil
            shown = nil
            folded = false
            othersFaded = false
            linesFaded = false
            ringFaded = false
            detailShown = false
            dialRingAll = false
            dialing = false
            ringOpen = nil   // folded: nothing unfolds any more (Frank's tidy)
        }
        pendingSwitch = nil   // a fifth tapped on the way back: there's no prayer to switch from now
        busy = false
    }

    /// Let go short of the way back: the prayer as it was.
    private func stayOpen() {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            dialing = false
            dialRingAll = false
        }
        busy = false
        if let next = pendingSwitch { pendingSwitch = nil; switchTo(next) }   // a fifth tapped meanwhile
    }

    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($edgeHeld) { _, held, _ in held = true }
            .onChanged { v in
                if edgeSideways == nil { edgeSideways = abs(v.translation.width) >= abs(v.translation.height) }
                guard edgeSideways == true else { return }
                if dragFrom == nil {
                    guard !busy, selected != nil, !swapping else { return }
                    beginBack()
                    dragFrom = 1
                    JourneyFrameLog.shared.start("prayer → scores (finger)")
                }
                guard let from = dragFrom else { return }
                dial.set(.month, min(max(from - max(v.translation.width, 0) / UIScreen.main.bounds.width, 0), 1))
            }
            .onEnded { v in edgeLetGo(v) }
    }

    /// The finger lifts (or the touch is cancelled — `edgeHeld` back to false with no `onEnded`): on to all five if it went
    /// far or fast enough, else back to the prayer.
    private func edgeLetGo(_ v: DragGesture.Value?) {
        edgeSideways = nil
        guard dragFrom != nil else { return }
        dragFrom = nil
        JourneyFrameLog.shared.stop()
        let w = UIScreen.main.bounds.width
        let goes = v.map { $0.translation.width > w / 4 || $0.predictedEndTranslation.width > w / 2 } ?? (dial.dial < 0.5)
        runBack(to: goes ? 0 : 1, how: v == nil ? "cancelled" : goes ? "let go" : "sprang back")
    }

    // MARK: The ring and its lines

    /// The prayer the ring shows: none once the way back has passed its swap.
    private var ringShown: String? { dialRingAll ? nil : shown }
    private var ringScore: Int? { ringShown.flatMap { data.prayers[$0]?.prayedScore } ?? (ringShown == nil ? data.prayedScore : nil) }

    /// The five prayers on the day page's own ring (owner, 2026-10-17: "make it look like the day ring" — its soft disc,
    /// its band, the dot "that indicates the prayer time relative to … its window"): each fifth in its prayer's average
    /// grade, its dot where that prayer usually lands in its window (the middle of its marks), the score in the middle with
    /// what it is under it. A tap on a fifth is a tap on that prayer's row ("clicking on any one of the fifths is the same
    /// as if we clicked on the list item"); open, its fifth stays and the rest fade, its name over its score.
    private var ring: some View {
        ZStack {
            NeuRaised(shape: Circle(), radius: 9, offset: 4.5)
                .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
            if MetricsLook.on {
                // The fifths at your usual places; a prayer open, its fifth unfolded into its window (YourPrayersRing).
                // A new span's dots turn to their new places.
                YourPrayersRing(usual: DayRing.order.map { data.prayers[$0]?.usualShare },
                                open: (shown ?? selected ?? ringOpen).flatMap { DayRing.order.firstIndex(of: $0) },   // from the tap: its fifth stays
                                unfolded: ringShown != nil, othersShown: ringShown == nil && !ringFaded,
                                dial: backDial, onPick: pickFifth)
                ringWords
                    .modifier(ScoresBackFade(part: .ringWords, rest: ringFaded ? 0 : 1, dial: backDial))
                    .allowsHitTesting(false)
            } else {
            DayRing(day: ringPrayers, picked: ringShown.flatMap { DayRing.order.firstIndex(of: $0) }, onPick: pickFifth)
            .id(data.span)   // a new span's fifths cross-fade in
            .transition(.opacity)
            VStack(spacing: 1) {
                Text(ringScore.map { "\($0)" } ?? "–")
                    .font(.system(size: MetricsLook.on ? 46 : 58, weight: .thin, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    // Rolls to a new span's number; the prayer's own swaps while the words are faded out.
                    .contentTransition(.numericText(value: Double(ringScore ?? 0)))
                    .modifier(ScoresBackFade(part: .ringWords, rest: ringFaded ? 0 : 1, dial: backDial))
                // What the number is (owner: "a little subtitle … saying like average lifetime score"); sized for the ring
                // drawn at 70 % beside the title.
                Text(data.ringLabel)
                    .contentTransition(.opacity)
                    .font(.system(size: 15, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .modifier(ScoresBackFade(part: .ringWords, rest: ringFaded ? 0 : 1, dial: backDial))
            }
            .allowsHitTesting(false)
            }
        }
        .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
    }

    /// A tap on a fifth is a tap on that prayer's row.
    private func pickFifth(_ i: Int) {
        let name = DayRing.order[i]
        guard MetricsLook.on ? data.prayers[name] != nil : data.prayers[name]?.prayedScore != nil else { return }
        if selected == nil { open(name) } else if name == selected && !swapping { close() } else { switchTo(name) }
    }

    /// The ring's middle: what the dots are; a prayer open, how far into its window you usually pray it over the span
    /// ("say the % of window we mark at on avg for the 7/30/all period"). The words swap as the day page's centre does.
    @ViewBuilder private var ringWords: some View {
        Group {
            if let s = ringShown {
                if let u = data.prayers[s]?.usualShare {
                    ringPair("\(Int((min(max(u, 0), 1) * 100).rounded()))%", "into its window,\nusually")
                } else {
                    ringPair("–", "too few times\nto say yet")
                }
            } else {
                // No number (owner, 2026-10-20): what the dots are.
                Text("when you\nusually pray")
                    .font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .id(ringShown ?? "")
        .transition(CircleMotion.dayPickSwap)
    }

    private func ringPair(_ big: String, _ small: String) -> some View {
        VStack(spacing: 2) {
            Text(big).font(.system(size: 50, weight: .thin, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())   // a new span's % rolls
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(small).font(.system(size: 16, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 160)
    }

    /// Each prayer as the day ring draws a day's: its average as the score, its usual place in its window (the middle of
    /// its marks, 0 the start … 1 the end, a Qaza past it) as when it was marked, on a stand-in window.
    private var ringPrayers: [DayPrayer] {
        let start = Date(timeIntervalSinceReferenceDate: 0), length: TimeInterval = 1_000
        return DayRing.order.map { name in
            let p = data.prayers[name]
            let sorted = (p?.positions ?? []).sorted()
            let middle = sorted.isEmpty ? nil : sorted[sorted.count / 2]
            let score = p?.prayedScore.map { Double($0) / 100 }
            return DayPrayer(name: name, start: start, end: start.addingTimeInterval(length),
                             markedAt: score == nil ? nil : start.addingTimeInterval(length * min(middle ?? 0.5, 1)),
                             score: score)
        }
    }

    /// Two lines under the ring, on both pages: what it covers / when you usually pray it, then the 7 / 30 day trend.
    private var lines: some View {
        usualLines.opacity(linesFaded ? 0 : 1)
    }

    /// "16–33 min after it starts · 41 prayers (9%)" — the minutes first, the count and share last, no grade word (its bar
    /// says it; owner, 2026-10-18: "it doesn't need to say the score … 16 to 33 minutes after it starts should come first. And
    /// then we should end it with the 41 prayers, 9%"), or "Made up after it ended · …".
    private func slotLine(_ p: PrayerScores.Prayer, _ k: Int) -> String {
        let (counts, qaza) = PrayerScoresChart.slotCounts(p)
        let n = k == PrayerScoresChart.qazaSlot ? qaza : (counts.indices.contains(k) ? counts[k] : 0)
        let total = max(1, p.positions.count)
        let tail = "\(n) prayer\(n == 1 ? "" : "s") (\(Int((Double(n) / Double(total) * 100).rounded()))%)"
        if k == PrayerScoresChart.qazaSlot { return "Made up after it ended · " + tail }
        guard let w = p.window, w > 0 else { return tail }
        let minutes = w / 60
        let a = Int((Double(k) / Double(PrayerScoresChart.slots) * minutes).rounded())
        let b = Int((Double(k + 1) / Double(PrayerScoresChart.slots) * minutes).rounded())
        return "\(Self.span(a, b)) after it starts · \(tail)"
    }

    /// "10–20 min", "1 h 10–1 h 30 min".
    private static func span(_ a: Int, _ b: Int) -> String {
        func f(_ m: Int) -> String { m < 60 ? "\(m)" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)" }
        return "\(f(a))–\(f(b)) min"
    }

    /// The open slot under a point on the chart (nil: off its slots, or an empty one).
    private func slot(at x: CGFloat, _ p: PrayerScores.Prayer) -> Int? {
        guard chartWidth > 0 else { return nil }
        let (counts, qaza) = PrayerScoresChart.slotCounts(p)
        let x0: CGFloat = 2, end = chartWidth * 0.74, after = chartWidth * 0.86
        if x >= x0, x < end {
            let k = min(PrayerScoresChart.slots - 1, Int((x - x0) / ((end - x0) / CGFloat(PrayerScoresChart.slots))))
            return counts[k] > 0 ? k : nil
        }
        if x >= end, x <= after + 12, qaza > 0 { return PrayerScoresChart.qazaSlot }
        return nil
    }

    private var usualLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let s = shown, let p = data.prayers[s] {
                Text(MetricsLook.on ? p.usualShare.map { PrayerScores.placeLine($0, today: recent.byName[s]?.window?.duration) }
                        ?? "Not enough yet to say when you usually pray it."
                     : p.usual.map { $0.replacingOccurrences(of: "Usually", with: "Lately, usually") }
                     ?? "Not enough yet to say when you usually pray it.")
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .contentTransition(.opacity)
            } else {
                Text("\(data.prayed.formatted()) of \(data.due.formatted()) prayed\(sinceWords.map { " · \($0)" } ?? "")")
                    .font(.system(size: 13.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            // A score's trend (↑3) is a 0–100 number: gone with the rethink (MetricsLook).
            if !MetricsLook.on { trendLine(shown ?? "all") }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "since Jul 2026", or the span's own words; "since Oct 19" when the fresh start cuts into the span. The date lives
    /// here, not on the chip (owner, 2026-10-19: "the span chip should be kept to "all time" and "since" should stay on
    /// the text line under the histogram").
    private var sinceWords: String? {
        if let fresh = data.countsFrom { return "since \(fresh.formatted(.dateTime.month(.abbreviated).day()))" }
        return switch data.span {
        case .all: data.since.map { "since \($0.formatted(.dateTime.month(.abbreviated).year()))" }
        case .days30: "in the last 30 days"
        case .days7: "in the last 7 days"
        }
    }

    /// "Last 7 days ↑3 · last 30 days steady" as one text, so it wraps beside the ring.
    @ViewBuilder private func trendLine(_ key: String) -> some View {
        // All time: the last week and month; a span: against the same span just before it.
        let parts: [(String, PrayerScores.Trend)] = switch data.span {
        case .all: [("Last 7 days", data.trend7[key]), ("last 30 days", data.trend30[key])].compactMap { label, t in t.map { (label, $0) } }
        case .days30: [("Vs the 30 days before", data.trend30[key])].compactMap { label, t in t.map { (label, $0) } }
        case .days7: [("Vs the week before", data.trend7[key])].compactMap { label, t in t.map { (label, $0) } }
        }
        if !parts.isEmpty {
            parts.enumerated().reduce(Text("")) { line, item in
                let (i, part) = item
                return line + Text(i > 0 ? " · " : "").foregroundStyle(.secondary)
                    + Text("\(part.0) ").foregroundStyle(.secondary) + Text(Self.change(part.1.change)).foregroundStyle(.primary)
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
            .contentTransition(.opacity)
        }
    }

    static func change(_ d: Int) -> String { abs(d) < 3 ? "steady" : d > 0 ? "↑\(d)" : "↓\(-d)" }

    /// The page's own title, as Journey's other pages have theirs ("To make up" over its grey line) — the one-liner its
    /// grey line — with the ring beside it, sharing the top (owner, 2026-10-17: "make the title of the page look more like
    /// the titles of our other journey pages … shift the ring to the side a little bit … so the main title, header, and its
    /// secondary line share kind of the same area that the main ring shares").
    private var header: some View {
        let scale: CGFloat = 0.7
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Open, the prayer's name is the title and its lines are the grey ones (owner, 2026-10-17: "instead of it
                // just saying prayer scores, like when a prayer is tapped, it instead says that prayer's name … same for
                // its secondary lines, we'll move that in there underneath it").
                // The picked prayer's name and score line, from the moment it's tapped: laid over its row's own text
                // (same size, same place) until the others fold, then rising here as they do, growing to the title —
                // and back down on close. Its "% prayed" stays ("We also lose like the 98% prayed stat … We should keep
                // that").
                ZStack(alignment: .leading) {
                    Text(pageTitle)
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .modifier(ScoresBackFade(part: .inLast, rest: selected == nil && !linesFaded ? 1 : 0, dial: backDial))
                    if let name = selected {
                        // Its symbol flies with it and stays beside the name ("it loses the SF. keep the sf").
                        HStack(spacing: folded ? 10 : 12) {
                            Image(systemName: prayerIcon(for: name))
                                .modifier(ScoresHeroTint(folded: folded, dial: backDial))
                                .modifier(ScoresHeroPart(part: .icon, folded: folded, dial: backDial, frames: heroFrames))
                                .matchedGeometryEffect(id: "icon", in: hero, properties: .position, isSource: folded)
                            Text(name)
                                .modifier(ScoresHeroPart(part: .name, folded: folded, dial: backDial, frames: heroFrames))
                                .lineLimit(1)
                                .matchedGeometryEffect(id: "name", in: hero, properties: .position, anchor: .leading, isSource: folded)
                        }
                        .opacity(swapping ? 0 : 1)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if let s = data.sentence {
                        Text(s.line)
                            .contentTransition(.opacity)
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            // Fades with the rows, both ways.
                            .modifier(ScoresBackFade(part: .inLast, rest: othersFaded || linesFaded ? 0 : 1, dial: backDial))
                    }
                    if let name = selected {
                        // No score here: the ring has it, large (owner, 2026-10-17: "get rid of the score here … because we
                        // already show it in the ring").
                        // It starts as the row's own line ("84 · 49% prayed"): the score part fades and folds away as it rises,
                        // and grows back as it sinks — swapped at the tap, the line jumped from one text to the other.
                        HStack(spacing: 0) {
                            ScoresScorePart(text: scorePart(name), folded: folded, dial: backDial)
                            // No score: the row's "Not enough yet" flies as it is and turns to its "% prayed" once landed
                            // (with the lines), and back before it sinks — never mid-flight.
                            Text(scorePart(name).isEmpty && (linesFaded || !folded) ? statLine(name) : prayedLine(name))
                                .contentTransition(.numericText())
                        }
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .modifier(ScoresHeroPart(part: .stat, folded: folded, dial: backDial, frames: heroFrames))
                            .matchedGeometryEffect(id: "stat", in: hero, properties: .position, anchor: .leading, isSource: folded)
                            .opacity(swapping ? 0 : 1)
                    }
                }
                if shown != nil {
                    // On the way back they fold as the rows unfold (the header grows back to all five's).
                    lines.modifier(ScoresBackFade(part: .outFirst, rest: 1, dial: backDial))
                        .modifier(ScoresBackCollapse(rest: 1, folds: true, dial: backDial))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // With MetricsLook one ring both ways (owner, 2026-10-20: "transition the fifth to its ring"): only its middle fades.
            ring.scaleEffect(scale)
                .frame(width: CircleMotion.dayDiscDiameter * scale, height: CircleMotion.dayDiscDiameter * scale)
        }
        .padding(.leading, 4)
    }

    /// All time | 30 days | 7 days, under the header (owner: "we have a lot of space where the header is"); the choice
    /// stays.
    private var spanSwitch: some View {
        // Always "All time": after a fresh start the line under the chart says since when (sinceWords; owner,
        // 2026-10-19 — it read "Since Oct 19" here from 2026-10-18).
        JourneySwitch(options: PrayerScores.Span.allCases.map { ($0.title, $0.rawValue) }, selection: $spanRaw)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    /// "98% prayed" (an open prayer's line under its name).
    private func prayedLine(_ name: String) -> String {
        if MetricsLook.on { return recentLine(name) }
        guard let p = data.prayers[name], p.due > 0 else { return " " }
        return "\(Int((Double(p.prayed) / Double(p.due) * 100).rounded()))% prayed"
    }

    /// "97 · " (a row's line before its "% prayed"), or nothing without a score.
    private func scorePart(_ name: String) -> String {
        if MetricsLook.on { return "" }
        return data.prayers[name]?.prayedScore.map { "\($0) · " } ?? ""
    }

    /// "in its time 224 of 239" over the span the chips pick, as the histogram is (MetricsLook: a row's line, and the open
    /// prayer's under its name). Was the last 7 days whatever the chip said (owner, 2026-10-20, on "3 of 5": "I don't even
    /// know if that's the metric we should even show").
    private func recentLine(_ name: String) -> String {
        guard let p = data.prayers[name], p.due > 0 else { return "Not enough yet" }
        return "in its window \(p.inTime) of \(p.due)"
    }

    /// "97 · 98% prayed" (a row's line).
    private func statLine(_ name: String) -> String {
        if MetricsLook.on { return recentLine(name) }
        guard let p = data.prayers[name] else { return " " }
        return p.prayedScore.map { "\($0) · \(Int((Double(p.prayed) / Double(max(1, p.due)) * 100).rounded()))% prayed" } ?? "Not enough yet"
    }

    // MARK: The rows

    private var rows: some View {
        let per = PrayerScoresChart.perDot(data.ranked.compactMap { data.prayers[$0] }, big: false)
        return VStack(spacing: 0) {
            ForEach(data.ranked, id: \.self) { name in
                let isPicked = selected == name
                let hidden = selected != nil && !isPicked
                // Folded, the picked row goes too: its name is the title now (owner: "we don't need to show it twice").
                row(name, per: per, picked: isPicked)
                    .modifier(ScoresBackHeight(rest: folded && (hidden || isPicked) ? 0 : Self.rowHeight, full: Self.rowHeight,
                                               dial: hidden || isPicked ? backDial : nil))
                    .clipped()
                    .modifier(ScoresBackFade(part: hidden ? .inLast : .shown,
                                             rest: (hidden && othersFaded) || (isPicked && folded) ? 0 : 1, dial: backDial))
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
                    .opacity(picked ? 0 : 1)   // the header's copy is it while picked (it flies up beside the name and back)
                    // On the way back's dial the copy flies by measured places (ScoresHeroPart): the row's own stays put.
                    .matchedGeometryEffect(id: picked && !dialing ? "icon" : "icon-\(name)", in: hero, properties: .position, isSource: !folded)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if picked { heroFrames.row[.icon] = $0 } }
                VStack(alignment: .leading, spacing: 2) {
                    // One weight and one colour always: changing either as the move starts dropped the name for the
                    // whole rise (seen frame by frame, 2026-10-16).
                    Text(name).font(.system(size: 16, weight: .light, design: .rounded))
                        .opacity(picked ? 0 : 1)   // the header's copy is it while picked (it flies up and back)
                        .matchedGeometryEffect(id: picked && !dialing ? "name" : "name-\(name)", in: hero, properties: .position,
                                               anchor: .leading, isSource: !folded)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if picked { heroFrames.row[.name] = $0 } }
                    Text(statLine(name))
                        .contentTransition(.numericText())
                        .font(.system(size: 12.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .opacity(picked ? 0 : 1)
                        .matchedGeometryEffect(id: picked && !dialing ? "stat" : "stat-\(name)", in: hero, properties: .position,
                                               anchor: .leading, isSource: !folded)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if picked { heroFrames.row[.stat] = $0 } }
                }
                // Wider with the rethink's count line ("in its time 224 of 329" wrapped at 104 — Zoe's sim check).
                .frame(width: MetricsLook.on ? 150 : 104, alignment: .leading)
                Group {
                    if let p, !p.positions.isEmpty {
                        PrayerScoresChart(prayer: p, per: per, big: false, focus: nil)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 46)
                .modifier(ScoresBackFade(part: .inLast, rest: picked && (othersFaded || detailShown) ? 0 : 1, dial: picked ? backDial : nil))
                Image(systemName: picked ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                    .modifier(ScoresBackFade(part: .inLast, rest: picked && folded ? 0 : 1, dial: picked ? backDial : nil))
            }
            .frame(height: Self.rowHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    .modifier(ScoresBackFade(part: .inLast, rest: picked && folded ? 0 : 1, dial: picked ? backDial : nil))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(picked ? "Back to all five prayers" : MetricsLook.on ? "Opens \(name)" : "Opens \(name)'s scores")
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
                            .contentTransition(.numericText())
                            .font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                    let per = PrayerScoresChart.perDot([p], big: true)
                    PrayerScoresChart(prayer: p, per: per, big: true, focus: focus, slot: slotPick)
                        // As tall as its own tallest column, up to 150: short columns left an empty band under "1 dot =
                        // 1 prayer" (owner, 2026-10-17: "a lot of empty space between the histogram and the priors label").
                        .frame(height: PrayerScoresChart.fittedHeight(p, per: per, big: true))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
                        // As the card's tiles: a tap picks the slot under it (again, or off the slots, lets it go); a finger
                        // resting picks and then moves across slots, a soft tick each. A quick drag still scrolls the page.
                        .contentShape(Rectangle())
                        .onTapGesture { pt in
                            let k = slot(at: pt.x, p)
                            triggerSomeVibration(type: .light)
                            withAnimation(.easeOut(duration: 0.15)) {
                                slotPick = k == slotPick ? nil : k
                                if slotPick != nil { focus = nil }
                            }
                        }
                        .gesture(JourneyHoldPick(hold: JourneyHomeCard.holdTime) { state, pt, _ in
                            guard state == .began || state == .changed, let k = slot(at: pt.x, p), k != slotPick else { return }
                            triggerSomeVibration(type: state == .began ? .medium : .soft)
                            withAnimation(.easeOut(duration: 0.12)) { slotPick = k; focus = nil }
                        })
                }
                .stagger(detailShown, 0)
                chartLine(p).padding(.top, 10).stagger(detailShown, 1)
                chips(p).padding(.top, 12).stagger(detailShown, 1)
                VStack(spacing: 0) {
                    if let i = data.insight(s) {
                        listRow(symbol: i.symbol, title: i.line, sub: i.sub, door: false) {}
                            .transition(.identity)
                    }
                    if p.owed > 0 {
                        listRow(symbol: "clock", title: "\(p.owed) to make up", sub: "Unmarked on days you used shukr", door: true) { showMakeUp = true }
                            .transition(.identity)
                    }
                    if p.photos > 0 {
                        listRow(symbol: "photo.on.rectangle", title: p.photos == 1 ? "1 photo" : "\(p.photos) photos",
                                sub: p.notes > 0 ? "\(p.notes) with a note" : "Your moments", door: true) { showMoments = true }
                            .transition(.identity)
                    }
                    if !p.pins.isEmpty {
                        listRow(symbol: "mappin.and.ellipse", title: "Where you pray it",
                                sub: p.topMasjid.map { "Most at a masjid: \($0.name) (\($0.count))" } ?? "\(p.pins.count) with a place",
                                door: true) { showMap = true }
                            .transition(.identity)
                    }
                }
                .padding(.top, 18)
                .stagger(detailShown, 2)
            }
            .padding(.top, 8)
        }
    }

    /// Under the chart: what it holds, a chip's grade, or the picked slot's answer in the same place — the old line fades
    /// out and the answer in (owner, 2026-10-18: "that text underneath the histogram … I think that area can be the same
    /// place … shows that histogram selection text. Like we fade out the other one and put this one in"). The line itself
    /// leaves the missed count to the To make up row ("get rid of amount missed in the line and only keep it as the to make
    /// up list item").
    private func chartLine(_ p: PrayerScores.Prayer) -> some View {
        ZStack {
            Group {
                if let f = focus {
                    // "Closing: 36 of 79 prayed" ("36 Closing of 79 prayed" didn't read once the words were Middle / Closing).
                    Text("\(f.word): \(p.grades[f] ?? 0)").fontWeight(.regular)
                    + Text(" of \(p.prayed) prayed").foregroundStyle(.secondary)
                } else {
                    Text("\(p.prayed) prayed").foregroundStyle(.primary)
                    + Text(sinceWords.map { " \($0)" } ?? "").foregroundStyle(.secondary)
                }
            }
            .contentTransition(.identity)   // rides the chart's height: a roll there ghosted (owner, 2026-10-21)
            .opacity(slotPick == nil ? 1 : 0)
            if let k = slotPick {
                Text(slotLine(p, k))
                    .contentTransition(.identity)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .light, design: .rounded))
        .lineLimit(1).minimumScaleFactor(0.75)
    }

    private func chips(_ p: PrayerScores.Prayer) -> some View {
        HStack(spacing: 8) {
            ForEach(PrayerScores.Grade.allCases) { g in
                let on = focus == g
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.25)) { focus = on ? nil : g; slotPick = nil }
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(g.color.opacity(0.75)).frame(width: 9, height: 9)
                            // Switches at once: rolled while the chart's growth slid the chips, the digits ghosted (owner,
                            // 2026-10-21).
                            Text("\(p.grades[g] ?? 0)").font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit()
                                .contentTransition(.identity)
                        }
                        Text(g.word).font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.secondary)
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
                .accessibilityLabel("\(g.word): \(p.grades[g] ?? 0)")
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
                    // A new span's words switch at once (the row still rides the chart's height): crossfaded while sliding
                    // they ghosted (owner, 2026-10-21: "The bottom list items in that page, we don't need to animate those …
                    // I care more about the histogram than anything else").
                    Text(title).font(.system(size: 16, weight: .light, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.identity)
                    Text(sub).font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .contentTransition(.identity)
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
            .contentTransition(.numericText())
            .font(.system(size: 11.5, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 18)
            .modifier(ScoresBackFade(part: .inLast, rest: othersFaded ? 0 : 1, dial: backDial))
            .modifier(ScoresBackCollapse(rest: folded ? 0 : 1, folds: false, dial: backDial))
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
struct PrayerScoresChart: View, Animatable {
    let prayer: PrayerScores.Prayer
    let per: Int
    let big: Bool
    let focus: PrayerScores.Grade?
    /// One picked slot (0…13, or `qazaSlot`): its dots and its stretch of the bar stay, the rest fade.
    var slot: Int? = nil
    /// Each slot's dots (the window's 14, then Qaza's), animatable: a new span's columns grow or drain a dot at a time, the
    /// one in between fading (owner, 2026-10-21, on the span switch: "it just takes everything out goes blank and puts it
    /// back in. lets shift or add things nicely").
    var dots: DotColumns
    var animatableData: DotColumns {
        get { dots }
        set { dots = newValue }
    }

    init(prayer: PrayerScores.Prayer, per: Int, big: Bool, focus: PrayerScores.Grade?, slot: Int? = nil) {
        self.prayer = prayer
        self.per = per
        self.big = big
        self.focus = focus
        self.slot = slot
        let (counts, qaza) = Self.slotCounts(prayer)
        dots = DotColumns(v: (counts + [qaza]).map { n in n == 0 ? 0 : Double(max(1, Int((Double(n) / Double(per)).rounded()))) })
    }

    typealias DotColumns = AnimatableNumbers

    static let slots = 14
    static let qazaSlot = slots

    /// Each window slot's count of marks, and the Qaza block's.
    static func slotCounts(_ prayer: PrayerScores.Prayer) -> (counts: [Int], qaza: Int) {
        var counts = Array(repeating: 0, count: slots)
        var qaza = 0
        for v in prayer.positions {
            if v > 1 { qaza += 1 } else { counts[min(slots - 1, max(0, Int(v * Double(slots))))] += 1 }
        }
        return (counts, qaza)
    }

    /// The grade a place in the window sits in (its colour bar).
    static func zone(_ v: Double, _ prayer: PrayerScores.Prayer) -> PrayerScores.Grade {
        v < prayer.bands.perfect ? .perfect : v < prayer.bands.late ? .onTime : .late
    }

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

    /// The height that holds this prayer's tallest column of dots (or its Qaza block) and the bar and labels under it —
    /// no more than `cap`. Measured on the same nominal width perDot uses; a wider screen only leaves a dot's room spare.
    static func fittedHeight(_ prayer: PrayerScores.Prayer, per: Int, big: Bool, cap: CGFloat = 150) -> CGFloat {
        let m = Metrics(big: big)
        let w: CGFloat = big ? 354 : 190
        let slotW = (w * 0.74 - 2) / CGFloat(slots)
        let wide = max(1, Int((slotW - 1) / m.step))
        let tall = max(1, Int((cap - m.labels - m.bandH - 6) / m.step))
        var counts = Array(repeating: 0, count: slots)
        var qaza = 0
        for v in prayer.positions {
            if v > 1 { qaza += 1 } else { counts[min(slots - 1, max(0, Int(v * Double(slots))))] += 1 }
        }
        let column = counts.map { n -> Int in
            guard n > 0 else { return 0 }
            let dots = min(wide * tall, max(1, Int((Double(n) / Double(per)).rounded())))
            return (dots + wide - 1) / wide
        }.max() ?? 0
        let qazaRows = qaza > 0 ? min(tall, max(1, Int((Double(qaza) / Double(per)).rounded()))) : 0
        let rows = max(column, qazaRows, 1)
        return min(cap, CGFloat(rows) * m.step + m.labels + m.bandH + 10)
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
            func dim(slot k: Int, _ g: PrayerScores.Grade) -> Double { slot.map { $0 == k ? 1 : 0.15 } ?? dim(g) }

            // The window's colour bar: Perfect · Middle · Closing, then a dashed stretch for after the end.
            let xPerfect = x0 + CGFloat(prayer.bands.perfect) * (end - x0), xLate = x0 + CGFloat(prayer.bands.late) * (end - x0)
            let barY = base + 2
            func bar(_ from: CGFloat, _ to: CGFloat, _ g: PrayerScores.Grade, _ base: Double) {
                let rect = CGRect(x: from, y: barY, width: max(0, to - from), height: m.bandH)
                let strength = slot != nil ? 0.35 : focus == nil ? 1 : focus == g ? 1.8 : 0.35
                ctx.fill(Path(roundedRect: rect, cornerRadius: m.bandH / 2), with: .color(g.color.opacity(base * strength)))
            }
            bar(x0, xPerfect, .perfect, 0.38)
            bar(xPerfect, xLate, .onTime, 0.42)
            bar(xLate, end, .late, 0.32)
            // A picked slot's own stretch of the bar, in its grade's colour, full.
            if let k = slot, k < Self.slots {
                let g = zone((Double(k) + 0.5) / Double(Self.slots))
                let rect = CGRect(x: x0 + CGFloat(k) * (end - x0) / CGFloat(Self.slots), y: barY,
                                  width: (end - x0) / CGFloat(Self.slots), height: m.bandH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: m.bandH / 2), with: .color(g.color.opacity(0.75)))
            }
            var dash = Path()
            dash.move(to: CGPoint(x: end + 4, y: barY + m.bandH / 2))
            dash.addLine(to: CGPoint(x: after + (big ? 8 : 4), y: barY + m.bandH / 2))
            ctx.stroke(dash, with: .color(Color.secondary.opacity(focus == .qaza || slot == Self.qazaSlot ? 0.7 : slot != nil ? 0.15 : 0.35)),
                       style: StrokeStyle(lineWidth: big ? 2 : 1.4, dash: [2, 4]))

            // Blocks inside the window: whole dots, and the one a column is growing into (or draining) at its share.
            let dotOpacity = big ? 0.8 : 0.72
            func column(_ d: Double, cap: Int, _ at: (Int) -> CGPoint, _ opacity: Double) {
                let whole = min(cap, Int(d)), part = whole < cap ? d - Double(Int(d)) : 0
                for i in 0..<(whole + (part > 0.02 ? 1 : 0)) {
                    let c = at(i)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - m.r, y: c.y - m.r, width: m.r * 2, height: m.r * 2)),
                             with: .color(ink.opacity(opacity * (i < whole ? 1 : part))))
                }
            }
            for k in 0..<Self.slots where dots[k] > 0.02 {
                let left = x0 + CGFloat(k) * slotW + (slotW - CGFloat(wide) * m.step) / 2 + m.r
                let g = zone((Double(k) + 0.5) / Double(Self.slots))
                column(dots[k], cap: wide * tall,
                       { i in CGPoint(x: left + CGFloat(i % wide) * m.step, y: base - m.r - CGFloat(i / wide) * m.step) },
                       dotOpacity * dim(slot: k, g))
            }
            // Qaza: its own block past the end, filled bottom-up then rightward.
            if dots[Self.qazaSlot] > 0.02 {
                let qx = end + m.r * 2 + 2
                column(dots[Self.qazaSlot], cap: .max,
                       { i in CGPoint(x: qx + CGFloat(i / tall) * m.step, y: base - m.r - CGFloat(i % tall) * m.step) },
                       dotOpacity * (slot.map { $0 == Self.qazaSlot ? 1 : 0.15 } ?? (focus == nil ? 0.55 : focus == .qaza ? 1 : 0.15)))
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
        let g = PrayerScores.Grade.allCases.map { "\($0.word): \(prayer.grades[$0] ?? 0)" }.joined(separator: ", ")
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


/// Its one child at its own size, as wide as `open` of that (1 all, 0 none): the open prayer's score part folding out of
/// its line as it rises (an animatable layout — a frame can't animate between its own width and zero).
private struct PrayerScoresCollapse: Layout {
    var open: CGFloat
    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: s.width * max(open, 0), height: s.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .unspecified)
    }
}

/// A font size that animates (a plain `.font` jumps between sizes): the picked prayer's name and line growing into the
/// header as they rise.
private struct PrayerScoresHeroFont: ViewModifier, Animatable {
    var size: CGFloat
    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .light, design: .rounded))
    }
}

// MARK: - The way back on a dial

/// From one prayer back to all five, on one dial (1 the prayer … 0 all five) — so a finger on the left edge can hold it
/// anywhere, as Journey's calendar does (owner, 2026-10-18: "fix the back swipes so that it feels fluid, like how we did in
/// the Journey page"). ‹ runs the same dial. Its stretches, by how far back (c = 1 − dial): the prayer's own page, lines and
/// ring words go first; the rows unfold and the name, symbol and line fly down to their row; the other rows, the title and
/// the sentence come in last. The pieces read the dial themselves (the leaf modifiers below), never the page.
enum ScoresBack {
    static func fadeOut(_ c: CGFloat) -> Double { Double(1 - JourneyMotion.out(JourneyMotion.seg(c, 0, 0.2))) }
    static func unfold(_ c: CGFloat) -> CGFloat { JourneyMotion.io(JourneyMotion.seg(c, 0.15, 0.75)) }
    static func fadeIn(_ c: CGFloat) -> Double { Double(JourneyMotion.out(JourneyMotion.seg(c, 0.7, 1))) }
    /// The ring's number and label: out with the page, back with all five (the number changes while they're out).
    static func ringWords(_ c: CGFloat) -> Double { max(fadeOut(c), fadeIn(c)) }
    /// Where the ring's number turns to all five's.
    static let ringSwap: CGFloat = 0.45
    /// A full way back on ‹ (a part of it, its share).
    static let duration = 0.8
}

/// Where the flying name, symbol and line are (the header's copy, before its offset) and where they land (the picked row's
/// own, laid out under it) — measured as they're laid out, never fixed positions, so a new layout of the page carries the
/// flight. Not observed: written every layout, read by the copy's offset.
@MainActor final class ScoresHeroFrames {
    enum Part: Hashable { case icon, name, stat }
    var copy: [Part: CGRect] = [:]
    var row: [Part: CGRect] = [:]
    /// The offset the copy was last drawn with: its measured place includes it (an offset moves what a view inside it
    /// measures), so it's taken off to get the copy's own place — else each frame chased the last one and landed short.
    var applied: [Part: CGSize] = [:]
}

/// A piece's opacity on the way back (`rest` while no dial runs).
private struct ScoresBackFade: ViewModifier {
    enum Part { case outFirst, inLast, ringWords, shown }
    let part: Part
    let rest: Double
    let dial: JourneyMonthDial?
    func body(content: Content) -> some View {
        let o: Double = dial.map { d in
            let c = 1 - d.dial
            return switch part {
            case .outFirst: ScoresBack.fadeOut(c)
            case .inLast: ScoresBack.fadeIn(c)
            case .ringWords: ScoresBack.ringWords(c)
            case .shown: 1
            }
        } ?? rest
        content.opacity(o)
    }
}

/// A folded row's height (and the rows' top room) as the dial unfolds them.
private struct ScoresBackHeight: ViewModifier {
    let rest: CGFloat
    let full: CGFloat
    let dial: JourneyMonthDial?
    func body(content: Content) -> some View {
        content.frame(height: dial.map { full * ScoresBack.unfold(1 - $0.dial) } ?? rest, alignment: .top)
    }
}
private struct ScoresBackRowsTop: ViewModifier {
    let folded: Bool
    let dial: JourneyMonthDial?
    func body(content: Content) -> some View {
        content.padding(.top, dial.map { JourneyMotion.lerp(10, 18, ScoresBack.unfold(1 - $0.dial)) } ?? (folded ? 10 : 18))
    }
}

/// A height that folds away (`open` 0 … 1): the open prayer's lines as the rows come back, the footnote under them.
private struct ScoresVCollapse: Layout {
    var open: CGFloat
    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: s.width, height: s.height * max(open, 0))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}
private struct ScoresBackCollapse: ViewModifier {
    /// Open at rest (1) or folded (0).
    let rest: CGFloat
    /// On the dial: the lines fold as the rows unfold (true), the footnote unfolds with them (false).
    let folds: Bool
    let dial: JourneyMonthDial?
    func body(content: Content) -> some View {
        let open = dial.map { d in let u = ScoresBack.unfold(1 - d.dial); return folds ? 1 - u : u } ?? rest
        ScoresVCollapse(open: open) { content }.clipped()
    }
}

/// One of the flying three (the header's copy of the picked row's symbol, name and line): its size grows into the header as
/// the rows fold (the open, on its animation) and, on the dial, shrinks and flies down to its row by the measured places;
/// the symbol turns from the header's white to the row's grey so the row's own takes over unseen (owner, 2026-10-18: "the
/// SF symbol, when it goes down, just flickers" — it changed colour and dropped 10 pt in one frame at the hand-off).
private struct ScoresHeroPart: ViewModifier {
    let part: ScoresHeroFrames.Part
    let folded: Bool
    let dial: JourneyMonthDial?
    let frames: ScoresHeroFrames

    private var sizes: (big: CGFloat, small: CGFloat) {
        switch part { case .icon: (28, 19); case .name: (34, 16); case .stat: (15, 12.5) }
    }

    func body(content: Content) -> some View {
        // 0 in the header … 1 on its row.
        let q: CGFloat = dial.map { ScoresBack.unfold(1 - $0.dial) } ?? (folded ? 0 : 1)
        let o = dial == nil ? CGSize.zero : offset(q)
        let _ = frames.applied[part] = o
        content
            .modifier(PrayerScoresHeroFont(size: JourneyMotion.lerp(sizes.big, sizes.small, q)))
            .frame(width: part == .icon ? JourneyMotion.lerp(34, 26, q) : nil)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                let a = frames.applied[part] ?? .zero
                frames.copy[part] = r.offsetBy(dx: -a.width, dy: -a.height)
            }
            .offset(o)
    }

    /// From its own place to its row's, by `q` (the symbol by its centre, the words by their leading edge).
    private func offset(_ q: CGFloat) -> CGSize {
        guard let a = frames.copy[part], let b = frames.row[part] else { return .zero }
        let dx = part == .icon ? b.midX - a.midX : b.minX - a.minX
        return CGSize(width: dx * q, height: (b.midY - a.midY) * q)
    }
}

/// The header symbol's colour: the row's grey at the row, white in the header — as a cross-fade, which animates with the
/// open and follows the dial.
private struct ScoresHeroTint: ViewModifier {
    let folded: Bool
    let dial: JourneyMonthDial?
    func body(content: Content) -> some View {
        let white: Double = dial.map { Double(1 - ScoresBack.unfold(1 - $0.dial)) } ?? (folded ? 1 : 0)
        ZStack {
            content.foregroundStyle(.secondary).opacity(1 - white)
            content.foregroundStyle(.primary).opacity(white)
        }
    }
}

/// Reports the moment the dial passes the ring's number swap (once each way), without the page reading the dial.
private struct ScoresBackWatch: View {
    let dial: JourneyMonthDial
    let onAll: (Bool) -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: 1 - dial.dial >= ScoresBack.ringSwap, initial: true) { _, all in onAll(all) }
    }
}

/// The open prayer's score at the front of its line ("84 · "), folding away as the line rises into the header and back as it
/// sinks (on the open's animation, or the dial).
private struct ScoresScorePart: View {
    let text: String
    let folded: Bool
    let dial: JourneyMonthDial?
    var body: some View {
        let q: CGFloat = dial.map { ScoresBack.unfold(1 - $0.dial) } ?? (folded ? 0 : 1)
        // Gone before the room it leaves has halved: fading with the room, "84 · " was cut down to "84" and ran into the
        // "% prayed" behind it ("8496% prayed" mid-flight).
        PrayerScoresCollapse(open: q) { Text(text).opacity(Double(JourneyMotion.seg(q, 0.55, 1))) }
            .clipped()
    }
}
