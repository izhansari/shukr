
// MARK: - Intents

import AppIntents
import ActivityKit
import WidgetKit
#if canImport(AlarmKit)
import AlarmKit
#endif

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
        // `.none`: with the app's iCloud entitlement (Your Data's iCloud Drive copy) SwiftData's default `.automatic`
        // turns on CloudKit sync, which our models can't do — the store refused to open (2026-10-14).
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
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
        for name in names.sorted() where name.hasPrefix("shukr.store.unopenable-") && !name.hasSuffix("-wal")
            && !name.hasSuffix("-shm") && !name.hasSuffix("_SUPPORT") {
            // (the set-aside media folder is a directory, never a store)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.appending(path: name).path, isDirectory: &isDir), !isDir.boolValue else { continue }
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
        // Only a store we can read and whose model doesn't match ours (or a corrupt file) is set aside.
        // Anything else — the file protected before the first unlock after a reboot (a background relaunch
        // for a location event), locked, a permission or timeout error — is transient: the caller runs in
        // memory for this launch and the files stay exactly where they are (audit A1, 2026-10-01).
        let verdict = storeOpenFailure(error)
        guard verdict.setAside else {
            print("⚠️ store recovery: not setting the store aside — \(verdict.reason) (\(error))")
            return nil
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        print("⚠️ store recovery: shared store won't open (\(verdict.reason): \(error)); setting it aside as shukr.store.unopenable-\(stamp)")
        // Copy all three files first, then remove the originals: a half-moved store (main file gone,
        // WAL left behind) used to lose the latest transactions (audit A3).
        let dir = url.deletingLastPathComponent()
        let asideBase = dir.appending(path: "shukr.store.unopenable-\(stamp)").path
        var copied: [URL] = []
        for suffix in ["-wal", "-shm", ""] {
            let from = URL(filePath: url.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = URL(filePath: asideBase + suffix)
            do { try fm.copyItem(at: from, to: to); copied.append(to) }
            catch {
                print("❌ store recovery: couldn't copy \(from.lastPathComponent): \(error) — leaving the store in place")
                for c in copied { try? fm.removeItem(at: c) }
                return nil
            }
        }
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(filePath: url.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            do { try fm.removeItem(at: from) }
            catch { print("⚠️ store recovery: couldn't remove \(from.lastPathComponent) after copying it: \(error)") }
        }
        // Its photos / voice memos (external storage) go aside with it, never deleted.
        let support = dir.appending(path: ".shukr_SUPPORT")
        if fm.fileExists(atPath: support.path) {
            let aside = dir.appending(path: "shukr.store.unopenable-\(stamp)_SUPPORT")
            do { try fm.moveItem(at: support, to: aside) }
            catch { print("⚠️ store recovery: couldn't set the media aside: \(error)") }
        }
        UserDefaults(suiteName: appGroup)?.set(false, forKey: legacyImportedKey) // re-import from default.store
        // The fresh store gets the built-ins again (their seed-once flags belong to the old one).
        UserDefaults.standard.removeObject(forKey: BuiltInAzkar.originalsSeededKey)
        UserDefaults.standard.removeObject(forKey: BuiltInAzkar.doneKey)
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
            let context = ModelContext(container)
            let seed = !UserDefaults.standard.bool(forKey: BuiltInAzkar.originalsSeededKey)
            let summary = try ShukrV2DataPass.run(in: context, seedOriginals: seed)
            if seed { UserDefaults.standard.set(true, forKey: BuiltInAzkar.originalsSeededKey) }
            print("✅ schema V2 data pass: \(summary)")
            // The built-ins' Arabic + notes and four new ones, once (BuiltInAzkar.swift).
            if let azkar = BuiltInAzkar.applyIfNeeded(in: context) { print("✅ built-in azkar: \(azkar)") }
            let tagged = BuiltInAzkar.tagRows(in: context)
            if tagged > 0 { print("✅ built-in azkar tagged: \(tagged)") }
            // 2.8.0: every prayer row carries its prayer day; rows from before get theirs here, once.
            let keyed = try backfillPrayerDayKeys(in: context)
            if keyed > 0 { print("✅ prayer day keys: filled=\(keyed)") }
        } catch {
            print("❌ schema V2 data pass failed (will retry next launch): \(error)")
        }
    }

    /// Rows with no `prayerDayKey` (made before 2.8.0) get the prayer day their start falls in — Fajr to the
    /// next Fajr at the saved location, the same rule new rows use — so an Isha that started after midnight
    /// joins its own day. Cheap: fetches only the rows that still need it; returns how many it filled.
    static func backfillPrayerDayKeys(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.prayerDayKey == nil }))
        guard !rows.isEmpty else { return 0 }
        for row in rows { row.prayerDayKey = PrayerDay.key(forRow: row.name, startingAt: row.startTime) }
        try context.save()
        return rows.count
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
        let t0 = ContinuousClock.now
        guard FileManager.default.fileExists(atPath: url.path), storeIsCurrentVersion(at: url) else {
            WidgetPerf.log("store not opened (missing or not \(currentVersionIdentifier)) \(WidgetPerf.ms(since: t0)) ms")
            return nil
        }
        do {
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            WidgetPerf.log("store opened \(WidgetPerf.ms(since: t0)) ms")
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

    /// Why `makeContainer()` failed, and whether setting the store aside is the right answer (audit A1).
    /// Set aside: the file reads fine but its model version isn't ours (a migration SwiftData won't infer), the
    /// error chain names a Core Data model / migration code, or the file is corrupt. Leave alone: everything
    /// else (protected data not yet available, a lock, a permission or timeout error, an unknown failure).
    static func storeOpenFailure(_ error: Error) -> (setAside: Bool, reason: String) {
        let codes = cocoaErrorCodes(in: error)
        // NSPersistentStoreIncompatibleSchemaError, …IncompatibleVersionHashError, the NSMigration* family,
        // NSInferredMappingModelError, the staged-migration codes (1345xx), NSFileReadCorruptFileError.
        let structural: Set<Int> = [134020, 134100, 134110, 134111, 134120, 134130, 134140, 134150, 134160, 134170, 134180, 134190, 259]
        if let c = codes.first(where: { structural.contains($0) || (134500...134599).contains($0) }) {
            return (true, "model / migration error \(c)")
        }
        switch (try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)) {
        case .some(let meta):
            let ids = meta[NSStoreModelVersionIdentifiersKey] as? [String] ?? []
            if ids.contains(currentVersionIdentifier) { return (false, "the file reads and is at our version; the failure is transient or unknown") }
            return (true, "the file reads but its model version \(ids) isn't ours (\(currentVersionIdentifier))")
        case .none:
            if codes.contains(259) { return (true, "corrupt file") }
            return (false, "the file can't be read right now (protected, locked or missing)")
        }
    }

    /// Every NSCocoaErrorDomain code in an error and its underlying / detailed errors (SwiftData wraps Core Data's).
    static func cocoaErrorCodes(in error: Error) -> [Int] {
        var out: [Int] = []
        var seen = 0
        func walk(_ e: Error) {
            seen += 1; guard seen < 20 else { return }
            let ns = e as NSError
            if ns.domain == NSCocoaErrorDomain { out.append(ns.code) }
            if let u = ns.userInfo[NSUnderlyingErrorKey] as? Error { walk(u) }
            if let many = ns.userInfo[NSDetailedErrorsKey] as? [Error] { many.forEach(walk) }
        }
        walk(error)
        // SwiftData's own error type hides the NSError; its description still carries "Code=1341xx".
        if out.isEmpty {
            let text = String(describing: error)
            var i = text.startIndex
            while let r = text.range(of: "Code=", range: i..<text.endIndex) {
                let digits = text[r.upperBound...].prefix { $0.isNumber }
                if let n = Int(digits) { out.append(n) }
                i = r.upperBound
            }
        }
        return out
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
            let legacyConfig = ModelConfiguration("legacy", schema: schema, url: tmpStore, cloudKitDatabase: .none)
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
        // 2.8.0: the prayer day `day` falls in, by key; a completed row wins over an unmarked twin (audit B4).
        let rows = ((try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forRow: name, startingAt: day)))) ?? []).filter { $0.name == name }
        return rows.first(where: \.isCompleted) ?? rows.sorted { $0.startTime < $1.startTime }.first
    }

    /// Names of today's prayers already marked complete, straight from the store.
    static func completedPrayerNamesToday() -> Set<String> {
        guard let container = widgetContainer else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: PrayerDay.start()))   // 2.8.0
        let done = ((try? context.fetch(descriptor)) ?? []).filter(\.isCompleted)
        return Set(done.map { $0.name })
    }

    /// When a prayer was marked (its row on that prayer day), for I Prayed's card when it's already marked.
    static func markedTime(of name: String, start: Date) -> Date? {
        guard let container = widgetContainer else { return nil }
        guard let row = fetchPrayer(named: name, on: start, in: ModelContext(container)), row.isCompleted else { return nil }
        return row.timeAtComplete ?? Date()
    }

    /// Last location the app saved for the widget (it writes lastLatitude/lastLongitude).
    /// When the saved spot was last a real fix (`PrayerViewModel.handleLocationChange`; cleared by a picked city).
    static let lastFixAtKey = "lastFixAt"
    /// The last real fix, while it's recent (30 min; audit B10): a widget / watch mark records where it was prayed from
    /// this. A stale fix, or a picked city's centre, put prayers at a mosque they weren't near (a Friday Dhuhr became Jumu'ah).
    static func lastKnownLocation() -> CLLocation? {
        guard let store = UserDefaults(suiteName: appGroup) else { return nil }
        let at = store.double(forKey: lastFixAtKey)
        guard at > 0, Date().timeIntervalSince1970 - at < 30 * 60 else { return nil }
        let lat = store.double(forKey: "lastLatitude"), lon = store.double(forKey: "lastLongitude")
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }
}

/// A LiveActivityIntent so it runs in shukr's process (owner, 2026-10-11): the prayer's Live Activity card goes at once,
/// and the app can take a fresh location for it (S9FJ) — from the widget's own process it could do neither.
struct MarkCompleteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer Complete"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false   // the widget's button; Shortcuts gets "Mark Prayer as Prayed"

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
        let t0 = ContinuousClock.now
        WidgetPerf.log("mark \(prayerName) start")
        if let hook = PrayerWindowHooks.widgetMark {
            _ = await hook(prayerName, prayerStart, prayerEnd)
        } else {
            SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
        }
        WidgetPerf.log("mark \(prayerName) done \(WidgetPerf.ms(since: t0)) ms")
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
        // Same rule as the app: a prayer that hasn't started can't be completed; nor one she's excused from.
        guard start <= Date(), !Excused.covers(start: start, end: end), let container = widgetContainer else { return false }
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

        let group = UserDefaults(suiteName: appGroup)
        group?.set(true, forKey: widgetWroteStoreKey)
        // The app rescores that day and its streaks (audit B5: every mark made outside the app, not only the list's —
        // a late mark of yesterday's Isha from a notification left yesterday's score stale).
        group?.set(start.timeIntervalSince1970, forKey: WidgetListMarks.markedDayKey)
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
        ControlCenter.shared.reloadAllControls()   // its "ends …" moves on
        return true
    }

    /// Posted by the app's own notification handler after "I already prayed" lands while the app is in front
    /// (audit B7): the page reconciles at once instead of at the next activation.
    static let markedElsewhere = Notification.Name("shukr.markedElsewhere")
}

struct OpenTasbeehIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbeeh"
    /// Folded into "Open shukr" → Zikr; the Tasbeeh control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's Zikr page.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
    
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetTasbeeh")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTasbeeh: \(store.bool(forKey: "widgetTasbeeh"))")
        }
        return .result()
    }
}

struct OpenCompassIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Qibla"
    /// Folded into "Open shukr" → Qibla; the Qibla control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's qibla map, turned so the qibla points up.")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(true, forKey: "widgetCompass")
            DeepLinkSignal.post()
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetCompass: \(store.bool(forKey: "widgetCompass"))")
        }
        return .result()
    }
}

/// A widget / control open's flags have just been written (widget-open-chrome). These intents run in the app
/// (`openAppWhenRun`), so on a cold launch they write after the app has started — after the welcome decided to play
/// and after the first look at the flags. The app opens the page as soon as this arrives, and the welcome steps aside.
/// In the widget's own process nobody listens.
enum DeepLinkSignal {
    static let arrived = Notification.Name("shukr.deepLinkArrived")
    static func post() {
        Task { @MainActor in NotificationCenter.default.post(name: arrived, object: nil) }
    }
}

/// Widget → one zikr task: the Zikr page with that task's circle in the middle, ready to tap.
struct OpenZikrTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Zikr Task"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        store?.set(taskID, forKey: "widgetZikrTask")
        store?.set(true, forKey: "widgetTasbeeh")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Widget → the Daily Ayah page (one-shot flag read on activation, like the compass one).
struct OpenDailyAyahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Daily Ayah"
    /// Folded into "Open shukr" → Daily Ayah; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens today's ayah in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetDailyAyah")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Widget times list (`WidgetListMarks`): a started row marks its prayer,
/// scored at the tap like the corner check, and the list stays up another `openFor` so the filled
/// circle is seen (the mark reloads the timeline).
struct MarkFromListIntent: LiveActivityIntent {   // in shukr's process, like MarkCompleteIntent
    static var title: LocalizedStringResource = "Mark Prayer Complete from the List"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

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
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        store?.set(true, forKey: WidgetListState.openKey)
        store?.set(Date().timeIntervalSince1970, forKey: WidgetListState.openedAtKey)
        let marked: Bool
        if let hook = PrayerWindowHooks.widgetMark {
            marked = await hook(prayerName, prayerStart, prayerEnd)
        } else {
            marked = SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
        }
        if !marked {
            WidgetCenter.shared.reloadAllTimelines()   // nothing marked: still keep the list up
        }
        return .result()
    }
}

/// Widget times list (`WidgetListMarks`): a done row opens the app to
/// "Unmark Asr?" — the widget never unmarks by itself.
struct AskUnmarkPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Unmark a Prayer"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "Prayer") var prayerName: String
    @Parameter(title: "Start") var prayerStart: Date

    init() {}
    init(prayerName: String, prayerStart: Date) {
        self.prayerName = prayerName
        self.prayerStart = prayerStart
    }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?
            .set("\(prayerName)|\(prayerStart.timeIntervalSince1970)", forKey: WidgetListMarks.unmarkKey)
        DeepLinkSignal.post()   // a running app asks at once (a Shortcuts card's Undo)
        return .result()
    }
}

/// Widget → the 99 Names page.
struct OpenNamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 99 Names"
    /// Folded into "Open shukr" → 99 Names; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens the 99 Names in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetNames")
        DeepLinkSignal.post()
        return .result()
    }
}

/// The Prayers widget's times list doesn't stick (2026-09-27, notes #1): opening it stores when,
/// and the timeline shows the list now plus the ring again `openFor` seconds later.
enum WidgetListState {
    static let openKey = "toggleShowAllTImes"
    static let openedAtKey = "widgetListOpenedAt"
    static let openFor: TimeInterval = 30

    static var openedAt: Date? {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        guard store?.bool(forKey: openKey) == true else { return nil }
        let t = store?.double(forKey: openedAtKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    /// Showing at `date` (opened less than `openFor` ago).
    static func isOpen(at date: Date) -> Bool {
        guard let openedAt else { return false }
        return date >= openedAt && date.timeIntervalSince(openedAt) < openFor
    }
}

struct showListToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetPerf.log("list toggle")
        if let store = UserDefaults(suiteName: SharedStore.appGroup) {
            // Showing → back to the ring at once; otherwise open it (again) from now.
            if WidgetListState.isOpen(at: Date()) {
                store.set(false, forKey: WidgetListState.openKey)
            } else {
                store.set(true, forKey: WidgetListState.openKey)
                store.set(Date().timeIntervalSince1970, forKey: WidgetListState.openedAtKey)
            }
        }
        return .result()
    }
}

struct textToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Screen"
    static var isDiscoverable: Bool = false   // a widget's own button, not a Shortcuts action
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        
        WidgetPerf.log("ring tap (text toggle)")
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(!store.bool(forKey: "widgetTextToggle"), forKey: "widgetTextToggle")
            WidgetCenter.shared.reloadAllTimelines()
            print("widgetTextToggle: \(store.bool(forKey: "widgetTextToggle"))")
        }
        return .result()
    }
}


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









// MARK: - From TasbeehView

/// AppEnum for Prayer Selection

/// AppEnum for Reference Point
enum ReferencePoint: String, AppEnum {
    case after = "after"
    case before = "before"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Before or After"
    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
        .before: "before",
        .after: "after"
    ]
}

/// Intent: Get Time of Chosen Prayer
struct GetSomePrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time of Chosen Prayer"
    /// Folded into "Get Prayer Time" (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description: LocalizedStringResource = "The next start time of the prayer you pick (today's, or tomorrow's once it has passed)."
    
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
        
        return .result(value: nextPrayerTime, dialog: IntentDialog(stringLiteral: "\(prayer.rawValue.capitalized) is at \(shortTimePM(nextPrayerTime))."))
    }
}

/// Intent: Get Next Fajr Time
struct GetNextFajrIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Fajr Time"
    /// Folded into "Get Prayer Time" → Fajr (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description: LocalizedStringResource = "When Fajr next starts, with your method and madhab."
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let nextFajr = Date() > todayTimes.fajr ? tomorrowTimes.fajr : todayTimes.fajr
        return .result(value: nextFajr, dialog: IntentDialog(stringLiteral: "Fajr is at \(shortTimePM(nextFajr))."))
    }
}

