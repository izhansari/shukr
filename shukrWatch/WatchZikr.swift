//
//  WatchZikr.swift
//  shukr Watch
//
//  Zikr on the wrist (Sami, 2026-09-27, notes #14): the phone's Zikr page, small. The watch runs
//  the tasks set up on the phone (it never creates or edits them) plus Freestyle.
//  - `WatchZikrStore`: today's tasks as the phone last sent them (`WatchZikrSync.payload` in the
//    iPhone app — keep the keys in step), plus this watch's own finished sessions until the phone
//    confirms them, so the rings fill at once even with the phone out of reach. The prayer day
//    starts at Fajr, as on the phone.
//  - `WatchZikrPage`: the circles on the phone's gentle arc / half tilt wheel; tap to centre, tap
//    the centre one to start; a part-done task asks "Continue from N / Start over" like the phone.
//  - `WatchCounterView`: tap, or hold and pump (drag down a little, back up half as far), like the
//    phone; − and the "+N" count-in-sets toggle top left, pause top right; the phone's haptics as
//    near as the watch's set allows. Pause: name, count / time / pace, the zikr's voice memo,
//    Resume, Finish early (two taps). A mindfulness runtime session keeps it going with the
//    wrist down.
//  - `WatchSettingsPage`: haptic strength.
//

import SwiftUI
import WatchKit
import WatchConnectivity
import AVFoundation

extension Color {
    /// The app's muted green (shukr/Utils.swift `Color.sage`).
    static let watchSage = Color(red: 0.40, green: 0.64, blue: 0.50)
}

// MARK: - Data

struct WatchTask: Identifiable, Equatable {
    let id: String
    let title: String
    /// The session title the phone saves (the zikr's name).
    let name: String
    let mantraLine: String?
    let mantraID: String?
    let memo: String?
    let countMode: Bool
    let goal: Int
    let phoneCount: Int
    let phoneSeconds: Double
    let step: Int

    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
        self.id = id
        self.title = title
        name = row["name"] as? String ?? title
        mantraLine = row["mantraLine"] as? String
        mantraID = row["mantraID"] as? String
        memo = row["memo"] as? String
        countMode = row["countMode"] as? Bool ?? true
        goal = max(row["goal"] as? Int ?? 1, 1)
        phoneCount = row["count"] as? Int ?? 0
        phoneSeconds = row["seconds"] as? Double ?? 0
        step = row["step"] as? Int ?? 0
    }
}

/// A session in progress, kept on the watch so the count is never lost: reopened paused if the
/// app is closed, saved as a finished session once it's been paused an hour or the prayer day
/// has turned at Fajr (so the task's "Continue from N" picks it up).
struct WatchDraft: Codable {
    let taskID: String?
    let name: String
    let mode: Int
    let targetMin: Int
    let targetCount: Int
    let startCount: Int
    let startSeconds: Double
    let count: Int
    let startedAt: Date
    let pausedTotal: Double
    let pausedAt: Date?
    let lastCountActive: Double
    let countingInSets: Bool
    let dayStart: Date
    let savedAt: Date

    /// Paused since (a draft saved mid-count counts as paused from its last save).
    var pausedSince: Date { pausedAt ?? savedAt }
    var sessionCount: Int { count - startCount }
}

/// A session finished on the watch, kept until the phone lists its id among today's sessions.
struct WatchZikrRecord: Codable, Equatable {
    let id: String
    let taskID: String?
    let name: String
    let mode: Int          // the phone's: 0 freestyle, 1 timed, 2 count
    let targetMin: Int
    let targetCount: Int
    let count: Int
    let start: Date
    let seconds: Double
    /// Time per count at the last count (pauses and idle time after it excluded), like the phone.
    var perCount: Double? = nil

    var userInfo: [String: Any] {
        var info: [String: Any] = ["type": "zikrSession", "id": id, "name": name, "mode": mode,
                                   "targetMin": targetMin, "targetCount": targetCount, "count": count,
                                   "start": start.timeIntervalSince1970, "seconds": seconds]
        if let taskID { info["taskID"] = taskID }
        if let perCount { info["perCount"] = perCount }
        return info
    }
}

/// Main actor only: the WCSession delegate (a background queue) hops here before touching it.
@MainActor
final class WatchZikrStore: ObservableObject {
    static let shared = WatchZikrStore()
    @Published private(set) var revision = 0

    private enum Key {
        static let day = "watch.zikr.day", tasks = "watch.zikr.tasks", sessions = "watch.zikr.sessions"
        static let freestyleStep = "watch.zikr.freestyleStep", pending = "watch.zikr.pending"
        static let memos = "watch.zikr.memos", hasData = "watch.zikr.hasData"
        static let draft = "watch.zikr.draft"
    }
    private var d: UserDefaults { WatchStore.defaults }

    // MARK: From the phone

    /// The zikr part of the phone's application context. True if anything changed.
    @discardableResult
    func take(_ context: [String: Any]) -> Bool {
        guard let rows = context["zikrTasks"] as? [[String: Any]] else { return false }
        d.set(true, forKey: Key.hasData)
        d.set(context["zikrDay"] as? Double ?? 0, forKey: Key.day)
        d.set(rows, forKey: Key.tasks)
        d.set(context["zikrSessions"] as? [String] ?? [], forKey: Key.sessions)
        d.set(context["freestyleStep"] as? Int ?? 0, forKey: Key.freestyleStep)
        dropConfirmed()
        bump()
        return true
    }

