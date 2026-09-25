
// MARK: - Intents

import AppIntents
import WidgetKit

// MARK: - Shared SwiftData store
//
// The app and the widget open the *same* store, kept in the app group container, so the
// widget's "complete prayer" button writes the completion directly and the app sees it on
// its next activation (`PrayerViewModel.reconcileAfterWidgetWrites`). The Models/ folder is
// compiled into both targets so the schema is identical on both sides.

import SwiftData
import CoreData
import CoreLocation

#if !DEBUG
/// Release builds log nothing: ~190 debug `print`s (some with coordinates) stay useful in DEBUG,
/// and this module-level function shadows `Swift.print` everywhere in the app and the widget
/// (this file is compiled into both targets).
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif
import SQLite3

enum SharedStore {
    static let appGroup = "group.betternorms.shukr.shukrWidget"
    /// Set by the widget after it writes; the app clears it once it has re-read the store.
    static let widgetWroteStoreKey = "widgetWroteStore"

    /// Current schema. Older stores are upgraded by SwiftData's inferred lightweight migration
    /// when the APP opens them (no staged plan — see SchemaVersions.swift for why), followed by
    /// `ShukrV2DataPass`. The widget only opens stores already at this version.
    static let schema = Schema(versionedSchema: ShukrSchemaV2.self)

