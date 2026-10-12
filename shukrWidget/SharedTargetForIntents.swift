
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
            DeepLinkSignal.post()
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


#if DEBUG
import ActivityKit
/// Which prayers get a Live Activity for their window (owner, 2026-10-11: its own setting, not the notifications' —
/// "two very different features"). App group, on by default for all five.
enum LiveActivityPrefs {
    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static func key(_ prayer: String) -> String { "liveActivity.\(prayer)" }
    static func isOn(_ prayer: String) -> Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: key(prayer)) as? Bool ?? true
    }
}

/// DEBUG Live Activity research (MY4R, 2026-10-11): a stand-in prayer window, and a log both processes write.
struct LATestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
        var symbol: String = "sun.max.fill"
        var markedAt: Date? = nil
        /// The app's look for this window (its light / dark / follows-the-sun setting, worked out by the app when it
        /// schedules); nil = the phone's.
        var dark: Bool? = nil
    }
    var n: Int
}

/// The test window's Mark prayed (runs in shukr's process): marks the stand-in window (never a real prayer), times a
/// location fix (S9FJ), refills the schedule. The app target supplies `LATestHooks.mark`.
struct LATestMarkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark test window prayed"
    static var isDiscoverable = false
    @Parameter(title: "Window") var n: Int
    init() {}
    init(n: Int) { self.n = n }
    func perform() async throws -> some IntentResult {
        LATestLog.add("Mark prayed tapped on #\(n)")
        await LATestHooks.mark?(n)
        return .result()
    }
}

/// After marking: the post-salah actions open shukr (the real routing comes with the feature).
struct LATestOpenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open after a test window"
    static var isDiscoverable = false
    static var openAppWhenRun = true
    @Parameter(title: "What") var what: String
    @Parameter(title: "Window") var n: Int
    init() {}
    init(what: String, n: Int) { self.what = what; self.n = n }
    func perform() async throws -> some IntentResult {
        LATestLog.add("\(what) tapped on #\(n) (opens shukr)")
        await LATestHooks.open?(n, what)
        return .result()
    }
}

enum LATestHooks {
    nonisolated(unsafe) static var mark: ((Int) async -> Void)?
    nonisolated(unsafe) static var open: ((Int, String) async -> Void)?
}

