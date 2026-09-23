//
//  SchemaVersions.swift
//  shukr
//
//  Versioned SwiftData schema + migration plan. Compiled into the app AND the widget (Models/
//  is in both targets), and both open the store through this plan (`SharedStore`). That matters:
//  if either process opened the store without the plan, SwiftData would apply the lightweight
//  part of a migration on its own and the custom `didMigrate` (which links tasks and sessions
//  to mantra rows) would never run for that store.
//
//  V1: the original models — mantra is a bare string on tasks, sessions only have a title.
//  V2: MantraModel gains name/fullText/notes/createdAt; tasks and sessions point at a mantra.
//      Renames use `originalName`, new columns have defaults, new relationships are optional,
//      so the store change itself is lightweight; `didMigrate` does the data work.
//
//  Adding V3 later: add an enum below, append it to `schemas`, add a stage. Keep the V1 copies
//  exactly as they are — they must hash to what an old store contains.
//

import Foundation
import SwiftData

// MARK: - V1 (original, unversioned)

enum ShukrSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SessionDataModel.self, MantraModel.self, TaskModel.self, DuaModel.self, PrayerModel.self, DailyPrayerScore.self]
    }

    @Model
    final class MantraModel {
        @Attribute(.unique) var id: UUID = UUID()
        var text: String
        init(text: String) { self.text = text }
    }

    @Model
    final class TaskModel {
        @Attribute(.unique) var id: UUID = UUID()
        var mantra: String
        var isCountMode: Bool
        var goal: Int
        @Relationship(deleteRule: .nullify, inverse: \SessionDataModel.task)
        var sessions: [SessionDataModel] = []
        init(mantra: String, isCountMode: Bool, goal: Int) {
            self.mantra = mantra; self.isCountMode = isCountMode; self.goal = goal
        }
    }

    @Model
    final class SessionDataModel {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String
        var sessionMode: Int
        var targetMin: Int
        var targetCount: Int
        var totalCount: Int
        var startTime: Date
        var secondsPassed: TimeInterval
        var timeDurationString: String
        var avgTimePerClick: TimeInterval
        var tasbeehRate: String
        var task: TaskModel?
        init(title: String, sessionMode: Int, targetMin: Int, targetCount: Int, totalCount: Int, startTime: Date,
             secondsPassed: TimeInterval, timeDurationString: String, avgTimePerClick: TimeInterval, tasbeehRate: String) {
            self.title = title; self.sessionMode = sessionMode; self.targetMin = targetMin
            self.targetCount = targetCount; self.totalCount = totalCount; self.startTime = startTime
            self.secondsPassed = secondsPassed; self.timeDurationString = timeDurationString
            self.avgTimePerClick = avgTimePerClick; self.tasbeehRate = tasbeehRate
        }
    }

    @Model
    final class PrayerModel {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String
        var dateAtMake: Date
        var startTime: Date
        var endTime: Date
        var isCompleted: Bool = false
        var timeAtComplete: Date?
        var numberScore: Double?
        var englishScore: String?
        var latPrayedAt: Double?
        var longPrayedAt: Double?
        var prayerStartedAt: Date?
        var prayerCompletedAt: Date?
        var duration: TimeInterval?
        init(name: String, dateAtMake: Date, startTime: Date, endTime: Date) {
            self.name = name; self.dateAtMake = dateAtMake; self.startTime = startTime; self.endTime = endTime
        }
    }

    @Model
    final class DuaModel {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String
        var duaBody: String
        var date: Date
        init(title: String, duaBody: String, date: Date) { self.title = title; self.duaBody = duaBody; self.date = date }
    }

    @Model
    final class DailyPrayerScore {
        @Attribute(.unique) var id: UUID = UUID()
        var date: Date
        var averageScore: Double?
        init(date: Date) { self.date = date }
    }
}

// MARK: - V2 (current): the top-level model classes in AllModels.swift

enum ShukrSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SessionDataModel.self, MantraModel.self, TaskModel.self, DuaModel.self, PrayerModel.self, DailyPrayerScore.self]
    }
}

// MARK: - Plan

enum ShukrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ShukrSchemaV1.self, ShukrSchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }

    /// Schema part is lightweight (renames + defaulted columns + optional relationships).
    /// Data part: make the four built-ins real rows, give every task a mantra row (creating one
    /// from its name if needed), and link sessions whose title matches a mantra. Sessions with a
    /// title that matches nothing keep their title and stay unlinked — never invent mantras from
    /// history, and never touch prayers/duas/scores.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: ShukrSchemaV1.self,
        toVersion: ShukrSchemaV2.self,
        willMigrate: nil
    ) { context in
        var byName: [String: MantraModel] = [:]
        for mantra in try context.fetch(FetchDescriptor<MantraModel>()) {
            byName[mantra.name.lowercased()] = mantra
        }
        for name in MantraModel.builtIn where byName[name.lowercased()] == nil {
            let mantra = MantraModel(name: name)
            context.insert(mantra)
            byName[name.lowercased()] = mantra
        }

        var tasksLinked = 0, tasksCreatedFor = 0
        for task in try context.fetch(FetchDescriptor<TaskModel>()) {
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

        var sessionsLinked = 0
        for session in try context.fetch(FetchDescriptor<SessionDataModel>()) {
            let key = session.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let mantra = byName[key] {
                session.mantra = mantra
                sessionsLinked += 1
            }
        }

        try context.save()
        print("✅ schema V1→V2: mantras=\(byName.count) (new from tasks: \(tasksCreatedFor)) tasks linked=\(tasksLinked) sessions linked=\(sessionsLinked)")
    }
}
