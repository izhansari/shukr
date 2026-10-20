//
//  PrayerUtils.swift
//  shukr (app and widget extension)
//
//  The calculation method (AutoMethod), PrayerUtils, the prayer enum and the time helpers.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 2).
//

import Foundation
import SwiftUI
import AppIntents
import CoreLocation
import Adhan

// MARK: - Automatic calculation method

/// "Automatic (follows where you are)" — the setup's default (notes #18). Stored as method 0 in
/// `calculationMethod` (0 was never a method); everything that computes times asks
/// `effectiveMethod()`, which resolves 0 from the country you're in: the app stores the country
/// code when it geocodes a fix (`setCountry`, PrayerViewModel), and until it has one the
/// coordinates give a rough guess. adhan-swift has no such helper, so this is our own table.
/// Compiled into the app and the widget; the watch gets the resolved number (WatchSync).
enum AutoMethod {
    static let automatic = 0
    static let countryKey = "autoMethodCountry"
    private static var store: UserDefaults? { UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") }

    /// The method number to compute with: the saved one, or Automatic resolved.
    static func effectiveMethod() -> Int {
        // No key yet (e.g. the widget running before the updated app's first launch wrote one):
        // ISNA, what an unset method always meant. Only an explicit 0 is Automatic.
        guard let store, store.object(forKey: "calculationMethod") != nil else { return 2 }
        let saved = store.integer(forKey: "calculationMethod")
        return saved == automatic ? resolved() : saved
    }

    /// The saved choice is Automatic (an explicit 0).
    static var isAutomatic: Bool {
        guard let store, store.object(forKey: "calculationMethod") != nil else { return false }
        return store.integer(forKey: "calculationMethod") == automatic
    }

    /// What Automatic means here and now.
    static func resolved() -> Int {
        if let code = store?.string(forKey: countryKey), !code.isEmpty { return method(forCountry: code) }
        let lat = store?.double(forKey: "lastLatitude") ?? 0, lon = store?.double(forKey: "lastLongitude") ?? 0
        return method(latitude: lat, longitude: lon)
    }

    /// The country of the latest fix (ISO code). Written only on a change (every app-group write
    /// re-renders what's bound to it). Returns true when the resolved method changed.
    @discardableResult
    static func setCountry(_ code: String?) -> Bool {
        guard let code = code?.uppercased(), !code.isEmpty, store?.string(forKey: countryKey) != code else { return false }
        let before = resolved()
        store?.set(code, forKey: countryKey)
        return resolved() != before
    }

    /// Country → the method its masajid mostly use. Unknown → Muslim World League.
    static func method(forCountry code: String) -> Int {
        switch code.uppercased() {
        case "US", "CA": return 2                                   // ISNA
        case "SA", "YE": return 4                                   // Umm al-Qura
        case "AE", "OM", "BH": return 8                             // Gulf (Dubai)
        case "KW": return 9                                         // Kuwait
        case "QA": return 10                                        // Qatar
        case "EG", "SD", "SS", "LY", "SY", "LB", "JO", "PS", "IQ",
             "MA", "DZ", "TN", "NG", "SO", "ET", "KE", "TZ", "UG", "GH", "SN",
             "ML", "NE", "TD", "CM", "ZA", "MU", "MR", "DJ", "ER", "GM": return 5   // Egyptian
        case "PK", "IN", "BD", "AF", "LK", "NP": return 1           // Karachi
        case "MY", "SG", "ID", "BN", "TH", "PH": return 11          // Singapore (JAKIM / MUIS family)
        case "IR": return 7                                         // Tehran
        case "TR", "AZ": return 13                                  // Diyanet
        default: return 3                                           // Muslim World League
        }
    }

    /// Before any country is known: North America → ISNA, else Muslim World League.
    static func method(latitude: Double, longitude: Double) -> Int {
        guard latitude != 0 || longitude != 0 else { return 2 }
        if (15...75).contains(latitude) && (-170 ... -50).contains(longitude) { return 2 }
        return 3
    }

    /// Short names, for "Automatic · ISNA here".
    static func shortName(_ method: Int) -> String {
        switch method {
        case 1: return "Karachi"
        case 2: return "ISNA"
        case 3: return "Muslim World League"
        case 4: return "Umm al-Qura"
        case 5: return "Egyptian"
        case 7: return "Tehran"
        case 8: return "Gulf (Dubai)"
        case 9: return "Kuwait"
        case 10: return "Qatar"
        case 11: return "Singapore"
        case 12: return "UOIF (France)"
        case 13: return "Diyanet (Turkey)"
        case 14: return "Muslims of Russia"
        default: return "ISNA"
        }
    }

    /// Once, at launch: an install that never picked a method gets one written, so the stored value
    /// and every picker agree. Existing users keep ISNA (what an unset value always meant); a new
    /// install starts on Automatic.
    static func migrateDefault(existingUser: Bool) {
        guard let store, store.object(forKey: "calculationMethod") == nil else { return }
        store.set(existingUser ? 2 : automatic, forKey: "calculationMethod")
    }
}

// MARK: - PrayerUtils


import AppIntents
import Adhan

/// Utility class for shared functionality
struct PrayerUtils {
    /// The calendar every adhan date is built with (audit A4, 2026-10-01): adhan reads year / month / day as
    /// Gregorian, so `Calendar.current` on a Buddhist, Persian, Islamic or Japanese phone gave the wrong year
    /// (every prayer "ended", nothing scheduled). Current time zone, Gregorian always.
    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    /// Times that always exist: 0°,0° (the equator has every prayer every day) on today's Gregorian date. For
    /// the widget's placeholder and its last-resort fallback (audit A5) — never for anything shown as real.
    static func dummyPrayerTimes() -> PrayerTimes {
        let components = gregorian.dateComponents([.year, .month, .day], from: Date())
        if let t = PrayerTimes(coordinates: Coordinates(latitude: 0, longitude: 0), date: components,
                               calculationParameters: CalculationMethod.northAmerica.params) { return t }
        // A fixed date as the last word (adhan can't fail at the equator; this guards a future library change).
        var fixed = DateComponents(); fixed.year = 2024; fixed.month = 3; fixed.day = 21
        return PrayerTimes(coordinates: Coordinates(latitude: 0, longitude: 0), date: fixed,
                           calculationParameters: CalculationMethod.northAmerica.params)!
    }


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
    
