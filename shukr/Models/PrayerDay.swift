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
            + "\(store?.integer(forKey: "calculationMethod") ?? 0)|\(store?.integer(forKey: "school") ?? 0)"
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

    /// When the current prayer day began, as an instant: its Fajr (3 AM without a location). Zikr sessions are timestamped, so "today's sessions" (task progress) means
    /// sessions since this — a session at 1 AM, before Fajr, counts for yesterday.
    static func sessionDayStart(for now: Date = Date()) -> Date {
        let dayStart = start(for: now)
        return fajr(onCalendarDayOf: dayStart)
            ?? Calendar.current.date(byAdding: .hour, value: fallbackHours, to: dayStart) ?? dayStart
    }

    /// Calendar-day bounds for fetching the prayer rows of the day that starts on `dayStart`.
    static func rowRange(forDayStarting dayStart: Date) -> (start: Date, end: Date) {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
        return (dayStart, end)
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