/// Intent: Get Offset Time Relative to Any Prayer
struct GetOffsetTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Offset Time Relative to Prayer"
    /// Folded into "Get Prayer Time" with minutes before / after (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "A time a set number of minutes before or after a prayer starts — e.g. 15 minutes before Maghrib to start cooking, or 10 minutes after Fajr for the lights. Uses the prayer's next start (today's, or tomorrow's once it has passed).",
        categoryName: "Prayer Times")

    // Same parameter names as before, so shortcuts already built keep their values.
    @Parameter(title: "Minutes", description: "How many minutes away from the prayer's start, 0 to 600.",
               default: 15, controlStyle: .field, inclusiveRange: (0, 600))
    var offsetMinutes: Int

    @Parameter(title: "Before or after", description: "Before or after the prayer starts.", default: .before)
    var referencePoint: ReferencePoint

    @Parameter(title: "Prayer", description: "The prayer to count from. Sunrise works too.", default: .maghrib)
    var prayer: enumPrayer

    static var parameterSummary: some ParameterSummary {
        Summary("Get the time \(\.$offsetMinutes) minutes \(\.$referencePoint) \(\.$prayer) starts")
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
        let name = prayer.rawValue
        let line = offsetMinutes == 0 ? "\(name) starts at \(shortTimePM(resultTime))."
            : "\(offsetMinutes) minutes \(referencePoint.rawValue) \(name) is \(shortTimePM(resultTime)) (\(name) at \(shortTimePM(nextPrayerTime)))."
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: line))
    }
}




/// Intent: Get Offset Time Relative to Fajr or Sunrise
/// The Fajr alarm's record (owner, 2026-10-10: "it doesn't tell us how many it schedules … i got an alarm going off at
/// midnight one time"): every plan, alarm set or cancelled, stop, "I'm up", ring seen and Shortcut call, with what it was
/// worked out from — in the app group, so the app and the Shortcut's intent both write it. Settings → Fajr alarm →
/// Alarm check shows it (beta installs); `devicectl … --domain-type appGroupDataContainer` pulls it.
enum FajrAlarmLog {
    private static let queue = DispatchQueue(label: "shukr.fajrAlarmLog")
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/fajr-alarm.log", isDirectory: false)
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm:ss zzz"
        return f
    }()
    /// "Fri Oct 10 5:12 AM" — every date in the log reads the same way.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    static func add(_ line: String) {
        let text = "\(stamp.string(from: Date()))  \(line)\n"
        print("⏰ \(line)")
        // Written before returning: the alarm's Stop runs shukr for a moment in the background, and a write left for later
        // was lost when iOS suspended it straight after (his first morning had no Stop line at all).
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? Data(text.utf8).write(to: url)
            }
            // Kept to the last ~1500 lines.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 400_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                let kept = all.split(separator: "\n").suffix(1500).joined(separator: "\n") + "\n"
                try? kept.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Newest first.
    static func lines() -> [String] {
        queue.sync {
            guard let url, let all = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return all.split(separator: "\n").map(String.init).reversed()
        }
    }

    static var text: String { queue.sync { url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" } }
}

/// The first Shortcut's step, kept for automations already made from it: it still stops them when the alarm is off or
/// shukr sets it itself, so they never make a second alarm. Hidden from the actions list: new shortcuts use
/// `FajrAlarmTimeIntent` (never blocks) and `FajrAlarmShortcutCheckIntent` (owner, 2026-10-12).
struct SetFajrAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Autopilot Fajr Alarm Time (legacy)"
    static var description: LocalizedStringResource = "Used by the first version of shukr's Fajr alarm Shortcut. New shortcuts: use Get Fajr Alarm Time."
    static var isDiscoverable: Bool = false

//    private let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
    
    /// Custom Error for Disabled Alarm
    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Your Fajr alarm is off. Turn it on in shukr’s Settings."
        }
    }

    /// shukr sets the Fajr alarm itself (AlarmKit, iOS 26.1+): this Shortcut step fails on purpose,
    /// so the shared Shortcut stops here and its next step ("Create Alarm") never runs — no second
    /// alarm, and nobody has to delete their automation.
    struct SetByShukrError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "shukr sets your Fajr alarm itself now, so this automation doesn't need to. You can turn it off in Shortcuts."
        }
    }

    /// Excused (Excused.swift): no alarm, said neutrally.
    struct NoAlarmNeededError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource { "No Fajr alarm is needed right now." }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        if Excused.isActive {
            FajrAlarmLog.add("Shortcut asked: excused — no alarm")
            throw NoAlarmNeededError()
        }
        if let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"), group.bool(forKey: "alarmKitActive") {
            // AlarmKit's permission taken away while the app wasn't running (audit B13): the Shortcut takes over
            // again, instead of neither setting an alarm.
            var permissionGone = false
            var permission = "?"
            #if canImport(AlarmKit)
            if #available(iOS 26.1, *) {
                permission = String(describing: AlarmManager.shared.authorizationState)
                // Only a real refusal: outside the app the state can read otherwise (the owner's phone went to the
                // Shortcut with AlarmKit allowed, 56 alarms left unplanned — 2026-10-10).
                if AlarmManager.shared.authorizationState == .denied { permissionGone = true }
            }
            #endif
            if permissionGone {
                FajrAlarmLog.add("Shortcut asked: AlarmKit permission reads \(permission) in \(Bundle.main.bundleIdentifier ?? "?") — AlarmKit mode off, the Shortcut takes over (AlarmKit's alarms stay set)")
                group.set(false, forKey: "alarmKitActive")
            } else {
                // A Shortcut that carries on past this error makes its "Create Alarm" with no time: 12:00 AM.
                FajrAlarmLog.add("Shortcut asked: AlarmKit sets the alarm — refused (an automation that carries on past this error makes a 12:00 AM alarm)")
                throw SetByShukrError()
            }
        }
        let calculatedAlarm: (description: String, time: Date)
        do { calculatedAlarm = try PrayerUtils.calculateAlarmDescription() } catch {
            FajrAlarmLog.add("Shortcut asked: no time worked out — \(error)")
            throw error
        }
        let resultTime = calculatedAlarm.time
        FajrAlarmLog.add("Shortcut asked: gave \(FajrAlarmLog.day(resultTime)) (\(calculatedAlarm.description))")

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





// MARK: - Prayer times, asked for in Shortcuts

/// Which prayer "Get Prayer Time" means, from now.
enum PrayerPick: String, AppEnum {
    case relevant, current, previous, next, fajr, dhuhr, asr, maghrib, isha
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Which prayer"
    static var caseDisplayRepresentations: [PrayerPick: DisplayRepresentation] = [
        .relevant: DisplayRepresentation(title: "Relevant", subtitle: "What shukr's circle shows: the one to pray now, next, or one you missed",
                                         image: .init(systemName: "scope")),
        .current: DisplayRepresentation(title: "Current", subtitle: "The prayer whose time it is now, prayed or not", image: .init(systemName: "clock"),
                                        synonyms: ["current prayer", "the current prayer", "this prayer"]),
        .previous: DisplayRepresentation(title: "Previous", subtitle: "The one before the current prayer", image: .init(systemName: "arrow.backward"),
                                         synonyms: ["previous prayer", "the previous prayer", "the last prayer"]),
        .next: DisplayRepresentation(title: "Next", subtitle: "The next to start", image: .init(systemName: "arrow.forward"),
                                     synonyms: ["next prayer", "the next prayer"]),
        // The five by name (owner: one Prayer Time in place of Fajr Time / Chosen Prayer): today's, or the next once over.
        .fajr: DisplayRepresentation(title: "Fajr", image: .init(systemName: prayerIcon(for: "Fajr").replacingOccurrences(of: ".fill", with: ""))),
        .dhuhr: DisplayRepresentation(title: "Dhuhr", image: .init(systemName: prayerIcon(for: "Dhuhr").replacingOccurrences(of: ".fill", with: ""))),
        .asr: DisplayRepresentation(title: "Asr", image: .init(systemName: prayerIcon(for: "Asr").replacingOccurrences(of: ".fill", with: ""))),
        .maghrib: DisplayRepresentation(title: "Maghrib", image: .init(systemName: prayerIcon(for: "Maghrib").replacingOccurrences(of: ".fill", with: ""))),
        .isha: DisplayRepresentation(title: "Isha", image: .init(systemName: prayerIcon(for: "Isha").replacingOccurrences(of: ".fill", with: ""))),
    ]
    /// The prayer's name for the five; nil for relevant / current / previous / next.
    var prayerName: String? {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        default: nil
        }
    }
}

/// The Shortcuts app's options for Prayer Time's tile, grouped (a phrase with a choice in it makes a tile per option —
/// these fold them into two collections under the one tile).
struct PrayerPickRelativeOptions: DynamicOptionsProvider {
    func results() async throws -> [PrayerPick] { [.relevant, .current, .next, .previous] }
}
struct PrayerPickByNameOptions: DynamicOptionsProvider {
    func results() async throws -> [PrayerPick] { [.fajr, .dhuhr, .asr, .maghrib, .isha] }
}

/// The five prayers' windows from yesterday to tomorrow, in order (Isha to 11:59 PM; Sunrise is never a prayer).
enum PrayerWindows {
    struct Window { let name: String; let start: Date; let end: Date }

    static func around(_ now: Date = Date()) -> [Window] {
        guard let coords = try? PrayerUtils.getUserCoordinates() else { return [] }
        let params = PrayerUtils.getCalculationParameters()
        let cal = Calendar.current
        let today = PrayerDay.date(for: now)
        var all: [Window] = []
        for offset in -1...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let times = try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params) else { continue }
            let nextFajr = cal.date(byAdding: .day, value: 1, to: day)
                .flatMap { try? PrayerUtils.getPrayerTimes(for: $0, coordinates: coords, params: params).fajr }
            let w = PrayerUtils.createWindowsFromTimes(times, on: day, nextFajr: nextFajr)
            for name in ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"] {
                if let (a, b, _) = w[name] { all.append(Window(name: name, start: a, end: b)) }
            }
        }
        return all.sorted { $0.start < $1.start }
    }

    /// The prayer day's five.
    static func today(_ now: Date = Date()) -> [Window] {
        // By the prayer day's key, not the calendar date: an Isha after midnight (high latitudes in summer) belongs to the
        // day before (review).
        let key = PrayerDay.key(for: now)
        return Array(around(now).filter { PrayerDay.key(forRow: $0.name, startingAt: $0.start) == key }.prefix(5))
    }

    static func pick(_ which: PrayerPick, now: Date = Date()) -> Window? {
        let all = around(now)
        let current = all.last { $0.start <= now && now < $0.end }
        switch which {
        case .current: return current
        case .next: return all.first { $0.start > now }
        case .previous:
            if let current, let i = all.firstIndex(where: { $0.start == current.start }), i > 0 { return all[i - 1] }
            return all.last { $0.end <= now }
        case .fajr, .dhuhr, .asr, .maghrib, .isha:
            // Today's while it isn't over (on now counts), else the next one.
            return all.first { $0.name == which.prayerName && now < $0.end }
        case .relevant:
            // As the Salah circle (PrayerViewModel.relevantPrayer): on and unmarked, else the next unmarked today, else
            // a missed one today; all five done → tomorrow's Fajr.
            let done = SharedStore.completedPrayerNamesToday()
            let day = today(now)
            return day.first { !done.contains($0.name) && $0.start <= now && now < $0.end }
                ?? day.first { !done.contains($0.name) && now < $0.start }
                ?? day.first { !done.contains($0.name) && $0.end <= now }
                ?? all.first { $0.start > now && $0.name == "Fajr" }
        }
    }

    /// "1 hour 5 minutes".
    static func span(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "under a minute" }   // as the cards (review: Siri said "1 minute", the card "under a minute")
        let m = Int((seconds / 60).rounded(.down))   // down, as the cards say it (review: Siri said a minute more)
        let h = m / 60, r = m % 60
        let hours = h == 0 ? "" : h == 1 ? "1 hour" : "\(h) hours"
        let mins = r == 0 ? "" : r == 1 ? "1 minute" : "\(r) minutes"
        return [hours, mins].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// "Get Prayer Time": the relevant, current, previous or next prayer — its start, and what it is.
struct GetPrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Prayer Time"
    static var description = IntentDescription(
        "The relevant, current, previous or next prayer — or Fajr, Dhuhr, Asr, Maghrib or Isha — and its start time, or a time some minutes before or after it (Show More). Relevant is what shukr's circle shows: the prayer to pray now, the next one, or one you missed.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "fajr", "dhuhr", "asr", "maghrib", "isha", "offset", "next prayer"],
        resultValueName: "Prayer Time")

    @Parameter(title: "Which prayer", description: "Relevant, current, previous, next, or one of the five.", default: .relevant) var which: PrayerPick
    /// Under Show More (was its own "Offset" action): a time some minutes before or after the prayer starts.
    @Parameter(title: "Minutes", description: "Minutes before or after the prayer starts (0 = its own time).", default: 0,
               inclusiveRange: (0, 600)) var minutes: Int
    @Parameter(title: "Before or after", description: "Before or after the prayer starts.", default: .before) var side: ReferencePoint

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$which) prayer time") {
            \.$minutes
            \.$side
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        ShortcutTopUp.request()
        let now = Date()
        let shift = TimeInterval(minutes * 60) * (side == .before ? -1 : 1)
        if minutes > 0 {
            // A time some minutes before / after the prayer: the next one that's still ahead (as the Offset action did —
            // "15 min before Maghrib" asked during Maghrib is tomorrow's), else the picked one as it is.
            let all = PrayerWindows.around(now)
            let w = which.prayerName.flatMap { name in all.first { $0.name == name && $0.start.addingTimeInterval(shift) > now } }
                ?? PrayerWindows.pick(which) ?? PrayerWindows.pick(.next)
            guard let w else { throw PrayerTimeUnavailable() }
            let t = w.start.addingTimeInterval(shift)
            return .result(value: t, dialog: "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(side == .before ? "before" : "after") \(w.name) is \(shortTimePM(t))\(Self.day(t)) (\(w.name) at \(shortTimePM(w.start))).")
        }
        guard let w = PrayerWindows.pick(which) else {
            if which == .current, let n = PrayerWindows.pick(.next) {
                return .result(value: n.start, dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).")
            }
            throw PrayerTimeUnavailable()
        }
        let on = w.start <= now && now < w.end
        let line: IntentDialog = switch which {
        case .current: "\(w.name) is on until \(shortTimePM(w.end))."   // one wording for "on" everywhere (review)
        case .previous: "The previous prayer was \(w.name), at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .next: "The next prayer is \(w.name), at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .fajr, .dhuhr, .asr, .maghrib, .isha:
            on ? "\(w.name) is on until \(shortTimePM(w.end))." : "\(w.name) is at \(shortTimePM(w.start))\(Self.day(w.start))."
        case .relevant:
            IntentDialog(stringLiteral: Self.prayedFirst(now: now, moving: w)
                + (on ? "\(w.name) is on until \(shortTimePM(w.end))."
                   : w.end <= now ? "\(w.name) isn’t marked yet. Its time ended at \(shortTimePM(w.end))."
                   : "\(w.name) is next, at \(shortTimePM(w.start))\(Self.day(w.start))."))
        }
        return .result(value: w.start, dialog: line)
    }

    /// Relevant moved past a prayer that's on but already prayed: say so first (owner: "You've prayed Asr. Maghrib is
    /// next, at 6:48 PM."); all five prayed: "You've prayed all five today."
    static func prayedFirst(now: Date, moving w: PrayerWindows.Window) -> String {
        let done = SharedStore.completedPrayerNamesToday()
        if PrayerWindows.today(now).allSatisfy({ done.contains($0.name) }) { return "You’ve prayed all five today. " }
        guard let current = PrayerWindows.pick(.current, now: now), current.start != w.start, done.contains(current.name)
        else { return "" }
        return "You’ve prayed \(current.name). "
    }

    /// " tomorrow" / " yesterday" when the prayer isn't on today's prayer day (Fajr tomorrow, Isha last night).
    static func day(_ start: Date, now: Date = Date()) -> String {
        // The calendar day, as people say it: after midnight this morning's Fajr is "next", not "tomorrow" (review).
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: now) { return "" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(start, inSameDayAs: t) { return " tomorrow" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(start, inSameDayAs: y) { return " yesterday" }
        return ""
    }
}

/// "Get Today's Prayer Times": the five as a list — earlier / now / still to come.
struct GetTodaysPrayerTimesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today’s Prayer Times"
    /// Replaced by TodaysTimesNowIntent (iOS 26); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "Today's five prayer times with your method and madhab, as a list: what's passed (✓ when you marked it), what's on now, what's to come.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "schedule", "timetable", "today"], resultValueName: "Prayer Times")

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let now = Date()
        let five = PrayerWindows.today(now)
        guard !five.isEmpty else { throw PrayerTimeUnavailable() }
        let rows = TodaysTimesSnippet.rows(now: now)
        let spoken = TodaysTimesSnippet.spoken(now: now)
        let lines = five.map { "\($0.name) \(shortTimePM($0.start))" }   // the output, as before: automations keep working
        let scheme = await ShortcutLook.scheme()
        return .result(value: lines, dialog: IntentDialog(stringLiteral: spoken),
                       view: TodaysTimesSnippet(rows: rows, now: now).environment(\.colorScheme, scheme))
    }
}

/// Today's Times as a list (owner: "a real list … three headings, one row per prayer with its symbol, name and time, the
/// current one highlighted, in shukr's look"): Earlier (dimmed, ✓ when marked) · Now (a soft sage card, "until …") ·
/// Still to come. Siri and Shortcuts show it under the spoken line; it follows the phone's light or dark.
struct TodaysTimesSnippet: View {
    enum When: Int { case earlier, now, coming }
    struct Row: Identifiable {
        let name: String, start: Date, end: Date, marked: Bool, when: When
        var id: String { name }
    }
    let rows: [Row]
    /// iOS 26: the current prayer's tick slot is a circle that marks it.
    var markable = false
    /// The moment it was asked (its "… left").
    var now = Date()
    /// shukr's sage (Color.sage lives in the app target only; this file is the widget's too).
    static let sage = Color(red: 0.40, green: 0.64, blue: 0.50)

