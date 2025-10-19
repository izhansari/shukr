import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications
import WidgetKit
import Combine

// MARK: - PrayerViewModel
class PrayerViewModel: ObservableObject{ //letsgoooo i removed the CLLocationManager stuff from here. one less location manager!
    
    // MARK: - Arguments & Init
    
    private var context: ModelContext // Inject the ModelContext in the initializer
    var ENV_LocationManager: EnvLocationManager // Inject the EnvLocationManager in the initializer
    init(context: ModelContext, envLocationManager: EnvLocationManager) {
        print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>PrayerViewModel initialized")
        self.context = context
        self.ENV_LocationManager = envLocationManager
        self.timeAtLastRefresh = Date()
        self.scheduleDailyRefresh() //this will only run once on initialization. but will not run again if app is kept open in appswitcher.
        self.subscribeToChanges()
        
//        self.loadDailyScores()

    }
    
    private func subscribeToChanges(){
        // Subscribe to userLocation changes
        ENV_LocationManager.$userLocation
            .sink { [weak self] newVal in
                self?.handleLocationChange(for: newVal)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - AppStorage
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0

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

    @AppStorage("lastLatitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLatitude: Double = 0
    @AppStorage("lastLongitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLongitude: Double = 0
    @AppStorage("lastCityName", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastCityName: String = "Wonderland"
    
    /// App Storage doesnt use Date types. So we use timeIntervalSince1970 to convert to Date. Then use a computed var to get and set it. (which deals with the unwrapping for us)
    @AppStorage("prayerStreak") var prayerStreak: Int = 0 //prayerstreak_flag
    @AppStorage("maxPrayerStreak") var maxPrayerStreak: Int = 0
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1
    @AppStorage("dateOfMaxPrayerStreak") var dateOfMaxPrayerStreakTimeInterval: Double = Date().timeIntervalSince1970
    var dateOfMaxPrayerStreak: Date {
        get { return Date(timeIntervalSince1970: dateOfMaxPrayerStreakTimeInterval) }
        set { dateOfMaxPrayerStreakTimeInterval = newValue.timeIntervalSince1970 }
    }
    @AppStorage("lastStreakDate") var lastStreakDate_TI: Double = Date().timeIntervalSince1970
    var lastStreakDate: Date {
        get { return Date(timeIntervalSince1970: lastStreakDate_TI) }
        set { lastStreakDate_TI = newValue.timeIntervalSince1970 }
    }

    // used appstorage for persistence purposes. but otherwise really not needed.
    @AppStorage("locationPrints") var locationPrints: Bool = false
    @AppStorage("schedulePrints") var schedulePrints: Bool = false
    @AppStorage("calculationPrints") var calculationPrints: Bool = false

    let orderedPrayerNames: [String] = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        
    var notifSettings: [String: (allowNotif: Bool, allowNudges: Bool)] {
        [    "Fajr":    (fajrNotif,    fajrNudges),
             "Dhuhr":   (dhuhrNotif,   dhuhrNudges),
             "Asr":     (asrNotif,     asrNudges),
             "Maghrib": (maghribNotif, maghribNudges),
             "Isha":    (ishaNotif,    ishaNudges)      ]
    }
    
    // MARK: - Published & State
    @Published var cityName: String?
    @Published var useTestPrayers: Bool = false  // Add this property
    @Published var prayerTimesForDateDict: [String: (start: Date, end: Date, window: TimeInterval)] = [:]
    @Published var timeAtLastRefresh: Date
    @Published var prayerSettings: [String: Bool] = [:]
    @Published var todaysPrayers: [PrayerModel] = []
    @Published var validPrayersToday: Int = 0
    @Published var todaysScore: Double = 0.0

    // Add this property to PrayerViewModel
//    @Published var dailyScores: [Date: Double] = [:]


    @State private var refreshTimer: Timer?

    // MARK: - Computed Vars
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
    

    // MARK: - Location Stuff
    private let geocoder = CLGeocoder()
    private var lastGeocodeRequestTime: Date?
    private var lastAppLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()

    func handleLocationChange(for location: CLLocation?) {
        guard let location = location else {
            locationPrinter(">passed by the didUpdateLocation< - No location found")
            return
        }

        let now = Date()
        if let lastAppLocation = lastAppLocation {
            let distanceChange = lastAppLocation.distance(from: location)
            if let lastRequestTime = lastGeocodeRequestTime {
                if distanceChange < 500, now.timeIntervalSince(lastRequestTime) < 30 {
                    // if we reach here, we are skipping updates
                    return
                } else { locationPrinter("📍 New Location: \(location.coordinate.latitude), \(location.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | \(Int(now.timeIntervalSince(lastRequestTime))) > 30s?") }
            } else { locationPrinter("📍 New Location: \(location.coordinate.latitude), \(location.coordinate.longitude) -- \(Int(distanceChange)) > 50m ? | First geocoding request") }
        } else { locationPrinter("⚠️ First location update. Proceeding with geocoding.") }

        // If we return out of the if block, update location and proceed with geocoding
        locationPrinter("🌍 Triggering geocoding and prayer times fetch...")
        self.lastLatitude = location.coordinate.latitude
        self.lastLongitude = location.coordinate.longitude
        self.lastGeocodeRequestTime = Date()
        self.lastAppLocation = location
        updateCityName(for: location)
        fetchPrayerTimes(cameFrom: "updateLocation")

    }
    
    //used in 2 methods: sub_handleLocationChange() & refreshCityAndPrayerTimes()
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
                let oldCityName = self?.lastCityName
                self?.lastCityName = self?.cityName ?? "Error."
                if oldCityName != self?.lastCityName {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    
    func refreshCityAndPrayerTimes() { // used outside of viewmodel.
        guard let location = ENV_LocationManager.manager.location else {
            print("Location not available")
            return
        }
        updateCityName(for: location)
        fetchPrayerTimes(cameFrom: "refreshCityAndPrayerTimes")
    }


    // MARK: - Potential Utils
    func getPrayerTime(for prayerName: String, on date: Date) -> (start: Date, end: Date)? { //PrayerUtilsFlas
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

    func calcAdhanLibraryPrayerTimes(date: Date) -> PrayerTimes?{ //PrayerUtilsFlag
        guard let location = ENV_LocationManager.manager.location else {
            print("Location not available")
            return nil
        }
        
        // Update latitude and longitude
        lastLatitude = location.coordinate.latitude
        lastLongitude = location.coordinate.longitude

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let params = PrayerUtils.getCalculationParameters()
        
        guard let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else{
            print("failed generating PrayerTimes object using Adhan libary")
            return nil
        }
        return times
    }

    // MARK: - Prayer Scheduling
        
    // the current one im working on.
    func fetchPrayerTimes(cameFrom: String) {
        print("@@ came from: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ \(cameFrom)")
        guard let times = calcAdhanLibraryPrayerTimes(date: Date()) else{
            print("failed using calcAdhanLibraryPrayerTimes() to build a valid a PrayerTimes object")
            return
        }
        
        // My new proposed way of just having calc var shown on prayerButtons. Dont store nothing in persistence UNTIL COMPLETION or MISSED
        //-------------------------------------------------------------------
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60))
        let midnightMinusOneSec = midnight.addingTimeInterval(-1)
        
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
        
        prayerTimesForDateDict = useTestPrayers ? testTimes : realTimes
                
        //-------------------------------------------------------------------
        
        ////  CURRENT OBJECTIVE: 12/2 @ 5:04PM just commented this out and gonna try making it dependent on the calc vars from Adhan. Then create the persisted prayerModel objects on completion instead... this is the start of a big rethinking of our current archtiecture to handle the prayers. The current code as it stands will not work because now thelast5Prayers rely on the persisted objects which are then fed into PulseCircleView and PrayerButton.
        
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
            saveChanges()
        } catch {
            print("❌ Error fetching existing prayers: \(error.localizedDescription)")
        }
        
        func saveChanges() {
            do {
                try context.save()
                let params = PrayerUtils.getCalculationParameters()
                calculationPrinter("👍 \(params.method) & \(params.madhab) & latitude: \(lastLatitude), longitude: \(lastLongitude)")
            } catch {
                print("🚨 Failed to save prayer state: \(error.localizedDescription)")
            }
        }
        //-------------------------------------------------------------------
        
        scheduleAllPrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
    }
    
    // MARK: - Notification Scheduling

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

    private func isNotCompletedToday(prayerName: String) -> Bool{
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

    
// MARK: - PrayerObject Utils

    /*
     moved to using Model based functions and calling directly on prayer instead of constantly passing it in. Cleaner seperation of responsibilities.
     func togglePrayerCompletion(for prayer: PrayerModel) {
         triggerSomeVibration(type: .medium)
         
         if prayer.startTime <= Date() {
             prayer.isCompleted.toggle()
             if prayer.isCompleted {
                 setPrayerScore(for: prayer)
                 setPrayerLocation(for: prayer)
                 cancelUpcomingNudges(for: prayer.name)
             } else {
                 prayer.resetPrayer()
             }
             calculatePrayerStreak()
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
        guard let location = ENV_LocationManager.manager.location else {
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
     */

    func togglePrayerCompletion(for prayer: PrayerModel) {
        triggerSomeVibration(type: .medium)
        
        if prayer.startTime <= Date() {
            prayer.isCompleted.toggle()
            if prayer.isCompleted {
                prayer.setPrayerScore()
                prayer.setPrayerLocation(with: ENV_LocationManager.manager.location)
                prayer.cancelUpcomingNudges()
            } else {
                prayer.resetPrayer()
            }
            calculatePrayerStreak()
            calculateDayScore(for: prayer.startTime)
//            updatePrayerStreak()
        }
    }
    
    /*
     lets say we have a streak counter already.
     we just wait for today to get 5. then add one to it.
     otherwise if day is over and didnt get to 5, then we kill the streak.
     also if they skipped a day inbetween then we kill the streak.
     we will allow this to run only if a prayer from today is marked as complete.
     we will ignore any incompletions.
      */

//    func calculatePrayerStreak() {
//        let now = Date()
//        let todayStart = Calendar.current.startOfDay(for: now)
//        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!.addingTimeInterval(-1)
//        var satisfiedForToday: Bool = false //need to use this somehow to know wether we increment or go back. but they shouldnt be able to game the system and toggle the 5th prayer back and forth to increment the streak.
//        // Fetch prayers for today
//        var todayPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
//            predicate: #Predicate<PrayerModel> {
//                $0.startTime >= todayStart && $0.startTime <= todayEnd
//            }
//        )
//        todayPrayersFetchDescriptor.fetchLimit = 5
//        
//        guard let todayPrayers = try? context.fetch(todayPrayersFetchDescriptor) else {
//            print("❌ Failed to fetch today's prayers")
//            return
//        }
//        
//        let prayersSatisfyGrading = todayPrayers.allSatisfy({ gradingCriteria(for: $0) })
//        let has5PrayerObjects = todayPrayers.count == 5
//        
//        if prayersSatisfyGrading && has5PrayerObjects {
//            // All 5 prayers for today are valid, increment streak
//            //prayerStreak += 1
//            satisfiedForToday = true
//
//        } else {
//            // Day is over and didn't get to 5 valid prayers, reset streak
//            //prayerStreak = 0
//            satisfiedForToday = false
//        }
//        if satisfiedForToday{
//            prayerStreak += 1
//        }
//        
//        // Update max streak if necessary
//        if prayerStreak > maxPrayerStreak {
//            maxPrayerStreak = prayerStreak
//            dateOfMaxPrayerStreak = now
//        }
//    }

    
    func calculateDayScore(for date: Date) {
        let today = Date()
        let updatingToday = Calendar.current.isDate(date, inSameDayAs: today)
        var runningScore: Double = 0.0
        var objectsToCheck: [PrayerModel] = updatingToday ? todaysPrayers : loadPrayerObjects(for: date)
        
        for name in /*viewModel.*/orderedPrayerNames {
            if let prayer = /*viewModel.*/objectsToCheck.first(where: { $0.name == name }){
                let thisWeightedScore = prayer.weightedSummaryScoreFromNumberScore()
                runningScore += thisWeightedScore
                print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with score: \(thisWeightedScore)")
            }
        }
//        let returnVal = runningScore / 5
//        if updatingToday {todaysScore = /*todaysScore*/ returnVal}
//        else {dailyScores[date] = returnVal}
        
        let dayScore = runningScore / 5
//        dailyScores[Calendar.current.startOfDay(for: date)] = dayScore
        if updatingToday { todaysScore = dayScore }
        saveDailyScore(for: date, score: dayScore)

    }
    
    
    // Add this method to PrayerViewModel to save a daily score to SwiftData
    func saveDailyScore(for date: Date, score: Double) {
//        let todayStart = Calendar.current.startOfDay(for: now)
//        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!.addingTimeInterval(-1)
//
//        // Fetch prayers for today
//        let todayPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
//            predicate: #Predicate<PrayerModel> {
//                $0.startTime >= todayStart && $0.startTime <= todayEnd
//            }
//        )
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-1)
        
        // Check if a record for this date already exists
        let fetchDescriptor = FetchDescriptor<DailyPrayerScore>(
            predicate: #Predicate<DailyPrayerScore> {
//                Calendar.current.startOfDay(for: $0.date) == startOfDay
                $0.date >= startOfDay && $0.date <= startOfDay
            }
        )
        
        do {
            let existingRecords = try context.fetch(fetchDescriptor)
            
            if let existingRecord = existingRecords.first {
                // Update existing record
                existingRecord.averageScore = score
                // We could also update individual prayer scores here if needed
            } else {
                // Create new record
                let newDailyScore = DailyPrayerScore(date: startOfDay)
                newDailyScore.averageScore = score
                context.insert(newDailyScore)
            }
            
            try context.save()
        } catch {
            print("❌ Error saving daily prayer score: \(error.localizedDescription)")
        }
    }
    
    // Add this to PrayerViewModel
/*
 func loadDailyScores() {
        let fetchDescriptor = FetchDescriptor<DailyPrayerScore>()
        
        do {
            let records = try context.fetch(fetchDescriptor)
            
            // Initialize the dictionary
            dailyScores = [:]
            
            // Populate the dictionary
            for record in records {
                let dayStart = Calendar.current.startOfDay(for: record.date)
                if let score = record.averageScore {
                    dailyScores[dayStart] = score
                }
            }
        } catch {
            print("❌ Error loading daily prayer scores: \(error.localizedDescription)")
        }
    }
  */
    
//    func calculateDayScore(for date: Date) {
////        todaysScore = 0
//        var runningScore: Double = 0.0
//        for name in /*viewModel.*/orderedPrayerNames {
//            if let prayer = /*viewModel.*/todaysPrayers.first(where: { $0.name == name }){
//                let thisWeightedScore = prayer.weightedSummaryScoreFromNumberScore()
////                summaryInfo[name] = thisWeightedScore
//                /*todaysScore*/ runningScore += thisWeightedScore
//                print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with score: \(thisWeightedScore)")
//            }
//        }
//        
//        todaysScore = /*todaysScore*/ runningScore / 5
//    }

    //most recent one
    func calculatePrayerStreak() {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let lastStreakDateStart = Calendar.current.startOfDay(for: lastStreakDate)
        
        checkToResetStreak()
                
        guard let todayPrayers = getTodaysPrayersFromContext() else{ return }
        let validPrayersToday = todayPrayers.filter { gradingCriteria(for: $0) }.count
        self.validPrayersToday = validPrayersToday
        let decrementStreak = validPrayersToday < 5 && lastStreakDateStart == todayStart

        if validPrayersToday == 5 { // if we get 5 then increment and move the streak date up
            prayerStreak += 1
            lastStreakDate = now
        } else if decrementStreak { // only decrement if we have gotten to 5 alteady and they came donw.
            prayerStreak -= 1
        }

        // Update max streak if necessary
        if prayerStreak > maxPrayerStreak {
            maxPrayerStreak = prayerStreak
            dateOfMaxPrayerStreak = now
        }
        
        func getTodaysPrayersFromContext() -> [PrayerModel]? {
            let todayStart = Calendar.current.startOfDay(for: now)
            let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!.addingTimeInterval(-1)

            // Fetch prayers for today
            let todayPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate<PrayerModel> {
                    $0.startTime >= todayStart && $0.startTime <= todayEnd
                }
            )
            guard let todayPrayers = try? context.fetch(todayPrayersFetchDescriptor) else {
                print("❌ Failed to fetch today's prayers")
                return nil
            }
            return todayPrayers
        }
    }
    
    func gradingCriteria(for prayer: PrayerModel) -> Bool {
        switch prayerStreakMode {
        case 1:
            return prayer.isCompleted
        case 2:
            return (prayer.numberScore ?? 0) > 0
        default:
            return (prayer.numberScore ?? 0) > 0.25
        }
    }
    
    func checkToResetStreak() {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart)!
        let lastStreakDateStart = Calendar.current.startOfDay(for: lastStreakDate)
        
        // Check if there's a gap between lastStreakDate and today
        let resetStreak = ( lastStreakDateStart != todayStart && lastStreakDateStart != yesterdayStart )
        if resetStreak {
            prayerStreak = 0 // Reset streak if there's a gap
            lastStreakDate = yesterdayStart
        }
    }

    
    //this one fetches a day of prayers from context and loops backwards. But flaw: 1. its starting from yesterday. 2. its loop based. 3. requires database fetching... not a fan.
//    func calculatePrayerStreak() {
//        print("------ starting the calculation")
//        let calendar = Calendar.current
//        let now = Date()
//        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
//        
//        var currentStreak = 0
//        var currentDate = calendar.startOfDay(for: yesterday)
//        
//        while true {
//            let dayStart = currentDate
//            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(-1)
//            
//            // Fetch prayers for the specific day
//            let prayersForDayFetchDescriptor = FetchDescriptor<PrayerModel>(
//                predicate: #Predicate<PrayerModel> {
//                    $0.startTime >= dayStart && $0.startTime <= dayEnd
//                }
//            )
//            
//            guard let prayersForDay = try? context.fetch(prayersForDayFetchDescriptor) else {
//                print("❌ Failed to fetch prayers for day \(currentDate)")
//                break
//            }
//            
//            if prayersForDay.count == 5 && prayersForDay.allSatisfy({ gradingCriteria(for: $0) }) {
//                print("\(currentStreak): \(currentDate)")
//                currentStreak += 1
//                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
//            } else {
//                break
//            }
//        }
//         
//         prayerStreak = currentStreak
//         
//         // Update max streak if necessary
//         if prayerStreak > maxPrayerStreak {
//             maxPrayerStreak = prayerStreak
//             dateOfMaxPrayerStreak = Date()
//         }
//        
//        func gradingCriteria(for prayer: PrayerModel) -> Bool{
//            if prayerStreakMode == 1 {
//                prayer.isCompleted
//            }
//            else if prayerStreakMode == 2 {
//                prayer.numberScore ?? 0 > 0
//            }
//            else {
//                prayer.numberScore ?? 0 > 0.25
//            }
//        }
//    }

  
//    func calculatePrayerStreak(){ //prayerstreak_flag main logic
//                
//        /*
//         NEW LOGIC:
//         - calculate by days
//         fetch all completed prayers from today.
//         if it totals to 5 AND all pass the grading then we are good.
//         Grading criteria:
//            > 1 includes kazas
//            > 2 on time
//            > 3. anything not in the red zone (aka 25% score or up)
//         have to
//         */
//        // Fetch prayers that are in the past
//        
//        
//
//
//        
//        // Fetch prayers for the current day from context...
//        let todayStart = Calendar.current.startOfDay(for: Date())
//        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)?.addingTimeInterval(-1) ?? Date()
//        var prayerFromTodayFetchDescriptor = FetchDescriptor<PrayerModel>(
//            predicate: #Predicate<PrayerModel> { $0.startTime >= todayStart && $0.startTime <= todayEnd},
//            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
//        )
//        prayerFromTodayFetchDescriptor.fetchLimit = 5
//        
//        // alternatively we can fetch all the prayers ever and loop through them...
//        let now = Date()
//        var allPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
//            predicate: #Predicate<PrayerModel> { $0.startTime <= now},
//            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
//        )
//        
//        // Fetch from the database
//        guard let prayersFromToday = try? context.fetch(prayerFromTodayFetchDescriptor) else {
//            print("❌ Failed to fetch prayers for streak.")
//            return
//        }
//        
//        guard let allPrayersInDatabase = try? context.fetch(allPrayersFetchDescriptor) else {
//            print("❌ Failed to fetch prayers for streak.")
//            return
//        }
//
//        for prayer in prayersFromToday {
//            if gradingCriteria(for: prayer) {
//                //then we can continue i guess...
//            }
//        }
//
////        //set a new max streak if the current streak is greateer than the max streak
////                if prayerStreak > maxPrayerStreak {
////                    maxPrayerStreak = prayerStreak
////                    dateOfMaxPrayerStreak = Date()
////                }
//        
//        func gradingCriteria(for prayer: PrayerModel) -> Bool{
//            if prayerStreakMode == 1 {
//                prayer.isCompleted
//            }
//            else if prayerStreakMode == 2 {
//                prayer.numberScore ?? 0 > 0
//            }
//            else {
//                prayer.numberScore ?? 0 > 0.25
//            }
//        }
//    }

    
    /*
    func calculatePrayerStreak(){ //prayerstreak_flag main logic
                
        /*
         NEW LOGIC:
         - calculate by days
         fetch all completed prayers from today.
         if it totals to 5 then we are good.
         Grading criteria:
            > 1 on time
            > 2 kazas
         */
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
     */

    func loadPrayerObjects(for date: Date? = nil) -> [PrayerModel] {
        let targetDate = date ?? Date() // Use the provided date or default to the current date
        let dayStart = Calendar.current.startOfDay(for: targetDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? Date()
        
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime >= dayStart && $0.startTime <= dayEnd },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        fetchDescriptor.fetchLimit = 5

        do {
            let prayers = try context.fetch(fetchDescriptor)
            printPrayersOutput(prayers, for: targetDate)
            return prayers
        } catch {
            print("❌ (loadPrayerObjects) Error occurred during the fetch attempt. \(error.localizedDescription)")
            return []
        }
    }
    
    func loadPrayerObjectsV2_AccountsForEmptyPrayerObjects_NotTested(for date: Date? = nil) -> [PrayerModel] {
        let targetDate = date ?? Date() // Use the provided date or default to the current date
        let dayStart = Calendar.current.startOfDay(for: targetDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? Date()
        
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.startTime >= dayStart && $0.startTime <= dayEnd },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        fetchDescriptor.fetchLimit = 5

        do {
            var prayers = try context.fetch(fetchDescriptor)
            for name in orderedPrayerNames {
                let searchForThisName = prayers.first(where: { $0.name == name })
                if searchForThisName == nil{
                    let newPrayer = createPrayerModel(name: name, at: targetDate)
                    prayers.append(newPrayer)
                }
            }
            printPrayersOutput(prayers, for: targetDate)
            return prayers
        } catch {
            print("❌ (loadPrayerObjects) Error occurred during the fetch attempt. \(error.localizedDescription)")
            return []
        }
    }

    func printPrayersOutput(_ prayers: [PrayerModel], for date: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        print("--------------------------- loadPrayerObjects()")
        print("\(prayers.count) PRAYER OBJECT(S) FOR \(dateFormatter.string(from: date)):")
        for (index, prayer) in prayers.enumerated() {
            print("Prayer \(index + 1): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(shortTimePM(prayer.startTime)) - \(shortTimePM(prayer.endTime))")
        }
        print("---------------------------")
    }
    
    
    func loadTodaysPrayerObjects(){
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
        
        printTodaysPrayersOutput()
        
        func printTodaysPrayersOutput(){
            var index = 1
            print("--------------------------- loadTodaysPrayerObjects()")
            print("\(todaysPrayers.count) PRAYER OBJECT FOR TODAY:")
            for prayer in todaysPrayers {
                print("Prayer \(index): (\(prayer.isCompleted ? "☑" : "☐")) \(prayer.name) : \(shortTimePM(prayer.startTime)) - \(shortTimePM(prayer.endTime))"); index += 1
            }
            print("---------------------------")
        }
    }
    
    // For Sun Based Color Scheme:
    var isDaytime: Bool {
        // Get the Fajr prayer time
        guard let fajr = prayerTimesForDateDict["Fajr"], let maghrib = prayerTimesForDateDict["Maghrib"] else {
            return true // Default to daytime if no times are available
        }
        let now = Date()
        
        // Check if the current time is between Fajr and 5:35 PM
        let isAfterFajr = now >= fajr.end
        let isBeforeMaghrib = now < maghrib.start /*testCutOffDate*/
        let isDaytime = isAfterFajr && isBeforeMaghrib
        return isDaytime
    }
    
    
}


// MARK: - Specialized Debug Printers

extension PrayerViewModel{
    
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

}

// MARK: - Non Location Functions

extension PrayerViewModel {
    
    private func scheduleDailyRefresh() { // this doesnt work when app is closed... but if its open before midnight and left open until... then it should work
        let calendar = Calendar.current
        if let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) {
            let timeInterval = midnight.timeIntervalSince(Date())
            
            print("next refresh scheduled for \(midnight) in \(timerStyle(timeInterval))")
            refreshTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
                self.timeAtLastRefresh = Date()
                self.fetchPrayerTimes(cameFrom: "scheduleDailyRefresh")
                self.scheduleDailyRefresh() // Schedule the next update
            }
        }
    }

}



extension PrayerViewModel {
    
    func createPrayerModel(name prayerName: String, at date: Date) -> PrayerModel {
        guard let times = getPrayerTime(for: prayerName, on: date) else {
            fatalError("Failed to get prayer times for \(prayerName) on \(date)")
        }
        
        let newPrayer = PrayerModel(
            name: prayerName,
            startTime: times.start,
            endTime: times.end,
            dateAtMake: date
        )
        
        context.insert(newPrayer)
        try? context.save()
        
        return newPrayer
    }
}