    /// Has the phone ever sent its tasks?
    var hasData: Bool { d.bool(forKey: Key.hasData) }
    var freestyleStep: Int { d.integer(forKey: Key.freestyleStep) }

    /// The tasks in the phone's order.
    var tasks: [WatchTask] {
        (d.array(forKey: Key.tasks) as? [[String: Any]] ?? []).compactMap(WatchTask.init)
    }

    /// When today's prayer day began (its Fajr; 3 AM without a location, like the phone).
    func dayStart(at now: Date = Date()) -> Date {
        if let fajr = WatchPrayers.day(at: now)?.prayers.first?.start { return fajr }
        let cal = Calendar.current
        var start = cal.date(byAdding: .hour, value: 3, to: cal.startOfDay(for: now)) ?? now
        if start > now { start = cal.date(byAdding: .day, value: -1, to: start) ?? start }
        return start
    }

    /// Is the phone's progress about today? (Its day is the same Fajr, give or take a little.)
    private func phoneIsToday(_ now: Date) -> Bool {
        abs(d.double(forKey: Key.day) - dayStart(at: now).timeIntervalSince1970) < 30 * 60
    }

    /// Today's progress: the phone's, plus this watch's sessions it hasn't confirmed yet.
    func progress(_ task: WatchTask, at now: Date = Date()) -> (count: Int, seconds: Double) {
        // The phone's latest numbers for it, not a copy taken when a session started (once the
        // phone confirmed a session, that old copy read 0).
        let task = tasks.first { $0.id == task.id } ?? task
        let start = dayStart(at: now)
        let confirmed = Set(d.stringArray(forKey: Key.sessions) ?? [])
        let mine = pending.filter { $0.taskID == task.id && $0.start >= start && !confirmed.contains($0.id) }
        let fromPhone = phoneIsToday(now) ? (task.phoneCount, task.phoneSeconds) : (0, 0)
        return (fromPhone.0 + mine.reduce(0) { $0 + $1.count }, fromPhone.1 + mine.reduce(0) { $0 + $1.seconds })
    }

    func fraction(_ task: WatchTask, at now: Date = Date()) -> Double {
        let p = progress(task, at: now)
        return task.countMode ? Double(p.count) / Double(task.goal) : p.seconds / Double(task.goal * 60)
    }

    func isDone(_ task: WatchTask, at now: Date = Date()) -> Bool { fraction(task, at: now) >= 1 }

    // MARK: To the phone

