//
//  MapModes.swift
//  shukr
//
//  The map's style button (2026-09-27, notes #15): a globe (`globe.americas.fill`, or
//  europe.africa / asia.australia by where the user is) that toggles Standard ⇄ Satellite.
//  Satellite keeps the labels (MKHybridMapConfiguration). Remembered in @AppStorage.
//  An Apple Maps-style "Map Modes" sheet (picture cards, Traffic, Labels) was built and dropped
//  the same day — owner: just the globe.
//

import SwiftUI
import MapKit

enum MapModes {
    static let satelliteKey = "mapMode.satellite"

    static func configuration(satellite: Bool) -> MKMapConfiguration {
        satellite ? MKHybridMapConfiguration() : MKStandardMapConfiguration()
    }

    /// The map-style button's symbol: a map, as Find My's (owner, 2026-10-17: "instead of the globe SF symbol, we should
    /// probably use the map SF symbol the same way they do in the Find My iOS app"; was the region's globe).
    static let styleSymbol = "map"
}
