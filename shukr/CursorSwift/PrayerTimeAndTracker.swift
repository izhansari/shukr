import SwiftUI
import Adhan
import CoreLocation
import SwiftData

@Model
class PrayerModel {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String // e.g., "Fajr", "Dhuhr"
    var startTime: Date
    var dateAtMake: Date
    var endTime: Date
    var isCompleted: Bool = false
    var latPrayedAt: Double? // lat where the prayer was performed (Cant store CLLocation in swiftdata)
    var longPrayedAt: Double? // long where the prayer was performed
    var prayerStartedAt: Date? // When the prayer was started
    var prayerCompletedAt: Date? // When the prayer was marked complete
    var duration: TimeInterval? // How long the prayer lasted
    var timeAtComplete: Date? // Exact timestamp of marking completion
    var numberScore: Double? // Numerical performance score
    var englishScore: String? // Descriptive performance score (e.g., "Good", "Poor")

    init(
        name: String,
        startTime: Date,
        endTime: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        dateAtMake: Date = .now
    ) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.latPrayedAt = latitude
        self.longPrayedAt = longitude
        self.dateAtMake = dateAtMake
    }
}

class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let context: ModelContext

    @Published var prayers: [PrayerModel] = [] {
        didSet {
            // Notify that prayers have been updated
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
        }
    }
    @AppStorage("calculationMethod") var calculationMethod: Int = 4
    @AppStorage("school") var school: Int = 0
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var hasValidLocation: Bool = false
    @Published var cityName: String?
    @Published var latitude: String = "N/A"
    @Published var longitude: String = "N/A"
    @Published var lastApiCallUrl: String = "N/A"
    @Published var useTestPrayers: Bool = false  // Add this property
    
    @Published var locationPrints: Bool = false
    let fetchPrints = true
    
    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()
    private var lastGeocodeRequestTime: Date?
    private var lastAppLocation: CLLocation?


    // Inject the ModelContext in the initializer
    init(context: ModelContext) {
        self.context = context
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
        
        // Load persisted prayers
        self.loadPersistedPrayers()
        
        print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>PrayerViewModel initialized")
    }
    
    
    func locationPrinter(_ message: String) {
        locationPrints ? print(message) : ()
    }

    
    private func loadPersistedPrayers() {
        do {
            // Define a FetchDescriptor with a sort order
            let fetchDescriptor = FetchDescriptor<PrayerModel>(
                sortBy: [
                    SortDescriptor(\.startTime, order: .forward) // Sort by startTime in ascending order
                ]
            )
            
            // Fetch prayers using the fetch descriptor
            let persistedPrayers: [PrayerModel] = try context.fetch(fetchDescriptor)
            
            DispatchQueue.main.async {
                self.prayers = persistedPrayers
            }
        } catch {
            locationPrinter("❌ Failed to fetch persisted prayers: \(error.localizedDescription)")
        }
    }

    
    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            locationAuthorizationStatus = .denied
            hasValidLocation = false
        case .authorizedWhenInUse, .authorizedAlways:
            locationAuthorizationStatus = .authorizedWhenInUse
            if let location = locationManager.location {
                hasValidLocation = true
                fetchPrayerTimes()
                updateCityName(for: location)
            } else {
                hasValidLocation = false
            }
        @unknown default:
            hasValidLocation = false
        }
    }

    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let deviceLocation = locations.last else {
            locationPrinter(">passed by the didUpdateLocation< - No location found")
            return
        }

        let now = Date()
        if let appLocation = lastAppLocation {
            let distanceChange = appLocation.distance(from: deviceLocation)
            if let lastRequestTime = lastGeocodeRequestTime {
                if distanceChange < 50, now.timeIntervalSince(lastRequestTime) < 30 {
                    // Only print if the update is skipped
                    return
                } else {
                    locationPrinter("📍 New Location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | \(Int(now.timeIntervalSince(lastRequestTime))) > 30s?")
                }
            } else {
                locationPrinter("📍 New Location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | First geocoding request")

            }
        } else {
            locationPrinter("⚠️ First location update. Proceeding with geocoding.")
        }

        // If checks pass, update location and proceed with geocoding
        updateLocation(deviceLocation)
    }


    private func updateLocation(_ location: CLLocation) {
        hasValidLocation = true
        latitude = String(format: "%.6f", location.coordinate.latitude)
        longitude = String(format: "%.6f", location.coordinate.longitude)

        // Update the last geocode request time and last updated location
        lastGeocodeRequestTime = Date()
        lastAppLocation = location

        locationPrinter("🌍 Triggering geocoding and prayer times fetch...")
        updateCityName(for: location)
        fetchPrayerTimes()
    }


    private func updateCityName(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.locationPrinter("❌ Reverse geocoding error: \(error.localizedDescription)")
                    self?.cityName = "Error fetching city"
                    return
                }

                if let placemark = placemarks?.first {
                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                    self?.locationPrinter("🏙️ Geocoded City: \(newCityName)")
                    self?.cityName = newCityName
                } else {
                    self?.locationPrinter("⚠️ No placemark found")
                    self?.cityName = "Unknown"
                }
            }
        }
    }

