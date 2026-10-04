
// MARK: - Intents

import AppIntents
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
            let config = ModelConfiguration(schema: schema, url: url)
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
        let t0 = ContinuousClock.now
        WidgetPerf.log("mark \(prayerName) start")
        SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd)
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

        let group = UserDefaults(suiteName: appGroup)
        group?.set(true, forKey: widgetWroteStoreKey)
        // The app rescores that day and its streaks (audit B5: every mark made outside the app, not only the list's —
        // a late mark of yesterday's Isha from a notification left yesterday's score stale).
        group?.set(start.timeIntervalSince1970, forKey: WidgetListMarks.markedDayKey)
        WidgetCenter.shared.reloadAllTimelines()   // both prayer widgets
        return true
    }

    /// Posted by the app's own notification handler after "I already prayed" lands while the app is in front
    /// (audit B7): the page reconciles at once instead of at the next activation.
    static let markedElsewhere = Notification.Name("shukr.markedElsewhere")
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

/// Widget → one zikr task: the Zikr page with that task's circle in the middle, ready to tap.
struct OpenZikrTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Zikr Task"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        store?.set(taskID, forKey: "widgetZikrTask")
        store?.set(true, forKey: "widgetTasbeeh")
        return .result()
    }
}

/// Widget → the Daily Ayah page (one-shot flag read on activation, like the compass one).
struct OpenDailyAyahIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Daily Ayah"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetDailyAyah")
        return .result()
    }
}

/// Widget times list (`WidgetListMarks`): a started row marks its prayer,
/// scored at the tap like the corner check, and the list stays up another `openFor` so the filled
/// circle is seen (the mark reloads the timeline).
struct MarkFromListIntent: AppIntent {
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
        if !SharedStore.markPrayerComplete(named: prayerName, start: prayerStart, end: prayerEnd) {
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
        return .result()
    }
}

/// Widget → the 99 Names page.
struct OpenNamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 99 Names"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetNames")
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

    /// Parameters for a method number (the Settings / setup picker's tags) and a school (1 Hanafi).
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
    

    static func calculateAlarmDescription() throws -> (description: String, time: Date) {
        print("hellow")
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let alarmEnabled = store.bool(forKey: "alarmEnabled")
        let alarmOffsetMinutes = store.integer(forKey: "alarmOffsetMinutes")
        // Unset = true (before / the start), the defaults Settings and the setup show; `bool(forKey:)`
        // read them as false, so an untouched rule came out "at sunrise".
        let alarmIsBefore = store.object(forKey: "alarmIsBefore") as? Bool ?? true
        let alarmIsFajr = store.object(forKey: "alarmIsFajr") as? Bool ?? true
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

    /// shukr sets the Fajr alarm itself (AlarmKit, iOS 26.1+): this Shortcut step fails on purpose,
    /// so the shared Shortcut stops here and its next step ("Create Alarm") never runs — no second
    /// alarm, and nobody has to delete their automation.
    struct SetByShukrError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "shukr sets your Fajr alarm itself now, so this automation doesn't need to. You can turn it off in Shortcuts."
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        if let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"), group.bool(forKey: "alarmKitActive") {
            // AlarmKit's permission taken away while the app wasn't running (audit B13): the Shortcut takes over
            // again, instead of neither setting an alarm.
            var permissionGone = false
            #if canImport(AlarmKit)
            if #available(iOS 26.1, *), AlarmManager.shared.authorizationState != .authorized { permissionGone = true }
            #endif
            if permissionGone { group.set(false, forKey: "alarmKitActive") } else { throw SetByShukrError() }
        }
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
