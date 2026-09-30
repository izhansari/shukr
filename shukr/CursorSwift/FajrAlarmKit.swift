//
//  FajrAlarmKit.swift
//  shukr
//
//  The Fajr alarm set by shukr itself with AlarmKit (iOS 26.1+; ideas #8, owner 2026-09-29). Same
//  rule as before (`alarmOffsetMinutes` / `alarmIsBefore` / `alarmIsFajr`, 5-minute steps): one
//  real system alarm per day, as many days ahead as AlarmKit allows (the cap isn't documented —
//  `maximumLimitReached` ends the run), each on its own `.fixed` date because Fajr moves daily.
//  - While it's on (`activeKey` in the app group) the old Shortcut's intent stops itself, so its
//    "Create Alarm" step never runs: no second alarm, nothing to delete (SetFajrAlarmIntent).
//  - Kept topped up without opening the app: every `NotificationScheduler` run (launch, coming
//    back, background refresh, notification actions, settings) re-plans, and so does stopping an
//    alarm or "I'm up — open Fajr" (their intents run in the app's process).
//  - Planning is a diff against what's scheduled: past ones (fired / stopped) are cancelled,
//    missing days added, nothing else touched — so there's never a pile of old alarms.
//  - iOS 18 – 26.0 keep the Shortcut path unchanged.
//

import SwiftUI
import AlarmKit
import AppIntents

enum FajrAlarms {
    /// App group: shukr sets the Fajr alarm with AlarmKit (the Shortcut steps aside).
    static let activeKey = "alarmKitActive"
    /// App group: the last scheduled alarm's date (for "set through …").
    static let throughKey = "alarmKitThrough"
    /// How far ahead we ask for (AlarmKit's own cap may stop us sooner).
    static let daysAhead = 60
    /// App group: the ids of one-off test alarms (Settings' "Test alarm"), which `plan` leaves alone
    /// until they're past.
    static let testKey = "alarmKitTestIDs"
    private static var testIDs: Set<String> {
        get { Set(group?.stringArray(forKey: testKey) ?? []) }
        set { group?.set(Array(newValue), forKey: testKey) }
    }