    var body: some View {
        // One plain list (owner: the Earlier / Now / Still to come headers were clutter); the marks and the current
        // row's sage fill say where the day is.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row($0) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    /// As the Live Activity card says it (review: three spellings of the same thing): "2 hr, 29 min left",
    /// "59 minutes left", "under a minute left".
    static func left(until end: Date, now: Date = Date()) -> String {
        let m = Int((end.timeIntervalSince(now) / 60).rounded(.down))
        if m < 1 { return "under a minute left" }
        let h = m / 60, r = m % 60
        return h == 0 ? "\(r) \(r == 1 ? "minute" : "minutes") left" : r == 0 ? "\(h) hr left" : "\(h) hr, \(r) min left"
    }

    /// Today's five as rows (one source for every card and the preview).
    static func rows(now: Date = Date()) -> [Row] {
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.today(now).map { w in
            Row(name: w.name, start: w.start, end: w.end, marked: done.contains(w.name),
                when: w.end <= now ? .earlier : w.start <= now ? .now : .coming)
        }
    }

    @ViewBuilder private func mark(_ r: Row) -> some View {
        if r.marked && markable {
            // Undo, never in one tap (owner): the ✓ opens shukr, which asks "Unmark Asr?" — as I Prayed's Undo.
            Button(intent: AskUnmarkPrayerIntent(prayerName: r.name, prayerStart: r.start)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Self.sage)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.name), prayed. Unmark in shukr")
        } else if r.marked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Self.sage)
                .accessibilityLabel("\(r.name), prayed")
        } else if r.when == .coming {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .padding(2)
                .accessibilityLabel("\(r.name), still to come")
        } else if r.when == .now && markable {
            Button(intent: MarkPrayerFromCardIntent(.init(name: r.name, start: r.start, end: r.end))) {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Self.sage)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(r.name) as prayed")
        } else {
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(r.when == .now ? Self.sage : Color.secondary)
                .accessibilityLabel(r.when == .now ? "\(r.name), now" : "\(r.name), not marked")
        }
    }

    /// The line said with the list: what's on, else what's next, else Fajr.
    static func spoken(now: Date = Date()) -> String {
        let five = PrayerWindows.today(now)
        if let on = five.first(where: { $0.start <= now && now < $0.end }) { return "\(on.name) is on until \(shortTimePM(on.end))." }
        if let next = five.first(where: { $0.start > now }) { return "\(noPrayerOnLine) \(next.name) starts at \(shortTimePM(next.start))." }
        if let fajr = PrayerWindows.pick(.fajr, now: now) { return "That’s all five for today. Fajr is at \(shortTimePM(fajr.start))." }
        return "That’s all five for today."
    }

    private func row(_ r: Row) -> some View {
        let now = r.when == .now
        return HStack(spacing: 12) {
            // The app's own marks in place of the prayer symbols (owner): ✓ = prayed, a circle = on now (on iOS 26 the
            // tap that marks it) or missed, dashed = still to come. One column, so the time keeps its room.
            mark(r)
                .frame(width: 26, height: 26)
            Text(r.name)
                .font(.system(.body, design: .rounded, weight: now ? .semibold : .regular))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(shortTimePM(r.start))
                    .font(.system(.body, design: .rounded, weight: now ? .semibold : .regular))
                    .monospacedDigit()
                if now {
                    Text(Self.left(until: r.end, now: self.now))   // time left, as the Live Activity says it (owner: not "until")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, now ? 9 : 6)
        .background {
            if now { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.sage.opacity(0.16)) }
        }
        .opacity(r.when == .earlier ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The look Shortcuts / Siri cards are drawn in: the phone's light or dark. Run in the background the app's views came
/// out light, unreadable on a dark sheet (his phone).
enum ShortcutLook {
    static func scheme() async -> ColorScheme {
        await MainActor.run { UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light }
    }
}

/// Shortcuts that only answer top the reminders up too (owner: "make them top up too … many people will use these as
/// recipes in bigger chained shortcuts"): the answer returns at once, the top-up runs after it in the app (notifications,
/// then Fajr alarms, then the Live Activity plan), and at most every 3 h — a chain asking ten times pays for it once.
enum ShortcutTopUp {
    nonisolated(unsafe) static var run: (() -> Void)?
    static let key = "shortcutTopUpAt"
    static let every: TimeInterval = 3 * 3600
    static func request() {
        guard run != nil, let g = UserDefaults(suiteName: SharedStore.appGroup) else { return }   // the widget's process: no hook
        let now = Date().timeIntervalSince1970
        guard now - g.double(forKey: key) > every else { return }
        g.set(now, forKey: key)
        Task { @MainActor in run?() }   // not awaited: the shortcut never waits on it
    }
}

/// Cards drawn with app-only views (the app sets them at launch; the widget never runs these actions).
enum ShortcutCards {
    /// Setup's alarm picture for Get Fajr Alarm Time; true = the alarm is off (frosted).
    nonisolated(unsafe) static var fajrAlarm: ((Bool, Date) -> AnyView)?
}

/// Time Left and I Prayed: the prayer's own Live Activity card (owner: "reuse the live activity view") — running, or
/// once marked its ✓ in the grade's colour; no 15 s bar. On iOS 26 its `action` puts a ✓ or an Undo in the button's place.
struct PrayerCardSnippet: View {
    let state: PrayerWindowAttributes.ContentState
    /// iOS 26's interactive cards: a ✓ that marks it, or an Undo that asks in shukr (never undone here — owner).
    enum Action { case none, mark, undo }
    var action: Action = .none
    var body: some View {
        var t = LATuning.current
        t.barThickness = 0
        return LALockCardBody(state: state, n: 0, ended: false, t: t, liveButtons: true)
            // One line for VoiceOver, before the buttons go on, so ✓ / Undo stay reachable (review).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .overlay(alignment: .trailing) {
                switch action {
                case .none: EmptyView()
                case .mark:
                    LARoundButton(intent: MarkPrayerFromCardIntent(.init(name: state.label, start: state.start, end: state.end)),
                                  symbol: "checkmark", size: t.buttonSize,
                                  symbolSize: t.buttonSymbolSize, t: t)
                        .padding(.trailing, t.cardPaddingSides)
                case .undo:
                    Button(intent: AskUnmarkPrayerIntent(prayerName: state.label, prayerStart: state.start)) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, t.cardPaddingSides)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)
    }
    /// One line for VoiceOver (the card stacks timer layers that would each be read).
    private var spoken: String {
        if let m = state.markedAt {
            let grade = PrayerScoring.grade(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: m)).rawValue
            return "\(state.label), prayed \(shortTimePM(m)), \(grade)"
        }
        return "\(state.label), \(TodaysTimesSnippet.left(until: state.end)), ends \(shortTimePM(state.end))"
    }
}

private extension String {
    func prefixed(_ p: String) -> String { p + self }
}

/// No prayer on (Sunrise to Dhuhr): the next one, its symbol, when it starts.
struct NextPrayerSnippet: View {
    let name: String
    let start: Date
    var now = Date()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: prayerIcon(for: name).replacingOccurrences(of: ".fill", with: ""))
                .font(.system(size: 22))
                .foregroundStyle(TodaysTimesSnippet.sage)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(.title3, design: .rounded, weight: .medium))
                Text(TodaysTimesSnippet.left(until: start, now: now).replacingOccurrences(of: " left", with: "").replacingOccurrences(of: "under a minute", with: "a moment").prefixed("starts in "))
                    .lineLimit(1)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortTimePM(start)).font(.system(.title3, design: .rounded)).monospacedDigit()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LASoft.surface(LATuning.current, scheme)))
        .padding(10)   // as the prayer's card: its surface, radius and margin (Time Left kept its look between Sunrise and Dhuhr)
        .accessibilityElement(children: .combine)
    }
}

/// The same words wherever no prayer's time is on (Sunrise to Dhuhr).
let noPrayerOnLine = "No prayer is on right now."

struct PrayerTimeUnavailable: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Open shukr once so it knows where you are." }
}

// MARK: - The Fajr alarm on the Lock Screen

/// The Lock Screen's Fajr (owner, 2026-10-15): once Isha is done the Prayers widget shows when the Fajr alarm rings, not
/// when Fajr starts — by default, whenever shukr rings it (iOS 26.1+ AlarmKit, the alarm on and allowed, not excused);
/// otherwise Fajr's start, as before. The alarm rule from Settings → Reminders → Fajr Alarm, as the scheduler reads it.
enum FajrAlarmShown {
    /// shukr rings the Fajr alarm: iOS 26.1+, on, allowed, not excused (Explore only talks about it then — owner).
    static var isOn: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoLockAlarm") { return true }   // `-demoLockAlarm YES` (in the app)
        #endif
        guard #available(iOS 26.1, *) else { return false }
        guard let g = UserDefaults(suiteName: SharedStore.appGroup),
              g.bool(forKey: "alarmEnabled"), g.bool(forKey: "alarmKitActive"), !Excused.isActive else { return false }
        #if canImport(AlarmKit)
        guard AlarmManager.shared.authorizationState == .authorized else { return false }
        #endif
        return true
    }

    static func time(fajrStart: Date, sunrise: Date) -> Date? {
        guard isOn, let g = UserDefaults(suiteName: SharedStore.appGroup) else { return nil }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoLockAlarm") { return fajrStart.addingTimeInterval(-20 * 60) }
        #endif
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
        let raw = g.integer(forKey: "alarmOffsetMinutes")
        let minutes = isFajr ? raw : max(10, raw)   // FajrAlarmRule.clamp: before the end of Fajr, at least 10
        return (isFajr ? fajrStart : sunrise).addingTimeInterval(TimeInterval(minutes * 60) * (before ? -1 : 1))
    }
}

// MARK: - The Fajr alarm's time, for any shortcut

/// "Get Fajr Alarm Time" (owner: usable in any shortcut — lights on at that time): the next time your Fajr alarm
/// rule gives (Settings → Reminders → Fajr Alarm), whether or not the alarm is on. Never stops a shortcut.
struct FajrAlarmTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Fajr Alarm Time"   // was "Autopilot …" (owner: verb first, no jargon)
    static var description = IntentDescription("The next time your Fajr alarm rule gives — e.g. 20 minutes before Fajr starts — from Settings → Reminders → Fajr Alarm, whether or not the alarm is on. Use it in any shortcut: lights, music, a Focus. With the alarm on, it's also what shukr's Lock Screen widget shows after Isha.",
                                               categoryName: "Fajr Alarm", searchKeywords: ["wake", "alarm", "fajr", "morning"],
                                               resultValueName: "Fajr Alarm Time")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog & ShowsSnippetView {
        let (time, on) = try Self.next()
        // Setup's alarm picture (the app's view, through ShortcutCards), frosted when the alarm is off.
        let scheme = await ShortcutLook.scheme()
        let view = await MainActor.run { ShortcutCards.fajrAlarm?(!on, time) } ?? AnyView(EmptyView())
        return .result(value: time, dialog: IntentDialog(stringLiteral: Self.spoken(time, on: on)),
                       view: AnyView(view.environment(\.colorScheme, scheme)))
    }
    static func spoken(_ time: Date, on: Bool) -> String {
        on ? "Your Fajr alarm is at \(shortTimePM(time))." : "Your Fajr alarm is off. When it’s on, it rings at \(shortTimePM(time))."
    }
    /// When the rule next rings, and whether the alarm is on.
    static func next() throws -> (time: Date, on: Bool) {
        ShortcutTopUp.request()
        // The rule on today's Fajr (or sunrise); tomorrow's only once that has passed (review: worked out from the
        // alarm's own time, an offset across midnight or an "after sunrise" rule landed on the wrong day).
        guard let g = UserDefaults(suiteName: SharedStore.appGroup), let coords = try? PrayerUtils.getUserCoordinates()
        else { throw PrayerTimeUnavailable() }
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let shift = TimeInterval(g.integer(forKey: "alarmOffsetMinutes") * 60) * ((g.object(forKey: "alarmIsBefore") as? Bool ?? true) ? -1 : 1)
        let params = PrayerUtils.getCalculationParameters()
        let now = Date()
        func rule(_ day: Date) -> Date? {
            (try? PrayerUtils.getPrayerTimes(for: day, coordinates: coords, params: params))
                .map { PrayerUtils.getTime(for: isFajr ? .fajr : .sunrise, in: $0).addingTimeInterval(shift) }
        }
        guard let today = rule(now) else { throw PrayerTimeUnavailable() }
        let time = today > now ? today : (Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap(rule) ?? today)
        FajrAlarmLog.add("Shortcut asked the rule's time: \(FajrAlarmLog.day(time))")
        // Say when it's off: the time is the rule's either way (an automation can still use it).
        // Excused (Excused.swift): it won't ring, so it reads as off.
        let on = UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: "alarmEnabled") == true && !Excused.isActive
        return (time, on)
    }
}

/// "Should a Shortcut Set the Fajr Alarm?": true only when the Daily alarm is on and shukr isn't setting it itself
/// (iOS 26.1+). shukr's Clock-alarm Shortcut checks this first, so there's never a second alarm.
struct FajrAlarmShortcutCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Fajr Alarm Shortcut"   // verb first (was a question)
    static var description = IntentDescription("Yes when your Fajr alarm is on and shukr isn’t already setting it itself. Check it before making a Clock alarm, so you never get two.",
                                               categoryName: "Fajr Alarm", searchKeywords: ["alarm", "clock", "fajr"], resultValueName: "Should Set")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let g = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let on = g?.bool(forKey: "alarmEnabled") == true
        var shukrSetsIt = g?.bool(forKey: "alarmKitActive") == true
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *), AlarmManager.shared.authorizationState == .denied { shukrSetsIt = false }
        #endif
        let excused = Excused.isActive   // no alarm while excused (Excused.swift)
        let answer = on && !shukrSetsIt && !excused
        FajrAlarmLog.add("Shortcut asked whether to set the alarm: \(answer) (switch \(on), shukr sets it \(shukrSetsIt)\(excused ? ", excused" : ""))")
        return .result(value: answer)
    }
}

// MARK: - Siri and Shortcuts: asked in plain words (owner: "natural questions")

/// What Siri's "the prayer that's on" means: the window you're in, prayed or not (owner: "I prayed just says no prayer
/// is on. not true. its maghrib"). Between Sunrise and Dhuhr none is.
enum RelevantPrayer {
    struct Info { let name: String; let start: Date; let end: Date; let isOn: Bool }

    static func now(_ now: Date = Date()) -> Info? {
        if let c = PrayerWindows.pick(.current, now: now) { return Info(name: c.name, start: c.start, end: c.end, isOn: true) }
        if let n = PrayerWindows.pick(.next, now: now) { return Info(name: n.name, start: n.start, end: n.end, isOn: false) }
        return nil
    }
}

/// "What's the next prayer?" — the next to start, answered at once. Gives its start time to the next action.
struct NextPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Prayer"
    /// Folded into "Get Prayer Time" (Relevant / Next) (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("The next prayer to start and how long until it does. Passes its start time on.",
                                               categoryName: "Prayer Times")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let now = Date()
        var line = "\(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))), at \(shortTimePM(n.start))."
        if let c = PrayerWindows.pick(.current) { line = "\(c.name) is on until \(shortTimePM(c.end)). " + line }
        return .result(value: n.start, dialog: IntentDialog(stringLiteral: line))
    }
}

/// "How long is left?" — time left in the prayer you're in, marked or not; between Sunrise and Dhuhr, time until Dhuhr.
/// Gives the minutes to the next action.
struct PrayerTimeLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Left"
    /// Replaced by TimeLeftNowIntent (iOS 26, a card with a ✓ — decision shortcut-buttons-ios26 A); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription(
        "Minutes left in the prayer whose time it is now — whether or not you've prayed it. Between Sunrise and Dhuhr, minutes until Dhuhr. Passes the minutes on.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "how long", "remaining", "ends"], resultValueName: "Minutes Left")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let now = Date()
        let scheme = await ShortcutLook.scheme()
        if let c = PrayerWindows.pick(.current) {
            let mins = max(1, Int((c.end.timeIntervalSince(now) / 60).rounded(.down)))
            // The card as it runs on the Lock Screen: the ring filling in its colour, the time left, when it ends.
            let state = PrayerWindowAttributes.ContentState(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                            dark: scheme == .dark)
            return .result(value: mins, dialog: "\(PrayerWindows.span(c.end.timeIntervalSince(now))) left for \(c.name). It ends at \(shortTimePM(c.end)).",
                           view: AnyView(PrayerCardSnippet(state: state).environment(\.colorScheme, scheme)))
        }
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let mins = max(1, Int((n.start.timeIntervalSince(now) / 60).rounded(.down)))
        return .result(value: mins, dialog: "\(noPrayerOnLine) \(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))).",
                       view: AnyView(NextPrayerSnippet(name: n.name, start: n.start, now: now).environment(\.colorScheme, scheme)))
    }
}

/// "I prayed" — marks the prayer whose time it is, scored now, without opening shukr; tells you if it was already marked.
/// Gives the grade to the next action.
struct MarkCurrentPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    /// Replaced by MarkPrayedNowIntent (iOS 26, with Undo); kept for saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Marks the prayer whose time it is now as prayed, scored like in shukr. Passes the grade on (Perfect, On time, Late, Qaza).",
                                               categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "prayed", "mark", "done"],
                                               resultValueName: "Grade")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        ShortcutTopUp.request()
        let scheme = await ShortcutLook.scheme()
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) {
                return .result(value: "", dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).",
                               view: AnyView(NextPrayerSnippet(name: n.name, start: n.start).environment(\.colorScheme, scheme)))
            }
            throw PrayerTimeUnavailable()
        }
        /// The prayer's card in its marked look: the ✓ in its grade's colour, "Prayed 4:31 PM", the grade and score.
        func card(_ at: Date) -> AnyView {
            AnyView(PrayerCardSnippet(state: .init(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                   markedAt: at, dark: scheme == .dark))
                .environment(\.colorScheme, scheme))
        }
        if let at = SharedStore.markedTime(of: c.name, start: c.start) {
            return .result(value: PrayerMarkNow.grade(c, at: at), dialog: "\(c.name) is already marked as prayed.", view: card(at))
        }
        let now = Date()
        guard await PrayerMarkNow.mark(c) else { throw PrayerTimeUnavailable() }
        let at = SharedStore.markedTime(of: c.name, start: c.start) ?? now
        let grade = PrayerMarkNow.grade(c, at: at)   // graded at the stored time, as the iOS 26 one
        return .result(value: grade, dialog: "\(c.name) marked as prayed. \(grade).", view: card(at))
    }
}

