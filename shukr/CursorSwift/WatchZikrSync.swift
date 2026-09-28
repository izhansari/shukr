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
import CoreLocation
import UIKit

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
    /// Prayer marks from the watch by id → [received at, the prayer's start]. Kept apart from
    /// sessions (they never go to the watch as confirmed sessions). A negative "received at" is an
    /// undo that arrived before its mark: that mark is then ignored.
    private static let marksKey = "watchZikr.receivedMarks"
    private static var receivedMarks: [String: [Double]] {
        get { UserDefaults.standard.dictionary(forKey: marksKey) as? [String: [Double]] ?? [:] }
        set {
            let cutoff = Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970
            UserDefaults.standard.set(newValue.filter { abs($0.value.first ?? 0) > cutoff }, forKey: marksKey)
        }
    }

    static func start(container: ModelContainer) {
        self.container = container
        pruneMemoFiles()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoWatchSyncTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { runSyncSelfTest() }
        }
        #endif
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
        #if DEBUG
        scheduledSends += 1
        #endif
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
            // Marks and undos the phone has handled, apart: the watch clears each from its outbox
            // only when its own kind is confirmed (an undo isn't dropped when just its mark is).
            "markIDs": receivedMarks.filter { ($0.value.first ?? 0) > 0 }.keys.sorted(),
            "unmarkIDs": receivedMarks.filter { ($0.value.first ?? 0) < 0 }.keys.sorted(),
            // Your masajid, so a Friday Dhuhr marked on the watch at one is Jumu'ah there too.
            "masajid": MosqueFavorites.all.map { [$0.name, String($0.latitude), String($0.longitude)] },
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
            case "prayerUnmarked": unmarkPrayer(info)
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
            mantra: task?.mantra ?? (info["postSalah"] as? Bool == true ? tasbihFatimah(in: context)
                                     : name.isEmpty ? nil : MantraModel.find(named: name, in: context))
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
        // The same mark arrives twice (direct + queued), and must never re-mark a prayer unmarked
        // here since: each mark has its own id.
        let markID = info["id"] as? String
        if let markID, receivedMarks[markID] != nil { scheduleSend(); return }
        let context = ModelContext(container)
        let startDate = Date(timeIntervalSince1970: start), endDate = Date(timeIntervalSince1970: end)
        let tapped = Date(timeIntervalSince1970: at)
        let rows = prayerRows(named: name, on: startDate, in: context)
        let prayer = rows.first ?? {
            let made = PrayerModel(name: name, startTime: startDate, endTime: endDate, dateAtMake: startDate)
            context.insert(made)
            return made
        }()
        // Already prayed (on any of the day's rows for it): nothing to add.
        guard !rows.contains(where: \.isCompleted) else {
            if let markID { receivedMarks[markID] = [Date().timeIntervalSince1970, start, -1] }   // not applied
            scheduleSend(); return
        }
        prayer.isCompleted = true
        prayer.setPrayerLocation(with: SharedStore.lastKnownLocation())
        // At one of your own masajid: a Friday Dhuhr is Jumu'ah at once, as when marked in the app.
        if let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt {
            prayer.mosqueName = MasjidDetector.favoriteMasjid(near: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        prayer.setPrayerScore(atDate: tapped)
        prayer.cancelUpcomingNudges()
        // Its own day's score (a mark delivered after Fajr belongs to yesterday).
        rescoreDay(of: startDate, in: context)
        do {
            try context.save()
        } catch {
            print("⌚️ watch mark not saved: \(error)")
            // Tell the watch, so it stops showing it marked.
            let reply: [String: Any] = ["type": "markFailed", "name": name, "id": markID ?? "", "start": start]
            if WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo(reply)
                if WCSession.default.isReachable { WCSession.default.sendMessage(reply, replyHandler: nil, errorHandler: nil) }
            }
            return
        }
        if let markID { receivedMarks[markID] = [Date().timeIntervalSince1970, start, at] }
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: SharedStore.widgetWroteStoreKey)
        // On screen, and about today's prayer day: the app's own completion moment, as for a mark
        // made here. (Yesterday's Isha delivered after Fajr must not play on today's circle.)
        if UIApplication.shared.applicationState == .active,
           Calendar.current.isDate(startDate, inSameDayAs: PrayerDay.date()) {
            let window = endDate.timeIntervalSince(startDate)
            let progress = window > 0 ? tapped.timeIntervalSince(startDate) / window : 1
            NotificationCenter.default.post(name: .prayerCompleted, object: PrayerCompletionEvent(
                name: prayer.displayName, score: prayer.numberScore ?? 0, progress: min(max(progress, 0), 1),
                summary: prayer.scoreSummary, prayerName: prayer.name))   // the circle holds that row under the flourish
        }
        NotificationCenter.default.post(name: .watchMarkedPrayer, object: startDate)
        WidgetCenter.shared.reloadAllTimelines()
        scheduleSend()
        print("⌚️ \(name) marked from the watch")
    }

    /// Undo on the watch, within seconds of a mark: that mark (by id) comes off again, and its day
    /// is rescored. An undo that arrives before its mark leaves a tombstone, so the mark is ignored.
    /// "Unmark Asr?" from the watch's list (`byName`): whoever marked it (watch, phone, widget), it
    /// comes off like an in-app unmark — unless the prayer was marked again after the watch's tap
    /// (a late retry never wipes a newer mark). Either way the unmark's id is then reported as
    /// handled, and the watch drops its own pending copy and shows what the phone has.
    /// A tombstone is written only once the outcome is saved: a failed save leaves nothing, so the
    /// watch's retry is applied.
    private static func unmarkPrayer(_ info: [String: Any]) {
        guard let container, let markID = info["id"] as? String, let name = info["name"] as? String,
              let start = info["start"] as? Double else { return }
        let startDate = Date(timeIntervalSince1970: start)
        func tombstone(_ ids: [String?]) {
            for case let id? in ids { receivedMarks[id] = [-Date().timeIntervalSince1970, start] }
        }
        if info["byName"] as? Bool == true {
            guard receivedMarks[markID] == nil else { scheduleSend(); return }
            let original = info["markID"] as? String
            let context = ModelContext(container)
            let done = prayerRows(named: name, on: startDate, in: context).filter(\.isCompleted)
            // Marked again since the watch's tap (on the phone, the widget, or a newer watch mark):
            // that mark stands.
            if let at = info["at"] as? Double,
               let latest = done.compactMap({ $0.timeAtComplete?.timeIntervalSince1970 }).max(), latest > at {
                tombstone([markID, original])
                scheduleSend()
                print("⌚️ \(name) unmark ignored: marked again since")
                return
            }
            guard !done.isEmpty else { tombstone([markID, original]); scheduleSend(); return }
            // Every completed row of that prayer on that day (a day can hold two).
            done.forEach { $0.resetPrayer() }
            rescoreDay(of: startDate, in: context)
            do { try saveUnmark(context) } catch {
                print("⌚️ watch unmark not saved: \(error)")
                context.rollback()
                return
            }
            tombstone([markID, original])
            unmarkApplied(name, day: startDate)
            print("⌚️ \(name) unmarked from the watch")
            return
        }
        let known = receivedMarks[markID]
        // Its mark hasn't arrived, or wasn't applied: the tombstone keeps a late copy out.
        guard let known, (known.first ?? 0) > 0, known.count > 2, known[2] > 0 else {
            tombstone([markID]); scheduleSend(); return   // the watch hears it's handled
        }
        let context = ModelContext(container)
        // Only the row still carrying *this* mark (its tap time): a newer mark, or one made on the
        // phone since, is never undone by an old undo.
        let carrying = prayerRows(named: name, on: startDate, in: context).filter {
            $0.isCompleted && abs(($0.timeAtComplete?.timeIntervalSince1970 ?? 0) - known[2]) < 1
        }
        guard !carrying.isEmpty else { tombstone([markID]); scheduleSend(); return }
        carrying.forEach { $0.resetPrayer() }
        rescoreDay(of: startDate, in: context)
        do { try saveUnmark(context) } catch {
            print("⌚️ watch undo not saved: \(error)")
            context.rollback()
            return
        }
        tombstone([markID])
        unmarkApplied(name, day: startDate)
        print("⌚️ \(name) unmarked from the watch (undo)")
    }

    /// Saves an unmark's changes (DEBUG: `failNextSave` makes one save fail, for the self-test).
    private static func saveUnmark(_ context: ModelContext) throws {
        #if DEBUG
        if failNextSave { failNextSave = false; throw CocoaError(.fileWriteUnknown) }
        #endif
        try context.save()
    }

    /// After an unmark is saved: the app reconciles (day score, streaks), widgets and the watch update.
    private static func unmarkApplied(_ name: String, day: Date) {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: SharedStore.widgetWroteStoreKey)
        NotificationCenter.default.post(name: .watchMarkedPrayer, object: day)
        WidgetCenter.shared.reloadAllTimelines()
        scheduleSend()
    }

    /// Every row of a prayer on that calendar day. A day can hold more than one, and a completed
    /// row must never hide behind an unmarked one (`fetchPrayer` returns the first it finds).
    private static func prayerRows(named name: String, on day: Date, in context: ModelContext) -> [PrayerModel] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? day
        return (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate<PrayerModel> {
            $0.name == name && $0.startTime >= dayStart && $0.startTime <= dayEnd
        }))) ?? []
    }

    #if DEBUG
    static var failNextSave = false
    /// Replies scheduled to the watch (the self-test checks an undo gets one).
    static var scheduledSends = 0

    /// `-demoWatchSyncTest` (simulator): the phone's side of watch marks / unmarks against rows on
    /// 2020-01-06 (made and removed here), logged as "⌚️ SYNCTEST".
    static func runSyncSelfTest() {
        guard let container else { return }
        let start = DateComponents(calendar: .current, year: 2020, month: 1, day: 6, hour: 15).date!
        let end = start.addingTimeInterval(3 * 3600)
        let s0 = start.timeIntervalSince1970, e0 = end.timeIntervalSince1970
        var ids: [String] = []
        func id(_ label: String) -> String { let v = "synctest-\(label)-\(UUID().uuidString)"; ids.append(v); return v }
        func setRows(_ times: [Double?]) {
            let c = ModelContext(container)
            prayerRows(named: "Asr", on: start, in: c).forEach { c.delete($0) }
            for t in times {
                let p = PrayerModel(name: "Asr", startTime: start, endTime: end, dateAtMake: start)
                if let t { p.isCompleted = true; p.setPrayerScore(atDate: Date(timeIntervalSince1970: t)) }
                c.insert(p)
            }
            try? c.save()
        }
        func state() -> String {
            prayerRows(named: "Asr", on: start, in: ModelContext(container))
                .map { $0.isCompleted ? "✓\(Int(($0.timeAtComplete?.timeIntervalSince1970 ?? 0) - s0))" : "·" }
                .sorted().joined(separator: ",")
        }
        func handled(_ id: String) -> String {
            receivedMarks[id].map { ($0.first ?? 0) < 0 ? "tombstone" : "applied" } ?? "none"
        }
        func unmark(_ id: String, at: Double, markID: String? = nil) {
            var info: [String: Any] = ["id": id, "byName": true, "name": "Asr", "start": s0, "at": at]
            if let markID { info["markID"] = markID }
            unmarkPrayer(info)
        }
        func mark(_ id: String, at: Double) {
            markPrayer(["id": id, "name": "Asr", "start": s0, "end": e0, "at": at])
        }
        var lines: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String) { lines.append("\(ok ? "✅" : "❌") \(name) — \(detail)") }

        setRows([s0 + 60])
        let u1 = id("u1"); unmark(u1, at: s0 + 120)
        check("unmark applies", state() == "·" && handled(u1) == "tombstone", "\(state()) \(handled(u1))")

        setRows([s0 + 300])
        let u2 = id("u2"); unmark(u2, at: s0 + 120)
        check("stale unmark (marked again after the tap) ignored, reported handled",
              state() == "✓300" && handled(u2) == "tombstone", "\(state()) \(handled(u2))")

        setRows([s0 + 60, s0 + 90])
        let u3 = id("u3"); unmark(u3, at: s0 + 200)
        check("both completed rows reset", state() == "·,·", state())

        setRows([s0 + 60])
        failNextSave = true
        let u4 = id("u4"); unmark(u4, at: s0 + 200)
        let afterFail = "\(state()) \(handled(u4))"
        unmark(u4, at: s0 + 200)
        check("failed save leaves no tombstone; the retry applies",
              afterFail == "✓60 none" && state() == "·" && handled(u4) == "tombstone", "\(afterFail) → \(state()) \(handled(u4))")

        setRows([nil])
        let m1 = id("m1"), m2 = id("m2"), u5 = id("u5")
        mark(m2, at: s0 + 200)          // mark 2 arrives first…
        unmark(u5, at: s0 + 100, markID: m1)   // …then the unmark of mark 1…
        mark(m1, at: s0 + 50)           // …then mark 1 itself
        check("out of order (M2, U1, M1) ends marked by M2",
              state() == "✓200" && handled(m2) == "applied" && handled(u5) == "tombstone" && handled(m1) == "tombstone",
              "\(state()) m2 \(handled(m2)) u5 \(handled(u5)) m1 \(handled(m1))")

        setRows([nil])
        let m6 = id("m6"); mark(m6, at: s0 + 70)
        unmarkPrayer(["id": m6, "name": "Asr", "start": s0])
        check("undo takes its own mark off", state() == "·" && handled(m6) == "tombstone", "\(state()) \(handled(m6))")

        // An undo whose mark never arrived (or wasn't applied): tombstoned, and the watch is told.
        let m8 = id("m8"), sendsBefore = scheduledSends
        unmarkPrayer(["id": m8, "name": "Asr", "start": s0])
        check("undo of a mark that never arrived: tombstoned, reply scheduled",
              handled(m8) == "tombstone" && scheduledSends > sendsBefore, "\(handled(m8)) sends +\(scheduledSends - sendsBefore)")

        // Undo after the phone confirmed the mark, delivered late (out of reach, then reconnected):
        // the mark is on the row until the undo lands, then comes off, and the reply goes out.
        setRows([nil])
        let m9 = id("m9"); mark(m9, at: s0 + 80)
        let confirmed = "\(state()) \(handled(m9))"
        let sendsBeforeUndo = scheduledSends
        unmarkPrayer(["id": m9, "name": "Asr", "start": s0])
        check("undo after the phone confirmed, delivered on reconnect",
              confirmed == "✓80 applied" && state() == "·" && handled(m9) == "tombstone" && scheduledSends > sendsBeforeUndo,
              "\(confirmed) → \(state()) \(handled(m9))")

        setRows([nil])
        let m7 = id("m7"); mark(m7, at: s0 + 70)
        setRows([s0 + 500])             // marked again on the phone since
        unmarkPrayer(["id": m7, "name": "Asr", "start": s0])
        check("old undo never removes a newer mark", state() == "✓500", state())

        // Clean up: the test rows, their day score and ids.
        let c = ModelContext(container)
        prayerRows(named: "Asr", on: start, in: c).forEach { c.delete($0) }
        let dayStart = Calendar.current.startOfDay(for: start)
        (try? c.fetch(FetchDescriptor<DailyPrayerScore>(predicate: #Predicate { $0.date == dayStart })))?.forEach { c.delete($0) }
        try? c.save()
        var marks = receivedMarks
        ids.forEach { marks[$0] = nil }
        receivedMarks = marks
        let report = "⌚️ SYNCTEST\n" + lines.joined(separator: "\n")
        print(report)
        try? report.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("synctest.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    /// A day's DailyPrayerScore from its rows (a late mark or an undo belongs to its own day).
    private static func rescoreDay(of startDate: Date, in context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: startDate)
        let (rowStart, rowEnd) = PrayerDay.rowRange(forDayStarting: dayStart)
        let dayPrayers = (try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: #Predicate { $0.startTime >= rowStart && $0.startTime <= rowEnd }))) ?? []
        let score = PrayerScoring.dayScore(for: dayPrayers)
        if let row = try? context.fetch(FetchDescriptor<DailyPrayerScore>(
            predicate: #Predicate { $0.date >= dayStart && $0.date <= dayStart })).first {
            row.averageScore = score
        } else {
            let row = DailyPrayerScore(date: dayStart)
            row.averageScore = score
            context.insert(row)
        }
    }

    /// The "Tasbih Fatimah" zikr, made on first use exactly as the phone's post-salah session does
    /// (PostSalahTasbeeh.prepare).
    private static func tasbihFatimah(in context: ModelContext) -> MantraModel {
        let name = PostSalahTasbeeh.mantraName
        if let found = MantraModel.find(named: name, in: context) { return found }
        let text = PostSalahTasbeeh.phases.map { "\($0.arabic)  ×\($0.count)" }.joined(separator: "\n")
            + "\nSubhanallah · Alhamdulillah · Allahu Akbar"
        let new = MantraModel(name: name, fullText: text,
                              notes: "After each obligatory prayer: 33, 33 and 34 — 100 in all.")
        new.builtInID = BuiltInAzkar.key(BuiltInAzkar.tasbihFatimahName)
        context.insert(new)
        return new
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
