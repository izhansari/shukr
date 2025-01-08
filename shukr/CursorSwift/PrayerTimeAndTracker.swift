import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications

// MARK: - PrayerViewModel
class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var context: ModelContext
    
    @AppStorage("calculationMethod") var calculationMethod: Int = 2
    @AppStorage("school") var school: Int = 0
    
    @AppStorage("fajrNotif") var fajrNotif: Bool = true
    @AppStorage("dhuhrNotif") var dhuhrNotif: Bool = false
    @AppStorage("asrNotif") var asrNotif: Bool = true
    @AppStorage("maghribNotif") var maghribNotif: Bool = true
    @AppStorage("ishaNotif") var ishaNotif: Bool = true
    
    @AppStorage("fajrNudges") var fajrNudges: Bool = true
    @AppStorage("dhuhrNudges") var dhuhrNudges: Bool = true
    @AppStorage("asrNudges") var asrNudges: Bool = true
    @AppStorage("maghribNudges") var maghribNudges: Bool = true
    @AppStorage("ishaNudges") var ishaNudges: Bool = true
    
    @AppStorage("locationPrints") var locationPrints: Bool = false
    @AppStorage("schedulePrints") var schedulePrints: Bool = false
    @AppStorage("calculationPrints") var calculationPrints: Bool = false

    @AppStorage("lastLatitude") var lastLatitude: Double = 0
    @AppStorage("lastLongitude") var lastLongitude: Double = 0


    var orderedPrayerNames: [String] {
        ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    }
        
    var notifSettings: [String: (allowNotif: Bool, allowNudges: Bool)] {
        [
            "Fajr": (allowNotif: fajrNotif, allowNudges: fajrNudges),
            "Dhuhr": (allowNotif: dhuhrNotif, allowNudges: dhuhrNudges),
            "Asr": (allowNotif: asrNotif, allowNudges: asrNudges),
            "Maghrib": (allowNotif: maghribNotif, allowNudges: maghribNudges),
            "Isha": (allowNotif: ishaNotif, allowNudges: ishaNudges)
        ]
    }
    
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var hasValidLocation: Bool = false
    @Published var cityName: String?
    @Published var latitude: String = "N/A"
    @Published var longitude: String = "N/A"
    @Published var lastApiCallUrl: String = "N/A"
    @Published var useTestPrayers: Bool = false  // Add this property
    @Published var prayerTimesForDateDict: [String: (start: Date, end: Date, window: TimeInterval)] = [:]
    @Published var timeAtLLastRefresh: Date
    @Published var prayerSettings: [String: Bool] = [:]
    
    @State private var refreshTimer: Timer?
        
    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()
    private var lastGeocodeRequestTime: Date?
    private var lastAppLocation: CLLocation?
    
    var todaysPrayers: [PrayerModel] = []
    
    func getCalcMethodFromAppStorageVar() -> CalculationMethod {
        let calculationMethod = UserDefaults.standard.integer(forKey: "calculationMethod")
        switch  calculationMethod{
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
        default: return .northAmerica
        }
    }

    func getSchoolFromAppStorageVar() -> Madhab {
        let school = UserDefaults.standard.integer(forKey: "school")
        switch school {
        case 0: return .shafi
        case 1: return .hanafi
        default: return .shafi
        }
    }
    
    var relevantPrayer: PrayerModel? {
        let now = Date()
        
        if let currentPrayer = todaysPrayers.first(where: {  // 1. Check for the current prayer if not completed
            !$0.isCompleted && $0.startTime <= now && now <= $0.endTime
        }) { return currentPrayer }

        if let nextPrayer = todaysPrayers.first(where: {     // 2. Check for the next upcoming prayer
            !$0.isCompleted && now < $0.startTime
        }) { return nextPrayer }

        if let missedPrayer = todaysPrayers.first(where: {   // 3. Check for missed prayers
            !$0.isCompleted && $0.endTime < now
        }) { return missedPrayer }

        return nil                                          // No relevant prayer found
    }

    // Inject the ModelContext in the initializer
    init(context: ModelContext) {
        print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>PrayerViewModel initialized")
        self.context = context
        self.timeAtLLastRefresh = Date()
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
        self.scheduleDailyRefresh()
    }

    
    func locationPrinter(_ message: String) {
        locationPrints ? print(message) : ()
    }
    
    func schedulePriner(_ message: String){
        schedulePrints ? print(message) : ()
    }
        
    func calculationPrinter(_ message: String = "",
                            addNewPrayer: (name: String, startTime: Date, endTime: Date)? = nil,
                            overwritePrayerStart: (name: String, startTime: Date, oldStartTime: Date)? = nil) {
        guard calculationPrints else { return }
        
        if let data = addNewPrayer {
            print("""
                ➕ Adding New Prayer: \(data.name)
                    ↳ Start Time: \(shortTimePMDate(data.startTime)) | End Time: \(shortTimePMDate(data.endTime))
                """)
        } else if let data = overwritePrayerStart {
            if data.startTime != data.oldStartTime {
                print("""
                ➤ OVERWRITING PRAYER: \(data.name)
                    ↳ NEW START = \(shortTimePMDate(data.startTime)) (was \(shortTimePMDate(data.oldStartTime)))
                """.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            print(message)
        }
    }

    
    private func scheduleDailyRefresh() {
        let calendar = Calendar.current
        if let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) {
            let timeInterval = midnight.timeIntervalSince(Date())
            
            print("next refresh scheduled for \(midnight) in \(timerStyle(timeInterval))")
            refreshTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
                self.timeAtLLastRefresh = Date()
                self.fetchPrayerTimes()
                self.scheduleDailyRefresh() // Schedule the next update
            }
        }
    }
    
    // CLLocationManagerDelegate method
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK:
    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            print("locman: notDetermined")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("locman: denied")
            locationAuthorizationStatus = .denied
            hasValidLocation = false
        case .authorizedWhenInUse, .authorizedAlways:
            print("locman: authorizedWhenInUse or authorizedAlways")
            locationAuthorizationStatus = .authorizedWhenInUse
            if let location = locationManager.location {
                hasValidLocation = true
                fetchPrayerTimes()
                updateCityName(for: location)
            } else {
                hasValidLocation = false
            }
        @unknown default:
            print("locman: default")
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
                    // if we reach here, we are skipping updates
                    return
                } else { locationPrinter("📍 New Location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | \(Int(now.timeIntervalSince(lastRequestTime))) > 30s?") }
            } else { locationPrinter("📍 New Location: \(deviceLocation.coordinate.latitude), \(deviceLocation.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | First geocoding request") }
        } else { locationPrinter("⚠️ First location update. Proceeding with geocoding.") }

        // If checks pass, update location and proceed with geocoding
        updateLocation(deviceLocation)
    }


    private func updateLocation(_ location: CLLocation) {
        hasValidLocation = true
        latitude = String(format: "%.6f", location.coordinate.latitude)
        longitude = String(format: "%.6f", location.coordinate.longitude)
        lastLatitude = location.coordinate.latitude
        lastLongitude = location.coordinate.longitude

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

    func getPrayerTime(for prayerName: String, on date: Date) -> (start: Date, end: Date)? {
        guard let times = calcAdhanLibraryPrayerTimes(date: date) else {
            print("Failed to fetch or calculate Adhan arguments for date: \(date)")
            return nil
        }

        let midnight = Calendar.current.startOfDay(for: date.addingTimeInterval(24 * 60 * 60))
        let midnightMinusOneSec = midnight.addingTimeInterval(-1)

        switch prayerName.lowercased() {
        case "fajr":
            return (times.fajr, times.sunrise)
        case "dhuhr", "zuhr":
            return (times.dhuhr, times.asr)
        case "asr":
            return (times.asr, times.maghrib)
        case "maghrib":
            return (times.maghrib, times.isha)
        case "isha":
            return (times.isha, midnightMinusOneSec)
        default:
            print("Invalid prayer name: \(prayerName)")
            return nil
        }
    }

    
    func calcAdhanLibraryPrayerTimes(date: Date) -> PrayerTimes?{
        guard let location = locationManager.location else {
            print("Location not available")
            return nil
        }
        let calculationMethod = getCalcMethodFromAppStorageVar(); let madhab = getSchoolFromAppStorageVar()
        
        // Update latitude and longitude
        self.latitude = String(format: "%.6f", location.coordinate.latitude)
        self.longitude = String(format: "%.6f", location.coordinate.longitude)

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        var params = calculationMethod.params
        params.madhab = madhab
        
        // Generate prayer times for the current date
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
//        return (cord: coordinates, date: components, params: params)
        
        guard let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else{
            print("failed generating PrayerTimes object using Adhan libary")
            return nil
        }
        return times
    }
    
    // the current one im working on.
    func fetchPrayerTimes() {
        guard let times = calcAdhanLibraryPrayerTimes(date: Date()) else{
            print("failed using adhanArgsFromLocSettingsDate() to build a valid a PrayerTimes object")
            return
        }
        
        // My new proposed way of just having calc var shown on prayerButtons. Dont store nothing in persistence UNTIL COMPLETION or MISSED
        //-------------------------------------------------------------------
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60)) // Start of next day
        let midnightMinusOneSec = midnight.addingTimeInterval(-1) // Subtract 1 second
        
        func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
            return (starTime, endTime, endTime.timeIntervalSince(starTime))
        }
        func createTestPrayerTime(startOffset: Int, endOffset: Int) -> (Date, Date, TimeInterval) {
            // Configurable Time Units for Testing
            let timeUnit: Calendar.Component = .minute // Use seconds for more granular testing
            let timeMult = 1 // Multiplier to scale the time intervals
            let start = Calendar.current.date(byAdding: timeUnit, value: startOffset * timeMult, to: Date())!
            let end = Calendar.current.date(byAdding: timeUnit, value: endOffset * timeMult, to: Date())!
            return (start: start, end: end, window: end.timeIntervalSince(start))
        }
        
        let realTimes = [
            "Fajr": timesAndWindow(times.fajr, times.sunrise),
            "Dhuhr": timesAndWindow(times.dhuhr, times.asr),
            "Asr": timesAndWindow(times.asr, times.maghrib),
            "Maghrib": timesAndWindow(times.maghrib, times.isha),
            "Isha": timesAndWindow(times.isha, /*todayAt(23, 59)*/ midnightMinusOneSec)
        ]

        
        let testTimes = [
            "Fajr": createTestPrayerTime(startOffset: -4, endOffset: -3),  // 18–15 seconds ago
            "Dhuhr": createTestPrayerTime(startOffset: -3, endOffset: -2), // 12–9 seconds ago
            "Asr": createTestPrayerTime(startOffset: -2, endOffset: 1),    // 3 seconds ago to 3 seconds from now
            "Maghrib": createTestPrayerTime(startOffset: 1, endOffset: 2), // 6–9 seconds from now
            "Isha": createTestPrayerTime(startOffset: 2, endOffset: 4)     // 12–18 seconds from now
        ]
        print("Current Test Times: Asr end \(shortTimeSecPM(testTimes["Asr"]!.1)), Maghrib Start \(shortTimeSecPM(testTimes["Maghrib"]!.0))")
        
        prayerTimesForDateDict = useTestPrayers ? testTimes : realTimes
                
        //-------------------------------------------------------------------
        
        ////  CURRENT OBJECTIVE: 12/2 @ 5:04PM just commented this out and gonna try making it dependent on the calc vars from Adhan. Then create the persisted prayerModel objects on completion instead... this is the start of a big rethinking of our current archtiecture to handle the prayers. The current code as it stands will not work because now thelast5Prayers rely on the persisted objects which are then fed into  PulseCircleView and PrayerButton.
        
        // Format the current date
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
        
        do {
            // Fetch prayers for the current day from the context
            var fetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate<PrayerModel> { $0.startTime >= todayStart && $0.startTime <= todayEnd},
                sortBy: [SortDescriptor(\.startTime, order: .forward)]
            )
            fetchDescriptor.fetchLimit = 5
            let existingPrayers = try self.context.fetch(fetchDescriptor)

            // Define prayer names and times
            for name in orderedPrayerNames {

                guard let thisPrayerInDict = prayerTimesForDateDict[name] else{
                    calculationPrinter("\(name) missing from prayerTimesForDateDict")
                    return
                }
                
                let startTime = thisPrayerInDict.start; let endTime = thisPrayerInDict.end
                if let persisted = existingPrayers.first(where: { $0.name == name }) {
                    // Update existing prayer if not completed and times differ
                    if !persisted.isCompleted && ( persisted.startTime != startTime || persisted.endTime != endTime ) {
                        calculationPrinter(overwritePrayerStart: (name: name, startTime: startTime, oldStartTime: persisted.startTime))
                        persisted.startTime = startTime
                        persisted.endTime = endTime
                    }
                } else {
                    // Insert new prayer
                    let newPrayer = PrayerModel( name: name, startTime: startTime, endTime: endTime )
                    self.context.insert(newPrayer)
                    calculationPrinter(addNewPrayer: (name: name, startTime: startTime, endTime: endTime))

                }
            }
            // Save changes
            self.saveChanges()
            //self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.
        } catch {
            print("❌ Error fetching existing prayers: \(error.localizedDescription)")
        }
        
        //-------------------------------------------------------------------
        
        scheduleAllPrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
    }
    
