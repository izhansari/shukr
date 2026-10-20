//
//  OpenShukrIntents.swift
//  shukr (app and widget extension)
//
//  The "open shukr to …" intents (widgets, controls, Shortcuts), DeepLinkSignal, WidgetPerf and the DEBUG WidgetSpeedTest.
//  What was left of SharedTargetForIntents.swift after the split (cleanup-map tangle 3, 2026-10-20).
//

// MARK: - Intents

import AppIntents
import ActivityKit
import WidgetKit
#if canImport(AlarmKit)
import AlarmKit
#endif
import SwiftData
import CoreData
import CoreLocation




struct OpenTasbeehIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbeeh"
    /// Folded into "Open shukr" → Zikr; the Tasbeeh control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's Zikr page.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
    
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetTasbeeh")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTasbeeh: \(store.bool(forKey: "widgetTasbeeh"))")
        }
        return .result()
    }
}

struct OpenCompassIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Qibla"
    /// Folded into "Open shukr" → Qibla; the Qibla control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's qibla map, turned so the qibla points up.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetCompass")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetCompass: \(store.bool(forKey: "widgetCompass"))")
        }
        return .result()
    }
}

/// A widget / control open's flags have just been written (widget-open-chrome). These intents run in the app
/// (`openAppWhenRun`), so on a cold launch they write after the app has started — after the welcome decided to play
/// and after the first look at the flags. The app opens the page as soon as this arrives, and the welcome steps aside.
/// In the widget's own process nobody listens.
enum DeepLinkSignal {
    static let arrived = Notification.Name("shukr.deepLinkArrived")
    static func post() {
        Task { @MainActor in NotificationCenter.default.post(name: arrived, object: nil) }
    }
}

/// Widget → one zikr task: the Zikr page with that task's circle in the middle, ready to tap.
struct OpenZikrTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Zikr Task"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        store?.set(taskID, forKey: "widgetZikrTask")
        store?.set(true, forKey: "widgetTasbeeh")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Widget → the Daily Ayah page (one-shot flag read on activation, like the compass one).
struct OpenDailyAyahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Daily Ayah"
    /// Folded into "Open shukr" → Daily Ayah; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens today's ayah in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetDailyAyah")
        DeepLinkSignal.post()
        return .result()
    }
}



/// Widget → the 99 Names page.
struct OpenNamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 99 Names"
    /// Folded into "Open shukr" → 99 Names; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens the 99 Names in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetNames")
        DeepLinkSignal.post()
        return .result()
    }
}
















/// "Start Tasbih Fatimah" — shukr opens into the 33 · 33 · 34 session (as the post-salah pill does).
struct StartTasbihFatimahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbih Fatimah"   // every action that opens shukr says "Open" (owner)
    static var description = IntentDescription("Opens shukr into Tasbih Fatimah: 33 · 33 · 34.", categoryName: "Open shukr",
                                               searchKeywords: ["tasbih", "tasbeeh", "zikr", "dhikr", "subhanallah"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "liveActivity.openTasbih")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens Memories (a control, a shortcut).
struct OpenMemoriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Moments"
    /// Folded into "Open shukr" → Memories; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens your prayer photos in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetMemories")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens the Salah page (the prayer control).
struct OpenSalahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Prayers"
    /// Folded into "Open shukr" → Salah (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr on today's prayers.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "alarmOpenSalah")
        DeepLinkSignal.post()
        return .result()
    }
}