    /// The store file. Falls back to SwiftData's default location if the app group is missing
    /// (which would mean the entitlement is broken; the widget can't share in that case anyway).
    static var url: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appending(path: "shukr.store")
        }
        return legacyURL
    }
    // MARK: Opening the store

    /// App side: open the shared store, creating it if needed. Call
    /// `importLegacyStoreIfNeeded(into:)` right after, before anything reads data.
    static func makeContainer() throws -> ModelContainer {
        // About to migrate an existing store (the app is the only one that does): copy it to
        // Library/Backups first, where `devicectl device copy from` can reach it.
        if Bundle.main.bundleURL.pathExtension != "appex",
           FileManager.default.fileExists(atPath: url.path), !storeIsCurrentVersion(at: url) {
            PrayerScoring.backUpStore(label: "before-\(currentVersionIdentifier)")
        }
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: Salvage from set-aside stores (app only)

    /// After a recovery, copy back what the fresh store lacks from each
    /// `shukr.store.unopenable-*` file: mantra fullText/notes (by name, into empty fields),
    /// prayer completions (by name + day, onto incomplete rows), and tasks / sessions missing by
    /// id. Read-only raw SQLite: SwiftData can't open the file, that's why it was set aside.
    /// Once per file (flag per file name); the file is left in place.
    static func salvageSetAsideStoresIfNeeded(into container: ModelContainer) {
        guard Bundle.main.bundleURL.pathExtension != "appex", url != legacyURL else { return }
        let dir = url.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let defaults = UserDefaults(suiteName: appGroup)
        for name in names.sorted() where name.hasPrefix("shukr.store.unopenable-") && !name.hasSuffix("-wal") && !name.hasSuffix("-shm") {
            let key = "salvaged." + name
            guard defaults?.bool(forKey: key) != true else { continue }
            do {
                let summary = try SetAsideStoreSalvage.run(file: dir.appending(path: name), into: ModelContext(container))
                defaults?.set(true, forKey: key)
                print("✅ salvage from \(name): \(summary)")
            } catch {
                print("❌ salvage from \(name) failed (will retry next launch): \(error)")
            }
        }
    }

    // MARK: Recovery when the shared store won't open (app only)

    /// Last resort, app only: the shared store exists but `makeContainer()` threw (a migration
    /// the OS won't infer, a store written by a model we can no longer match). Move the file
    /// aside — never delete — clear the legacy-import flag, and open a fresh store. The caller
    /// then runs the normal launch sequence, which re-imports the legacy `default.store` (still
    /// in the group container) and the V2 data pass. What the set-aside file held beyond the
    /// legacy store (activity since that file was last written) stays in it for salvage.
    /// Returns nil if there is nothing to recover from or the fresh store fails too.
    static func recoverFromUnopenableStore(after error: Error) -> ModelContainer? {
        guard Bundle.main.bundleURL.pathExtension != "appex" else { return nil }
        let fm = FileManager.default
        guard url != legacyURL, fm.fileExists(atPath: url.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        print("⚠️ store recovery: shared store won't open (\(error)); setting it aside as shukr.store.unopenable-\(stamp)")
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(filePath: url.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = URL(filePath: url.deletingLastPathComponent().appending(path: "shukr.store.unopenable-\(stamp)").path + suffix)
            do { try fm.moveItem(at: from, to: to) }
            catch { print("❌ store recovery: couldn't move \(from.lastPathComponent): \(error)"); return nil }
        }
        UserDefaults(suiteName: appGroup)?.set(false, forKey: legacyImportedKey) // re-import from default.store
        do {
            let fresh = try makeContainer()
            print("✅ store recovery: fresh store opened; legacy import + data pass follow")
            return fresh
        } catch {
            print("❌ store recovery: fresh store failed too: \(error)")
            return nil
        }
    }

    // MARK: Schema V2 data pass (app only)

    /// Seeds / links what the lightweight migration can't (see `ShukrV2DataPass`). Runs on
    /// every app launch: it only reads the rows that still need linking, so on a healthy store
    /// it costs a couple of tiny fetches, and any store shape (fresh, upgraded, half-migrated by
    /// an earlier build) heals itself without a flag to get out of sync.
    static func runV2DataPass(in container: ModelContainer) {
        guard Bundle.main.bundleURL.pathExtension != "appex" else { return }
        do {
            let summary = try ShukrV2DataPass.run(in: ModelContext(container))
            print("✅ schema V2 data pass: \(summary)")
        } catch {
            print("❌ schema V2 data pass failed (will retry next launch): \(error)")
        }
    }

    /// Widget side: open the shared store ONLY if the app has already created it AND it is at
    /// the current schema version. The widget never creates and never migrates the store:
    /// WidgetKit refreshes right after an install/update, so a widget-created store would be
    /// empty and pre-empt the app's legacy import (how the owner's tasks vanished once), and a
    /// widget-run migration races the app's own — sim-tested: the app's staged migration found
    /// the file already at 2.0.0 mid-flight and died with "model incompatible". Opened without
    /// the plan so it physically can't migrate. Retries on each access until the app has done
    /// its part, then caches.
    private static var cachedWidgetContainer: ModelContainer?
    static var widgetContainer: ModelContainer? {
        if let cached = cachedWidgetContainer { return cached }
        guard FileManager.default.fileExists(atPath: url.path), storeIsCurrentVersion(at: url) else { return nil }
        do {
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            cachedWidgetContainer = container
            return container
        } catch {
            print("❌ widget couldn't open the shared store: \(error)")
            return nil
        }
    }

    /// "2.0.0" etc. — what a migrated store carries in `NSStoreModelVersionIdentifiers`.
    static var currentVersionIdentifier: String {
        let v = ShukrSchemaV2.versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    /// Reads the store's metadata without opening it. False for a pre-versioned (V1) store,
    /// for an older versioned one, and for anything unreadable.
    static func storeIsCurrentVersion(at url: URL) -> Bool {
        guard let meta = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url) else { return false }
        let ids = meta[NSStoreModelVersionIdentifiersKey] as? [String] ?? []
        return ids.contains(currentVersionIdentifier)
    }

    // MARK: One-time import of the pre-app-group store (app only)

    /// "v2": the first version of this flag could be set without importing anything (it looked
    /// for the legacy file in the wrong place), so a new key makes sure the import still runs
    /// on an install that already carries the old flag.
    static let legacyImportedKey = "legacyStoreImported.v2"

    /// Where the store lived before it moved to `url`. With a default `ModelConfiguration()`,
    /// SwiftData puts `default.store` in the *app group's* Library/Application Support when the
    /// app has an app-group entitlement (this app has had one since the widget's shared
    /// UserDefaults), and in the app's own Application Support otherwise. Checked in that order.
    /// Only meaningful in the app process: an extension's Application Support is its own sandbox.
    private static var legacyURLs: [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            urls.append(group.appending(path: "Library/Application Support/default.store"))
        }
        urls.append(URL.applicationSupportDirectory.appending(path: "default.store"))
        return urls
    }
    /// Sandbox location; also what `url` falls back to when the app group is missing.
    private static var legacyURL: URL { URL.applicationSupportDirectory.appending(path: "default.store") }

    /// Merge everything from the old `default.store` into the shared store, once. A merge, not
    /// a file swap: the shared store may already hold data written since the update (prayers
    /// completed from the widget, for instance). The old files are never modified or deleted;
    /// we work on a temporary copy. The done-flag is set only after a successful save, so a
    /// failure retries next launch. If no legacy file exists the flag is left unset: the check
    /// is two `fileExists` calls, and a wrong "done" is what lost the owner's data once.
    static func importLegacyStoreIfNeeded(into container: ModelContainer) {
        guard Bundle.main.bundleURL.pathExtension != "appex" else { return }
        let defaults = UserDefaults(suiteName: appGroup)
        guard defaults?.bool(forKey: legacyImportedKey) != true else { return }

        let fm = FileManager.default
        // No app group (entitlement missing) means we're still running on the legacy file itself.
        guard url != legacyURL,
              let source = legacyURLs.first(where: { fm.fileExists(atPath: $0.path) }) else {
            print("ℹ️ legacy import: no legacy store found (fresh install, or nothing to import)")
            return
        }

        let tmpDir = fm.temporaryDirectory.appending(path: "legacy-import-\(UUID().uuidString)")
        let tmpStore = tmpDir.appending(path: "default.store")
        defer { try? fm.removeItem(at: tmpDir) }
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let from = URL(filePath: source.path + suffix)
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.copyItem(at: from, to: URL(filePath: tmpStore.path + suffix))
            }
            // The copy is at whatever version the old app wrote; opening it with the current
            // schema lightweight-migrates the copy (never the original).
            let legacyConfig = ModelConfiguration("legacy", schema: schema, url: tmpStore)
            let legacy = try ModelContainer(for: schema, configurations: [legacyConfig])
            let summary = try merge(from: ModelContext(legacy), into: ModelContext(container))
            defaults?.set(true, forKey: legacyImportedKey)
            print("✅ legacy import: \(summary)")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("❌ legacy import failed (will retry next launch): \(error)")
        }
    }

    /// Copy rows from `src` that `dst` doesn't have. Ids are preserved so the two stores stay
    /// comparable. Returns a one-line summary for the log.
    private static func merge(from src: ModelContext, into dst: ModelContext) throws -> String {
        var tasksN = 0, sessionsN = 0, mantrasN = 0, duasN = 0, prayersN = 0, mergedN = 0, scoresN = 0
        let cal = Calendar.current

        // Mantras first: tasks and sessions link to them. Dedupe by name, not id — the shared
        // store already holds the seeded built-ins (and anything added since) under its own ids.
        var mantraByName: [String: MantraModel] = [:]
        for mantra in try dst.fetch(FetchDescriptor<MantraModel>()) { mantraByName[mantra.name.lowercased()] = mantra }
        for old in try src.fetch(FetchDescriptor<MantraModel>()) where mantraByName[old.name.lowercased()] == nil {
            let new = MantraModel(name: old.name, fullText: old.fullText, notes: old.notes)
            new.id = old.id
            new.createdAt = old.createdAt
            dst.insert(new)
            mantraByName[new.name.lowercased()] = new
            mantrasN += 1
        }
        func mantra(for old: MantraModel?) -> MantraModel? {
            old.flatMap { mantraByName[$0.name.lowercased()] }
        }

        // Tasks next: sessions link to them by id.
        var taskByID: [UUID: TaskModel] = [:]
        for task in try dst.fetch(FetchDescriptor<TaskModel>()) { taskByID[task.id] = task }
        for old in try src.fetch(FetchDescriptor<TaskModel>()) where taskByID[old.id] == nil {
            let new = TaskModel(mantra: mantra(for: old.mantra), isCountMode: old.isCountMode,
                                goal: old.goal, mantraName: old.mantraName, sortOrder: old.sortOrder)
            new.id = old.id
            dst.insert(new)
            taskByID[new.id] = new
            tasksN += 1
        }

        let sessionIDs = Set(try dst.fetch(FetchDescriptor<SessionDataModel>()).map { $0.id })
        for old in try src.fetch(FetchDescriptor<SessionDataModel>()) where !sessionIDs.contains(old.id) {
            let new = SessionDataModel(
                title: old.title, sessionMode: old.sessionMode, targetMin: old.targetMin,
                targetCount: old.targetCount, totalCount: old.totalCount, startTime: old.startTime,
                secondsPassed: old.secondsPassed, avgTimePerClick: old.avgTimePerClick,
                tasbeehRate: old.tasbeehRate, task: old.task.flatMap { taskByID[$0.id] },
                mantra: mantra(for: old.mantra)
            )
            new.id = old.id
            new.timeDurationString = old.timeDurationString
            dst.insert(new)
            sessionsN += 1
        }

        let duaIDs = Set(try dst.fetch(FetchDescriptor<DuaModel>()).map { $0.id })
        for old in try src.fetch(FetchDescriptor<DuaModel>()) where !duaIDs.contains(old.id) {
            dst.insert(DuaModel(id: old.id, title: old.title, duaBody: old.duaBody, date: old.date))
            duasN += 1
        }

        // Prayers are keyed by name + day. The shared store has its own rows for days since the
        // update; keep those, except where the old row is completed and the new one isn't.
        func key(_ name: String, _ date: Date) -> String {
            "\(name)|\(cal.startOfDay(for: date).timeIntervalSince1970)"
        }
        var prayerByKey: [String: PrayerModel] = [:]
        for prayer in try dst.fetch(FetchDescriptor<PrayerModel>()) { prayerByKey[key(prayer.name, prayer.startTime)] = prayer }
        for old in try src.fetch(FetchDescriptor<PrayerModel>()) {
            if let existing = prayerByKey[key(old.name, old.startTime)] {
                if !existing.isCompleted && old.isCompleted {
                    copyCompletion(from: old, to: existing)
                    mergedN += 1
                }
                continue
            }
            let new = PrayerModel(name: old.name, startTime: old.startTime, endTime: old.endTime,
                                  latitude: old.latPrayedAt, longitude: old.longPrayedAt, dateAtMake: old.dateAtMake)
            new.id = old.id
            copyCompletion(from: old, to: new)
            dst.insert(new)
            prayerByKey[key(new.name, new.startTime)] = new
            prayersN += 1
        }

        var scoreDays = Set(try dst.fetch(FetchDescriptor<DailyPrayerScore>()).map { cal.startOfDay(for: $0.date) })
        for old in try src.fetch(FetchDescriptor<DailyPrayerScore>()) where !scoreDays.contains(cal.startOfDay(for: old.date)) {
            let new = DailyPrayerScore(date: old.date)
            new.id = old.id
            new.averageScore = old.averageScore
            dst.insert(new)
            scoreDays.insert(cal.startOfDay(for: old.date))
            scoresN += 1
        }

        try dst.save()
        return "tasks=\(tasksN) sessions=\(sessionsN) mantras=\(mantrasN) duas=\(duasN) prayers=\(prayersN) (merged \(mergedN)) scores=\(scoresN)"
    }

    private static func copyCompletion(from old: PrayerModel, to new: PrayerModel) {
        new.isCompleted = old.isCompleted
        new.timeAtComplete = old.timeAtComplete
        new.numberScore = old.numberScore
        new.englishScore = old.englishScore
        new.latPrayedAt = old.latPrayedAt
        new.longPrayedAt = old.longPrayedAt
        new.prayerStartedAt = old.prayerStartedAt
        new.prayerCompletedAt = old.prayerCompletedAt
        new.duration = old.duration
    }

    // MARK: Widget-side helpers (the app uses its own ModelContainer / PrayerViewModel)

    static func fetchPrayer(named name: String, on day: Date, in context: ModelContext) -> PrayerModel? {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? day
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.name == name && $0.startTime >= dayStart && $0.startTime <= dayEnd }
        )
        return try? context.fetch(descriptor).first
    }

    /// Names of today's prayers already marked complete, straight from the store.
    static func completedPrayerNamesToday() -> Set<String> {
        guard let container = widgetContainer else { return [] }
        let context = ModelContext(container)
        let (dayStart, dayEnd) = PrayerDay.rowRange(forDayStarting: PrayerDay.start())
        let descriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> { $0.isCompleted && $0.startTime >= dayStart && $0.startTime <= dayEnd }
        )
        let done = (try? context.fetch(descriptor)) ?? []
        return Set(done.map { $0.name })
    }

    /// Last location the app saved for the widget (it writes lastLatitude/lastLongitude).
    static func lastKnownLocation() -> CLLocation? {
        guard let store = UserDefaults(suiteName: appGroup) else { return nil }
        let lat = store.double(forKey: "lastLatitude"), lon = store.double(forKey: "lastLongitude")
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }
}