//    func fetchPrayerTimes() {
//        
//        guard let stuff = adhanArgsFromLocSettingsDate(date: Date()) else{
//            return
//        }
//        let coordinates = stuff.cord
//        let components = stuff.date
//        let params  = stuff.params
//        // My new proposed way of just having calc var shown on prayerButtons. Dont store nothing in persistence UNTIL COMPLETION or MISSED
//        //-------------------------------------------------------------------
////        if let times = PrayerTimes(coordinates: stuff.cord, date: stuff.date, calculationParameters: stuff.params) {
//        if let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
//            
//            let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60)) // Start of next day
//            let midnightMinusOneSec = midnight.addingTimeInterval(-1) // Subtract 1 second
//
//            func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
//                return (starTime, endTime, endTime.timeIntervalSince(starTime))
//            }
//            
//            func createTestPrayerTime(startOffset: Int, endOffset: Int) -> (start: Date, end: Date, window: TimeInterval) {
//                // Configurable Time Units for Testing
//                let timeUnit: Calendar.Component = .minute // Use seconds for more granular testing
//                let timeMult = 1 // Multiplier to scale the time intervals
//                let start = Calendar.current.date(byAdding: timeUnit, value: startOffset * timeMult, to: Date())!
//                let end = Calendar.current.date(byAdding: timeUnit, value: endOffset * timeMult, to: Date())!
//                return (start: start, end: end, window: end.timeIntervalSince(start))
//            }
//            
//            let realTimes = [
//                "Fajr": timesAndWindow(times.fajr, times.sunrise),
//                "Dhuhr": timesAndWindow(times.dhuhr, times.asr),
//                "Asr": timesAndWindow(times.asr, times.maghrib),
//                "Maghrib": timesAndWindow(times.maghrib, times.isha),
//                "Isha": timesAndWindow(times.isha, /*todayAt(23, 59)*/ midnightMinusOneSec)
//            ]
//            
//            let testTimes = [
//                "Fajr": createTestPrayerTime(startOffset: -4, endOffset: -3),  // 18–15 seconds ago
//                "Dhuhr": createTestPrayerTime(startOffset: -3, endOffset: -2), // 12–9 seconds ago
//                "Asr": createTestPrayerTime(startOffset: -2, endOffset: 1),    // 3 seconds ago to 3 seconds from now
//                "Maghrib": createTestPrayerTime(startOffset: 1, endOffset: 2), // 6–9 seconds from now
//                "Isha": createTestPrayerTime(startOffset: 2, endOffset: 4)     // 12–18 seconds from now
//            ]
//            
//            prayerTimesForDateDict = useTestPrayers ? testTimes : realTimes
//
//
//        }
//        
////        schedulePrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
//
//        //-------------------------------------------------------------------
//        
//        ////  CURRENT OBJECTIVE: 12/2 @ 5:04PM just commented this out and gonna try making it dependent on the calc vars from Adhan. Then create the persisted prayerModel objects on completion instead... this is the start of a big rethinking of our current archtiecture to handle the prayers. The current code as it stands will not work because now thelast5Prayers rely on the persisted objects which are then fed into  PulseCircleView and PrayerButton.
//
//        // Format the current date
//        let todayStart = Calendar.current.startOfDay(for: Date())
//        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
//
//        if let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
//            do {
//                // Fetch prayers for the current day from the context
//                let fetchDescriptor = FetchDescriptor<PrayerModel>(
//                    predicate: #Predicate { prayer in
//                        prayer.startTime >= todayStart && prayer.startTime <= todayEnd
//                    }
//                )
//                let existingPrayers = try self.context.fetch(fetchDescriptor)
//                
//
//                // Define prayer names and times
//                let prayerInfo = [
//                    ("Fajr", prayerTimes.fajr, prayerTimes.sunrise),
//                    ("Dhuhr", prayerTimes.dhuhr, prayerTimes.asr),
//                    ("Asr", prayerTimes.asr, prayerTimes.maghrib),
//                    ("Maghrib", prayerTimes.maghrib, prayerTimes.isha),
//                    ("Isha", prayerTimes.isha, Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                ]
//                
//
//                for (name, startTime, endTime) in prayerInfo {
//                    if let existingPrayer = existingPrayers.first(where: { $0.name == name }) {
//                        // Update existing prayer if not completed
//                        if !existingPrayer.isCompleted {
//                            if existingPrayer.startTime != startTime {
//                                calculationPrinter("""
//                                    ➤ OVERWRITING PRAYER: \(name)
//                                        \(existingPrayer.startTime != startTime ? "↳ NEW START = \(shortTimePMDate(startTime)) (was \(shortTimePMDate( existingPrayer.startTime)))" : "")
//                                    """.trimmingCharacters(in: .whitespacesAndNewlines)) // Remove empty lines
//                                existingPrayer.startTime = startTime
//                            }
//                            if existingPrayer.endTime != endTime {
//                                existingPrayer.endTime = endTime
//                            }
//                        }
//                    } else {
//                        // Insert new prayer
//                        let newPrayer = PrayerModel(
//                            name: name,
//                            startTime: startTime,
//                            endTime: endTime
//                        )
//                        self.context.insert(newPrayer)
//                        calculationPrinter("""
//                        ➕ Adding New Prayer: \(name)
//                            ↳ Start Time: \(shortTimePMDate(startTime)) | End Time:   \(shortTimePMDate(endTime))
//                        """)
//                    }
//                }
//
//                calculationPrinter("Calc: \(String(describing: getCalcMethodFromAppStorageVar())) & \(String(describing: getSchoolFromAppStorageVar())) & \(coordinates)")
//
//                // Save changes
//                self.saveChanges()
////                self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.startTime })
//
//            } catch {
//                print("❌ Error fetching existing prayers: \(error.localizedDescription)")
//            }
//        }
//
//        //-------------------------------------------------------------------
//        
//        scheduleAllPrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
//    }

    

    func scheduleAllPrayerNotifications(prayerByDateDict: [String : (start: Date, end: Date, window: TimeInterval)]) {
        var logMessages: [String] = [] // Collect logs here to ensure they print in order
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests() // Remove old notifications
        schedulePriner("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ scheduling at \(shortTimeSecPM(Date()))")
        
        for name in orderedPrayerNames {
            let prayerTimeData = prayerByDateDict[name]!
            let settings = notifSettings[name]!

            logMessages.append("---(\(settings.allowNotif  ? (settings.allowNudges ? "3" : "1") : "0")) \(name) Notifs ---")
            guard let isCompleted = checkIfComplete(prayerName: name, startTime: prayerTimeData.start), !isCompleted else{
                logMessages.append("➤ \(name) is completed"); continue
            }
            guard settings.allowNotif else{
                logMessages.append("🛑 \(name) notifs disabled"); continue
            }
            scheduleThisPrayerNotifAt("Start", prayerName: name, prayerTimeData: prayerTimeData)
            if settings.allowNudges {
                scheduleThisPrayerNotifAt("Mid", prayerName: name, prayerTimeData: prayerTimeData)
                scheduleThisPrayerNotifAt("End", prayerName: name, prayerTimeData: prayerTimeData)
            }
        }
        schedulePriner(logMessages.joined(separator: "\n")) // Print all logs at once
        schedulePriner("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^end \(shortTimeSecPM(Date()))")
        
        func scheduleThisPrayerNotifAt(_ notifType: String, prayerName: String, prayerTimeData: (start: Date, end: Date, window: TimeInterval)) {
            let endTime = prayerTimeData.end
            var schedDate = prayerTimeData.start
            let content = UNMutableNotificationContent()
            var passedSwitchCase = true

            switch notifType {
            case "Start":
                schedDate = prayerTimeData.start
                content.title = /*nudges ?*/ "\(prayerName) Time 🟢" /*: "\(prayerName) Time"*/
                content.subtitle = "Pray by \(shortTimePM(endTime))"
            case "Mid":
                let timeUntilEnd = prayerTimeData.window * 0.5
                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
                content.title = "\(prayerName) At Midpoint 🟡"
                content.subtitle = /*"Did you pray?" */"There's \(timeLeftString(from: timeUntilEnd))"
            case "End":
                let timeUntilEnd = prayerTimeData.window * 0.25
                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
                content.title = "\(prayerName) Almost Over! 🔴"
                content.subtitle = /*"Did you pray?" */"There's still \(timeLeftString(from: timeUntilEnd))"
            default:
                logMessages.append("failed to conform to switch case")
                passedSwitchCase = false
            }
            
            if passedSwitchCase{
                // Skip scheduling if the date is in the past
                if schedDate < Date() {
                    logMessages.append("❌ In Past \(prayerName)\(notifType): \(shortTimeSecPM(schedDate))")
                }else{
                    let center = UNUserNotificationCenter.current()
                    let identifier = "\(prayerName)\(notifType)"
                    content.sound = .default
                    content.interruptionLevel = .timeSensitive
                    content.categoryIdentifier = "Round1_Snooze"
                    let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: schedDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                    center.add(request) { error in
                        if let error = error {
                            print("Error \(identifier): \(error.localizedDescription)")
                        }
                    }
                    logMessages.append("✅ Scheduled \(identifier): \(shortTimeSecPM(schedDate))")
                }
            }
        }
    }

    func checkIfComplete(prayerName: String, startTime: Date) -> Bool?{
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
        var thisPrayerInContext: PrayerModel?
        
        do {
            var fetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate<PrayerModel> { $0.startTime >= todayStart && $0.startTime <= todayEnd && $0.name == prayerName }
            )
            fetchDescriptor.fetchLimit = 1
            thisPrayerInContext = try context.fetch(fetchDescriptor).first // Fetch the first item directly
            if let prayer = thisPrayerInContext {
                return prayer.isCompleted
            }else {
                // fetch succeeded but did not find any relevant data.
                return nil
            }
        } catch {
            //2 an error occured during the fetch attempt.
            print("❌ (checkIfComplete) Error fetching '\(prayerName) \(shortTimePMDate(startTime))' from context \(error.localizedDescription)")
            return nil
        }
    }

    
    func addToNotificationCenterBySeconds(identifier: String, content: UNMutableNotificationContent, sec: Double){
        let center = UNUserNotificationCenter.current()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Error \(identifier): \(error.localizedDescription)")
            }
        }
        print("✅ Scheduled \(identifier): in \(sec)s")
    }

    
    private func saveChanges() {
        do {
            try context.save()
            calculationPrinter("👍 \(getCalcMethodFromAppStorageVar()) & \(getSchoolFromAppStorageVar()) & latitude: \(self.latitude), longitude: \(self.longitude)")
        } catch {
            print("🚨 Failed to save prayer state: \(error.localizedDescription)")
        }
    }

    func refreshCityAndPrayerTimes() { // used outside of viewmodel.
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }
        updateCityName(for: location)
        fetchPrayerTimes()
    }


    func togglePrayerCompletion(for prayer: PrayerModel) {
        triggerSomeVibration(type: .medium)
        
        if prayer.startTime <= Date() {
            prayer.isCompleted.toggle()
            if prayer.isCompleted {
                setPrayerScore(for: prayer)
                setPrayerLocation(for: prayer)
                cancelUpcomingNudges(for: prayer.name)
            } else {
                prayer.timeAtComplete = nil
                prayer.numberScore = nil
                prayer.englishScore = nil
                prayer.latPrayedAt = nil
                prayer.longPrayedAt = nil
            }
        }
        
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
        
        func setPrayerLocation(for prayer: PrayerModel) {
            guard let location = locationManager.location else {
                print("Location not available")
                return
            }
            print("setting location at complete as: ", location.coordinate.latitude, "and ", location.coordinate.longitude)
            prayer.latPrayedAt = location.coordinate.latitude
            prayer.longPrayedAt = location.coordinate.longitude

        }
    }
    
    
    func cancelUpcomingNudges(for prayerName: String){ /// FIXME: Issue. Cancels pending notification requests... but just schedules them again when fetchPrayers() is run.
        // Remove pending notifications for this prayer
        let center = UNUserNotificationCenter.current()
        let identifiers = ["\(prayerName)Mid", "\(prayerName)End"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("✅ Canceled notifications for \(prayerName): [\(identifiers)]")
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


    
    func loadTodaysPrayers(){
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime >= todayStart && $0.startTime <= todayEnd},
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        fetchDescriptor.fetchLimit = 5

        do {
            todaysPrayers = try context.fetch(fetchDescriptor)
        } catch {
            print("❌ (loadLast5Prayers) Error occured during the fetch attempt. \(error.localizedDescription)")
        }
        
        var index = 1
        print("---------------------------")
        print("\(todaysPrayers.count) PRAYERS FROM loadLast5Prayers() v2:")
        for prayer in todaysPrayers {
            print("Prayer \(index): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(shortTimePM(prayer.startTime)) - \(shortTimePM(prayer.endTime))"); index += 1
        }
        print("---------------------------")
    }
    
}


