//
//  PrayerDay.swift
//  shukr
//
//  The "prayer day" can run past midnight. With a rollover of 2 (hours), 1 AM still belongs to
//  yesterday's prayers and Isha can be marked until 2 AM; before this, Isha ended at 11:59 PM
//  and a late Isha had nothing to be marked against. The rollover is a Settings-page setting,
//  stored in the app group so the widget agrees with the app.
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

    /// Isha's end on the calendar day of `date`: a second before the rollover (as the old
    /// 11:59:59 PM was a second before midnight), but never past the next Fajr when it's known.
    static func ishaEnd(on date: Date, nextFajr: Date?) -> Date {
        let end = rolloverInstant(after: date).addingTimeInterval(-1)
        if let nextFajr, nextFajr < end { return nextFajr }
        return end
    }
}