    private var pending: [WatchZikrRecord] {
        get { (try? JSONDecoder().decode([WatchZikrRecord].self, from: d.data(forKey: Key.pending) ?? Data())) ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: Key.pending) }
    }

    /// A finished session: kept here (so the ring counts it now) and queued for the phone.
    func record(_ record: WatchZikrRecord) {
        print("⌚️ recorded \(record.count) for \(record.taskID ?? "freestyle")")
        pending.append(record)
        send(record)
        bump()
    }

    private func send(_ record: WatchZikrRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            print("⌚️ not sent yet: session not active"); return
        }
        print("⌚️ sending \(record.id) reachable=\(WCSession.default.isReachable)")
        // Queued: lands even if the phone is out of reach (the phone ignores an id it already has).
        WCSession.default.transferUserInfo(record.userInfo)
        // And straight away when the phone is in reach, so the phone's rings update at once.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(record.userInfo, replyHandler: nil) { error in
                print("⌚️ message not delivered: \(error.localizedDescription)")
            }
        }
    }

    /// After the session activates: anything the phone hasn't confirmed and that isn't already on
    /// its way goes again (the phone ignores an id it already has).
    func resendUnconfirmed() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let confirmed = Set(d.stringArray(forKey: Key.sessions) ?? [])
        let inFlight = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String })
        for record in pending where !confirmed.contains(record.id) && !inFlight.contains(record.id) {
            send(record)
        }
    }

    /// When the phone comes into reach: everything it hasn't confirmed goes straight over as a
    /// message too (quicker than the queue; simulators only deliver this way).
    func sendUnconfirmedNow() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        let confirmed = Set(d.stringArray(forKey: Key.sessions) ?? [])
        for record in pending where !confirmed.contains(record.id) {
            WCSession.default.sendMessage(record.userInfo, replyHandler: nil) { error in
                print("⌚️ message not delivered: \(error.localizedDescription)")
            }
        }
    }

    /// Drops sessions the phone now lists, and anything older than two days.
    private func dropConfirmed() {
        let confirmed = Set(d.stringArray(forKey: Key.sessions) ?? [])
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        pending = pending.filter { !confirmed.contains($0.id) && $0.start > cutoff }
    }

    // MARK: Draft (a session in progress)

    var draft: WatchDraft? {
        get { d.data(forKey: Key.draft).flatMap { try? JSONDecoder().decode(WatchDraft.self, from: $0) } }
        set { d.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.draft) }
    }

    /// The draft to reopen, if any. One paused over an hour, or from before today's Fajr, is saved
    /// as a finished session instead (nothing counted is ever dropped).
    func settleDraft(now: Date = Date()) -> WatchDraft? {
        guard let draft else { return nil }
        #if DEBUG
        // `-demoWatchDraftAge 7200`: pretend the draft is that many seconds older (simulator check).
        let now = now.addingTimeInterval(UserDefaults.standard.double(forKey: "demoWatchDraftAge"))
        #endif
        let stale = now.timeIntervalSince(draft.pausedSince) > 3600
            || abs(dayStart(at: now).timeIntervalSince(draft.dayStart)) > 60
        guard stale else { return draft }
        self.draft = nil
        if draft.sessionCount > 0 {
            let seconds = max(0, draft.pausedSince.timeIntervalSince(draft.startedAt) - draft.pausedTotal)
            record(WatchZikrRecord(id: UUID().uuidString, taskID: draft.taskID, name: draft.name, mode: draft.mode,
                                   targetMin: draft.targetMin, targetCount: draft.targetCount,
                                   count: draft.sessionCount, start: draft.startedAt, seconds: seconds,
                                   perCount: draft.lastCountActive / Double(draft.sessionCount)))
            print("⌚️ saved a paused session (\(draft.sessionCount))")
        }
        return nil
    }

    // MARK: Voice memos

    private var memoFolder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var memoVersions: [String: String] {
        get { d.dictionary(forKey: Key.memos) as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: Key.memos) }
    }
    private var requested: Set<String> = []

    /// The memo file, if this watch has the version the phone last described.
    func memoURL(for task: WatchTask) -> URL? {
        guard let id = task.mantraID, let memo = task.memo, memoVersions[id] == memo else { return nil }
        let url = memoFolder.appendingPathComponent("\(id).m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Asks the phone for a zikr's memo once per version.
    func requestMemoIfNeeded(for task: WatchTask) {
        guard let id = task.mantraID, let memo = task.memo, memoURL(for: task) == nil,
              !requested.contains(id + memo),
              WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        requested.insert(id + memo)
        let info: [String: Any] = ["type": "memoRequest", "mantraID": id]
        WCSession.default.transferUserInfo(info)
        if WCSession.default.isReachable { WCSession.default.sendMessage(info, replyHandler: nil, errorHandler: nil) }
    }

    /// A memo arrived (WCSession file transfer). The file is only valid during the delegate
    /// callback, so it's moved there (any queue); only the bookkeeping hops to the main actor.
    nonisolated static func saveMemo(_ file: WCSessionFile) {
        guard let id = file.metadata?["mantraID"] as? String, let memo = file.metadata?["memo"] as? String else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("\(id).m4a")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: target)
            DispatchQueue.main.async {
                shared.memoVersions[id] = memo
                shared.bump()
            }
        } catch {
            print("⌚️ memo not kept: \(error)")
        }
    }

    private func bump() { revision += 1 }
}

// MARK: - Haptics

/// The phone's counter haptics, as near as the watch's fixed set allows (it has no strengths).
enum WatchHaptics {
    static let key = "watch.hapticStrength"   // 0 light · 1 medium · 2 strong
    static var strength: Int { WatchStore.defaults.object(forKey: key) as? Int ?? 1 }

    static func count() {
        let type: WKHapticType = switch strength {
        case 0: .click
        case 2: .start
        default: .directionUp
        }
        WKInterfaceDevice.current().play(type)
    }
    /// Counting in sets: the phone's ta-ta-ta. watchOS drops haptics played that close together,
    /// so one built-in multi-tap pattern (.retry) instead.
    static func set() { WKInterfaceDevice.current().play(.retry) }
    static func hundred() { WKInterfaceDevice.current().play(.notification) }
    static func goal() { WKInterfaceDevice.current().play(.success) }
    static func minus() { WKInterfaceDevice.current().play(.directionDown) }
    static func tick() { WKInterfaceDevice.current().play(.click) }
}

// MARK: - Zikr page (the wheel)

/// The phone's Zikr circle (ZikrCircleFace), small: a thick pale track and a glowing green ring —
/// full for Freestyle, today's progress for a task.
struct WatchZikrFace: View {
    let title: String
    var icon: String? = nil
    var mantraLine: String? = nil
    let subtitle: String
    let fraction: Double
    var done = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .green.opacity(0.5), radius: 3)
                .shadow(color: .green.opacity(0.3), radius: 6)
                .opacity(fraction > 0 ? 1 : 0)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if let icon { Image(systemName: icon).font(.system(size: 13, weight: .light)) }
                    Text(title)
                        .font(.system(size: 17, weight: .light, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 88)
                if let mantraLine {
                    Text(mantraLine)
                        .font(.system(size: 10, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 84)
                }
                HStack(spacing: 2) {
                    if done { Image(systemName: "checkmark") }
                    Text(subtitle).monospacedDigit()
                }
                .font(.system(size: 11, weight: .thin, design: .rounded))
                .foregroundStyle(done ? Color.watchSage : .secondary)
            }
        }
        .frame(width: 112, height: 112)
    }
}