//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -60*60*3, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
////                        var testPrayers = [
////                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 2, to: now) ?? now),
////                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 2, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 4, to: now) ?? now),
////                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 4, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 6, to: now) ?? now),
////                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 6, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 8, to: now) ?? now),
////                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 8, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 10, to: now) ?? now)
////                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }

    
    // the current one im working on.
    func fetchPrayerTimes() {
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }

        // Update latitude and longitude
        self.latitude = String(format: "%.6f", location.coordinate.latitude)
        self.longitude = String(format: "%.6f", location.coordinate.longitude)

        // Format the current date
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()

        // Map calculationMethod and school to Adhan enums
        let adhanCalculationMethod: CalculationMethod? = {
            switch self.calculationMethod {
            case 1: return .karachi
            case 2: return .northAmerica
            case 3: return .muslimWorldLeague
            case 4: return .ummAlQura
            case 5: return .egyptian
            case 7: return .tehran
            case 8: return .dubai
            case 9: return .kuwait
            case 10: return .qatar
            case 11: return .singapore
            case 12: return .other
            case 13: return .turkey
            case 14: return .other
            default: return nil
            }
        }()

        let adhanMadhab: Madhab? = {
            switch self.school {
            case 0: return .shafi
            case 1: return .hanafi
            default: return nil
            }
        }()

        guard let calculationMethod = adhanCalculationMethod, let madhab = adhanMadhab else {
            print("Invalid calculation method or madhab")
            return
        }

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        var params = calculationMethod.params
        params.madhab = madhab

        // Generate prayer times for the current date
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        if let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
            do {
                // Fetch prayers for the current day from the context
                let fetchDescriptor = FetchDescriptor<PrayerModel>(
                    predicate: #Predicate { prayer in
                        prayer.startTime >= todayStart && prayer.startTime <= todayEnd
                    }
                )
                let existingPrayers = try self.context.fetch(fetchDescriptor)
                

                // Define prayer names and times
                let prayerInfo = [
                    ("Fajr", prayerTimes.fajr, prayerTimes.sunrise),
                    ("Dhuhr", prayerTimes.dhuhr, prayerTimes.asr),
                    ("Asr", prayerTimes.asr, prayerTimes.maghrib),
                    ("Maghrib", prayerTimes.maghrib, prayerTimes.isha),
                    ("Isha", prayerTimes.isha, calendar.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
                ]

                for (name, startTime, endTime) in prayerInfo {
                    if let existingPrayer = existingPrayers.first(where: { $0.name == name }) {
                        // Update existing prayer if not completed
                        if !existingPrayer.isCompleted {
                            if existingPrayer.startTime != startTime || existingPrayer.endTime != endTime {
                                print("Overwriting Prayer: Name: \(name)")
                                if existingPrayer.startTime != startTime {
                                    print("Changed Start: \(startTime) (old \(existingPrayer.startTime))")
                                    existingPrayer.startTime = startTime
                                }
                                if existingPrayer.endTime != endTime {
                                    print("Changed End: \(endTime) (old \(existingPrayer.endTime))")
                                    existingPrayer.endTime = endTime
                                }
                            }
                        }
                    } else {
                        // Insert new prayer
                        let newPrayer = PrayerModel(
                            name: name,
                            startTime: startTime,
                            endTime: endTime
                        )
                        self.context.insert(newPrayer)
                    }
                }
                print("\(calculationMethod) & \(madhab) & \(coordinates)")

                // Save changes
                self.saveChanges()
                self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.startTime })

            } catch {
                print("❌ Error fetching existing prayers: \(error.localizedDescription)")
            }
        }
    }

    
    // okay now this matches our current settings so its dynamic. but some of the calculation methods from AlAdhan arent in Adhan
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Format the current date
//        let calendar = Calendar.current
//        let todayStart = calendar.startOfDay(for: Date())
//        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
//
//        // Map calculationMethod and school to Adhan enums
//        let adhanCalculationMethod: CalculationMethod? = {
//            switch self.calculationMethod {
//            case 1: return .karachi
//            case 2: return .northAmerica
//            case 3: return .muslimWorldLeague
//            case 4: return .ummAlQura
//            case 5: return .egyptian
//            case 7: return .tehran
//            case 8: return .dubai
//            case 9: return .kuwait
//            case 10: return .qatar
//            case 11: return .singapore
//            case 12: return .other // Union Organization Islamic de France (customizable)
//            case 13: return .turkey
//            case 14: return .other // Spiritual Administration of Muslims of Russia (customizable)
//            default: return nil
//            }
//        }()
//
//        let adhanMadhab: Madhab? = {
//            switch self.school {
//            case 0: return .shafi
//            case 1: return .hanafi
//            default: return nil
//            }
//        }()
//
//        guard let calculationMethod = adhanCalculationMethod, let madhab = adhanMadhab else {
//            print("Invalid calculation method or madhab")
//            return
//        }
//
//        // Set up Adhan parameters
//        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
//        var params = calculationMethod.params
//        params.madhab = madhab
//
//        // Generate prayer times for the current date
//        let components = calendar.dateComponents([.year, .month, .day], from: Date())
//        if let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
//            let fetchedPrayers = [
//                PrayerModel(name: "Fajr", startTime: prayerTimes.fajr, endTime: prayerTimes.sunrise),
//                PrayerModel(name: "Dhuhr", startTime: prayerTimes.dhuhr, endTime: prayerTimes.asr),
//                PrayerModel(name: "Asr", startTime: prayerTimes.asr, endTime: prayerTimes.maghrib),
//                PrayerModel(name: "Maghrib", startTime: prayerTimes.maghrib, endTime: prayerTimes.isha),
//                PrayerModel(name: "Isha", startTime: prayerTimes.isha, endTime: calendar.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//            ]
//
//            do {
//                let fetchDescriptor = FetchDescriptor<PrayerModel>(
//                    predicate: #Predicate { prayer in
//                        prayer.startTime >= todayStart && prayer.startTime <= todayEnd
//                    }
//                )
//                let existingPrayers = try self.context.fetch(fetchDescriptor)
//
//                // Update or insert prayers
//                for fetched in fetchedPrayers {
//                    if let existingPrayer = existingPrayers.first(where: { $0.name == fetched.name }) {
//                        // Update existing prayer if not completed
//                        if !existingPrayer.isCompleted {
//                            existingPrayer.startTime = fetched.startTime
//                            existingPrayer.endTime = fetched.endTime
//                        }
//                    } else {
//                        // Insert new prayer
//                        let newPrayer = PrayerModel(
//                            name: fetched.name,
//                            startTime: fetched.startTime,
//                            endTime: fetched.endTime,
//                            dateAtMake: Date() // Track when it was added
//                        )
//                        self.context.insert(newPrayer)
//                    }
//                }
//
//                // Save changes
//                self.saveChanges()
//                self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.startTime })
//
//            } catch {
//                print("❌ Error fetching existing prayers: \(error.localizedDescription)")
//            }
//        }
//    }

    // successfully used a fetch descriptor and update the items directly instead of replacing.
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Format the current date
//        let calendar = Calendar.current
//        let todayStart = calendar.startOfDay(for: Date())
//        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
//
//        // Make the API call URL
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd"
//        let currentDateString = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDateString)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        self.lastApiCallUrl = urlString
//
//        // Perform the API call
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//
//                        // Parse the fetched prayers
//                        let fetchedPrayers = [
//                            PrayerModel(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            PrayerModel(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            PrayerModel(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            PrayerModel(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            PrayerModel(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        // Fetch prayers for the current day from the context
//                        let fetchDescriptor = FetchDescriptor<PrayerModel>(
//                            predicate: #Predicate { prayer in
//                                prayer.startTime >= todayStart && prayer.startTime <= todayEnd
//                            }
//                        )
//
//                        do {
//                            let existingPrayers = try self.context.fetch(fetchDescriptor)
//
//                            // Update or insert prayers
//                            for fetched in fetchedPrayers {
//                                if let existingPrayer = existingPrayers.first(where: { $0.name == fetched.name }) {
//                                    // Update existing prayer if not completed
//                                    if !existingPrayer.isCompleted {
//                                        existingPrayer.startTime = fetched.startTime
//                                        existingPrayer.endTime = fetched.endTime
//                                    }
//                                } else {
//                                    // Insert new prayer
//                                    let newPrayer = PrayerModel(
//                                        name: fetched.name,
//                                        startTime: fetched.startTime,
//                                        endTime: fetched.endTime,
//                                        dateAtMake: Date() // Track when it was added
//                                    )
//                                    self.context.insert(newPrayer)
//                                }
//                            }
//
//                            // Save changes
//                            self.saveChanges()
//                            self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.startTime })
//
//                        } catch {
//                            print("❌ Error fetching existing prayers: \(error.localizedDescription)")
//                        }
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }

    
    
