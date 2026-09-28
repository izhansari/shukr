//
//  WidgetListTaps.swift
//  shukr
//
//  Prototype (owner, 2026-09-28): the Prayers widget's times list with tappable rows — a prayer
//  that has started and isn't marked is marked right there (scored at the tap, like the corner
//  check); a marked one opens the app to "Unmark Asr?". Off by default: the list stays read-only.
//  In the app group so the widget follows; Settings (beta builds) → "Widget: tap prayers in the
//  list (prototype)".
//

import Foundation

enum WidgetListTaps {
    static let key = "widget.listTaps"
    /// The app-group key a done row's tap leaves for the app: "Asr|<start, seconds since 1970>".
    static let unmarkKey = "widgetUnmarkPrayer"
    /// The prayer-day start (seconds) of a prayer the list just marked, so the app rescores that
    /// day — it can be another day than the app's (a list drawn before Fajr, tapped after).
    static let markedDayKey = "widgetListMarkedDay"

    static var enabled: Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: key) ?? false
    }
}