    /// The calculation parameters for the saved method (Automatic resolved, see `AutoMethod`) and
    /// madhab.
    static func getCalculationParameters() -> CalculationParameters {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        return parameters(method: AutoMethod.effectiveMethod(), school: store.integer(forKey: "school"))
    }

    /// Parameters for a method number (the Settings / setup picker's tags) and a school (1 Hanafi): PrayerMethods.swift,
    /// shared with the watch (audit B8).
    static func parameters(method: Int, school: Int) -> CalculationParameters {
        PrayerMethods.parameters(method: method, school: school)
    }

    /// `date` is the prayer day the times are for; `nextFajr` caps Isha (see PrayerDay).
    static func createWindowsFromTimes(_ times: PrayerTimes, on date: Date = PrayerDay.date(), nextFajr: Date? = nil) -> [String : (Date, Date, TimeInterval)] {
        let ishaEnd = PrayerDay.ishaEnd(on: date, ishaStart: times.isha, nextFajr: nextFajr)
        
        func timesAndWindow(_ starTime: Date, _ endTime: Date) -> (Date, Date, TimeInterval) {
            return (starTime, endTime, endTime.timeIntervalSince(starTime))
        }
        
        return [
            "Fajr": timesAndWindow(times.fajr, times.sunrise),
            "Sunrise": timesAndWindow(times.sunrise, times.dhuhr),
            "Dhuhr": timesAndWindow(times.dhuhr, times.asr),
            "Asr": timesAndWindow(times.asr, times.maghrib),
            "Maghrib": timesAndWindow(times.maghrib, times.isha),
            "Isha": timesAndWindow(times.isha, ishaEnd)
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
        let components = PrayerUtils.gregorian.dateComponents([.year, .month, .day], from: date)
        
        guard let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else {
            throw PrayerError(message: "Unable to calculate prayer times for \(date).")
        }
        
        return prayerTimes
    }
    
    /// Generic prayer time retrieval
    static func getTime(for prayer: enumPrayer, in times: PrayerTimes) -> Date {
        switch prayer {
        case .fajr: return times.fajr
        case .sunrise: return times.sunrise
        case .dhuhr: return times.dhuhr
        case .asr: return times.asr
        case .maghrib: return times.maghrib
        case .isha: return times.isha
        }
    }
    
    static func getNextTime(for prayer: enumPrayer) throws -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()

        let todaysPrayers = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowsPrayers = try PrayerUtils.getPrayerTimes(for: tomorrow, coordinates: coordinates, params: params)

        let prayerToday = PrayerUtils.getTime(for: prayer, in: todaysPrayers)
        let prayerTomorrow = PrayerUtils.getTime(for: prayer, in: tomorrowsPrayers)

        let nextPrayer = Date() > prayerToday ? prayerTomorrow : prayerToday

        return nextPrayer
    }
    

