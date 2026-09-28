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
    /// Each zikr's memo hash ("" = no memo), so a payload doesn't load the audio (external
    /// storage) on every save. Cleared when a save touches a zikr (MantraModel).
    private static var memoHashes: [PersistentIdentifier: String] = [:]
    /// Ids of every watch session received (with when), confirmed back to the watch for a week so
    /// it never resends one — even if it's since been deleted here, or started before today's Fajr.
    private static let receivedKey = "watchZikr.received"
    private static var received: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: receivedKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: receivedKey) }
    }

    static func start(container: ModelContainer) {
        self.container = container
        pruneMemoFiles()
        guard saveObserver == nil else { return }
        // Any save (a session, a task edit or delete, a zikr's memo) may change what the watch
        // shows. WatchSync.send() only sends when the context actually changed.
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
            let touched = keys.flatMap { note.userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
            // Only the zikr rows this save touched lose their cached memo hash (a session save
            // touches its zikr too, via the inverse relationship — that one re-hashes, not all).
            let zikrs = touched.filter { $0.entityName == "MantraModel" }
            Task { @MainActor in
                for id in zikrs { memoHashes[id] = nil }
                scheduleSend()
            }
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
                if let memo = memoHash(mantra), !memo.isEmpty { row["memo"] = memo }
            }
            return row
        }
        // Today's marked prayers with their scores, for the watch list's dots (score colour, faded).
        let (rowStart, rowEnd) = PrayerDay.rowRange(forDayStarting: PrayerDay.start())
        let fresh = container.map { ModelContext($0) } ?? context   // widget / notification marks too
        let marked = (try? fresh.fetch(FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.isCompleted && $0.startTime >= rowStart && $0.startTime <= rowEnd }))) ?? []
        var scores: [String: Double] = [:]
        for prayer in marked { scores[prayer.name] = prayer.numberScore ?? 0 }
        return [
            "scores": scores,
            "zikrDay": dayStart.timeIntervalSince1970,
            "zikrTasks": rows,
            // Sorted: an unchanged set must compare equal, or every save resends the context.
            "zikrSessions": Set(sessions.map(\.id.uuidString)).union(recentReceived()).sorted(),
            "qiblaSensitivity": UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: "qibla_sensitivity") as? Double ?? 3.5,
            "freestyleStep": QuickAddSteps.step(for: nil),
        ]
    }

    /// The zikr's memo hash, loading its audio only when it isn't cached.
    private static func memoHash(_ mantra: MantraModel) -> String? {
        let id = mantra.persistentModelID
        if let hash = memoHashes[id] { return hash }
        let hash = mantra.audioData.map(hash(of:)) ?? ""
        memoHashes[id] = hash
        return hash
    }

    private static func hash(of audio: Data) -> String {
        SHA256.hash(data: audio).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Watch session ids received in the last week.
    private static func recentReceived() -> [String] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        let kept = received.filter { $0.value > cutoff }
        if kept.count != received.count { received = kept }
        return Array(kept.keys)
    }

    private static var memoFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchMemos", isDirectory: true)
    }

    /// Memo transfer files older than a day.
    private static func pruneMemoFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: memoFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for url in files where ((try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < Date().addingTimeInterval(-86_400) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Watch → phone

    /// From `WatchSync`'s WCSession delegate (any thread).
    nonisolated static func receive(_ info: [String: Any]) {
        Task { @MainActor in
            switch info["type"] as? String {
            case "zikrSession": saveSession(info)
            case "memoRequest": if let id = info["mantraID"] as? String { sendMemo(mantraID: id) }
            case "prayerMarked": markPrayer(info)
            default: break
            }
        }
    }

    private static func saveSession(_ info: [String: Any]) {
        guard let context = container?.mainContext,
              let idString = info["id"] as? String, let id = UUID(uuidString: idString),
              let count = info["count"] as? Int, count > 0,
              let start = info["start"] as? Double else { return }
        // Already received (a repeated delivery, or one deleted here since)? Confirm it again.
        guard received[idString] == nil else { scheduleSend(); return }
        var existing = FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        if let found = try? context.fetch(existing), !found.isEmpty {
            received[idString] = Date().timeIntervalSince1970
            scheduleSend()
            return
        }

        var task: TaskModel?
        if let taskString = info["taskID"] as? String, let taskID = UUID(uuidString: taskString) {
            var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskID })
            d.fetchLimit = 1
            task = try? context.fetch(d).first     // deleted on the phone meanwhile → saved unlinked
        }
        let name = (info["name"] as? String) ?? ""
        let seconds = info["seconds"] as? Double ?? 0
        // Pace from the time at the last count, like the phone (pauses and idle time after the
        // last tap excluded).
        let perCount = info["perCount"] as? Double ?? seconds / Double(count)
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
        do {
            try context.save()
            received[idString] = Date().timeIntervalSince1970   // confirmed only once it's saved
        } catch {
            print("⌚️ watch session not saved: \(error)")
            context.rollback()
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        print("⌚️ saved a watch session: \(count) \(item.title)")
    }

    /// "I prayed" on the watch: marked on its row, scored at the tap (not at delivery), with the
    /// phone's last known spot, its nudges cancelled — the widget's routine, done here with the
    /// tap time. The app redoes the day score / streak / masjid check through the same
    /// reconcile path as a widget mark (`widgetWroteStore`), at once if it's open.
    private static func markPrayer(_ info: [String: Any]) {
        guard let container, let name = info["name"] as? String,
              let start = info["start"] as? Double, let end = info["end"] as? Double,
              let at = info["at"] as? Double else { return }
        let context = ModelContext(container)
        let startDate = Date(timeIntervalSince1970: start), endDate = Date(timeIntervalSince1970: end)
        let prayer = SharedStore.fetchPrayer(named: name, on: startDate, in: context) ?? {
            let made = PrayerModel(name: name, startTime: startDate, endTime: endDate, dateAtMake: startDate)
            context.insert(made)
            return made
        }()
        guard !prayer.isCompleted else { scheduleSend(); return }
        prayer.isCompleted = true
        prayer.setPrayerScore(atDate: Date(timeIntervalSince1970: at))
        prayer.setPrayerLocation(with: SharedStore.lastKnownLocation())
        prayer.cancelUpcomingNudges()
        do { try context.save() } catch { print("⌚️ watch mark not saved: \(error)"); return }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: SharedStore.widgetWroteStoreKey)
        NotificationCenter.default.post(name: .watchMarkedPrayer, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
        scheduleSend()
        print("⌚️ \(name) marked from the watch")
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
        let folder = memoFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A file per transfer: rewriting one a transfer is still reading would corrupt it.
        pruneMemoFiles()
        let file = folder.appendingPathComponent("\(mantraID)-\(UUID().uuidString).m4a")
        do {
            try audio.write(to: file, options: .atomic)
            WCSession.default.transferFile(file, metadata: ["mantraID": mantraID, "memo": hash(of: audio)])
        } catch {
            print("⌚️ memo not sent: \(error)")
        }
    }
}

extension Notification.Name {
    /// A prayer was marked on the watch: an open app reconciles now (as after a widget mark).
    static let watchMarkedPrayer = Notification.Name("watchMarkedPrayer")
}
