import SwiftUI
import SwiftData

// The end-of-day page (decision day-score-end, Izhan: "they dont get the same reward out as the effort they put in"):
// the ring shows the day — five fifths in their prayers' colours, a dot where in each window it was prayed — round
// the score and "4 of 5 in time"; a tap on a fifth tells that prayer; under the circle one line from `DayInsight`
// (with the Fajr alarm when it helps); a full day glows once. Mockups: board/mocks/day-score-mocks/v3.

extension DayPrayer {
    init(_ row: PrayerModel) {
        let key = PrayerPhotos.key(dayKey: row.dayKey, name: row.name)
        self.init(name: row.name, start: row.startTime, end: row.endTime,
                  markedAt: row.isCompleted ? row.markedTime : nil,
                  score: row.isCompleted ? row.numberScore : nil,
                  photoKey: row.isCompleted && PrayerPhotos.has(key) ? key : nil,
                  excused: !row.isCompleted && Excused.covers(start: row.startTime, end: row.endTime),
                  noTime: row.isCompleted && row.timeUnknown)
    }
}

/// Whether the circle is showing the day's page (summaryCircle is up): the list's card rises with it, not at the mark
/// (Izhan: "have it rise together with the page").
/// The Salah page's own state (mainCircle.swift, PrayerTimesAndTracker.swift, SalahLook.swift write and read it).
/// Journey reads only its measured rests — `salahRing`, `salahList`, `salahPill`, `salahBarTop` (written by the Salah
/// page's layout) — so its day page lines up with the Salah page's on every phone (JourneyDayPage.layout); it never
/// writes here.
@MainActor @Observable final class DayPageState {
    static let shared = DayPageState()
    private(set) var up = false
    /// What's in the ring's centre takes its own taps — a prayer's photo, the make-up pill: the circle's own tap layer
    /// lets taps through to it (owner: "still can't click on the image while it's in the center of my ring"). A count,
    /// not a flag: one pick replacing another has the old view's late onDisappear land after the new one's onAppear.
    var centreTakesTaps: Bool { centreTaps > 0 }
    private var centreTaps = 0
    func centreAppeared() { centreTaps += 1 }
    func centreGone() { centreTaps = max(0, centreTaps - 1) }
    /// The prayer picked, by its fifth or its row (0 = Fajr … 4 = Isha; nil = the day). Shared, not the ring's own: the
    /// rows pick too (the day page merge, owner 2026-10-15). No timer: a second tap or the day changing clears it. The
    /// Salah tab has no day card to flip (owner, 2026-10-16: "the salah stays simple"); Journey's is JourneyDayPage's.
    var picked: Int?

    /// A fifth (or its row) picks; the same one again clears it. A pick lets the rank go: un-picking comes back to the score.
    func togglePick(_ i: Int) {
        picked = picked == i ? nil : i
        showsRank = false
    }
    /// The middle shows the day's rank instead of its score (a tap on the middle; owner, 2026-10-17: "Let's keep it as a
    /// tap"). Only while there's a rank to show (`rankReady`, set by the day page).
    var showsRank = false
    var rankReady = false
    /// The middle was tapped this showing: the rank's own flip (its teaching) stands down.
    private(set) var centreTouched = false
    /// A tap on the ring's middle (the band picks a fifth; a photo or pill there takes its own tap): a picked prayer goes
    /// back to the day, else the score and the rank swap. False when there was nothing to do.
    func centreTapped() -> Bool {
        centreTouched = true
        if picked != nil { picked = nil; return true }
        guard rankReady else { return false }
        showsRank.toggle()
        return true
    }
    func togglePick(name: String) {
        if let i = DayRing.order.firstIndex(of: name) { togglePick(i) }
    }
    /// The list's card is raised: set `CircleMotion.dayCardLiftDelay` after the page comes up (its rows unfold first —
    /// Izhan: "let it expand first then raise the card"), cleared with it. Kept here, not in the card's view: the list
    /// rebuilds its card as the page swaps, and a view's own state started out raised.
    private(set) var lifted = false
    /// The open page's room between the ring's outer edge and the list's top (measured at rest): the day's line sits in its
    /// middle (owner: it hung 22 pt under the ring with the list far below). nil until measured.
    var ringListGap: CGFloat?
    /// The Salah page's open rests on screen (global): the ring's box, the list's card, the day page's pill — Journey's day
    /// page lays itself out from these, so both pages follow one rule on every phone size (Frank's check on a Pro Max: my
    /// fixed numbers from a 17 Pro sat the card 80 pt high there). nil until the Salah page has laid out.
    var salahRing: CGRect?
    var salahList: CGRect?
    var salahPill: CGRect?
    /// The Salah page's bottom bar's top (global): the day page's pill sits a fixed distance above it.
    var salahBarTop: CGFloat?
    private var token = 0