enum LATestLog {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.betternorms.shukr.shukrWidget")?
            .appendingPathComponent("Library/Application Support/la-test.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.laTestLog")
    static func add(_ line: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss.SSS"
        let text = "\(f.string(from: Date()))  [\(Bundle.main.bundleURL.pathExtension == "appex" ? "ext" : "app")] \(line)\n"
        print("🟣 \(line)")
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
#endif

#if DEBUG
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
    var cardSurfaceGrey: Double = 0.14
    // Ring
    var ringSize: Double = 69
    var ringArcDiameter: Double = 0.83      // of the ring size
    var ringBandWidth: Double = 7          // at the 90 pt design size
    var ringArcWidth: Double = 5.5          // at the 90 pt design size
    var ringSymbolSize: Double = 17
    var ringBandLift: Double = 0.11
    // Text
    var titleSize: Double = 19
    var timeLeftSize: Double = 12
    var endsSize: Double = 10
    var lineSpacing: Double = 2
    var textOffsetY: Double = 0
    // Glow
    var glowStrength: Double = 0.19
    var glowReach: Double = 0.52
    var glowCentreX: Double = 0.11
    var glowCentreY: Double = 0.73
    // Buttons
    var buttonSize: Double = 44
    var buttonSymbolSize: Double = 18
    var buttonStackGap: Double = 8
    var buttonOffsetX: Double = 0
    var buttonSymbolOpacity: Double? = nil   // nil = 0.65: the symbols a little dull, not stark white (owner)
    var symbolOpacity: Double { get { buttonSymbolOpacity ?? 0.65 } set { buttonSymbolOpacity = newValue } }
    // 15 s bar
    var barSideInset: Double = 8
    var barBottomInset: Double = 0
    var barThickness: Double = 0.5
    // Dynamic Island (opened up)
    var islandRingSize: Double = 55
    var islandTitleSize: Double = 18
    var islandLineSize: Double = 11
    var islandButtonSize: Double = 38
    var islandTimeSizeOpt: Double? = nil        // nil = 17: the time left above the island's button
    /// The expanded island's layout (nil = 1), to compare on a phone (the simulator doesn't draw the island): 0 the ring beside the
    /// camera, the name under it (center region) · 1 ring + name together beside the camera, below it if too wide ·
    /// 2 ring + name and time + button as one row under the camera (leading / trailing with priority).
    var islandLayout: Int? = nil
    var islandTimeSize: Double { get { islandTimeSizeOpt ?? 17 } set { islandTimeSizeOpt = newValue } }
    // How the time left is written — iOS's self-updating formats only (a Live Activity has no timeline): 0 "1 hour,
    // 39 minutes" (offset) · 1 "1 hr, 39 min" (relative; under an hour it ticks seconds) · 2 "1:39" · 3 "1:39:12" ·
    // 4 (nil, the default — owner: no seconds) relative over an hour, then "59 minutes", then "under a minute", switched
    // by timer gates. Optional so a saved tuning without it still decodes (renamed from timeLeftStyle so earlier picks drop).
    var timeLeftFormat: Int? = nil

    static let key = "la.tuning2"   // 2: his sim tuning became the defaults; earlier saved tunings are left behind
    static var current: LATuning {
        guard let data = UserDefaults(suiteName: SharedStore.appGroup)?.data(forKey: key),
              let t = try? JSONDecoder().decode(LATuning.self, from: data) else { return LATuning() }
        return t
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults(suiteName: SharedStore.appGroup)?.set(data, forKey: Self.key) }
    }
    var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// The app's soft look, dark (the card is always dark — owner).
enum LASoft {
    static func surface(_ t: LATuning) -> Color { Color(white: t.cardSurfaceGrey) }
    static let shade = Color.black.opacity(0.75)
    static let light = Color.white.opacity(0.06)
    /// The island is black: its soft pieces are a dark grey raised off it.
    static let island = Color(white: 0.11)
}

/// The running look until the window ends, the ended look from then on — by itself (timer gates), because iOS's stale
/// flag didn't flip at the stale date. Marked, or already stale: just that one look.
struct LAEnds<Content: View>: View {
    let state: LATestAttributes.ContentState
    let stale: Bool
    @ViewBuilder let content: (_ ended: Bool) -> Content
    var body: some View {
        if state.markedAt != nil {
            content(false)
        } else if stale {
            content(true)
        } else {
            ZStack {
                content(false).mask { LAGate(from: nil, until: state.end) }
                content(true).mask { LAGate(from: state.end, until: nil) }
            }
        }
    }
}

/// The Lock Screen card (always dark).
struct LALockCard: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let stale: Bool
    var t = LATuning.current
    var body: some View {
        LAEnds(state: state, stale: stale) { e in LALockCardBody(state: state, n: n, ended: e, t: t) }
            .environment(\.colorScheme, .dark)
    }
}

/// Look D's layout in the soft look: the soft ring with the prayer's symbol on the left, the name and two lines beside
/// it, the soft round buttons on the right, the score colour glowing out from the ring; once prayed, the 15 s bar.
struct LALockCardBody: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    var body: some View {
        HStack(spacing: t.gapRingToText) {
            LASideRing(state: state, ended: ended, size: t.ringSize, symbolSize: t.ringSymbolSize, onIsland: false, t: t)
            LANameLines(state: state, ended: ended, big: true, t: t).offset(y: t.textOffsetY)
            Spacer(minLength: 0)
            LAGlyphs(state: state, n: n, ended: ended, size: t.buttonSize, onIsland: false, t: t).offset(x: t.buttonOffsetX)
        }
        .padding(.horizontal, t.cardPaddingSides).padding(.vertical, t.cardPaddingTopBottom)
        .frame(minHeight: t.cardMinHeight)
        // Our own solid surface under the glow: iOS draws `activityBackgroundTint` see-through (the wallpaper turned a red
        // glow pink on his phone).
        .background {
            ZStack {
                LASoft.surface(t)
                LAWash(state: state, ended: ended, t: t)
            }
        }
        .overlay(alignment: .bottom) {
            LADismissBar(state: state).scaleEffect(x: 1, y: t.barThickness)
                .padding(.horizontal, t.barSideInset).padding(.bottom, t.barBottomInset)
        }
        .activityBackgroundTint(LASoft.surface(t))
        .activitySystemActionForegroundColor(.primary)
    }
}

