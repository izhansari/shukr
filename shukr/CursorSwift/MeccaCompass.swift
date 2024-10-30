import SwiftUI
import CoreLocation

struct MeccaCompass: View {
    @StateObject private var locationManager = LocationManager()
    
    // Mecca coordinates
    private let meccaLatitude = 21.4225
    private let meccaLongitude = 39.8262
    
    var body: some View {
        VStack {
            Spacer()
            
            // Compass arrow
            Image(systemName: "arrow.up")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .foregroundColor(.green)
                .rotationEffect(Angle(degrees: calculateQiblaDirection()))
                .animation(.linear, value: locationManager.compassHeading)
            
            Spacer()
            
            Text("Qibla Direction")
                .font(.title)
                .padding()
            
            if let location = locationManager.location {
                Text("Current Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    .font(.caption)
            } else {
                Text("Locating...")
                    .font(.caption)
            }
        }
        .onAppear {
            locationManager.startUpdating()
        }
    }
    
    private func calculateQiblaDirection() -> Double {
        guard let userLocation = locationManager.location else { return 0 }
        
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLong = userLocation.coordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180
        
        let y = sin(meccaLong - userLong)
        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
        
        var qiblaDirection = atan2(y, x) * 180 / .pi
        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
        
        return qiblaDirection - locationManager.compassHeading
    }
}

// Location Manager class to handle Core Location
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var compassHeading: Double = 0
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        compassHeading = newHeading.magneticHeading
    }
}

#Preview {
    MeccaCompass()
}
