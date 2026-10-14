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

    /// Three tiles, each in sections (owner, 2026-10-12: one per job; 2026-10-14: iOS 27 hides any tile outside a section
    /// once an app has sections, so everything is in one): Prayer Time (Find the Current or Next Prayer · Look Up a Prayer's
    /// Time), Open shukr (Open a Page in shukr, Tasbih Fatimah too) and, on iOS 26, Ask shukr (Check on Your Day · See What's
    /// Around You: the cards). Fajr Time, Next Prayer, Chosen Prayer and Offset are Get Prayer Time; Qibla is a page of Open
    /// shukr; each card's own action still runs in saved shortcuts. Symbols: outline, the app's own where it has one.
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // Every tile sits in a section (iOS 27 hides an app's tiles outside one once any tile has sections — Apple's
        // FB24520413; his phone, 2026-10-14): the cards are Ask shukr's options, Tasbih Fatimah a page of Open shukr.
        // Their own actions stay (saved shortcuts, the editor), without tiles of their own.
        // FIRST (owner: the page in this order — See What's Around You, Check on Your Day, Find the Current or Next Prayer,
        // Look Up a Prayer's Time, Open a Page in shukr). Xcode marks every tile after an `if #available` block 26-only too,
        // so before iOS 26 shukr has no tiles (the actions stay); an AppShortcutsBuilder can't drop a tile on 26.
        if #available(iOS 26.0, *) {
            AppShortcut(
                intent: AskShukrIntent(),
                phrases: [
                    // Each option's synonyms are the old tiles' phrases: "How long is left in shukr", "I prayed in shukr",
                    // "Nearby mosques in shukr", "Have I prayed here in shukr", "My zikr tasks in shukr" …
                    "\(\.$answer) in \(.applicationName)",
                    "Ask \(.applicationName) \(\.$answer)"
                ],
                shortTitle: "Ask shukr",
                systemImageName: "text.bubble",
                parameterPresentation: ParameterPresentation(
                    for: \.$answer,
                    summary: Summary("\(\.$answer)"),
                    optionsCollections: {
                        OptionsCollection(AskShukrAroundOptions(), title: "See What’s Around You", systemImageName: "location")
                        OptionsCollection(AskShukrTodayOptions(), title: "Check on Your Day", systemImageName: "sun.max")
                    }
                )
            )
        }

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
            intent: OpenShukrIntent(),
            phrases: [
                "Open \(\.$page) in \(.applicationName)",
                "Show \(\.$page) in \(.applicationName)",
                "Go to \(\.$page) in \(.applicationName)",
                "Start \(\.$page) in \(.applicationName)"   // "Start Tasbih Fatimah in shukr" (it was its own tile)
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

    }
}

/// What a tile in Ask shukr's sections answers: each was its own tile until iOS 27 hid tiles outside a section.
enum ShukrAnswer: String, AppEnum {
    case timeLeft, todaysTimes, prayed, zikrTasks, fajrAlarm, mosques, prayedHere
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Answer"
    static var caseDisplayRepresentations: [ShukrAnswer: DisplayRepresentation] = [
        .timeLeft: DisplayRepresentation(title: "Time Left", subtitle: "Time left for the prayer that's on", image: .init(systemName: "hourglass"),
                                         synonyms: ["how long is left", "how much time is left", "how long is left to pray", "prayer time left"]),
        .todaysTimes: DisplayRepresentation(title: "Today’s Times", subtitle: "All five of today's times", image: .init(systemName: "list.bullet"),
                                            synonyms: ["prayer times today", "today's prayer times", "today's times", "all prayer times today", "show today's prayers"]),
        .prayed: DisplayRepresentation(title: "I Prayed", subtitle: "Marks the prayer that's on", image: .init(systemName: "checkmark.circle"),
                                       synonyms: ["I prayed", "mark my prayer", "mark prayer as prayed"]),
        .zikrTasks: DisplayRepresentation(title: "Zikr Tasks", subtitle: "Today's zikr tasks", image: .init(systemName: "checklist"),
                                          synonyms: ["my zikr tasks", "show my zikr tasks", "what zikr is left"]),
        .fajrAlarm: DisplayRepresentation(title: "Fajr Alarm Time", subtitle: "When your Fajr alarm rings", image: .init(systemName: "alarm"),
                                          synonyms: ["when is my Fajr alarm", "Fajr alarm time"]),
        .mosques: DisplayRepresentation(title: "Nearby Mosques", subtitle: "The nearest mosques on a map", image: .init(systemName: "building.columns"),
                                        synonyms: ["nearby mosques", "find nearby mosques", "find a mosque", "mosques near me", "find a masjid", "nearest mosque"]),
        .prayedHere: DisplayRepresentation(title: "Prayed Here", subtitle: "Your prayers where you are", image: .init(systemName: "mappin.and.ellipse"),
                                           synonyms: ["how many times have I prayed here", "have I prayed here", "when did I last pray here", "my prayers here"]),
    ]
}