/// The pages "Open shukr" goes to (owner: one tile, pick the page; the Control Center buttons stay separate). Each
/// sets the flag its own control / widget sets, so the app opens it the same way (PrayerTimesView).
enum ShukrPage: String, AppEnum, CaseIterable {
    case salah, qibla, zikr, dailyAyah, names, memories, tasbihFatimah
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static var caseDisplayRepresentations: [ShukrPage: DisplayRepresentation] = [
        .salah: DisplayRepresentation(title: "Salah", subtitle: "Today's prayers", image: .init(systemName: "sun.horizon"),
                                      synonyms: ["prayers", "prayer times", "salat", "namaz"]),
        .qibla: DisplayRepresentation(title: "Qibla", subtitle: "The qibla map", image: .init(systemName: "location.north.line"),
                                      synonyms: ["compass", "the qibla", "direction of Mecca"]),
        .zikr: DisplayRepresentation(title: "Zikr", subtitle: "Your zikr and tasks", image: .init(systemName: "hands.and.sparkles"),
                                     synonyms: ["dhikr", "tasbeeh", "tasbih", "azkar"]),
        .dailyAyah: DisplayRepresentation(title: "Daily Ayah", subtitle: "Today's ayah", image: .init(systemName: "book"),
                                          synonyms: ["ayah", "the ayah", "verse of the day", "Quran"]),
        .names: DisplayRepresentation(title: "99 Names", subtitle: "The names of Allah", image: .init(systemName: "moon.stars"),
                                      synonyms: ["names", "names of Allah", "Asma ul Husna"]),
        .memories: DisplayRepresentation(title: "Moments", subtitle: "Your prayer photos", image: .init(systemName: "photo.stack"),
                                         synonyms: ["photos", "prayer photos", "memories"]),   // its old name (owner renamed it Moments, 2026-10-15)
        // Its own tile until iOS 27 hid every tile outside a section (2026-10-14): a page here, so it stays on the page.
        .tasbihFatimah: DisplayRepresentation(title: "Tasbih Fatimah", subtitle: "33 · 33 · 34", image: .init(systemName: "circle.hexagonpath"),
                                              synonyms: ["Tasbih Fatimah", "tasbeeh Fatimah", "33 33 34"]),
    ]
    /// The app group flag its control / widget sets.
    var flag: String {
        switch self {
        case .salah: "alarmOpenSalah"
        case .qibla: "widgetCompass"
        case .zikr: "widgetTasbeeh"
        case .dailyAyah: "widgetDailyAyah"
        case .names: "widgetNames"
        case .memories: "widgetMemories"
        case .tasbihFatimah: "liveActivity.openTasbih"
        }
    }
}

/// Open shukr's pages as one collection under its tile (see PrayerPickRelativeOptions).
struct ShukrPageOptions: DynamicOptionsProvider {
    func results() async throws -> [ShukrPage] { ShukrPage.allCases }
}

/// "Open shukr": one tile for every page (owner, 2026-10-12) — "Open qibla in shukr", "Open moments in shukr".
struct OpenShukrIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shukr"
    static var description = IntentDescription("Opens shukr on the page you pick: Salah, Qibla, Zikr, Daily Ayah, 99 Names or Moments.",
                                               categoryName: "Open shukr", searchKeywords: ["open", "go to", "show", "qibla", "zikr", "ayah", "names", "moments", "memories"])
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Page", default: .salah) var page: ShukrPage
    static var parameterSummary: some ParameterSummary { Summary("Open shukr on \(\.$page)") }

    init() {}
    init(page: ShukrPage) { self.page = page }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: page.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// "Find Nearby Mosques" (owner: "a quick way to ask for nearby mosques and see a map with the pins and a list"): shukr
/// opens on the map with its mosques — the pins and the list in the sheet.
struct FindNearbyMosquesIntent: AppIntent {
    static let flag = "widgetMosques"
    static var title: LocalizedStringResource = "Open Nearby Mosques"   // it opens shukr, so it says Open (owner)
    /// Replaced on iOS 26 by Find Nearby Mosques' card (decision nearby-mosques-card A); still the card's "Open in shukr"
    /// and saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's map on the mosques near you: their pins, and the nearest in a list.",
                                               categoryName: "Open shukr", searchKeywords: ["masjid", "mosque", "near me", "find", "jumuah", "map"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

// (The App Shortcuts list lives in the app only: shukr/CursorSwift/ShukrAppShortcuts.swift.)




/// DEBUG: the widget's tap → redraw path timed, one line per step, in the app group's
/// Library/Caches/widget-perf.log (last ~200 KB). Pull it with `xcrun devicectl device copy from --device <udid>
/// --domain-type appGroupDataContainer --domain-identifier group.betternorms.shukr.shukrWidget
/// --source Library/Caches/widget-perf.log --destination <file>`.
enum WidgetPerf {
    static func log(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appending(path: "Library/Caches", directoryHint: .isDirectory) else { return }
        let url = dir.appending(path: "widget-perf.log")
        let stamp = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .secondFraction(.fractional(3)))
        let data = Data("\(stamp) [\(ProcessInfo.processInfo.processName)] \(line())\n".utf8)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            if let size = try? h.seekToEnd(), size > 200_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    /// Milliseconds since `start`.
    static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

#if DEBUG
/// DEBUG switches (Settings → My Dev Stuff) to find what makes a Prayers widget tap slow to redraw.
enum WidgetSpeedTest {
    static let stillRingKey = "debugWidget.stillRing"
    static let fewestEntriesKey = "debugWidget.fewestEntries"
    static var stillRing: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: stillRingKey) == true }
    static var fewestEntries: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: fewestEntriesKey) == true }
}
#endif



import SwiftUI



