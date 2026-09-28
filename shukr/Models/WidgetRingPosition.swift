//
//  WidgetRingPosition.swift
//  shukr
//
//  Where the Prayers widget's ring sits in the free space between the widget's top edge and the
//  chevron's circle (owner, 2026-09-28, feedback D3DC914D: dead centre reads a touch high; the
//  perceived centre is lower). In the app group so the widget follows; Settings (beta builds) →
//  "Widget ring position". Default 60 % of the space above, 40 % below.
//

import Foundation

enum WidgetRingPosition: String, CaseIterable, Identifiable {
    case even = "50"
    case slightlyLow = "55"
    case low = "60"

    static let key = "widget.ringPosition"
    static let `default` = WidgetRingPosition.low

    var id: String { rawValue }
    /// The share of the free space above the ring.
    var above: Double { (Double(rawValue) ?? 60) / 100 }
    var title: String { "\(rawValue) / \(100 - (Int(rawValue) ?? 60))" }

    static var current: WidgetRingPosition {
        UserDefaults(suiteName: SharedStore.appGroup)?.string(forKey: key).flatMap(WidgetRingPosition.init) ?? .default
    }
}