struct ZikrTaskSnapshot: Identifiable {
    let id: String
    /// The task's title: its own name ("After Fajr"), else the mantra.
    let name: String
    /// The mantra, when `name` is the task's own name.
    var mantra: String? = nil
    let isCountMode: Bool
    let goal: Int
    let count: Int
    let minutes: Int
    let done: Bool
    /// Roughly how long what's left takes at your pace (nil: no history yet).
    var secondsLeft: TimeInterval? = nil
    /// The row's estimate: time for a count goal, counts for a timed one (`TaskModel.estimateNote`).
    var note: String? = nil

    var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(isCountMode ? count : minutes) / Double(goal), 1)
    }
    var valueText: String { isCountMode ? "\(count)" : "\(minutes)m" }
    var progressText: String { isCountMode ? "\(count)/\(goal)" : "\(minutes)/\(goal) min" }
}

extension ZikrTaskSnapshot {
    /// Today's tasks (the prayer day's sessions), what's left first, done ones at the end — like the Zikr page; nil
    /// while the shared store isn't there yet. The Zikr widget and the Zikr Tasks shortcut.
    static func today() -> [ZikrTaskSnapshot]? {
        guard let container = SharedStore.widgetContainer else { return nil }
        let context = ModelContext(container)
        // Paused goals are left out (TaskModel.pausedAt, decision zikr-pause A).
        let tasks = ((try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []).filter { $0.pausedAt == nil }
        let dayStart = PrayerDay.sessionDayStart()
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(
            predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
        let snaps = tasks.map { task -> ZikrTaskSnapshot in
            let p = task.progress(in: sessions)
            return ZikrTaskSnapshot(id: task.id.uuidString, name: task.title, mantra: task.mantraLine,
                                    isCountMode: task.isCountMode, goal: task.goal,
                                    count: p.count, minutes: Int(p.seconds / 60),
                                    done: task.isCompleted(with: p),
                                    secondsLeft: task.secondsLeft(p),
                                    note: task.estimateNote(p))
        }
        return snaps.filter { !$0.done } + snaps.filter(\.done)
    }
}

// MARK: - Zikr Tasks (Shortcuts / Siri; owner 2026-10-13: "here are your tasks, and then you click on one to start that one")

/// A task row in the Zikr Tasks card: shukr opens and starts that task's session (today's count carried on).
struct StartZikrTaskIntent: AppIntent {
    static let flag = "shortcutZikrStart", idKey = "shortcutZikrStartID"
    static var title: LocalizedStringResource = "Start Zikr Task"
    static var isDiscoverable: Bool = false   // the card's rows
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Task") var taskID: String
    init() {}
    init(taskID: String) { self.taskID = taskID }
    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: SharedStore.appGroup)
        store?.set(taskID, forKey: Self.idKey)
        store?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// Today's zikr tasks: to do (a tap starts one), then done.
struct ZikrTasksSnippet: View {
    let tasks: [ZikrTaskSnapshot]
    private static let sage = TodaysTimesSnippet.sage
    private static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if tasks.isEmpty {
                Button(intent: OpenTasbeehIntent()) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle").font(.system(size: 20, weight: .light)).foregroundStyle(Self.sage)
                        Text("Add a task on the Zikr page").font(.system(.body, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            let todo = tasks.filter { !$0.done }, done = tasks.filter(\.done)
            let todoShown = Array(todo.prefix(Self.shown))
            let doneShown = Array(done.prefix(max(0, Self.shown - todoShown.count)))
            if !todoShown.isEmpty { section("To do", todoShown) }
            if !doneShown.isEmpty { section("Done today", doneShown) }
            let more = tasks.count - todoShown.count - doneShown.count
            if more > 0 {
                Text("\(more) more in shukr")
                    .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).padding(.leading, 10)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    private func section(_ title: String, _ rows: [ZikrTaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            ForEach(rows) { t in
                if t.done { row(t) } else {
                    Button(intent: StartZikrTaskIntent(taskID: t.id)) { row(t) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start \(t.name)")
                }
            }
        }
    }

    private func row(_ t: ZikrTaskSnapshot) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: t.done ? 1 : t.fraction)
                    .stroke(Self.sage, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if t.done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Self.sage)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(t.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(detail(t))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !t.done {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.sage)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Self.sage.opacity(0.16)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// "40 of 100 · ~4 min" / "12 of 20 min" / "Goal 100" / "100 · done".
    private func detail(_ t: ZikrTaskSnapshot) -> String {
        if t.done { return t.isCountMode ? "\(t.count) · done" : "\(t.minutes) min · done" }
        let base = t.isCountMode ? "\(t.count) of \(t.goal)" : "\(t.minutes) of \(t.goal) min"
        if t.count == 0 && t.minutes == 0 {
            return t.isCountMode ? "Goal \(t.goal)" + (t.secondsLeft.map { " · " + zikrEstimateString($0) } ?? "")
                                 : "Goal \(t.goal) min"
        }
        guard t.isCountMode, let s = t.secondsLeft, s > 0 else { return base }
        return base + " · " + zikrEstimateString(s)
    }

    /// The line said with the card.
    static func spoken(_ tasks: [ZikrTaskSnapshot]) -> String {
        if tasks.isEmpty { return "You have no zikr tasks yet." }
        let left = tasks.filter { !$0.done }
        if left.isEmpty { return tasks.count == 1 ? "Your zikr task is done for today." : "All \(tasks.count) zikr tasks are done for today." }
        let lead = tasks.count == 1 ? "Your zikr task is still to do today"
            : left.count == tasks.count ? "\(tasks.count) zikr tasks to do today"
            : "\(left.count) of \(tasks.count) zikr tasks left today"
        let known = left.compactMap(\.secondsLeft)
        guard !known.isEmpty else { return lead + "." }
        return lead + ", about " + zikrEstimateString(known.reduce(0, +)).replacingOccurrences(of: "~", with: "") + "."
    }
}

/// The card, drawn again when shown.
@available(iOS 26.0, *)
struct ZikrTasksCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Zikr Tasks Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        return .result(view: AnyView(ZikrTasksSnippet(tasks: ZikrTaskSnapshot.today() ?? []).environment(\.colorScheme, scheme)))
    }
}

/// "Get Zikr Tasks": today's tasks in a card; a tap on one starts it in shukr.
@available(iOS 26.0, *)
struct ZikrTasksNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Zikr Tasks"
    static var description = IntentDescription(
        "Today's zikr tasks and how far along each one is. Tap a task to start it in shukr.",
        categoryName: "Zikr", searchKeywords: ["zikr", "dhikr", "tasbeeh", "tasks", "to do"], resultValueName: "Zikr Tasks")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<[String]> {
        guard let tasks = ZikrTaskSnapshot.today() else { throw PrayerTimeUnavailable() }
        return .init(value: tasks.filter { !$0.done }.map(\.name),
                     dialog: IntentDialog(stringLiteral: ZikrTasksSnippet.spoken(tasks)),
                     card: ZikrTasksCardIntent())
    }
}


// MARK: - Control Center (owner, 2026-10-13)

/// Today's list in shukr: the Salah page with the list up (the Prayer control — a control can't show a card, Apple
/// forum 760793 — so it opens the list, which has every prayer, the time left and marking).
struct OpenPrayerListIntent: AppIntent {
    static let flag = "widgetPrayerList"
    static var title: LocalizedStringResource = "Open Today’s Prayers"
    static var isDiscoverable: Bool = false   // the control's; Shortcuts has Open shukr → Salah
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// The I Prayed control: marks the prayer whose time it is (or today's late one) without opening shukr, says so in a line.
/// Already marked: never unmarked here (owner: no easy undo) — shukr's list does that, and asks.
struct MarkPrayerFromControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    /// iOS 26: it can bring shukr forward when she's excused (owner: ask, never a silent no).
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        defer { ControlCenter.shared.reloadAllControls() }
        if Excused.isActive {
            if #available(iOS 26.0, *) {
                try await continueInForeground(alwaysConfirm: false)
                ExcusedResume.ask()
                return .result(dialog: "")
            }
            return .result(dialog: "Prayers are paused. Open shukr to turn them back on.")
        }
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) { return .result(dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).") }
            throw PrayerTimeUnavailable()
        }
        if SharedStore.markedTime(of: c.name, start: c.start) != nil {
            return .result(dialog: "\(c.name) is already marked. Change it in shukr.")
        }
        guard await PrayerMarkNow.mark(c) else { throw PrayerTimeUnavailable() }
        let grade = PrayerMarkNow.grade(c, at: SharedStore.markedTime(of: c.name, start: c.start) ?? Date())
        return .result(dialog: "\(c.name) marked as prayed. \(grade).")
    }
}

/// The Fajr alarm switch (Control Center): the same `alarmEnabled` as Settings → Reminders → Fajr Alarm; re-planned in
/// the app (a LiveActivityIntent runs there).
struct SetFajrAlarmEnabledIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Fajr Alarm On or Off"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "On") var value: Bool
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(value, forKey: "alarmEnabled")
        await FajrAlarmHooks.replan?()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// The app's Fajr alarm planner, for the control (set at launch; the widget never runs it).
enum FajrAlarmHooks {
    nonisolated(unsafe) static var replan: (() async -> Void)?
}

// MARK: - iOS 26: cards with buttons (decision shortcut-buttons-ios26 A)

/// What a mark from Shortcuts marks: the prayer whose time it is, else today's last one still unmarked (a late Isha).
enum PrayerMarkNow {
    static func target(now: Date = Date()) -> PrayerWindows.Window? {
        // Excused: nothing to mark, and every answer stays neutral ("No prayer is on right now"), so a question asked
        // out loud never says why (owner).
        if Excused.isActive { return nil }
        if let c = PrayerWindows.pick(.current, now: now) { return c }
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.pick(.previous, now: now).flatMap { p in
            PrayerWindows.today(now).contains { $0.start == p.start } && !done.contains(p.name) ? p : nil }
    }
    static func mark(_ c: PrayerWindows.Window) async -> Bool {
        if Excused.covers(start: c.start, end: c.end) { return false }
        if let hook = PrayerWindowHooks.widgetMark { return await hook(c.name, c.start, c.end) }
        return SharedStore.markPrayerComplete(named: c.name, start: c.start, end: c.end)
    }
    static func grade(_ c: PrayerWindows.Window, at: Date) -> String {
        PrayerScoring.grade(for: PrayerScoring.score(start: c.start, end: c.end, markedAt: at)).rawValue
    }
    /// The prayer's card now: running (with a ✓), or marked (with an Undo when asked for).
    static func card(_ c: PrayerWindows.Window, undo: Bool, scheme: ColorScheme) -> AnyView {
        // Its own row, not today's names: a late Isha redrawn after Fajr still reads as marked (review).
        let marked = SharedStore.markedTime(of: c.name, start: c.start)
        let state = PrayerWindowAttributes.ContentState(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                        markedAt: marked, dark: scheme == .dark)
        // Excused (Excused.swift): no ✓ that would do nothing.
        let mark: PrayerCardSnippet.Action = Excused.covers(start: c.start, end: c.end) ? .none : .mark
        return AnyView(PrayerCardSnippet(state: state, action: marked == nil ? mark : undo ? .undo : .none)
            .environment(\.colorScheme, scheme))
    }
}

/// A card's ✓ (Time Left, Today's Times): marks the prayer the card shows (review: re-working it out at the tap, a card
/// showing Asr tapped after Maghrib began marked Maghrib); the card redraws itself after.
struct MarkPrayerFromCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer from a Card"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult {
        let w: PrayerWindows.Window? = if let name, let start, let end { .init(name: name, start: start, end: end) } else { PrayerMarkNow.target() }
        if let w, SharedStore.markedTime(of: w.name, start: w.start) == nil { _ = await PrayerMarkNow.mark(w) }
        return .result()
    }
}

/// The Time Left card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TimeLeftCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Time Left Card"
    static var isDiscoverable: Bool = false
    /// The prayer it was asked about (redrawn after its ✓ it stays that prayer, even once the next one has begun).
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        if let name, let start, let end {
            return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: false, scheme: scheme))
        }
        if let c = PrayerWindows.pick(.current) { return .result(view: PrayerMarkNow.card(c, undo: false, scheme: scheme)) }
        if let n = PrayerWindows.pick(.next) {
            return .result(view: AnyView(NextPrayerSnippet(name: n.name, start: n.start).environment(\.colorScheme, scheme)))
        }
        return .result(view: AnyView(EmptyView()))
    }
}

/// A Shortcuts answer: what's said, its card, and the value it passes on. Each action builds its own, and shukr's grouped
/// tiles (Ask shukr, ShukrAppShortcuts.swift) give the same one (iOS 27 hides an app's tiles outside a section).
@available(iOS 26.0, *)
struct ShortcutAnswer<Value> {
    let value: Value
    let dialog: IntentDialog
    let card: any SnippetIntent
}

/// "Get Time Left" on iOS 26: the same answer, its card with a ✓.
@available(iOS 26.0, *)
struct TimeLeftNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Left"
    static var description = IntentDescription(
        "Minutes left in the prayer whose time it is now — whether or not you've prayed it. Between Sunrise and Dhuhr, minutes until Dhuhr. Passes the minutes on; its card can mark the prayer.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "how long", "remaining", "ends"], resultValueName: "Minutes Left")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<Int> {
        ShortcutTopUp.request()
        let now = Date()
        if let c = PrayerWindows.pick(.current) {
            let mins = max(1, Int((c.end.timeIntervalSince(now) / 60).rounded(.down)))
            return .init(value: mins, dialog: "\(PrayerWindows.span(c.end.timeIntervalSince(now))) left for \(c.name). It ends at \(shortTimePM(c.end)).",
                         card: TimeLeftCardIntent(c))
        }
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let mins = max(1, Int((n.start.timeIntervalSince(now) / 60).rounded(.down)))
        return .init(value: mins, dialog: "\(noPrayerOnLine) \(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))).",
                     card: TimeLeftCardIntent())
    }
}

/// Today's Times card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TodaysTimesCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Today's Times Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let now = Date()
        return .result(view: AnyView(TodaysTimesSnippet(rows: TodaysTimesSnippet.rows(now: now), markable: !Excused.isActive, now: now)
            .environment(\.colorScheme, scheme)))
    }
}

/// "Get Today's Prayer Times" on iOS 26: the list, its current prayer markable.
@available(iOS 26.0, *)
struct TodaysTimesNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today’s Prayer Times"
    static var description = IntentDescription(
        "Today's five prayer times with your method and madhab, as a list: what's passed (✓ when you marked it), what's on now (tap to mark it), what's to come.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "schedule", "timetable", "today"], resultValueName: "Prayer Times")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<[String]> {
        ShortcutTopUp.request()
        let now = Date()
        let five = PrayerWindows.today(now)
        guard !five.isEmpty else { throw PrayerTimeUnavailable() }
        let spoken = TodaysTimesSnippet.spoken(now: now)
        return .init(value: five.map { "\($0.name) \(shortTimePM($0.start))" }, dialog: IntentDialog(stringLiteral: spoken),
                     card: TodaysTimesCardIntent())
    }
}

/// I Prayed's card: the marked prayer with an Undo that asks in shukr (owner: never an easy undo).
@available(iOS 26.0, *)
struct PrayedCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Prayed Card"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Prayer") var name: String
    @Parameter(title: "Start") var start: Date
    @Parameter(title: "End") var end: Date
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: true, scheme: scheme))
    }
}

/// "Mark Prayer as Prayed" on iOS 26: marks it, shows its card with Undo.
@available(iOS 26.0, *)
struct MarkPrayedNowIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    static var description = IntentDescription("Marks the prayer whose time it is now as prayed, scored like in shukr. Passes the grade on (Perfect, On time, Late, Qaza). Undo asks in shukr.",
                                               categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "prayed", "mark", "done"],
                                               resultValueName: "Grade")
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<String> {
        ShortcutTopUp.request()
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) {
                return .init(value: "", dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).", card: TimeLeftCardIntent())
            }
            throw PrayerTimeUnavailable()
        }
        if SharedStore.completedPrayerNamesToday().contains(c.name) {
            let at = SharedStore.markedTime(of: c.name, start: c.start) ?? Date()
            return .init(value: PrayerMarkNow.grade(c, at: at), dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
        }
        let now = Date()
        let marked = await PrayerMarkNow.mark(c)
        let at = SharedStore.markedTime(of: c.name, start: c.start) ?? now
        let grade = PrayerMarkNow.grade(c, at: at)
        guard marked else {   // review: it said "marked" even when nothing was
            if SharedStore.markedTime(of: c.name, start: c.start) != nil {
                return .init(value: grade, dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
            }
            throw PrayerTimeUnavailable()
        }
        return .init(value: grade, dialog: "\(c.name) marked as prayed. \(grade).", card: PrayedCardIntent(c))
    }
}

/// "Start Tasbih Fatimah" — shukr opens into the 33 · 33 · 34 session (as the post-salah pill does).
struct StartTasbihFatimahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasbih Fatimah"   // every action that opens shukr says "Open" (owner)
    static var description = IntentDescription("Opens shukr into Tasbih Fatimah: 33 · 33 · 34.", categoryName: "Open shukr",
                                               searchKeywords: ["tasbih", "tasbeeh", "zikr", "dhikr", "subhanallah"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "liveActivity.openTasbih")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens Memories (a control, a shortcut).
struct OpenMemoriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Moments"
    /// Folded into "Open shukr" → Memories; its control (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens your prayer photos in shukr.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetMemories")
        DeepLinkSignal.post()
        return .result()
    }
}

