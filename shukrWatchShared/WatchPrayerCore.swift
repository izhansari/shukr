//
//  WatchPrayerCore.swift
//  shukr (watch app + watch complications)
//
//  The watch works out prayer times itself — they're maths (adhan-swift) from a location and a
//  calculation method — so it never has to wait on the phone. The phone sends what it needs over
//  WatchConnectivity (`WatchSync` in the iPhone app): location, method, madhab, city, and which
//  prayers are marked today. The watch app keeps it in the watch's own app-group defaults, where
//  the complications read it. Same rules as the phone: the prayer day runs Fajr to Fajr, Isha's
//  window ends at 11:59 PM (or an hour after it starts, capped at the next Fajr).
//

import Foundation
import SwiftUI
import Adhan

enum WatchStore {
    static let group = "group.betternorms.shukr.shukrWidget"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    enum Key {
        static let latitude = "watch.lat", longitude = "watch.lon"
        static let method = "watch.method", school = "watch.school"
        static let city = "watch.city"
        static let completed = "watch.completed", completedDay = "watch.completedDay"
        static let scores = "watch.scores"
        static let qiblaSensitivity = "watch.qiblaSensitivity"
        /// Prayers marked on this watch, shown at once until the phone reports them:
        /// name → [prayer-day start, score, tapped at].
        static let localMarks = "watch.localMarks"
        /// The mark id sent to the phone for each local mark (name → id), for undo / a failed save.
        static let localMarkIDs = "watch.localMarkIDs"
    }

    /// Saves what the phone sent. Returns true if anything changed.
    @discardableResult
    static func save(_ context: [String: Any]) -> Bool {
        let d = defaults
        var changed = false
        func set(_ value: Any?, _ key: String) {
            guard let value else { return }
            if (d.object(forKey: key) as? NSObject) != (value as? NSObject) { d.set(value, forKey: key); changed = true }
        }
        set(context["lat"], Key.latitude)
        set(context["lon"], Key.longitude)
        set(context["method"], Key.method)
        set(context["school"], Key.school)
        set(context["city"], Key.city)
        set(context["completed"], Key.completed)
        set(context["completedDay"], Key.completedDay)
        set(context["scores"], Key.scores)
        set(context["qiblaSensitivity"], Key.qiblaSensitivity)
        // Marks the phone now reports (for that day) no longer need the watch's own copy.
        if let completed = context["completed"] as? [String], let day = context["completedDay"] as? Double {
            var marks = localMarks
            for name in completed where abs((marks[name]?.first ?? -1) - day) < 1 { marks[name] = nil }
            if marks.count != localMarks.count { d.set(marks, forKey: Key.localMarks); changed = true }
        }
        return changed
    }

    static var localMarks: [String: [Double]] {
        defaults.dictionary(forKey: Key.localMarks) as? [String: [Double]] ?? [:]
    }

    /// Records a prayer marked on the watch (until the phone confirms it).
    static func addLocalMark(_ name: String, dayStart: Date, score: Double, at: Date, id: String) {
        var marks = localMarks
        marks[name] = [Calendar.current.startOfDay(for: dayStart).timeIntervalSince1970, score, at.timeIntervalSince1970]
        defaults.set(marks, forKey: Key.localMarks)
        var ids = localMarkIDs
        ids[name] = id
        defaults.set(ids, forKey: Key.localMarkIDs)
    }

    static var localMarkIDs: [String: String] {
        defaults.dictionary(forKey: Key.localMarkIDs) as? [String: String] ?? [:]
    }

    /// The prayer a mark id belongs to, while its local mark is still here.
    static func localMarkName(forID id: String) -> String? {
        localMarkIDs.first { $0.value == id }?.key
    }

    static func removeLocalMark(_ name: String) {
        var marks = localMarks
        marks[name] = nil
        defaults.set(marks, forKey: Key.localMarks)
        var ids = localMarkIDs
        ids[name] = nil
        defaults.set(ids, forKey: Key.localMarkIDs)
    }

    static var hasLocation: Bool {
        defaults.double(forKey: Key.latitude) != 0 || defaults.double(forKey: Key.longitude) != 0
    }
    static var city: String { defaults.string(forKey: Key.city) ?? "" }
}

struct WatchPrayer: Hashable {
    let name: String
    let start: Date
    let end: Date
}

