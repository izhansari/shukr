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

/// "Bottom right" leaves out what "Bottom left" has (owner, 2026-09-27: choosing the same button
/// twice made no sense). "None" is always offered. Only one way: two providers depending on each
/// other is a circular type reference; `corners` covers a left changed to match the right.
struct BottomRightOptions: DynamicOptionsProvider {
    @IntentParameterDependency<ConfigurationAppIntent>(\.$bottomLeft) var config
    func results() async throws -> [WidgetCornerAction] {
        WidgetCornerAction.allCases.filter { $0 == .none || $0 != config?.bottomLeft }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Prayers"
    static var description = IntentDescription("Today's prayers and how much time is left.")

    /// Defaults are the corners the widget always had, so existing widgets don't change.
    @Parameter(title: "Bottom left", default: .qibla)
    var bottomLeft: WidgetCornerAction

    @Parameter(title: "Bottom right", default: .tasbeeh, optionsProvider: BottomRightOptions())
    var bottomRight: WidgetCornerAction

    /// The corners as shown: a widget already set to the same button twice shows the next unused
    /// one on the right instead of a duplicate.
    var corners: (left: WidgetCornerAction, right: WidgetCornerAction) {
        let left = bottomLeft
        guard bottomRight != .none, bottomRight == left else { return (left, bottomRight) }
        let fallback = [WidgetCornerAction.tasbeeh, .qibla, .dailyAyah, .names].first { $0 != left } ?? .none
        return (left, fallback)
    }
}
