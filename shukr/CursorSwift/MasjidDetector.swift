//
//  MasjidDetector.swift
//  shukr
//
//  Was this prayer prayed at a masjid? (CLAUDE.md "Masjid-aware prayers", built 2026-09-26.)
//  A marked prayer's spot (latPrayedAt / longPrayedAt) is checked against your own masajid first
//  (no network), then an Apple Maps mosque search around it; a mosque within 75 m wins (GPS indoors
//  is loose). The answer is stored on the row (`PrayerModel.mosqueName`, "" = no), so each row is
//  checked once. A Friday Dhuhr found at a masjid becomes Jumu'ah and is rescored Early.
//  Runs after every mark in the app, and on activation for rows marked elsewhere (widget,
//  notification) and — a few spots per launch, Friday Dhuhrs first — for older history.
//  Mosques you've marked "don't recommend" never count.
//

import Foundation
import MapKit
import SwiftData

@MainActor
enum MasjidDetector {
    static let radius: CLLocationDistance = 75
    private static var running = false
    /// Searches by ~100 m cell within this run (a spot you pray at often is searched once).
    private static var cache: [String: String] = [:]

    private static func cell(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }

    /// The masjid at `coordinate`, or "" if none.
    static func masjid(at coordinate: CLLocationCoordinate2D) async -> String {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let fav = MosqueFavorites.all
            .map({ ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) })
            .filter({ $0.1 < 100 }).min(by: { $0.1 < $1.1 }) {
            return fav.0.name
        }
        let key = cell(coordinate)
        if let hit = cache[key] { return hit }
        let found = await MosqueSearch.find(in: MKCoordinateRegion(center: coordinate,
                                                                   span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        let best = found
            .filter { !MosqueHiding.isHidden($0) }
            .map { ($0, CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude).distance(from: here)) }
            .filter { $0.1 < radius }
            .min { $0.1 < $1.1 }
        let name = best?.0.name ?? ""
        cache[key] = name
        return name
    }

    /// Checks `prayers` (completed, with a spot, not checked yet). Returns the days whose scores
    /// changed (a new Jumu'ah).
    @discardableResult
    static func check(_ prayers: [PrayerModel], in context: ModelContext, maxSearches: Int = .max) async -> [Date] {
        var rescored: [Date] = []
        var searches = 0
        for prayer in prayers {
            guard prayer.isCompleted, prayer.mosqueName == nil,
                  let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { continue }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let isCached = cache[cell(coordinate)] != nil
            if !isCached {
                if searches >= maxSearches { break }
                searches += 1
            }
            prayer.mosqueName = await masjid(at: coordinate)
            if prayer.isJumuah {
                prayer.setPrayerScore(atDate: prayer.timeAtComplete ?? prayer.startTime)
                rescored.append(prayer.startTime)
            }
            if !isCached { try? await Task.sleep(for: .seconds(2)) }   // MKLocalSearch is rate-limited
        }
        try? context.save()
        return rescored
    }

    /// On activation: rows marked outside the app first, then history — Friday Dhuhrs, then
    /// newest — a few new spots per launch.
    static func catchUp(context: ModelContext, onRescore: @escaping ([Date]) -> Void) {
        guard !running else { return }
        running = true
        Task { @MainActor in
            defer { running = false }
            let descriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate { $0.isCompleted && $0.mosqueName == nil && $0.latPrayedAt != nil },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)])
            let rows = (try? context.fetch(descriptor)) ?? []
            guard !rows.isEmpty else { return }
            let fridays = rows.filter { $0.name == "Dhuhr" && Calendar.current.component(.weekday, from: $0.startTime) == 6 }
            let rest = rows.filter { !($0.name == "Dhuhr" && Calendar.current.component(.weekday, from: $0.startTime) == 6) }
            let days = await check(fridays + rest, in: context, maxSearches: 12)
            if !days.isEmpty { onRescore(days) }
        }
    }
}
