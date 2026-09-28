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

    static var enabled: Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: key) ?? false
    }
}
