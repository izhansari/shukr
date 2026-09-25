//
//  AppIntent.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    // The Prayers widget has nothing to configure; with no parameters, Edit Widget has no
    // options to show.
    static var title: LocalizedStringResource = "Prayers"
    static var description = IntentDescription("Today's prayers and how much time is left.")
}
