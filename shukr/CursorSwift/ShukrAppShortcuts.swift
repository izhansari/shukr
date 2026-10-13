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
import SwiftUI

struct PrayerTimeShortcuts: AppShortcutsProvider {
    /// The tiles in the Shortcuts app, in shukr's sage (owner: "add color to match our branding").
    static var shortcutTileColor: ShortcutTileColor = .grayGreen

    /// Eight tiles, one per job (owner, 2026-10-12: "if made well enough, we dont need the redundant ones"). Fajr Time,
    /// Next Prayer, Chosen Prayer and Offset are Get Prayer Time now; Qibla is a page of Open shukr. Their old actions
    /// still run in saved shortcuts (hidden). Symbols: outline, the app's own where it has one.
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetPrayerTimeIntent(),
            phrases: [
                // "the next prayer" / "the current prayer" are the choices' synonyms: a phrase without the choice ran
                // Relevant, and answered "Asr isn't marked yet" to "next prayer" (review).
                // No bare "[choice] in shukr" / "[choice] prayer time": Siri took "Today's prayer times in shukr" for this
                // one on his phone.
                "\(\.$which) time in \(.applicationName)",
                "When is \(\.$which) in \(.applicationName)",
                "What's \(\.$which) in \(.applicationName)"
            ],
            shortTitle: "Prayer Time",
            systemImageName: "clock",
            // One tile with its choices grouped, not a tile per choice (the Shortcuts app showed nine).
            parameterPresentation: ParameterPresentation(
                for: \.$which,
                summary: Summary("\(\.$which) prayer time"),
                optionsCollections: {
                    // Section names read as actions (owner: "now and next is vague").
                    OptionsCollection(PrayerPickRelativeOptions(), title: "Find the Current or Next Prayer", systemImageName: "clock")
                    OptionsCollection(PrayerPickByNameOptions(), title: "Look Up a Prayer’s Time", systemImageName: "sun.horizon")
                }
            )
        )

        AppShortcut(
            intent: FajrAlarmTimeIntent(),
            phrases: [
                "When is my Fajr alarm in \(.applicationName)",
                "Fajr alarm time in \(.applicationName)"
            ],
            shortTitle: "Fajr Alarm Time",
            systemImageName: "alarm"
        )

        AppShortcut(
            intent: FindNearbyMosquesIntent(),
            phrases: [
                "Nearby mosques in \(.applicationName)",
                "Open nearby mosques in \(.applicationName)",
                "Find nearby mosques in \(.applicationName)",
                "Find a mosque in \(.applicationName)",
                "Mosques near me in \(.applicationName)",
                "Find a masjid in \(.applicationName)"
            ],
            shortTitle: "Open Nearby Mosques",
            systemImageName: "building.columns"
        )

        AppShortcut(
            intent: OpenShukrIntent(),
            phrases: [
                "Open \(\.$page) in \(.applicationName)",
                "Show \(\.$page) in \(.applicationName)",
                "Go to \(\.$page) in \(.applicationName)"
            ],
            shortTitle: "Open shukr",
            systemImageName: "arrow.up.forward.app",
            parameterPresentation: ParameterPresentation(
                for: \.$page,
                summary: Summary("Open \(\.$page)"),
                optionsCollections: {
                    OptionsCollection(ShukrPageOptions(), title: "Open a Page in shukr", systemImageName: "arrow.up.forward.app")
                }
            )
        )

        AppShortcut(
            intent: StartTasbihFatimahIntent(),
            phrases: [
                "Open Tasbih Fatimah in \(.applicationName)",
                "Start Tasbih Fatimah in \(.applicationName)",
                "Tasbih Fatimah in \(.applicationName)"
            ],
            shortTitle: "Open Tasbih Fatimah",
            systemImageName: "circle.hexagonpath"
        )

        // Time Left, Today's Times and I Prayed with buttons in their cards: iOS 26 only (decision shortcut-buttons-ios26 A).
        // LAST in the list: Xcode marks every tile after an `if #available` block as 26-only too (it did).
        // An AppShortcutsBuilder can't drop a tile on 26 ("#unavailable" isn't allowed), so before 26 these three have no tile.
        if #available(iOS 26.0, *) {
            AppShortcut(
                intent: TimeLeftNowIntent(),
                phrases: [
                    // Not "Time left in …": Siri asked "shukr or Home?" on his phone.
                    "How long is left in \(.applicationName)",
                    "How much time is left in \(.applicationName)",
                    "How long is left to pray in \(.applicationName)",
                    "Prayer time left in \(.applicationName)"
                ],
                shortTitle: "Time Left",
                systemImageName: "hourglass"
            )

            AppShortcut(
                intent: TodaysTimesNowIntent(),
                phrases: [
                    "Prayer times today in \(.applicationName)",
                    "Today's prayer times in \(.applicationName)",
                    "Today's times in \(.applicationName)",
                    "All prayer times today in \(.applicationName)",
                    "Show today's prayers in \(.applicationName)"
                ],
                shortTitle: "Today’s Times",
                systemImageName: "list.bullet"
            )

            AppShortcut(
                intent: ZikrTasksNowIntent(),
                phrases: [
                    "My zikr tasks in \(.applicationName)",
                    "Show my zikr tasks in \(.applicationName)",
                    "What zikr is left in \(.applicationName)",
                    "My \(.applicationName) tasks"
                ],
                shortTitle: "Zikr Tasks",
                systemImageName: "checklist"
            )

            AppShortcut(
                intent: MarkPrayedNowIntent(),
                phrases: [
                    "I prayed in \(.applicationName)",
                    "Mark my prayer in \(.applicationName)",
                    "Mark prayer as prayed in \(.applicationName)"
                ],
                shortTitle: "I Prayed",
                systemImageName: "checkmark.circle"
            )
        }
    }
}

