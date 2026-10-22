//
//  SharedStore.swift
//  shukr (app and widget extension)
//
//  The shared SwiftData store and the raw-SQLite salvage of a set-aside one.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 1).
//

import Foundation
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
    /// The app runs on an in-memory store (StoreFallback, shukrApp.swift): set only in the app's process, never in the
    /// widget extension's. Then the app's own process doesn't open the on-disk store either — a banner's "I already
    /// prayed" or a widget mark run in the app wrote a file the app no longer reads, so the widget and the app told
    /// different stories (mark audit #4). Outside marks made in the app fail cleanly instead, like "store unavailable".
    static var appOnMemoryStore = false
    static var widgetContainer: ModelContainer? {
        if appOnMemoryStore { return nil }
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

        // Prayers are keyed by name + prayer day (2.8.0's `dayKey`, not the calendar day: an Isha that starts after
        // midnight belongs to the day before — by calendar day an old 00:30 Isha's mark landed on the next day's Isha,
        // mark audit #10). The shared store has its own rows for days since the update; keep those, except where the
        // old row is completed and the new one isn't.
        func key(_ prayer: PrayerModel) -> String { "\(prayer.name)|\(prayer.dayKey)" }
        var prayerByKey: [String: PrayerModel] = [:]
        for prayer in try dst.fetch(FetchDescriptor<PrayerModel>()) { prayerByKey[key(prayer)] = prayer }
        for old in try src.fetch(FetchDescriptor<PrayerModel>()) {
            if let existing = prayerByKey[key(old)] {
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
            prayerByKey[key(new)] = new
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
        new.markKind = old.markKind
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
    /// The app's last good fix itself, [latitude, longitude, accuracy m, time] (outside-mark location C, Frank-reviewed,
    /// 2026-10-22): saved on every fix ≤ 200 m the app gets (`saveFix`), and stamped again as it goes to the background
    /// (`stampFix`). Its own key: lastLatitude / lastLongitude move only at a location pass (≥ 500 m or 10 min), so a time
    /// written beside them alone would have called a spot up to 500 m old fresh.
    static let lastFixKey = "lastFix"

    /// A fix the app got (not a picked city): kept when it's ≤ 200 m, and written only on change — a 10 m move, a better
    /// accuracy, or a minute on (every app-group write invalidates bound @AppStorage).
    static func saveFix(_ l: CLLocation) {
        guard l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 200, let store = UserDefaults(suiteName: appGroup) else { return }
        if let old = store.array(forKey: lastFixKey) as? [Double], old.count == 4 {
            let moved = CLLocation(latitude: old[0], longitude: old[1]).distance(from: l)
            if moved < 10, l.horizontalAccuracy >= old[2] - 5, l.timestamp.timeIntervalSince1970 - old[3] < 60 { return }
        }
        store.set([l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy, l.timestamp.timeIntervalSince1970],
                  forKey: lastFixKey)
    }

    /// The app is going to the background with its fine updates running. `lastSeen`: the last fix iOS handed over this
    /// visit (any accuracy), or nil. With a 50 m filter no newer fix means the phone was still within 50 m of it — so when
    /// it's within 50 m of the saved fix, that one is good as of now (a phone sitting still gets no fixes at all). Says
    /// what it did, for the mark log.
    @discardableResult
    static func stampFix(lastSeen: CLLocation?, now: Date = Date()) -> String {
        guard let store = UserDefaults(suiteName: appGroup), var f = store.array(forKey: lastFixKey) as? [Double], f.count == 4 else {
            return "shared fix not stamped: none saved yet"
        }
        guard let lastSeen else { return "shared fix not stamped: no fix this visit" }
        let off = Int(CLLocation(latitude: f[0], longitude: f[1]).distance(from: lastSeen))
        guard off <= 50 else {
            return "shared fix not stamped: the phone was last seen \(off) m from it (±\(Int(lastSeen.horizontalAccuracy)) m)"
        }
        guard now.timeIntervalSince1970 - f[3] > 30 else { return "shared fix already fresh (±\(Int(f[2])) m)" }
        f[3] = now.timeIntervalSince1970
        store.set(f, forKey: lastFixKey)
        return "shared fix stamped as now (±\(Int(f[2])) m; last seen \(off) m from it)"
    }

    /// A picked city: its centre is not where a prayer was prayed (audit B10).
    static func clearFix() {
        let store = UserDefaults(suiteName: appGroup)
        store?.removeObject(forKey: lastFixKey)
        store?.removeObject(forKey: lastFixAtKey)
    }

    /// The last real fix, while it's recent (30 min; audit B10): a widget / watch mark records where it was prayed from
    /// this. A stale fix, or a picked city's centre, put prayers at a mosque they weren't near (a Friday Dhuhr became Jumu'ah).
    static func lastKnownLocation() -> CLLocation? {
        guard let store = UserDefaults(suiteName: appGroup) else { return nil }
        if let f = store.array(forKey: lastFixKey) as? [Double], f.count == 4 {
            guard Date().timeIntervalSince1970 - f[3] < 30 * 60 else { return nil }
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: f[0], longitude: f[1]), altitude: 0,
                              horizontalAccuracy: f[2], verticalAccuracy: -1, timestamp: Date(timeIntervalSince1970: f[3]))
        }
        // Before this build saved its first fix: the old keys (lastFixAt over lastLatitude / lastLongitude).
        let at = store.double(forKey: lastFixAtKey)
        guard at > 0, Date().timeIntervalSince1970 - at < 30 * 60 else { return nil }
        let lat = store.double(forKey: "lastLatitude"), lon = store.double(forKey: "lastLongitude")
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
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

        // Prayers: a completed row with no live counterpart (name + prayer day) is added whole; a live
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
                    // The map's own key (name + prayer day): a calendar-day number never matched it, so every completed
                    // row was added again beside its live one (mark audit #2).
                    let key = "\(name)|\(PrayerDay.key(forRow: name, startingAt: start))"
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