/// The phone's wheel look (`WheelFalloff`, "Gentle arc, half tilt"), scaled to the watch: circles
/// shrink and fade away from the middle, ride an arc bulging right and turn with it.
struct WatchWheelFalloff: ViewModifier {
    let itemHeight: CGFloat
    private let radius: CGFloat = 134        // the phone's 240 × (112 / 200)
    private let perRow: CGFloat = 0.55
    private let tilt: CGFloat = 0.5

    func body(content: Content) -> some View {
        content.visualEffect { [itemHeight, radius, perRow, tilt] content, proxy in
            let frame = proxy.frame(in: .scrollView(axis: .vertical))
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? frame.height
            let rows: CGFloat = (frame.midY - viewport / 2) / itemHeight
            let d: CGFloat = min(abs(rows), 3)
            let ease: CGFloat = 1 - exp(-1.1 * d)
            let scale: CGFloat = 1 - 0.62 * ease
            let theta: CGFloat = min(max(rows, -2.2), 2.2) * perRow
            let arcX: CGFloat = -(1 - cos(theta)) * radius
            let pullY: CGFloat = -(rows >= 0 ? 1 : -1) * itemHeight * (1 - scale) * 0.45 * min(d, 1.5)
            return content
                .scaleEffect(scale)
                .opacity(1 - 0.7 * ease)
                .rotationEffect(.radians(Double(theta * tilt)))
                .offset(x: arcX, y: pullY)
        }
    }
}

/// What a counter session runs: Freestyle (no task) or a task, maybe continuing today's progress.
struct WatchCounterConfig: Identifiable {
    let id = UUID()
    let task: WatchTask?
    /// Today's progress to continue from (0 = a fresh goal).
    var startCount = 0
    var startSeconds: Double = 0
    /// Reopening a session the app was closed on (it comes back paused).
    var draft: WatchDraft? = nil

    init(task: WatchTask?, startCount: Int = 0, startSeconds: Double = 0) {
        self.task = task
        self.startCount = startCount
        self.startSeconds = startSeconds
    }

    init(restoring draft: WatchDraft, task: WatchTask?) {
        self.task = task
        self.startCount = draft.startCount
        self.startSeconds = draft.startSeconds
        self.draft = draft
    }
}

struct WatchZikrPage: View {
    @ObservedObject private var store = WatchZikrStore.shared
    @State private var centered: String? = "freestyle"
    @State private var running: WatchCounterConfig?
    @State private var resumeAsk: WatchTask?
    private let rowHeight: CGFloat = 122

    private enum Item: Identifiable {
        case freestyle, task(WatchTask)
        var id: String { if case .task(let t) = self { return t.id } else { return "freestyle" } }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = store.revision
            let tasks = store.tasks
            let open = tasks.filter { !store.isDone($0, at: context.date) }
            let done = tasks.filter { store.isDone($0, at: context.date) }
            let items: [Item] = [.freestyle] + (open + done).map { .task($0) }
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            face(item, now: context.date)
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                                .contentShape(Rectangle())
                                .modifier(WatchWheelFalloff(itemHeight: rowHeight))
                                .onTapGesture { tapped(item, now: context.date) }
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
                .contentMargins(.vertical, max((geo.size.height - rowHeight) / 2, 0), for: .scrollContent)
                .scrollIndicators(.hidden)
                .overlay(alignment: .bottom) {
                    if !store.hasData {
                        Text("Your tasks come from shukr on your iPhone")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        #if DEBUG
        // `-demoWatchCounter N`: start the Nth circle (0 = Freestyle) as if tapped (simulator).
        .onAppear {
            guard UserDefaults.standard.object(forKey: "demoWatchCounter") != nil else { return }
            let n = UserDefaults.standard.integer(forKey: "demoWatchCounter")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let tasks = store.tasks
                if n == 0 || tasks.isEmpty { running = WatchCounterConfig(task: nil); return }
                let task = tasks[min(n - 1, tasks.count - 1)]
                let p = store.progress(task)
                if ProcessInfo.processInfo.arguments.contains("-demoWatchContinue") {
                    running = WatchCounterConfig(task: task, startCount: task.countMode ? p.count : 0,
                                                 startSeconds: task.countMode ? 0 : p.seconds)
                } else if p.count > 0 || p.seconds >= 1 { centered = task.id; resumeAsk = task }
                else { running = WatchCounterConfig(task: task) }
            }
        }
        #endif
        .fullScreenCover(item: $running) { config in
            WatchCounterView(config: config)
        }
        .onAppear { reopenDraft() }
        .alert(resumeAsk?.title ?? "", isPresented: Binding(get: { resumeAsk != nil }, set: { if !$0 { resumeAsk = nil } }),
               presenting: resumeAsk) { task in
            let p = store.progress(task)
            Button(task.countMode ? "Continue from \(p.count)" : "Continue from \(minutesText(p.seconds))") {
                running = WatchCounterConfig(task: task, startCount: task.countMode ? p.count : 0,
                                             startSeconds: task.countMode ? 0 : p.seconds)
                resumeAsk = nil
            }
            Button("Start over") { running = WatchCounterConfig(task: task); resumeAsk = nil }
            Button("Cancel", role: .cancel) { resumeAsk = nil }
        } message: { task in
            let p = store.progress(task)
            Text(task.countMode
                 ? "You've done \(p.count) of \(task.goal) today. Pick up from there, or count a fresh \(task.goal)?"
                 : "You've done \(minutesText(p.seconds)) of \(task.goal) min today. Pick up from there, or start a fresh \(task.goal) min?")
        }
    }