// MARK: - Prayer Times View

struct PrayerTimesView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) var context
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @FocusState private var isNumberEntryFocused

    @Query private var prayersFromPersistence: [PrayerModel] = []
    
    @State private var activeTimerId: UUID? = nil
    @State private var dragOffset: CGFloat = 0.0
    @State private var showTasbeehPage = false // State to control full-screen cover
    @State private var showMantraSheetFromHomePage: Bool = false
    @State private var chosenMantra: String? = ""
    @State private var isAnimating: Bool = false
    @State private var showChainZikrButton: Bool = false
//    @State private var nextFajr: (start: Date, end: Date)? = nil // State for Fajr time
    
    var showTop: Bool { sharedState.newTopMainOrBottom == .top }
    var showBottom: Bool { sharedState.newTopMainOrBottom == .bottom }
    var showMain: Bool { sharedState.newTopMainOrBottom == .main }
    
    private func handleTap(for targetView: SharedStateClass.ViewPosition) {
        if isNumberEntryFocused {
            isNumberEntryFocused = false
        }else{
            let viewState = sharedState.newTopMainOrBottom
            withAnimation {
                sharedState.newTopMainOrBottom = (viewState == .main ? targetView : .main)
            }
        }
    }
    
    private func handleDragEnd(translation: CGFloat) {
        let threshold: CGFloat = 30
        let satisfiedDragDown = translation > threshold
        let satisfiedDragUp = translation < -threshold
        let viewState = sharedState.newTopMainOrBottom
        
        guard satisfiedDragDown || satisfiedDragUp else { return }

        withAnimation(.bouncy(duration: 0.5)) {
            switch viewState {
            case .main:
                if satisfiedDragUp { sharedState.newTopMainOrBottom = .bottom }
                else if satisfiedDragDown { sharedState.newTopMainOrBottom = .top }
            case .top:
                if satisfiedDragUp { sharedState.newTopMainOrBottom = .main }
            case .bottom:
                if satisfiedDragDown { sharedState.newTopMainOrBottom = .main }
            }
            dragOffset = 0
        }
        isNumberEntryFocused = false
        triggerSomeVibration(type: .medium)
//        print("Drag translation: \(translation)")
    }


    private var startCondition: Bool{
        let timeModeCond = (sharedState.selectedMode == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedMode == 0)
        return (timeModeCond || countModeCond || freestyleModeCond)
    }
    
    
    var body: some View {
        ZStack {
            
            Color("bgColor")
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0){
                Color.white.opacity(0.001)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        handleTap(for: .top)
                    }
                
                Color.white.opacity(0.001)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        handleTap(for: .bottom)
                    }
            }
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
                            NeuCircularProgressView(progress: (0))
                            
                            // the color outline circle to indicate start button
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
                    
                    // MARK:  current focus
                    // state 2
                    //FIXME: need to account for if they didnt complete all of todays prayers. cant show done if its not done.
                    if !showTop{
                        if let relevantPrayer = viewModel.relevantPrayer{
                            PulseCircleView(prayer: relevantPrayer)
                                .transition(.opacity)
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
                        else {
                            summaryCircle()
                        }
                    }
                    
                    
                    // state 3
                    if showBottom {
                        // just for spacing to push it up.
                        RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
                            .fill(Color.clear)
                            .frame(width: 320, height: 320)
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
                            
                            //FIXME: ADD TASKS HERE?
                        }
                        
                        FloatingChainZikrButton(showTasbeehPage: $showTasbeehPage, showChainZikrButton: $showChainZikrButton)
                        
                        TopBar(dragOffset: dragOffset)
                            .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    // This VStack holds the PrayerTracker list
                    VStack {
                        // expandable prayer tracker (dynamically shown)
                        if showBottom {
                            let spacing: CGFloat = 6
                            VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
                                    PrayerButton(
                                        showChainZikrButton: $showChainZikrButton,
                                        name: prayerName,
                                        viewModel: viewModel
                                    )
                                    .padding(.bottom, prayerName == "Isha" ? 0 : spacing)
                                    
                                    if prayerName != "Isha" {
                                        Divider().foregroundStyle(.secondary)
                                            .padding(.top, -spacing / 2 - 0.5)
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
                            
                            CustomBottomBar()
                            .padding(.top, 35)
                            .padding(.bottom, 25)
                            .padding(.horizontal, 45)
                            .opacity(0.7)
//                            .background(Color("bgColor"))
//                            .cornerRadius(15)
                        }
                        
                        // chevron button to pull up the tracker.
                        if showMain{
                            Image(systemName: "chevron.up")
                                .font(.title3)
                                .foregroundColor(.gray)
                                .scaleEffect(x: 1, y: dragOffset > 0 || showBottom ? -1 : 1)
                                .padding(.bottom, 30)
//                                .padding(.top)
                                .onTapGesture{
                                    withAnimation{
                                        print("tapped the chev")
                                        sharedState.newTopMainOrBottom = showBottom ? .main : .bottom
                                    }
                                }
                        }
                    }
                    .offset(y: dragOffset) // moves with drag
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
        .edgesIgnoringSafeArea(.bottom)
        .onAppear {
            viewModel.loadTodaysPrayers()
            if sharedState.firstLaunch{
                sharedState.newTopMainOrBottom = .main
                sharedState.firstLaunch = false
            }
        }
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
        return PrayerTimesView(/*context: context*/)
            .environmentObject(sharedState)
    }
}