    private static var group: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroup) }

    static var supported: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }
    static var isActive: Bool { supported && group?.bool(forKey: activeKey) == true }
    static var scheduledThrough: Date? {
        let t = group?.double(forKey: throughKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// The rule's alarm for each day ahead (skipping ones already past), from the saved location.
    static func dates(from now: Date = Date(), days: Int = daysAhead) -> [(alarm: Date, reference: Date)] {
        guard let g = group, g.bool(forKey: "alarmEnabled"),
              let coords = try? PrayerUtils.getUserCoordinates() else { return [] }
        let offset = g.integer(forKey: "alarmOffsetMinutes")
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let params = PrayerUtils.getCalculationParameters()
        let cal = Calendar.current
        var out: [(Date, Date)] = []
        for d in 0...days {
            guard let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)),
                  let t = try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params) else { continue }
            let ref = isFajr ? t.fajr : t.sunrise
            let fire = ref.addingTimeInterval(Double(offset * 60) * (before ? -1 : 1))
            if fire > now.addingTimeInterval(60) { out.append((fire, ref)) }
        }
        return out
    }

    /// Turn it on: ask for AlarmKit permission (once), then plan. False = refused / not supported.
    @MainActor static func enable() async -> Bool {
        guard #available(iOS 26.1, *) else { return false }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else { return false }
        } catch { return false }
        group?.set(true, forKey: activeKey)
        await plan(reason: "turned on")
        return true
    }

    /// Back to no AlarmKit alarms (permission gone, or AlarmKit mode off).
    @MainActor static func disable() async {
        group?.set(false, forKey: activeKey)
        cancelAll()
    }

    /// Every alarm of ours that isn't ringing right now.
    @MainActor private static func cancelAll() {
        group?.removeObject(forKey: throughKey)
        guard #available(iOS 26.1, *) else { return }
        for alarm in (try? AlarmManager.shared.alarms) ?? [] where alarm.state != .alerting {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
    }

    /// Make the scheduled alarms match the rule: cancel ones that are past or no longer wanted,
    /// add the missing days until AlarmKit's cap. Cheap when nothing changed (no calls at all).
    @MainActor static func plan(reason: String) async {
        guard #available(iOS 26.1, *), isActive else { return }
        if AlarmManager.shared.authorizationState != .authorized {
            print("⏰ fajr alarms: permission gone — off (\(reason))")
            group?.set(false, forKey: activeKey)
            return
        }
        // The alarm switched off: nothing scheduled (AlarmKit mode stays for when it's back on).
        guard group?.bool(forKey: "alarmEnabled") == true else { cancelAll(); return }
        let wanted = dates()
        let wantedKeys = Set(wanted.map { Int($0.alarm.timeIntervalSince1970 / 60) })
        let existing = (try? AlarmManager.shared.alarms) ?? []
        var have = Set<Int>()
        var cancelled = 0
        let tests = testIDs
        for alarm in existing where alarm.state != .alerting {
            // A test alarm is left alone until it's past (then it goes like any other).
            if tests.contains(alarm.id.uuidString) {
                if case .fixed(let date)? = alarm.schedule, date > Date() { continue }
                try? AlarmManager.shared.cancel(id: alarm.id)
                testIDs.remove(alarm.id.uuidString)
                continue
            }
            guard case .fixed(let date)? = alarm.schedule else { try? AlarmManager.shared.cancel(id: alarm.id); cancelled += 1; continue }
            let key = Int(date.timeIntervalSince1970 / 60)
            if date < Date() || !wantedKeys.contains(key) || have.contains(key) {
                try? AlarmManager.shared.cancel(id: alarm.id)
                cancelled += 1
            } else {
                have.insert(key)
            }
        }
        var added = 0
        var last: Date? = existing.compactMap { a -> Date? in
            if case .fixed(let d)? = a.schedule, have.contains(Int(d.timeIntervalSince1970 / 60)) { return d }
            return nil
        }.max()
        for item in wanted where !have.contains(Int(item.alarm.timeIntervalSince1970 / 60)) {
            do {
                let id = UUID()
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration(id: id, at: item.alarm, reference: item.reference))
                added += 1
                last = max(last ?? item.alarm, item.alarm)
                have.insert(Int(item.alarm.timeIntervalSince1970 / 60))
            } catch let error as AlarmManager.AlarmError where error == .maximumLimitReached {
                print("⏰ fajr alarms: AlarmKit's cap reached at \(have.count) alarms")
                break
            } catch {
                print("⏰ fajr alarms: schedule failed — \(error)")
                break
            }
        }
        if let last { group?.set(last.timeIntervalSince1970, forKey: throughKey) }
        if added > 0 || cancelled > 0 {
            print("⏰ fajr alarms (\(reason)): \(have.count) set, +\(added) −\(cancelled), through \(last.map { shortTimePMDate($0) } ?? "—")")
        }
        // The next one, for Settings' row and the widget-free summary.
        if let next = wanted.first {
            group?.set(shortTimePM(next.alarm), forKey: "alarmTimeSetFor")
        }
    }

    /// Settings' "Test alarm" (owner, 2026-09-30, note C9FB37FF): one real AlarmKit alarm at
    /// `date`, looking just like the Fajr one but titled as a test. False = not allowed / failed.
    @MainActor static func scheduleTest(at date: Date) async -> Bool {
        guard #available(iOS 26.1, *) else { return false }
        do {
            guard try await AlarmManager.shared.requestAuthorization() == .authorized else { return false }
            let id = UUID()
            testIDs.insert(id.uuidString)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration(id: id, at: date, reference: date, test: true))
            print("⏰ test alarm set for \(shortTimePM(date))")
            return true
        } catch {
            print("⏰ test alarm failed — \(error)")
            return false
        }
    }

    /// The test alarms still ahead (for Settings' line), soonest first.
    @MainActor static func pendingTests() -> [Date] {
        guard #available(iOS 26.1, *) else { return [] }
        let tests = testIDs
        return ((try? AlarmManager.shared.alarms) ?? []).compactMap { alarm -> Date? in
            guard tests.contains(alarm.id.uuidString), case .fixed(let d)? = alarm.schedule, d > Date() else { return nil }
            return d
        }.sorted()
    }

    @MainActor static func cancelTests() {
        guard #available(iOS 26.1, *) else { return }
        for id in testIDs { if let u = UUID(uuidString: id) { try? AlarmManager.shared.cancel(id: u) } }
        testIDs = []
    }

    @available(iOS 26.1, *)
    private static func configuration(id: UUID, at date: Date, reference: Date, test: Bool = false) -> AlarmManager.AlarmConfiguration<FajrAlarmMetadata> {
        let isFajr = group?.object(forKey: "alarmIsFajr") as? Bool ?? true
        let title: LocalizedStringResource = test ? "Test alarm from shukr"
            : "Fajr \(isFajr ? "starts" : "ends") \(shortTimePM(reference))"
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: AlarmButton(text: "I'm up — open Fajr", textColor: .white, systemImageName: "sunrise.fill"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: FajrAlarmMetadata(),
                                         tintColor: Color(red: 0.43, green: 0.62, blue: 0.5))
        return .alarm(schedule: .fixed(date), attributes: attributes,
                      stopIntent: FajrAlarmStopIntent(alarmID: id.uuidString),
                      secondaryIntent: FajrAlarmOpenIntent(alarmID: id.uuidString),
                      sound: .default)
    }
}

@available(iOS 26.1, *)
struct FajrAlarmMetadata: AlarmMetadata {}

/// The alarm's Stop: it stops, then the next days are topped up (runs in the app's process).
@available(iOS 26.1, *)
struct FajrAlarmStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the Fajr alarm"
    static let isDiscoverable = false
    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        await FajrAlarms.plan(reason: "alarm stopped")
        return .result()
    }
}

/// "I'm up — open Fajr": stops the alarm, opens shukr on the Salah page, tops up the next days.
@available(iOS 26.1, *)
struct FajrAlarmOpenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm up — open Fajr"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "alarmOpenSalah")
        await FajrAlarms.plan(reason: "I'm up")
        return .result()
    }
}
