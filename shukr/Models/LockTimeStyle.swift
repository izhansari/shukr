//
//  LockTimeStyle.swift
//  shukr
//
//  How the Lock Screen circle writes the time left in a prayer's last hour: "27m" (owner, idea J2UQ; the
//  27:13 / 27min trial ended with settings-cleanup-1 — the Settings picker is gone). iOS's live formats can
//  only say "27 minutes", so the widget's timeline carries an entry a minute in the last hour.
//

import Foundation

enum LockTimeLeft {
    /// "27m" for the time left, rounded up (never "0m" while it's still on).
    static func text(left seconds: TimeInterval) -> String {
        "\(max(1, Int((seconds / 60).rounded(.up))))m"
    }
}