//    func fetchPrayerTimes() {
//        // get a location.
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // format the date for the api call
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        // make the api call url
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        
//        // check if url is valid
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        
//        self.lastApiCallUrl = urlString
//
//        // enter url session. get acc data from api call.
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            // catch any errors
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                // boil down the data to get the timings.
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let fetchedPrayers = [
//                            PrayerModel(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            PrayerModel(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            PrayerModel(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            PrayerModel(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            PrayerModel(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        var prayersToShow: [PrayerModel] = []
//
//                        for fetched in fetchedPrayers {
//                            
//                            if let existingPrayer = self.prayers.first(where: {
//                                $0.name == fetched.name &&
//                                Calendar.current.isDate($0.startTime, inSameDayAs: fetched.startTime)
//                                }) {
//                                if existingPrayer.startTime > now {
//                                    // Replace future prayers with new ones
//                                    prayersToShow.append(fetched) // lets maybe change this to just make the existingPrayer to equal fetched self.prayer
//                                } else {
//                                    // Retain past and completed prayers
//                                    prayersToShow.append(existingPrayer)
//                                }
//                            } else {
//                                // If no prayer exists for the same name and date, save the new prayer
//                                prayersToShow.append(fetched)
//                                self.context.insert(fetched) // Add to the context
//                            }
//                            
//                        }
//
//                        self.prayers = prayersToShow.sorted(by: { $0.startTime < $1.startTime })
//                        
//                        print("\(self.calculationMethod) & \(self.school) & \(self.cityName ?? "(no city)")")
//                        // Persist changes
//                        self.saveChanges()
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }

    
    
    private func parseTime(_ timeString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Set the formatter's time zone to the current time zone
        formatter.timeZone = TimeZone.current
        locationPrinter("from parseTime: \(TimeZone.current)")

        // Parse the time string
        guard let time = formatter.date(from: timeString) else {
            return Date()
        }

        // Get the current calendar
        let calendar = Calendar.current
        let now = Date()

        // Extract hour and minute from the parsed time
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        // Combine the current date with the parsed time
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                             minute: timeComponents.minute ?? 0,
                             second: 0,
                             of: now) ?? now
    }

    // new way. doesnt use index. so no need to parse through database. was using index = prayers.firstIndex(where: { $0.id == prayer.id })
    func togglePrayerCompletion(for prayer: PrayerModel) {
        triggerSomeVibration(type: .medium)
        
            if prayer.startTime <= Date() {
                prayer.isCompleted.toggle()
                if prayer.isCompleted {
                    setPrayerScore(for: prayer)
                } else {
                    prayer.timeAtComplete = nil
                    prayer.numberScore = nil
                    prayer.englishScore = nil
                }

                // Persist the changes (swiftdata saves automatically for us.)
            }
        
    }
    
    
    private var saveTimer: Timer?

    private func scheduleSaveChanges() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.saveChanges()
        }
    }
    
    private func saveChanges() {
        do {
            try context.save()
            print("✅ Prayer state saved successfully")
        } catch {
            print("❌ Failed to save prayer state: \(error.localizedDescription)")
        }
    }


    // CLLocationManagerDelegate method
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func fetchAndPrintCity() {
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }
        updateCityName(for: location)
    }

    func getColorForPrayerScore(_ score: Double?) -> Color {
        guard let score = score else { return .gray }

        if score >= 0.50 {
            return .green
        } else if score >= 0.25 {
            return .yellow
        } else if score > 0 {
            return .red
        } else {
            return .gray
        }
    }

    // new way directly writes on the prayer. old way used an index.
    func setPrayerScore(for prayer: PrayerModel) {
        print("setting time at complete as: ", Date())
        prayer.timeAtComplete = Date()

        if let completedTime = prayer.timeAtComplete {
            let timeLeft = prayer.endTime.timeIntervalSince(completedTime)
            let totalInterval = prayer.endTime.timeIntervalSince(prayer.startTime)
            let score = timeLeft / totalInterval
            prayer.numberScore = max(0, min(score, 1))

            if let percentage = prayer.numberScore {
                if percentage > 0.50 {
                    prayer.englishScore = "Optimal"
                } else if percentage > 0.25 {
                    prayer.englishScore = "Good"
                } else if percentage > 0 {
                    prayer.englishScore = "Poor"
                } else {
                    prayer.englishScore = "Kaza"
                }
            }
        }
    }

    
}



