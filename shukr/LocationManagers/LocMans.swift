//
//  LocMans.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/30/25.
//

import SwiftUI
import CoreLocation
import WidgetKit
import Combine

//used by pulseCircle
struct QiblaSettings {
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) static var alignmentThreshold: Double = 3.5
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 15.0 // More forgiving

    /// Older builds' Settings page saved the value to the standard suite while this read the app
    /// group, so the stepper never took. Carry a value set back then over, once.
    static func migrateFromStandardDefaultsIfNeeded() {
        guard let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"),
              group.object(forKey: "qibla_sensitivity") == nil,
              let old = UserDefaults.standard.object(forKey: "qibla_sensitivity") as? Double else { return }
        group.set(old, forKey: "qibla_sensitivity")
    }
}

//MARK: - Env Location Manager
/// (merged MainCircleLocationManager into GlobalLocationManager)

/// The compass stream: heading and qibla, many updates a second on a phone. Its own object so
/// only the views that draw the compass (`@EnvironmentObject var compass: CompassState`)
/// re-render per update. It used to be two @Published properties on EnvLocationManager, which
/// the root view holds as @StateObject — so every heading tick re-rendered the whole app
/// (Settings, the pager, the chrome), which is what made every Menu picker flicker on the
/// phone (2026-09-25). No compass in the simulator, so it never showed there.
final class CompassState: ObservableObject {
    @Published var heading: Double = 0
    @Published var qibla: (aligned: Bool, heading: Double) = (false, 0)
}

class EnvLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate { //locman_flag used for the compass in MainCircle and with injection on @Main
    @ObservationIgnored let manager = CLLocationManager()
    
    // Location and Heading Data
    /// Not @Published: no view reads it (the qibla math does), and the root view observes this
    /// object — publishing every GPS fix re-rendered the whole app once a second. PrayerViewModel
    /// follows fixes through `locationUpdates` instead.
    var userLocation: CLLocation?
    let locationUpdates = PassthroughSubject<CLLocation?, Never>()
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// A city the user picked instead of sharing their location (App Review tests denial, and
    /// prayer times shouldn't need GPS). Its coordinate lives in the app group's lastLatitude /
    /// lastLongitude, which the widget already reads. GPS wins whenever it's authorized.
    @Published private(set) var hasManualLocation: Bool =
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.bool(forKey: "manualLocation") ?? false
    /// GPS when authorized, otherwise the picked city.
    var effectiveLocation: CLLocation? {
        if isAuthorized, let gps = manager.location { return gps }
        return manualLocation
    }
    private var manualLocation: CLLocation? {
        guard hasManualLocation, let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") else { return nil }
        return CLLocation(latitude: group.double(forKey: "lastLatitude"), longitude: group.double(forKey: "lastLongitude"))
    }
    /// Heading + qibla live here (see CompassState). Not @Published on this object on purpose.
    let compass = CompassState()
    var compassHeading: Double { compass.heading }
    var qibla: (aligned: Bool, heading: Double) { compass.qibla }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = /*kCLLocationAccuracyBest*/ kCLLocationAccuracyNearestTenMeters
        manager.headingFilter = 1   // degrees; no delegate call for sub-degree jitter
//        startLocationServices()
    }
    
    // Modify this method to be called explicitly
    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    // CL Location Manager Delegate method for authorization changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationServices()
    }
    
    /// Use a picked city for prayer times and the qibla (see `hasManualLocation`).
    func setManualLocation(_ coordinate: CLLocationCoordinate2D, name: String) {
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        group?.set(coordinate.latitude, forKey: "lastLatitude")
        group?.set(coordinate.longitude, forKey: "lastLongitude")
        group?.set(name, forKey: "lastCityName")
        group?.set(true, forKey: "manualLocation")
        hasManualLocation = true
        if !isAuthorized { useManualLocation() }
    }

    /// Feed the picked city through the same path a GPS fix takes. The compass works without
    /// location permission, so the qibla still turns.
    private func useManualLocation() {
        guard let location = manualLocation else { return }
        userLocation = location
        locationUpdates.send(location)
        manager.startUpdatingHeading()
        updateQibla()
    }

    // Function to start location services
    func startLocationServices() {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "locationWasAuthorized")
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        case .notDetermined:
            isAuthorized = false
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isAuthorized = false
            print("Location services are denied or restricted.")
            // Location was on and has just been turned off: drop the picked city so the
            // welcome screen asks again — the best chance of getting it back. Someone who
            // denied from the start and picked a city keeps it.
            let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
            if group?.bool(forKey: "locationWasAuthorized") == true {
                group?.set(false, forKey: "locationWasAuthorized")
                group?.set(false, forKey: "manualLocation")
                hasManualLocation = false
            }
            useManualLocation()
        @unknown default:
            isAuthorized = false
            print("Unknown authorization status.")
        }
    }

    // Function to explicitly start updating location and heading
    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    // CL Location Manager Delegate method for location updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last
        locationUpdates.send(locations.last)
        updateQibla()
    }
    
    // CL Location Manager Delegate method for heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard abs(newHeading.magneticHeading - compass.heading) >= 0.5 else { return }
        compass.heading = newHeading.magneticHeading
        updateQibla()
    }
    
    // Error handling for location updates
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
    }
    
    // Updates the stored Qibla heading when location/heading changes
    private func updateQibla() {
        let qiblaHeading = calculateQiblaDirection()
        let qiblaAligned = abs(qiblaHeading) <= QiblaSettings.alignmentThreshold
        compass.qibla = (qiblaAligned, qiblaHeading)
    }

    func calculateQiblaDirection() -> Double {
        guard let userLocation = userLocation else { return 0 }
        let meccaLatitude = 21.4225
        let meccaLongitude = 39.8262
        
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLong = userLocation.coordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180
        
        let y = sin(meccaLong - userLong)
        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
        
        var qiblaDirection = atan2(y, x) * 180 / .pi
        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
        
        let returnVal = qiblaDirection - compassHeading
        
        return returnVal
    }
}