#if DEBUG
/// `-intentSelfTest`: runs the Shortcuts actions in the app and logs each answer — a simulator build isn't team-signed,
/// so iOS won't run App Shortcuts there ("Unable to get teamId").
enum IntentSelfTest {
    @MainActor static func runIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("-intentSelfTest") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            func line(_ r: Any) -> String { String(describing: r).replacingOccurrences(of: "\n", with: " ") }
            func log(_ s: String) { NSLog("%@", "INTENTTEST " + s) }   // never as the format: answers hold "%"
            for pick in PrayerPick.allCases {
                var i = GetPrayerTimeIntent(); i.which = pick; i.minutes = 0; i.side = .before
                do { log("Prayer Time \(pick.rawValue): \(line(try await i.perform()))") }
                catch { log("Prayer Time \(pick.rawValue): threw \(error)") }
            }
            var off = GetPrayerTimeIntent(); off.which = .maghrib; off.minutes = 15; off.side = .before
            log("Prayer Time maghrib -15: \((try? await off.perform()).map(line) ?? "threw")")
            if #available(iOS 26.0, *) {   // the ones people run on 26
                log("Time Left: \((try? await TimeLeftNowIntent().perform()).map(line) ?? "threw")")
                log("Today: \((try? await TodaysTimesNowIntent().perform()).map(line) ?? "threw")")
                log("Zikr tasks: \(ZikrTaskSnapshot.today().map { ZikrTasksSnippet.spoken($0) } ?? "no store")")
            } else {
                log("Time Left: \((try? await PrayerTimeLeftIntent().perform()).map(line) ?? "threw")")
                log("Today: \((try? await GetTodaysPrayerTimesIntent().perform()).map(line) ?? "threw")")
            }
            log("Fajr alarm: \((try? await FajrAlarmTimeIntent().perform()).map(line) ?? "threw")")
            // `-intentSelfTest -selfTestControls YES`: the Control Center ones too — I Prayed marks (twice: the second only
            // says so) and the Fajr alarm switch flips and comes back.
            guard UserDefaults.standard.bool(forKey: "selfTestControls") else { return }
            for n in 1...2 {
                do { log("I Prayed #\(n): \(line(try await MarkPrayerFromControlIntent().perform()))") }
                catch { log("I Prayed #\(n): threw \(error)") }
            }
            let group = UserDefaults(suiteName: SharedStore.appGroup)
            let was = group?.bool(forKey: "alarmEnabled") == true
            var t = SetFajrAlarmEnabledIntent(); t.value = !was
            _ = try? await t.perform()
            log("Fajr switch \(was) → \(group?.bool(forKey: "alarmEnabled") == true)")
            t.value = was
            _ = try? await t.perform()
            log("Fajr switch back → \(group?.bool(forKey: "alarmEnabled") == true)")
        }
    }
}
#endif

