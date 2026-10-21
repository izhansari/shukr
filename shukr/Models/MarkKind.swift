//
//  MarkKind.swift
//  shukr
//
//  How a prayer was marked, when it isn't a plain timed tap (`PrayerModel.markKind`, schema 2.10.0; prayer-metrics
//  rethink phase 6, board/scoring-rethink/plan-v3.md §3 and §15). Honest data: a prayer tapped hours after its window
//  may have been prayed in its time, and saying so must never invent a clock time. Compiled into the app and the
//  widget (Models/).
//

import SwiftUI

enum MarkKind: String {
    /// In its time, the clock not recorded ("I don't remember the time"; the late-mark question's "In its time"; a
    /// no-record day filled in). Counts as in its time; never read as a time.
    case timeUnknown
    /// Asked and answered "Making it up now" (or marked from To make up / at a picked time after the window): a make-up,
    /// so the app never asks about it again. Same state as a late mark with no kind.
    case madeUp
    /// Combined with its pair while travelling (NM6W) — not built yet.
    case combined

    /// What a no-time mark reads as, where a grade word would go.
    static let inTimeWord = "In its time"
    /// Its fill: grey-green, in its time with no third claimed (plan-v3 §2's table; Zoe's demo).
    static let inTimeColor = Color(hue: 0.36, saturation: 0.22, brightness: 0.62)
}

/// Late marks the app asks about: a prayer marked after its window, from anywhere, that nobody has said "in its time" or
/// "making it up" for. In the app the question comes before the mark (the list, the circle); marks from outside (widget,
/// notification, watch, Siri, the Live Activity) are asked about once at the next open (plan-v3 §15). Only marks made
/// since this build first ran: the old history isn't questioned.
enum LateMarks {
    /// When asking began (the app group, so a widget mark before the first open counts too). Set once.
    static let askFromKey = "lateMarks.askFrom"

    static func startIfNeeded() {
        guard let group = UserDefaults(suiteName: SharedStore.appGroup), group.object(forKey: askFromKey) == nil else { return }
        group.set(Date().timeIntervalSince1970, forKey: askFromKey)
    }

    static var askFrom: Date? {
        guard let t = UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: askFromKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// A row to ask about: marked after its window ended, marked since asking began, no answer yet. Jumu'ah is never asked
    /// (it follows the masjid's time).
    static func needsAsk(_ row: PrayerModel, since: Date) -> Bool {
        guard row.isCompleted, row.markKind == nil, !row.isJumuah, let at = row.timeAtComplete else { return false }
        return at > row.endTime && at >= since
    }
}
