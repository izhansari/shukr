//
//  WidgetPayloads.swift
//  shukr
//
//  Small hand-offs from the app to the home-screen widgets (both targets compile this).
//  Zikr tasks and prayers come straight from the shared SwiftData store; the Daily Ayah needs the
//  app's bundled Qur'an databases, so the app writes the day's revealed verse here instead.
//

import Foundation

enum WidgetKinds {
    static let prayers = "PrayersWidget"
    static let zikr = "ZikrTasksWidget"
    static let name = "NameOfTheDayWidget"
    static let ayah = "DailyAyahWidget"
}

/// Today's ayah, written by the app once it's been revealed (the widget never spoils the reveal).
struct DailyAyahWidgetPayload: Codable, Equatable {
    var day: Date          // start of the calendar day it's for
    var arabic: String
    var english: String
    var reference: String  // "Al-Baqarah · 2:255"

    static let key = "widget.dailyAyah"
    private static var store: UserDefaults? { UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") }

    static func load() -> DailyAyahWidgetPayload? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DailyAyahWidgetPayload.self, from: data)
    }

    /// Writes only when it changed: every write to the group suite re-renders the app's
    /// @AppStorage views (see CLAUDE.md, Re-render hygiene). Returns true if it wrote.
    @discardableResult
    func save() -> Bool {
        guard Self.load() != self, let data = try? JSONEncoder().encode(self) else { return false }
        Self.store?.set(data, forKey: Self.key)
        return true
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }
}

extension NamesOfAllah {
    /// One name a day, the same everywhere (widget and app): Allah, then the 99 in order, round
    /// and round.
    static func nameOfTheDay(_ date: Date = Date()) -> AllahName {
        let calendar = Calendar.current
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .distantPast
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: epoch),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let index = ((days % all.count) + all.count) % all.count
        return all[index]
    }
}