    func pageAppeared() {
        up = true
        token += 1
        let mine = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CircleMotion.dayCardLiftDelay))
            guard token == mine, up else { return }
            lifted = true
        }
    }

    /// The circle left the screen (a push, the page swapping): the lift is reset; the pick, the flip and the open notes
    /// stay — coming back from the back's Zikr or Photos page lands on the back again (Bradley's review). `leaveDay`
    /// clears them when the day page itself goes.
    func pageGone() {
        token += 1
        up = false
        lifted = false
    }

    /// The day page is over (the score side left, the day changed, a row unmarked): nothing picked, the front up.
    func leaveDay() {
        picked = nil
        showsRank = false
        centreTouched = false
    }
}

/// A row on the Settings page to scroll to once it's at rest (the day page's "Set a Fajr alarm ›" lands on the alarm, not
/// the top — Ben's audit). Settings scrolls on `count`.
@MainActor @Observable final class SettingsJump {
    static let shared = SettingsJump()
    private(set) var target = ""
    private(set) var count = 0
    func request(_ id: String) { target = id; count += 1 }
    static let fajrAlarm = "fajrAlarm"
    /// Reminders' Live Activities side (Explore shukr's Set it up).
    static let liveActivities = "liveActivitiesSide"
    /// Reminders' Notifications side (Explore's notifications card).
    static let notifications = "notificationsSide"
}

/// The day's five prayers round the circle (Fajr at the top, clockwise), on the ring's own band. `drawn` (0…1, animatable)
/// draws the fifths in one after another, clockwise from the top; each one's dot shows as it completes; at 0 nothing.
struct DayRing: View, Animatable {
    let day: [DayPrayer]
    let picked: Int?
    var drawn: CGFloat = 1
    /// A fifth not drawn here: a mark's moment draws its own over this ring as it folds in (CompletionFlourish).
    var hidden: Int? = nil
    let onPick: (Int) -> Void
    var animatableData: CGFloat {
        get { drawn }
        set { drawn = newValue }
    }

    /// Fifth `i`'s share drawn: they overlap — each starts 0.15 after the one before and takes 0.4.
    private func part(_ i: Int) -> Double { min(max((Double(drawn) - Double(i) * 0.15) / 0.4, 0), 1) }
    @Environment(\.circleTheme) private var theme

    static let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static let gap = 0.014

