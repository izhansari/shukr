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

/// The alarm rule's minutes: 5-minute steps up to an hour; before the END of Fajr at least 10 (owner: you need time to
/// wake up and make wudu — 0 or 5 minutes before sunrise is too late). Setup's and Settings' wheels and the scheduler
/// all go through here.
enum FajrAlarmRule {
    static func minutes(isFajr: Bool) -> [Int] { Array(stride(from: isFajr ? 0 : 10, through: 60, by: 5)) }
    static func clamp(_ minutes: Int, isFajr: Bool) -> Int { isFajr ? minutes : max(10, minutes) }
}

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
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let offset = FajrAlarmRule.clamp(g.integer(forKey: "alarmOffsetMinutes"), isFajr: isFajr)
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
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

    /// AlarmKit's answer so far: nil = not asked yet (or no AlarmKit), true = allowed, false = refused.
    @MainActor static var allowed: Bool? {
        guard #available(iOS 26.1, *) else { return nil }
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return nil
        }
    }

    /// Turn it on: ask for AlarmKit permission (once), then plan. False = refused / not supported.
    @MainActor static func enable() async -> Bool {
        guard #available(iOS 26.1, *) else { return false }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else { return false }
        } catch { return false }
        group?.set(true, forKey: activeKey)
        FajrAlarmLog.add("AlarmKit mode on")
        await plan(reason: "turned on")
        return true
    }

    /// Back to no AlarmKit alarms (permission gone, or AlarmKit mode off).
    @MainActor static func disable() async {
        group?.set(false, forKey: activeKey)
        FajrAlarmLog.add("AlarmKit mode off")
        cancelAll()
    }

    /// Every alarm of ours that isn't ringing right now.
    @MainActor private static func cancelAll() {
        group?.removeObject(forKey: throughKey)
        guard #available(iOS 26.1, *) else { return }
        let all = (try? AlarmManager.shared.alarms) ?? []
        for alarm in all where alarm.state != .alerting {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
        if !all.isEmpty { FajrAlarmLog.add("cancelled all \(all.count) alarms") }
    }

    /// Make the scheduled alarms match the rule: cancel ones that are past or no longer wanted,
    /// add the missing days until AlarmKit's cap. Cheap when nothing changed (no calls at all).
    @MainActor static func plan(reason: String) async {
        guard #available(iOS 26.1, *) else { return }
        // Switched off by a misread while AlarmKit is allowed and still holds our alarms (only `disable` turns it off on
        // purpose, and it cancels them all): back on, so they're kept to the rule again. The owner's phone, 2026-10-10:
        // mode off, permission authorized, 56 alarms nobody planned any more.
        if !isActive, AlarmManager.shared.authorizationState == .authorized, group?.bool(forKey: "alarmEnabled") == true,
           scheduled().contains(where: { !$0.test }) {
            group?.set(true, forKey: activeKey)
            group?.removeObject(forKey: "fajrAlarmLog.off")
            FajrAlarmLog.add("AlarmKit mode back on (\(reason)): allowed, and \(scheduled().count) alarm(s) were still set with nothing planning them")
        }
        guard isActive else {
            // AlarmKit mode off (the Shortcut answers): nothing re-plans or cancels what AlarmKit still holds. Say so
            // whenever that changes — leftovers ring at their old times (a lead for the midnight alarm, 2026-10-10).
            let held = scheduled().filter { !$0.test }
            let line = "AlarmKit mode off (\(String(describing: AlarmManager.shared.authorizationState))) — \(held.count) AlarmKit alarm(s) still set"
                + (held.first?.date.map { ", next \(FajrAlarmLog.day($0))" } ?? "")
            if group?.string(forKey: "fajrAlarmLog.off") != line {
                group?.set(line, forKey: "fajrAlarmLog.off")
                FajrAlarmLog.add(line)
            }
            return
        }
        if AlarmManager.shared.authorizationState != .authorized {
            FajrAlarmLog.add("plan (\(reason)): AlarmKit permission \(String(describing: AlarmManager.shared.authorizationState)) — AlarmKit mode off, the Shortcut can take over; \(scheduled().count) still set")
            group?.set(false, forKey: activeKey)
            return
        }
        // The alarm switched off: nothing scheduled (AlarmKit mode stays for when it's back on).
        guard group?.bool(forKey: "alarmEnabled") == true else { cancelAll(); return }
        logInputsIfChanged()
        let wanted = dates()
        if wanted.isEmpty { FajrAlarmLog.add("plan (\(reason)): no days worked out — no saved location?") }
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
                FajrAlarmLog.add("cancelled a past test alarm \(alarm.id.uuidString.prefix(4))")
                continue
            }
            guard case .fixed(let date)? = alarm.schedule else {
                try? AlarmManager.shared.cancel(id: alarm.id); cancelled += 1
                FajrAlarmLog.add("cancelled \(alarm.id.uuidString.prefix(4)): not a fixed date (\(String(describing: alarm.schedule)))")
                continue
            }
            let key = Int(date.timeIntervalSince1970 / 60)
            if date < Date() || !wantedKeys.contains(key) || have.contains(key) {
                try? AlarmManager.shared.cancel(id: alarm.id)
                cancelled += 1
                let why = date < Date() ? "past" : have.contains(key) ? "a second one that minute" : "not the rule's time any more"
                FajrAlarmLog.add("cancelled \(alarm.id.uuidString.prefix(4)) \(FajrAlarmLog.day(date)): \(why)")
            } else {
                have.insert(key)
            }
        }
        // Alarms that went off since the last plan: gone from AlarmKit without our cancelling them (rang and ended).
        let known = Set(group?.stringArray(forKey: "fajrAlarmLog.known") ?? [])
        let nowIDs = Set(existing.map(\.id.uuidString))
        let gone = known.subtracting(nowIDs)
        if !gone.isEmpty {
            let when = (group?.dictionary(forKey: "fajrAlarmLog.dates") as? [String: Double]) ?? [:]
            for id in gone {
                let at = when[id].map { FajrAlarmLog.day(Date(timeIntervalSince1970: $0)) } ?? "unknown time"
                FajrAlarmLog.add("went off: \(id.prefix(4)) set for \(at) (no longer in AlarmKit; a Stop / I'm up would be logged above)")
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
                // One line per alarm only for the first few (60 at once on a first plan).
                if added <= 3 { FajrAlarmLog.add("set \(id.uuidString.prefix(4)) \(FajrAlarmLog.day(item.alarm)) (Fajr \(shortTimePM(item.reference)))") }
                last = max(last ?? item.alarm, item.alarm)
                have.insert(Int(item.alarm.timeIntervalSince1970 / 60))
            } catch let error as AlarmManager.AlarmError where error == .maximumLimitReached {
                FajrAlarmLog.add("AlarmKit's limit reached at \(have.count) alarms")
                break
            } catch {
                FajrAlarmLog.add("setting one failed — \(error)")
                break
            }
        }
        if let last { group?.set(last.timeIntervalSince1970, forKey: throughKey) }
        // What's held now, for the next plan's "went off" lines.
        let held = (try? AlarmManager.shared.alarms) ?? []
        group?.set(held.map(\.id.uuidString), forKey: "fajrAlarmLog.known")
        var dates: [String: Double] = [:]
        for a in held { if case .fixed(let d)? = a.schedule { dates[a.id.uuidString] = d.timeIntervalSince1970 } }
        group?.set(dates, forKey: "fajrAlarmLog.dates")
        let next = wanted.first.map { " · next \(FajrAlarmLog.day($0.alarm))" } ?? ""
        FajrAlarmLog.add("plan (\(reason)): \(have.count) set, +\(added) −\(cancelled), through \(last.map { FajrAlarmLog.day($0) } ?? "—")\(next)")
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
            var dates = (group?.dictionary(forKey: "fajrAlarmLog.dates") as? [String: Double]) ?? [:]
            dates[id.uuidString] = date.timeIntervalSince1970
            group?.set(dates, forKey: "fajrAlarmLog.dates")
            FajrAlarmLog.add("test alarm \(id.uuidString.prefix(4)) set for \(FajrAlarmLog.day(date))")
            return true
        } catch {
            FajrAlarmLog.add("test alarm failed — \(error)")
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

    /// What the times are worked out from, logged when it changes (a move, a method or rule change, a time zone).
    private static func logInputsIfChanged() {
        guard let g = group else { return }
        let hasPlace = (try? PrayerUtils.getUserCoordinates()) != nil
        let offset = g.integer(forKey: "alarmOffsetMinutes")
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let line = String(format: "rule: %d min %@ %@ · at %.2f, %.2f · method %@ · madhab %d · %@", offset,
                          before ? "before" : "after", isFajr ? "Fajr" : "sunrise",
                          hasPlace ? g.double(forKey: "lastLatitude") : 0, hasPlace ? g.double(forKey: "lastLongitude") : 0,
                          String(describing: AutoMethod.effectiveMethod()), g.integer(forKey: "school"),
                          TimeZone.current.identifier)
        guard g.string(forKey: "fajrAlarmLog.inputs") != line else { return }
        g.set(line, forKey: "fajrAlarmLog.inputs")
        FajrAlarmLog.add(line)
    }

    /// The id of the alarm and its date, for the intents' lines.
    @available(iOS 26.1, *)
    static func describe(_ idString: String) -> String {
        guard let id = UUID(uuidString: idString) else { return idString }
        let alarm = ((try? AlarmManager.shared.alarms) ?? []).first { $0.id == id }
        // A ringing / stopped alarm no longer reports its schedule: the time noted when it was set.
        let noted = (UserDefaults(suiteName: SharedStore.appGroup)?.dictionary(forKey: "fajrAlarmLog.dates") as? [String: Double])?[idString]
        let when: String = if case .fixed(let d)? = alarm?.schedule { FajrAlarmLog.day(d) }
            else if let noted { FajrAlarmLog.day(Date(timeIntervalSince1970: noted)) } else { "unknown time" }
        let test = testIDs.contains(idString) ? " (test)" : ""
        return "\(idString.prefix(4)) set for \(when)\(test)"
    }

    /// While shukr runs: a line whenever one of ours starts ringing (AlarmKit's own updates).
    @MainActor static func watch() {
        guard #available(iOS 26.1, *), watching == nil else { return }
        watching = Task { @MainActor in
            var ringing = Set<UUID>()
            for await alarms in AlarmManager.shared.alarmUpdates {
                let now = Set(alarms.filter { $0.state == .alerting }.map(\.id))
                for id in now.subtracting(ringing) { FajrAlarmLog.add("ringing: \(describe(id.uuidString))") }
                ringing = now
            }
        }
    }
    @MainActor private static var watching: Task<Void, Never>?

    /// Every alarm AlarmKit has for shukr, soonest first (the Alarm check page).
    @MainActor static func scheduled() -> [(id: String, date: Date?, state: String, test: Bool)] {
        guard #available(iOS 26.1, *) else { return [] }
        let tests = testIDs
        return ((try? AlarmManager.shared.alarms) ?? []).map { a in
            let d: Date? = if case .fixed(let date)? = a.schedule { date } else { nil }
            return (a.id.uuidString, d, String(describing: a.state), tests.contains(a.id.uuidString))
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    @available(iOS 26.1, *)
    private static func configuration(id: UUID, at date: Date, reference: Date, test: Bool = false) -> AlarmManager.AlarmConfiguration<FajrAlarmMetadata> {
        let isFajr = group?.object(forKey: "alarmIsFajr") as? Bool ?? true
        var test = test
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-alarmTestIn") { test = false }   // looks like the real one
        #endif
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
        FajrAlarmLog.add("Stop: \(FajrAlarms.describe(alarmID))")
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
        FajrAlarmLog.add("I'm up: \(FajrAlarms.describe(alarmID))")
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: "alarmOpenSalah")
        await FajrAlarms.plan(reason: "I'm up")
        return .result()
    }
}

/// Settings → Fajr alarm → Alarm check (beta installs; owner, 2026-10-10: "it doesn't tell us how many it schedules and
/// how reliable it'll be"): every alarm AlarmKit holds for shukr, checked against the rule — the wrong time for its
/// day, two on one day, a day missing — and the log (FajrAlarmLog), newest first, to copy or share.
struct FajrAlarmCheckView: View {
    @State private var alarms: [(id: String, date: Date?, state: String, test: Bool)] = []
    @State private var wanted: [(alarm: Date, reference: Date)] = []
    @State private var log: [String] = []
    @State private var planning = false
    @State private var copied = false

    private var wantedKeys: Set<Int> { Set(wanted.map { Int($0.alarm.timeIntervalSince1970 / 60) }) }
    private var ours: [(id: String, date: Date?, state: String, test: Bool)] { alarms.filter { !$0.test } }

    /// Our alarms that aren't the rule's time for their day (what a re-plan would cancel).
    private var wrong: [(id: String, date: Date?, state: String, test: Bool)] {
        ours.filter { a in
            guard let d = a.date else { return true }
            return d > Date() && !wantedKeys.contains(Int(d.timeIntervalSince1970 / 60))
        }
    }
    private var doubles: Int {
        let days = ours.compactMap { $0.date.map { Calendar.current.startOfDay(for: $0) } }
        return days.count - Set(days).count
    }
    /// Days the rule wants up to the last one set, with no alarm.
    private var missing: [Date] {
        guard let last = ours.compactMap(\.date).max() else { return wanted.map(\.alarm) }
        let have = Set(ours.compactMap { $0.date.map { Int($0.timeIntervalSince1970 / 60) } })
        return wanted.map(\.alarm).filter { $0 <= last && !have.contains(Int($0.timeIntervalSince1970 / 60)) }
    }

    var body: some View {
        List {
            Section {
                row("AlarmKit permission", permission)
                row("shukr sets the alarms", FajrAlarms.isActive ? "yes" : "no (the Shortcut)")
                row("Alarms set", "\(ours.count)" + (alarms.count > ours.count ? " + \(alarms.count - ours.count) test" : ""))
                row("Through", ours.compactMap(\.date).max().map(FajrAlarmLog.day) ?? "—")
            }
            Section("Check") {
                check(wrong.isEmpty, wrong.isEmpty ? "Every alarm is the rule's time for its day"
                                                  : "\(wrong.count) not the rule's time: " + wrong.prefix(4).map { $0.date.map(FajrAlarmLog.day) ?? "no date" }.joined(separator: ", "))
                check(doubles == 0, doubles == 0 ? "One alarm a day" : "\(doubles) day(s) with two alarms")
                check(missing.isEmpty, missing.isEmpty ? "No day missing" : "\(missing.count) day(s) missing: " + missing.prefix(3).map(FajrAlarmLog.day).joined(separator: ", "))
                Button("Ring a test alarm in 1 minute") {
                    Task { _ = await FajrAlarms.scheduleTest(at: Date().addingTimeInterval(60)); load() }
                }
                Button(planning ? "Planning…" : "Re-plan now") {
                    planning = true
                    Task { await FajrAlarms.plan(reason: "Alarm check"); load(); planning = false }
                }
                .disabled(planning)
            }
            Section("Next alarms") {
                ForEach(Array(alarms.prefix(14).enumerated()), id: \.offset) { _, a in
                    HStack {
                        Text(a.date.map(FajrAlarmLog.day) ?? "no date").monospacedDigit()
                        Spacer()
                        Text(a.test ? "test" : a.state).font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(wrong.contains { $0.id == a.id } ? Color.red : Color.primary)
                }
            }
            Section {
                ForEach(Array(log.prefix(300).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = FajrAlarmLog.text; copied = true }
                    ShareLink(item: FajrAlarmLog.text) { Image(systemName: "square.and.arrow.up") }
                }
                .textCase(nil)
            }
        }
        .navigationTitle("Alarm check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .refreshable { load() }
    }

    private var permission: String {
        guard #available(iOS 26.1, *) else { return "needs iOS 26.1" }
        return String(describing: AlarmManager.shared.authorizationState)
    }

    private func load() {
        alarms = FajrAlarms.scheduled()
        wanted = FajrAlarms.dates()
        log = FajrAlarmLog.lines()
        copied = false
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }

    private func check(_ ok: Bool, _ text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Color.green : Color.orange)
    }
}