/// The soft ring with the prayer's symbol inside (a ✓ in its score colour once prayed).
struct LASideRing: View {
    let state: LATestAttributes.ContentState
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
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The name, then: the time left (red in the last half hour) + "ends 6:48 PM"; prayed: "Prayed 4:31 PM" +
/// "Perfect · 100"; ended: "Asr ended" + "6:48 PM · not marked".
struct LANameLines: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let big: Bool
    let t: LATuning
    var body: some View {
        let title = big ? t.titleSize : t.islandTitleSize
        let line = big ? t.timeLeftSize : t.islandLineSize
        let small = big ? t.endsSize : t.islandLineSize
        VStack(alignment: .leading, spacing: t.lineSpacing) {
            Text(ended ? "\(state.label) ended" : state.label)
                .font(.system(size: title, weight: .light))
                .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if let at = state.markedAt {
                let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: line)).foregroundStyle(.primary)
                Text("\(PrayerScoring.grade(for: score).rawValue) · \(Int((score * 100).rounded()))")
                    .font(.system(size: small)).foregroundStyle(.secondary)
            } else if ended {
                Text("\(state.end.formatted(date: .omitted, time: .shortened)) · not marked")
                    .font(.system(size: line)).foregroundStyle(.secondary)
            } else if !big {
                Text("ends \(state.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: line)).foregroundStyle(.secondary)
            } else {
                let lastHalf = state.end.addingTimeInterval(-30 * 60)
                ZStack(alignment: .leading) {
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard).foregroundStyle(.primary)
                        .mask { LAGate(from: nil, until: lastHalf) }
                    LATimeLeft(end: state.end, style: t.timeLeftFormat ?? LATimeLeft.standard).foregroundStyle(.red).fontWeight(.semibold)
                        .mask { LAGate(from: lastHalf, until: nil) }
                }
                .font(.system(size: line))
                if big {
                    Text("ends \(state.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: small)).foregroundStyle(.secondary)
                }
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
            ZStack(alignment: .leading) {
                Text("\(Text(end, style: .relative))\(left)").mask { LAGate(from: nil, until: hour) }
                Text("\(Text(.currentDate, format: .offset(to: end, allowedFields: [.minute], maxFieldCount: 1, sign: .never)))\(left)")
                    .mask { LAGate(from: hour, until: minute) }
                Text("under a minute\(left)").mask { LAGate(from: minute, until: nil) }
            }
        case 1: Text("\(Text(end, style: .relative))\(left)")
        case 2: Text("\(Text(.currentDate, format: .timer(countingDownIn: Date.now..<max(end, .now), maxPrecision: .seconds(60))))\(left)")
        case 3: Text("\(Text(timerInterval: Date.now...max(end, .now), countsDown: true))\(left)")
        default: Text("\(Text(.currentDate, format: .offset(to: end, allowedFields: [.hour, .minute], maxFieldCount: 2, sign: .never)))\(left)")
        }
    }
}

