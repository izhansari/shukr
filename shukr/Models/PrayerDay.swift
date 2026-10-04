//
//  PrayerDay.swift
//  shukr
//
//  The "prayer day" runs Fajr to Fajr (owner, 2026-09-25): after midnight and before Fajr it's
//  still yesterday, so a late Isha can still be marked — as a Qaza: Isha's window itself ends
//  at 11:59 PM (see `ishaEnd`). Fajr comes from the location and calculation method the app
//  saves in the app group (`PrayerUtils`), so the widget agrees with the app; with no location
//  yet the day turns at 3 AM (`fallbackHours`). (Before 2026-09-25 this was a Settings hour, Midnight…3 AM,
//  stored as `prayerDayRolloverHours`; the setting is gone and the key is no longer read.)
//
//  Prayer rows are still keyed by the calendar day their Fajr falls on (every fetch of "a day's
//  prayers" uses that calendar day); only two things move: which calendar day counts as
//  "today" (`date(for:)` / `start(for:)`) and where Isha ends (`ishaEnd(on:nextFajr:)`).
//  Compiled into the app and the widget (Models/ is in both targets).
//

import Foundation
import Adhan

enum PrayerDay {
    /// With no saved location there's no Fajr to go by: the day turns at 3 AM (owner's pick).
    static let fallbackHours = 3

    /// Fajr on the calendar day of `day`, or nil when there's no saved location (or no Fajr at
    /// that latitude). Cached per day + location + method: this is called from view bodies.
    static func fajr(onCalendarDayOf day: Date) -> Date? {
        let dayStart = Calendar.current.startOfDay(for: day)
        guard let coordinates = try? PrayerUtils.getUserCoordinates() else { return nil }
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let key = "\(dayStart.timeIntervalSince1970)|\(store?.double(forKey: "lastLatitude") ?? 0)|"
            + "\(store?.double(forKey: "lastLongitude") ?? 0)|"
            + "\(AutoMethod.effectiveMethod())|\(store?.integer(forKey: "school") ?? 0)"
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = fajrCache[key] { return hit }
        let fajr = try? PrayerUtils.getPrayerTimes(for: dayStart, coordinates: coordinates,
                                                   params: PrayerUtils.getCalculationParameters()).fajr
        if fajrCache.count > 16 { fajrCache.removeAll() }
        fajrCache[key] = fajr
        return fajr
    }
    private static var fajrCache: [String: Date?] = [:]
    private static let cacheLock = NSLock()

    /// A time on the calendar date whose prayers are "today's" at `now`: yesterday's before
    /// today's Fajr, today's from Fajr on.
    static func date(for now: Date = Date()) -> Date {
        guard let fajr = fajr(onCalendarDayOf: now) else {
            return Calendar.current.date(byAdding: .hour, value: -fallbackHours, to: now) ?? now
        }
        guard now < fajr else { return now }
        return Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    }