#if DEBUG
/// `-snippetPreview today`: the Shortcuts cards over a Siri-like frost, at the times now (the simulator can't run the
/// real shortcut). With `-snippetDark YES` in dark.
struct SnippetPreviewHost: View {
    var body: some View {
        if let what = UserDefaults.standard.string(forKey: "snippetPreview") {
            ZStack {
                LinearGradient(colors: [.orange.opacity(0.5), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text(spoken(what)).font(.headline).padding([.horizontal, .top], 16)
                    card(what)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 60)
            }
            .environment(\.colorScheme, UserDefaults.standard.bool(forKey: "snippetDark") ? .dark : .light)
        }
    }

    private var rows: [TodaysTimesSnippet.Row] {
        TodaysTimesSnippet.rows(now: Date().addingTimeInterval(-UserDefaults.standard.double(forKey: "snippetHoursAgo") * 3600))   // `-snippetHoursAgo 6`
    }
    private func spoken(_ what: String) -> String {
        switch what {
        case "timeleft": return "2 hours 3 minutes left for Asr. It ends at 6:43 PM."
        case "prayed": return "Asr marked as prayed. Perfect."
        case "alarm": return "Your Fajr alarm is at 6:00 AM."
        case "tasks": return ZikrTasksSnippet.spoken(ZikrTaskSnapshot.today() ?? [])
        case "alarmoff": return "Your Fajr alarm rule gives 6:00 AM, but the alarm is off."
        default: break
        }
        if let on = rows.first(where: { $0.when == .now }) { return "\(on.name) is on until \(shortTimePM(on.end))." }
        return noPrayerOnLine
    }
    @ViewBuilder private func card(_ what: String) -> some View {
        let now = Date().addingTimeInterval(-UserDefaults.standard.double(forKey: "snippetHoursAgo") * 3600)
        let dark = UserDefaults.standard.bool(forKey: "snippetDark")
        let on = PrayerWindows.pick(.current, now: now)
        switch what {
        case "timeleft":
            if let on { PrayerCardSnippet(state: .init(label: on.name, start: on.start, end: on.end, symbol: prayerIcon(for: on.name), dark: dark)) }
        case "prayed":
            if let on { PrayerCardSnippet(state: .init(label: on.name, start: on.start, end: on.end, symbol: prayerIcon(for: on.name),
                                                       markedAt: on.start.addingTimeInterval(12 * 60), dark: dark)) }
        case "next":
            if let n = PrayerWindows.pick(.next, now: now) { NextPrayerSnippet(name: n.name, start: n.start, now: now) }
        case "alarm": ShortcutCards.fajrAlarm?(false, Date().addingTimeInterval(86400)) ?? AnyView(EmptyView())
        case "alarmoff": ShortcutCards.fajrAlarm?(true, Date().addingTimeInterval(86400)) ?? AnyView(EmptyView())
        case "tasks": ZikrTasksSnippet(tasks: ZikrTaskSnapshot.today() ?? [])
        default: TodaysTimesSnippet(rows: rows, now: now)
        }
    }
}
#endif