class SharedStateClass: ObservableObject {
    @Published var selectedViewPage: Int = 1
    @Published var selectedMode: Int = 2
    @Published var selectedMinutes: Int = 0
    @Published var targetCount: String = ""
    @Published var titleForSession: String = ""
    @Published var showTopMainOrBottom: Int = 0 // 1 for top, 0 for default, -1 for bottom
    @Published var isDoingPostNamazZikr: Bool = false
    @Published var showingOtherPages: Bool = false
}


struct PrayerTimesView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    //@StateObject private var viewModel: PrayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @FocusState private var isNumberEntryFocused

    @Environment(\.modelContext) var context
    @Query private var prayersFromPersistence: [PrayerModel] = []
    @State private var last5Prayers: [PrayerModel] = []

    

    
    @State private var relevantPrayerTimer: Timer? = nil
    @State private var timeDisplayTimer: Timer? = nil
    @State private var activeTimerId: UUID? = nil
    @State private var showBottom: Bool = false
    @State private var showTop: Bool = false
    @State private var dragOffset: CGFloat = 0.0
    @State private var showTasbeehPage = false // State to control full-screen cover
    @State private var showMantraSheetFromHomePage: Bool = false
    @State private var chosenMantra: String? = ""
    @State private var isAnimating: Bool = false
    @State private var showChainZikrButton: Bool = false
    //    @GestureState private var dragOffset: CGFloat = 0.0
    //    @State private var showingDuaPage: Bool = false
    //    @State private var showingHistoryPage: Bool = false
    //    @State private var showingTasbeehPage: Bool = false
    
    let schedulePrints = false
    
