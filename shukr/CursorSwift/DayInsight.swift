import Foundation

/// One prayer of a day, as the end-of-day page reads it (from its `PrayerModel` row).
struct DayPrayer {
    let name: String
    let start: Date
    let end: Date
    let markedAt: Date?
    let score: Double?

    var done: Bool { markedAt != nil && score != nil }
    /// In its window (Perfect, On time or Late) — not Qaza, not missed.
    var inTime: Bool { done && (score ?? 0) >= PrayerScoring.inWindowFloor - 0.0001 }
    var perfect: Bool { done && (score ?? 0) >= 0.9999 }
    /// Where in its window it was prayed: 0 = as it began, 1 = as it ended; past 1 (Qaza) reads 1.
    var share: Double? {
        guard let markedAt, end > start else { return nil }
        return min(max(markedAt.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }
    /// Minutes after its start it was prayed (in its window only).
    var minutesIn: Double? {
        guard inTime, let markedAt else { return nil }
        return max(markedAt.timeIntervalSince(start) / 60, 0)
    }
}

/// The end-of-day page's one line (decision day-score-end, Izhan: "make sure it's not going to get repetitive").
///
/// Three tiers, in order:
/// 1. **Something to act on** — a prayer that was missed, Qaza or late today (the worst first); when the same prayer has
///    been hard all week it says so, and a Fajr line offers the alarm when it's off.
/// 2. **A milestone** — 7, 14, 21, 30, 40, 50, 60, 90, 100… days in a row with all five in time. Rare on purpose.
/// 3. **Something noticed** — rotated so the same one doesn't come back within three days: a prayer's early run, a
///    personal best, earlier than usual, the day's average, the week's tally, all five early, Jumu'ah tomorrow.
/// Then the plain fallback: tomorrow's Fajr. Every line has a few phrasings, picked by the day, so even a repeat reads
/// differently. One line per prayer day: once picked it's kept for that day (`remember`).
enum DayInsight {
    struct Line: Equatable {
        let id: String
        let text: String
        /// Show "Set a Fajr alarm ›" under it.
        let offersFajrAlarm: Bool
    }

    struct Inputs {
        let dayKey: String
        let today: [DayPrayer]
        /// Earlier prayer days, newest first (yesterday at 0), up to about a month.
        let history: [[DayPrayer]]
        let fajrAlarmOn: Bool
        /// Tomorrow's start for a prayer (the same name), if known.
        let tomorrowStart: (String) -> Date?
        let tomorrowIsFriday: Bool
    }

    private static let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    // MARK: Picking

    /// The day's line: the one already picked for `dayKey`, else a new pick (remembered).
    static func line(_ input: Inputs, store: UserDefaults = .standard) -> Line {
        let all = candidates(input)
        var shown = store.dictionary(forKey: shownKey) as? [String: String] ?? [:]
        if let id = shown[input.dayKey], let kept = all.first(where: { $0.id == id }) { return kept }
        let line = pick(all, input: input, shown: shown)
        shown[input.dayKey] = line.id
        // Keep the last two weeks.
        if shown.count > 14 { for k in shown.keys.sorted().prefix(shown.count - 14) { shown[k] = nil } }
        store.set(shown, forKey: shownKey)
        return line
    }

    static let shownKey = "daySummary.shownLines"

    private static func pick(_ all: [Line], input: Inputs, shown: [String: String]) -> Line {
        let earlier = shown.keys.filter { $0 < input.dayKey }.sorted()
        let noticed = all.filter { $0.id.hasPrefix("notice.") }
        let fix = all.filter { $0.id.hasPrefix("fix.") || $0.id.hasPrefix("hard.") }
        if let first = fix.first {
            // The same fix two nights running already: a third night gives way to something noticed (no nagging).
            let lastTwo = earlier.suffix(2).compactMap { shown[$0] }
            if !(lastTwo.count == 2 && lastTwo.allSatisfy { $0 == first.id } && !noticed.isEmpty) { return first }
        }
        if let milestone = all.first(where: { $0.id.hasPrefix("milestone.") }) { return milestone }
        // Thursday night: Jumu'ah tomorrow is the one to act on.
        if let jumuah = noticed.first(where: { $0.id == "notice.jumuah" }) { return jumuah }
        // Not one shown on any of the last three days (by id, the prayer included).
        let recent = Set(earlier.suffix(3).compactMap { shown[$0] })
        let fresh = noticed.filter { !recent.contains($0.id) }
        let pool = fresh.isEmpty ? noticed : fresh
        if !pool.isEmpty { return pool[seed(input.dayKey) % pool.count] }
        return all.last ?? Line(id: "tomorrow", text: "", offersFajrAlarm: false)
    }

    /// A stable number for the day (not `hashValue`, which changes per launch).
    private static func seed(_ key: String) -> Int {
        key.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
    }
    private static func phrase(_ options: [String], _ input: Inputs) -> String {
        options[seed(input.dayKey + options[0]) % options.count]
    }

    // MARK: Candidates

    static func candidates(_ input: Inputs) -> [Line] {
        var out: [Line] = []
        let today = order.compactMap { name in input.today.first { $0.name == name } }
        let week = [input.today] + input.history.prefix(6)

        // 1 · Something to act on: missed, then Qaza, then late — the worst prayer of today.
        let missed = today.filter { !$0.done && $0.end < Date() }
        let qaza = today.filter { $0.done && !$0.inTime }
        let late = today.filter { $0.inTime && !$0.perfect && ($0.score ?? 1) < 0.8 }
        if let p = missed.first ?? qaza.first ?? late.first {
            let hardDays = week.filter { day in day.first { $0.name == p.name }.map { !$0.inTime } ?? false }.count
            let lateDays = week.filter { day in day.first { $0.name == p.name }.map { !($0.score.map { $0 >= 0.8 } ?? false) } ?? false }.count
            let when = input.tomorrowStart(p.name).map(time) ?? ""
            let tomorrow = when.isEmpty ? "" : " Tomorrow's is at \(when)."
            let alarm = p.name == "Fajr" && !input.fajrAlarmOn
            if hardDays >= 3 || lateDays >= 4 {
                out.append(Line(id: "hard.\(p.name)", text: phrase([
                    "\(p.name) has been your hardest this week.\(tomorrow)",
                    "\(p.name) has been the hard one this week.\(tomorrow)",
                ], input), offersFajrAlarm: alarm))
            } else if !p.done {
                out.append(Line(id: "fix.missed.\(p.name)", text: phrase([
                    "\(p.name) was missed today.\(tomorrow)",
                    "No \(p.name) marked today.\(tomorrow)",
                ], input), offersFajrAlarm: alarm))
            } else if !p.inTime {
                out.append(Line(id: "fix.qaza.\(p.name)", text: phrase([
                    "\(p.name) counted as Qaza today.\(tomorrow)",
                    "\(p.name) was made up after its time today.\(tomorrow)",
                ], input), offersFajrAlarm: alarm))
            } else if let marked = p.markedAt {
                out.append(Line(id: "fix.late.\(p.name)", text: phrase([
                    "\(p.name) came late today, at \(time(marked)).\(tomorrow)",
                    "\(p.name) was close today: \(time(marked)), its window ended at \(time(p.end)).",
                ], input), offersFajrAlarm: alarm))
            }
        }

        // 2 · A milestone: days in a row with all five in time, today included.
        if today.count == 5, today.allSatisfy(\.inTime) {
            var run = 1
            for day in input.history {
                guard day.count == 5, day.allSatisfy(\.inTime) else { break }
                run += 1
            }
            if milestones.contains(run) {
                out.append(Line(id: "milestone.\(run)", text: phrase([
                    "\(run) days in a row, all five in time. Alhamdulillah.",
                    "All five in time, \(run) days running. Alhamdulillah.",
                ], input), offersFajrAlarm: false))
            }
        }

        // 3 · Something noticed.
        if today.count == 5, today.allSatisfy(\.perfect) {
            out.append(Line(id: "notice.allEarly", text: phrase([
                "All five in their first 30 minutes. Alhamdulillah.",
                "Every prayer today, early in its time. Alhamdulillah.",
            ], input), offersFajrAlarm: false))
        }
        for p in today where p.perfect {
            // An early run: this prayer in its first 30 minutes, days in a row (3+), the longest one only.
            var run = 1
            for day in input.history {
                guard let q = day.first(where: { $0.name == p.name }), q.perfect else { break }
                run += 1
            }
            if run >= 3, !out.contains(where: { $0.id.hasPrefix("notice.run.") }) {
                out.append(Line(id: "notice.run.\(p.name)", text: phrase([
                    "\(p.name) in its first 30 minutes, \(run) days running.",
                    "\(run) days of early \(p.name) in a row.",
                ], input), offersFajrAlarm: false))
            }
        }
        for p in today {
            guard let mins = p.minutesIn else { continue }
            let past = input.history.prefix(30).compactMap { day in day.first { $0.name == p.name }?.minutesIn }
            // A personal best: the earliest in at least two weeks of marks.
            if past.count >= 14, mins < (past.min() ?? 0) - 1 {
                out.append(Line(id: "notice.best.\(p.name)", text: phrase([
                    "Your earliest \(p.name) in \(past.count >= 28 ? "a month" : "two weeks"): \(minutes(mins)) after it began.",
                    "\(p.name) \(minutes(mins)) after it began: your earliest in \(past.count >= 28 ? "a month" : "two weeks").",
                ], input), offersFajrAlarm: false))
            }
            // Earlier than usual: 15+ minutes before this week's middle.
            let lastWeek = Array(past.prefix(7)).sorted()
            if lastWeek.count >= 4 {
                let usual = lastWeek[lastWeek.count / 2]
                if usual - mins >= 15 {
                    out.append(Line(id: "notice.earlier.\(p.name)", text: phrase([
                        "\(p.name) \(minutes(usual - mins)) earlier than your usual.",
                        "\(p.name) came \(minutes(usual - mins)) sooner than this week's usual.",
                    ], input), offersFajrAlarm: false))
                }
            }
        }
        let leads = today.compactMap(\.minutesIn)
        if leads.count == 5 {
            let avg = leads.reduce(0, +) / Double(leads.count)
            out.append(Line(id: "notice.average", text: phrase([
                "On average, each prayer today came \(minutes(avg)) after it began.",
                "Today's average: \(minutes(avg)) from each start to your prayer.",
            ], input), offersFajrAlarm: false))
        }
        let weekDays = week.filter { $0.count == 5 }
        if weekDays.count >= 5 {
            let inTime = weekDays.reduce(0) { $0 + $1.filter(\.inTime).count }
            out.append(Line(id: "notice.week", text: phrase([
                "\(inTime) of \(weekDays.count * 5) prayers in time this week.",
                "This week: \(inTime) of \(weekDays.count * 5) prayers in their time.",
            ], input), offersFajrAlarm: false))
        }
        if input.tomorrowIsFriday {
            out.append(Line(id: "notice.jumuah", text: phrase([
                "Tomorrow is Jumu'ah.",
                "Jumu'ah tomorrow.",
            ], input), offersFajrAlarm: false))
        }

        // The fallback: tomorrow's Fajr.
        if let fajr = input.tomorrowStart("Fajr") {
            out.append(Line(id: "tomorrow", text: "Tomorrow's Fajr is at \(time(fajr)).", offersFajrAlarm: !input.fajrAlarmOn))
        }
        return out
    }

    static let milestones: Set<Int> = [7, 14, 21, 30, 40, 50, 60, 90, 100, 150, 200, 250, 300, 365]

    // MARK: Words

    private static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    private static func minutes(_ m: Double) -> String {
        let n = Int(m.rounded())
        if n < 1 { return "under a minute" }
        if n < 60 { return n == 1 ? "1 minute" : "\(n) minutes" }
        let h = n / 60, r = n % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }
}
