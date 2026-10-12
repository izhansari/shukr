//
//  ShukrAppShortcuts.swift
//  shukr
//
//  shukr's built-in shortcuts (the Shortcuts app's tiles, Siri's phrases, Spotlight). In the app target ONLY: an app
//  has one AppShortcutsProvider — it was compiled into the widget extension too, and the Shortcuts app showed the tiles
//  without their colour (owner: "I don't see the colors"). The intents themselves stay shared
//  (shukrWidget/SharedTargetForIntents.swift).
//

import AppIntents

struct PrayerTimeShortcuts: AppShortcutsProvider {
    /// The tiles in the Shortcuts app, in shukr's sage (owner: "add color to match our branding").
    static var shortcutTileColor: ShortcutTileColor = .grayGreen

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNextFajrIntent(),
            phrases: [
//                "Get Next Fajr time from \(.applicationName)",
//                "When is Fajr",
//                "Get Fajr time from \(.applicationName)",
//                "Fajr time from \(.applicationName)",
//                "Get morning prayer time from \(.applicationName)",
//                "morning prayer time from \(.applicationName)"
                "Get Next Fajr time from ${applicationName}",
                "Get Fajr time from ${applicationName}",
                "Fajr time from ${applicationName}",
                "Get morning prayer time from ${applicationName}",
                "morning prayer time from ${applicationName}"
            ],
            shortTitle: "Fajr Time",
            systemImageName: "sunrise.fill"
        )
        
        AppShortcut(
            intent: NextPrayerIntent(),
            phrases: [
                "Next prayer in ${applicationName}",
                "What's the next prayer in ${applicationName}",
                "Next prayer time from ${applicationName}",
                "Get next prayer time from ${applicationName}",
                "When is the next prayer in ${applicationName}"
            ],
            shortTitle: "Next Prayer",
            systemImageName: "clock.fill"
        )

        AppShortcut(
            intent: PrayerTimeLeftIntent(),
            phrases: [
                "How long is left in ${applicationName}",
                "How much time is left in ${applicationName}",
                "Time left in ${applicationName}"
            ],
            shortTitle: "Time Left",
            systemImageName: "hourglass"
        )

        AppShortcut(
            intent: MarkCurrentPrayerIntent(),
            phrases: [
                "I prayed in ${applicationName}",
                "Mark my prayer in ${applicationName}",
                "Mark prayer as prayed in ${applicationName}"
            ],
            shortTitle: "I Prayed",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: StartTasbihFatimahIntent(),
            phrases: [
                "Start Tasbih Fatimah in ${applicationName}",
                "Tasbih Fatimah in ${applicationName}"
            ],
            shortTitle: "Tasbih Fatimah",
            systemImageName: "circle.hexagonpath"
        )

        AppShortcut(
            intent: GetTodaysPrayerTimesIntent(),
            phrases: [
                "Prayer times today in ${applicationName}",
                "Today's prayer times in ${applicationName}"
            ],
            shortTitle: "Today's Times",
            systemImageName: "list.bullet.clipboard"
        )

        AppShortcut(
            intent: GetPrayerTimeIntent(),
            phrases: [
                "Get a prayer time in ${applicationName}",
                "Previous prayer in ${applicationName}"
            ],
            shortTitle: "Prayer Time",
            systemImageName: "clock.arrow.2.circlepath"
        )

        AppShortcut(
            intent: FajrAlarmTimeIntent(),
            phrases: [
                "When is my Fajr alarm in ${applicationName}",
                "Fajr alarm time in ${applicationName}"
            ],
            shortTitle: "Fajr Alarm Time",
            systemImageName: "alarm"
        )

        AppShortcut(
            intent: OpenCompassIntent(),
            phrases: [
                "Show the qibla in ${applicationName}",
                "Find the qibla in ${applicationName}"
            ],
            shortTitle: "Qibla",
            systemImageName: "location.north.line.fill"
        )

        AppShortcut(
            intent: GetOffsetTimeIntent(),
            phrases: [
//                "Get offset prayer time from \(.applicationName)"
                "Get offset prayer time from ${applicationName}"
            ],
            shortTitle: "Offset Prayer Time",
            systemImageName: "clock.badge.questionmark"
        )
        
    }
}