/// Opens the Salah page (the prayer control).
struct OpenSalahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Prayers"
    /// Folded into "Open shukr" → Salah (owner, 2026-10-12): hidden from the action list, still runs in saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr on today's prayers.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "alarmOpenSalah")
        DeepLinkSignal.post()
        return .result()
    }
}

/// The pages "Open shukr" goes to (owner: one tile, pick the page; the Control Center buttons stay separate). Each
/// sets the flag its own control / widget sets, so the app opens it the same way (PrayerTimesView).
enum ShukrPage: String, AppEnum, CaseIterable {
    case salah, qibla, zikr, dailyAyah, names, memories, tasbihFatimah
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static var caseDisplayRepresentations: [ShukrPage: DisplayRepresentation] = [
        .salah: DisplayRepresentation(title: "Salah", subtitle: "Today's prayers", image: .init(systemName: "sun.horizon"),
                                      synonyms: ["prayers", "prayer times", "salat", "namaz"]),
        .qibla: DisplayRepresentation(title: "Qibla", subtitle: "The qibla map", image: .init(systemName: "location.north.line"),
                                      synonyms: ["compass", "the qibla", "direction of Mecca"]),
        .zikr: DisplayRepresentation(title: "Zikr", subtitle: "Your zikr and tasks", image: .init(systemName: "hands.and.sparkles"),
                                     synonyms: ["dhikr", "tasbeeh", "tasbih", "azkar"]),
        .dailyAyah: DisplayRepresentation(title: "Daily Ayah", subtitle: "Today's ayah", image: .init(systemName: "book"),
                                          synonyms: ["ayah", "the ayah", "verse of the day", "Quran"]),
        .names: DisplayRepresentation(title: "99 Names", subtitle: "The names of Allah", image: .init(systemName: "moon.stars"),
                                      synonyms: ["names", "names of Allah", "Asma ul Husna"]),
        .memories: DisplayRepresentation(title: "Moments", subtitle: "Your prayer photos", image: .init(systemName: "photo.stack"),
                                         synonyms: ["photos", "prayer photos", "memories"]),   // its old name (owner renamed it Moments, 2026-10-15)
        // Its own tile until iOS 27 hid every tile outside a section (2026-10-14): a page here, so it stays on the page.
        .tasbihFatimah: DisplayRepresentation(title: "Tasbih Fatimah", subtitle: "33 · 33 · 34", image: .init(systemName: "circle.hexagonpath"),
                                              synonyms: ["Tasbih Fatimah", "tasbeeh Fatimah", "33 33 34"]),
    ]
    /// The app group flag its control / widget sets.
    var flag: String {
        switch self {
        case .salah: "alarmOpenSalah"
        case .qibla: "widgetCompass"
        case .zikr: "widgetTasbeeh"
        case .dailyAyah: "widgetDailyAyah"
        case .names: "widgetNames"
        case .memories: "widgetMemories"
        case .tasbihFatimah: "liveActivity.openTasbih"
        }
    }
}

/// Open shukr's pages as one collection under its tile (see PrayerPickRelativeOptions).
struct ShukrPageOptions: DynamicOptionsProvider {
    func results() async throws -> [ShukrPage] { ShukrPage.allCases }
}

/// "Open shukr": one tile for every page (owner, 2026-10-12) — "Open qibla in shukr", "Open moments in shukr".
struct OpenShukrIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shukr"
    static var description = IntentDescription("Opens shukr on the page you pick: Salah, Qibla, Zikr, Daily Ayah, 99 Names or Moments.",
                                               categoryName: "Open shukr", searchKeywords: ["open", "go to", "show", "qibla", "zikr", "ayah", "names", "moments", "memories"])
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Page", default: .salah) var page: ShukrPage
    static var parameterSummary: some ParameterSummary { Summary("Open shukr on \(\.$page)") }

    init() {}
    init(page: ShukrPage) { self.page = page }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: page.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

/// "Find Nearby Mosques" (owner: "a quick way to ask for nearby mosques and see a map with the pins and a list"): shukr
/// opens on the map with its mosques — the pins and the list in the sheet.
struct FindNearbyMosquesIntent: AppIntent {
    static let flag = "widgetMosques"
    static var title: LocalizedStringResource = "Open Nearby Mosques"   // it opens shukr, so it says Open (owner)
    /// Replaced on iOS 26 by Find Nearby Mosques' card (decision nearby-mosques-card A); still the card's "Open in shukr"
    /// and saved shortcuts.
    static var isDiscoverable: Bool = false
    static var description = IntentDescription("Opens shukr's map on the mosques near you: their pins, and the nearest in a list.",
                                               categoryName: "Open shukr", searchKeywords: ["masjid", "mosque", "near me", "find", "jumuah", "map"])
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: Self.flag)
        DeepLinkSignal.post()
        return .result()
    }
}

// (The App Shortcuts list lives in the app only: shukr/CursorSwift/ShukrAppShortcuts.swift.)


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
        // Each table in its own try, reading only the columns the file has (an older store lacked
        // ZSORTORDER; a newer one may have columns we don't know) — one odd table no longer sinks the
        // whole salvage (audit A2). What's missing from the fresh store is INSERTED, not only patched
        // onto rows that happen to exist. Photos / voice memos stay in the set-aside `_SUPPORT` folder
        // (Core Data's external-storage markers can't be re-linked from here; nothing is deleted).
        var parts: [String] = []
        var failures: [String] = []

        // Mantras: missing ones are added (name, text, notes, +N step, created, built-in id); existing
        // ones get text / notes only where the live row has none.
        var mantraByName: [String: MantraModel] = [:]
        var mantrasUpdated = 0, mantrasAdded = 0
        do {
            for m in try context.fetch(FetchDescriptor<MantraModel>()) { mantraByName[m.name.lowercased()] = m }
            let liveBuiltIns = Set(mantraByName.values.compactMap { $0.builtInID })
            let c = cols(db, "ZMANTRAMODEL")
            let want = ["ZNAME", "ZFULLTEXT", "ZNOTES", "ZQUICKADDSTEP", "ZCREATEDAT", "ZBUILTINID"].filter { c.contains($0) }
            if c.contains("ZNAME") {
                for r in try rows(db, "SELECT \(want.joined(separator: ", ")) FROM ZMANTRAMODEL") {
                    let name = str(r, "ZNAME")
                    guard !name.isEmpty else { continue }
                    let full = str(r, "ZFULLTEXT"), notes = str(r, "ZNOTES")
                    if let live = mantraByName[name.lowercased()] {
                        var changed = false
                        if live.fullText.isEmpty, !full.isEmpty { live.fullText = full; changed = true }
                        if live.notes.isEmpty, !notes.isEmpty { live.notes = notes; changed = true }
                        if changed { mantrasUpdated += 1 }
                        continue
                    }
                    let m = MantraModel(name: name, fullText: full, notes: notes)
                    if c.contains("ZQUICKADDSTEP") { m.quickAddStep = Int(int(r, "ZQUICKADDSTEP")) }
                    if let created = date(r, "ZCREATEDAT") { m.createdAt = created }
                    if let bid = r["ZBUILTINID"] as? String, !bid.isEmpty, !liveBuiltIns.contains(bid) { m.builtInID = bid }
                    context.insert(m)
                    mantraByName[name.lowercased()] = m
                    mantrasAdded += 1
                }
            }
            parts.append("mantras added=\(mantrasAdded) updated=\(mantrasUpdated)")
        } catch { failures.append("mantras: \(error)") }

        // Tasks missing by id (rare; created after the legacy snapshot).
        var taskByID: [UUID: TaskModel] = [:]
        var oldTaskPKToID: [Int64: UUID] = [:]
        var tasksAdded = 0
        do {
            for t in try context.fetch(FetchDescriptor<TaskModel>()) { taskByID[t.id] = t }
            let c = cols(db, "ZTASKMODEL")
            let want = ["Z_PK", "ZID", "ZMANTRANAME", "ZISCOUNTMODE", "ZGOAL", "ZCUSTOMNAME"].filter { c.contains($0) }
            let nextOrder = TaskModel.nextSortOrder(in: context)
            if c.contains("ZID") {
                for r in try rows(db, "SELECT \(want.joined(separator: ", ")) FROM ZTASKMODEL") {
                    guard let id = uuid(r, "ZID"), let pk = r["Z_PK"] as? Int64 else { continue }
                    oldTaskPKToID[pk] = id
                    if taskByID[id] != nil { continue }
                    let name = str(r, "ZMANTRANAME")
                    let task = TaskModel(mantra: mantraByName[name.lowercased()], isCountMode: int(r, "ZISCOUNTMODE") != 0,
                                         goal: Int(int(r, "ZGOAL")), mantraName: name, sortOrder: nextOrder + tasksAdded)
                    task.id = id
                    if let custom = r["ZCUSTOMNAME"] as? String, !custom.isEmpty { task.customName = custom }
                    context.insert(task)
                    taskByID[id] = task
                    tasksAdded += 1
                }
            }
            parts.append("tasks added=\(tasksAdded)")
        } catch { failures.append("tasks: \(error)") }

        // Sessions missing by id.
        var sessionsAdded = 0
        do {
            let sessionIDs = Set(try context.fetch(FetchDescriptor<SessionDataModel>()).map { $0.id })
            let c = cols(db, "ZSESSIONDATAMODEL")
            let want = ["ZID", "ZTITLE", "ZSESSIONMODE", "ZTARGETMIN", "ZTARGETCOUNT", "ZTOTALCOUNT", "ZSTARTTIME", "ZSECONDSPASSED",
                        "ZAVGTIMEPERCLICK", "ZTASBEEHRATE", "ZTIMEDURATIONSTRING", "ZTASK"].filter { c.contains($0) }
            if c.contains("ZID"), c.contains("ZSTARTTIME") {
                for r in try rows(db, "SELECT \(want.joined(separator: ", ")) FROM ZSESSIONDATAMODEL") {
                    guard let id = uuid(r, "ZID"), !sessionIDs.contains(id), let start = date(r, "ZSTARTTIME") else { continue }
                    let title = str(r, "ZTITLE")
                    let task = (r["ZTASK"] as? Int64).flatMap { oldTaskPKToID[$0] }.flatMap { taskByID[$0] }
                    let sess = SessionDataModel(
                        title: title, sessionMode: Int(int(r, "ZSESSIONMODE")), targetMin: Int(int(r, "ZTARGETMIN")),
                        targetCount: Int(int(r, "ZTARGETCOUNT")), totalCount: Int(int(r, "ZTOTALCOUNT")), startTime: start,
                        secondsPassed: dbl(r, "ZSECONDSPASSED") ?? 0, avgTimePerClick: dbl(r, "ZAVGTIMEPERCLICK") ?? 0,
                        tasbeehRate: str(r, "ZTASBEEHRATE"), task: task, mantra: mantraByName[title.lowercased()]
                    )
                    sess.id = id
                    if !str(r, "ZTIMEDURATIONSTRING").isEmpty { sess.timeDurationString = str(r, "ZTIMEDURATIONSTRING") }
                    context.insert(sess)
                    sessionsAdded += 1
                }
            }
            parts.append("sessions added=\(sessionsAdded)")
        } catch { failures.append("sessions: \(error)") }

        // Prayers: a completed row with no live counterpart (name + calendar day) is added whole; a live
        // incomplete row gets the completion. Unmarked set-aside rows aren't worth carrying over.
        var prayersCompleted = 0, prayersAdded = 0
        do {
            var prayerByKey: [String: PrayerModel] = [:]
            for p in try context.fetch(FetchDescriptor<PrayerModel>()) {
                prayerByKey["\(p.name)|\(p.dayKey)"] = p   // 2.8.0: by prayer day
            }
            let c = cols(db, "ZPRAYERMODEL")
            let want = ["ZNAME", "ZSTARTTIME", "ZENDTIME", "ZDATEATMAKE", "ZTIMEATCOMPLETE", "ZNUMBERSCORE", "ZENGLISHSCORE", "ZLATPRAYEDAT",
                        "ZLONGPRAYEDAT", "ZPRAYERSTARTEDAT", "ZPRAYERCOMPLETEDAT", "ZDURATION", "ZMOSQUENAME",
                        "ZRECORDEDTIMEATCOMPLETE", "ZRECORDEDLAT", "ZRECORDEDLON"].filter { c.contains($0) }
            if c.contains("ZNAME"), c.contains("ZSTARTTIME"), c.contains("ZISCOMPLETED") {
                for r in try rows(db, "SELECT \(want.joined(separator: ", ")) FROM ZPRAYERMODEL WHERE ZISCOMPLETED = 1") {
                    guard let start = date(r, "ZSTARTTIME") else { continue }
                    let name = str(r, "ZNAME")
                    let key = "\(name)|\(cal.startOfDay(for: start).timeIntervalSince1970)"
                    let row: PrayerModel
                    if let live = prayerByKey[key] {
                        guard !live.isCompleted else { continue }
                        row = live
                        prayersCompleted += 1
                    } else {
                        let end = date(r, "ZENDTIME") ?? start.addingTimeInterval(60 * 60)
                        row = PrayerModel(name: name, startTime: start, endTime: end, dateAtMake: date(r, "ZDATEATMAKE") ?? start)
                        context.insert(row)
                        prayerByKey[key] = row
                        prayersAdded += 1
                    }
                    row.isCompleted = true
                    row.timeAtComplete = date(r, "ZTIMEATCOMPLETE")
                    row.numberScore = dbl(r, "ZNUMBERSCORE")
                    row.englishScore = r["ZENGLISHSCORE"] as? String
                    row.latPrayedAt = dbl(r, "ZLATPRAYEDAT")
                    row.longPrayedAt = dbl(r, "ZLONGPRAYEDAT")
                    row.prayerStartedAt = date(r, "ZPRAYERSTARTEDAT")
                    row.prayerCompletedAt = date(r, "ZPRAYERCOMPLETEDAT")
                    row.duration = dbl(r, "ZDURATION")
                    if c.contains("ZMOSQUENAME") { row.mosqueName = r["ZMOSQUENAME"] as? String }
                    if c.contains("ZRECORDEDTIMEATCOMPLETE") {
                        row.recordedTimeAtComplete = date(r, "ZRECORDEDTIMEATCOMPLETE")
                        row.recordedLat = dbl(r, "ZRECORDEDLAT"); row.recordedLon = dbl(r, "ZRECORDEDLON")
                    }
                }
            }
            parts.append("prayers added=\(prayersAdded) completed=\(prayersCompleted)")
        } catch { failures.append("prayers: \(error)") }

        // Day scores missing by day.
        var scoresAdded = 0
        do {
            let c = cols(db, "ZDAILYPRAYERSCORE")
            if c.contains("ZDATE") {
                let liveDays = Set(try context.fetch(FetchDescriptor<DailyPrayerScore>()).map { cal.startOfDay(for: $0.date).timeIntervalSince1970 })
                let want = ["ZDATE", "ZAVERAGESCORE"].filter { c.contains($0) }
                for r in try rows(db, "SELECT \(want.joined(separator: ", ")) FROM ZDAILYPRAYERSCORE") {
                    guard let day = date(r, "ZDATE"), !liveDays.contains(cal.startOfDay(for: day).timeIntervalSince1970) else { continue }
                    let score = DailyPrayerScore(date: day)
                    score.averageScore = dbl(r, "ZAVERAGESCORE")
                    context.insert(score)
                    scoresAdded += 1
                }
            }
            parts.append("day scores added=\(scoresAdded)")
        } catch { failures.append("day scores: \(error)") }

        guard failures.count < 5 else { throw Failure(description: failures.joined(separator: "; ")) }
        if context.hasChanges { try context.save() }
        if !failures.isEmpty { parts.append("FAILED: " + failures.joined(separator: "; ")) }
        return parts.joined(separator: " · ")
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

    /// The columns a table has in this file (`PRAGMA table_info`); empty when the table is missing.
    private static func cols(_ db: OpaquePointer, _ table: String) -> Set<String> {
        Set(((try? rows(db, "PRAGMA table_info(\(table))")) ?? []).compactMap { $0["name"] as? String })
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


/// DEBUG: the widget's tap → redraw path timed, one line per step, in the app group's
/// Library/Caches/widget-perf.log (last ~200 KB). Pull it with `xcrun devicectl device copy from --device <udid>
/// --domain-type appGroupDataContainer --domain-identifier group.betternorms.shukr.shukrWidget
/// --source Library/Caches/widget-perf.log --destination <file>`.
enum WidgetPerf {
    static func log(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appending(path: "Library/Caches", directoryHint: .isDirectory) else { return }
        let url = dir.appending(path: "widget-perf.log")
        let stamp = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .secondFraction(.fractional(3)))
        let data = Data("\(stamp) [\(ProcessInfo.processInfo.processName)] \(line())\n".utf8)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            if let size = try? h.seekToEnd(), size > 200_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    /// Milliseconds since `start`.
    static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

#if DEBUG
/// DEBUG switches (Settings → My Dev Stuff) to find what makes a Prayers widget tap slow to redraw.
enum WidgetSpeedTest {
    static let stillRingKey = "debugWidget.stillRing"
    static let fewestEntriesKey = "debugWidget.fewestEntries"
    static var stillRing: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: stillRingKey) == true }
    static var fewestEntries: Bool { UserDefaults(suiteName: SharedStore.appGroup)?.bool(forKey: fewestEntriesKey) == true }
}
#endif