enum WatchPrayers {
    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    /// The phone's method numbers (PrayerUtils.getCalculationParameters).
    static func parameters(method: Int, school: Int) -> CalculationParameters {
        let calculationMethod: CalculationMethod = {
            switch method {
            case 1: return .karachi
            case 2: return .northAmerica
            case 3: return .muslimWorldLeague
            case 4: return .ummAlQura
            case 5: return .egyptian
            case 7: return .tehran
            case 8: return .dubai
            case 9: return .kuwait
            case 10: return .qatar
            case 11: return .singapore
            case 12, 14: return .other
            case 13: return .turkey
            default: return .northAmerica
            }
        }()
        var params = calculationMethod.params
        params.madhab = school == 1 ? .hanafi : .shafi
        return params
    }

    private static func times(on day: Date) -> PrayerTimes? {
        let d = WatchStore.defaults
        guard WatchStore.hasLocation else { return nil }
        let coordinates = Coordinates(latitude: d.double(forKey: WatchStore.Key.latitude),
                                      longitude: d.double(forKey: WatchStore.Key.longitude))
        let params = parameters(method: d.object(forKey: WatchStore.Key.method) as? Int ?? 2,
                                school: d.integer(forKey: WatchStore.Key.school))
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params)
    }

    /// Today's five prayer windows (the prayer day: before today's Fajr it's still yesterday),
    /// Sunrise, and the next Fajr.
    static func day(at now: Date = Date()) -> (prayers: [WatchPrayer], sunrise: Date?, nextFajr: Date?)? {
        let calendar = Calendar.current
        guard let todays = times(on: now) else { return nil }
        let dayDate = now < todays.fajr ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now) : now
        guard let t = dayDate == now ? todays : times(on: dayDate) else { return nil }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayDate) ?? dayDate
        let nextFajr = times(on: tomorrow)?.fajr
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayDate)) ?? dayDate
        var ishaEnd = max(midnight.addingTimeInterval(-1), t.isha.addingTimeInterval(3600))
        if let nextFajr, nextFajr < ishaEnd { ishaEnd = nextFajr }
        let prayers = [
            WatchPrayer(name: "Fajr", start: t.fajr, end: t.sunrise),
            WatchPrayer(name: "Dhuhr", start: t.dhuhr, end: t.asr),
            WatchPrayer(name: "Asr", start: t.asr, end: t.maghrib),
            WatchPrayer(name: "Maghrib", start: t.maghrib, end: t.isha),
            WatchPrayer(name: "Isha", start: t.isha, end: ishaEnd),
        ]
        return (prayers, t.sunrise, nextFajr)
    }

    /// Prayers marked today, as the phone last reported (only if it was about this prayer day).
    static func completed(dayStart: Date) -> Set<String> {
        let d = WatchStore.defaults
        let day = Calendar.current.startOfDay(for: dayStart).timeIntervalSince1970
        let reportedDay = d.double(forKey: WatchStore.Key.completedDay)
        var done = abs(reportedDay - day) < 1 ? Set(d.stringArray(forKey: WatchStore.Key.completed) ?? []) : []
        for (name, mark) in WatchStore.localMarks where abs((mark.first ?? -1) - day) < 1 { done.insert(name) }
        return done
    }

    /// Scores of today's marked prayers (0…1), as the phone last reported.
    static func scores(dayStart: Date) -> [String: Double] {
        let day = Calendar.current.startOfDay(for: dayStart).timeIntervalSince1970
        let reportedDay = WatchStore.defaults.double(forKey: WatchStore.Key.completedDay)
        var scores = abs(reportedDay - day) < 1
            ? WatchStore.defaults.dictionary(forKey: WatchStore.Key.scores) as? [String: Double] ?? [:] : [:]
        for (name, mark) in WatchStore.localMarks where abs((mark.first ?? -1) - day) < 1 && mark.count > 1 {
            scores[name] = mark[1]
        }
        return scores
    }

    /// What the watch shows: the prayer that's on (not yet prayed), else the next one; after Isha,
    /// tomorrow's Fajr. `current` = its window is open now.
    static func relevant(at now: Date = Date()) -> (prayer: WatchPrayer, current: Bool)? {
        guard let day = day(at: now) else { return nil }
        let done = completed(dayStart: day.prayers[0].start)
        for p in day.prayers where !done.contains(p.name) {
            if p.start <= now && now < p.end { return (p, true) }
            if now < p.start { return (p, false) }
        }
        let fajr = day.nextFajr ?? now
        return (WatchPrayer(name: "Fajr", start: fajr, end: fajr), false)
    }

    /// Moments the complications should redraw: every prayer start and end from now on, plus the
    /// grade boundaries inside each window (Perfect → On time at +30 min, On time → Late halfway
    /// through the rest), so the stock timer ring changes colour on time (it can't within an entry).
    /// Also the next prayer day's (at least its Fajr window: +30 min, On time → Late, sunrise), so
    /// after Isha the timeline doesn't stop at Fajr and lean on the reload hint (a watch treats it
    /// as a hint only; Fajr could stay green, or still show after sunrise).
    static func boundaries(after now: Date = Date()) -> [Date] {
        guard let day = day(at: now) else { return [] }
        func marks(_ prayers: [WatchPrayer]) -> [Date] {
            prayers.flatMap { [$0.start, $0.end] + WatchScoring.gradeChanges(start: $0.start, end: $0.end) }
        }
        var dates = marks(day.prayers)
        if let f = day.nextFajr {
            dates.append(f)
            if let next = self.day(at: f.addingTimeInterval(1)) { dates += marks(Array(next.prayers.prefix(2))) }
        }
        return Array(Set(dates.filter { $0 > now })).sorted()
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "Fajr": return "sunrise.fill"
        case "Dhuhr": return "sun.max.fill"
        case "Asr": return "sun.haze.fill"
        case "Maghrib": return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }
}