struct MarkCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Prayer Complete"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Prayer") var prayerName: String
    @Parameter(title: "Start") var prayerStart: Date
    @Parameter(title: "End") var prayerEnd: Date

    init() {}
    init(prayerName: String, prayerStart: Date, prayerEnd: Date) {
        self.prayerName = prayerName
        self.prayerStart = prayerStart
        self.prayerEnd = prayerEnd
    }

    func perform() async throws -> some IntentResult {
        SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
        return .result()
    }
}

extension SharedStore {
    /// Marks the prayer `name` on the day of `start` complete, scored at the tap. The widget's
    /// checkmark (`MarkCompleteIntent`) and the notification action "I already prayed"
    /// (`NotificationDelegate`) both come here. Writes through its own container and sets
    /// `widgetWroteStoreKey`, so the app re-reads on its next activation. Returns false when
    /// the prayer hasn't started, is already complete, or the store can't be opened.
    @discardableResult
    static func markPrayerComplete(named name: String, start: Date, end: Date) -> Bool {
        // Same rule as the app: a prayer that hasn't started can't be completed.
        guard start <= Date(), let container = widgetContainer else { return false }
        let context = ModelContext(container)

        // The app creates today's rows when it opens; if it hasn't opened today, make this one.
        let prayer = fetchPrayer(named: name, on: start, in: context) ?? {
            let made = PrayerModel(name: name, startTime: start, endTime: end, dateAtMake: start)
            context.insert(made)
            return made
        }()
        guard !prayer.isCompleted else { return false }

        prayer.isCompleted = true
        prayer.setPrayerScore()                                        // scored now, at the tap
        prayer.setPrayerLocation(with: lastKnownLocation())
        prayer.cancelUpcomingNudges()                                  // app repeats this on next open in case extensions can't
        do { try context.save() } catch {
            print("❌ markPrayerComplete(\(name)) save failed: \(error)")
            return false
        }

        UserDefaults(suiteName: appGroup)?.set(true, forKey: widgetWroteStoreKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "PrayersWidget")
        return true
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
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        
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

        print("1")

        guard alarmEnabled else {
            print("hellow3")
            throw AlarmDisabledError()
        }

        /*
        print("2")
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        print("3")
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        print("4")
        let fajrOrSunrise: enumPrayer = alarmIsFajr ? .fajr : .sunrise
        let fajrSunriseToday = PrayerUtils.getTime(for: fajrOrSunrise, in: todayTimes)
        let fajrSunriseTomorrow = PrayerUtils.getTime(for: fajrOrSunrise, in: tomorrowTimes)
        print("5")
        let nextFajrSunrise = Date() > fajrSunriseToday ? fajrSunriseTomorrow : fajrSunriseToday
        print("6")
        */
        
        let nextFajrSunrise = try PrayerUtils.getNextTime(for: alarmIsFajr ? .fajr : .sunrise)
 

        let offset = TimeInterval(alarmOffsetMinutes * 60)
        let resultTime = nextFajrSunrise.addingTimeInterval(alarmIsBefore ? -offset : offset)
        
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
        
        let prayerTime = PrayerUtils.getTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getTime(for: prayer, in: tomorrowTimes) : prayerTime
        
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
        
        let prayerTime = PrayerUtils.getTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getTime(for: prayer, in: tomorrowTimes) : prayerTime
        
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
//                "Get Next Fajr time from \(.applicationName)",
//                "When is Fajr",
//                "Get Fajr time from \(.applicationName)",
//                "Fajr time from \(.applicationName)",
//                "Get morning prayer time from \(.applicationName)",
//                "morning prayer time from \(.applicationName)"
                "Get Next Fajr time from ${applicationName}",
                "Get Fajr time from ${applicationName}",
                "Fajr time from ${applicationName}",
                "Get morning prayer time from ${applicationName}",
                "morning prayer time from ${applicationName}"
            ],
            shortTitle: "Fajr Time",
            systemImageName: "sunrise.fill"
        )
        
        AppShortcut(
            intent: GetSomePrayerTimeIntent(),
            phrases: [
//                "Get next prayer time from \(.applicationName)",
//                "Next prayer time from \(.applicationName)",
                "Get next prayer time from ${applicationName}",
                "Next prayer time from ${applicationName}"//,
//                "When is the next prayer",
//                "What's the upcoming prayer time"
            ],
            shortTitle: "Some Prayer Time",
            systemImageName: "clock.fill"
        )
        
        AppShortcut(
            intent: GetOffsetTimeIntent(),
            phrases: [
//                "Get offset prayer time from \(.applicationName)"
                "Get offset prayer time from ${applicationName}"
            ],
            shortTitle: "Offset Prayer Time",
            systemImageName: "clock.badge.questionmark"
        )
        
    }
}


