//
//  PrayerViewModel+Location.swift
//  shukr
//
//  The location pass: a new fix → the gate (500 m / 10 min), the city, the times; Settings' Refresh Location.
//  Moved out of PrayerViewModel.swift (cleanup-map tangle 2, step 7).
//

import SwiftUI
import CoreLocation
import WidgetKit

extension PrayerViewModel {
    private static let lastPassKey = "location.lastPass"

    func handleLocationChange(for location: CLLocation?) {
        guard let location = location else {
            locationPrinter(">passed by the didUpdateLocation< - No location found")
            return
        }

        let now = Date()
        // The last pass, kept on disk: a background wake is a fresh process, and with only memory every wake looked like
        // the first and ran the whole pass (geocode, times, 30 days of reminders, the Fajr alarms) — perf-recheck,
        // 2026-10-14.
        if lastAppLocation == nil, let saved = UserDefaults.standard.array(forKey: Self.lastPassKey) as? [Double], saved.count == 3 {
            lastAppLocation = CLLocation(latitude: saved[0], longitude: saved[1])
            lastGeocodeRequestTime = Date(timeIntervalSince1970: saved[2])
        }
        // In the background only a real move (≥ 500 m) re-plans; the 10-minute refresh is for when the app is open.
        if UIApplication.shared.applicationState == .background, let last = lastAppLocation, last.distance(from: location) < 500 {
            restoreCityIfNeeded(for: location)
            return
        }
        if let lastAppLocation = lastAppLocation {
            let distanceChange = lastAppLocation.distance(from: location)
            if let lastRequestTime = lastGeocodeRequestTime {
                // Under 500 m and under 10 min since the last pass: nothing to do (audit B3 — every 30 s a stationary
                // phone re-geocoded, re-fetched, re-planned ~7 days of reminders and 60 alarms; CLGeocoder then
                // rate-limited and "Error fetching city" reached the widgets).
                if distanceChange < 500, now.timeIntervalSince(lastRequestTime) < 600 {
                    restoreCityIfNeeded(for: location)
                    return
                } else { locationPrinter("📍 New Location: \(location.coordinate.latitude), \(location.coordinate.longitude) -- \(Int(distanceChange)) > 500m ? | \(Int(now.timeIntervalSince(lastRequestTime))) > 10 min?") }
            } else { locationPrinter("📍 New Location: \(location.coordinate.latitude), \(location.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | First geocoding request") }
        } else { locationPrinter("⚠️ First location update. Proceeding with geocoding.") }

        // If we return out of the if block, update location and proceed with geocoding
        locationPrinter("🌍 Triggering geocoding and prayer times fetch...")
        // A real move (travel, notes #18; also a significant-change wake in the background): the
        // widgets and the watch follow straight away. Times + reminders follow below.
        // From the saved spot, not the last fix: after a background relaunch there's no last fix.
        let saved = CLLocation(latitude: lastLatitude, longitude: lastLongitude)
        let moved = (lastLatitude == 0 && lastLongitude == 0) ? 0 : saved.distance(from: location)
        let travelled = moved > 15_000
        storeLastCoordinate(location.coordinate)
        // When the saved spot was last a real fix (audit B10): a widget / watch mark records where it was prayed only
        // while this is fresh (`SharedStore.lastKnownLocation`); a picked city clears it (`setManualLocation`).
        if !ENV_LocationManager.hasManualLocation, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 200 {
            UserDefaults(suiteName: SharedStore.appGroup)?.set(now.timeIntervalSince1970, forKey: SharedStore.lastFixAtKey)
        }
        self.lastGeocodeRequestTime = Date()
        self.lastAppLocation = location
        UserDefaults.standard.set([location.coordinate.latitude, location.coordinate.longitude, now.timeIntervalSince1970],
                                  forKey: Self.lastPassKey)
        if travelled {
            print("🧳 moved \(Int(moved / 1000)) km: updating times, widgets, watch")
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.send()
        }
        updateCityName(for: location)
        #if DEBUG
        let passStart = Date()
        #endif
        fetchPrayerTimes(cameFrom: "updateLocation")
        #if DEBUG
        // How long a move's pass holds the main thread (the compass reads its heading there; compass-freeze 8Q9K).
        CompassLog.write("location pass \(Int(Date().timeIntervalSince(passStart) * 1000)) ms\(travelled ? " · travelled" : "")")
        #endif

    }
    
