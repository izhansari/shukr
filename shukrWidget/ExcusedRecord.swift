//
//  ExcusedRecord.swift
//  shukr (app and widget extension)
//
//  Excused from prayer: the ranges, the shared record and its lock, the resume intent.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 6).
//

import Foundation
import SwiftUI
import AppIntents
import WidgetKit

// MARK: - Excused from prayer (haid / after childbirth; owner, 2026-10-13, plan board/mocks/excused-days)

/// One stretch she was (or is) excused from prayer. A prayer whose window touches it can't be marked and isn't asked of
/// her; the app's "counted days" leave its prayer days out of streaks and stats (Excused.swift).
struct ExcusedRange: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case haid, nifas }
    var id = UUID()
    var kind: Kind
    var start: Date
    /// Her estimate: the check-ins are planned from it. Nothing ends by itself.
    var expectedEnd: Date
    /// Set when she ends it; nil while it runs.
    var end: Date?
    /// Zikr reminders pause too (her choice; zikr streaks never break on excused days either way).
    var pauseZikr: Bool

    /// A prayer window [from, to) she's excused from: it overlaps this stretch, and she was still excused when it ended.
    /// Ending it during a prayer's time makes that prayer due (it can be marked), as the fiqh has it.
    func covers(from: Date, to: Date) -> Bool { to > start && from < (end ?? .distantFuture) && (end.map { $0 >= to } ?? true) }
}

/// The one record (app group, JSON): every range, the running one last. Only the app writes it; the widget and the
/// intents read it. Read it once per loop (`ranges`) — each read decodes.
enum Excused {
    static let key = "excused.ranges"
    static let changed = Notification.Name("ExcusedChanged")

    /// Decoded once per change, not per call: every prayer row, the circle (≈10×/s while idle) and the widget's rows ask
    /// (perf-recheck, 2026-10-14). The stored bytes are compared — cheap — so a change from any process is seen at once.
    static var ranges: [ExcusedRange] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        rangesLock.lock(); defer { rangesLock.unlock() }
        if let cached = rangesCache, cached.data == data { return cached.list }
        let list = (try? JSONDecoder().decode([ExcusedRange].self, from: data)) ?? []
        rangesCache = (data, list)
        return list
    }
    private static let defaults = UserDefaults(suiteName: SharedStore.appGroup)
    private static let rangesLock = NSLock()
    nonisolated(unsafe) private static var rangesCache: (data: Data, list: [ExcusedRange])?
    static var current: ExcusedRange? { ranges.last(where: { $0.end == nil }) }
    static var isActive: Bool { current != nil }

    /// A prayer window she's excused from (marking it does nothing).
    static func covers(start: Date, end: Date, in list: [ExcusedRange] = ranges) -> Bool {
        list.contains { $0.covers(from: start, to: end) }
    }

    /// Written only when it changed: every app-group write invalidates bound @AppStorage (CLAUDE.md).
    static func save(_ list: [ExcusedRange]) {
        guard list != ranges, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: key)
    }
}

/// Excused, and someone tried to mark a prayer (she may be done and forgot): shukr opens and asks whether she's back,
/// never a silent no (owner). The flag is read by the Salah page (`openFromWidgetFlags`).
enum ExcusedResume {
    static let askKey = "excused.askResume"
    static func ask() {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: askKey)
        DeepLinkSignal.post()
    }
}

/// The Prayers widget's check and rows while excused: opens shukr to "Prayers are paused · I'm back".
struct ExcusedResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Prayers"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        ExcusedResume.ask()
        return .result()
    }
}