struct CustomBottomBar: View {
    @EnvironmentObject var sharedState: SharedStateClass

    var body: some View {
        HStack {
            
            NavigationLink(destination: HistoryPageView()) {
                VStack(spacing: 6){
                    Image(systemName: "circle.hexagonpath")
                        .font(.system(size: 20))
                    Text("Zikr")
                        .font(.system(size: 12))
                        .fontWeight(.light)
                }
                .foregroundColor(.gray)
                .frame(width: 100)
//                .background(.blue)
            }
            
            Spacer()

            
            Button(action: {
                withAnimation(.bouncy(duration: 0.5)) {
                    sharedState.newTopMainOrBottom = .main
                }
            }) {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 20))
                    Text("Salah")
                        .font(.system(size: 12))
                        .fontWeight(.light)
                }
                .foregroundColor(.green)
                .frame(width: 100)
            }

            
            
            Spacer()
            
            NavigationLink(destination: DuaPageView()) {
                VStack(spacing: 6){
                    Image(systemName: "book")
                        .font(.system(size: 20))
                    Text("Duas")
                        .font(.system(size: 12))
                        .fontWeight(.light)
                }
                .foregroundColor(.gray)
                .frame(width: 100)
//                .background(.blue)
            }
        }
        .background(Color("bgColor").opacity(0.1))
    }
}

