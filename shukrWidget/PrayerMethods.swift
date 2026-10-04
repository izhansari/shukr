//
//  PrayerMethods.swift
//  shukr (app, widget, watch, watch widgets)
//
//  The calculation method numbers (the Settings / setup picker's tags) → adhan's parameters, in one place for the
//  phone, its widget and the watch (audit B8: the watch's copy lacked the angle fixes for 12 and 14 — Fajr ≈ sunrise,
//  Isha ≈ Maghrib on the watch, so its marks carried wrong windows and scores).
//

import Adhan

enum PrayerMethods {
    /// Parameters for a method number and a school (1 = Hanafi).
    static func parameters(method: Int, school: Int) -> CalculationParameters {
        let calculationMethod: CalculationMethod = {
            switch method {
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
        // adhan-swift's .other has no angles (0 / 0): give France's and Russia's methods theirs.
        if method == 12 { params.fajrAngle = 12; params.ishaAngle = 12 }          // UOIF
        if method == 14 { params.fajrAngle = 16; params.ishaAngle = 15 }          // Spiritual Administration of Muslims of Russia
        params.madhab = school == 1 ? .hanafi : .shafi
        return params
    }
}
