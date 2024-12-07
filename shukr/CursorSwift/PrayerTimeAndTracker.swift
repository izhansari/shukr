import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications

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
    
    var calcMethodFromAppStorageVar: CalculationMethod? {
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

    var schoolFromAppStorageVar: Madhab? {
        let school = UserDefaults.standard.integer(forKey: "school")
        switch school {
        case 0: return .shafi
        case 1: return .hanafi
        default: return .shafi
        }
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
    
    func calculationPrinter(_ message: String){
        calculationPrints ? print(message) : ()
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

    
    // the current one im working on.
    func fetchPrayerTimes() {
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }

        // Update latitude and longitude
        self.latitude = String(format: "%.6f", location.coordinate.latitude)
        self.longitude = String(format: "%.6f", location.coordinate.longitude)

        guard let calculationMethod = calcMethodFromAppStorageVar, let madhab = schoolFromAppStorageVar else {
            print("Invalid calculation method or madhab")
            return
        }

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        var params = calculationMethod.params
        params.madhab = madhab
        
        // Generate prayer times for the current date
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        
        
        // My new proposed way of just having calc var shown on prayerButtons. Dont store nothing in persistence UNTIL COMPLETION or MISSED
        //-------------------------------------------------------------------
        if let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
            
            let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60)) // Start of next day
            let midnightMinusOneSec = midnight.addingTimeInterval(-1) // Subtract 1 second

            func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
                return (starTime, endTime, endTime.timeIntervalSince(starTime))
            }
            
            func createTestPrayerTime(startOffset: Int, endOffset: Int) -> (start: Date, end: Date, window: TimeInterval) {
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
            
            prayerTimesForDateDict = useTestPrayers ? testTimes : realTimes


        }
        
//        schedulePrayerNotifications(prayerByDateDict: prayerTimesForDateDict)

        //-------------------------------------------------------------------
        
        ////  CURRENT OBJECTIVE: 12/2 @ 5:04PM just commented this out and gonna try making it dependent on the calc vars from Adhan. Then create the persisted prayerModel objects on completion instead... this is the start of a big rethinking of our current archtiecture to handle the prayers. The current code as it stands will not work because now thelast5Prayers rely on the persisted objects which are then fed into  PulseCircleView and PrayerButton.

        // Format the current date
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()

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
                            if existingPrayer.startTime != startTime {
                                calculationPrinter("""
                                    ➤ OVERWRITING PRAYER: \(name)
                                        \(existingPrayer.startTime != startTime ? "↳ NEW START = \(shortTimePMDate(startTime)) (was \(shortTimePMDate( existingPrayer.startTime)))" : "")
                                    """.trimmingCharacters(in: .whitespacesAndNewlines)) // Remove empty lines
                                existingPrayer.startTime = startTime
                            }
                            if existingPrayer.endTime != endTime {
                                existingPrayer.endTime = endTime
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
                        calculationPrinter("""
                        ➕ Adding New Prayer: \(name)
                            ↳ Start Time: \(shortTimePMDate(startTime)) | End Time:   \(shortTimePMDate(endTime))
                        """)
                    }
                }

                calculationPrinter("Calc: \(calculationMethod) & \(madhab) & \(coordinates)")

                // Save changes
                self.saveChanges()
