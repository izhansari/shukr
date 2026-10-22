//
//  LiveActivityIntents.swift
//  shukr (app and widget extension)
//
//  The prayer Live Activity: its settings, attributes, the card's intents, the hooks the app fills, the log.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 5a).
//

import Foundation
import SwiftUI
import AppIntents
import ActivityKit
import WidgetKit

/// Which prayers get a Live Activity for their window (owner, 2026-10-11: its own setting, not the notifications' —
/// "two very different features"). App group, on by default for all five.
enum LiveActivityPrefs {
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static func key(_ prayer: String) -> String { "liveActivity.\(prayer)" }
    /// All five by default (owner, 2026-10-12; was Dhuhr, Asr and Maghrib): iOS's five at a time are topped up whenever
    /// shukr opens, and setup / Settings say so.
    static let onByDefault: Set<String> = Set(prayers)
    static func isOn(_ prayer: String) -> Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: key(prayer)) as? Bool ?? onByDefault.contains(prayer)
    }
}

/// The Live Activity card's own look, apart from the app's (owner, 2026-10-12: "the same way … their widgets"): System
/// (the phone's — the default, as the widgets), Light, Dark, Follows the sun (a window's card can't switch mid-way, so
/// Dhuhr and Asr light, Fajr, Maghrib and Isha dark). Settings → Live Activities → Card look. App group.
enum LiveActivityLook: String, CaseIterable, Identifiable {
    case system, light, dark, sun
    static let key = "liveActivity.look"
    var id: String { rawValue }
    static var current: LiveActivityLook {
        UserDefaults(suiteName: SharedStore.appGroup)?.string(forKey: key).flatMap(LiveActivityLook.init(rawValue:)) ?? .system
    }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .sun: "Sun"
        }
    }
    var detail: String {
        switch self {
        case .system: "Light or dark with your iPhone."
        case .light: "Always light."
        case .dark: "Always dark."
        case .sun: "Light after Fajr, dark at Maghrib."
        }
    }
    /// A prayer's card: dark or not; nil = the phone's.
    func dark(for prayer: String) -> Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        case .sun: !(prayer == "Dhuhr" || prayer == "Asr")
        }
    }
}

/// A prayer window as a Live Activity (PrayerLiveActivities.swift plans them; the card is `PrayerWindowLiveActivity`).
struct PrayerWindowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
        var symbol: String = "sun.max.fill"
        var markedAt: Date? = nil
        /// The Lock Screen card's look (`LiveActivityLook`): nil = the phone's.
        var dark: Bool? = nil
        /// The last card shukr has queued (owner): nothing comes after it until shukr opens, so it says so at its foot.
        /// Optional, so cards already held decode.
        var last: Bool? = nil
        /// After the last card's ↻ added more (owner: "you're all good"): how many cards it added, said on the card that
        /// was tapped; the card says "Live Activity cards topped up" (owner, 2026-10-14: no count — it only worried
        /// people). Optional, so cards already held decode.
        var toppedUp: String? = nil
    }
    /// The window's id: its start in whole minutes since 1970 (so a window is never scheduled twice).
    var n: Int
}

/// The card's ✓ (runs in shukr's process, as every LiveActivityIntent does): marks the real prayer and turns the card.
struct PrayerWindowMarkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark prayer prayed"
    static var isDiscoverable = false
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Mark prayed tapped on #\(n)")
        await MarkLog.$source.withValue("live activity ✓") { await markCard() }
        return .result()
    }
    private func markCard() async {
        if let mark = PrayerWindowHooks.mark {
            await mark(n)
        } else if let a = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n }) {
            // The app's hooks weren't set yet (Frank): the store's own mark, and the card goes — never a silent no-op.
            let st = a.content.state
            let done = SharedStore.markPrayerComplete(named: st.label, start: st.start, end: st.end)
            await a.end(nil, dismissalPolicy: .immediate)
            PrayerWindowLog.add("Mark prayed #\(n) without the app's hooks: store mark \(done ? "done" : "not needed / failed"), card ended")
        } else {
            MarkLog.add("live activity ✓ · card #\(n) → NOT marked: the card wasn't found")
        }
    }
}

/// The last card's ↻ (owner, 2026-10-14: "a refresh button on that last card"): runs in shukr without opening it — a
/// card button's run is when iOS lets shukr add cards from the background (the alarm's Stop can't) — and adds the next ones.
struct PrayerWindowRefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Get more prayer cards"
    static var isDiscoverable = false
    /// Opens shukr (decision last-card-refresh B): in front it fills all five; from the Lock Screen a tap adds only one.
    static var openAppWhenRun = true
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Refresh tapped on the last card (#\(n))")
        if let refresh = PrayerWindowHooks.refresh { _ = await refresh(n) }
        else { PrayerWindowLog.add("Refresh: the app's hooks weren't set") }
        // Without opening, iOS let a tap add one card only (the allowance is the tap's, not the run's — a chained second
        // intent was refused too, his phone 2026-10-14), so this opens shukr, which fills all five in front.
        return .result()
    }
}

/// After marking: Photo (the prayer's camera) or Tasbih (Tasbih Fatimah) — opens shukr.
struct PrayerWindowOpenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open after a prayer"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "What") var what: String
    @Parameter(title: "Window") var n: Int
    init() {}
    init(what: String, n: Int) { self.what = what; self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("\(what) tapped on #\(n) (opens shukr)")
        await PrayerWindowHooks.open?(n, what)
        return .result()
    }
}

/// The Prayers widget's camera (decision widget-camera A): once the prayer that's on is marked, it opens shukr on the
/// prayer photo's camera for it — as the Live Activity card's Photo does.
struct OpenPrayerPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Take a prayer photo"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "Prayer") var prayerName: String
    init() {}
    init(prayerName: String) { self.prayerName = prayerName }
    func perform() async throws -> some IntentResult {
        await PrayerWindowHooks.openPhoto?(prayerName)
        return .result()
    }
}

/// Set by the app at launch (an intent's run is always in the app's process).
enum PrayerWindowHooks {
    /// The widget's camera: the prayer's photo camera, once shukr is in front.
    nonisolated(unsafe) static var openPhoto: ((String) async -> Void)?
    nonisolated(unsafe) static var mark: ((Int) async -> Void)?
    nonisolated(unsafe) static var open: ((Int, String) async -> Void)?
    /// The last card's refresh: as many next cards as iOS lets this run add.
    nonisolated(unsafe) static var refresh: ((Int) async -> Int)?
    /// A widget's mark, run in the app (owner: the card goes at once; and a fresh location — S9FJ). Returns whether it marked.
    nonisolated(unsafe) static var widgetMark: ((String, Date, Date) async -> Bool)?
}

/// What the Live Activities did, both processes — app group Library/Application Support/live-activities.log (1 MB cap).
enum PrayerWindowLog {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/live-activities.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.liveActivityLog")
    static func add(_ line: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss.SSS"
        let text = "\(f.string(from: Date()))  [\(Bundle.main.bundleURL.pathExtension == "appex" ? "ext" : "app")] \(line)\n"
        #if DEBUG
        print("🟣 \(line)")
        #endif
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? Data(text.utf8).write(to: url) }
            // Days of it, never too big: the last ~4000 lines once it passes 1 MB.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? (all.split(separator: "\n").suffix(4000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
