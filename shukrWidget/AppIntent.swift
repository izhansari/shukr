//
//  AppIntent.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import WidgetKit
import AppIntents

/// What a bottom corner of the home-screen Prayers widget opens (Edit Widget, 2026-09-27,
/// notes #1). Same symbols as the app uses for each feature.
enum WidgetCornerAction: String, AppEnum, CaseIterable {
    case qibla, tasbeeh, dailyAyah, names, none

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Button"
    static var caseDisplayRepresentations: [WidgetCornerAction: DisplayRepresentation] = [
        .qibla: DisplayRepresentation(title: "Qibla", image: .init(systemName: "location")),
        .tasbeeh: DisplayRepresentation(title: "Tasbeeh", image: .init(systemName: "circle.hexagonpath")),
        .dailyAyah: DisplayRepresentation(title: "Daily Ayah", image: .init(systemName: "book")),
        .names: DisplayRepresentation(title: "99 Names", image: .init(systemName: "moon.stars")),
        .none: DisplayRepresentation(title: "None"),
    ]

    var symbol: String? {
        switch self {
        case .qibla: "location"
        case .tasbeeh: "circle.hexagonpath"
        case .dailyAyah: "book"
        case .names: "moon.stars"
        case .none: nil
        }
    }

    /// The existing intent it runs (nil for None: the corner stays empty).
    var intent: (any AppIntent)? {
        switch self {
        case .qibla: OpenCompassIntent()
        case .tasbeeh: OpenTasbeehIntent()
        case .dailyAyah: OpenDailyAyahIntent()
        case .names: OpenNamesIntent()
        case .none: nil
        }
    }
}

/// Tried 2026-09-27 and dropped: one "Bottom buttons" list of up to two (an `AppEntity` array with
/// `size: 2` — the only list type iOS offers). Its picks never reached the widget (the timeline got
/// an empty list, even for the default, and `entities(for:)` was never called), and iOS offers a
/// button already in the list anyway. A picker of ready-made pairs was rejected by the owner.
/// "Bottom right" leaves out what "Bottom left" has (owner, 2026-09-27: choosing the same button
/// twice made no sense). "None" is always offered. Only one way: two providers depending on each
/// other is a circular type reference; `corners` covers a left changed to match the right.
struct BottomRightOptions: DynamicOptionsProvider {
    @IntentParameterDependency<ConfigurationAppIntent>(\.$bottomLeft) var config
    func results() async throws -> [WidgetCornerAction] {
        WidgetCornerAction.allCases.filter { $0 == .none || $0 != config?.bottomLeft }
    }
}

/// The home-screen Prayers widget's look (Edit Widget, owner 2026-09-28). System follows the phone
/// (what every widget did before, so nothing changes unasked); "Follows the sun" (`auto`, the name
/// the owner picked — "Auto" sounded like System) is the app's own auto mode, "Auto · follows the
/// sun": dark from Maghrib until sunrise, light between. The Lock Screen ignores it (the system
/// tints it). Order: System · Light · Dark · Follows the sun.
enum WidgetStyle: String, AppEnum, CaseIterable {
    case system, light, dark, auto

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [WidgetStyle: DisplayRepresentation] = [
        .system: DisplayRepresentation(title: "System"),
        .light: DisplayRepresentation(title: "Light"),
        .dark: DisplayRepresentation(title: "Dark"),
        .auto: DisplayRepresentation(title: "Follows the sun", subtitle: "Dark from Maghrib until sunrise"),
    ]
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Prayers"
    static var description = IntentDescription("Today's prayers and how much time is left.")

    /// Defaults are the corners the widget always had, so existing widgets don't change.
    @Parameter(title: "Bottom left", default: .qibla)
    var bottomLeft: WidgetCornerAction

    @Parameter(title: "Bottom right", default: .tasbeeh, optionsProvider: BottomRightOptions())
    var bottomRight: WidgetCornerAction

    /// Off: a prayed prayer's dot is one plain colour instead of its score's (owner, 2026-09-27).
    @Parameter(title: "Score colours", default: true)
    var scoreColors: Bool?

    /// System (follows the phone; the default) · Light · Dark · Follows the sun (Maghrib → sunrise dark).
    @Parameter(title: "Style", description: "Home Screen only: the Lock Screen widgets follow the system.", default: .system)
    var style: WidgetStyle?

    /// The corners as picked — the same button on both is allowed (owner, 2026-09-27: "fine if
    /// they put the same thing twice"); it used to swap in another one silently.
    var corners: (left: WidgetCornerAction, right: WidgetCornerAction) { (bottomLeft, bottomRight) }
}