//@Observable
//class EnvLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate { //locman_flag used for the compass in MainCircle and with injection on @Main
//    @ObservationIgnored let manager = CLLocationManager()
//    
//    // Location and Heading Data
//    @Published var userLocation: CLLocation?
//    @Published var compassHeading: Double = 0
//    @Published var isAuthorized: Bool = false
//    @Published var qibla: (aligned: Bool, heading: Double) = (false, 0) // Stores the latest Qibla data
//
//    override init() {
//        super.init()
//        manager.delegate = self
//        manager.desiredAccuracy = /*kCLLocationAccuracyBest*/ kCLLocationAccuracyNearestTenMeters
//        startLocationServices()
//    }
//    
//    // CL Location Manager Delegate method for authorization changes
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        startLocationServices()
//    }
//    
//    // Function to start location services
//    func startLocationServices() {
//        switch manager.authorizationStatus {
//        case .authorizedAlways, .authorizedWhenInUse:
//            isAuthorized = true
//            manager.startUpdatingLocation()
//            manager.startUpdatingHeading()
//        case .notDetermined:
//            isAuthorized = false
//            manager.requestWhenInUseAuthorization()
//        case .denied, .restricted:
//            isAuthorized = false
//            print("Location services are denied or restricted.")
//        @unknown default:
//            isAuthorized = false
//            print("Unknown authorization status.")
//        }
//    }
//
//    // Function to explicitly start updating location and heading
//    func startUpdating() {
//        manager.requestWhenInUseAuthorization()
//        manager.startUpdatingLocation()
//        manager.startUpdatingHeading()
//    }
//    
//    // CL Location Manager Delegate method for location updates
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        userLocation = locations.last
//        updateQibla()
//    }
//    
//    // CL Location Manager Delegate method for heading updates
//    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
//        compassHeading = newHeading.magneticHeading
//        updateQibla()
//    }
//    
//    // Error handling for location updates
//    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//        print("Location Manager failed with error: \(error.localizedDescription)")
//    }
//    
//    // Updates the stored Qibla heading when location/heading changes
//    private func updateQibla() {
//        let qiblaHeading = calculateQiblaDirection()
//        let qiblaAligned = abs(qiblaHeading) <= QiblaSettings.alignmentThreshold
//        qibla = (qiblaAligned, qiblaHeading)
//    }
//
//    func calculateQiblaDirection() -> Double {
//        guard let userLocation = userLocation else { return 0 }
//        let meccaLatitude = 21.4225
//        let meccaLongitude = 39.8262
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - compassHeading
//        
//        return returnVal
//    }
//}


//MARK: - Prayer Widget Location Manager

class PrayersWidgetLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate { //locman_flag used in the widget.
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var heading: Double = 0
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var locationName: String = "Unknown Location"
    
    @AppStorage("lastCityName", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastCityName: String = "Wonderland"
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingHeading()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        geocodeLocation(location) // Perform reverse geocoding
//        updateCityName(for: location)
//        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
    }
    
    private func geocodeLocation(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Geocoding failed with error: \(error.localizedDescription)")
                self.locationName = "ran error"
                return
            }
            
            if let placemark = placemarks?.first {
                let cityName = placemark.locality ?? placemark.administrativeArea
                self.locationName = cityName ?? "if Unknown"
                
                if let widgetCityName = cityName {
                    let oldCityName = self.lastCityName
                    self.lastCityName = widgetCityName
                    if oldCityName != self.lastCityName {
                        WidgetCenter.shared.reloadAllTimelines()
                        print("Widget 🏙️ Geocoded City: \(self.lastCityName)")
                    }
                }

//                print("Widget 🏙️ Geocoded City: \(self.locationName)")
            } else {
                self.locationName = "else unknown"
                print("No placemarks found")
            }
        }
    }
    
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            guard let self = self else { return }
//
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Widget ❌ Reverse geocoding error: \(error.localizedDescription)")
//                    self.locationName = "xUnknown Location"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    self.locationName = newCityName
//                    print("Widget 🏙️ Geocoded City: \(newCityName)")
//                } else {
//                    self.locationName = "Unknown"
//                    print("Widget ⚠️ No placemark found")
//                }
//            }
//        }
//    }

    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        locationName = "fail error"
    }
}