// MARK: - Raw SQLite salvage of a store SwiftData can no longer open

/// Reads a set-aside `shukr.store` with the SQLite C API (the app already links it for the
/// Quran databases) and merges what the live store lacks. Core Data table/column names are the
/// model's with a Z prefix; dates are seconds since 2001; UUIDs are 16-byte blobs.
enum SetAsideStoreSalvage {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run(file: URL, into context: ModelContext) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            sqlite3_close(handle)
            throw Failure(description: "open: \(msg)")
        }
        defer { sqlite3_close(db) }
        let cal = Calendar.current

        // Mantras: text and notes, only where the live row has none.
        var mantraByName: [String: MantraModel] = [:]
        for m in try context.fetch(FetchDescriptor<MantraModel>()) { mantraByName[m.name.lowercased()] = m }
        var mantrasUpdated = 0
        for r in try rows(db, "SELECT ZNAME, ZFULLTEXT, ZNOTES FROM ZMANTRAMODEL") {
            guard let live = mantraByName[str(r, "ZNAME").lowercased()] else { continue }
            var changed = false
            let full = str(r, "ZFULLTEXT"), notes = str(r, "ZNOTES")
            if live.fullText.isEmpty, !full.isEmpty { live.fullText = full; changed = true }
            if live.notes.isEmpty, !notes.isEmpty { live.notes = notes; changed = true }
            if changed { mantrasUpdated += 1 }
        }

        // Tasks missing by id (rare; created after the legacy snapshot).
        var taskByID: [UUID: TaskModel] = [:]
        for t in try context.fetch(FetchDescriptor<TaskModel>()) { taskByID[t.id] = t }
        var oldTaskPKToID: [Int64: UUID] = [:]
        var tasksAdded = 0
        // No ZSORTORDER: a set-aside store may predate it (the owner's did). Added tasks go last.
        let nextOrder = TaskModel.nextSortOrder(in: context)
        for r in try rows(db, "SELECT Z_PK, ZID, ZMANTRANAME, ZISCOUNTMODE, ZGOAL FROM ZTASKMODEL") {
            guard let id = uuid(r, "ZID"), let pk = r["Z_PK"] as? Int64 else { continue }
            oldTaskPKToID[pk] = id
            if taskByID[id] != nil { continue }
            let name = str(r, "ZMANTRANAME")
            let task = TaskModel(mantra: mantraByName[name.lowercased()], isCountMode: int(r, "ZISCOUNTMODE") != 0,
                                 goal: Int(int(r, "ZGOAL")), mantraName: name, sortOrder: nextOrder + tasksAdded)
            task.id = id
            context.insert(task)
            taskByID[id] = task
            tasksAdded += 1
        }

        // Sessions missing by id.
        let sessionIDs = Set(try context.fetch(FetchDescriptor<SessionDataModel>()).map { $0.id })
        var sessionsAdded = 0
        for r in try rows(db, "SELECT ZID, ZTITLE, ZSESSIONMODE, ZTARGETMIN, ZTARGETCOUNT, ZTOTALCOUNT, ZSTARTTIME, ZSECONDSPASSED, ZAVGTIMEPERCLICK, ZTASBEEHRATE, ZTIMEDURATIONSTRING, ZTASK FROM ZSESSIONDATAMODEL") {
            guard let id = uuid(r, "ZID"), !sessionIDs.contains(id), let start = date(r, "ZSTARTTIME") else { continue }
            let title = str(r, "ZTITLE")
            let task = (r["ZTASK"] as? Int64).flatMap { oldTaskPKToID[$0] }.flatMap { taskByID[$0] }
            let s = SessionDataModel(
                title: title, sessionMode: Int(int(r, "ZSESSIONMODE")), targetMin: Int(int(r, "ZTARGETMIN")),
                targetCount: Int(int(r, "ZTARGETCOUNT")), totalCount: Int(int(r, "ZTOTALCOUNT")), startTime: start,
                secondsPassed: dbl(r, "ZSECONDSPASSED") ?? 0, avgTimePerClick: dbl(r, "ZAVGTIMEPERCLICK") ?? 0,
                tasbeehRate: str(r, "ZTASBEEHRATE"), task: task, mantra: mantraByName[title.lowercased()]
            )
            s.id = id
            if !str(r, "ZTIMEDURATIONSTRING").isEmpty { s.timeDurationString = str(r, "ZTIMEDURATIONSTRING") }
            context.insert(s)
            sessionsAdded += 1
        }

        // Prayer completions onto live rows that aren't complete (name + day).
        var prayerByKey: [String: PrayerModel] = [:]
        for p in try context.fetch(FetchDescriptor<PrayerModel>()) {
            prayerByKey["\(p.name)|\(cal.startOfDay(for: p.startTime).timeIntervalSince1970)"] = p
        }
        var prayersCompleted = 0
        for r in try rows(db, "SELECT ZNAME, ZSTARTTIME, ZTIMEATCOMPLETE, ZNUMBERSCORE, ZENGLISHSCORE, ZLATPRAYEDAT, ZLONGPRAYEDAT, ZPRAYERSTARTEDAT, ZPRAYERCOMPLETEDAT, ZDURATION FROM ZPRAYERMODEL WHERE ZISCOMPLETED = 1") {
            guard let start = date(r, "ZSTARTTIME"),
                  let live = prayerByKey["\(str(r, "ZNAME"))|\(cal.startOfDay(for: start).timeIntervalSince1970)"],
                  !live.isCompleted else { continue }
            live.isCompleted = true
            live.timeAtComplete = date(r, "ZTIMEATCOMPLETE")
            live.numberScore = dbl(r, "ZNUMBERSCORE")
            live.englishScore = r["ZENGLISHSCORE"] as? String
            live.latPrayedAt = dbl(r, "ZLATPRAYEDAT")
            live.longPrayedAt = dbl(r, "ZLONGPRAYEDAT")
            live.prayerStartedAt = date(r, "ZPRAYERSTARTEDAT")
            live.prayerCompletedAt = date(r, "ZPRAYERCOMPLETEDAT")
            live.duration = dbl(r, "ZDURATION")
            prayersCompleted += 1
        }

        if context.hasChanges { try context.save() }
        return "mantras updated=\(mantrasUpdated) tasks added=\(tasksAdded) sessions added=\(sessionsAdded) prayers completed=\(prayersCompleted)"
    }

    // MARK: SQLite helpers

    private static func rows(_ db: OpaquePointer, _ sql: String) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Failure(description: "prepare: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: Any]] = []
        let count = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, i) {
                        row[name] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i)))
                    }
                default: break
                }
            }
            out.append(row)
        }
        return out
    }

    private static func str(_ r: [String: Any], _ k: String) -> String { (r[k] as? String) ?? "" }
    private static func int(_ r: [String: Any], _ k: String) -> Int64 { (r[k] as? Int64) ?? Int64((r[k] as? Double) ?? 0) }
    private static func dbl(_ r: [String: Any], _ k: String) -> Double? {
        if let d = r[k] as? Double { return d }
        if let i = r[k] as? Int64 { return Double(i) }
        return nil
    }
    private static func date(_ r: [String: Any], _ k: String) -> Date? {
        dbl(r, k).map { Date(timeIntervalSinceReferenceDate: $0) }
    }
    private static func uuid(_ r: [String: Any], _ k: String) -> UUID? {
        guard let data = r[k] as? Data, data.count == 16 else { return nil }
        return UUID(uuid: data.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }
}