    var body: some View {
        // Half the prayer arc's band: the five grade colours together are loud, so thin (owner, 2026-10-15).
        let style = StrokeStyle(lineWidth: theme.arc.width * 0.5, lineCap: theme.arc.cap)
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let from = Double(i) / 5 + Self.gap, full = Double(i + 1) / 5 - Self.gap
                let share = part(i)
                let to = from + (full - from) * share
                let p = Self.order.indices.contains(i) ? day.first { $0.name == Self.order[i] } : nil
                let on = picked == nil || picked == i
                ZStack {
                    if let p, p.done {
                        let color = p.noTime ? MarkKind.inTimeColor : PrayerScoring.color(for: p.score)
                        Circle().trim(from: from, to: to)
                            .stroke(color.opacity(picked == i ? 1 : 0.72), style: style)
                        if let at = p.share {
                            let angle = 360 * (from + (full - from) * at)
                            // When in its window it was prayed — a dot, photo or not (owner: the photos on the ring went
                            // back to dots; tapping the fifth still shows its photo in the centre).
                            // Hollow (owner, 2026-10-15, from his picture): a ring in its grade colour round the disc's own
                            // surface, sitting on the fifth.
                            Circle().fill(theme.surface)
                                .overlay(Circle().strokeBorder(color, lineWidth: picked == i ? 3 : 2.4))
                                .frame(width: picked == i ? 15 : 12, height: picked == i ? 15 : 12)
                                // Its photo waiting for its tap: the dot breathes (DevelopBreath, its own small view).
                                .background { if let key = p.photoKey { DevelopBreath(key: key, color: color) } }
                                .offset(x: 100)
                                .rotationEffect(.degrees(angle))
                                .opacity(max(0, (share - 0.85) / 0.15))   // as its fifth completes
                        }
                    } else {
                        // Not marked: the fifth stays a faint track.
                        Circle().trim(from: from, to: to)
                            .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: theme.arc.width * 0.5, lineCap: .round, dash: [1, 7]))
                    }
                }
                .opacity(share < 0.001 || hidden == i ? 0 : (on ? 1 : 0.25))   // undrawn: nothing (a zero trim still drew a cap)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 200, height: 200)
        // Only the band takes a tap (the centre keeps the circle's own).
        .contentShape(Circle().stroke(lineWidth: 46))
        .gesture(SpatialTapGesture().onEnded { tap in
            let dx = tap.location.x - 100, dy = tap.location.y - 100
            var turn = atan2(dx, -dy) / (2 * .pi)   // 0 at the top, clockwise
            if turn < 0 { turn += 1 }
            onPick(min(Int(turn * 5), 4))
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        Self.order.map { name in
            guard let p = day.first(where: { $0.name == name }), p.done, let s = p.score else { return "\(name): not marked" }
            return "\(name): \(PrayerScoring.grade(for: s).rawValue), \(PrayerScoring.points(for: s))"
        }.joined(separator: ", ")
    }
}

/// The centre: the score and "4 of 5 in time", or the picked prayer — its photo filling the ring (the name on a tag in
/// it), else its name, when it was prayed and its grade; "excused"; or, missed, the way to To make up (owner, 2026-10-15,
/// the day page merge: the row already says the time and the score, so the ring shows what the row can't).
struct DayCentre: View {
    let day: [DayPrayer]
    let score: Double
    let picked: Int?
    let yesterday: Bool
    /// Prayers still owed (JourneyMakeUpPage.entries), for a missed prayer picked; nil or 0 = no pill.
    var makeUpCount: Int? = nil
    var onMakeUp: (() -> Void)? = nil
    /// The day's place among your days, shown instead of the score while `showsRank` (the Salah tab's day page only).
    var rank: DayRank? = nil
    var showsRank = false

