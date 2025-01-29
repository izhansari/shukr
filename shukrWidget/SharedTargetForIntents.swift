
// MARK: - Intents

import AppIntents
import WidgetKit

struct MarkCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Prayers"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetCompletion")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetCompletion: \(store.bool(forKey: "widgetCompletion"))")
        }
        return .result()
    }
}

struct OpenTasbeehIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbeeh"
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
    
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetTasbeeh")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTasbeeh: \(store.bool(forKey: "widgetTasbeeh"))")
        }
        return .result()
    }
}

struct OpenCompassIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Compass"
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetCompass")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetCompass: \(store.bool(forKey: "widgetCompass"))")
        }
        return .result()
    }
}

struct showListToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(!store.bool(forKey: "toggleShowAllTImes"), forKey: "toggleShowAllTImes")
//            WidgetCenter.shared.reloadAllTimelines()
            print("toggleShowAllTImes: \(store.bool(forKey: "toggleShowAllTImes"))")
        }
        return .result()
    }
}

struct textToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(!store.bool(forKey: "widgetTextToggle"), forKey: "widgetTextToggle")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTextToggle: \(store.bool(forKey: "widgetTextToggle"))")
        }
        return .result()
    }
}


// MARK: - PrayerUtils


import AppIntents
import Adhan

/// Utility class for shared functionality
struct PrayerUtils {

    /// Fetches user location from UserDefaults
    static func getUserCoordinates() throws -> Coordinates {
//        var latitude = UserDefaults.standard.double(forKey: "lastLatitude")
//        var longitude = UserDefaults.standard.double(forKey: "lastLongitude")

        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let latitude = store.double(forKey: "lastLatitude")
        let longitude = store.double(forKey: "lastLongitude")
        
        guard latitude != 0, longitude != 0 else {
            throw PrayerError(message: "Location not available. Please open the app first.")
        }
        
        return Coordinates(latitude: latitude, longitude: longitude)
    }
    
    /// Fetches calculation parameters based on UserDefaults
    static func getCalculationParameters() -> CalculationParameters {
        
//        var calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
//        var madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi

        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let calcMethodInt = store.integer(forKey: "calculationMethod")
        let madhab = store.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
        
        let calculationMethod: CalculationMethod = {
            switch calcMethodInt {
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
            case 12, 14: return .other
            case 13: return .turkey
            default: return .northAmerica
            }
        }()
        
        var params = calculationMethod.params
        params.madhab = madhab
        return params
    }
    
    static func createWindowsFromTimes(_ times: PrayerTimes) -> [String : (Date, Date, TimeInterval)] {
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60)) // Start of next day
        let midnightMinusOneSec = midnight.addingTimeInterval(-1) // Subtract 1 second
        
        func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
            return (starTime, endTime, endTime.timeIntervalSince(starTime))
        }
        
        return [
            "Fajr": timesAndWindow(times.fajr, times.sunrise),
            "Sunrise": timesAndWindow(times.sunrise, times.dhuhr),
            "Dhuhr": timesAndWindow(times.dhuhr, times.asr),
            "Asr": timesAndWindow(times.asr, times.maghrib),
            "Maghrib": timesAndWindow(times.maghrib, times.isha),
            "Isha": timesAndWindow(times.isha, /*todayAt(23, 59)*/ midnightMinusOneSec)
        ]
    }
    
    static func createDummyWindows() -> [String : (Date, Date, TimeInterval)] {
        func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
            return (starTime, endTime, endTime.timeIntervalSince(starTime))
        }
        
        return [
            "x_Fajr": timesAndWindow(Date(), Date()),
            "x_Sunrise": timesAndWindow(Date(), Date()),
            "x_Dhuhr": timesAndWindow(Date(), Date()),
            "x_Asr": timesAndWindow(Date(), Date()),
            "x_Maghrib": timesAndWindow(Date(), Date()),
            "x_Isha": timesAndWindow(Date(), Date()),
        ]
    }
    
    /// Fetches prayer times for a specific date
    static func getPrayerTimes(for date: Date, coordinates: Coordinates, params: CalculationParameters) throws -> PrayerTimes {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        
        guard let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else {
            throw PrayerError(message: "Unable to calculate prayer times for \(date).")
        }
        
        return prayerTimes
    }
    
    /// Generic prayer time retrieval
    static func getPrayerTime(for prayer: enumPrayer, in times: PrayerTimes) -> Date {
        switch prayer {
        case .fajr: return times.fajr
        case .sunrise: return times.sunrise
        case .dhuhr: return times.dhuhr
        case .asr: return times.asr
        case .maghrib: return times.maghrib
        case .isha: return times.isha
        }
    }
    

    static func calculateAlarmDescription() throws -> (description: String, time: Date) {
        print("hellow")
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let alarmEnabled = store.bool(forKey: "alarmEnabled")
        let alarmOffsetMinutes = store.integer(forKey: "alarmOffsetMinutes")
        let alarmIsBefore = store.bool(forKey: "alarmIsBefore")
        let alarmIsFajr = store.bool(forKey: "alarmIsFajr")
        print("Alarm Enabled: \(alarmEnabled)")
        print("Alarm Offset Minutes: \(alarmOffsetMinutes)")
        print("Alarm Is Before: \(alarmIsBefore)")
        print("Alarm Is Fajr: \(alarmIsFajr)")


        guard alarmEnabled else {
            print("hellow3")
            throw AlarmDisabledError()
        }
        print("hellow4")
        let coordinates = try PrayerUtils.getUserCoordinates()
        print("1")
        let params = PrayerUtils.getCalculationParameters()
        print("2")
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        print("3")
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        print("4")
        let prayer: enumPrayer = alarmIsFajr ? .fajr : .sunrise
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        print("5")
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        print("6")

        let offset = TimeInterval(alarmOffsetMinutes * 60)
        let resultTime = nextPrayerTime.addingTimeInterval(alarmIsBefore ? -offset : offset)
        
        let offsetMinutesText = "\(alarmOffsetMinutes) minute\(alarmOffsetMinutes == 1 ? "" : "s")"
        let beforeAfterText = alarmIsBefore ? "before" : "after"
        let fajrSunriseText = alarmIsFajr ? "Fajr" : "Sunrise"
        let resultTimeText = "(\(shortTimePM(resultTime)))"
        let firstPartText = alarmOffsetMinutes != 0 ? "\(offsetMinutesText) \(beforeAfterText)" : "Alarm at"
        let description = "\(firstPartText) \(fajrSunriseText) \(resultTimeText)"

        return (description, resultTime)
    }


    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Daily Fajr Alarm is disabled. Please enable it in the Shukr app settings."
        }
    }

}

