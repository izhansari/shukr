import SwiftUI
import SwiftData

// The kinds of data Your Data lists and exports, and the settings it can write out. Your Data is a plain "export your
// data" page (owner, 2026-10-14: "whatever someone would expect to see in a page like this in any other app"): choose
// what to include, Export, Restore. The pages that opened each kind (stats, then "what's kept", a photo grid) are gone.

enum DataKind: String, CaseIterable, Hashable {
    case prayers, zikr, azkar, photos, donations, names, excused, settings

    var title: String {
        switch self {
        case .prayers: "Prayers"
        case .zikr: "Zikr sessions"
        case .azkar: "Azkar and daily goals"
        case .photos: "Prayer photos"
        case .names: "99 Names you've learned"
        case .donations: "Donations"
        case .excused: "Excused Mode"
        case .settings: "Your settings"
        }
    }

    var symbol: String {
        switch self {
        case .prayers: "checkmark.circle"
        case .zikr: "circle.hexagonpath"
        case .azkar: "books.vertical"
        case .photos: "camera"
        case .names: "character.book.closed"
        case .donations: "gift"
        case .excused: "pause.circle"
        case .settings: "gearshape"
        }
    }

    /// The copy's spreadsheets for this kind.
    var sheets: [String] {
        switch self {
        case .prayers: ["prayers.csv"]
        case .zikr: ["zikr-sessions.csv"]
        case .azkar: ["azkar.csv", "daily-goals.csv"]
        case .names: ["names-learned.csv"]
        case .donations: ["donations.csv"]
        case .excused: ["excused-mode.csv"]
        case .settings: ["settings.csv", "your-masajid.csv"]
        case .photos: []
        }
    }
}

/// What's personal among the settings, as a spreadsheet (Setting, Value): where you are, how your times are worked
/// out, the Fajr alarm, your masajid. The rest are switches that live in Settings itself.
@MainActor enum DataSettings {
    static func csv() -> String {
        func cell(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        return (["Setting,Value"] + rows().map { "\(cell($0.0)),\(cell($0.1))" }).joined(separator: "\n")
    }

    static func rows() -> [(String, String)] {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        let methods = [1: "University of Islamic Sciences, Karachi", 2: "Islamic Society of North America", 3: "Muslim World League",
                       4: "Umm Al-Qura University, Makkah", 5: "Egyptian General Authority of Survey",
                       7: "Institute of Geophysics, University of Tehran", 8: "Gulf Region", 9: "Kuwait", 10: "Qatar",
                       11: "Majlis Ugama Islam Singapura, Singapore", 12: "Union Organization islamic de France",
                       13: "Diyanet İşleri Başkanlığı, Turkey", 14: "Spiritual Administration of Muslims of Russia"]
        let saved = group?.object(forKey: "calculationMethod") == nil ? 2 : (group?.integer(forKey: "calculationMethod") ?? 2)
        let method = saved == 0 ? "Automatic · " + (methods[AutoMethod.effectiveMethod()] ?? "") : (methods[saved] ?? "Method \(saved)")
        let city = group?.string(forKey: "lastCityName").flatMap { $0 == "Wonderland" || $0.isEmpty ? nil : $0 } ?? "Not set"
        var alarm = "Off"
        if group?.bool(forKey: "alarmEnabled") == true {
            let mins = group?.integer(forKey: "alarmOffsetMinutes") ?? 0
            let before = group?.object(forKey: "alarmIsBefore") == nil || group?.bool(forKey: "alarmIsBefore") == true
            let fajr = group?.object(forKey: "alarmIsFajr") == nil || group?.bool(forKey: "alarmIsFajr") == true
            alarm = mins == 0 ? (fajr ? "As Fajr starts" : "As Fajr ends") : "\(mins) min \(before ? "before" : "after") Fajr \(fajr ? "starts" : "ends")"
        }
        let d = UserDefaults.standard
        let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let reminders = prayers.map { p -> (String, String) in
            let k = p.lowercased()
            let on = d.object(forKey: "\(k)Notif") == nil ? NotificationDefaults.notify(p) : d.bool(forKey: "\(k)Notif")
            let nudges = d.object(forKey: "\(k)Nudges") == nil ? NotificationDefaults.nudges(p) : d.bool(forKey: "\(k)Nudges")
            return ("\(p) notifications", !on ? "Off" : nudges ? "Nudge" : "At the start")
        }
        let cards = prayers.map { ("\($0) Live Activity", LiveActivityPrefs.isOn($0) ? "On" : "Off") }
        let looks = [3: "System", 0: "Light", 1: "Dark", 2: "Sun"]
        let lat = group?.double(forKey: "lastLatitude") ?? 0, lon = group?.double(forKey: "lastLongitude") ?? 0
        return [("Location", city),
                ("Coordinates", lat == 0 && lon == 0 ? "" : String(format: "%.4f, %.4f", lat, lon)),
                ("Calculation method", method),
                ("Asr", group?.integer(forKey: "school") == 1 ? "Hanafi" : "Shafi'i"),
                ("Fajr alarm", alarm)]
            + reminders + cards
            + [("Live Activity look", LiveActivityLook.current.title),
               ("App look", looks[d.integer(forKey: "modeToggleNew")] ?? "System"),
               ("A dua on arriving at a masjid", d.bool(forKey: MasjidArrival.enabledKey) ? "On" : "Off"),
               ("Your masajid", "\(MosqueFavorites.all.count) starred · \((d.stringArray(forKey: MosqueHiding.key) ?? []).count) hidden")]
    }
}