/// Which prayers get a Live Activity for their window (owner, 2026-10-11: its own setting, not the notifications' —
/// "two very different features"). App group, on by default for all five.
enum LiveActivityPrefs {
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static func key(_ prayer: String) -> String { "liveActivity.\(prayer)" }
    /// All five by default (owner, 2026-10-12; was Dhuhr, Asr and Maghrib): iOS's five at a time are topped up whenever
    /// shukr opens, and setup / Settings say so.
    static let onByDefault: Set<String> = Set(prayers)
    static func isOn(_ prayer: String) -> Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: key(prayer)) as? Bool ?? onByDefault.contains(prayer)
    }
}

/// The Live Activity card's own look, apart from the app's (owner, 2026-10-12: "the same way … their widgets"): System
/// (the phone's — the default, as the widgets), Light, Dark, Follows the sun (a window's card can't switch mid-way, so
/// Dhuhr and Asr light, Fajr, Maghrib and Isha dark). Settings → Live Activities → Card look. App group.
enum LiveActivityLook: String, CaseIterable, Identifiable {
    case system, light, dark, sun
    static let key = "liveActivity.look"
    var id: String { rawValue }
    static var current: LiveActivityLook {
        UserDefaults(suiteName: SharedStore.appGroup)?.string(forKey: key).flatMap(LiveActivityLook.init(rawValue:)) ?? .system
    }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .sun: "Sun"
        }
    }
    var detail: String {
        switch self {
        case .system: "Light or dark with your iPhone."
        case .light: "Always light."
        case .dark: "Always dark."
        case .sun: "Light after Fajr, dark at Maghrib."
        }
    }
    /// A prayer's card: dark or not; nil = the phone's.
    func dark(for prayer: String) -> Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        case .sun: !(prayer == "Dhuhr" || prayer == "Asr")
        }
    }
}

/// A prayer window as a Live Activity (PrayerLiveActivities.swift plans them; the card is `PrayerWindowLiveActivity`).
struct PrayerWindowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
        var symbol: String = "sun.max.fill"
        var markedAt: Date? = nil
        /// The Lock Screen card's look (`LiveActivityLook`): nil = the phone's.
        var dark: Bool? = nil
        /// The last card shukr has queued (owner): nothing comes after it until shukr opens, so it says so at its foot.
        /// Optional, so cards already held decode.
        var last: Bool? = nil
        /// After the last card's ↻ added more (owner: "you're all good"): how many cards it added, said on the card that
        /// was tapped; the card says "Live Activity cards topped up" (owner, 2026-10-14: no count — it only worried
        /// people). Optional, so cards already held decode.
        var toppedUp: String? = nil
    }
    /// The window's id: its start in whole minutes since 1970 (so a window is never scheduled twice).
    var n: Int
}

/// The card's ✓ (runs in shukr's process, as every LiveActivityIntent does): marks the real prayer and turns the card.
struct PrayerWindowMarkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark prayer prayed"
    static var isDiscoverable = false
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Mark prayed tapped on #\(n)")
        if let mark = PrayerWindowHooks.mark {
            await mark(n)
        } else if let a = Activity<PrayerWindowAttributes>.activities.first(where: { $0.attributes.n == n }) {
            // The app's hooks weren't set yet (Frank): the store's own mark, and the card goes — never a silent no-op.
            let st = a.content.state
            let done = SharedStore.markPrayerComplete(named: st.label, start: st.start, end: st.end)
            await a.end(nil, dismissalPolicy: .immediate)
            PrayerWindowLog.add("Mark prayed #\(n) without the app's hooks: store mark \(done ? "done" : "not needed / failed"), card ended")
        }
        return .result()
    }
}

/// The last card's ↻ (owner, 2026-10-14: "a refresh button on that last card"): runs in shukr without opening it — a
/// card button's run is when iOS lets shukr add cards from the background (the alarm's Stop can't) — and adds the next ones.
struct PrayerWindowRefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Get more prayer cards"
    static var isDiscoverable = false
    /// Opens shukr (decision last-card-refresh B): in front it fills all five; from the Lock Screen a tap adds only one.
    static var openAppWhenRun = true
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("Refresh tapped on the last card (#\(n))")
        if let refresh = PrayerWindowHooks.refresh { _ = await refresh(n) }
        else { PrayerWindowLog.add("Refresh: the app's hooks weren't set") }
        // Without opening, iOS let a tap add one card only (the allowance is the tap's, not the run's — a chained second
        // intent was refused too, his phone 2026-10-14), so this opens shukr, which fills all five in front.
        return .result()
    }
}

/// After marking: Photo (the prayer's camera) or Tasbih (Tasbih Fatimah) — opens shukr.
struct PrayerWindowOpenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open after a prayer"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "What") var what: String
    @Parameter(title: "Window") var n: Int
    init() {}
    init(what: String, n: Int) { self.what = what; self.n = n }
    func perform() async throws -> some IntentResult {
        PrayerWindowLog.add("\(what) tapped on #\(n) (opens shukr)")
        await PrayerWindowHooks.open?(n, what)
        return .result()
    }
}

/// The Prayers widget's camera (decision widget-camera A): once the prayer that's on is marked, it opens shukr on the
/// prayer photo's camera for it — as the Live Activity card's Photo does.
struct OpenPrayerPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Take a prayer photo"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "Prayer") var prayerName: String
    init() {}
    init(prayerName: String) { self.prayerName = prayerName }
    func perform() async throws -> some IntentResult {
        await PrayerWindowHooks.openPhoto?(prayerName)
        return .result()
    }
}

/// Set by the app at launch (an intent's run is always in the app's process).
enum PrayerWindowHooks {
    /// The widget's camera: the prayer's photo camera, once shukr is in front.
    nonisolated(unsafe) static var openPhoto: ((String) async -> Void)?
    nonisolated(unsafe) static var mark: ((Int) async -> Void)?
    nonisolated(unsafe) static var open: ((Int, String) async -> Void)?
    /// The last card's refresh: as many next cards as iOS lets this run add.
    nonisolated(unsafe) static var refresh: ((Int) async -> Int)?
    /// A widget's mark, run in the app (owner: the card goes at once; and a fresh location — S9FJ). Returns whether it marked.
    nonisolated(unsafe) static var widgetMark: ((String, Date, Date) async -> Bool)?
}

/// What the Live Activities did, both processes — app group Library/Application Support/live-activities.log (1 MB cap).
enum PrayerWindowLog {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/live-activities.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.liveActivityLog")
    static func add(_ line: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss.SSS"
        let text = "\(f.string(from: Date()))  [\(Bundle.main.bundleURL.pathExtension == "appex" ? "ext" : "app")] \(line)\n"
        #if DEBUG
        print("🟣 \(line)")
        #endif
        queue.sync {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? Data(text.utf8).write(to: url) }
            // Days of it, never too big: the last ~4000 lines once it passes 1 MB.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? (all.split(separator: "\n").suffix(4000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

import SwiftUI

// MARK: - Prayer Live Activity card (MY4R), shared by the widget extension (the real card) and the app (the tuner's
// preview). Look D's layout in the app's soft look, dark. Every size / gap / glow comes from `LATuning` (owner: "give me
// a tuner … then I can send you the config"), kept in the app group so the real card reads what the tuner set.

/// The card's adjustable numbers. Defaults = what's on his phone now. Stored as JSON in the app group (`la.tuning`).
struct LATuning: Codable, Equatable {
    // Card
    var cardPaddingSides: Double = 15
    var cardPaddingTopBottom: Double = 12
    var cardMinHeight: Double = 88
    var gapRingToText: Double = 12
    var cardSurfaceGrey: Double = 0.12
    // Ring
    var ringSize: Double = 73   // his phone's tuner, 2026-10-14 (and the nine below)
    var ringArcDiameter: Double = 0.82      // of the ring size
    var ringBandWidth: Double = 5.5          // at the 90 pt design size
    var ringArcWidth: Double = 3.5          // at the 90 pt design size
    var ringSymbolSize: Double = 17
    var ringBandLift: Double = 0.1
    // Text
    var titleSize: Double = 20
    var timeLeftSize: Double = 14   // 12 read too small on his phone (owner, 2026-10-12)
    var endsSize: Double = 12
    var lineSpacing: Double = 1.5
    var textOffsetY: Double = 0
    // Glow
    var glowStrength: Double = 0.16
    var glowReach: Double = 0.51
    var glowCentreX: Double = 0.19
    var glowCentreY: Double = 0.5
    // Buttons
    var buttonSize: Double = 44
    var buttonSymbolSize: Double = 18
    var buttonStackGap: Double = 7
    var buttonOffsetX: Double = 0
    var buttonSymbolOpacity: Double? = nil   // nil = 0.65: the symbols a little dull, not stark white (owner)
    var symbolOpacity: Double { get { buttonSymbolOpacity ?? 0.65 } set { buttonSymbolOpacity = newValue } }
    // 15 s bar
    var barSideInset: Double = 5
    var barBottomInset: Double = 0
    var barThickness: Double = 0.8
    // Dynamic Island (opened up)
    var islandRingSize: Double = 66
    var islandTitleSize: Double = 20
    var islandLineSize: Double = 13
    var islandButtonSize: Double = 38
    var islandTimeSizeOpt: Double? = nil        // nil = 17: the folded island's "24m"
    /// The prayer name's weight: 0 light · 1 regular · 2 medium (nil — owner) · 3 semibold · 4 bold — the card and the island apart.
    var titleWeight: Int? = 1   // regular (his tuner, 2026-10-14; was medium)
    var islandTitleWeight: Int? = nil
    static let weights: [Font.Weight] = [.light, .regular, .medium, .semibold, .bold]
    static let weightNames = ["Light", "Regular", "Medium", "Semibold", "Bold"]
    var islandTimeSize: Double { get { islandTimeSizeOpt ?? 17 } set { islandTimeSizeOpt = newValue } }
    /// The opened island's row: the button's height (the time sits beside it now); the ring's side takes the same.
    var islandRowHeight: Double { islandButtonSize }
    /// The ended ring's dashes (owner: tunable): how many, how much of each step is dash, how bright, how thick (nil =
    /// the arc's width).
    var endedDashCountOpt: Double? = nil
    var endedDashShareOpt: Double? = nil
    var endedDashOpacityOpt: Double? = nil
    var endedDashWidthOpt: Double? = 2.5
    var endedDashCount: Double { get { endedDashCountOpt ?? 16 } set { endedDashCountOpt = newValue } }
    var endedDashShare: Double { get { endedDashShareOpt ?? 0.5 } set { endedDashShareOpt = newValue } }
    var endedDashOpacity: Double { get { endedDashOpacityOpt ?? 0.5 } set { endedDashOpacityOpt = newValue } }
    var endedDashWidth: Double { get { endedDashWidthOpt ?? ringArcWidth } set { endedDashWidthOpt = newValue } }
    // How the time left is written — iOS's self-updating formats only (a Live Activity has no timeline): 0 "1 hour,
    // 39 minutes" (offset) · 1 "1 hr, 39 min" (relative; under an hour it ticks seconds) · 2 "1:39" · 3 "1:39:12" ·
    // 4 (nil, the default — owner: no seconds) relative over an hour, then "59 minutes", then "under a minute", switched
    // by timer gates. Optional so a saved tuning without it still decodes (renamed from timeLeftStyle so earlier picks drop).
    var timeLeftFormat: Int? = 4

    /// Only what differs from the defaults is saved, laid over the defaults on reading — so a new default reaches every
    /// value nobody tuned (a full save kept the old ones). 3: earlier full saves are left behind.
    static let key = "la.tuning3"
    private static func dict(_ t: LATuning) -> [String: Any] {
        (try? JSONEncoder().encode(t)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    static var current: LATuning {
        guard let data = UserDefaults(suiteName: SharedStore.appGroup)?.data(forKey: key),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return LATuning() }
        let merged = dict(LATuning()).merging(saved) { _, new in new }
        return (try? JSONSerialization.data(withJSONObject: merged)).flatMap { try? JSONDecoder().decode(LATuning.self, from: $0) } ?? LATuning()
    }
    func save() {
        let base = Self.dict(LATuning())
        let changed = Self.dict(self).filter { k, v in !(base[k].map { "\($0)" == "\(v)" } ?? false) }
        if let data = try? JSONSerialization.data(withJSONObject: changed) { UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: Self.key) }
    }
    var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// The app's soft look, dark (the card is always dark — owner).
enum LASoft {
    /// The card's surface: the dark grey (tunable), or the app's light soft surface (asset NeuRing, light).
    static func surface(_ t: LATuning, _ scheme: ColorScheme = .dark) -> Color {
        scheme == .dark ? Color(white: t.cardSurfaceGrey) : Color(red: 0.890, green: 0.898, blue: 0.933)
    }
    /// The soft look's two shadows (assets NeuDarkShad / NeuLightShad in light; deeper in dark).
    static func shade(_ scheme: ColorScheme = .dark) -> Color { scheme == .dark ? .black.opacity(0.75) : .black.opacity(0.22) }
    static func light(_ scheme: ColorScheme = .dark) -> Color { scheme == .dark ? .white.opacity(0.06) : .white }
    /// The island is black: its soft pieces are a dark grey raised off it.
    static let island = Color(white: 0.11)
}

/// The running look until the window ends, the ended look from then on — by itself (timer gates), because iOS's stale
/// flag didn't flip at the stale date. Marked, or already stale: just that one look.
struct LAEnds<Content: View>: View {
    let state: PrayerWindowAttributes.ContentState
    let stale: Bool
    @ViewBuilder let content: (_ ended: Bool) -> Content
    var body: some View {
        // ONE structure in every state (owner: "the shared elements stay … just the new stuff animates in"): when the
        // card is marked or goes stale only the masks change, so iOS keeps the name, the ring, the card itself, and fades
        // just what's new or gone (an if / else here swapped the whole card in a cross-fade).
        // Marked: the SAME gates as while running, their switch set far off — a different mask (Color.white) still made
        // iOS fade the whole piece, so "Asr" ghosted as it was marked (the sim's island).
        let marked = state.markedAt != nil
        let edge = marked ? Date.distantFuture : state.end
        ZStack {
            content(false).mask {
                if stale && !marked { Color.clear } else { LAGate(from: nil, until: edge) }
            }
            content(true).mask {
                if stale && !marked { Color.white } else { LAGate(from: edge, until: nil) }
            }
        }
    }
}

/// The Lock Screen card (always dark).
extension EnvironmentValues {
    /// A picture of the card (the setup page and Settings' Card look play a window in seconds): its "ends" line keeps
    /// this time instead of the moving window's (owner: "the end time would stay fixed"). Never set on the real card.
    @Entry var laShownEnd: Date? = nil
    /// The Dynamic Island's views: their timed changes flip instead of fading (LAGate). On an island iPhone iOS archives
    /// them with the Lock Screen card, under one ~2 MB limit, and they were half of it (2026-10-16); the card keeps its fade.
    @Entry var laInstantGates = false
}

struct LALockCard: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let stale: Bool
    var t = LATuning.current
    @Environment(\.colorScheme) private var system
    var body: some View {
        // The buttons are drawn ONCE, over both looks: inside LAEnds the ended copy sat on top and took the touch, so the
        // visible button never showed its press (owner). The one button switches its own symbol at the end.
        let unmarkedEnded = stale && state.markedAt == nil
        LAEnds(state: state, stale: stale) { e in LALockCardBody(state: state, n: n, ended: e, t: t, liveButtons: true) }
            .overlay(alignment: .trailing) {
                LAGlyphs(state: state, n: n, ended: unmarkedEnded, size: t.buttonSize, onIsland: false, t: t, live: true)
                    .offset(x: t.buttonOffsetX)
                    .padding(.trailing, t.cardPaddingSides)
                    // Level with the ring's row, not the middle of a card grown by the last card's note.
                    .padding(.bottom, LALastNote.shows(state) ? LALastNote.room : 0)
            }
            .overlay(alignment: .bottom) {
                if LALastNote.shows(state) { LALastNote(state: state, n: n, live: true).padding(.bottom, 8) }
            }
            .environment(\.colorScheme, state.dark.map { $0 ? .dark : .light } ?? system)
    }
}

/// Look D's layout in the soft look: the soft ring with the prayer's symbol on the left, the name and two lines beside
/// it, the soft round buttons on the right, the score colour glowing out from the ring; once prayed, the 15 s bar.
struct LALockCardBody: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    /// The card draws its buttons itself, once (LALockCard): here they only hold their place.
    var liveButtons = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: t.gapRingToText) {
            LASideRing(state: state, ended: ended, size: t.ringSize, symbolSize: t.ringSymbolSize, onIsland: false, t: t)
            LANameLines(state: state, ended: ended, big: true, t: t).offset(y: t.textOffsetY)
            Spacer(minLength: 0)
            LAGlyphs(state: state, n: n, ended: ended, size: t.buttonSize, onIsland: false, t: t).offset(x: t.buttonOffsetX)
                .opacity(liveButtons ? 0 : 1).allowsHitTesting(!liveButtons)
        }
        .padding(.horizontal, t.cardPaddingSides).padding(.vertical, t.cardPaddingTopBottom)
        .frame(minHeight: t.cardMinHeight)
        // The last card queued: a line at its foot, centred (owner) — the row above keeps its size.
        .padding(.bottom, LALastNote.shows(state) ? LALastNote.room : 0)
        // Our own solid surface under the glow: iOS draws `activityBackgroundTint` see-through (the wallpaper turned a red
        // glow pink on his phone).
        .background {
            ZStack {
                LASoft.surface(t, scheme)
                LAWash(state: state, ended: ended, t: t)
            }
        }
        .overlay(alignment: .bottom) {
            LADismissBar(state: state).scaleEffect(x: 1, y: t.barThickness)
                .padding(.horizontal, t.barSideInset).padding(.bottom, t.barBottomInset)
        }
        .overlay(alignment: .bottom) {
            if LALastNote.shows(state) {
                LALastNote(state: state).padding(.bottom, 8)
                    .opacity(liveButtons ? 0 : 1).allowsHitTesting(false)   // the real card draws its button once (LALockCard)
            }
        }
        .activityBackgroundTint(LASoft.surface(t, scheme))
        .activitySystemActionForegroundColor(.primary)
    }
}

