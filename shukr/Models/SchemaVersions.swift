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

/// The current schema. Opening a store with it stamps "2.0.0" into its metadata, which is what
/// the widget's `storeIsCurrentVersion` looks for. Bump the version when the models change.
enum ShukrSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
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
    static func run(in context: ModelContext) throws -> String {
        var byName: [String: MantraModel] = [:]
        for mantra in try context.fetch(FetchDescriptor<MantraModel>()) {
            byName[mantra.name.lowercased()] = mantra
        }
        var seeded = 0
        for name in MantraModel.builtIn where byName[name.lowercased()] == nil {
            let mantra = MantraModel(name: name)
            context.insert(mantra)
            byName[name.lowercased()] = mantra
            seeded += 1
        }

        var tasksLinked = 0, tasksCreatedFor = 0
        let tasks = try context.fetch(FetchDescriptor<TaskModel>())
        for task in tasks where task.mantraRef == nil {
            let name = task.mantraName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if byName[name.lowercased()] == nil {
                let mantra = MantraModel(name: name)
                context.insert(mantra)
                byName[name.lowercased()] = mantra
                tasksCreatedFor += 1
            }
            task.mantra = byName[name.lowercased()]
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
            let key = session.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let mantra = byName[key] {
                session.mantra = mantra
                sessionsLinked += 1
            }
        }

        if context.hasChanges { try context.save() }
        return "mantras=\(byName.count) (seeded \(seeded), from tasks \(tasksCreatedFor)) tasks linked=\(tasksLinked) numbered=\(numbered) sessions linked=\(sessionsLinked)"
    }
}
