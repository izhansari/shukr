import SwiftUI
import QuartzCore
import Adhan
import CoreLocation
import SwiftData
import UserNotifications
import WidgetKit
import Combine

// MARK: - PrayerViewModel
class PrayerViewModel: ObservableObject{ //letsgoooo i removed the CLLocationManager stuff from here. one less location manager!
    
    // MARK: - Arguments & Init
    
    private(set) var context: ModelContext // Inject the ModelContext in the initializer
    var ENV_LocationManager: EnvLocationManager // Inject the EnvLocationManager in the initializer
    /// The app's one view model, for code that runs in shukr's process without a view (a Live Activity's Mark prayed
    /// marks through it — the widget's separate-container path lost a mark when the app later saved over it).
    static weak var current: PrayerViewModel?

    /// Today's row for `name` whose window starts at `start` (a Live Activity's window), if it's loaded.
    func todaysRow(named name: String, startingAt start: Date) -> PrayerModel? {
        // Within 3 h, not 2 min: a card's start can be off by a time change it wasn't corrected for yet (a new place, a
        // madhab change); today's rows hold one row per prayer (Frank).
        todaysPrayers.first { $0.name == name && abs($0.startTime.timeIntervalSince(start)) < 3 * 3600 }
    }

    /// A fresh fix for a prayer marked from outside (a widget's mark, run in the app — PrayerLiveActivities).
    func setLocation(_ location: CLLocation, on row: PrayerModel) {
        row.setPrayerLocation(with: location)
        try? context.save()
    }