    /// Start of that calendar day: the key every "today's prayers" fetch uses.
    static func start(for now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date(for: now))
    }

    // MARK: Day keys (schema 2.8.0)

    /// "YYYY-MM-DD" of the prayer day an instant falls in (Fajr to the next Fajr at the saved location; the 3 AM
    /// rule without one). What every "today's rows" lookup compares.
    static func key(for instant: Date = Date()) -> String {
        PrayerNotificationID.dayKey(date(for: instant))
    }

    /// The day key for a prayer ROW, from its name and start — what `PrayerModel.prayerDayKey` stores. Only an Isha
    /// can belong to the day before its calendar date (one that starts after midnight); Fajr, Dhuhr, Asr and
    /// Maghrib always belong to the calendar day they start on. Keyed by name on purpose: a Fajr recorded at another
    /// location (an earlier Fajr than today's rule would compute for that date) must never slip to the previous day.
    static func key(forRow name: String, startingAt start: Date) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: start)
        guard name == "Isha" else { return PrayerNotificationID.dayKey(dayStart) }
        let cutoff = fajr(onCalendarDayOf: start) ?? dayStart.addingTimeInterval(6 * 3600)   // no location: before 6 AM
        if start < cutoff, let previous = calendar.date(byAdding: .day, value: -1, to: dayStart) {
            return PrayerNotificationID.dayKey(previous)
        }
        return PrayerNotificationID.dayKey(dayStart)
    }

    /// Midnight at the start of a key's calendar date, in the current time zone.
    static func start(ofKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c).map { Calendar.current.startOfDay(for: $0) }
    }

    /// The predicate for one prayer day's rows: the stored key, or — for rows the backfill hasn't reached (an
    /// install's first launch after the update, or the widget running before the app) — the old time window
    /// of `rowRange(forDayStarting:)`. Pass both so the fetch works in every state.
    static func rowsPredicate(key: String, start: Date, end: Date) -> Predicate<PrayerModel> {
        #Predicate<PrayerModel> { $0.prayerDayKey == key || ($0.prayerDayKey == nil && $0.startTime >= start && $0.startTime <= end) }
    }

    /// `rowsPredicate` for the prayer day that starts on the calendar day `dayStart`.
    static func rowsPredicate(forDayStarting dayStart: Date) -> Predicate<PrayerModel> {
        let (s, e) = rowRange(forDayStarting: dayStart)
        return rowsPredicate(key: PrayerNotificationID.dayKey(dayStart), start: s, end: e)
    }

    /// When the current prayer day began, as an instant: its Fajr (3 AM without a location). Zikr sessions are timestamped, so "today's sessions" (task progress) means
    /// sessions since this — a session at 1 AM, before Fajr, counts for yesterday.
    static func sessionDayStart(for now: Date = Date()) -> Date {
        let dayStart = start(for: now)
        return fajr(onCalendarDayOf: dayStart)
            ?? Calendar.current.date(byAdding: .hour, value: fallbackHours, to: dayStart) ?? dayStart
    }

    /// Bounds for fetching the prayer rows of the prayer day that starts on the calendar day `dayStart`:
    /// from that day's Fajr (less a 90-min allowance for a Fajr that moved) up to the next day's Fajr.
    /// It used to be the calendar day — so an Isha starting after midnight (≈45–48°N, 18° methods, June)
    /// was invisible to its own day (re-inserted on every refresh) and adopted by the next one, and a
    /// marked row moved days with a time-zone change (audit A6, 2026-10-01). Without a location the
    /// calendar day stays (no Fajr to anchor on). Shared with the widget.
    static func rowRange(forDayStarting dayStart: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let calendarEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
        guard let fajr = fajr(onCalendarDayOf: dayStart) else { return (dayStart, calendarEnd) }
        let start = max(dayStart, fajr.addingTimeInterval(-90 * 60))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let end = (self.fajr(onCalendarDayOf: nextDay) ?? calendarEnd).addingTimeInterval(-1)
        return (start, max(end, calendarEnd))
    }

    /// When the prayer day of the calendar day containing `date` ends: the next day's Fajr
    /// (3 AM without a location).
    static func rolloverInstant(after date: Date) -> Date {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return fajr(onCalendarDayOf: nextDay)
            ?? calendar.date(byAdding: .hour, value: fallbackHours, to: nextDay) ?? nextDay
    }

    /// Shortest Isha window: where Isha starts late (far north in summer, it can start after
    /// 11 PM or even after midnight), 11:59 PM would leave it minutes long or make every Isha a
    /// Qaza.
    static let minimumIshaWindow: TimeInterval = 60 * 60

    /// Isha's end: 11:59:59 PM on the calendar day of `date`, independent of the rollover — or
    /// an hour after `ishaStart` if that's later — and never past the next Fajr when it's known.
    static func ishaEnd(on date: Date, ishaStart: Date? = nil, nextFajr: Date?) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        var end = midnight.addingTimeInterval(-1)
        if let ishaStart { end = max(end, ishaStart.addingTimeInterval(minimumIshaWindow)) }
        if let nextFajr, nextFajr < end { return nextFajr }
        return end
    }
}

/// Prayer notification ids carry their prayer day (2026-09-27, `NotificationScheduler`):
/// "2026-09-27.FajrStart", "2026-09-27.AsrMid". Days never overwrite each other, and one prayer's
/// nudges can be cancelled exactly. Before, ids were just "AsrMid" (still recognised as legacy).
/// The day is the calendar day the prayer's day starts on (its Fajr) — all five start on it.
enum PrayerNotificationID {
    static let kinds = ["Start", "Mid", "End"]
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    static func dayKey(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func make(day: Date, prayer: String, kind: String) -> String {
        "\(dayKey(day)).\(prayer)\(kind)"
    }
    /// (day key or nil for a legacy id, prayer, kind) — nil when it isn't a prayer notification.
    static func parse(_ id: String) -> (dayKey: String?, prayer: String, kind: String)? {
        var rest = Substring(id)
        var day: String?
        if let dot = rest.firstIndex(of: "."), rest.distance(from: rest.startIndex, to: dot) == 10 {
            day = String(rest[..<dot])
            rest = rest[rest.index(after: dot)...]
        }
        for prayer in prayers where rest.hasPrefix(prayer) {
            let kind = String(rest.dropFirst(prayer.count))
            if kinds.contains(kind) { return (day, prayer, kind) }
        }
        return nil
    }
}