/// After Mark prayed: how long until the card goes (15 s) — a thin sage bar, full at the tap, emptying right to left.
struct LADismissBar: View {
    let state: LATestAttributes.ContentState
    static let seconds: TimeInterval = 15
    var body: some View {
        if let at = state.markedAt {
            ProgressView(timerInterval: at...at.addingTimeInterval(Self.seconds), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(Color(red: 0.43, green: 0.62, blue: 0.5))
                .labelsHidden()
        }
    }
}

/// The island's small right side: empty — the ring says enough — until the last half hour: "27m" in red (owner).
struct LACompactTrailing: View {
    let state: LATestAttributes.ContentState
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
/// are words), so this is the stock "27:08" timer cut to its minutes digits (clipped to the width of "00", then "0" under
/// ten minutes — a timer gate swaps them) with an "m" after it. Nothing before the last half hour.
struct LAMinutesLeft: View {
    let end: Date
    var body: some View {
        let ten = end.addingTimeInterval(-10 * 60), one = end.addingTimeInterval(-60)
        ZStack(alignment: .trailing) {
            digits("00").mask { LAGate(from: nil, until: ten) }
            digits("0").mask { LAGate(from: ten, until: one) }
            Text("<1m").mask { LAGate(from: one, until: nil) }
        }
        .monospacedDigit()
    }
    private func digits(_ room: String) -> some View {
        HStack(spacing: 0) {
            Text(room).hidden()
                .overlay(alignment: .leading) {
                    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                        .multilineTextAlignment(.leading)
                        .fixedSize()
                }
                .clipped()
            Text("m")
        }
    }
}

/// The island's time left over its button: only in the last half hour, "27m" in red (owner: the ring says enough before).
struct LAIslandTime: View {
    let end: Date
    var body: some View {
        LAMinutesLeft(end: end).foregroundStyle(.red).fontWeight(.semibold)
            .mask { LAGate(from: end.addingTimeInterval(-30 * 60), until: nil) }
    }
}

/// The island's left side: the soft ring.
struct LAIslandLeading: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        // No glow: the island is always black and each region clips to its own box (the glow came out a square).
        LASideRing(state: state, ended: ended, size: t.islandRingSize, symbolSize: t.islandRingSize * 0.26, onIsland: true, t: t)
    }
}

/// The island's ring with the name beside it (layouts 1 and 2 — Frank's mock).
struct LAIslandRingAndName: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let t: LATuning
    var body: some View {
        HStack(spacing: 12) {
            LAIslandLeading(state: state, ended: ended, t: t)
            LANameLines(state: state, ended: ended, big: false, t: t)
        }
    }
}

/// The island's right side: the time left over the mark button (Frank's mock); prayed → camera over tasbih.
struct LAIslandTrailing: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    let t: LATuning
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if state.markedAt == nil && !ended {
                LAIslandTime(end: state.end).font(.system(size: t.islandTimeSize, weight: .regular))
            }
            LAGlyphs(state: state, n: n, ended: ended, size: t.islandButtonSize, onIsland: true, t: t)
                .padding(4)   // the soft disc's shadow, inside the region (it clips)
        }
    }
}

/// The right side: the soft round buttons — a ✓ marks it (owner: the circle looked odd); prayed → camera over the zikr beads;
/// ended → a grey dashed circle (Qaza; never red — owner).
struct LAGlyphs: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    let size: Double
    let onIsland: Bool
    let t: LATuning
    var body: some View {
        if state.markedAt != nil {
            // On the Lock Screen the pair fits the running card's row (the ring or the one button, whichever is taller), so
            // marking never makes the card taller (owner).
            let pair = onIsland ? size * 0.82 : min(size * 0.82, (max(t.ringSize, t.buttonSize) - t.buttonStackGap) / 2)
            VStack(spacing: t.buttonStackGap) {
                LARoundButton(intent: LATestOpenIntent(what: "Photo", n: n), symbol: "camera", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
                LARoundButton(intent: LATestOpenIntent(what: "Tasbih", n: n), symbol: "circle.hexagonpath", size: pair, symbolSize: min(t.buttonSymbolSize * 0.9, pair * 0.5), onIsland: onIsland, t: t)
            }
        } else if ended {
            LARoundButton(intent: LATestMarkIntent(n: n), symbol: "circle.dashed", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland, dim: true, t: t)
        } else {
            LARoundButton(intent: LATestMarkIntent(n: n), symbol: "checkmark", size: size, symbolSize: t.buttonSymbolSize, onIsland: onIsland, t: t)
        }
    }
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
    let t: LATuning
    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .light))
                .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(t.symbolOpacity)))
                .frame(width: size, height: size)
                .background {
                    if onIsland {
                        Circle().fill(LASoft.island)
                            .shadow(color: .black, radius: 3, x: 1.5, y: 1.5)
                            .shadow(color: .white.opacity(0.09), radius: 3, x: -1.5, y: -1.5)
                            .shadow(color: .white.opacity(t.ringBandLift * 0.6), radius: 1.5, x: -1, y: -1)
                    } else {
                        Circle().fill(LASoft.surface(t))
                            .shadow(color: LASoft.shade, radius: 3, x: 1.5, y: 1.5)
                            .shadow(color: LASoft.light, radius: 3, x: -1.5, y: -1.5)
                    }
                }
        }
        .buttonStyle(LAPressStyle())
    }
}

