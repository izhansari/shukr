//
//  SessionDraft.swift
//  shukr
//
//  A running tasbeeh session lived only in the view's @State: go to the background and get evicted, or swipe the
//  app away, and 300 counts were gone (audit A7, 2026-10-01). Now the session writes a small draft to the standard
//  defaults on every pause, on going inactive / background and every few counts; a normal save clears it. A draft
//  found at the next launch is saved to history as the session it was (its zikr and task linked by id, its counts
//  and time as recorded), silently — the owner decides the wording, if any (decision audit-a7-restore-face).
//

import Foundation
import SwiftData

struct SessionDraft: Codable {
    static let key = "tasbeeh.draft"

    var title: String
    var mode: Int                 // 0 freestyle · 1 timed · 2 count
    var targetMin: Int
    var targetCount: Int
    var count: Int                // this session's own counts (offset already taken off)
    var startTime: Date
    var secondsPassed: TimeInterval
    var avgTimePerClick: TimeInterval
    var tasbeehRate: String
    var mantraID: UUID?
    var taskID: UUID?
    var postSalah: Bool
    var savedAt: Date

    // MARK: Writing (from the session)

    static func write(_ d: SessionDraft) {
        guard d.count > 0, let data = try? JSONEncoder().encode(d) else { clear(); return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func load() -> SessionDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionDraft.self, from: data)
    }

    // MARK: Restoring (at launch)

    /// A draft left by a session that never got to save: saved now as that session. Returns what was saved.
    /// Idempotent: the draft is cleared first, so a crash mid-save can't save it twice.
    @MainActor @discardableResult
    static func restoreIfAny(in container: ModelContainer) -> SessionDataModel? {
        guard let d = load() else { return nil }
        clear()
        guard d.count > 0 else { return nil }
        let context = ModelContext(container)
        var mantra: MantraModel? = nil
        if let id = d.mantraID {
            let fd = FetchDescriptor<MantraModel>(predicate: #Predicate { $0.id == id })
            mantra = try? context.fetch(fd).first
        }
        if mantra == nil, !d.title.isEmpty, d.title != "Untitled" { mantra = MantraModel.find(named: d.title, in: context) }
        var task: TaskModel? = nil
        if let id = d.taskID, d.mode != 0, !d.postSalah {
            let fd = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
            task = try? context.fetch(fd).first
        }
        let session = SessionDataModel(
            title: d.title, sessionMode: d.mode, targetMin: d.targetMin, targetCount: d.targetCount,
            totalCount: d.count, startTime: d.startTime, secondsPassed: max(d.secondsPassed, 0),
            avgTimePerClick: d.avgTimePerClick, tasbeehRate: d.tasbeehRate, task: task, mantra: mantra
        )
        context.insert(session)
        do {
            try context.save()
            print("✅ session draft restored: \(d.title) · \(d.count) counts from \(d.startTime)")
            if let task { ZikrReminders.taskMaybeDone(task, context: context) }
            return session
        } catch {
            print("❌ session draft: couldn't save (\(error)); dropped")
            return nil
        }
    }
}