    @ViewBuilder
    private func face(_ item: Item, now: Date) -> some View {
        switch item {
        case .freestyle:
            WatchZikrFace(title: "Zikr", icon: "circle.hexagonpath", subtitle: "tap to freestyle", fraction: 1)
        case .task(let task):
            let p = store.progress(task, at: now)
            let done = store.isDone(task, at: now)
            WatchZikrFace(title: task.title, mantraLine: task.mantraLine,
                          subtitle: done ? "done today" : (task.countMode ? "\(p.count) of \(task.goal)"
                                                                           : "\(Int(p.seconds / 60)) of \(task.goal) min"),
                          fraction: store.fraction(task, at: now), done: done)
        }
    }

    /// A session the app was closed on comes back, paused (or has just been saved, if stale).
    private func reopenDraft() {
        guard running == nil, let draft = store.settleDraft() else { return }
        let task = draft.taskID.flatMap { id in store.tasks.first { $0.id == id } }
        running = WatchCounterConfig(restoring: draft, task: task)
    }

    private func tapped(_ item: Item, now: Date) {
        guard centered == item.id else {
            withAnimation(.snappy) { centered = item.id }
            return
        }
        WatchHaptics.tick()
        switch item {
        case .freestyle:
            running = WatchCounterConfig(task: nil)
        case .task(let task):
            let p = store.progress(task, at: now)
            if !store.isDone(task, at: now) && (p.count > 0 || p.seconds >= 1) {
                resumeAsk = task
            } else {
                running = WatchCounterConfig(task: task)
            }
        }
    }
}

func minutesText(_ seconds: Double) -> String {
    let s = Int(seconds)
    return s >= 3600 ? "\(s / 3600)h \((s % 3600) / 60)m" : (s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s")
}

// MARK: - Counter

struct WatchCounterView: View {
    let config: WatchCounterConfig
    @Environment(\.dismiss) private var dismiss

    @State private var count = 0                 // the ring's count, including a continued start
    @State private var startedAt = Date()
    @State private var pausedAt: Date?
    @State private var pausedTotal: TimeInterval = 0
    @State private var lastCountAt: Date?
    @State private var countingInSets = false
    @State private var finished: WatchZikrRecord?
    @State private var finishArmed = false
    @State private var finishArmToken = 0
    @State private var now = Date()
    @State private var runtime = WatchRuntime()
    /// Kept in state: made inside `body`, every tap re-rendered a new timer and it never fired
    /// while tapping faster than once a second (timed goals froze).
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var lastCountActive: Double = 0
    // Digital Crown counting: each detent forward = one tap's worth; backwards does nothing (− is on
    // screen), so the crown's value only ever moves the baseline down.
    @State private var crown: Double = 0
    @State private var crownBase: Double = 0
    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var wristDown
    /// "Pinch to count · or turn the Crown", once, on the first session.
    @AppStorage("watch.countHintSeen", store: WatchStore.defaults) private var hintSeen = false
    @State private var showHint = false
    // The phone's drag "pump": down past the threshold counts, back up half as far re-arms.
    @State private var dragArmed = true
    @State private var highest: CGFloat = 0
    @State private var lowest: CGFloat = 0
    @State private var dragCounted = false
    private let threshold: CGFloat = 28

    private var task: WatchTask? { config.task }
    private var paused: Bool { pausedAt != nil }
    private var step: Int {
        #if DEBUG
        let demo = UserDefaults.standard.integer(forKey: "demoWatchStep")   // `-demoWatchStep 3`
        if demo > 1 { return demo }
        #endif
        return task?.step ?? WatchZikrStore.shared.freestyleStep
    }
    private var tapWorth: Int { countingInSets && step > 1 ? step : 1 }
    private var sessionCount: Int { count - config.startCount }
    /// Time spent counting, pauses excluded.
    private func activeSeconds(at date: Date) -> Double {
        max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pausedTotal)
    }
    private var fraction: Double {
        guard let task else { return Double(count % 100) / 100 }
        return task.countMode ? Double(count) / Double(task.goal)
                              : (config.startSeconds + activeSeconds(at: now)) / Double(task.goal * 60)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let finished {
                    WatchResultsView(record: finished, task: task) { close() }
                } else {
                    counter
                    if paused {
                        // Solid, so nothing behind it makes it hard to read (owner).
                        pauseScreen
                            .background(Color.black.ignoresSafeArea())
                            .transition(.opacity)
                    }
                }
            }
            // No bar while paused or on the results: watchOS would put its own ✕ there, which
            // drops the session in one tap. Resume / Finish early / Done are on the screen.
            .toolbar(paused || finished != nil ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if finished == nil && !paused {
                    // In the slot watchOS gives its own ✕ (which would drop the count in one tap).
                    ToolbarItem(placement: .cancellationAction) {
                        HStack(spacing: 4) {
                            Button { minus() } label: { Image(systemName: "minus") }
                            if step > 1 {
                                Button {
                                    WatchHaptics.tick()
                                    withAnimation(.easeInOut(duration: 0.2)) { countingInSets.toggle() }
                                } label: {
                                    Text("+\(step)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(countingInSets ? Color.green : .primary)
                                }
                                .background(Circle().fill(countingInSets ? Color.green.opacity(0.2) : .clear))
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { togglePause() } label: { Image(systemName: "pause.fill") }
                    }
                }
            }
        }
        .onAppear {
            if let draft = config.draft {
                count = draft.count
                startedAt = draft.startedAt
                pausedTotal = draft.pausedTotal
                pausedAt = draft.pausedSince
                lastCountActive = draft.lastCountActive
                countingInSets = draft.countingInSets
                return
            }
            count = config.startCount
            startedAt = Date()
            runtime.start()
            crownFocused = true
            if !hintSeen {
                hintSeen = true
                withAnimation(.easeOut(duration: 0.3).delay(0.6)) { showHint = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { withAnimation(.easeIn(duration: 0.4)) { showHint = false } }
            }
            #if DEBUG
            // `-demoWatchTaps N [-demoWatchPause] [-demoWatchFinish]` (simulator checks).
            let taps = UserDefaults.standard.integer(forKey: "demoWatchTaps")
            let args = ProcessInfo.processInfo.arguments
            for i in 0..<taps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 0.15) { increment() }
            }
            let after = 1.5 + Double(taps) * 0.15
            if args.contains("-demoWatchPause") || args.contains("-demoWatchFinish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + after) { togglePause() }
            }
            if args.contains("-demoWatchFinish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + after + 1) { tappedFinish() }
                DispatchQueue.main.asyncAfter(deadline: .now() + after + 1.5) { tappedFinish() }
            }
            #endif
        }
        .onDisappear { runtime.stop() }
        .onReceive(ticker) { date in
            guard finished == nil else { return }
            if let p = pausedAt {
                // Paused over an hour, or the prayer day turned at Fajr: save it, like the store
                // does for a closed app.
                let store = WatchZikrStore.shared
                if date.timeIntervalSince(p) > 3600 || abs(store.dayStart(at: date).timeIntervalSince(store.dayStart(at: startedAt))) > 60 {
                    finish()
                }
                return
            }
            now = date
            // A timed goal stops itself, like the phone.
            if let task, !task.countMode, fraction >= 1 { reachedGoal() }
        }
    }

    private var counter: some View {
        ZStack {
            WatchCountRing(fraction: fraction)
            // Just the number, like the phone: nothing says what's being recited (owner: privacy).
            // It's also the Double Tap target (Series 9+ / Ultra 2): pinch finger and thumb and it
            // counts like a tap. Not hit-testable: screen touches go to the tap / pump gesture.
            Button { increment() } label: {
                Text("\(count)")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.15), value: count)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(false)
            .handGestureShortcut(.primaryAction, isEnabled: !paused && finished == nil)
            if showHint {
                VStack(spacing: 2) {
                    Image(systemName: "hand.pinch")
                    Text("Pinch to count")
                    Text("or turn the Crown")
                }
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .offset(y: 46)
                .transition(.opacity)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(countGesture)
        // The crown counts here (nothing on this screen scrolls). Detent haptics are off: each
        // count plays the tap's own haptic instead.
        .focusable(!paused && finished == nil)
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 1,
                              sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, value in crownTurned(to: value) }
        .opacity(paused ? 0 : 1)
    }

    /// A detent forward counts; backwards only moves the baseline. Ignored with the wrist down
    /// (dimmed screen), so a sleeve brushing the crown doesn't count.
    private func crownTurned(to value: Double) {
        guard !paused, finished == nil, !wristDown else { crownBase = value; return }
        if value < crownBase { crownBase = value; return }
        while value - crownBase >= 1 {
            crownBase += 1
            increment()
        }
    }

    /// One gesture for both: a touch that barely moves is a tap (+1 / +N); a drag counts on each
    /// pump, like the phone.
    private var countGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !paused, finished == nil else { return }
                let y = value.translation.height
                highest = min(highest, y)
                lowest = max(lowest, y)
                if dragArmed && y - highest > threshold {
                    dragArmed = false
                    dragCounted = true
                    increment()
                    lowest = y
                } else if !dragArmed && lowest - y > threshold / 2 {
                    dragArmed = true
                    highest = y
                }
            }
            .onEnded { value in
                defer { dragArmed = true; highest = 0; lowest = 0; dragCounted = false }
                guard !paused, finished == nil else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if !dragCounted && moved < 12 { increment() }
            }
    }

    private func increment() {
        if showHint { withAnimation(.easeIn(duration: 0.3)) { showHint = false } }
        let before = count
        count = min(count + tapWorth, 10_000)
        lastCountAt = Date()
        lastCountActive = activeSeconds(at: Date())
        tapWorth > 1 ? WatchHaptics.set() : WatchHaptics.count()
        if count / 100 > before / 100 { WatchHaptics.hundred() }
        if let task, task.countMode, count >= task.goal, before < task.goal { reachedGoal() } else { saveDraft() }
    }

    /// The session so far, so closing the app never loses it.
    private func saveDraft() {
        guard finished == nil, sessionCount > 0 else { WatchZikrStore.shared.draft = nil; return }
        WatchZikrStore.shared.draft = WatchDraft(
            taskID: task?.id, name: task?.name ?? "",
            mode: task == nil ? 0 : (task!.countMode ? 2 : 1),
            targetMin: task.map { $0.countMode ? 0 : $0.goal } ?? 0,
            targetCount: task.map { $0.countMode ? $0.goal : 0 } ?? 0,
            startCount: config.startCount, startSeconds: config.startSeconds, count: count,
            startedAt: startedAt, pausedTotal: pausedTotal, pausedAt: pausedAt,
            lastCountActive: lastCountActive, countingInSets: countingInSets,
            dayStart: WatchZikrStore.shared.dayStart(at: startedAt), savedAt: Date())
    }

    private func minus() {
        guard count > config.startCount else { return }
        count = max(count - tapWorth, config.startCount)
        WatchHaptics.minus()
        saveDraft()
    }

    private func togglePause() {
        WatchHaptics.tick()
        withAnimation(.easeInOut(duration: 0.25)) {
            if let p = pausedAt {
                pausedTotal += Date().timeIntervalSince(p)
                pausedAt = nil
                runtime.start()
                crownFocused = true
            } else {
                pausedAt = Date()
                finishArmed = false
                runtime.stop()      // a paused session doesn't need to outlive a lowered wrist
            }
        }
        saveDraft()
    }

    private func reachedGoal() {
        WatchHaptics.goal()
        finish()
    }

    private func finish() {
        let seconds = activeSeconds(at: Date())
        guard sessionCount > 0 else { close(); return }
        let record = WatchZikrRecord(
            id: UUID().uuidString,
            taskID: task?.id,
            name: task?.name ?? "",
            mode: task == nil ? 0 : (task!.countMode ? 2 : 1),
            targetMin: task.map { $0.countMode ? 0 : $0.goal } ?? 0,
            targetCount: task.map { $0.countMode ? $0.goal : 0 } ?? 0,
            count: sessionCount,
            start: startedAt,
            seconds: seconds,
            perCount: lastCountActive / Double(max(sessionCount, 1)))
        WatchZikrStore.shared.draft = nil
        WatchZikrStore.shared.record(record)
        runtime.stop()
        withAnimation(.easeOut(duration: 0.25)) { finished = record }
    }

    private func close() {
        WatchZikrStore.shared.draft = nil
        runtime.stop()
        dismiss()
    }

    // MARK: Pause

    private var pauseScreen: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("paused")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text(task?.title ?? "Freestyle")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    stat("\(sessionCount)", "count")
                    stat(minutesText(activeSeconds(at: Date())), "time")
                    stat(sessionCount > 0 ? String(format: "%.1fs", lastCountActive / Double(sessionCount)) : "–", "pace")
                }
                if let task, task.memo != nil || WatchMemoButton.demo {
                    WatchMemoButton(task: task)
                }
                Button { togglePause() } label: {
                    Text("Resume")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.watchSage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.watchSage)
                .handGestureShortcut(.primaryAction)   // Double Tap resumes
                Button { tappedFinish() } label: {
                    Text(finishArmed ? "Tap again to finish" : "Finish early")
                        .font(.system(size: 12, weight: finishArmed ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(finishArmed ? Color.green : .secondary)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .light, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }

    /// Two taps, like the phone: the first arms it (green), it disarms after 3 s.
    private func tappedFinish() {
        if finishArmed {
            finish()
        } else {
            WatchHaptics.tick()
            withAnimation(.easeInOut(duration: 0.3)) { finishArmed = true }
            finishArmToken += 1
            let token = finishArmToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if token == finishArmToken { withAnimation(.easeInOut(duration: 0.3)) { finishArmed = false } }
            }
        }
    }
}