struct AskShukrTodayOptions: DynamicOptionsProvider {
    func results() async throws -> [ShukrAnswer] { [.timeLeft, .todaysTimes, .prayed, .zikrTasks, .fajrAlarm] }
}
struct AskShukrAroundOptions: DynamicOptionsProvider {
    func results() async throws -> [ShukrAnswer] { [.mosques, .prayedHere] }
}

/// The tiles of Ask shukr's sections: the same answer and card as each one's own action.
@available(iOS 26.0, *)
struct AskShukrIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Ask shukr"
    static var description = IntentDescription("Time left, today's times, I prayed, your zikr tasks, your Fajr alarm, mosques near you, or your prayers where you are, each with its card.",
                                               categoryName: "Prayer Times")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Answer", default: .timeLeft) var answer: ShukrAnswer
    static var parameterSummary: some ParameterSummary { Summary("Ask shukr: \(\.$answer)") }
    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        switch answer {
        case .timeLeft: let a = try await TimeLeftNowIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .todaysTimes: let a = try await TodaysTimesNowIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .prayed: let a = try await MarkPrayedNowIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .zikrTasks: let a = try await ZikrTasksNowIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .mosques: let a = await NearbyMosquesNowIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .prayedHere: let a = await PrayedHereIntent.answer(); return .result(dialog: a.dialog, snippetIntent: a.card)
        case .fajrAlarm:
            let (time, on) = try FajrAlarmTimeIntent.next()
            return .result(dialog: IntentDialog(stringLiteral: FajrAlarmTimeIntent.spoken(time, on: on)),
                           snippetIntent: FajrAlarmCardIntent(time: time, on: on))
        }
    }
}

/// Get Fajr Alarm Time's card (setup's alarm picture) as a card intent, for Ask shukr's tile.
@available(iOS 26.0, *)
struct FajrAlarmCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Fajr Alarm Card"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Time") var time: Date
    @Parameter(title: "On") var on: Bool
    init() {}
    init(time: Date, on: Bool) { self.time = time; self.on = on }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let view = await MainActor.run { ShortcutCards.fajrAlarm?(!on, time) } ?? AnyView(EmptyView())
        return .result(view: AnyView(view.environment(\.colorScheme, scheme)))
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
    // `-snippetPreview mosques|here`: the place cards, loaded as the shortcuts load them.
    @State private var mosquesCard: AnyView?
    @State private var hereCard: AnyView?
    @State private var mosquesLine = "…"
    @State private var hereLine = "…"

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
            .task { await loadPlaces(what) }
        }
    }

    @MainActor private func loadPlaces(_ what: String) async {
        let dark = UserDefaults.standard.bool(forKey: "snippetDark")
        if what == "mosques" {
            let outcome = await NearbyMosquesSearch.run()
            mosquesLine = NearbyMosquesSearch.spoken(outcome)
            var map: UIImage?
            if case .found(let here, let list) = outcome, !list.isEmpty {
                map = await PlaceShortcutPreview.snapshot(here: here.coordinate, pins: list.prefix(NearbyMosquesSnippet.shown).map(\.coordinate),
                                                          size: CGSize(width: 360, height: 110), dark: dark)
            }
            mosquesCard = AnyView(NearbyMosquesSnippet(outcome: outcome, map: map))
        } else if what == "here" {
            let s = await PrayedHereLookup.run()
            hereLine = s?.spoken ?? "I couldn’t tell where you are right now."
            hereCard = AnyView(PrayedHereSnippet(summary: s))
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
        case "mosques": return mosquesLine
        case "here": return hereLine
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
        case "mosques": if let mosquesCard { mosquesCard }
        case "here": if let hereCard { hereCard }
        default: TodaysTimesSnippet(rows: rows, now: now)
        }
    }
}
#endif