    /// A pass the gates above skip still needs a city on screen. The last pass is kept on disk, so a new process (an
    /// install, a relaunch) within 10 min and 500 m returned with no city: the top bar said "Fetching location…" and
    /// Settings "Finding…" until its refresh (owner, 2026-10-19). The saved name first; a lookup only when there's none.
    private func restoreCityIfNeeded(for location: CLLocation) {
        guard cityName == nil else { return }
        let saved = lastCityName
        if !saved.isEmpty, !["Wonderland", "Error.", "Unknown", "Error fetching city"].contains(saved) {
            cityName = saved
        } else {
            updateCityName(for: location)
        }
    }

    /// `done`: the city found, or nil when the lookup failed (Settings' Refresh Location says which).
    private func updateCityName(for location: CLLocation, done: ((String?) -> Void)? = nil) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.locationPrinter("❌ Reverse geocoding error: \(error.localizedDescription)")
                    // A failed lookup (the rate limit, no network) keeps the city it had (audit B3).
                    if let s = self, (s.cityName ?? "").isEmpty || s.cityName == "Unknown" { s.cityName = "Error fetching city" }
                    done?(nil)
                    return
                }

                if let placemark = placemarks?.first {
                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                    self?.locationPrinter("🏙️ Geocoded City: \(newCityName)")
                    self?.cityName = newCityName
                    // Automatic method: a new country can mean a different method (AutoMethod). The
                    // country is stored either way; only an Automatic user's times change.
                    if AutoMethod.setCountry(placemark.isoCountryCode) && AutoMethod.isAutomatic {
                        print("🧭 Automatic method now \(AutoMethod.shortName(AutoMethod.resolved())) (\(placemark.isoCountryCode ?? "?"))")
                        self?.fetchPrayerTimes(cameFrom: "automatic method changed")
                        WidgetCenter.shared.reloadAllTimelines()
                        WatchSync.shared.send()
                    }
                } else {
                    self?.locationPrinter("⚠️ No placemark found")
                    self?.cityName = "Unknown"
                }
                // Write the group suite only on a real change (every write invalidates the
                // app's @AppStorage bindings and re-renders Settings).
                let newCityName = self?.cityName ?? "Error."
                if self?.lastCityName != newCityName {
                    self?.lastCityName = newCityName
                    WidgetCenter.shared.reloadAllTimelines()
                }
                done?(self?.cityName)
            }
        }
    }
    
    struct RefreshFailure: Error { let message: String }

    /// Settings' Refresh Location: the place and the times again, and when it's done (or why not) — the button
    /// says so (owner, settings-cleanup-1).
    /// On the main actor: the class isn't, so after the city's await this ran on a background thread and set the times
    /// (and SwiftData) from there — SwiftData stopped the app (his phone, 2026-10-12).
    @MainActor func refreshLocationNow() async -> Result<String, RefreshFailure> {
        guard let location = ENV_LocationManager.effectiveLocation else {
            return .failure(RefreshFailure(message: "No location yet"))
        }
        let city: String? = await withCheckedContinuation { continuation in
            updateCityName(for: location) { continuation.resume(returning: $0) }
        }
        fetchPrayerTimes(cameFrom: "Settings Refresh Location")
        guard let city else { return .failure(RefreshFailure(message: "Couldn't find your city")) }
        return .success(city)
    }

    /// Writes the app-group `lastLatitude` / `lastLongitude` only when they actually moved. Every
    /// write to that suite invalidates every @AppStorage bound to it (Settings, the root), so
    /// rewriting the same coordinate on each prayer-time calculation re-rendered them for nothing.
    func storeLastCoordinate(_ c: CLLocationCoordinate2D) {
        // ~50 m: GPS jitter is metres per fix and can't change prayer times or the qibla.
        if abs(lastLatitude - c.latitude) > 5e-4 { lastLatitude = c.latitude }
        if abs(lastLongitude - c.longitude) > 5e-4 { lastLongitude = c.longitude }
    }
}
