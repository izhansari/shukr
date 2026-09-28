//
//  WatchZikrSync.swift
//  shukr
//
//  Zikr on the Apple Watch, the phone's half (Sami, 2026-09-27, notes #14). The watch runs the
//  tasks set up here; it never creates or edits them.
//  - Phone → watch: today's tasks with their progress, the ids of today's sessions (so the watch
//    knows which of its own sessions have landed) and the freestyle "+N" step. Merged into the
//    application context `WatchSync` already sends, and re-sent (debounced) after every SwiftData
//    save, so a session on the phone shows on the watch within a moment.
//  - Watch → phone: each finished watch session arrives as `transferUserInfo` (queued; it lands
//    even if the phone was out of reach). It's saved as an ordinary `SessionDataModel` with the
//    watch's UUID as its id, so a repeat delivery is ignored, and linked to its task, which also
//    removes today's reminder once the task is done (`ZikrReminders.taskMaybeDone`).
//  - Voice memos: the watch asks for a zikr's memo when it doesn't have the current one
//    ("memoRequest"); the phone sends the audio with `transferFile`. The context only carries a
//    short hash of each memo, so the watch can tell when it changed.
//  No schema change.
//

import Foundation
import SwiftData
import WatchConnectivity
import WidgetKit
import CryptoKit

@MainActor
enum WatchZikrSync {
    private static var container: ModelContainer?
    private static var saveObserver: NSObjectProtocol?
    private static var pendingSend: Task<Void, Never>?
    /// Memo hashes by zikr id + audio size, so a payload doesn't re-hash unchanged audio.
    private static var memoHashes: [String: String] = [:]

    static func start(container: ModelContainer) {
        self.container = container
        guard saveObserver == nil else { return }
        // Any save (a session, a task edit or delete, a zikr's memo) may change what the watch
        // shows. WatchSync.send() only sends when the context actually changed.
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in scheduleSend() }
        }
    }

    static func scheduleSend() {
        pendingSend?.cancel()
        pendingSend = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            WatchSync.shared.send()
        }
    }

    // MARK: Phone → watch

    /// The zikr part of the watch's application context. Keys are read by `WatchZikrStore` on the
    /// watch (shukrWatch/WatchZikr.swift); keep the two in step.
    static func payload() -> [String: Any] {
        guard let context = container?.mainContext else { return [:] }
        let dayStart = PrayerDay.sessionDayStart()
        let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(
            predicate: #Predicate { $0.startTime >= dayStart }))) ?? []
        let rows: [[String: Any]] = tasks.map { task in
            let p = task.progress(in: sessions)
            var row: [String: Any] = [
                "id": task.id.uuidString,
                "title": task.title,
                "name": task.displayName,           // the session title the phone would save
                "countMode": task.isCountMode,
                "goal": task.goal,
                "count": p.count,
                "seconds": p.seconds,
                "step": QuickAddSteps.step(for: task.mantra),
            ]
            if let line = task.mantraLine { row["mantraLine"] = line }
            if let mantra = task.mantra {
                row["mantraID"] = mantra.id.uuidString
                if let audio = mantra.audioData { row["memo"] = memoHash(mantra.id.uuidString, audio) }
            }
            return row
        }
        // Today's marked prayers with their scores, for the watch list's dots (score colour, faded).
        let (rowStart, rowEnd) = PrayerDay.rowRange(forDayStarting: PrayerDay.start())
        let marked = (try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted && $0.startTime >= rowStart && $0.startTime <= rowEnd }))) ?? []
        var scores: [String: Double] = [:]
        for prayer in marked { scores[prayer.name] = prayer.numberScore ?? 0 }
        return [
            "scores": scores,
            "zikrDay": dayStart.timeIntervalSince1970,
            "zikrTasks": rows,
            "zikrSessions": sessions.map(\.id.uuidString),
            "freestyleStep": QuickAddSteps.step(for: nil),
        ]
    }

    private static func memoHash(_ id: String, _ audio: Data) -> String {
        let key = "\(id).\(audio.count)"
        if let hash = memoHashes[key] { return hash }
        let hash = SHA256.hash(data: audio).prefix(8).map { String(format: "%02x", $0) }.joined()
        memoHashes[key] = hash
        return hash
    }

    // MARK: Watch → phone

    /// From `WatchSync`'s WCSession delegate (any thread).
    nonisolated static func receive(_ info: [String: Any]) {
        Task { @MainActor in
            switch info["type"] as? String {
            case "zikrSession": saveSession(info)
            case "memoRequest": if let id = info["mantraID"] as? String { sendMemo(mantraID: id) }
            default: break
            }
        }
    }

    private static func saveSession(_ info: [String: Any]) {
        guard let context = container?.mainContext,
              let idString = info["id"] as? String, let id = UUID(uuidString: idString),
              let count = info["count"] as? Int, count > 0,
              let start = info["start"] as? Double else { return }
        // Already saved (a repeated delivery)?
        var existing = FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        var task: TaskModel?
        if let taskString = info["taskID"] as? String, let taskID = UUID(uuidString: taskString) {
            var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskID })
            d.fetchLimit = 1
            task = try? context.fetch(d).first     // deleted on the phone meanwhile → saved unlinked
        }
        let name = (info["name"] as? String) ?? ""
        let seconds = info["seconds"] as? Double ?? 0
        let perCount = seconds / Double(count)
        let item = SessionDataModel(
            title: task?.displayName ?? (name.isEmpty ? "Untitled" : name),
            sessionMode: info["mode"] as? Int ?? 0,
            targetMin: info["targetMin"] as? Int ?? 0,
            targetCount: info["targetCount"] as? Int ?? 0,
            totalCount: count,
            startTime: Date(timeIntervalSince1970: start),
            secondsPassed: seconds,
            avgTimePerClick: perCount,
            tasbeehRate: rateString(perCount),
            task: task,
            mantra: task?.mantra ?? (name.isEmpty ? nil : MantraModel.find(named: name, in: context))
        )
        item.id = id
        context.insert(item)
        if let task { ZikrReminders.taskMaybeDone(task, context: context) }
        do { try context.save() } catch { print("⌚️ watch session not saved: \(error)") }
        WidgetCenter.shared.reloadAllTimelines()
        print("⌚️ saved a watch session: \(count) \(item.title)")
    }

    /// The phone's "per 100" rate, as tasbeehView writes it.
    private static func rateString(_ perCount: Double) -> String {
        let to100 = Int(perCount * 100)
        return to100 >= 60 ? "\(to100 / 60)m \(to100 % 60)s" : "\(to100)s"
    }

    private static func sendMemo(mantraID: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let context = container?.mainContext, let id = UUID(uuidString: mantraID) else { return }
        var d = FetchDescriptor<MantraModel>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let mantra = try? context.fetch(d).first, let audio = mantra.audioData else { return }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchMemos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(mantraID).m4a")
        do {
            try audio.write(to: file, options: .atomic)
            WCSession.default.transferFile(file, metadata: ["mantraID": mantraID, "memo": memoHash(mantraID, audio)])
        } catch {
            print("⌚️ memo not sent: \(error)")
        }
    }
}