/// The counter's ring: the pale track and the green arc filling toward the goal.
struct WatchCountRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Results

struct WatchResultsView: View {
    let record: WatchZikrRecord
    let task: WatchTask?
    let done: () -> Void
    @ObservedObject private var store = WatchZikrStore.shared
    @State private var popped = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.watchSage)
                .scaleEffect(popped ? 1 : 0.4)
                .opacity(popped ? 1 : 0)
            Text("\(record.count) · saved")
                .font(.system(size: 18, weight: .light, design: .rounded))
            Text(line)
                .font(.system(size: 12, weight: .thin, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done", action: done)
                .buttonStyle(.bordered)
                .tint(.watchSage)
                .handGestureShortcut(.primaryAction)   // Double Tap closes
                .padding(.top, 4)
        }
        .padding(.horizontal, 6)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { popped = true } }
    }

    private var line: String {
        let _ = store.revision
        guard let task else { return "sent to your iPhone's history" }
        let p = store.progress(task)
        return task.countMode ? "\(task.title) · \(p.count) of \(task.goal) today"
                              : "\(task.title) · \(Int(p.seconds / 60)) of \(task.goal) min today"
    }
}

// MARK: - Voice memo

/// The zikr's voice memo from the phone (how it's said): play / stop with a thin progress ring.
struct WatchMemoButton: View {
    let task: WatchTask
    @ObservedObject private var store = WatchZikrStore.shared
    @StateObject private var player = WatchMemoPlayer()

