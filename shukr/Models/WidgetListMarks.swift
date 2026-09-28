//
//  WidgetListMarks.swift
//  shukr
//
//  Marking from the Prayers widget's times list (owner, 2026-09-28): a prayer that has started and
//  isn't marked is marked right there (scored at the tap, like the corner check); a marked one opens
//  the app to "Unmark Asr?" — the widget never unmarks by itself. These are the app-group keys the
//  widget leaves for the app.
//

import Foundation

enum WidgetListMarks {
    /// A marked row's tap: "Asr|<start, seconds since 1970>", for the app to ask about.
    static let unmarkKey = "widgetUnmarkPrayer"
    /// The prayer-day start (seconds) of a prayer the list just marked, so the app rescores that
    /// day — it can be another day than the app's (a list drawn before Fajr, tapped after).
    static let markedDayKey = "widgetListMarkedDay"
}