//    init(viewModel: PrayerViewModel) {
//         self._viewModel = StateObject(wrappedValue: viewModel)
//     }

    
    private var startCondition: Bool{
        let timeModeCond = (sharedState.selectedMode == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedMode == 0)
        return (timeModeCond || countModeCond || freestyleModeCond)
    }
    
    func schedulePrinter(_ message: String) {
        schedulePrints ? print(message) : ()
    }

    private func scheduleNextTransition() {
        // Cancel any existing timer to avoid duplicates
        relevantPrayerTimer?.invalidate()

        let now = Date()
        schedulePrinter("\n--- Scheduling Check at \(formatTime(now)) ---")
        schedulePrinter("Number of prayers: \(viewModel.prayers.count)") // Debug: Check if prayers array is empty
        
        guard !viewModel.prayers.isEmpty else {
            schedulePrinter("⚠️ No prayers available yet")
            return
        }
        
        // Find the next transition time from all prayers
        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
            if !prayer.isCompleted && prayer.startTime > now { // If prayer hasn't started and isn't completed
                schedulePrinter("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
                return prayer.startTime
            } else if !prayer.isCompleted && prayer.endTime > now { // If prayer is ongoing and isn't completed
                schedulePrinter("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
                return prayer.endTime
            }
            schedulePrinter("Skipping \(prayer.name) - completed or past")
            return nil
        }.min()
        
        if let nextTime = nextTransition { // If we found a next transition time
            schedulePrinter("Scheduling next transition for: \(formatTime(nextTime))")
            
            relevantPrayerTimer = Timer.scheduledTimer(
                withTimeInterval: nextTime.timeIntervalSinceNow,
                repeats: false
            ) { _ in
                schedulePrinter("\n🔄 Timer fired at \(formatTime(Date()))")
                withAnimation { // Force view refresh when timer fires
                    self.viewModel.objectWillChange.send()
                }
                self.scheduleNextTransition() // Schedule the next transition
            }
        } else {
            schedulePrinter("⚠️ No more transitions to schedule today")
        }
    }
    
    var body: some View {
//        NavigationView {
            ZStack {
  
                Color("bgColor")
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0){
                    Color.white.opacity(0.001)
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            if isNumberEntryFocused {
                                isNumberEntryFocused = false
                            } else{
                                withAnimation/*(.spring(response: 0.3, dampingFraction: 0.7))*/ {
                                    !showBottom ? showTop.toggle() : (showBottom = false)
                                }
                            }
                        }
                    
                    Color.white.opacity(0.001)
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            if isNumberEntryFocused {
                                isNumberEntryFocused = false
                            } else{
                                withAnimation/*(.spring(response: 0.3, dampingFraction: 0.7))*/ {
                                    !showTop ? showBottom.toggle() : (showTop = false)
                                }
                            }
                        }
                }
                .padding(.horizontal, 40) // makes it so edges allow us to swipe main tab view at each edge
                .highPriorityGesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = calculateResistance(value.translation.height)
                        }
                        .onEnded { value in
                            handleDragEnd(translation: value.translation.height)
                        }
                )

                // This is a zstack with SwipeZikrMenu, pulseCircle, (and roundedrectangle just to push up.)
                ZStack {
                    VStack {
                        // state 1
                        if showTop {
                            // replace circle with tasbeehSelectionTabView
                            ZStack{
                                // the middle with a swipable selection
                                TabView (selection: $sharedState.selectedMode) {
                                    
                                    timeTargetMode(selectedMinutesBinding: $sharedState.selectedMinutes)
                                        .tag(1)
                                    
                                    countTargetMode(targetCount: $sharedState.targetCount, isNumberEntryFocused: _isNumberEntryFocused)
                                        .tag(2)

                                    freestyleMode()
                                        .tag(0)
                                }
                                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Enable paging
                                .scrollBounceBehavior(.always)
                                .frame(width: 200, height: 200) // Match the CircularProgressView size
                                .onChange(of: sharedState.selectedMode) {_, newPage in
                                    isNumberEntryFocused = false //Dismiss keyboard when switching pages
                                }
                                .onTapGesture {
                                    if(startCondition){
                                        showTasbeehPage = true // Set to true to show the full-screen cover
                                        triggerSomeVibration(type: .medium)
                                    }
                                    isNumberEntryFocused = false //Dismiss keyboard when tabview tapped
                                }
                                
                                // the circles we see
                                CircularProgressView(progress: (0))
                                
                                Circle()
                                    .stroke(lineWidth: 2)
                                    .frame(width: 222, height: 222)
                                    .foregroundStyle(startCondition ?
                                                     LinearGradient(
                                                        gradient: Gradient(colors: colorScheme == .dark ?
                                                                           [.yellow.opacity(0.6), .green.opacity(0.8)] :
                                                                            [.yellow, .green]
                                                                          ),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                     ) :
                                                        LinearGradient(
                                                            gradient: Gradient(colors: []),
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                    )
                                    .animation(.easeInOut(duration: 0.5), value: startCondition)

                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // state 2
                        if !showTop, let relevantPrayer = viewModel.prayers.first(where: {
                            !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() // current prayer if not completed
                        }) ?? viewModel.prayers.first(where: {
                            !$0.isCompleted && $0.startTime > Date() // next up prayer
                        }) ?? viewModel.prayers.first(where: {
                            !$0.isCompleted && $0.endTime < Date() // missed prayers
                        }) {
                            PulseCircleView(prayer: relevantPrayer) {
                                viewModel.togglePrayerCompletion(for: relevantPrayer)
                                scheduleNextTransition()
                            }
                            .transition(.blurReplace)
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = calculateResistance(value.translation.height)
                                    }
                                    .onEnded { value in
                                        handleDragEnd(translation: value.translation.height)
                                    }
                            )
                        }
                        else if !showTop{
                            ZStack{
                                CircularProgressView(progress: 0)
                                VStack{
                                    Text("done.")
//                                    Text("fajr is at 6:00")
//                                        .font(.caption)
                                }
                            }
                            
                        }
                        
                        // state 3
                        if showBottom {
                            // just for spacing to push it up.
                            RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
                                .fill(Color.clear)
                                .frame(width: 320, height: 250)
                        }
                    }
                    .offset(y: dragOffset)
                }
                .fullScreenCover(isPresented: $showTasbeehPage) {
                    tasbeehView(isPresented: $showTasbeehPage/*, autoStart: true*/)
                        .onAppear{
                            print("showNewPage (from tabview): \(showTasbeehPage)")
                        }
                        .transition(.blurReplace) // Apply fade-in effect
                }
                
                
                Group {
                    // in the case of having a valid location (everything except pulsecirlce):
                    if viewModel.hasValidLocation {
                        VStack {
                            // This ZStack holds the manraSelector, floatingChainZikrButton, and TopBar
                            ZStack(alignment: .top) {
                                // select mantra button (zikrFlag1)
                                if showTop{
                                    Text("\(sharedState.titleForSession != "" ? sharedState.titleForSession : "select zikr")")
                                        .frame(width: 150, height: 40)
                                        .font(.footnote)
                                        .fontDesign(.rounded)
                                        .fontWeight(.thin)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .background(.gray.opacity(0.08))
                                        .cornerRadius(10)
                                        .padding(.top, 50)
                                        .offset(y: dragOffset) // drags with finger
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                        .highPriorityGesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    dragOffset = calculateResistance(value.translation.height)
                                                }
                                                .onEnded { value in
                                                    handleDragEnd(translation: value.translation.height)
                                                }
                                        )
                                        .onTapGesture {
                                            showMantraSheetFromHomePage = true
                                        }
                                        .onChange(of: chosenMantra){
                                            if let newSetMantra = chosenMantra{
                                                sharedState.titleForSession = newSetMantra
                                            }
                                        }
                                        .sheet(isPresented: $showMantraSheetFromHomePage) {
                                            MantraPickerView(isPresented: $showMantraSheetFromHomePage, selectedMantra: $chosenMantra, presentation: [.large])
                                        }
                                }
                                
                                // floating chain zikr button
                                FloatingChainZikrButton(showTasbeehPage: $showTasbeehPage, showChainZikrButton: $showChainZikrButton)
                                
                                // top bar
                                TopBar(viewModel: viewModel,/* /*showingDuaPageBool: $showingDuaPage , showingHistoryPageBool: $showingHistoryPage, */showingTasbeehPageBool: $showingTasbeehPage, */showTop: $showTop, showBottom: $showBottom, dragOffset: dragOffset)
                                        .transition(.opacity)
                                
                            }
                                                        
                            Spacer()
                            
                            // This VStack holds the PrayerTracker list
                            VStack {
                                // expandable prayer tracker (dynamically shown)
                                if showBottom {
                                    let spacing: CGFloat = 6
                                    VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                                        ForEach(viewModel.prayers.indices, id: \.self) { index in
                                            let prayer = viewModel.prayers[index]
                                            
                                            PrayerButton(
                                                showChainZikrButton: $showChainZikrButton,
                                                prayer: prayer,
                                                toggleCompletion: {
                                                    viewModel.togglePrayerCompletion(for: prayer)
                                                    scheduleNextTransition()
                                                },
                                                viewModel: viewModel
                                            )
                                            
                                            .padding(.bottom, prayer.name == "Isha" ? 0 : spacing)
                                            
                                            if(prayer.name != "Isha"){
                                                Divider().foregroundStyle(.secondary)
                                                    .padding(.top, -spacing/2 - 0.5)
                                                    .padding(.horizontal, 25)
                                            }
                                        }
                                    }
                                    .padding()
                                    .background( NeumorphicBorder() )
                                    .frame(width: 260)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .highPriorityGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                dragOffset = calculateResistance(value.translation.height)
                                            }
                                            .onEnded { value in
                                                handleDragEnd(translation: value.translation.height)
                                            }
                                    )
                                }
                                
                                // chevron button to pull up the tracker.
                                if !showTop{
                                    Button(action: {
                                        withAnimation/*(.spring(response: 0.3, dampingFraction: 0.7))*/ {
                                            !showTop ? showBottom.toggle() : ()
                                        }
                                    }) {
                                        Image(systemName: /*showBottom ? "chevron.down" :*/ "chevron.up")
                                            .font(.title3)
                                            .foregroundColor(.gray)
                                            .scaleEffect(x: 1, y: dragOffset > 0 || showBottom ? -1 : 1)
                                            .padding(.bottom, 2)
                                            .padding(.top)
                                    }
                                }
                            }
                            .offset(y: dragOffset) // drags with finger
                        }
                        .navigationBarHidden(true)
                    }
                    // Page we get when they authorization for location has not been granted or denied
                    else if viewModel.locationAuthorizationStatus != .authorizedWhenInUse {
                        VStack {
                            Text("Location Access Required")
                                .font(.headline)
                                .padding()
                            Text("Please allow location access to fetch accurate prayer times.")
                                .multilineTextAlignment(.center)
                                .padding()
                            Button("Allow Location Access") {
                                viewModel.requestLocationAuthorization()
                            }
                            .padding()
                        }
                    }
                }

                