    var body: some View {
        let _ = store.revision
        let url = store.memoURL(for: task) ?? Self.demoURL
        Button {
            guard let url else { return }
            player.toggle(url)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2)
                    Circle().trim(from: 0, to: player.progress)
                        .stroke(Color.watchSage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 9))
                }
                .frame(width: 22, height: 22)
                Text(url == nil ? "getting the memo…" : (player.isPlaying ? "playing" : "hear how it's said"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(url == nil ? .secondary : .primary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .onAppear { store.requestMemoIfNeeded(for: task) }
        .onDisappear { player.stop() }
    }

    /// DEBUG `-demoWatchMemo`: a short sample tone as the memo (the simulators can't transfer
    /// files between the phone and the watch).
    static var demo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demoWatchMemo")
        #else
        return false
        #endif
    }

    static var demoURL: URL? {
        guard demo else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-memo.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let rate = 16_000, samples = rate * 2
            var pcm = Data(capacity: samples * 2)
            for i in 0..<samples {
                let v = Int16(sin(Double(i) * 2 * .pi * 330 / Double(rate)) * 6000 * min(1, Double(samples - i) / 4000))
                withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
            }
            var wav = Data()
            func put(_ s: String) { wav.append(s.data(using: .ascii)!) }
            func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
            func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
            put("RIFF"); put32(UInt32(36 + pcm.count)); put("WAVE"); put("fmt ")
            put32(16); put16(1); put16(1); put32(UInt32(rate)); put32(UInt32(rate * 2)); put16(2); put16(16)
            put("data"); put32(UInt32(pcm.count)); wav.append(pcm)
            try? wav.write(to: url)
        }
        return url
    }
}