//                self.prayers = try self.context.fetch(fetchDescriptor).sorted(by: { $0.startTime < $1.startTime })

            } catch {
                print("❌ Error fetching existing prayers: \(error.localizedDescription)")
            }
        }

        //-------------------------------------------------------------------
        
        scheduleAllPrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
    }
    

    func scheduleAllPrayerNotifications(prayerByDateDict: [String : (start: Date, end: Date, window: TimeInterval)]) {
        var logMessages: [String] = [] // Collect logs here to ensure they print in order
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests() // Remove old notifications
        schedulePriner("^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ scheduling at \(shortTimeSecPM(Date()))")
        
        for prayerName in orderedPrayerNames {
            
            guard let prayerTimeData = prayerByDateDict[prayerName], let settings = notifSettings[prayerName] else {
                prayerByDateDict[prayerName] == nil ? logMessages.append("---\(prayerName) Notifs---⚠️ not in prayerByDateDict") : ()
                notifSettings[prayerName] == nil ? logMessages.append("---\(prayerName) Notifs---⚠️ not in notifSettings") : ()
                continue
            }
            logMessages.append("---(\(settings.allowNotif  ? (settings.allowNudges ? "3" : "1") : "0")) \(prayerName) Notifs ---")
            guard let isCompleted = checkIfComplete(prayerName: prayerName, startTime: prayerTimeData.start), !isCompleted else{
                logMessages.append("➤ \(prayerName) is completed")
                continue
            }
            guard settings.allowNotif else{
                logMessages.append("🛑 \(prayerName) notifs disabled")
                continue
            }
            scheduleThisPrayerNotifAt("Start", prayerName: prayerName, prayerTimeData: prayerTimeData)
            if settings.allowNudges {
                scheduleThisPrayerNotifAt("Mid", prayerName: prayerName, prayerTimeData: prayerTimeData)
                scheduleThisPrayerNotifAt("End", prayerName: prayerName, prayerTimeData: prayerTimeData)
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
                content.subtitle = /*nudges ?*/ "\(prayerName) Time 🟢" /*: "\(prayerName) Time"*/
                content.body = "Pray by \(shortTimePM(endTime))"
            case "Mid":
                let timeUntilEnd = prayerTimeData.window * 0.5
                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
                content.subtitle = "\(prayerName) At Midpoint 🟡"
                content.body = "Did you pray? There's \(timeLeftString(from: timeUntilEnd))"
            case "End":
                let timeUntilEnd = prayerTimeData.window * 0.25
                schedDate = endTime.addingTimeInterval(-timeUntilEnd)
                content.subtitle = "\(prayerName) Almost Over! 🔴"
                content.body = "Did you pray? There's still \(timeLeftString(from: timeUntilEnd))"
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
                    content.categoryIdentifier = "PRAYER_CATEGORY"
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

    
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//        formatter.timeZone = TimeZone.current
//        locationPrinter("from parseTime: \(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
    
    private func saveChanges() {
        do {
            try context.save()
            calculationPrinter("👍 Prayer state saved successfully")
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


    
    // new way. doesnt use index. so no need to parse through database. was using index = prayers.firstIndex(where: { $0.id == prayer.id })
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

    

    
}



struct PrayerTimesView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) var context
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @FocusState private var isNumberEntryFocused

    @Query private var prayersFromPersistence: [PrayerModel] = []
    
    @State private var last5Prayers: [PrayerModel] = []
    @State private var todaysStartedPrayers: [PrayerModel] = []
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

    
    private var startCondition: Bool{
        let timeModeCond = (sharedState.selectedMode == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedMode == 0)
        return (timeModeCond || countModeCond || freestyleModeCond)
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
                        
                        // state 2
                        if !showTop, let relevantPrayer = last5Prayers.first(where: {
                            !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() // current prayer if not completed
                        }) ?? last5Prayers.first(where: {
                            !$0.isCompleted && $0.startTime > Date() // next up prayer
                        }) ?? last5Prayers.first(where: {
                            !$0.isCompleted && $0.endTime < Date() // missed prayers
                        }) {
                            PulseCircleView(prayer: relevantPrayer)
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
                                NeuCircularProgressView(progress: 0)
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
                                TopBar(/*viewModel: viewModel,*/ /* /*showingDuaPageBool: $showingDuaPage , showingHistoryPageBool: $showingHistoryPage, */showingTasbeehPageBool: $showingTasbeehPage, */showTop: $showTop, showBottom: $showBottom, dragOffset: dragOffset)
                                        .transition(.opacity)
                                
                            }
                                                        
                            Spacer()
                            
                            // This VStack holds the PrayerTracker list
                            VStack {
                                // expandable prayer tracker (dynamically shown)
                                if showBottom {
                                    let spacing: CGFloat = 6
                                    VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                                        ForEach(last5Prayers) { prayer in
                                            PrayerButton(
                                                showChainZikrButton: $showChainZikrButton,
                                                todaysStartedPrayers: $todaysStartedPrayers, // Pass as binding
                                                prayerObject: prayer,
                                                name: prayer.name
                                            )
                                            
                                            .padding(.bottom, prayer.name == "Isha" ? 0 : spacing)
                                            
                                            if(prayer.name != "Isha"){
                                                Divider().foregroundStyle(.secondary)
                                                    .padding(.top, -spacing/2 - 0.5)
                                                    .padding(.horizontal, 25)
                                            }
                                        }
                                        
                                        
//                                        Button(action: {
//                                            print("hes on")
//                                            if let maghPray = todaysStartedPrayers.first(where: { $0.name == "Isha" } ){
//                                                print("\(maghPray.isCompleted) & \(maghPray.name)")
////                                                maghPray?.isCompleted.toggle()
//                                                viewModel.togglePrayerCompletion(for: maghPray)
//                                            }
//                                            
//                                        } ) {
//                                            Image(systemName: "checkmark.circle.fill")
//                                                .font(.system(size: 26))
//                                                .foregroundColor(.green.opacity(0.5))
//                                                .padding()
//                                                .background(.clear)
//                                                .cornerRadius(10)
//                                        }
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
            }

            .onAppear {
                
                loadLast5Prayers()
                
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
            
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
            
            // print out what we got
            print("---------------------------")
            print("\(last5Prayers.count) PRAYERS FROM LOADLAST5PRAYERS():")
            var tempArray: [PrayerModel] = []

            for (index, prayer) in last5Prayers.enumerated() {
                print("Prayer \(index + 1): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(shortTimePM(prayer.startTime)) - \(shortTimePM(prayer.endTime)) (\(prayer.startTime >= todayStart && prayer.startTime <= todayEnd))")
                
                if (prayer.startTime >= todayStart && prayer.startTime <= todayEnd){
                    tempArray.append(prayer)
                }
                todaysStartedPrayers = tempArray
            }
            
            print("---------------------------")
            print("\(todaysStartedPrayers.count) PRAYERS FROM todaysPrayersInContext \(shortTimePM(todayStart)) - \(shortTimePM(todayEnd)):")
            
            for (index, prayer) in todaysStartedPrayers.enumerated() {
                print("Prayer \(index + 1): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(shortTimePM(prayer.startTime)) - \(shortTimePM(prayer.endTime))")
            }
            
            print("---------------------------")

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
        return PrayerTimesView(/*context: context*/)
            .environmentObject(sharedState)
    }
}
