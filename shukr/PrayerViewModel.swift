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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoStreakBackfill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.demoStreakBackfill() }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPrayerDayKeyTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.demoPrayerDayKeyTest() }
        }
        #endif
//        self.loadDailyScores()

    }
    
    private func subscribeToChanges(){
        // Subscribe to userLocation changes
        ENV_LocationManager.locationUpdates
            .sink { [weak self] newVal in
                self?.handleLocationChange(for: newVal)
            }
            .store(in: &cancellables)
        // The clock or the time zone changed (travel, DST, a corrected clock; audit B12): the times, the rows, the
        // reminders (calendar triggers would fire at the old wall-clock) and the rollover timer follow.
        for name in [UIApplication.significantTimeChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    NSTimeZone.resetSystemTimeZone()
                    self?.fetchPrayerTimes(cameFrom: "time or zone change")
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - AppStorage
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0

    @AppStorage("fajrNotif") var fajrNotif: Bool = NotificationDefaults.notify("Fajr")
    @AppStorage("dhuhrNotif") var dhuhrNotif: Bool = NotificationDefaults.notify("Dhuhr")
    @AppStorage("asrNotif") var asrNotif: Bool = NotificationDefaults.notify("Asr")
    @AppStorage("maghribNotif") var maghribNotif: Bool = NotificationDefaults.notify("Maghrib")
    @AppStorage("ishaNotif") var ishaNotif: Bool = NotificationDefaults.notify("Isha")
    
    @AppStorage("fajrNudges") var fajrNudges: Bool = NotificationDefaults.nudges("Fajr")
    @AppStorage("dhuhrNudges") var dhuhrNudges: Bool = NotificationDefaults.nudges("Dhuhr")
    @AppStorage("asrNudges") var asrNudges: Bool = NotificationDefaults.nudges("Asr")
    @AppStorage("maghribNudges") var maghribNudges: Bool = NotificationDefaults.nudges("Maghrib")
    @AppStorage("ishaNudges") var ishaNudges: Bool = NotificationDefaults.nudges("Isha")

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
    /// In-time days: days in a row with all five prayed within their windows (no Qaza, none
    /// missed; score ≥ 60), and the last day that counted. Keys keep their old "onTime" names.
    /// (Was all five Early / On time until 2026-09-25.)
    @AppStorage("onTimeStreak") var onTimeStreak: Int = 0
    @AppStorage("maxOnTimeStreak") var maxOnTimeStreak: Int = 0
    @AppStorage("lastOnTimeStreakDate") var lastOnTimeStreakDate_TI: Double = 0
    /// Last day celebrated as a perfect day (all five within their windows), so it fires once.
    @AppStorage("lastPerfectDay") var lastPerfectDay_TI: Double = 0
    @AppStorage("lastStreakDate") var lastStreakDate_TI: Double = 0   // audit B15: "today" by default made a fresh install count today (1 Day Streak)
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


    private var refreshTimer: Timer?   // a plain property (audit B2): `@State` does nothing outside a View, so the timer could never be re-planned

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
                // Under 500 m and under 10 min since the last pass: nothing to do (audit B3 — every 30 s a stationary
                // phone re-geocoded, re-fetched, re-planned ~7 days of reminders and 60 alarms; CLGeocoder then
                // rate-limited and "Error fetching city" reached the widgets).
                if distanceChange < 500, now.timeIntervalSince(lastRequestTime) < 600 {
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
        if travelled {
            print("🧳 moved \(Int(moved / 1000)) km: updating times, widgets, watch")
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.send()
        }
        updateCityName(for: location)
        fetchPrayerTimes(cameFrom: "updateLocation")

    }
    
    //used in 2 methods: sub_handleLocationChange() & refreshCityAndPrayerTimes()
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
    func refreshLocationNow() async -> Result<String, RefreshFailure> {
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

    func refreshCityAndPrayerTimes() { // used outside of viewmodel.
        guard let location = ENV_LocationManager.effectiveLocation else {
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

        // Isha ends at 11:59 PM (PrayerDay.ishaEnd); the rollover only extends marking it, as Qaza.
        let nextFajr = Calendar.current.date(byAdding: .day, value: 1, to: date).flatMap { calcAdhanLibraryPrayerTimes(date: $0)?.fajr }
        let ishaEnd = PrayerDay.ishaEnd(on: date, ishaStart: times.isha, nextFajr: nextFajr)

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
            return (times.isha, ishaEnd)
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
        guard let location = ENV_LocationManager.effectiveLocation else {
            print("Location not available")
            return nil
        }
        
        // Update latitude and longitude
        storeLastCoordinate(location.coordinate)

        // Set up Adhan parameters
        let coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let components = PrayerUtils.gregorian.dateComponents([.year, .month, .day], from: date)
        let params = PrayerUtils.getCalculationParameters()
        
        guard let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else{
            print("failed generating PrayerTimes object using Adhan libary")
            return nil
        }
        return times
    }

    /// Writes the app-group `lastLatitude` / `lastLongitude` only when they actually moved. Every
    /// write to that suite invalidates every @AppStorage bound to it (Settings, the root), so
    /// rewriting the same coordinate on each prayer-time calculation re-rendered them for nothing.
    /// A fix worth recording as where a prayer was prayed (audit B10): under 10 min old and within 500 m. `nil` = no spot.
    static func usableFix(_ location: CLLocation?) -> CLLocation? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500,
              Date().timeIntervalSince(location.timestamp) < 600 else { return nil }
        return location
    }

    private func storeLastCoordinate(_ c: CLLocationCoordinate2D) {
        // ~50 m: GPS jitter is metres per fix and can't change prayer times or the qibla.
        if abs(lastLatitude - c.latitude) > 5e-4 { lastLatitude = c.latitude }
        if abs(lastLongitude - c.longitude) > 5e-4 { lastLongitude = c.longitude }
    }

    // MARK: - Prayer Scheduling
        
    // the current one im working on.
    func fetchPrayerTimes(cameFrom: String) {
        print("@@ came from: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ \(cameFrom)")
        // "Today" is the prayer day: before the rollover hour it's still yesterday's calendar date.
        let prayerDate = PrayerDay.date()
        guard let times = calcAdhanLibraryPrayerTimes(date: prayerDate) else{
            print("failed using calcAdhanLibraryPrayerTimes() to build a valid a PrayerTimes object")
            return
        }
        
        // My new proposed way of just having calc var shown on prayerButtons. Dont store nothing in persistence UNTIL COMPLETION or MISSED
        //-------------------------------------------------------------------
        let nextFajr = Calendar.current.date(byAdding: .day, value: 1, to: prayerDate).flatMap { calcAdhanLibraryPrayerTimes(date: $0)?.fajr }
        let ishaEnd = PrayerDay.ishaEnd(on: prayerDate, ishaStart: times.isha, nextFajr: nextFajr)
        
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
            "Isha": timesAndWindow(times.isha, ishaEnd)
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
        
        // The prayer day's rows: keyed by the calendar day of `prayerDate`.
        let dayStartOfPrayerDate = Calendar.current.startOfDay(for: prayerDate)
        var changed = false   // a row inserted or its times moved (audit B2)
        
        do {
            // Fetch prayers for the current day from the context
            // Every row of the day. It had `fetchLimit = 5` (sorted by time): once a day held a sixth
            // row (a moved / edited / imported one), Maghrib and Isha fell outside the five and a new
            // pair was inserted on every refresh — hundreds of duplicates, and a map that couldn't
            // draw (2026-09-27). `removeDuplicatePrayerRows` cleans up what that left.
            let fetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: PrayerDay.rowsPredicate(forDayStarting: dayStartOfPrayerDate),   // 2.8.0: by prayer day
                sortBy: [SortDescriptor(\.startTime, order: .forward)]
            )
            let existingPrayers = try self.context.fetch(fetchDescriptor)

            // Define prayer names and times
            for name in orderedPrayerNames {

                guard let thisPrayerInDict = prayerTimesForDateDict[name] else{
                    calculationPrinter("\(name) missing from prayerTimesForDateDict")
                    return
                }
                
                let startTime = thisPrayerInDict.start; let endTime = thisPrayerInDict.end
                // A completed row wins over an unmarked one with the same name.
                if let persisted = existingPrayers.first(where: { $0.name == name && $0.isCompleted })
                    ?? existingPrayers.first(where: { $0.name == name }) {
                    // Update existing prayer if not completed and times differ
                    if !persisted.isCompleted && ( persisted.startTime != startTime || persisted.endTime != endTime ) {
                        calculationPrinter(overwritePrayerStart: (name: name, startTime: startTime, oldStartTime: persisted.startTime))
                        persisted.startTime = startTime
                        persisted.endTime = endTime
                        changed = true
                    }
                } else {
                    // Insert new prayer
                    let newPrayer = PrayerModel( name: name, startTime: startTime, endTime: endTime )
                    self.context.insert(newPrayer)
                    changed = true
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
        
        // The rows on screen follow (audit B2): a new day's rows (the day turned while the app was open) or moved times
        // reached `todaysPrayers` only at the next appear — the circle and the list stayed on yesterday, and after a
        // resume the list could be empty.
        let todayKey = PrayerDay.key()
        if changed || todaysPrayers.isEmpty || todaysPrayers.contains(where: { $0.dayKey != todayKey }) {
            loadTodaysPrayerObjects()
        }
        scheduleDailyRefresh()   // Fajr moves with the place: the rollover timer follows the times
        scheduleAllPrayerNotifications(prayerByDateDict: prayerTimesForDateDict)
    }
    
    // MARK: - Notification Scheduling

    /// All prayer notifications, several days ahead (NotificationScheduler, 2026-09-27). Used to
    /// wipe everything pending and schedule only the current prayer day, which dropped Fajr once
    /// the day turned at Fajr, and deleted snoozes.
    func scheduleAllPrayerNotifications(prayerByDateDict: [String : (start: Date, end: Date, window: TimeInterval)]) {
        Task { @MainActor in
            NotificationScheduler.reschedule(context: context,
                                             todayOverride: useTestPrayers ? prayerByDateDict : nil,
                                             reason: "prayer times")
        }
    }

    private func isNotCompletedToday(prayerName: String) -> Bool{
        let (todayStart, todayEnd) = PrayerDay.rowRange(forDayStarting: PrayerDay.start())
        let todayKey = PrayerDay.key()
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { ($0.prayerDayKey == todayKey || ($0.prayerDayKey == nil && $0.startTime >= todayStart && $0.startTime <= todayEnd)) && $0.name == prayerName }
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


    /// Moves a prayer's pin (PrayerLocationPicker, 2026-09-26) and asks again whether it was at a
    /// masjid: one of your masajid is known at once, anywhere else the search runs after. The score
    /// follows — a Friday Dhuhr moved onto a masjid becomes Jumu'ah, moved off one it's scored by
    /// the clock again.
    @MainActor func movePrayer(_ prayer: PrayerModel, to spot: CLLocationCoordinate2D) {
        if TourRuntime.shared.isPractice(prayer) {   // the tour's pretend prayer: nothing saved
            prayer.latPrayedAt = spot.latitude
            prayer.longPrayedAt = spot.longitude
            objectWillChange.send()
            return
        }
        // Keep where the app recorded it, the first time it's moved (so it can be put back).
        if prayer.recordedLat == nil, let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt {
            prayer.recordedLat = lat
            prayer.recordedLon = lon
        }
        prayer.latPrayedAt = spot.latitude
        prayer.longPrayedAt = spot.longitude
        prayer.mosqueName = MasjidDetector.favoriteMasjid(near: spot)   // nil = search below
        if prayer.isCompleted { prayer.setPrayerScore(atDate: prayer.timeAtComplete ?? prayer.startTime) }
        calculateDayScore(for: prayer.startTime)
        calculatePrayerStreak()
        pushCompletionsToWidget()
        objectWillChange.send()
        guard prayer.mosqueName == nil else { return }
        Task { @MainActor in
            let days = await MasjidDetector.check([prayer], in: context)
            guard !days.isEmpty else { return }
            for day in days { calculateDayScore(for: day) }
            pushCompletionsToWidget()
            objectWillChange.send()
        }
    }

    /// Back to the spot the app recorded (then it's unedited again).
    @MainActor func revertPrayerLocation(_ prayer: PrayerModel) {
        guard let recorded = prayer.recordedSpot else { return }
        movePrayer(prayer, to: recorded)
        prayer.recordedLat = nil
        prayer.recordedLon = nil
    }

    /// A user's time edit (the time editor): keeps the recorded time, rescores, updates the day.
    func editPrayerTime(_ prayer: PrayerModel, to date: Date) {
        if TourRuntime.isPracticeAnywhere(prayer) {   // the tour's pretend prayer: nothing saved
            prayer.editTime(to: date)
            objectWillChange.send()
            return
        }
        prayer.editTime(to: date)
        afterTimeChange(prayer)
    }
    func revertPrayerTime(_ prayer: PrayerModel) {
        prayer.revertTime()
        afterTimeChange(prayer)
    }
    private func afterTimeChange(_ prayer: PrayerModel) {
        calculateDayScore(for: prayer.startTime)
        calculatePrayerStreak()
        pushCompletionsToWidget()
        objectWillChange.send()
    }

    func togglePrayerCompletion(for prayer: PrayerModel) {
        // The tour's pretend prayer: the moment plays, nothing is saved, scored into streaks, sent to widgets or rescheduled.
        if TourRuntime.isPracticeAnywhere(prayer) {
            if !prayer.isCompleted {
                prayer.isCompleted = true
                prayer.setPrayerScore()
                PrayerCompletionHaptics.play()
                let window = prayer.endTime.timeIntervalSince(prayer.startTime)
                let progress = window > 0 ? Date().timeIntervalSince(prayer.startTime) / window : 1
                NotificationCenter.default.post(name: .prayerCompleted, object: PrayerCompletionEvent(
                    name: prayer.displayName, score: prayer.numberScore ?? 0, progress: min(max(progress, 0), 1),
                    summary: prayer.scoreSummary, prayerName: prayer.name))
            } else {
                triggerSomeVibration(type: .medium)
                prayer.resetPrayer()
            }
            objectWillChange.send()
            return
        }
        if prayer.startTime <= Date() {
            prayer.isCompleted.toggle()
            if prayer.isCompleted {
                let fix = Self.usableFix(ENV_LocationManager.manager.location)
                prayer.setPrayerLocation(with: fix)
                // At one of your own masajid: known at once, so a Jumu'ah is scored (and shown)
                // as Jumu'ah right away. Anywhere else the MasjidDetector search below decides —
                // only from an accurate fix (audit B10): a coarse one put a prayer at a mosque it wasn't near.
                if let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt {
                    if let fix, fix.horizontalAccuracy <= 100 {
                        prayer.mosqueName = MasjidDetector.favoriteMasjid(near: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    } else {
                        prayer.mosqueName = ""   // checked: no masjid search for this row
                    }
                }
                prayer.setPrayerScore()
                prayer.cancelUpcomingNudges()
                // The completion moment: haptic + flourish on the circle + the row's pop (PrayerCompletionFX).
                PrayerCompletionHaptics.play()
                let window = prayer.endTime.timeIntervalSince(prayer.startTime)
                let progress = window > 0 ? Date().timeIntervalSince(prayer.startTime) / window : 1
                NotificationCenter.default.post(name: .prayerCompleted, object: PrayerCompletionEvent(
                    name: prayer.displayName, score: prayer.numberScore ?? 0, progress: min(max(progress, 0), 1),
                    summary: prayer.scoreSummary, prayerName: prayer.name))
            } else {
                triggerSomeVibration(type: .medium)
                prayer.resetPrayer()
            }
            calculatePrayerStreak()
            calculateDayScore(for: prayer.startTime)
//            updatePrayerStreak()
            pushCompletionsToWidget()
            // Prayed at a masjid? (Jumu'ah gets full marks.)
            if prayer.isCompleted {
                Task { @MainActor in
                    let days = await MasjidDetector.check([prayer], in: context)
                    for day in days { calculateDayScore(for: day) }
                    if !days.isEmpty {
                        pushCompletionsToWidget()
                        objectWillChange.send()
                        // It turned out to be Jumu'ah: the moment, corrected (the right name and score), not replayed.
                        let window = prayer.endTime.timeIntervalSince(prayer.startTime)
                        let markedAt = prayer.timeAtComplete ?? Date()
                        let progress = window > 0 ? markedAt.timeIntervalSince(prayer.startTime) / window : 1
                        NotificationCenter.default.post(name: .prayerCompleted, object: PrayerCompletionEvent(
                            name: prayer.displayName, score: prayer.numberScore ?? 1, progress: min(max(progress, 0), 1),
                            summary: prayer.scoreSummary, prayerName: prayer.name, isCorrection: true))
                    }
                }
            }
        }
    }

    /// Rows marked outside the app (widget, notification) and older history: which were at a
    /// masjid. A few new spots per launch (MasjidDetector.catchUp).
    @MainActor func catchUpMasjidChecks() {
        MasjidDetector.catchUp(context: context) { [weak self] days in
            guard let self else { return }
            for day in days { self.calculateDayScore(for: day) }
            self.calculatePrayerStreak()
            self.pushCompletionsToWidget()
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Widget completions
    
    /// The widget writes prayer completions straight into the shared store. Our ModelContext
    /// may still hold cached copies of those rows, so when the widget says it wrote, commit
    /// anything pending, drop cached values, re-read, and redo the bits only the app can do.
    func reconcileAfterWidgetWrites() {
        let defaults = UserDefaults(suiteName: SharedStore.appGroup)
        guard defaults?.bool(forKey: SharedStore.widgetWroteStoreKey) == true else { return }
        defaults?.set(false, forKey: SharedStore.widgetWroteStoreKey)
        
        do {
            try context.save()
            context.rollback()      // refaults registered objects so the next fetch reads the store
        } catch {
            // The app's unsaved edits stay (audit B6): a rollback after a failed save threw them away.
            print("⚠️ reconcile: save failed, keeping the app's edits: \(error.localizedDescription)")
        }
        loadTodaysPrayerObjects()
        // Never the tour's practice rows (Ben's G8): they own no notifications.
        for prayer in todaysPrayers where prayer.isCompleted && !TourRuntime.isPracticeAnywhere(prayer) {
            prayer.cancelUpcomingNudges()   // the extension may not be able to reach our notification center
        }
        calculatePrayerStreak()
        calculateDayScore(for: PrayerDay.date())
        print("✅ reconciled widget completions: \(todaysPrayers.filter { $0.isCompleted }.map { $0.name })")
    }
    
    /// Flush and refresh the widget so an in-app completion shows there right away.
    func pushCompletionsToWidget() {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
        WatchSync.shared.send()                    // the watch's ✓s
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
        let today = PrayerDay.date()
        let updatingToday = Calendar.current.isDate(date, inSameDayAs: today)
        // During the tour `todaysPrayers` is its practice day: today is scored from the store's real rows, never the
        // practice ones (Bradley's review: a mid-tour widget / banner mark saved the practice score as today's).
        let practiceShown = TourRuntime.practiceMirror != nil
        let objectsToCheck: [PrayerModel] = updatingToday && !practiceShown ? todaysPrayers : loadPrayerObjects(for: date)
        // Average of the five prayers' points, unmarked = 0 (PrayerScoring).
        let dayScore = PrayerScoring.dayScore(for: objectsToCheck)
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
        guard !StoreFallback.active else { return }   // in-memory store (WF56): keep the saved streaks as they are
        let now = Date()
        let todayStart = PrayerDay.start(for: now)
        let lastStreakDateStart = PrayerDay.start(for: lastStreakDate)
        
        checkToResetStreak()
        // The old unmark path could subtract on every call and left some streaks negative.
        if prayerStreak < 0 { prayerStreak = 0 }

        guard let todayPrayers = getTodaysPrayersFromContext() else{ return }
        let validPrayersToday = todayPrayers.filter { gradingCriteria(for: $0) }.count
        self.validPrayersToday = validPrayersToday
        let decrementStreak = validPrayersToday < 5 && lastStreakDateStart == todayStart

        if validPrayersToday == 5 {
            // A day continues the streak once. This runs on every mark, time edit and widget
            // reconcile, and used to add 1 each time once all five were in (2026-09-24).
            if lastStreakDateStart != todayStart {
                prayerStreak += 1
                lastStreakDate = now
                NotificationCenter.default.post(name: .prayerStreakContinued, object: nil)
            }
        } else if decrementStreak { // today had counted and a prayer was unmarked
            prayerStreak = max(prayerStreak - 1, 0)
            // Today no longer counts: back to "counted through yesterday", so this can't
            // decrement again on the next call and re-completing today counts it again.
            lastStreakDate = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        }

        // Update max streak if necessary
        if prayerStreak > maxPrayerStreak {
            maxPrayerStreak = prayerStreak
            dateOfMaxPrayerStreak = now
        }

        updateDayMilestones(todayPrayers: todayPrayers, todayStart: todayStart, now: now)
        
        func getTodaysPrayersFromContext() -> [PrayerModel]? {
            // Fetch prayers for today (2.8.0: by prayer day key)
            let todayPrayersFetchDescriptor = FetchDescriptor<PrayerModel>(
                predicate: PrayerDay.rowsPredicate(forDayStarting: PrayerDay.start(for: now))
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
        case 2:   // prayed within its window (not Qaza)
            return prayer.isCompleted && (prayer.numberScore ?? 0) >= PrayerScoring.inWindowFloor - 0.0001
        default:  // on time or early
            return prayer.isCompleted && (prayer.numberScore ?? 0) >= 0.8
        }
    }
    
    /// The in-time days streak (all five within their windows: no Qaza, none missed) and the
    /// perfect day (all five Early), each counted once a day like the main streak. Posted after the main
    /// streak's notification so the top bar can play them in order.
    private func updateDayMilestones(todayPrayers: [PrayerModel], todayStart: Date, now: Date) {
        func doneNames(minScore: Double) -> Set<String> {
            Set(todayPrayers.filter { $0.isCompleted && ($0.numberScore ?? 0) >= minScore - 0.0001 }.map(\.name))
        }
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        // In-time days (owner, 2026-09-25: "days where there was no qaza"). The days before today
        // were just recounted from the rows (refreshStreaksFromHistory, via checkToResetStreak);
        // only today is added / taken back here, which is also where its celebration fires.
        let lastOnTime = PrayerDay.start(for: Date(timeIntervalSince1970: lastOnTimeStreakDate_TI))
        if doneNames(minScore: PrayerScoring.inWindowFloor).count == 5 {
            if lastOnTime != todayStart {
                onTimeStreak += 1
                lastOnTimeStreakDate_TI = now.timeIntervalSince1970
                maxOnTimeStreak = max(maxOnTimeStreak, onTimeStreak)
                NotificationCenter.default.post(name: .onTimeStreakContinued, object: nil)
            }
        } else if lastOnTime == todayStart {   // today had counted; a prayer was unmarked or re-timed
            onTimeStreak = max(onTimeStreak - 1, 0)
            lastOnTimeStreakDate_TI = yesterdayStart.timeIntervalSince1970
        }

        // Perfect day: all five Early (owner, 2026-09-25 — "only when everything is green")
        if doneNames(minScore: 1).count == 5,
           PrayerDay.start(for: Date(timeIntervalSince1970: lastPerfectDay_TI)) != todayStart {
            lastPerfectDay_TI = now.timeIntervalSince1970
            NotificationCenter.default.post(name: .perfectDay, object: nil)
        }
    }

    /// Runs on app activation and at the start of every streak update. It used to only zero the
    /// streak on a gap in `lastStreakDate`; now it recounts the days before today from the rows.
    func checkToResetStreak() {
        refreshStreaksFromHistory()
    }

    /// Streaks from the stored prayers, not incrementally from today (owner-approved fix,
    /// 2026-09-27): a prayer of an earlier prayer day marked late — a watch mark delivered after
    /// Fajr, the widget or "I already prayed" around Fajr, a time edit on an old prayer — completed
    /// that day but the streak never counted it, and the next day's gap check reset it to 0.
    ///
    /// The days BEFORE today are recounted from the rows (the run of consecutive complete days
    /// ending yesterday). Today is left to `calculatePrayerStreak` / `updateDayMilestones`, which add
    /// it once — and post its celebration — or take it back on an unmark: if today had already been
    /// counted it stays counted (run + 1), else the streak is the run and "counted through" is
    /// yesterday. Idempotent (a second call changes nothing) and silent: a past day never plays a
    /// celebration. Perfect day has no streak (its date only stops today's celebration repeating),
    /// so there's nothing to recount for it. Entry point for marks made elsewhere (the watch):
    /// `recomputeStreaks()`.
    func refreshStreaksFromHistory() {
        guard !StoreFallback.active else { return }   // an empty in-memory store would recount them to 0
        let now = Date()
        let todayStart = PrayerDay.start(for: now)
        let calendar = Calendar.current
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let five: Set<String> = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let inWindow = { (p: PrayerModel) in (p.numberScore ?? 0) >= PrayerScoring.inWindowFloor - 0.0001 }

        // Walk back from yesterday a week at a time and stop at the first day that breaks both runs
        // (a typical call reads one or two weeks of rows, not 1000 days — it runs on every Salah
        // page appear and every mark). Rows are keyed by the calendar day their prayers start on.
        var streakRun = 0, inTimeRun = 0
        var streakAlive = true, inTimeAlive = true
        var batchEnd = todayStart                     // exclusive
        var day = yesterdayStart
        batches: for _ in 0..<150 {                   // ≤ ~1000 days
            guard let batchStart = calendar.date(byAdding: .day, value: -7, to: batchEnd) else { break }
            // 2.8.0: a day's Isha can start after midnight, so fetch 6 h past the batch and group rows by their own
            // prayer day; rows whose day lies before this batch wait for the next one (it fetches them).
            let fetchEnd = batchEnd.addingTimeInterval(6 * 3600)
            let descriptor = FetchDescriptor<PrayerModel>(
                predicate: #Predicate<PrayerModel> { $0.startTime >= batchStart && $0.startTime < fetchEnd && $0.isCompleted }
            )
            guard let rows = try? context.fetch(descriptor) else { return }
            var byDay: [Date: [PrayerModel]] = [:]
            for row in rows {
                let d = row.dayStart
                if d >= batchStart && d < batchEnd { byDay[d, default: []].append(row) }
            }
            while day >= batchStart {
                let dayRows = byDay[day] ?? []
                if streakAlive {
                    if five.isSubset(of: Set(dayRows.filter { self.gradingCriteria(for: $0) }.map(\.name))) { streakRun += 1 } else { streakAlive = false }
                }
                if inTimeAlive {
                    if five.isSubset(of: Set(dayRows.filter(inWindow).map(\.name))) { inTimeRun += 1 } else { inTimeAlive = false }
                }
                if !streakAlive && !inTimeAlive { break batches }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break batches }
                day = previous
            }
            batchEnd = batchStart
        }

        let before = (streak: prayerStreak, inTime: onTimeStreak, maxStreak: maxPrayerStreak, maxInTime: maxOnTimeStreak)

        // The day streak (by the chosen streak mode). Only changed values are written: each write
        // re-renders the views bound to these keys.
        let todayCounted = PrayerDay.start(for: lastStreakDate) == todayStart
        let newStreak = todayCounted ? streakRun + 1 : streakRun
        if prayerStreak != newStreak { prayerStreak = newStreak }
        if !todayCounted && PrayerDay.start(for: lastStreakDate) != yesterdayStart { lastStreakDate = yesterdayStart }
        if prayerStreak > maxPrayerStreak {
            maxPrayerStreak = prayerStreak
            dateOfMaxPrayerStreak = todayCounted ? now : yesterdayStart   // the day that ended the run
        }

        // In-time days (all five within their windows).
        let inTimeTodayCounted = PrayerDay.start(for: Date(timeIntervalSince1970: lastOnTimeStreakDate_TI)) == todayStart
        let newInTime = inTimeTodayCounted ? inTimeRun + 1 : inTimeRun
        if onTimeStreak != newInTime { onTimeStreak = newInTime }
        if !inTimeTodayCounted && lastOnTimeStreakDate_TI != yesterdayStart.timeIntervalSince1970 {
            lastOnTimeStreakDate_TI = yesterdayStart.timeIntervalSince1970
        }
        if onTimeStreak > maxOnTimeStreak { maxOnTimeStreak = onTimeStreak }

        logFirstRecount(before: before)
    }

    /// Once per install: what the first history recount changed (streak, in-time days, their
    /// maxes), so the owner can be told exactly — the log in DEBUG, one line in the app group
    /// ("streakRecount.firstRun") on any build.
    private func logFirstRecount(before: (streak: Int, inTime: Int, maxStreak: Int, maxInTime: Int)) {
        let key = "streakRecount.firstRun"
        guard let group = UserDefaults(suiteName: SharedStore.appGroup), group.string(forKey: key) == nil else { return }
        let line = "\(Date().formatted(.iso8601)) streak \(before.streak)→\(prayerStreak), in-time \(before.inTime)→\(onTimeStreak), max streak \(before.maxStreak)→\(maxPrayerStreak), max in-time \(before.maxInTime)→\(maxOnTimeStreak)"
        group.set(line, forKey: key)
        print("📊 first streak recount: \(line)")
    }

    /// For a prayer marked somewhere else, possibly on an earlier prayer day (the watch): recount
    /// the streaks from the rows, then today's part.
    func recomputeStreaks() {
        try? context.save()
        calculatePrayerStreak()
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

    /// A day's rows, one per prayer name (a completed row wins, else the first), in time order.
    /// The loaders used `fetchLimit = 5`: with a sixth row that day (an edited / imported / duplicate
    /// one) a prayer dropped out of the list — the same bug as fetchPrayerTimes' (2026-09-27).
    static func onePerPrayer(_ rows: [PrayerModel]) -> [PrayerModel] {
        var picked: [String: PrayerModel] = [:]
        for row in rows {
            if let current = picked[row.name], current.isCompleted || !row.isCompleted { continue }
            picked[row.name] = row
        }
        return picked.values.sorted { $0.startTime < $1.startTime }
    }

    func loadPrayerObjects(for date: Date? = nil) -> [PrayerModel] {
        let targetDate = date ?? PrayerDay.date() // the provided calendar day, else the current prayer day
        let dayStart = Calendar.current.startOfDay(for: targetDate)
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forDayStarting: dayStart),   // 2.8.0: the prayer day of that date
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        do {
            let prayers = Self.onePerPrayer(try context.fetch(fetchDescriptor))
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
        var fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forDayStarting: dayStart),   // 2.8.0
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        do {
            var prayers = Self.onePerPrayer(try context.fetch(fetchDescriptor))
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
        // The first-run tour shows its pretend day instead of today (Tour.swift); nothing of it is saved.
        if let practice = TourRuntime.practiceMirror {
            todaysPrayers = practice
            return
        }
        let fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forDayStarting: PrayerDay.start()),   // 2.8.0: by prayer day
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        do {
            todaysPrayers = Self.onePerPrayer(try context.fetch(fetchDescriptor))
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
    
    private func scheduleDailyRefresh() {
        // Runs while the app stays open across the rollover (Fajr, or the hour in Settings); a closed app refreshes on
        // its next open. Re-planned after every fetch (audit B2): Fajr moves with the place and the method.
        refreshTimer?.invalidate()
        let midnight = PrayerDay.rolloverInstant(after: PrayerDay.date())
        let timeInterval = max(midnight.timeIntervalSince(Date()), 1)
        print("next refresh scheduled for \(midnight) in \(timerStyle(timeInterval))")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timeAtLastRefresh = Date()
            self.fetchPrayerTimes(cameFrom: "scheduleDailyRefresh")   // plans the next turn's timer itself
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

extension Notification.Name {
    /// Posted once when today's five prayers continue the streak; the top bar celebrates it.
    /// (object: an Int only from the DEBUG test triggers — a fake streak to show.)
    static let prayerStreakContinued = Notification.Name("prayerStreakContinued")
    /// Posted once when all five were Early / On time today; the top bar celebrates it.
    static let onTimeStreakContinued = Notification.Name("onTimeStreakContinued")
    /// Posted once when all five were Early today; the list celebrates it.
    static let perfectDay = Notification.Name("perfectDay")
}

extension PrayerViewModel {
    /// Launch clean-up for the duplicates `fetchPrayerTimes` used to insert (see there): per
    /// calendar day and prayer name, extra UNMARKED rows are deleted — kept: every completed row
    /// (nothing marked is ever removed) and, when none is completed, the first unmarked one.
    /// Cheap when there's nothing to do; backs the store up first when there is.
    static func removeDuplicatePrayerRows(in container: ModelContainer) {
        let context = ModelContext(container)
        guard let rows = try? context.fetch(FetchDescriptor<PrayerModel>(sortBy: [SortDescriptor(\.startTime)])) else { return }
        var groups: [String: [PrayerModel]] = [:]
        for row in rows {
            groups["\(row.dayKey)|\(row.name)", default: []].append(row)   // 2.8.0: by prayer day, not calendar day
        }
        var doomed: [PrayerModel] = []
        for (_, list) in groups where list.count > 1 {
            let unmarked = list.filter { !$0.isCompleted }
            if list.contains(where: \.isCompleted) { doomed += unmarked } else { doomed += unmarked.dropFirst() }
        }
        guard !doomed.isEmpty else { return }
        PrayerScoring.backUpStore(label: "before-dedupe")
        for row in doomed { context.delete(row) }
        do {
            try context.save()
            print("✅ removed \(doomed.count) duplicate unmarked prayer rows")
        } catch {
            print("❌ duplicate prayer clean-up failed: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
extension PrayerViewModel {
    /// `-demoStreakBackfill` (simulator only; writes rows): the two prayer days before today get all
    /// five marked on time, the streak is set as if the last counted day was three days ago (what a
    /// late mark left behind), then the recount runs twice. Logs STREAKBACKFILL before / after.
    func demoStreakBackfill() {
        let calendar = Calendar.current
        let todayStart = PrayerDay.start(for: Date())
        for back in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: todayStart) else { continue }
            let (start, end) = PrayerDay.rowRange(forDayStarting: day)
            let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.startTime >= start && $0.startTime <= end }))) ?? []
            for (i, name) in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].enumerated() {
                let row = rows.first { $0.name == name } ?? {
                    let s = day.addingTimeInterval(Double(5 + i * 3) * 3600)
                    let r = PrayerModel(name: name, startTime: s, endTime: s.addingTimeInterval(7200))
                    context.insert(r); return r
                }()
                row.isCompleted = true
                row.timeAtComplete = row.startTime.addingTimeInterval(600)
                row.numberScore = 1
            }
        }
        try? context.save()
        prayerStreak = 1
        lastStreakDate = calendar.date(byAdding: .day, value: -3, to: todayStart) ?? todayStart
        onTimeStreak = 1
        lastOnTimeStreakDate_TI = lastStreakDate.timeIntervalSince1970
        print("STREAKBACKFILL before: streak=\(prayerStreak) inTime=\(onTimeStreak)")
        checkToResetStreak()
        print("STREAKBACKFILL after 1: streak=\(prayerStreak) inTime=\(onTimeStreak) last=\(lastStreakDate)")
        checkToResetStreak()
        print("STREAKBACKFILL after 2: streak=\(prayerStreak) inTime=\(onTimeStreak)")
    }

    /// `-demoPrayerDayKeyTest` (simulator only; writes then removes rows): schema 2.8.0's reason. Today's Isha is
    /// given a start after midnight (tomorrow 00:30) and yesterday's Isha a start this morning (00:30): the day's
    /// rows must still be exactly today's — the late Isha found (not re-inserted by a refresh), yesterday's not
    /// adopted. Logs PRAYERDAYKEY ✅ / ❌ and cleans up.
    func demoPrayerDayKeyTest() {
        let calendar = Calendar.current
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        if (store?.double(forKey: "lastLatitude") ?? 0) == 0 {   // times need a place: New York
            store?.set(40.7128, forKey: "lastLatitude"); store?.set(-74.0060, forKey: "lastLongitude")
        }
        let todayKey = PrayerDay.key()
        let todayStart = PrayerDay.start()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let yesterdayKey = PrayerNotificationID.dayKey(yesterday)
        let marker = "PRAYERDAYKEYTEST"
        // Clear today's existing Isha rows so the late one is the day's only Isha.
        let existing = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: todayStart)))) ?? []
        for r in existing where r.name == "Isha" { context.delete(r) }
        let late = PrayerModel(name: "Isha", startTime: tomorrow.addingTimeInterval(30 * 60), endTime: tomorrow.addingTimeInterval(90 * 60))
        late.prayerDayKey = todayKey; late.isCompleted = true; late.numberScore = 0.9; late.timeAtComplete = late.startTime.addingTimeInterval(300); late.mosqueName = marker
        let stale = PrayerModel(name: "Isha", startTime: todayStart.addingTimeInterval(30 * 60), endTime: todayStart.addingTimeInterval(90 * 60))
        stale.prayerDayKey = yesterdayKey; stale.isCompleted = true; stale.numberScore = 0.4; stale.mosqueName = marker
        context.insert(late); context.insert(stale)
        try? context.save()
        var ok = true
        func check(_ cond: Bool, _ what: String) { print("PRAYERDAYKEY \(cond ? "✅" : "❌") \(what)"); ok = ok && cond }
        let rows1 = loadPrayerObjects(for: PrayerDay.date())
        check(rows1.contains { $0 === late }, "today's rows include the Isha that starts after midnight")
        check(!rows1.contains { $0 === stale }, "yesterday's late Isha (this morning) is not adopted by today")
        fetchPrayerTimes(cameFrom: "PRAYERDAYKEYTEST")
        let ishas = ((try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: todayStart)))) ?? []).filter { $0.name == "Isha" }
        check(ishas.count == 1, "a refresh leaves one Isha for today (found \(ishas.count))")
        check(ishas.first === late && late.isCompleted, "and it's the marked late one, untouched")
        let rows2 = Self.onePerPrayer(loadPrayerObjects(for: PrayerDay.date()))
        check(rows2.count == 5, "the day still has five prayers (found \(rows2.count))")
        print("PRAYERDAYKEY \(ok ? "✅ ALL PASSED" : "❌ FAILED")")
        // Clean up the fakes; a normal refresh restores today's Isha from the times.
        for r in (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.mosqueName == marker }))) ?? [] { context.delete(r) }
        try? context.save()
        fetchPrayerTimes(cameFrom: "PRAYERDAYKEYTEST cleanup")
    }
}
#endif
