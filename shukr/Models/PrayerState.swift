//
//  PrayerState.swift
//  shukr
//
//  What a prayer is, in one word: the one place that decides it (prayer-metrics rethink, board/scoring-rethink/plan-v3.md
//  §2a; build plan phase 0). Every count reads a prayer's state from here instead of deciding "missed", "in time" or
//  "excused" on its own (inventory.md found four meanings of "missed"). Phase 0 reproduces today's rules exactly: the
//  three in-time states are PrayerScoring's grades (Perfect · Middle · Closing), Qaza is `madeUp`. Later phases move the
//  bands to thirds (phase 2) and add the no-time mark (phase 6). Compiled into the app and the widget (Models/).
//

import Foundation

enum PrayerState: Equatable {
    /// Marked in its window, by PrayerScoring's grade (Perfect · Middle · Closing; the words change in phase 2).
    case opening, middle, closing
    /// Marked after its window ended (Qaza).
    case madeUp
    /// Its window ended and nothing was marked (not excused).
    case notMarked
    /// Excused Mode covered it: never due.
    case excused
    /// Its window hasn't ended and it isn't marked.
    case toCome

    /// The state of a prayer from its row's facts. `excused` = Excused Mode covers its window (`Excused.covers`); it only
    /// matters for an unmarked prayer — a marked one is what it was marked as. An unmarked prayer still open is to come,
    /// even while excused (the excused state wins: an excused prayer is never due).
    static func of(isCompleted: Bool, score: Double?, end: Date, excused: Bool, now: Date) -> PrayerState {
        if isCompleted {
            switch PrayerScoring.grade(for: score ?? 0) {
            case .perfect: return .opening
            case .onTime: return .middle
            case .late: return .closing
            case .qaza: return .madeUp
            }
        }
        if excused { return .excused }
        return end > now ? .toCome : .notMarked
    }

    /// Prayed, in its time or made up.
    var prayed: Bool { inTime || self == .madeUp }
    /// Prayed in its window.
    var inTime: Bool { self == .opening || self == .middle || self == .closing }
    /// Owed: the one meaning of "missed" (To make up, the day page, the missed face, Journey).
    var notMarked: Bool { self == .notMarked }
}

extension PrayerModel {
    /// This row's state now. `excusedRanges`: read `Excused.ranges` once per loop and pass it in (it decodes a list).
    func state(excusedRanges: [ExcusedRange], now: Date = Date()) -> PrayerState {
        PrayerState.of(isCompleted: isCompleted, score: numberScore, end: endTime,
                       excused: !isCompleted && !excusedRanges.isEmpty
                           && Excused.covers(start: startTime, end: endTime, in: excusedRanges),
                       now: now)
    }
}