    var body: some View {
        if let i = picked, DayRing.order.indices.contains(i) {
            let name = DayRing.order[i]
            let p = day.first { $0.name == name }
            if let p, let key = p.photoKey {
                // The rounded-square photo inside the ring, its name and when under it (owner, 2026-10-16: "keep the
                // [squircle] picture inside of the ring instead of it filling the whole ring"); a tap opens it.
                VStack(spacing: 6) {
                    PrayerPhotoCard(key: key, width: 92)
                    Text("\(p.name) · \(p.markedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")")
                        .font(.footnote).fontWeight(.light).fontDesign(.rounded).foregroundStyle(.secondary)
                }
                .onAppear { DayPageState.shared.centreAppeared() }
                .onDisappear { DayPageState.shared.centreGone() }
                .transition(CircleMotion.dayPickSwap)
            } else {
                VStack(spacing: 3) {
                    Text(name).font(.system(size: 30, weight: .light, design: .rounded))
                    Text(p?.excused == true ? "excused" : p?.noTime == true ? "prayed in its time"
                         : p?.markedAt.map { "prayed \($0.formatted(date: .omitted, time: .shortened))" } ?? "not marked")
                        .font(.footnote).fontWeight(.thin).fontDesign(.rounded).foregroundStyle(.secondary)
                    if let s = p?.score {
                        Text(p?.noTime == true ? MarkKind.inTimeWord : PrayerScoring.summary(for: s))
                            .font(.caption).fontDesign(.rounded)
                            .foregroundStyle((p?.noTime == true ? MarkKind.inTimeColor : PrayerScoring.color(for: s)).opacity(0.9))
                            .padding(.top, 2)
                    } else if let p, p.missed, let makeUpCount, makeUpCount > 0, let onMakeUp {
                        // Missed: "see the others you gotta make up" (owner); marking stays the list's dot.
                        DayMakeUpPill(count: makeUpCount, action: onMakeUp).padding(.top, 6)
                    }
                }
                .transition(CircleMotion.dayPickSwap)
            }
        } else if MetricsLook.on {
            // The day as a count (prayer-metrics phase 3, plan-v3 §5): "4 of 5" with "in their time" under it — the prayers
            // due that day, an excused one not asked. The rank only as words, and only when it's true: the best day yet.
            let due = day.filter { !$0.excused }.count
            VStack(spacing: 3) {
                // A fully excused day asks nothing: no "0 of 0" (Fable's review).
                Text(due == 0 ? "Excused" : "\(day.filter(\.inTime).count) of \(due)")
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(due == 0 ? (yesterday ? "yesterday · nothing asked" : "nothing asked")
                     : showsRank && rank?.place == 1 && rank?.tiedWith == 0 ? "your best day yet"
                     : yesterday ? "yesterday · in their time" : "in their time")
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .transition(CircleMotion.dayPickSwap)
        } else if showsRank, let rank {
            // The rank in the score's place, the same type: "5th" / "of 112 days" (the suffix small, raised).
            VStack(spacing: 3) {
                (Text("\(rank.place)") + Text(rank.suffix).font(.system(size: 22, weight: .light, design: .rounded)).baselineOffset(18))
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(rank.caption)
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .transition(CircleMotion.dayPickSwap)
        } else {
            VStack(spacing: 3) {
                CountingScore(value: score)   // counts up when animated (the day's first showing)
                    .font(.system(size: 48, weight: .thin, design: .rounded))   // a little lighter (owner, 2026-10-15)
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            .transition(CircleMotion.dayPickSwap)
        }
    }

    private var caption: String {
        let inTime = day.filter(\.inTime).count
        let words: String
        if inTime == 5 { words = day.allSatisfy(\.perfect) ? "all five in the Opening" : "all five in time" }
        else { words = "\(inTime) of 5 in time" }
        return yesterday ? "yesterday · \(words)" : words
    }
}

/// Today's place among every finished day you've marked, by the day page's own number (`dayScore`, the five ÷ 5): the
/// same place Journey shows on a picked day ("5th of 112"), equal scores sharing it. None for an unfinished or excused day,
/// or before there's a week to compare (owner, 2026-10-17: "you've marked prayers for this many days. And of those days,
/// like, this ranked, like, number 5").
struct DayRank: Equatable {
    let place: Int
    let of: Int
    /// Other days with the same score.
    let tiedWith: Int

    /// Fewer finished days than this: no rank ("2nd of 3" says nothing yet).
    static let minimumDays = 7

    var suffix: String {
        let f = NumberFormatter(); f.numberStyle = .ordinal
        let s = f.string(from: NSNumber(value: place)) ?? "\(place)"
        return String(s.drop { $0.isNumber })
    }
    /// "of 112 days"; at the top "your best day yet", or "best day · tied with 8" when others share it.
    var caption: String {
        guard place == 1 else { return "of \(of) days" }
        return tiedWith == 0 ? "your best day yet" : "best day · tied with \(tiedWith)"
    }

    /// Today's rank, read off the main thread (JourneyLog.load: the whole prayer log).
    @MainActor static func today(container: ModelContainer) async -> DayRank? {
        let date = PrayerDay.date()
        let log = await JourneyLog.load(container: container, ranges: Excused.ranges)
        guard let day = log.days[PrayerNotificationID.dayKey(date)], day.allFive, day.excused == 0, !day.unfinished,
              let place = log.dayRank(date), log.rankedDays >= minimumDays else { return nil }
        // Among the ranked days, as `place` and `of` are (only those since a fresh start — Fable's audit #2).
        let tied = log.days.values.filter { $0.active && !$0.unfinished && $0.counted && $0.rankKey == day.rankKey }.count - 1   // ranks' own order
        return DayRank(place: place, of: log.rankedDays, tiedWith: max(tied, 0))
    }
}

/// The day's prayers, before today's: one list per prayer day, newest first (yesterday at 0), `days` of them; an
/// empty list for a day with no rows (it breaks a run, as it should).
enum DayHistory {
    /// Earlier days don't change within a day: one fetch per prayer day (Ben's audit — it ran on every appearance).
    @MainActor private static var cache: (key: String, days: [[DayPrayer]])?
    /// Excused changed (Excused.swift): earlier days count differently now.
    @MainActor static func invalidate() { cache = nil }

    @MainActor static func load(_ context: ModelContext, days: Int = 35) -> [[DayPrayer]] {
        let today = PrayerDay.date()
        let key = PrayerNotificationID.dayKey(today)
        if let cache, cache.key == key, cache.days.count == days { return cache.days }
        let loaded = fetch(context, days: days, today: today)
        cache = (key, loaded)
        return loaded
    }

    @MainActor private static func fetch(_ context: ModelContext, days: Int, today: Date) -> [[DayPrayer]] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days + 2), to: Calendar.current.startOfDay(for: today)) ?? today
        let descriptor = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.startTime >= cutoff })
        guard let rows = try? context.fetch(descriptor) else { return [] }
        // One row per name per day (a completed row wins), grouped by the row's own prayer day.
        var byDay: [String: [String: PrayerModel]] = [:]
        for row in rows {
            let key = row.dayKey
            if let kept = byDay[key]?[row.name], kept.isCompleted, !row.isCompleted { continue }
            byDay[key, default: [:]][row.name] = row
        }
        // Excused days (Excused.swift) are left out, so a run of good days or a "missed" pattern steps over them.
        let excused = Excused.Days()
        return (1...days).compactMap { back in
            let date = Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
            let rows = byDay[PrayerNotificationID.dayKey(date)] ?? [:]
            let full = rows.values.filter(\.isCompleted).count >= 5
            guard Excused.counts(day: Calendar.current.startOfDay(for: date), fullyPrayed: full, in: excused) else { return nil }
            return rows.values.map(DayPrayer.init)
        }
    }
}