/// The last card shukr has queued says so (owner: "the last one … open the app if you want to keep receiving them"): one
/// quiet line at the card's foot, centred. Not once marked (the card is going), never on the island. Marking from the
/// card also adds the next ones (iOS lets a card's ✓ add cards; the alarm's Stop can't) — decision last-card-note B.
struct LALastNote: View {
    static let room: CGFloat = 22
    static let text = "Last card · tap to add more"
    static let toppedUpText = "Live Activity cards topped up"
    static func shows(_ s: PrayerWindowAttributes.ContentState) -> Bool {
        s.markedAt == nil && (s.last == true || s.toppedUp != nil)
    }
    let state: PrayerWindowAttributes.ContentState
    var n = 0
    /// The real card's button (drawn once, in LALockCard's overlay); elsewhere the same pill as a picture.
    var live = false
    var body: some View {
        if state.toppedUp != nil, state.last != true {
            // After a tap added more: a plain line with a green check, not a pill (owner) — it isn't a button. No count
            // (owner: "not worth worrying them, esp if they're non-power users").
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                Text(Self.toppedUpText)
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 3)
        } else if live {
            Button(intent: PrayerWindowRefreshIntent(n: n)) { pill(symbol: "arrow.clockwise", text: Self.text) }.buttonStyle(.plain)
        } else {
            pill(symbol: "arrow.clockwise", text: Self.text)
        }
    }
    private func pill(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text)
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// The soft ring with the prayer's symbol inside (a ✓ in its score colour once prayed).
struct LASideRing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let size: Double
    let symbolSize: Double
    let onIsland: Bool
    let t: LATuning
    var body: some View {
        ZStack {
            LARing(state: state, ended: ended, size: size * t.ringArcDiameter, onIsland: onIsland, t: t)
            if let at = state.markedAt {
                Image(systemName: "checkmark")
                    .font(.system(size: symbolSize * 0.9, weight: .medium))
                    .foregroundStyle(PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at)))
                    .transition(LATransitions.swap)
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .transition(LATransitions.swap)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The name, then: the time left (red in the last half hour) + "ends 6:48 PM"; prayed: "Prayed 4:31 PM" +
/// "Perfect · 100"; ended: "Asr ended" + "6:48 PM · not marked".
struct LANameLines: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let big: Bool
    let t: LATuning
    @Environment(\.laShownEnd) private var shownEnd
    var body: some View {
        let title = big ? t.titleSize : t.islandTitleSize
        let line = big ? t.timeLeftSize : t.islandLineSize
        let small = big ? t.endsSize : t.islandLineSize
        VStack(alignment: .leading, spacing: t.lineSpacing) {
            Text(ended ? "\(state.label) ended" : state.label)
                .font(.system(size: title, weight: LATuning.weights[min(max((big ? t.titleWeight : t.islandTitleWeight) ?? 2, 0), 4)]))
                .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if let at = state.markedAt {
                let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                Group {
                    Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: line)).foregroundStyle(.primary)
                    Text("\(PrayerScoring.grade(for: score).rawValue) · \(Int((score * 100).rounded()))")
                        .font(.system(size: small)).foregroundStyle(.secondary)
                }
                .transition(LATransitions.line)
            } else if ended {
                Text("\(state.end.formatted(date: .omitted, time: .shortened)) · not marked")
                    .font(.system(size: line)).foregroundStyle(.secondary)
            } else {
                let lastHalf = LAGate.lastHalf(of: state.end)
                Group {
                ZStack(alignment: .leading) {
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard, part: .early).foregroundStyle(.primary)
                        .mask { LAGate(from: nil, until: lastHalf) }
                    // Real semibold (owner: "rather have it bold in red than avoid the doubling"; the fade is short enough).
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard, part: .late).foregroundStyle(.red).fontWeight(.semibold)
                        .mask { LAGate(from: lastHalf, until: nil) }
                }
                .font(.system(size: line))
                // The island too (owner: the time between the two lines, as on the card; "24m" only folded).
                Text("ends \((shownEnd ?? state.end).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: small)).foregroundStyle(.secondary)
                }
                .transition(LATransitions.line)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// The time left, ticking by itself in a format iOS draws (`LATuning.timeLeftFormat`).
struct LATimeLeft: View {
    let end: Date
    var style = 0
    var suffix = true
    /// Which stretch this copy is ever seen in (the card's white copy is hidden from the last half hour, its red copy
    /// before it): a layer it can never show isn't drawn (`shown(…, never:)`).
    var part = LATimePart.all
    private var left: String { suffix ? " left" : "" }
    static let styles = ["1 hour, 39 minutes", "1 hr, 39 min · 19 min, 56 sec", "timer to the minute (iOS writes it in words)", "1:39:12", "1 hr, 39 min · 59 minutes"]
    /// What the tuner offers: 2 reads the same as 0 (iOS writes a minute-precision timer in words).
    static let offered = [4, 1, 0, 3]
    static let standard = 4
    var body: some View {
        switch style {
        case 4:
            // Relative drops to "19 min, 56 sec" under an hour and ticks; offset, minutes only, floors to "0 minutes" in the
            // last one — so three layers, each shown only in its own stretch (the sim: 1 hr, 0 min → 59 minutes on time).
            let hour = end.addingTimeInterval(-3600), minute = end.addingTimeInterval(-60)
            // Before the last half hour: over an hour, or 31–59 minutes. In it: under 31 minutes.
            ZStack(alignment: .leading) {
                Text("\(Text(end, style: .relative))\(left)").shown(from: nil, until: hour, never: part == .late)
                LAMinuteWords(end: end, left: left, part: part)
                    .shown(from: part == .late ? nil : hour, until: part == .early ? nil : minute)
                Text("under a minute\(left)").shown(from: minute, until: nil, never: part == .early)
            }
        case 1: Text("\(Text(end, style: .relative))\(left)")
        case 2: Text("\(Text(.currentDate, format: .timer(countingDownIn: Date.now..<max(end, .now), maxPrecision: .seconds(60))))\(left)")
        case 3: Text("\(Text(timerInterval: Date.now...max(end, .now), countsDown: true))\(left)")
        default: Text("\(Text(.currentDate, format: .offset(to: end, allowedFields: [.hour, .minute], maxFieldCount: 2, sign: .never)))\(left)")
        }
    }
}

/// After Mark prayed: how long until the card goes (15 s) — a thin grey bar, full at the tap, emptying right to left.
struct LADismissBar: View {
    let state: PrayerWindowAttributes.ContentState
    static let seconds: TimeInterval = 15
    var body: some View {
        if let at = state.markedAt {
            ProgressView(timerInterval: at...at.addingTimeInterval(Self.seconds), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(Color(white: 0.55))   // neutral: sage clashed with a yellow / red ring (owner)
                .labelsHidden()
        }
    }
}

/// The island's small right side: empty — the ring says enough — until the last half hour: "27m" in red (owner).
struct LACompactTrailing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    var body: some View {
        if state.markedAt == nil && !ended {
            LAIslandTime(end: state.end)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: 64)
        }
    }
}

/// "27m": the minutes left, by itself, for the last half hour. iOS has no such format (its minute-precision countdowns
/// are words), so this is the stock "27:08" countdown set flush right, its ":08" hidden under a mask the width of ":00",
/// and an "m" in that place. (Clipping it to the width of "00" from the left worked in the app but drew only the "m" on the
/// island: iOS lays a timer text out at its widest.) Under a minute: "<1m".
/// "30 minutes left" from the per-second countdown, so the number turns exactly on time (iOS's own minute text turned
/// 1–4 s late, and the red last half hour has to start just after "30" — owner): the stock "30:08" set so its digits
/// land on a hidden "00", the rest masked off, then " minutes left". "0" room under ten minutes; "1 minute left"; the
/// last minute is the caller's. Never fixedSize on the timer (an unbounded ideal width crashed the widget).
struct LAMinuteWords: View {
    let end: Date
    var left = " left"
    var part = LATimePart.all
    var body: some View {
        let ten = end.addingTimeInterval(-10 * 60), two = end.addingTimeInterval(-2 * 60)
        ZStack(alignment: .leading) {
            words(room: "00").shown(from: nil, until: part == .early ? nil : ten)
            words(room: "0").shown(from: ten, until: two, never: part == .early)
            Text("1 minute\(left)").shown(from: two, until: nil, never: part == .early)
        }
        .monospacedDigit()
    }
    private func words(room: String) -> some View {
        HStack(spacing: 0) {
            Text(room).hidden()
            Text(" minutes\(left)")
        }
        .overlay(alignment: .leading) {
            // "00:00" laid out (hidden), the timer flush right over it: its digits fall on the "00".
            HStack(spacing: 0) { Text(room).hidden(); Text(":00").hidden() }
                .overlay(alignment: .trailing) {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 400, alignment: .trailing)
                }
                .mask {
                    HStack(spacing: 0) {
                        Text(room).hidden().overlay(Color.black)
                        Text(":00").hidden()
                    }
                }
        }
    }
}

struct LAMinutesLeft: View {
    let end: Date
    /// The font size it's drawn at: its width is set from it (≈ "00m"), since the timer text claims room for far more
    /// (that widened the folded island; a hidden "00m" as the frame garbled the digits on the island).
    var size: Double = 14
    var body: some View {
        let one = end.addingTimeInterval(-60)
        // Never fixedSize here: in a widget a timer text's ideal width is unbounded, and the gates' GeometryReaders then
        // crashed the extension (the card vanished). A fixed room instead, the time flush right in it, clipped below.
        ZStack(alignment: .trailing) {
            // The "m" sits in the ":00"'s room, which is wider: pulled right by the difference so "24m" ends at the edge.
            minutes.padding(.trailing, -size * 0.62).frame(width: size * 4, alignment: .trailing).mask { LAGate(from: nil, until: one) }
            Text("<1m").lineLimit(1).frame(width: size * 4, alignment: .trailing).mask { LAGate(from: one, until: nil) }
        }
        .monospacedDigit()
        .frame(width: size * 2.8, alignment: .trailing)
        .clipped()
    }
    private var minutes: some View {
        ZStack(alignment: .trailing) {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
                .mask {
                    HStack(spacing: 0) {
                        Color.black
                        Text(":00").hidden()   // the seconds' room: masked away
                    }
                }
            Text(":00").hidden().overlay(alignment: .leading) { Text("m") }   // the "m" where ":08" was
        }
    }
}

/// The island's time left over its button: only in the last half hour, "27m" in red (owner: the ring says enough before).
struct LAIslandTime: View {
    let end: Date
    var size: Double = 14
    var body: some View {
        LAMinutesLeft(end: end, size: size).foregroundStyle(.red).fontWeight(.semibold)
            .mask { LAGate(from: LAGate.lastHalf(of: end), until: end) }
    }
}

/// The folded island's left side: the small ring (its right side is `LACompactTrailing`).
struct LACompactLeading: View {
    let state: PrayerWindowAttributes.ContentState
    let stale: Bool
    let t: LATuning
    var body: some View {
        // Room round the ring inside LAEnds' masks (each is exactly its content's box): the band, the arc and the glow are
        // stroked on the ring's edge and half of them was cut off (owner: "looks broken in bottom and left side"). The
        // negative padding gives the room back, so the island lays it out at 22 pt as before.
        // The ring alone, no prayer symbol inside (owner, 2026-10-16: "get rid of the symbol when it's in the collapsed
        // dynamic island"; it didn't draw on her 15 Pro at the smaller ring).
        LAEnds(state: state, stale: stale) { e in LAFoldedRing(state: state, ended: e, t: t).padding(6) }
            .padding(-6)
    }
}

/// The folded island's ring (and the minimal one beside another app's): smaller than its 22 pt slot and drawn thicker
/// (owner, 2026-10-16: it was clipped against the pill's rounded end on her 15 Pro — "make the radius smaller and the
/// ring / progress a little thicker"). The slot stays 22 pt so the island keeps its width; the band is plain (no shadows).
struct LAFoldedRing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    static let slot = 22.0, ring = 18.0, lineScale = 2.9   // band ≈ 3.1 pt, arc ≈ 2 pt (were 1.3 / 0.9)
    var body: some View {
        LARing(state: state, ended: ended, size: Self.ring, onIsland: true, lineScale: Self.lineScale, t: t)
            .frame(width: Self.slot, height: Self.slot)
    }
}

/// The island's left side: the soft ring.
struct LAIslandLeading: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        // No glow: the island is always black and each region clips to its own box (the glow came out a square).
        LASideRing(state: state, ended: ended, size: t.islandRingSize, symbolSize: t.islandRingSize * 0.26, onIsland: true, t: t)
    }
}

/// The island's ring with the name beside it (layouts 1 and 2 — Frank's mock).
struct LAIslandRingAndName: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        HStack(spacing: 12) {
            LAIslandLeading(state: state, ended: ended, t: t)
            LANameLines(state: state, ended: ended, big: false, t: t)
        }
        .frame(minHeight: t.islandRowHeight + 8)   // the button side's height (+ its 4 pt padding), centred alike
    }
}

/// The island's right side: the mark button (Frank's mock); prayed → camera over tasbih.
struct LAIslandTrailing: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    /// Drawn once (not inside LAEnds — a hidden copy on top took the touch): the button switches at the end itself.
    var live = false
    var body: some View {
        // A plain ✓ that never changes layout (a button whose contents switched by time took no tap on the island); the
        // time left is the name's middle line, as on the card — "24m" only on the folded island (owner).
        LAGlyphs(state: state, n: n, ended: ended, size: t.islandButtonSize, onIsland: true, t: t, live: live)
            .frame(minHeight: t.islandRowHeight)
            .padding(.vertical, 2)
    }
}

/// The right side: the soft round buttons — a ✓ marks it (owner: the circle looked odd); prayed → camera over the zikr beads;
/// ended → a grey dashed circle (Qaza; never red — owner).
struct LAGlyphs: View {
    let state: PrayerWindowAttributes.ContentState
    let n: Int
    let ended: Bool
    let size: Double
    let onIsland: Bool
    let t: LATuning
    /// Drawn once over both looks: the mark button turns from ✓ to the dim dashed circle by itself at the window's end.
    var live = false
    var body: some View {
        if state.markedAt != nil {
            // On the Lock Screen the pair fits the running card's row (the ring or the one button, whichever is taller), so
            // marking never makes the card taller (owner).
            // The island too: the pair fits the ring's height, so marking never resizes the island (a resize cross-faded
            // the whole island instead of swapping only what changed — owner).
            let row = onIsland ? max(t.islandRingSize, t.islandButtonSize) : max(t.ringSize, t.buttonSize)
            let pair = min(size * 0.82, (row - t.buttonStackGap) / 2)
            VStack(spacing: t.buttonStackGap) {
                LARoundButton(intent: PrayerWindowOpenIntent(what: "Photo", n: n), symbol: "camera", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
                LARoundButton(intent: PrayerWindowOpenIntent(what: "Tasbih", n: n), symbol: "circle.hexagonpath", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
            }
            .transition(LATransitions.swap)
        } else {
            HStack(spacing: t.buttonStackGap) {
                // The last card's ↻ beside the ✓ (owner: "more in your face"), as well as its pill; never on the island.
                if state.last == true && !onIsland {
                    LARoundButton(intent: PrayerWindowRefreshIntent(n: n), symbol: "arrow.clockwise", size: size,
                                  symbolSize: t.buttonSymbolSize * 0.9, t: t)
                        .transition(LATransitions.swap)
                }
                if ended {
                    LARoundButton(intent: PrayerWindowMarkIntent(n: n), symbol: "circle.dashed", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland, dim: true, t: t)
                        .transition(LATransitions.swap)
                } else {
                    LARoundButton(intent: PrayerWindowMarkIntent(n: n), symbol: "checkmark", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland,
                                  endsAt: live ? state.end : nil, t: t)
                        .transition(LATransitions.swap)
                }
            }
        }
    }
}

/// What changes when the card is updated (marked): what stays keeps its place, the new grows / rises in and the old
/// fades out (owner: "feels like one living card"). iOS plays transitions with its own timing (animation modifiers are
/// ignored), up to 2 s.
enum LATransitions {
    // Each with its own timing (Live Activities honour a transition's .animation): the old out fast, the new in just
    // after — at iOS's default the two overlapped for ~0.6 s and the old lingered (owner: "only brings in new items").
    private static let into = Animation.easeOut(duration: 0.25)
    // The old goes at once (a fading-out old under the fading-in new still overlapped for ~0.3 s), the new comes in.
    static let swap = AnyTransition.asymmetric(insertion: AnyTransition.scale(scale: 0.6).combined(with: .opacity).animation(into),
                                               removal: .identity)
    static let line = AnyTransition.asymmetric(insertion: AnyTransition.offset(y: 5).combined(with: .opacity).animation(into),
                                               removal: .identity)
}

/// Pressed: a touch darker and smaller.
struct LAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
    }
}

/// The app's soft raised disc.
struct LARoundButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: Double
    let symbolSize: Double
    var onIsland = false
    var dim = false
    /// The ✓ gives way to the dim dashed circle (Qaza) here, by itself.
    var endsAt: Date? = nil
    let t: LATuning
    var body: some View {
        Button(intent: intent) {
            LADisc(symbol: symbol, size: size, symbolSize: symbolSize, onIsland: onIsland, dim: dim, endsAt: endsAt, t: t)
        }
        .buttonStyle(LAPressStyle())
    }
}

