//
//  PrayerDay.swift
//  shukr
//
//  The "prayer day" can run past midnight. With a rollover of 2 (hours), 1 AM still belongs to
//  yesterday's prayers, so a late Isha can still be marked until 2 AM — as a Qaza: Isha's
//  window itself ends at 11:59 PM (see `ishaEnd`). The rollover is a Settings-page setting
//  ("Day rolls over at"), stored in the app group so the widget agrees with the app.
//  (2026-09-25 → 09-24: for a day the rollover also moved Isha's end, which inflated Isha
//  scores; owner asked for the end to stay at 11:59 PM.)
//
//  Prayer rows are still keyed by the calendar day their Fajr falls on (every fetch of "a day's
//  prayers" uses that calendar day); only two things move: which calendar day counts as
//  "today" (`date(for:)` / `start(for:)`) and where Isha ends (`ishaEnd(on:nextFajr:)`).
//  Compiled into the app and the widget (Models/ is in both targets).
//

import Foundation

enum PrayerDay {
    static let rolloverKey = "prayerDayRolloverHours"
    static let maxRolloverHours = 4

    /// Hours after midnight the prayer day ends: 0 = midnight (the old behaviour) … 4.
    static var rolloverHours: Int {
        let stored = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.integer(forKey: rolloverKey) ?? 0
        return min(max(stored, 0), maxRolloverHours)
    }

    /// The calendar date whose prayers are "today's" at `now`.
    static func date(for now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .hour, value: -rolloverHours, to: now) ?? now
    }

    /// Start of that calendar day: the key every "today's prayers" fetch uses.
    static func start(for now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date(for: now))
    }

    /// When the current prayer day began, as an instant: its calendar day plus the rollover
    /// hours. Zikr sessions are timestamped, so "today's sessions" (task progress) means
    /// sessions since this — a session at 1 AM with a 3 AM rollover counts for yesterday.
    static func sessionDayStart(for now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .hour, value: rolloverHours, to: start(for: now)) ?? start(for: now)
    }

    /// Calendar-day bounds for fetching the prayer rows of the day that starts on `dayStart`.
    static func rowRange(forDayStarting dayStart: Date) -> (start: Date, end: Date) {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
        return (dayStart, end)
    }

    /// When the prayer day containing `date` ends: the rollover time after the next midnight.
    static func rolloverInstant(after date: Date) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return calendar.date(byAdding: .hour, value: rolloverHours, to: midnight) ?? midnight
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
