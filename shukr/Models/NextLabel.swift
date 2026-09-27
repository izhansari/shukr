//
//  NextLabel.swift
//  shukr
//
//  Whether a prayer that hasn't started says "NEXT" above its name, or only its dashed ring does
//  the talking (owner, 2026-09-27: wants to see both). In the app group so the home-screen widget
//  follows it; Settings → My Dev Stuff → "Next prayer" (DEBUG). The Lock Screen widget never shows
//  NEXT — just the dashed ring.
//

import Foundation

enum NextLabel {
    static let key = "nextLabel.show"
    /// Default: NEXT shown (the owner's preference, if it looks good higher up).
    static var shown: Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: key) as? Bool ?? true
    }
}