//                if(showingDuaPage){
//                    DuaPageView(/*showingDuaPageBool: $showingDuaPage*/)
//                        .transition(.move(edge: .leading))
//                        .zIndex(1)
//                }
//                if showingHistoryPage{
//                    HistoryPageView(/*showingHistoryPageBool: $showingHistoryPage*/)
//                        .transition(.move(edge: .trailing))
//                        .zIndex(1)
//                }
//                if showingTasbeehPage {
//                    tasbeehView(isPresented: $showNewPage, autoStart: false)
////                        .environmentObject(sharedState) // Inject sharedState into the environment
//                        .onAppear{
//                            print("showNewPage (from sidebar ): \(showNewPage)")
//                        }
//                    .transition(.blurReplace.animation(.easeInOut(duration: 0.4)))
//                        .zIndex(1) // Ensure it appears above other content
//                }
            }
            .onAppear {
//                sharedState.showingOtherPages = false
                 
////                do {
////                    prayersFromPersistence = try context.fetch(PrayerModel.fetchRequest())
//                    print("Number of prayers fetched: \(prayersFromPersistence.count)")
//                    
//                    // Loop through prayers and print their details
//                    for (index, prayer) in prayersFromPersistence.enumerated() {
//                        print("Prayer \(index + 1): \(prayer.name)")
//                        print("Start Time: \(prayer.startTime)")
//                        print("End Time: \(prayer.endTime)")
//                        print("---")
//                    }
////                } catch {
////                    print("Error fetching prayers: \(error.localizedDescription)")
////                }
                
                loadLast5Prayers()
                print(">F>F>F>F>F>F>F>F>F>F")
                print(last5Prayers.count)
                for (index, prayer) in last5Prayers.enumerated() {
                    print("Prayer \(index + 1): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(prayer.startTime) - \(prayer.endTime)")
                }

                
                if !viewModel.prayers.isEmpty { scheduleNextTransition() }
                NotificationCenter.default.addObserver(
                    forName: .prayersUpdated,
                    object: nil,
                    queue: .main
                ) { _ in
                    scheduleNextTransition()
                }
                switch sharedState.showTopMainOrBottom {
                    case 1:
                    showTop = true
                    showBottom = false
                case -1:
                    showTop = false
                    showBottom = true
                default:
                    showTop = false
                    showBottom = false
                }
                sharedState.showTopMainOrBottom = 0
            }