/// Custom error for prayer intents
struct PrayerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// AppEnum for Prayer Selection
enum enumPrayer: String, AppEnum {
    case fajr = "Fajr"
    case sunrise = "Sunrise"
    case dhuhr = "Dhuhr"
    case asr = "Asr"
    case maghrib = "Maghrib"
    case isha = "Isha"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static var caseDisplayRepresentations: [enumPrayer: DisplayRepresentation] = [
        .fajr: "Fajr",
        .sunrise: "Sunrise",
        .dhuhr: "Dhuhr",
        .asr: "Asr",
        .maghrib: "Maghrib",
        .isha: "Isha"
    ]
}

// DIsplays as 2:01 AM
func shortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm"
    return formatter.string(from: date)
}

func shortTimePM(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

// experiment but returns string so doesnt update dynamically
func timeLeftStringFromNow(to targetDate: Date) -> String {
    let timeInterval = targetDate.timeIntervalSince(Date())
    let totalSeconds = Int(max(timeInterval, 0)) // Ensure non-negative
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 { components.append("\(hours)h") }
    
    if minutes > 0 { components.append("\(minutes)m") }
    
    if hours < 1 { components.append("\(seconds)s") } // Only show seconds if less than a minute

    if components.isEmpty { return "0s left" } // If no time left, return "0s left"

    return components.joined(separator: " ") + " left"
}

func prayerIcon(for prayerName: String) -> String {
    switch prayerName.lowercased() {
    case "fajr":
        return "sunrise.fill"
    case "dhuhr":
        return "sun.max.fill"
    case "asr":
        return "sun.haze.fill"
    case "maghrib":
        return "sunset.fill"
    default:
        return "moon.stars.fill"
    }
}









// MARK: - From TasbeehView

/// AppEnum for Prayer Selection
enum enumFajrSunrisePrayer: String, AppEnum {
    case fajr = "Fajr"
    case sunrise = "Sunrise"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static var caseDisplayRepresentations: [enumFajrSunrisePrayer: DisplayRepresentation] = [
        .fajr: "Fajr",
        .sunrise: "Sunrise",
    ]
}

/// AppEnum for Reference Point
enum ReferencePoint: String, AppEnum {
    case after = "after"
    case before = "before"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reference Point"
    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
        .after: "after",
        .before: "before"
    ]
}

/// Intent: Get Time of Chosen Prayer
struct GetSomePrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time of Chosen Prayer"
    static var description: LocalizedStringResource = "Returns the time for the selected prayer."
    
    @Parameter(title: "Prayer", description: "Select which prayer time you want.")
    var prayer: enumPrayer
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get start time for \(\.$prayer)")
    }
    
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        return .result(value: nextPrayerTime, dialog: IntentDialog(stringLiteral: "\(prayer) will be at \(shortTimePM(nextPrayerTime))"))
    }
}