final class WatchMemoPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ url: URL) { isPlaying ? stop() : play(url) }

    private func play(_ url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = CGFloat(p.currentTime / p.duration)
            }
        } catch {
            print("⌚️ memo can't play: \(error)")
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.stop() }
    }
}

// MARK: - Wrist down

/// A mindfulness runtime session while counting, so lowering the wrist doesn't end it
/// (Info.plist WKBackgroundModes: mindfulness).
final class WatchRuntime: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    /// One being invalidated (after a pause): a new one can't start until it has ended.
    private var ending: WKExtendedRuntimeSession?
    private var wantsStart = false
    private var retried = false

    func start() {
        guard session == nil else { return }
        #if DEBUG
        // Scripted simulator runs kill the app between launches; a session left behind ends
        // later and takes the next run's app down with it.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demoWatch") }) { return }
        #endif
        if ending != nil { wantsStart = true; return }     // a quick pause → resume
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    func stop() {
        wantsStart = false
        // Also one still starting (.scheduled): invalidating that cancels it.
        if let s = session, s.state == .running || s.state == .scheduled {
            s.invalidate()
            ending = s
        }
        session = nil
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        DispatchQueue.main.async {
            if extendedRuntimeSession === self.ending {
                self.ending = nil
                if self.wantsStart { self.wantsStart = false; self.start() }
                return
            }
            guard extendedRuntimeSession === self.session else { return }
            self.session = nil
            if let error {
                print("⌚️ runtime session ended: \(reason.rawValue) \(error)")
                // It didn't start (e.g. the last one was still ending): once more, a moment later.
                if !self.retried {
                    self.retried = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
                }
            }
        }
    }
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    /// The hour a mindfulness session gets is nearly up: a buzz so a long session isn't silently
    /// dropped (the count stays on screen; finishing still saves it).
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WKInterfaceDevice.current().play(.notification)
    }
}

// MARK: - Settings page

struct WatchSettingsPage: View {
    @AppStorage(WatchHaptics.key, store: WatchStore.defaults) private var strength = 1
    private let names = ["Light", "Medium", "Strong"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                Text("haptics")
                    .font(.system(size: 10, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(0..<3, id: \.self) { level in
                    Button {
                        strength = level
                        WatchHaptics.count()
                    } label: {
                        HStack {
                            Text(names[level]).font(.system(size: 15, design: .rounded))
                            Spacer()
                            if strength == level {
                                Image(systemName: "checkmark").foregroundStyle(Color.green)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(strength == level ? Color.green.opacity(0.15) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                Text("How each count feels on your wrist. Tap one to try it.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("counting")
                    .font(.system(size: 10, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Tap anywhere, or drag down", systemImage: "hand.tap")
                    Label("Pinch finger and thumb (Double Tap)", systemImage: "hand.pinch")
                    Label("Turn the Digital Crown forward, a click a count", systemImage: "digitalcrown.arrow.clockwise")
                }
                .font(.system(size: 12, design: .rounded))
                Text("Double Tap needs Apple Watch Series 9 or Ultra 2 or later. The crown doesn't count while your wrist is down.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
