//
//  LockTimeStyle.swift
//  shukr
//
//  How the Lock Screen circle writes the time left in a prayer's last hour (owner, 2026-09-30,
//  idea J2UQ / note 1D497A13: "27m" or "27min", with a Settings toggle to compare before settling).
//  In the app group so the widget follows it; Settings (the owner only) → "Lock Screen time left".
//

import Foundation

enum LockTimeStyle: String, CaseIterable, Identifiable {
    /// A live countdown, "27:13" (the system ticks it; no extra timeline entries).
    case timer
    /// "27m" / "27min": iOS's live formats can only say "27 minutes", so the timeline carries an
    /// entry a minute in the last hour — only while one of these is picked.
    case m
    case min

    static let key = "lockTimeStyle"
    var id: String { rawValue }

    static var current: LockTimeStyle {
        UserDefaults(suiteName: SharedStore.appGroup)?.string(forKey: key).flatMap(LockTimeStyle.init) ?? .timer
    }

    var sample: String {
        switch self {
        case .timer: "27:13"
        case .m: "27m"
        case .min: "27min"
        }
    }

    /// "27m" / "27min" for the time left at `date`, rounded up (never "0m" while it's still on).
    func text(left seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return self == .min ? "\(minutes)min" : "\(minutes)m"
    }
}