/// A soft round button's face: the symbol on the raised disc.
struct LADisc: View {
    let symbol: String
    let size: Double
    let symbolSize: Double
    var onIsland = false
    var dim = false
    var endsAt: Date? = nil
    let t: LATuning
    private func glyph(_ name: String, dim: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: symbolSize, weight: .light))
            .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(t.symbolOpacity)))
    }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if let endsAt {
                glyph(symbol, dim: dim).mask { LAGate(from: nil, until: endsAt) }
                glyph("circle.dashed", dim: true).mask { LAGate(from: endsAt, until: nil) }
            } else {
                glyph(symbol, dim: dim)
            }
        }
        .frame(width: size, height: size)
        .background {
            if onIsland {
                // On the island's black a plain grey disc (owner): the soft shadows only showed as clipped corners.
                Circle().fill(Color(white: 0.19))
            } else {
                Circle().fill(LASoft.surface(t, scheme))
                    .shadow(color: LASoft.shade(scheme), radius: 3, x: 1.5, y: 1.5)
                    .shadow(color: LASoft.light(scheme), radius: 3, x: -1.5, y: -1.5)
            }
        }
    }
}

/// The score colour glowing out from the ring (Look D's halo), in the colour of the grade now (changes by itself);
/// prayed: its score's colour; ended: none.
struct LAWash: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let t: LATuning
    /// The island: a round glow this wide, centred on the ring (the island has no background of ours to fill).
    var islandRadius: Double? = nil
    var body: some View {
        // Only a prayer marked Perfect glows (owner, 2026-10-11): none while the window runs, nor for a lower grade.
        if let at = state.markedAt {
            let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
            if PrayerScoring.grade(for: score) == .perfect { wash(PrayerScoring.color(for: score)) }
        }
    }
    /// An ellipse centred on the ring (Look D: 120 % × 140 % of the card), the colour at `glowStrength`, gone by `glowReach`.
    @ViewBuilder private func wash(_ c: Color) -> some View {
        if let r = islandRadius {
            RadialGradient(colors: [c.opacity(t.glowStrength * 1.4), c.opacity(0)], center: .center, startRadius: 0, endRadius: r)
                .frame(width: r * 2, height: r * 2)
                .allowsHitTesting(false)
        } else {
            card(c)
        }
    }
    private func card(_ c: Color) -> some View {
        GeometryReader { g in
            let rx = g.size.width * 1.2 * t.glowReach, ry = g.size.height * 1.4 * t.glowReach
            EllipticalGradient(colors: [c.opacity(t.glowStrength), c.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: rx * 2, height: ry * 2)
                .position(x: g.size.width * t.glowCentreX, y: g.size.height * t.glowCentreY)
        }
    }
}

/// The window's grades in order, each with when it applies (its colour taken mid-stretch: 1 s after a change a long
/// window's score is still 0.99999…, which counts as Perfect).
enum LAGrades {
    struct Span { let grade: PrayerScoring.Grade; let color: Color; let from: Date?; let until: Date? }
    static func spans(_ s: PrayerWindowAttributes.ContentState) -> [Span] {
        let changes = PrayerScoring.gradeChanges(start: s.start, end: s.end)
        let starts: [Date?] = [nil] + changes.map { Optional($0) }
        return starts.enumerated().map { i, from in
            let a = from ?? s.start
            let b = i + 1 < starts.count ? (starts[i + 1] ?? s.end) : s.end
            let at = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let score = PrayerScoring.score(start: s.start, end: s.end, markedAt: at)
            return Span(grade: PrayerScoring.grade(for: score), color: PrayerScoring.color(for: score),
                        from: from, until: i + 1 < starts.count ? starts[i + 1] : s.end)
        }
    }
}

/// The soft raised band (the app's / widget's): the surface, lifted — shade down-right, light up-left.
struct LASoftBand: View {
    let width: Double
    let t: LATuning
    var surface: Color? = nil
    /// The lifted band (owner, 2026-10-14: "more apparent on the lock screen"); the island keeps the flat one (each of
    /// its regions clips, so no drop or glow there — island-rules.md).
    var lifted = true
    /// No shadows at all: the folded island's thick band (its shadows grew with it into a grey halo at the region's edge).
    var plain = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if plain {
            Circle().stroke(surface ?? LASoft.surface(t, scheme), lineWidth: width)
        } else if lifted && surface == nil {
            LiftedSoftBand(width: width, surface: LASoft.surface(t, scheme), shade: LASoft.shade(scheme), light: LASoft.light(scheme))
        } else {
            Circle()
                .stroke(surface ?? LASoft.surface(t, scheme), lineWidth: width)
                .shadow(color: LASoft.shade(surface == nil ? scheme : .dark), radius: width * 0.6, x: width * 0.3, y: width * 0.3)
                .shadow(color: LASoft.light(surface == nil ? scheme : .dark), radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
                .shadow(color: .white.opacity(t.ringBandLift), radius: width * 0.5, x: -width * 0.25, y: -width * 0.25)
        }
    }
}

/// The soft ring's band, lifted off its surface (the app icon's idea, decision app-icon-depth D, on the soft ring's own
/// radii — the edges stay soft, owner): today's shade and light, each stacked again wider and further; a long blurred
/// drop under the ring; a blurred glow along the band's top-left. Dark reads as raised, not a black outline. Mocked in
/// Settings → My Dev Stuff → Ring depth (RingDepthMocks.swift); used by the Live Activity card and the Prayers widget.
struct LiftedSoftBand: View {
    let width: Double
    let surface: Color
    let shade: Color
    let light: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let w = width, dark = scheme == .dark
        ZStack {
            Circle().stroke(lineWidth: w * 1.4)
                .foregroundStyle(Color.black.opacity(dark ? 0.5 : 0.14))
                .blur(radius: w * 1.6)
                .offset(x: w * 0.6, y: w * 0.9)
            Circle().stroke(surface, lineWidth: w)
                .shadow(color: shade, radius: w * 0.6, x: w * 0.3, y: w * 0.3)
                .shadow(color: shade.opacity(0.8), radius: w * 1.02, x: w * 0.54, y: w * 0.54)
                .shadow(color: light, radius: w * 0.9, x: -w * 0.3, y: -w * 0.3)
                .shadow(color: light, radius: w * 1.35, x: -w * 0.48, y: -w * 0.48)
            Circle().stroke(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.9), .white.opacity(0)],
                                           startPoint: .topLeading, endPoint: .center), lineWidth: w * 0.6)
                .blur(radius: w * 0.35)
        }
    }
}

/// A still picture of a card (Explore's pictures): its live arcs drawn once, at this moment, not redrawn 30 times a
/// second — a list of them sat at ~37 % CPU idle on the owner's 13 Pro Max (perf-recheck, 2026-10-14). nil = live.
private struct LAStillMomentKey: EnvironmentKey { static let defaultValue: Date? = nil }
extension EnvironmentValues {
    var laStillMoment: Date? {
        get { self[LAStillMomentKey.self] }
        set { self[LAStillMomentKey.self] = newValue }
    }
}

/// The live arc (the widget's `LiveArc`): a round arc with a glow, shown up to now by the stock timer ring used as a mask.
struct LALiveArc: View {
    let start: Date
    let end: Date
    let color: Color
    let width: Double
    @Environment(\.laStillMoment) private var stillMoment
    /// In the app (the tuner's preview) the stock timer ring is a spinner, not a gauge: there the arc is drawn up to now
    /// (once a second); on the Lock Screen it's the system's own, self-updating mask.
    private static let inApp = Bundle.main.bundleURL.pathExtension != "appex"
    var body: some View {
        if Self.inApp, let stillMoment {
            arc(upTo: stillMoment)
        } else if Self.inApp {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in   // smooth: the setup / Card look demo plays a window in seconds
                arc(upTo: ctx.date)
            }
        } else {
            systemArc
        }
    }

    private func arc(upTo now: Date) -> some View {
        let f = min(max(now.timeIntervalSince(start) / max(end.timeIntervalSince(start), 1), 0), 1)
        return Circle().trim(from: 0, to: f)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: color.opacity(0.45), radius: 3)
    }

    private var systemArc: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .mask {
                ZStack {
                    Color.black
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .labelsHidden()
                }
                .frame(width: 98, height: 98)
                .environment(\.colorScheme, .light)
                .compositingGroup()
                .brightness(-0.35)
                .contrast(3)
                .luminanceToAlpha()
            }
            .shadow(color: color.opacity(0.45), radius: 3)
    }
}

/// The ring at its 90 pt design size, scaled: one colour at a time (an arc per grade, each shown only while its grade
/// lasts). Prayed: the whole ring in its score. Ended: 8 grey dashes.
struct LARing: View {
    let state: PrayerWindowAttributes.ContentState
    let ended: Bool
    let size: Double
    var onIsland = false
    /// The band, the arc and the ended dashes this many times their design width: at the folded island's size the card's
    /// widths scale to hairlines (owner, 2026-10-16: "make the radius smaller and the ring / progress a little thicker").
    var lineScale: Double = 1
    let t: LATuning
    var body: some View {
        let band = t.ringBandWidth * lineScale, arc = t.ringArcWidth * lineScale
        ZStack {
            LASoftBand(width: band, t: t, surface: onIsland ? LASoft.island : nil, plain: lineScale > 1)
            if let at = state.markedAt {
                let c = PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at))
                Circle().stroke(c, style: StrokeStyle(lineWidth: arc, lineCap: .round))
                    .shadow(color: c.opacity(0.45), radius: 3)
            } else if ended {
                let step = CGFloat.pi * 90 / max(t.endedDashCount.rounded(), 1)
                Circle().stroke(Color.secondary.opacity(t.endedDashOpacity),
                                style: StrokeStyle(lineWidth: t.endedDashWidth * lineScale, lineCap: .round, dash: [step * t.endedDashShare, step * (1 - t.endedDashShare)]))
                    .rotationEffect(.degrees(-90))
            } else {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    LALiveArc(start: state.start, end: state.end, color: span.color, width: arc)
                        // The window's end needs no edge of its own: every ring sits in LAEnds, whose live copy goes then.
                        .mask { LAGate(from: span.from, until: span.until == state.end ? nil : span.until).frame(width: 110, height: 110) }
                }
            }
        }
        .frame(width: 90, height: 90)
        .scaleEffect(size / 90)
        .frame(width: size, height: size)
    }
}

/// The stretch of a window a copy of the time left is ever seen in: before the last half hour, in it, or both.
enum LATimePart { case all, early, late }

extension View {
    /// Shown from `from` until `until` (LAGate) — or, `never`, not drawn at all (the other copy of the time left draws
    /// it, so the line's room is the same). iOS ends a card whose archive passes ~2 MB, and every edge still to come
    /// (five timer bars) adds to it; on an island iPhone the island's views count too: a fresh card was 2.3 MB and iOS
    /// removed it within 2 s (chronod: archiveTooLarge, 2026-10-16). Draw and gate only what can show.
    @ViewBuilder func shown(from: Date?, until: Date?, never: Bool = false) -> some View {
        if !never { mask { LAGate(from: from, until: until) } }
    }
}

/// Visible from `from` (nil = from the start) until `until` (nil = for good), by itself: each edge is a stock timer bar
/// over a 1 s interval stretched over the whole area, thresholded to all-or-nothing.
struct LAGate: View {
    let from: Date?
    let until: Date?
    /// How a look gives way to the next when its time comes (owner, 2026-10-12: show both): 0 a 1 s wipe left to right
    /// (the stock bar filling), 1 an instant flip, 2 a fade in 5 instant steps over 0.15 s (a blurred, soft-edged sweep
    /// froze on the Lock Screen: the blur stops the bar's live fill). App group `la.gateStyle`.
    static let styleKey = "la.gateStyle"
    /// Unset = the fade (owner: "I think I like fade").
    static var style: Int {
        let g = UserDefaults(suiteName: SharedStore.appGroup)
        return g?.object(forKey: styleKey) == nil ? 2 : g?.integer(forKey: styleKey) ?? 2
    }
    private static let steps = 5
    private static let fadeLength: TimeInterval = 0.15   // owner: 0.15 s (1.5, 0.5, 0.25 read as lag)
    /// The island's views flip (`laInstantGates`): fewer timer bars in the card's archive.
    @Environment(\.laInstantGates) private var instant

    /// When the last half hour's red begins: 1 s after the time left turns "30" (owner: white "30" fades to red "30").
    /// The words under an hour come from the per-second countdown (LAMinuteWords), which reads "30" from end − 30:59, so
    /// the red starts a second later (owner: "30 for 1 second"). iOS's own minute text turned 1–4 s late.
    static func lastHalf(of end: Date) -> Date { end.addingTimeInterval(-31 * 60 + 2) }

    var body: some View {
        // An edge already passed when this is drawn is drawn solid: its stock bar re-filled on every update, sweeping a
        // look across the card (owner). Only edges still to come are bars (empty until then, so nothing moves).
        let now = Date()
        let style = instant ? 1 : Self.style
        Group {
            if let from, from > now {
                if style == 2 { fadeIn(from, now: now) } else { edge(from, fill: .white, ground: .black, lift: -0.35, span: style == 1 ? 0.05 : 1) }
            } else { Color.white }
        }
        .mask {
            if let until {
                if until > now {
                    if style == 2 { fadeOut(until, now: now) } else { edge(until, fill: .black, ground: .white, lift: 0.2, span: style == 1 ? 0.05 : 1) }
                } else { Color.clear }
            } else { Color.white }
        }
    }

    /// Coverage rising k/N as the N layers switch on one by one (layer i at 1/(N−i+1) opacity — "over" adds up linearly).
    private func fadeIn(_ t: Date, now: Date) -> some View {
        let n = Self.steps, dt = Self.fadeLength / Double(n)
        return ZStack {
            ForEach(1...n, id: \.self) { i in
                let at = t.addingTimeInterval(Double(i - 1) * dt)
                Group {
                    if at > now { edge(at, fill: .white, ground: .black, lift: -0.35, span: 0.05) } else { Color.white }
                }
                .opacity(1 / Double(n - i + 1))
            }
        }
    }

    /// Coverage falling 1 − k/N: layer j (opacity 1/j) switches off j-th.
    private func fadeOut(_ t: Date, now: Date) -> some View {
        let n = Self.steps, dt = Self.fadeLength / Double(n)
        return ZStack {
            ForEach(1...n, id: \.self) { j in
                let at = t.addingTimeInterval(Double(j - 1) * dt)
                Group {
                    if at > now { edge(at, fill: .black, ground: .white, lift: 0.2, span: 0.05) } else { Color.clear }
                }
                .opacity(1 / Double(j))
            }
        }
    }

    private func edge(_ t: Date, fill: Color, ground: Color, lift: Double, span: TimeInterval) -> some View {
        GeometryReader { geo in
            ZStack {
                ground
                ProgressView(timerInterval: t...t.addingTimeInterval(span), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(fill)
                    .labelsHidden()
                    .frame(width: geo.size.width)
                    .scaleEffect(x: 1, y: max(geo.size.height, 4) * 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .environment(\.colorScheme, .light)   // in dark the stock bar's tint resolves differently
            .compositingGroup()
            .brightness(lift)
            .contrast(3)
            .luminanceToAlpha()
        }
    }
}


// MARK: - Excused from prayer (haid / after childbirth; owner, 2026-10-13, plan board/mocks/excused-days)

/// One stretch she was (or is) excused from prayer. A prayer whose window touches it can't be marked and isn't asked of
/// her; the app's "counted days" leave its prayer days out of streaks and stats (Excused.swift).
struct ExcusedRange: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case haid, nifas }
    var id = UUID()
    var kind: Kind
    var start: Date
    /// Her estimate: the check-ins are planned from it. Nothing ends by itself.
    var expectedEnd: Date
    /// Set when she ends it; nil while it runs.
    var end: Date?
    /// Zikr reminders pause too (her choice; zikr streaks never break on excused days either way).
    var pauseZikr: Bool

    /// A prayer window [from, to) she's excused from: it overlaps this stretch, and she was still excused when it ended.
    /// Ending it during a prayer's time makes that prayer due (it can be marked), as the fiqh has it.
    func covers(from: Date, to: Date) -> Bool { to > start && from < (end ?? .distantFuture) && (end.map { $0 >= to } ?? true) }
}

/// The one record (app group, JSON): every range, the running one last. Only the app writes it; the widget and the
/// intents read it. Read it once per loop (`ranges`) — each read decodes.
enum Excused {
    static let key = "excused.ranges"
    static let changed = Notification.Name("ExcusedChanged")

    /// Decoded once per change, not per call: every prayer row, the circle (≈10×/s while idle) and the widget's rows ask
    /// (perf-recheck, 2026-10-14). The stored bytes are compared — cheap — so a change from any process is seen at once.
    static var ranges: [ExcusedRange] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        rangesLock.lock(); defer { rangesLock.unlock() }
        if let cached = rangesCache, cached.data == data { return cached.list }
        let list = (try? JSONDecoder().decode([ExcusedRange].self, from: data)) ?? []
        rangesCache = (data, list)
        return list
    }
    private static let defaults = UserDefaults(suiteName: SharedStore.appGroup)
    private static let rangesLock = NSLock()
    nonisolated(unsafe) private static var rangesCache: (data: Data, list: [ExcusedRange])?
    static var current: ExcusedRange? { ranges.last(where: { $0.end == nil }) }
    static var isActive: Bool { current != nil }

    /// A prayer window she's excused from (marking it does nothing).
    static func covers(start: Date, end: Date, in list: [ExcusedRange] = ranges) -> Bool {
        list.contains { $0.covers(from: start, to: end) }
    }

    /// Written only when it changed: every app-group write invalidates bound @AppStorage (CLAUDE.md).
    static func save(_ list: [ExcusedRange]) {
        guard list != ranges, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: key)
    }
}

/// Excused, and someone tried to mark a prayer (she may be done and forgot): shukr opens and asks whether she's back,
/// never a silent no (owner). The flag is read by the Salah page (`openFromWidgetFlags`).
enum ExcusedResume {
    static let askKey = "excused.askResume"
    static func ask() {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: askKey)
        DeepLinkSignal.post()
    }
}

/// The Prayers widget's check and rows while excused: opens shukr to "Prayers are paused · I'm back".
struct ExcusedResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Prayers"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        ExcusedResume.ask()
        return .result()
    }
}
