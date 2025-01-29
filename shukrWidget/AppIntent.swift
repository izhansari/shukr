//
//  AppIntent.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
//    static var title: LocalizedStringResource = "Configuration"
//    static var description = IntentDescription("This is an example widget.")
//
//    // An example configurable parameter.
//    @Parameter(title: "this guy", default: "🛎️")
//    var favoriteEmoji: String
    static var title: LocalizedStringResource = "the title wip..."
    static var description = IntentDescription("the description wip...")

    // An example configurable parameter.
    @Parameter(title: "this guy wip...", default: true)
    var defaultViewIsCurrent: Bool

}