//            .onChange(of: showingDuaPage || showingHistoryPage || showingTasbeehPage){_, new in
////                sharedState.showingOtherPages = new
//            }
            .onDisappear {
                relevantPrayerTimer?.invalidate()
                relevantPrayerTimer = nil
                NotificationCenter.default.removeObserver(self)
                timeDisplayTimer?.invalidate()
                timeDisplayTimer = nil
            }
        //}
//        .navigationBarBackButtonHidden()
    }
    
    private func loadLast5Prayers() {
        do {
            var fetchDescriptor = FetchDescriptor<PrayerModel>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            fetchDescriptor.fetchLimit = 5
            
            last5Prayers = try context.fetch(fetchDescriptor)
            
            last5Prayers.reverse()
        } catch {
            print("❌ Failed to fetch prayers: \(error.localizedDescription)")
        }
    }
        
    private func handleDragEnd(translation: CGFloat) {
        let threshold: CGFloat = 30

        withAnimation(.bouncy(duration: 0.5)) {
            if !showBottom && !showTop {
                if translation > threshold {
                    showTop = true
                    triggerSomeVibration(type: .medium)
                } else if translation < -threshold {
                    showBottom = true
                    triggerSomeVibration(type: .medium)
                }
            } else if showBottom && !showTop {
                if translation > threshold {
                    showBottom = false
                    triggerSomeVibration(type: .medium)
                }
            } else if showTop && !showBottom {
                if translation < -threshold {
                    showTop = false
                    triggerSomeVibration(type: .medium)
                }
            }
            dragOffset = 0 // can't use this with a @GestureState (automatically resets)
        }

        print("translation: \(translation)")
    }
    
}
struct ContentView3_Previews: PreviewProvider {
    static var previews: some View {
        let sharedState = SharedStateClass()
        
        // Create a preview ModelContainer
        let previewModelContainer: ModelContainer = {
            let schema = Schema([
                PrayerModel.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer for preview: \(error)")
            }
        }()

        // Create a preview context
        let context = previewModelContainer.mainContext

        // Create a preview PrayerTimesView
        return PrayerTimesView()
            .environmentObject(sharedState)
    }
}

//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        PrayerTimesView()
//            .environmentObject(SharedStateClass()) // Inject the environment object here
//    }
//}

// Add notification name
extension Notification.Name {
    static let prayersUpdated = Notification.Name("prayersUpdated")
}

struct TopBar: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sharedState: SharedStateClass

    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var colorModeToggle = false

    let viewModel: PrayerViewModel
//    @Binding var showingDuaPageBool: Bool
//    @Binding var showingHistoryPageBool: Bool
//    @Binding var showingTasbeehPageBool: Bool
    @Binding var showTop: Bool
    @Binding var showBottom: Bool
    @GestureState var dragOffset: CGFloat
    
    @State private var expandButtons: Bool = false
    
    private var switchToTopLabel: Bool {
        ((dragOffset > 0 && !showBottom) || showTop)
    }
    