/// Intent: Get Next Fajr Time
struct GetNextFajrIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Fajr Time"
    static var description: LocalizedStringResource = "Returns the next Fajr prayer time."
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let nextFajr = Date() > todayTimes.fajr ? tomorrowTimes.fajr : todayTimes.fajr
        return .result(value: nextFajr, dialog: IntentDialog(stringLiteral: "Fajr will be at \(shortTimePM(nextFajr))"))
    }
}

/// Intent: Get Offset Time Relative to Any Prayer
struct GetOffsetTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Offset Time Relative to Prayer"
    static var description: LocalizedStringResource = "Returns a time offset from any prayer."
    
    @Parameter(title: "Minutes", description: "Number of minutes to offset.")
    var offsetMinutes: Int
    
    @Parameter(title: "Reference Point", description: "Offset after or before the prayer.")
    var referencePoint: ReferencePoint
    
    @Parameter(title: "Prayer", description: "Select the prayer reference.")
    var prayer: enumPrayer
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get time \(\.$offsetMinutes) minutes \(\.$referencePoint) \(\.$prayer)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        let offset = TimeInterval(offsetMinutes * 60)
        let resultTime = referencePoint == .after ? nextPrayerTime.addingTimeInterval(offset) : nextPrayerTime.addingTimeInterval(-offset)
        
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: "\(offsetMinutes) minutes \(referencePoint) \(prayer) will be at \(shortTimePM(resultTime))"))
    }
}



/// Intent: Get Offset Time Relative to Fajr or Sunrise
//struct SetFajrAlarmIntent: AppIntent {
//    static var title: LocalizedStringResource = "Autopilot Fajr Alarm Time"
//    static var description: LocalizedStringResource = "Dynamically returns a time offset from Fajr or Sunrise (rules defined in the Shukr app settings)"
//        
//    @AppStorage("alarmTimeSetFor") private var alarmTimeSetFor: String = ""
//    @AppStorage("alarmDescription") private var alarmDescription: String = ""
//
//    /// Custom Error for Disabled Alarm
//    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
//        var localizedStringResource: LocalizedStringResource {
//            "Daily Fajr Alarm is disabled. Please enable it in the Shukr app settings."
//        }
//    }
//    
//    @MainActor
//    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
//        
//        let calculatedAlarm = try PrayerUtils.calculateAlarmDescription()
//        let resultTime = calculatedAlarm.time
//        alarmTimeSetFor = shortTimePM(resultTime)
//        alarmDescription = calculatedAlarm.description
//                
//        print("\(alarmDescription)")
//        
//        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: alarmDescription))
//    }
//}

/// Intent: Get Offset Time Relative to Fajr or Sunrise
struct SetFajrAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Autopilot Fajr Alarm Time"
    static var description: LocalizedStringResource = "Dynamically returns a time offset from Fajr or Sunrise (rules defined in the Shukr app settings)"

//    private let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
    
    /// Custom Error for Disabled Alarm
    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Daily Fajr Alarm is disabled. Please enable it in the Shukr app settings."
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        print("yoyoyo")
        
        let calculatedAlarm = try PrayerUtils.calculateAlarmDescription()
        let resultTime = calculatedAlarm.time

//        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
//            store.setValue(shortTimePM(resultTime), forKey: "alarmTimeSetFor")
//            store.setValue(calculatedAlarm.description, forKey: "alarmDescription")
//            
//            print("SetFajrAlarmIntent: Alarm Description: \(store.string(forKey: "alarmDescription") ?? "")")
//        }
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        store.setValue(shortTimePM(resultTime), forKey: "alarmTimeSetFor")
        store.setValue(calculatedAlarm.description, forKey: "alarmDescription")
        print("SetFajrAlarmIntent: Alarm Description: \(store.string(forKey: "alarmDescription") ?? "")")
        
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: calculatedAlarm.description))
    }
}





struct PrayerTimeShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNextFajrIntent(),
            phrases: [
                "Get Next Fajr time from \(.applicationName)",
                "When is Fajr",
                "Get Fajr time from \(.applicationName)",
                "Fajr time from \(.applicationName)",
                "Get morning prayer time from \(.applicationName)",
                "morning prayer time from \(.applicationName)"
            ],
            shortTitle: "Fajr Time",
            systemImageName: "sunrise.fill"
        )
        
        AppShortcut(
            intent: GetSomePrayerTimeIntent(),
            phrases: [
                "Get next prayer time from \(.applicationName)",
                "When is the next prayer",
                "Next prayer time from \(.applicationName)",
                "What's the upcoming prayer time"
            ],
            shortTitle: "Some Prayer Time",
            systemImageName: "clock.fill"
        )
        
        AppShortcut(
            intent: GetOffsetTimeIntent(),
            phrases: [
                "Get offset prayer time from \(.applicationName)"
            ],
            shortTitle: "Offset Prayer Time",
            systemImageName: "clock.badge.questionmark"
        )
        
    }
}