/// The score colour glowing out from the ring (Look D's halo), in the colour of the grade now (changes by itself);
/// prayed: its score's colour; ended: none.
struct LAWash: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let t: LATuning
    /// The island: a round glow this wide, centred on the ring (the island has no background of ours to fill).
    var islandRadius: Double? = nil
    var body: some View {
        if let at = state.markedAt {
            wash(PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at)))
        } else if !ended {
            ZStack {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    wash(span.color).mask { LAGate(from: span.from, until: span.until) }
                }
            }
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
    static func spans(_ s: LATestAttributes.ContentState) -> [Span] {
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
    var body: some View {
        Circle()
            .stroke(surface ?? LASoft.surface(t), lineWidth: width)
            .shadow(color: LASoft.shade, radius: width * 0.6, x: width * 0.3, y: width * 0.3)
            .shadow(color: LASoft.light, radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
            .shadow(color: .white.opacity(t.ringBandLift), radius: width * 0.5, x: -width * 0.25, y: -width * 0.25)
    }
}

/// The live arc (the widget's `LiveArc`): a round arc with a glow, shown up to now by the stock timer ring used as a mask.
struct LALiveArc: View {
    let start: Date
    let end: Date
    let color: Color
    let width: Double
    /// In the app (the tuner's preview) the stock timer ring is a spinner, not a gauge: there the arc is drawn up to now
    /// (once a second); on the Lock Screen it's the system's own, self-updating mask.
    private static let inApp = Bundle.main.bundleURL.pathExtension != "appex"
    var body: some View {
        if Self.inApp {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let f = min(max(ctx.date.timeIntervalSince(start) / max(end.timeIntervalSince(start), 1), 0), 1)
                Circle().trim(from: 0, to: f)
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.45), radius: 3)
            }
        } else {
            systemArc
        }
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
    let state: LATestAttributes.ContentState
    let ended: Bool
    let size: Double
    var onIsland = false
    let t: LATuning
    var body: some View {
        let band = t.ringBandWidth, arc = t.ringArcWidth
        ZStack {
            LASoftBand(width: band, t: t, surface: onIsland ? LASoft.island : nil)
            if let at = state.markedAt {
                let c = PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at))
                Circle().stroke(c, style: StrokeStyle(lineWidth: arc, lineCap: .round))
                    .shadow(color: c.opacity(0.45), radius: 3)
            } else if ended {
                let gap = CGFloat.pi * 90 / 8
                Circle().stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: arc, lineCap: .round, dash: [gap * 0.55, gap * 0.45]))
                    .rotationEffect(.degrees(-90))
            } else {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    LALiveArc(start: state.start, end: state.end, color: span.color, width: arc)
                        .mask { LAGate(from: span.from, until: span.until).frame(width: 110, height: 110) }
                }
            }
        }
        .frame(width: 90, height: 90)
        .scaleEffect(size / 90)
        .frame(width: size, height: size)
    }
}

/// Visible from `from` (nil = from the start) until `until` (nil = for good), by itself: each edge is a stock timer bar
/// over a 1 s interval stretched over the whole area, thresholded to all-or-nothing.
struct LAGate: View {
    let from: Date?
    let until: Date?
    var body: some View {
        // An edge already passed when this is drawn is drawn solid: its stock bar re-filled on every update, sweeping a
        // look across the card (owner). Only edges still to come are bars (empty until then, so nothing moves).
        let now = Date()
        Group {
            if let from, from > now { edge(from, fill: .white, ground: .black, lift: -0.35) } else { Color.white }
        }
        .mask {
            if let until { if until > now { edge(until, fill: .black, ground: .white, lift: 0.2) } else { Color.clear } } else { Color.white }
        }
    }

    private func edge(_ t: Date, fill: Color, ground: Color, lift: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                ground
                ProgressView(timerInterval: t...t.addingTimeInterval(1), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
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
#endif