    private var tasbeehModeName: String {
        switch sharedState.selectedMode{
        case 0: return "Freestyle"
        case 1: return "Time Goal"
        case 2: return "Count Goal"
        default: return "Error on page name switch"
        }
    }

    
    var body: some View {
//        VStack(spacing: 0){
//            HStack(alignment: .center) {
//                
//                Image(systemName: "xmark")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray.opacity(0.001))
//                    .padding([.top, .leading, .trailing])
//
//                Spacer()
//                
//                if let cityName = viewModel.cityName {
//                    HStack {
//                        Image(systemName: "location.fill")
//                            .foregroundColor(.secondary)
//                        Text(cityName)
//                    }
//                    .font(.caption)
//                    .fontDesign(.rounded)
//                    .fontWeight(.thin)
//                    .padding([.top, .leading, .trailing])
//                } else {
//                    HStack {
//                        Image(systemName: "location.circle")
//                            .foregroundColor(.secondary)
//                        Text("Fetching location...")
//                    }
//                    .font(.caption)
//                    .fontDesign(.rounded)
//                }
//                
//                
//                
//                Spacer()
//                
//                
//                Button(action: {
//                    triggerSomeVibration(type: .light)
//                    withAnimation {
//                        expandButtons.toggle()
//                    }
//                }) {
//                    Image(systemName: "ellipsis.circle")
//                        .font(.system(size: 24))
//                        .foregroundColor(.gray.opacity(!expandButtons ? 0.3 : 1))
//                        .padding([.top, .leading, .trailing])
//                }
//                
//            }
//            .padding(.top, 8)
//            .padding(.bottom, 5)
//
//            HStack{
//                Spacer()
//                VStack (spacing: 0){
//                    if expandButtons{
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingTasbeehPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "circle.hexagonpath")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingDuaPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "book")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingHistoryPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "rectangle.stack")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                colorModeToggle.toggle()
//                            }
//                        }) {
//                            Image(systemName: colorModeToggle ? "moon.fill" : "sun.max.fill")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                            Image(systemName: "gear")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                    }
//                }
//                .padding(.trailing)
//                .opacity(0.7)
//            }
//        }
//        .padding(.horizontal)
        ZStack{
            VStack{
                if let cityName = viewModel.cityName {
                    VStack {
                        ZStack{
                                // tasbeeh label
                                HStack{
                                    Image(systemName: "circle.hexagonpath")
                                        .foregroundColor(.secondary)
                                    Text("Tasbeeh - \(tasbeehModeName)")

                                }
                                .opacity(switchToTopLabel ? 1 : 0)
                                .offset(y: switchToTopLabel ? 0 : -10)
                                
                                // location label
                                HStack{
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.secondary)
                                    Text(cityName)
                                }
                                .opacity(switchToTopLabel ? 0 : 1)
                                .offset(y: switchToTopLabel ? 10 : 0)
                            }
                        
                        
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .frame(height: 24, alignment: .center)
                    .offset(y: !showBottom && (dragOffset > 0 || showTop) ? dragOffset : 0)
                    .animation(.easeInOut, value: dragOffset > 0 && !showBottom)
                    
                } else {
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.secondary)
                        Text("Fetching location...")
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .frame(height: 24, alignment: .center)
                }
                
                Spacer()
            }
            .padding()
            
            VStack{
                HStack{
                    Spacer()

                        VStack (spacing: 0){
                            //// FIXME: eventually need to clean up the side bar since we no longer have the showing page booleans
                            
                            Button(action: {
                                triggerSomeVibration(type: .light)
                                withAnimation {
                                    expandButtons.toggle()
                                }
                            }) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray.opacity(!expandButtons ? 0.3 : 1))
                                    .padding(.bottom, 7)
                            }
                            
                            if expandButtons{
                                
//                                Button(action: {
//                                    triggerSomeVibration(type: .light)
//                                    withAnimation {
////                                        showingTasbeehPageBool = true
//                                        showBottom = false
//                                        showTop.toggle()
//                                    }
//                                }) {
//                                    Image(systemName: "circle.hexagonpath")
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                        .padding(.vertical, 7)
//                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
//                                        showingDuaPageBool = true
                                        sharedState.selectedViewPage = 2
                                    }
//                                    openLeftPage(proxy: proxy)
                                }) {
                                    Image(systemName: "book")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
//                                        showingHistoryPageBool = true
                                        sharedState.selectedViewPage = 0
                                    }
                                }) {
                                    Image(systemName: "rectangle.stack")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
                                        colorModeToggle.toggle()
                                    }
                                }) {
                                    Image(systemName: colorModeToggle ? "moon.fill" : "sun.max.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                NavigationLink(destination: LocationMapContentView()) {
                                    Image(systemName: "scribble")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                NavigationLink(destination: SeeAllPrayers()) {
                                    Image(systemName: "volleyball.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                NavigationLink(destination: AdhanTestView()) {
                                    Image(systemName: "basketball.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                NavigationLink(destination: SettingsView()) {
                                    Image(systemName: "gear")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                            }
                        }
                        .frame(width: 30)
                        .opacity(0.7)
                }
                Spacer()
            }.padding()
        }
        .preferredColorScheme(colorModeToggle ? .dark : .light)
    }
}

/*
 Things i added:
 - dimmer slider when inactivity toggle on
 - select mantra from pause screen
 -
 */

struct FloatingChainZikrButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @State private var chainButtonPressed = false
    @Binding var showTasbeehPage: Bool
    @Binding var showChainZikrButton: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                triggerSomeVibration(type: .success)
                chainButtonPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                chainButtonPressed = false
                sharedState.isDoingPostNamazZikr = true
                showTasbeehPage = true
                sharedState.showingOtherPages = true
            }
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.08))
                
                // Outline
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                
                // Content
                Text("post prayer zikr?")
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .foregroundColor(.primary)
            }
            .frame(width: 150, height: 50)
            .shadow(radius: 10)
            .scaleEffect(chainButtonPressed ? 0.95 : 1.0)
        }
        .padding()
        .offset(y: showChainZikrButton ? 50 : 0)
        .opacity(showChainZikrButton ? 1 : 0)
        .disabled(!showChainZikrButton)
        .animation(.easeInOut, value: showChainZikrButton)
    }
}
