//
//  PrayerViewModel.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/17/25.
//


import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications

// MARK: - PrayerViewModel
class PrayerViewModel_WillMakeThisDaddy: NSObject, ObservableObject, CLLocationManagerDelegate {
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

    // App Storage doesnt use Date types. So we use timeIntervalSince1970 to convert to Date. Then use a computed var to get and set it. (which deals with the unwrapping for us)
    @AppStorage("prayerStreak") var prayerStreak: Int = 0
    @AppStorage("maxPrayerStreak") var maxPrayerStreak: Int = 0
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1
    @AppStorage("dateOfMaxPrayerStreak") var dateOfMaxPrayerStreakTimeInterval: Double = Date().timeIntervalSince1970
    var dateOfMaxPrayerStreak: Date {
        get {
            return Date(timeIntervalSince1970: dateOfMaxPrayerStreakTimeInterval)
        }
        set {
            dateOfMaxPrayerStreakTimeInterval = newValue.timeIntervalSince1970
        }
    }

    

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
    @Published var useTestPrayers: Bool = false  // Add this property
    @Published var prayerTimesForDateDict: [String: (start: Date, end: Date, window: TimeInterval)] = [:]
    @Published var timeAtLLastRefresh: Date
    @Published var prayerSettings: [String: Bool] = [:]
    @Published var compassHeading: Double = 0

    
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
                self.fetchPrayerTimes(cameFrom: "scheduleDailyRefresh")
                self.scheduleDailyRefresh() // Schedule the next update
            }
        }
    }
    
    // to get compass heading
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        compassHeading = newHeading.magneticHeading
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
                fetchPrayerTimes(cameFrom: "checkLocationAuthorization")
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
        lastLatitude = location.coordinate.latitude
        lastLongitude = location.coordinate.longitude

        // Update the last geocode request time and last updated location
        lastGeocodeRequestTime = Date()
        lastAppLocation = location

        locationPrinter("🌍 Triggering geocoding and prayer times fetch...")
        updateCityName(for: location)
        fetchPrayerTimes(cameFrom: "updateLocation")
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
        case "sunrise":
            return (times.sunrise, times.dhuhr)
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
    
    func getNextPrayerTime(for prayerName: String) -> Date? {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        guard let todaysTime = getPrayerTime(for: prayerName, on: now)?.start,
           let tomorrowsTime = getPrayerTime(for: prayerName, on: tomorrow)?.start else{
            print("getNextPrayerTime failed (probably cuz invalid prayer names)")
            return nil
        }

        let nextPrayerTime = now > todaysTime ? tomorrowsTime : todaysTime
        
        return nextPrayerTime
    }

    
    func calcAdhanLibraryPrayerTimes(date: Date) -> PrayerTimes?{
        guard let location = locationManager.location else {
            print("Location not available")
            return nil
        }
        
        // Update latitude and longitude
        lastLatitude = location.coordinate.latitude
        lastLongitude = location.coordinate.longitude

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var params = getCalcMethodFromAppStorageVar().params
        params.madhab = getSchoolFromAppStorageVar()
        
        guard let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else{
            print("failed generating PrayerTimes object using Adhan libary")
            return nil
        }
        return times
    }
    
    // the current one im working on.
    func fetchPrayerTimes(cameFrom: String) {
        print("@@ came from: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ \(cameFrom)")
        guard let times = calcAdhanLibraryPrayerTimes(date: Date()) else{
            print("failed using calcAdhanLibraryPrayerTimes() to build a valid a PrayerTimes object")
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
//        print("Current Test Times: Asr end \(shortTimeSecPM(testTimes["Asr"]!.1)), Maghrib Start \(shortTimeSecPM(testTimes["Maghrib"]!.0))")
        
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
    

    func scheduleAllPrayerNotifications(prayerByDateDict: [String : (start: Date, end: Date, window: TimeInterval)]) {
        var logMessages: [String] = [] // Collect logs here to ensure they print in order
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests() // Remove old notifications
        schedulePriner("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ scheduling at \(shortTimeSecPM(Date()))")
        
        for name in orderedPrayerNames {
            let prayerTimeData = prayerByDateDict[name]!
            let settings = notifSettings[name]!
                        
            logMessages.append("--- (\(settings.allowNotif  ? (settings.allowNudges ? "3" : "1") : "0")) \(name) Notifs ---")
            guard isNotCompletedToday(prayerName: name) /*== false, !isCompleted*/ else{
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
//            case "End":
//                let timeUntilEnd = prayerTimeData.window * 0.25
//                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
//                content.title = "\(prayerName) Almost Over! 🔴"
//                content.subtitle = /*"Did you pray?" */"There's still \(timeLeftString(from: timeUntilEnd))"
            case "End":
                let timeUntilEnd = (30.0 * 60)
                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
                content.title = "\(prayerName) Almost Over! 🔴"
                content.subtitle = /*"Did you pray?" */"There's only \(timeLeftString(from: timeUntilEnd))"
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

    func isNotCompletedToday(prayerName: String) -> Bool{
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime >= todayStart && $0.startTime <= todayEnd && $0.name == prayerName }
        )
        fetchDescriptor.fetchLimit = 1

        do {
            let fetchedPrayer = try context.fetch(fetchDescriptor).first // Fetch the first item directly
            let isIncomplete = ( fetchedPrayer?.isCompleted == false )
            return isIncomplete ? true : false
        } catch {
            print("❌ (checkIfComplete) Error fetching '\(prayerName)' from context \(error.localizedDescription)")
            return false
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
//            calculationPrinter("👍 \(getCalcMethodFromAppStorageVar()) & \(getSchoolFromAppStorageVar()) & latitude: \(self.latitude), longitude: \(self.longitude)")
            calculationPrinter("👍 \(getCalcMethodFromAppStorageVar()) & \(getSchoolFromAppStorageVar()) & latitude: \(lastLatitude), longitude: \(self.lastLongitude)")
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
        fetchPrayerTimes(cameFrom: "refreshCityAndPrayerTimes")
    }


    func togglePrayerCompletion(for prayer: PrayerModel) {
        triggerSomeVibration(type: .medium)
        
        if prayer.startTime <= Date() {
            prayer.isCompleted.toggle()
            if prayer.isCompleted {
                setPrayerScore(for: prayer)
                setPrayerLocation(for: prayer)
                cancelUpcomingNudges(for: prayer.name)
                calculatePrayerStreak()
            } else {
                prayer.resetPrayer()
                calculatePrayerStreak()
            }
        }
    }
    
    func setPrayerScore(for prayer: PrayerModel, atDate: Date = Date()) {
        print("setting time at complete as: ", atDate)
        prayer.timeAtComplete = atDate

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
    
    
    func cancelUpcomingNudges(for prayerName: String){
        let center = UNUserNotificationCenter.current()
        let identifiers = ["\(prayerName)Mid", "\(prayerName)End"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("✅ Canceled notifications for \(prayerName): [\(identifiers)]")
    }
            
    func calculatePrayerStreak()/* -> Int */{
                
        // Fetch prayers that are in the past
        let now = Date()
        let fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime <= now},
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        // Fetch all prayers from the database
        guard let pastPrayersSorted = try? context.fetch(fetchDescriptor) else {
            print("❌ Failed to fetch prayers for streak.")
            prayerStreak = -999 // to quickly see in the view that something is wrong
            return
        }
        
        prayerStreak = 0
        for prayer in pastPrayersSorted {
            if gradingCriteria(for: prayer) {
                prayerStreak += 1
            }
            else if now <= prayer.endTime{continue}
            else {
                if prayerStreak > maxPrayerStreak {
                    maxPrayerStreak = prayerStreak
                    dateOfMaxPrayerStreak = Date()
                }
                break
            }
        }
        
        func gradingCriteria(for prayer: PrayerModel) -> Bool{
            if prayerStreakMode == 1 {
                prayer.isCompleted
            }
            else if prayerStreakMode == 2 {
                prayer.numberScore ?? 0 > 0
            }
            else {
                prayer.numberScore ?? 0 > 0.25
            }
        }
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
    
    // For Sun Based Color Scheme:
    var isDaytime: Bool {
        // Get the Fajr prayer time
        guard let fajr = prayerTimesForDateDict["Fajr"], let maghrib = prayerTimesForDateDict["Maghrib"] else {
            return true // Default to daytime if no times are available
        }
        let now = Date()

//        let testCutOffDate = todayAt(17, 47)
        
        // Check if the current time is between Fajr and 5:35 PM
        let isAfterFajr = now >= fajr.end
        let isBeforeMaghrib = now < maghrib.start /*testCutOffDate*/
        let isDaytime = isAfterFajr && isBeforeMaghrib

        // Combine all prints into one statement
//        print("isDayTime: Past Fajr: \(isAfterFajr), Before Maghrib: \(isBeforeMaghrib) = Daytime?: \(isDaytime)")

        return isDaytime
    }
    
    
    func calculateQiblaDirection() -> Double {
        guard let userLocation = locationManager.location else { return 0 }
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
