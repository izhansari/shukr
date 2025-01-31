//
//  LocMans.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/30/25.
//

import SwiftUI
import CoreLocation
import WidgetKit

//used by pulseCircle
struct QiblaSettings {
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) static var alignmentThreshold: Double = 3.5
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 15.0 // More forgiving
}

// merged MainCircleLocationManager into GlobalLocationManager
//@Observable
class EnvLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate { //locman_flag used for the compass in MainCircle and with injection on @Main
    @ObservationIgnored let manager = CLLocationManager()
    
    // Location and Heading Data
    @Published var userLocation: CLLocation?
    @Published var compassHeading: Double = 0
    @Published var isAuthorized: Bool = false
    @Published var qibla: (aligned: Bool, heading: Double) = (false, 0) // Stores the latest Qibla data

//    var qibla: (aligned: Bool, heading: Double){
//        let qiblaHeading = calculateQiblaDirection()
//        let qiblaAligned = abs(qiblaHeading) <= QiblaSettings.alignmentThreshold
//        return (qiblaAligned, qiblaHeading)
//    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        startLocationServices()
    }
    
    // CL Location Manager Delegate method for authorization changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
        startLocationServices()
    }
    
    // Function to start location services
    func startLocationServices() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        case .notDetermined:
            isAuthorized = false
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isAuthorized = false
            print("Location services are denied or restricted.")
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
        updateQibla()
    }
    
    // CL Location Manager Delegate method for heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        compassHeading = newHeading.magneticHeading
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
        qibla = (qiblaAligned, qiblaHeading)
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
        WidgetCenter.shared.reloadTimelines(ofKind: "PrayersWidget")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        geocodeLocation(location) // Perform reverse geocoding
//        updateCityName(for: location)
//        WidgetCenter.shared.reloadTimelines(ofKind: "PrayersWidget")
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