/// The phone's scoring rule (shukr/Models/PrayerScoring.swift — the source of truth; that file also
/// holds SwiftData code, so the watch targets can't compile it). Keep the numbers in step:
/// Perfect ≤ 30 min after the adhan (100), then sliding to 60 at the window's end (On time ≥ 80,
/// Late below), Qaza after the window.
enum WatchScoring {
    static let earlyWindow: TimeInterval = 30 * 60
    static let inWindowFloor = 0.6

    /// The score you'd get marking it at `at` (0...1).
    static func score(start: Date, end: Date, at: Date) -> Double {
        if at > end { return 0.4 }
        let elapsed = at.timeIntervalSince(start)
        if elapsed <= earlyWindow { return 1 }
        let rest = end.timeIntervalSince(start) - earlyWindow
        guard rest > 0 else { return 1 }
        let left = min(max(end.timeIntervalSince(at) / rest, 0), 1)
        return inWindowFloor + (1 - inWindowFloor) * left
    }

    /// The phone's grade word for a score (PrayerScoring): Perfect · On time · Late · Qaza.
    static func word(forScore s: Double) -> String {
        if s >= 0.9999 { return "Perfect" }
        if s >= 0.8 { return "On time" }
        if s >= inWindowFloor - 0.0001 { return "Late" }
        return "Qaza"
    }

    /// "On time · 88", "Qaza" — the completion moment's line, as on the phone.
    static func summary(forScore s: Double) -> String {
        let word = word(forScore: s)
        return word == "Qaza" ? word : "\(word) · \(Int((s * 100).rounded()))"
    }

    /// A marked prayer's colour from its stored score (the phone's PrayerScoring.color(for:)).
    static func color(forScore s: Double) -> Color {
        if s >= 0.9999 { return .green }
        if s >= 0.8 { return .yellow }
        if s >= inWindowFloor - 0.0001 { return .red }
        return .gray
    }

    /// Green Perfect, yellow On time, red Late — the phone's circle colours.
    static func color(start: Date, end: Date, at: Date) -> Color {
        let s = score(start: start, end: end, at: at)
        if s >= 0.9999 { return .green }
        if s >= 0.8 { return .yellow }
        if s >= inWindowFloor - 0.0001 { return .red }
        return .gray
    }

    /// When the colour changes inside a window: +30 min, and the On time → Late point (score 0.8,
    /// halfway through the rest of the window).
    static func gradeChanges(start: Date, end: Date) -> [Date] {
        let rest = end.timeIntervalSince(start) - earlyWindow
        guard rest > 0 else { return [] }
        let perfectEnds = start.addingTimeInterval(earlyWindow)
        return [perfectEnds, perfectEnds.addingTimeInterval(rest / 2)]
    }
}

/// The qibla from where the phone last was (the watch has no GPS fix of its own here): the
/// great-circle bearing to the Kaaba, in degrees from true north — the phone's rule.
enum WatchQibla {
    static let kaaba = (lat: 21.4225, lon: 39.8262)

    static var bearing: Double? {
        guard WatchStore.hasLocation else { return nil }
        let d = WatchStore.defaults
        let lat = d.double(forKey: WatchStore.Key.latitude) * .pi / 180
        let lon = d.double(forKey: WatchStore.Key.longitude) * .pi / 180
        let kLat = kaaba.lat * .pi / 180, kLon = kaaba.lon * .pi / 180
        let y = sin(kLon - lon) * cos(kLat)
        let x = cos(lat) * sin(kLat) - sin(lat) * cos(kLat) * cos(kLon - lon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The phone's Settings → qibla accuracy (± degrees counted as facing it).
    static var sensitivity: Double {
        WatchStore.defaults.object(forKey: WatchStore.Key.qiblaSensitivity) as? Double ?? 3.5
    }
}
