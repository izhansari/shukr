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

    /// Apple swaps the globe by region; we go by where the user is.
    static func globeSymbol(longitude: Double?) -> String {
        guard let lon = longitude else { return "globe.americas.fill" }
        if lon < -25 { return "globe.americas.fill" }
        if lon < 65 { return "globe.europe.africa.fill" }
        return "globe.asia.australia.fill"
    }
}