// MARK: - Prayer Button


import MapKit
struct PrayerButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel

    @AppStorage("calculationMethod") var calculationMethod: Int = 2
    @AppStorage("school") var school: Int = 0

    @Binding var showChainZikrButton: Bool
    
    @State private var toggledText: Bool = false
    @State private var showAlert = false // State for showing alert
    @State private var isMarkingIncomplete = false // Track if we are marking incomplete
    @State private var showTimePicker = false
    @State private var selectedDate = Date()
    @State private var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var searchQuery = ""

    
    let prayerObject: PrayerModel
    let name: String
        
    init(showChainZikrButton: Binding<Bool>, name: String, viewModel: PrayerViewModel) {
        guard let foundPrayer = viewModel.todaysPrayers.first(where: { $0.name == name }) else {
            fatalError("PrayerModel not found for name: \(name)")
        }
        self._showChainZikrButton = showChainZikrButton
        self.prayerObject = foundPrayer
        self.name = name
    }
    
    private func searchLocation() {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = searchQuery
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            guard let response = response else {
                print("Error: \(error?.localizedDescription ?? "Unknown error").")
                return
            }
            
            if let firstItem = response.mapItems.first {
                selectedLocation = firstItem.placemark.coordinate
            }
        }
    }

    
    private var isFuturePrayer: Bool {
        calcStartTime > Date()
    }
    
    // Status Circle Properties
    private var statusImageName: String {
        if isFuturePrayer { return "circle" }
        return prayerObject.isCompleted ? "checkmark.circle.fill" : "circle"
    }
    
    private var statusColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayerObject.isCompleted ? viewModel.getColorForPrayerScore(prayerObject.numberScore) : Color.secondary.opacity(0.5)
    }
    
    // Text Properties
    private var statusBasedOpacity: Double {
        if isFuturePrayer { return 0.6 }
        return prayerObject.isCompleted ? 0.7 : 1
    }
    
    // Background Properties
    private var backgroundColor: Color {
        if isFuturePrayer { return Color("bgColor") }
        return prayerObject.isCompleted ? Color("NeuClickedButton") : Color("bgColor")
    }
    
    // Shadow Properties
    private var shadowXOffset: CGFloat {
        prayerObject.isCompleted ? -2 : 0
    }
    
    private var shadowYOffset: CGFloat {
        prayerObject.isCompleted ? -2 : 0
    }
    
    private var nameFontSize: Font {
        return .callout
    }
    
    private var timeFontSize: Font {
        return .footnote
    }
    
    private var calcStartTime: Date{
        if let timesFromDict = viewModel.prayerTimesForDateDict[name]{
            return timesFromDict.start
        }
        return Date()
    }
    
    var body: some View {
            HStack {
                // Status Circle
                Button(action: {
                    // Handle Future Prayer Toggle
                    if !isFuturePrayer {
                        // Handle Prayer Completion with Spring Animation
                        if prayerObject.isCompleted {
                            // Show alert if trying to mark as incomplete
                            showAlert = true
                        }
                        else {
                            withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                                viewModel.togglePrayerCompletion(for: prayerObject)
                            }
                        }
                        
                        // Show Chain Zikr Button Animation
                        if prayerObject.isCompleted {
                            withAnimation {
                                showChainZikrButton = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    showChainZikrButton = false
                                }
                            }
                        }
                    }
                }) {
                    Image(systemName: statusImageName)
                        .foregroundColor(statusColor)
                        .frame(width: 24, height: 24, alignment: .leading)
                }
                    .buttonStyle(PlainButtonStyle())
                
                // Prayer Name Label
                Text(name)
                    .font(nameFontSize)
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                
                Spacer()
                
                // Time Display Section
                if isFuturePrayer {
                    // Future Prayer: Toggleable Time/Countdown
                    ExternalToggleText(
                        originalText: shortTimePM(calcStartTime),
                        toggledText: timeUntilStart(calcStartTime),
                        externalTrigger: $toggledText,
                        font: timeFontSize,
                        fontDesign: .rounded,
                        fontWeight: .light,
                        hapticFeedback: true
                    )
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))

                } else if prayerObject.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if let completedTime = prayerObject.timeAtComplete {
                        Text("@ \(shortTimePM(completedTime))")
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    }
                } else {
                    // Current Prayer: Show Start Time
                    Text(shortTimePM(calcStartTime))
                        .font(timeFontSize)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
                
                // Chevron Arrow
                ChevronTap()
                    .opacity(statusBasedOpacity)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            // Background Effects Container
            .background(
                Group {
                    if isFuturePrayer || !prayerObject.isCompleted {
                        // Plain Effect: Future Prayer (No Shadow) or Current
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor)
                    } else {
                        // Neumorphic Effect: Completed Prayer
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor
                                  // Indent/Outdent Effects
                                .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 1, x: -shadowXOffset, y: -shadowYOffset))
                                .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 1, x: shadowXOffset, y: shadowYOffset))
                            )
                    }
                }
            )
            .animation(.spring(response: 0.1, dampingFraction: 0.7), value: prayerObject.isCompleted)
            .alert(isPresented: $showAlert) {
                        Alert(
                            title: Text("Confirm Action"),
                            message: Text("Are you sure you want to mark this prayer as incomplete?"),
                            primaryButton: .destructive(Text("Yes")) {
                                isMarkingIncomplete = true
                                withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                                    viewModel.togglePrayerCompletion(for: prayerObject)
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    }
            .sheet(isPresented: $showTimePicker) {
                VStack {
                    Text("Edit Prayer Details for \(name)")
                        .font(.headline)
                        .padding()
                    
                    DatePicker("Completion Time", selection: $selectedDate, displayedComponents: [.hourAndMinute, .date])
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                    
                    // Add a small map view
                    MiniMapView(coordinate: $selectedLocation)
                        .frame(height: 200)
                        .cornerRadius(10)
                        .padding()
                    
                    // Add a search bar
                    TextField("Search location", text: $searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .onSubmit {
                            searchLocation()
                        }
                    
                    Button("Save") {
//                        viewModel.updatePrayerDetails(for: prayerObject, time: selectedDate, location: selectedLocation)
                        prayerObject.latPrayedAt = selectedLocation.latitude
                        prayerObject.longPrayedAt = selectedLocation.longitude
                        showTimePicker = false
                    }
                    .padding()
                }
            }
            .onTapGesture {
                if isFuturePrayer {
                    withAnimation {
                        toggledText.toggle()
                    }
                }
            }
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in
                        if prayerObject.isCompleted {
                            selectedDate = prayerObject.timeAtComplete ?? Date()
                            showTimePicker = true
                        }
                    }
            )
    }

        
    struct MiniMapView: View {
        @Binding var coordinate: CLLocationCoordinate2D
        @State private var region: MKCoordinateRegion
        
        init(coordinate: Binding<CLLocationCoordinate2D>) {
            self._coordinate = coordinate
            _region = State(initialValue: MKCoordinateRegion(
                center: coordinate.wrappedValue,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        
        var body: some View {
            Map(coordinateRegion: $region, interactionModes: .all, showsUserLocation: true, userTrackingMode: .none)
                .onTapGesture { location in
                    let coordinate = region.center
                    self.coordinate = coordinate
                }
        }
    }
}

struct ChevronTap: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .onTapGesture {
                triggerSomeVibration(type: .medium)
                print("chevy hit")
            }
    }
}