    /// `ignoringSwitch`: the rule's time even with the Daily alarm off (the "Get Fajr Alarm Time" action, for any
    /// shortcut).
    static func calculateAlarmDescription(ignoringSwitch: Bool = false) throws -> (description: String, time: Date) {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let alarmEnabled = store.bool(forKey: "alarmEnabled")
        let alarmOffsetMinutes = store.integer(forKey: "alarmOffsetMinutes")
        // Unset = true (before / the start), the defaults Settings and the setup show; `bool(forKey:)`
        // read them as false, so an untouched rule came out "at sunrise".
        let alarmIsBefore = store.object(forKey: "alarmIsBefore") as? Bool ?? true
        let alarmIsFajr = store.object(forKey: "alarmIsFajr") as? Bool ?? true
        guard alarmEnabled || ignoringSwitch else { throw AlarmDisabledError() }

        
        let nextFajrSunrise = try PrayerUtils.getNextTime(for: alarmIsFajr ? .fajr : .sunrise)
 

        let offset = TimeInterval(alarmOffsetMinutes * 60)
        let resultTime = nextFajrSunrise.addingTimeInterval(alarmIsBefore ? -offset : offset)
        
        let description = "\(alarmRuleText(offset: alarmOffsetMinutes, isBefore: alarmIsBefore, isStart: alarmIsFajr)) (\(shortTimePM(resultTime)))"

        return (description, resultTime)
    }

    /// The Fajr alarm's rule in words (owner, 2026-09-28: "Start" / "End" of Fajr, not "Fajr" /
    /// "Sunrise"): "10 min before Start of Fajr", "At End of Fajr". Settings, the setup and the
    /// Shortcut's description all use it. (The keys stay: `alarmIsFajr` true = start, false = end.)
    static func alarmRuleText(offset: Int, isBefore: Bool, isStart: Bool) -> String {
        let anchor = isStart ? "Start of Fajr" : "End of Fajr"
        return offset == 0 ? "At \(anchor)" : "\(offset) min \(isBefore ? "before" : "after") \(anchor)"
    }

    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Your Fajr alarm is off. Turn it on in shukr’s Settings."
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

func prayerIcon(for prayerName: String) -> String {
    switch prayerName.lowercased() {
    case "fajr":
        return "sunrise.fill"
    case "sunrise":
        return "sun.horizon.fill"   // not Isha's moon (feedback 99D47ABE)
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