/// The day's score as a whole number that counts through every value when it's animated (the first showing each day).
struct CountingScore: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text("\(Int((value * 100).rounded()))") }
}

/// A fifth whose photo has developed but waits for its tap (Tap to develop): a soft halo in its grade colour swells out
/// and fades behind the dot — three ~2.5 s breaths once the ring has drawn in, then still; again the next time the day
/// page opens; never once the photo is developed. Every waiting dot starts on the same beat, so several breathe in sync.
/// Reduce Motion: a still, soft halo instead. The animation lives here only — never the ring's or the circle's body.
struct DevelopBreath: View {
    let key: String
    let color: Color
    @State private var breaths = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var reveals = PhotoRevealState.shared

    init(key: String, color: Color) {
        self.key = key
        self.color = color
    }

    var body: some View {
        let _ = reveals.value   // stops once this photo is developed
        if PhotoDevelop.needsReveal(key: key) {
            if reduceMotion {
                Circle().fill(color.opacity(0.35)).frame(width: 18, height: 18).blur(radius: 3)
            } else {
                Circle().fill(color)
                    .frame(width: 9, height: 9)
                    .keyframeAnimator(initialValue: Breath(), trigger: breaths) { halo, b in
                        halo.scaleEffect(b.scale).opacity(b.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {   // three breaths
                            LinearKeyframe(1, duration: 0.01); LinearKeyframe(2.6, duration: 2.5, timingCurve: .easeOut)
                            LinearKeyframe(1, duration: 0.01); LinearKeyframe(2.6, duration: 2.5, timingCurve: .easeOut)
                            LinearKeyframe(1, duration: 0.01); LinearKeyframe(2.6, duration: 2.5, timingCurve: .easeOut)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0.45, duration: 0.01); LinearKeyframe(0, duration: 2.5, timingCurve: .easeOut)
                            LinearKeyframe(0.45, duration: 0.01); LinearKeyframe(0, duration: 2.5, timingCurve: .easeOut)
                            LinearKeyframe(0.45, duration: 0.01); LinearKeyframe(0, duration: 2.5, timingCurve: .easeOut)
                        }
                    }
                    .allowsHitTesting(false)
                    // After the ring's draw-in, every waiting dot on the same beat.
                    .task {
                        try? await Task.sleep(for: .seconds(CircleMotion.dayRingBreathDelay))
                        breaths += 1
                    }
            }
        }
    }

    struct Breath { var scale: CGFloat = 1; var opacity: Double = 0 }
}