struct summaryCircle: View{
    // FIXME: think this through more and make sure it makes sense.
    @State private var nextFajr: (start: Date, end: Date)?
    @EnvironmentObject var viewModel: PrayerViewModel
    @State var summaryInfo: [String : Double?] = [:]
    @State private var textTrigger = false
    @State private var currentTime = Date()

    private var fajrAtString: String{
        guard let fajrTime = nextFajr else { return "" }
//        return "Fajr in " + formatTimeIntervalWithS(fajrTime.start.timeIntervalSince(currentTime))
        return "Farj at \(shortTimePM(fajrTime.start))"
    }
    
    private var sunriseAtString: String{
        guard let fajrTime = nextFajr else { return "" }
        return "Sunrise at \(shortTimePM(fajrTime.end))"
    }
    
    private func getTheSummaryInfo(){
        for name in viewModel.orderedPrayerNames {
            if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }){
                summaryInfo[name] = prayer.numberScore
                print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with scores: \(prayer.numberScore ?? 0)")
            }
        }
    }
    
    func setTheRightFajrTime(){
        if let todaysFajr = viewModel.getPrayerTime(for: "Fajr", on: Date()){
            if todaysFajr.start > Date(){
                nextFajr = todaysFajr
            }
            else{
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                nextFajr = viewModel.getPrayerTime(for: "Fajr", on: tomorrow)
            }
        }
    }
    
    func calculateScoreDotPosition(_ score: Double, from: CGFloat, to: CGFloat) -> CGPoint {
        let angle = CGFloat(-90.0) + 360.0 * (CGFloat(score) * (to - from) + from)
        let radius: CGFloat = 90 // Adjust based on your circle size
        let radians = angle * .pi / 180
        return CGPoint(x: cos(radians) * radius, y: sin(radians) * radius)
    }

    var body: some View{
        ZStack{
            NeuCircularProgressView(progress: 0)
            
//            ForEach(0..<5) { index in
//                let prayerSpace = 360.0 / 5 // 360 degrees / 5 sections
//                let startAngle = CGFloat(index) * prayerSpace
//                
//                // Separator lines
//                Rectangle()
//                    .fill(Color.secondary.opacity(0.2))
//                    .frame(width: 2, height: 12)
//                    .offset(y: -100) // Based on circle size of 200x200
//                    .rotationEffect(.degrees(Double(startAngle)))
//                
//                Circle()
//                    .trim(from: 0, to: 0.2)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .foregroundStyle(.secondary)
//                    .rotationEffect(.degrees(Double(startAngle)))
//                
//                
//                // Dot on the circle
//                let score: CGFloat = 0.25 // Example prayer score
//                let dotAngle = startAngle + ((1 - score) * prayerSpace) // Place dot at 1 - score from end
//                let scoreColor: Color = .secondary // Replace with your dynamic color variable
//                Circle()
//                    .stroke(scoreColor.opacity(0.5), lineWidth: 0.5) // Dot stroke with scoreColor
//                    .frame(width: 10, height: 10) // Dot size
//                    .offset(y: -100) // Radius positioning
//                    .rotationEffect(.degrees(Double(dotAngle))) // Dot position in section
//            }

                        
            VStack{
                Text("done")
                if let fajrTime = nextFajr {
                    
                    ExternalToggleText(
                        originalText: fajrAtString,
                        toggledText: sunriseAtString,
//                        toggledText: "Fajr in \(fajrInString)",
//                        toggledText: "Fajr in \(formatTimeInterval(fajrTime.end.timeIntervalSince(Date())))",
                        externalTrigger: $textTrigger,  // Pass the binding
                        fontDesign: .rounded,
                        fontWeight: .thin,
                        hapticFeedback: true
                    )
                }
            }
            
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 200, height: 200)
                .onTapGesture {
                    textTrigger.toggle()  // Toggle the trigger
                }
        }
        .onAppear {
            setTheRightFajrTime()
            getTheSummaryInfo()
            viewModel.fetchPrayerTimes() // FIXME: think this through more and make sure it makes sense.
        }
    }
    

}
