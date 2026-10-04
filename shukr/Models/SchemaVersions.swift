//
//  SchemaVersions.swift
//  shukr
//
//  Schema version + the data pass that goes with it. Compiled into the app AND the widget
//  (Models/ is in both targets).
//
//  How the store is upgraded: NOT with a SchemaMigrationPlan. The V1→V2 change is lightweight
//  at the store level (`@Attribute(originalName:)` renames, new columns with defaults, new
//  optional relationships), so SwiftData migrates it automatically when the store is opened
//  with the current schema — the same mechanism that has carried this app's store through
//  every earlier model change. A staged plan was tried first: it needs the store's entity hashes
//  to match a hand-copied V1 schema, which held on the iOS 18.5 simulator and failed on the
//  owner's phone with CoreData 134504 "Cannot use staged migration with an unknown model
//  version". Inferred migration has no such dependency.
//
//  The data work a migration stage would have done (seed built-ins, link tasks and sessions to
//  mantra rows, number tasks) is `ShukrV2DataPass`, run by the app once per store (flag in the
//  app-group defaults) and again after a legacy import. It is idempotent.
//
//  Only the app opens a store that isn't at the current version: `SharedStore.widgetContainer`
//  checks `storeIsCurrentVersion` first, so the widget never triggers a migration.
//

import Foundation
import SwiftData

/// The current schema. Opening a store with it stamps "2.1.0" into its metadata, which is what
/// the widget's `storeIsCurrentVersion` looks for. Bump the version when the models change.
enum ShukrSchemaV2: VersionedSchema {
    /// 2.1.0 (2026-09-25): `MantraModel.quickAddStep` (a defaulted Int — lightweight).
    /// 2.2.0 (2026-09-26): `PrayerModel.mosqueName` (optional String — lightweight).
    /// 2.3.0 (2026-09-26): `PrayerModel.recorded…` (optional — lightweight).
    /// 2.4.0 (2026-09-27): `TaskModel.customName` + the reminder fields (optional — lightweight).
    /// 2.5.0 (2026-09-27): `MantraModel.imageData` / `audioData` (optional, external storage).
    /// 2.6.0 (2026-09-27): `MantraModel.builtInID` (optional) — built-ins are marked on the row,
    /// not guessed from the name.
    /// 2.7.0 (2026-09-30): `SessionDataModel.endedAsleep` (a defaulted Bool — lightweight).
    /// 2.8.0 (2026-10-04): `PrayerModel.prayerDayKey` (optional String — lightweight; filled by the data pass).
    static let versionIdentifier = Schema.Version(2, 8, 0)
    static var models: [any PersistentModel.Type] {
        [SessionDataModel.self, MantraModel.self, TaskModel.self, DuaModel.self, PrayerModel.self, DailyPrayerScore.self]
    }
}

/// Fills in what the schema change alone can't: the four built-ins as rows, a mantra row for
/// every task (created from its name if needed), sessions linked to a mantra by title, and an
/// initial `sortOrder` for tasks that never had one. Sessions whose title matches nothing stay
/// unlinked on purpose (never invent mantras from history); prayers/duas/scores are untouched.
/// Safe to run repeatedly: it only touches rows that still need it.
enum ShukrV2DataPass {
    @discardableResult
    /// `seedOriginals`: add any of the original four built-ins that's missing — only on the pass
    /// that hasn't done it yet (`BuiltInAzkar.originalsSeededKey`), so one the user can't have
    /// deleted anyway is never re-seeded bare every launch. Matched like BuiltInAzkar (letters and
    /// digits only).
    static func run(in context: ModelContext, seedOriginals: Bool) throws -> String {
        var byName: [String: MantraModel] = [:]
        var keys = Set<String>()
        for mantra in try context.fetch(FetchDescriptor<MantraModel>()) {
            byName[BuiltInAzkar.key(mantra.name)] = mantra
            keys.insert(BuiltInAzkar.key(mantra.name))
        }
        var seeded = 0
        if seedOriginals {
            for name in MantraModel.builtIn where !keys.contains(BuiltInAzkar.key(name)) {
                let mantra = MantraModel(name: name)
                mantra.builtInID = BuiltInAzkar.key(name)
                context.insert(mantra)
                byName[BuiltInAzkar.key(name)] = mantra
                keys.insert(BuiltInAzkar.key(name))
                seeded += 1
            }
        }

        var tasksLinked = 0, tasksCreatedFor = 0
        let tasks = try context.fetch(FetchDescriptor<TaskModel>())
        for task in tasks where task.mantraRef == nil {
            let name = task.mantraName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if byName[BuiltInAzkar.key(name)] == nil {
                let mantra = MantraModel(name: name)
                context.insert(mantra)
                byName[BuiltInAzkar.key(name)] = mantra
                tasksCreatedFor += 1
            }
            task.mantra = byName[BuiltInAzkar.key(name)]
            tasksLinked += 1
        }
        // V1 had no order. If nobody has been numbered yet, fetch order becomes the initial one.
        var numbered = 0
        if tasks.count > 1, tasks.allSatisfy({ $0.sortOrder == 0 }) {
            for (position, task) in tasks.enumerated() { task.sortOrder = position }
            numbered = tasks.count
        }

        var sessionsLinked = 0
        // Only the unlinked ones come out of the store; on a linked store this fetches nothing.
        let unlinked = FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.mantra == nil })
        for session in try context.fetch(unlinked) {
            let key = BuiltInAzkar.key(session.title)
            if let mantra = byName[key] {
                session.mantra = mantra
                sessionsLinked += 1
            }
        }

        let quickAddMoved = QuickAddSteps.moveLegacySteps(into: Array(byName.values))

        if context.hasChanges { try context.save() }
        return "mantras=\(byName.count) (seeded \(seeded), from tasks \(tasksCreatedFor)) tasks linked=\(tasksLinked) numbered=\(numbered) sessions linked=\(sessionsLinked) quick add moved=\(quickAddMoved)"
    }
}