    init(context: ModelContext, envLocationManager: EnvLocationManager) {
        print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>PrayerViewModel initialized")
        self.context = context
        self.ENV_LocationManager = envLocationManager
        self.scheduleDailyRefresh() //this will only run once on initialization. but will not run again if app is kept open in appswitcher.
        self.subscribeToChanges()
        PrayerViewModel.current = self
        #if DEBUG
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoStreakExcused") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.demoStreakExcused() }
        }
        #endif
        // `-demoGoalFlip`: the goal to another level and back, 6 s and 10 s after launch, so a flip's cost lands in
        // journey-perf.log on his phone (run with -demoLand journey to include Journey's rebuild). Leaves it as it was.
        if ProcessInfo.processInfo.arguments.contains("-demoGoalFlip") {
            let original = PrayerGoal.current
            let other: PrayerGoal = original == .perfect ? .prayed : .perfect
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { MainActor.assumeIsolated { PrayerGoal.set(other) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { MainActor.assumeIsolated { PrayerGoal.set(original) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
                MainActor.assumeIsolated {
                    JourneyPerf.began("best recount, every day")
                    self.recountBestStreak(from: .distantPast, save: false)
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoStreakBackfill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.demoStreakBackfill() }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoPrayerDayKeyTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.demoPrayerDayKeyTest() }
        }
        #endif
    }
    
    private func subscribeToChanges(){
        // Subscribe to userLocation changes
        // The goal or the fresh start changed: recount, silently.
        NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rulesChanged() }
            .store(in: &cancellables)
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

    @AppStorage("lastLatitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLatitude: Double = 0
    @AppStorage("lastLongitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLongitude: Double = 0
    @AppStorage("lastCityName", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastCityName: String = "Wonderland"
    
    /// App Storage doesnt use Date types. So we use timeIntervalSince1970 to convert to Date. Then use a computed var to get and set it. (which deals with the unwrapping for us)
    @AppStorage("prayerStreak") var prayerStreak: Int = 0 //prayerstreak_flag
    @AppStorage("maxPrayerStreak") var maxPrayerStreak: Int = 0
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
        
    // MARK: - Published & State
    @Published var cityName: String?
    @Published var useTestPrayers: Bool = false  // Add this property
    @Published var prayerTimesForDateDict: [String: (start: Date, end: Date, window: TimeInterval)] = [:]
    @Published var todaysPrayers: [PrayerModel] = []
    @Published var todaysScore: Double = 0.0


    private var refreshTimer: Timer?   // a plain property (audit B2): `@State` does nothing outside a View, so the timer could never be re-planned

    /// While excusedChanged re-scores 60 days: one save at the end, not one a day (perf-recheck, 2026-10-14: ~60 saves on
    /// the main thread in one go when Excused Mode went on or off).
    var batchingScores = false

    // MARK: - Computed Vars
    var relevantPrayer: PrayerModel? {
        let now = Date()

        if let currentPrayer = todaysPrayers.first(where: {  // 1. Check for the current prayer if not completed
            !$0.isCompleted && $0.startTime <= now && now <= $0.endTime
        }) { return currentPrayer }

        if let nextPrayer = todaysPrayers.first(where: {     // 2. Check for the next upcoming prayer
            !$0.isCompleted && now < $0.startTime
        }) { return nextPrayer }

        let excused = Excused.ranges   // a prayer she was excused from is never "missed" (Excused.swift)
        // 3. The LATEST missed prayer of the day, so after Isha ends the circle stays on Isha (owner, 2026-10-19: "stay on
        // isha is fine. i like that"); the line says when there are more (MainCircleView.missedToday).
        if let missedPrayer = todaysPrayers.filter({
            !$0.isCompleted && $0.endTime < now && !Excused.covers(start: $0.startTime, end: $0.endTime, in: excused)
        }).max(by: { $0.startTime < $1.startTime }) { return missedPrayer }

        return nil                                          // No relevant prayer found
    }
    

    // MARK: - Location Stuff
    let geocoder = CLGeocoder()
    var lastGeocodeRequestTime: Date?
    var lastAppLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()


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

    /// A fix worth recording as where a prayer was prayed (audit B10): under 10 min old and within 500 m. `nil` = no spot.
    static func usableFix(_ location: CLLocation?) -> CLLocation? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500,
              Date().timeIntervalSince(location.timestamp) < 600 else { return nil }
        return location
    }

    // MARK: - Prayer Scheduling
        
    // the current one im working on.
    func fetchPrayerTimes(cameFrom: String) {
        ControlCenter.shared.reloadAllControls()   // times may have moved
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
        calculateDayScore(for: prayer.dayStart)
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
        calculateDayScore(for: prayer.dayStart)
        calculatePrayerStreak()
        pushCompletionsToWidget()
        objectWillChange.send()
        JourneyChange.post()
    }

    /// A mark from Journey's prayer sheet, on any day (decision journey-past-marks A): at `date` — after the window it's
    /// Qaza. The prayer on now, marked now, takes the list's own path (the spot, the masjid, the moment); any other is
    /// scored at the picked time with no spot (where it was prayed days ago isn't known — the sheet can add one). The picked
    /// time is the recorded one, so nothing reads as edited. False = not marked (excused).
    @MainActor @discardableResult func markFromJourney(_ prayer: PrayerModel, at date: Date) -> Bool {
        guard !prayer.isCompleted, prayer.startTime <= Date() else { return false }
        if Excused.covers(start: prayer.startTime, end: prayer.endTime) { return false }
        let now = Date()
        if prayer.endTime > now, abs(date.timeIntervalSince(now)) < 60 {
            togglePrayerCompletion(for: prayer)
            DayHistory.invalidate()
            return prayer.isCompleted
        }
        prayer.isCompleted = true
        prayer.mosqueName = ""   // checked: no spot, so no masjid search (a spot added later decides)
        prayer.setPrayerScore(atDate: date)
        prayer.cancelUpcomingNudges()
        PrayerCompletionHaptics.play()
        calculateDayScore(for: prayer.dayStart)
        calculatePrayerStreak()
        DayHistory.invalidate()
        pushCompletionsToWidget()
        PhotoDevelop.check(todaysPrayers)
        objectWillChange.send()
        JourneyChange.post()
        return true
    }

    /// An unmark from Journey's prayer sheet: the list's own path (its photo goes too).
    @MainActor func unmarkFromJourney(_ prayer: PrayerModel) {
        guard prayer.isCompleted else { return }
        togglePrayerCompletion(for: prayer)
        DayHistory.invalidate()
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
        // Excused from prayer (Excused.swift): a prayer she's excused from can't be marked (unmarking one marked before
        // still works).
        if !prayer.isCompleted, Excused.covers(start: prayer.startTime, end: prayer.endTime) {
            triggerSomeVibration(type: .light)
            // Ask whether she's back (owner: never a silent no); the Salah page shows the question.
            NotificationCenter.default.post(name: Excused.askResume, object: prayer)
            return
        }
        // Only a mark needs the prayer to have started; an unmark always runs (a clock set back by hand left a marked
        // prayer "not started" and its dot dead — mark audit #8).
        if prayer.isCompleted || prayer.startTime <= Date() {
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
                PrayerPhotos.discard(for: prayer)
                // A day can hold two completed rows of one prayer (a store salvage, a legacy import): the others go
                // too, or the next reload picks one and it's still prayed (mark audit #9; the widget's and the watch's
                // unmarks already reset every one).
                for twin in completedTwins(of: prayer) { twin.resetPrayer(); PrayerPhotos.discard(for: twin) }
                // The mark took away its halfway / 30-minutes-left nudges: the plan puts them back (a diff — mark audit #6).
                Task { @MainActor in NotificationScheduler.topUp(reason: "unmark") }
            }
            calculatePrayerStreak()
            calculateDayScore(for: prayer.dayStart)
            pushCompletionsToWidget()
            PhotoDevelop.check(todaysPrayers)   // the last of the five develops the day's photos
            JourneyChange.post()   // Journey's numbers (in the pager it stays built)
            // Prayed at a masjid? (Jumu'ah gets full marks.)
            if prayer.isCompleted {
                Task { @MainActor in
                    let days = await MasjidDetector.check([prayer], in: context)
                    for day in days { calculateDayScore(for: day) }
                    if !days.isEmpty {
                        pushCompletionsToWidget()
                        objectWillChange.send()
                        JourneyChange.post()   // rescored
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
    @MainActor func reconcileAfterWidgetWrites() {
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
        // Yesterday too: two outside marks on different days before an open leave only the last one's day in
        // `markedDayKey` (yesterday's Isha from its banner after Fajr, then Fajr from the widget — mark audit #11). Only a
        // day with rows, so a new install doesn't get a zero day.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: PrayerDay.date()),
           !loadPrayerObjects(for: yesterday).isEmpty {
            calculateDayScore(for: yesterday)
        }
        DayHistory.invalidate()   // an outside mark of an earlier day: the day page's history and the circle's line (mark audit #5)
        JourneyChange.post()   // a widget / notification / watch mark: Journey's numbers too
        print("✅ reconciled widget completions: \(todaysPrayers.filter { $0.isCompleted }.map { $0.name })")
    }
    
    /// Flush and refresh the widget so an in-app completion shows there right away.
    func pushCompletionsToWidget() {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
        ControlCenter.shared.reloadAllControls()   // the Prayer control's line
        WatchSync.shared.send()                    // the watch's ✓s
        // Live Activities: a mark ends its card at once, an unmark brings it back while its window is open
        // (owner: "we should show the live activity so long as unmarked") — re-planned now, while shukr is in front.
        Task { @MainActor in PrayerLiveActivities.plan(reason: "a prayer marked / unmarked / edited in shukr") }
    }
    

    /// The other completed rows of `prayer`'s name on its prayer day (duplicates; normally none).
    private func completedTwins(of prayer: PrayerModel) -> [PrayerModel] {
        let name = prayer.name, id = prayer.persistentModelID
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forDayStarting: prayer.dayStart)))) ?? []
        return rows.filter { $0.name == name && $0.isCompleted && $0.persistentModelID != id }
    }

    
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
            PhotoDevelop.check(todaysPrayers)   // all five marked develops the day's photos
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
            self.fetchPrayerTimes(cameFrom: "scheduleDailyRefresh")   // plans the next turn's timer itself
        }
    }

}



extension PrayerViewModel {
    
    /// A new row for that prayer and day, or nil when its times can't be worked out yet (no location, no times):
    /// the caller skips it and the next fetch fills it in (App Store crash safety — was a fatalError).
    func createPrayerModel(name prayerName: String, at date: Date) -> PrayerModel? {
        guard let times = getPrayerTime(for: prayerName, on: date) else {
            print("⚠️ createPrayerModel: no times for \(prayerName) on \(date) — skipped")
            return nil
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
        // Once a day: it reads every prayer row ever kept (~48 ms in the first frame on his 13 Pro Max and growing with
        // history — perf-recheck, 2026-10-14), and the 5-row lookup that made the duplicates is long gone.
        let today = PrayerDay.key()
        guard UserDefaults.standard.string(forKey: "prayerRows.dedupedDay") != today else { return }
        UserDefaults.standard.set(today, forKey: "prayerRows.dedupedDay")
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
