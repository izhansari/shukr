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
                "\(\.$which) time in \(.applicationName)",
                "\(\.$which) prayer time in \(.applicationName)",
                "When is \(\.$which) in \(.applicationName)",
                "What's \(\.$which) in \(.applicationName)",
                "\(\.$which) in \(.applicationName)"
            ],
            shortTitle: "Prayer Time",
            systemImageName: "clock",
            // One tile with its choices grouped, not a tile per choice (the Shortcuts app showed nine).
            parameterPresentation: ParameterPresentation(
                for: \.$which,
                summary: Summary("\(\.$which) prayer time"),
                optionsCollections: {
                    OptionsCollection(PrayerPickRelativeOptions(), title: "Now and next", systemImageName: "clock")
                    OptionsCollection(PrayerPickByNameOptions(), title: "By name", systemImageName: "sun.horizon")
                }
            )
        )

        AppShortcut(
            intent: PrayerTimeLeftIntent(),
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
            intent: GetTodaysPrayerTimesIntent(),
            phrases: [
                "Prayer times today in \(.applicationName)",
                "Today's prayer times in \(.applicationName)",
                "Today's times in \(.applicationName)"
            ],
            shortTitle: "Today's Times",
            systemImageName: "list.bullet"
        )

        AppShortcut(
            intent: MarkCurrentPrayerIntent(),
            phrases: [
                "I prayed in \(.applicationName)",
                "Mark my prayer in \(.applicationName)",
                "Mark prayer as prayed in \(.applicationName)"
            ],
            shortTitle: "I Prayed",
            systemImageName: "checkmark.circle"
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
                    OptionsCollection(ShukrPageOptions(), title: "Pages", systemImageName: "arrow.up.forward.app")
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
            log("Time Left: \((try? await PrayerTimeLeftIntent().perform()).map(line) ?? "threw")")
            log("Today: \((try? await GetTodaysPrayerTimesIntent().perform()).map(line) ?? "threw")")
            log("Fajr alarm: \((try? await FajrAlarmTimeIntent().perform()).map(line) ?? "threw")")
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
        let now = Date().addingTimeInterval(-UserDefaults.standard.double(forKey: "snippetHoursAgo") * 3600)   // `-snippetHoursAgo 6`
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.today(now).map { w in
            TodaysTimesSnippet.Row(name: w.name, start: w.start, end: w.end, marked: done.contains(w.name) || w.name == "Dhuhr",
                                   when: w.end <= now ? .earlier : w.start <= now ? .now : .coming)
        }
    }
    private func spoken(_ what: String) -> String {
        if let on = rows.first(where: { $0.when == .now }) { return "\(on.name) is on until \(shortTimePM(on.end))." }
        return noPrayerOnLine
    }
    @ViewBuilder private func card(_ what: String) -> some View {
        switch what {
        default: TodaysTimesSnippet(rows: rows)
        }
    }
}
#endif
