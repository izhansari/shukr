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
    /// Your usual seconds per count for this zikr (the phone's `MantraModel.secondsPerCount`).
    let pace: Double?

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
        pace = (row["pace"] as? Double).flatMap { $0 > 0 ? $0 : nil }
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
    /// Counting with the Crown (screen taps off) — kept so a reopened session stays that way.
    var crownMode: Bool? = nil
    var postSalah: Bool? = nil
    /// Which counter session wrote it (a reopened one keeps it).
    var sessionID: String? = nil

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
    /// Tasbih Fatimah: the phone saves it under that zikr, like its own post-salah session.
    var postSalah: Bool? = nil

    var userInfo: [String: Any] {
        var info: [String: Any] = ["type": "zikrSession", "id": id, "name": name, "mode": mode,
                                   "targetMin": targetMin, "targetCount": targetCount, "count": count,
                                   "start": start.timeIntervalSince1970, "seconds": seconds]
        if let taskID { info["taskID"] = taskID }
        if let perCount { info["perCount"] = perCount }
        if postSalah == true { info["postSalah"] = true }
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
        static let draft = "watch.zikr.draft", postSalahPace = "watch.zikr.postSalahPace"
        static let azkar = "watch.zikr.azkar", freestylePick = "watch.zikr.freestylePick"
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
        d.set(context["postSalahPace"] as? Double ?? 0, forKey: Key.postSalahPace)
        if let azkar = context["azkar"] as? [String] { d.set(azkar, forKey: Key.azkar) }
        dropConfirmed()
        bump()
        return true
    }

    /// Has the phone ever sent its tasks?
    var hasData: Bool { d.bool(forKey: Key.hasData) }
    var freestyleStep: Int { d.integer(forKey: Key.freestyleStep) }
    /// Your azkar from the phone, for the Freestyle picker.
    var azkar: [String] { d.stringArray(forKey: Key.azkar) ?? [] }
    /// The zikr Freestyle counts under (the last pick; nil = just count).
    var freestylePick: String? {
        get { d.string(forKey: Key.freestylePick).flatMap { $0.isEmpty ? nil : $0 } }
        set { d.set(newValue ?? "", forKey: Key.freestylePick); bump() }
    }
    /// Tasbih Fatimah's usual seconds per count (nil until the phone has one).
    var postSalahPace: Double? { let v = d.double(forKey: Key.postSalahPace); return v > 0 ? v : nil }

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

    init() {
        // Builds before round 4 kept the draft in the app-group suite: move it over once.
        if UserDefaults.standard.data(forKey: Key.draft) == nil, let old = WatchStore.defaults.data(forKey: Key.draft) {
            UserDefaults.standard.set(old, forKey: Key.draft)
        }
        if WatchStore.defaults.object(forKey: Key.draft) != nil { WatchStore.defaults.removeObject(forKey: Key.draft) }
    }

    /// In the standard defaults: written often, and every app-group write would redraw anything
    /// bound to that suite (the Settings page's @AppStorage).
    var draft: WatchDraft? {
        get { UserDefaults.standard.data(forKey: Key.draft).flatMap { try? JSONDecoder().decode(WatchDraft.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.draft) }
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
                                   perCount: draft.lastCountActive / Double(draft.sessionCount),
                                   postSalah: draft.postSalah))
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

/// The counter's haptics. watchOS has no intensity control — only a fixed set of `WKHapticType`s —
/// so the levels are different types: `.click` is the one soft tap (the lightest there is);
/// `.directionUp` / `.directionDown` a little stronger; `.start` / `.stop` firm; `.success`,
/// `.retry`, `.failure`, `.notification` and the navigation ones are longer patterns, too much for
/// every count. Off silences counting only (counts, sets, hundreds, phrase / goal buzzes, −);
/// buttons' clicks, marking, the qibla and notifications keep theirs (owner, 2026-09-29).
enum WatchHaptics {
    // One feel, no choice (owner, idea GUSV): every count is the soft tap; the moments that mean
    // something — each 100, each Tasbih Fatimah step, a session finishing onto its results — are one
    // level stronger. (The old strength setting, `watch.hapticStrength`, is no longer read.)
    private static let soft: WKHapticType = .click
    private static let stronger: WKHapticType = .directionUp

    static func count() { WKInterfaceDevice.current().play(soft) }
    /// Counting in sets: the phone's ta-ta-ta. watchOS drops haptics played that close together,
    /// so one built-in multi-tap pattern (.retry) instead.
    static func set() { WKInterfaceDevice.current().play(.retry) }
    /// Every 100, a Tasbih Fatimah step, a session done: one level above a count.
    static func milestone() { WKInterfaceDevice.current().play(stronger) }
    static func minus() { WKInterfaceDevice.current().play(.directionDown) }
    /// Buttons (pause, finish, +N): always, like every other button click.
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
    /// Freestyle: the zikr it counts under, as a small chip inside the circle (tap → pick one);
    /// the rest of the circle still starts counting in one tap.
    var pick: (label: String, chosen: Bool, action: () -> Void)? = nil

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
            // Freestyle's zikr chip on the circle's bottom edge (owner, YGF3): in the middle it sat
            // where a thumb aims to start, and opened the picker instead.
            if let pick {
                VStack {
                    Spacer()
                    Button(action: pick.action) {
                        HStack(spacing: 2) {
                            Text(pick.label).lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                        }
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(pick.chosen ? Color.watchSage : Color.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .frame(maxWidth: 88)
                        .background(Capsule().fill(Color.black))   // over the ring
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .offset(y: 10)
                }
            }
        }
        .frame(width: 112, height: 112)
    }
}

/// A wheel circle pressed: it dims a touch, like the system's buttons.
/// Draws its label as it is, pressed or not (the counter's background, Double Tap's button: no press dimming).
struct WatchStillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

struct WatchCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

    /// Tasbih Fatimah after a prayer: 33 · 33 · 34 in one session (the phone's post-salah zikr).
    var postSalah = false
    /// Freestyle under a zikr (the Freestyle picker): the session saves with that zikr, like the phone's.
    var zikrName: String? = nil

    init(task: WatchTask?, startCount: Int = 0, startSeconds: Double = 0) {
        self.task = task
        self.startCount = startCount
        self.startSeconds = startSeconds
    }

    init(postSalah: Bool) {
        self.task = nil
        self.postSalah = postSalah
    }

    init(restoring draft: WatchDraft, task: WatchTask?) {
        self.task = task
        // The task was deleted meanwhile: no offset from its progress (it saves as an unlinked
        // session under the draft's name).
        let orphan = task == nil && draft.taskID != nil
        self.startCount = orphan ? 0 : draft.startCount
        self.startSeconds = orphan ? 0 : draft.startSeconds
        self.draft = draft
        self.restoredCount = orphan ? draft.sessionCount : draft.count
        self.postSalah = draft.postSalah ?? false
    }

    /// The ring's count when reopening a draft.
    var restoredCount = 0
}

struct WatchZikrPage: View {
    @ObservedObject private var store = WatchZikrStore.shared
    @State private var centered: String? = "freestyle"
    @State private var running: WatchCounterConfig?
    @State private var resumeAsk: WatchTask?
    /// The task the open session belongs to, so closing it can move on once it's done.
    @State private var sessionTaskID: String?
    @State private var showZikrPicker = false
    private let rowHeight: CGFloat = 122

    private enum Item: Identifiable {
        case freestyle, task(WatchTask)
        var id: String { if case .task(let t) = self { return t.id } else { return "freestyle" } }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = store.revision
            // Your order, a task done today keeping its place (owner, 2026-09-29, as on the phone).
            let items: [Item] = [.freestyle] + store.tasks.map { .task($0) }
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            // A real button (owner, YGF3: starting was hard to hit): the system's
                            // press feedback and its touch slop — a bare tap gesture in a scrolling
                            // wheel dropped any tap with a little finger movement. The whole circle
                            // is the target.
                            Button { tapped(item, now: context.date) } label: {
                                face(item, now: context.date)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                                    .contentShape(Circle().inset(by: -6))
                            }
                            .buttonStyle(WatchCircleButtonStyle())
                            .modifier(WatchWheelFalloff(itemHeight: rowHeight))
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
                            .padding(.bottom, 16)
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
        .sheet(isPresented: $showZikrPicker) { WatchZikrPicker(isPresented: $showZikrPicker) }
        .fullScreenCover(item: $running, onDismiss: landAfterSession) { config in
            WatchCounterView(config: config)
        }
        .onChange(of: running?.task?.id) { _, id in if let id { sessionTaskID = id } }
        .onAppear { reopenDraft() }
        // Continue or start over (owner: shorter) — the zikr's name, then the two choices; the
        // sheet's own ✕ (top left) cancels.
        .sheet(item: $resumeAsk) { task in
            let p = store.progress(task)
            VStack(spacing: 8) {
                Text(task.title)
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(task.countMode ? "Continue from \(p.count)" : "Continue from \(minutesText(p.seconds))") {
                    start(WatchCounterConfig(task: task, startCount: task.countMode ? p.count : 0,
                                             startSeconds: task.countMode ? 0 : p.seconds))
                }
                .tint(.watchSage)
                Button("Start over") { start(WatchCounterConfig(task: task)) }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func face(_ item: Item, now: Date) -> some View {
        switch item {
        case .freestyle:
            // The picked zikr, if any, under the title (one tap still starts counting).
            WatchZikrFace(title: "Zikr", icon: "circle.hexagonpath", subtitle: "tap to count", fraction: 1,
                          pick: store.azkar.isEmpty ? nil
                              : (store.freestylePick ?? "Pick a zikr", store.freestylePick != nil, { showZikrPicker = true }))
        case .task(let task):
            let p = store.progress(task, at: now)
            let done = store.isDone(task, at: now)
            WatchZikrFace(title: task.title, mantraLine: task.mantraLine,
                          subtitle: done ? "done today" : (task.countMode ? "\(p.count) of \(task.goal)"
                                                                           : "\(Int(p.seconds / 60)) of \(task.goal) min"),
                          fraction: store.fraction(task, at: now), done: done)
        }
    }

    /// Closes the continue sheet, then opens the counter once it's gone (two presentations at
    /// once can drop the second).
    private func start(_ config: WatchCounterConfig) {
        resumeAsk = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { running = config }
    }

    /// Back from a task's session: once it's done, centre the next task still to do after it in
    /// your order (wrapping), else Freestyle — the phone's rule (it stays in its own place).
    private func landAfterSession() {
        guard let id = sessionTaskID else { return }
        sessionTaskID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tasks = store.tasks
            guard let i = tasks.firstIndex(where: { $0.id == id }), store.isDone(tasks[i]) else { return }
            let next = (tasks[(i + 1)...] + tasks[..<i]).first { !store.isDone($0) }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { centered = next?.id ?? "freestyle" }
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
            var config = WatchCounterConfig(task: nil)
            config.zikrName = store.freestylePick
            running = config
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
    // Digital Crown counting: one count per step the counting way (WatchCrownGate); a step the other
    // way reloads, never subtracts (− is on screen).
    @State private var crown: Double = 0
    @State private var crownGate = WatchCrownGate(direction: WatchCrownDirection.current.fixed)
    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var wristDown
    /// "Pinch to count · or turn the Crown", once, on the first session.
    @AppStorage("watch.countHintSeen", store: WatchStore.defaults) private var hintSeen = false
    @State private var showHint = false
    /// Counting with the Crown: taps, drags and pinches stop counting — the Crown on its own (a hand
    /// holding the watch taps it by accident). The first crown count turns it on; the badge turns it
    /// off (owner: tap and pinch together, or the Crown alone — no setting for all three).
    @State private var crownMode = false
    @State private var crownNote = false
    /// The pause screen's page: 0 the card, 1 haptics. Back to the card on every pause.
    @State private var pausePage = 0
    @State private var draftToken = 0
    /// When ‹ last resumed (− ignores taps just after; it shares the spot).
    @State private var resumedAt = Date.distantPast
    @State private var sessionID = UUID().uuidString
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The phone's drag "pump": down past the threshold counts, back up half as far re-arms.
    @State private var dragArmed = true
    @State private var highest: CGFloat = 0
    @State private var lowest: CGFloat = 0
    @State private var dragCounted = false
    private let threshold: CGFloat = 28

    private var task: WatchTask? { config.task }
    private var paused: Bool { pausedAt != nil }
    private var postSalah: Bool { config.postSalah }
    /// Tasbih Fatimah's phrase at the count (0-based), how far into it, and of how many.
    private var phase: (index: Int, done: Int, of: Int) { WatchPostSalah.phase(at: count) }

    private var step: Int {
        if postSalah { return 0 }   // no sets in Tasbih Fatimah (the phone doesn't offer them)
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
        if postSalah { return Double(count) / Double(WatchPostSalah.total) }
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
                    // The phone's tasbeeh page colour (bgColor, dark), edge to edge — the neumorphic
                    // band and inset beads only read on it (owner: no fade at the edges). Black with
                    // the wrist down, like the rest of watchOS's always-on screens.
                    //
                    // Double Tap's button (Series 9+ / Ultra 2) is this background: a real, full-size, visible
                    // control, so watchOS finds and presses it at once — the 2 × 2 pt, near-invisible one it had was
                    // pressed ~2 s late, after a dim (owner; Sami's review, decision watch-extra-fixes A). The counter
                    // above takes every touch, so only a pinch reaches it; it counts like a tap, not in crown mode
                    // (owner: tap and pinch together, or the Crown on its own).
                    Button { increment() } label: { wristDown ? Color.black : WatchNeu.bg }
                        .buttonStyle(WatchStillButtonStyle())
                        .handGestureShortcut(.primaryAction, isEnabled: !paused && finished == nil && !crownMode)
                        .accessibilityLabel("Count")
                        .ignoresSafeArea()
                        .opacity(paused ? 0 : 1)
                    counter
                    if paused {
                        // Solid, so nothing behind it makes it hard to read (owner).
                        pauseScreen
                            .background(Color.black.ignoresSafeArea())
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            // The − / +N and pause buttons live in the bar, which is always filled so watchOS never
            // puts its own ✕ in the slot (one tap would drop the session). While paused / on the
            // results (Resume, Finish early and Done are on the screen) the whole bar is hidden:
            // watchOS 26 draws a glass circle behind each item that stayed as an empty bubble when
            // only the buttons faded (owner). The system ✕ lives in the same bar, so it can't
            // appear while the bar is hidden.
            .toolbarVisibility(finished == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbar {
                if paused {
                    // Paused: ‹ resumes (owner, idea GUSV: Resume as a back chevron, top left) — in the
                    // slot watchOS gives its own ✕, so that can't appear. Double Tap resumes too.
                    ToolbarItem(placement: .cancellationAction) {
                        Button { togglePause() } label: { Image(systemName: "chevron.left") }
                            .handGestureShortcut(.primaryAction)
                            .accessibilityLabel("Resume")
                    }
                } else {
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
                if let id = draft.sessionID { sessionID = id }
                count = config.restoredCount
                crownMode = draft.crownMode ?? false
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
            // `-demoWatchPreset N`: start the count at N (e.g. 198, then 2 taps to see 199 → 200).
            if UserDefaults.standard.object(forKey: "demoWatchPreset") != nil {
                count = UserDefaults.standard.integer(forKey: "demoWatchPreset")
            }
            for i in 0..<taps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 0.15) { increment() }
            }
            let after = 1.5 + Double(taps) * 0.15
            if args.contains("-demoWatchCrown") {   // crown mode, then a screen tap (the note)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { crownMode = true } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(taps) * 0.15) { screenCount() }
            }
            if args.contains("-demoWatchPause") || args.contains("-demoWatchFinish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + after) { togglePause() }
            }
            // `-demoWatchPausePage 1` (with -demoWatchPause): the haptics page.
            if UserDefaults.standard.integer(forKey: "demoWatchPausePage") == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + after + 0.8) { withAnimation { pausePage = 1 } }
            }
            if args.contains("-demoWatchFinish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + after + 1) { tappedFinish() }
                DispatchQueue.main.asyncAfter(deadline: .now() + after + 1.5) { tappedFinish() }
            }
            #endif
        }
        .onDisappear { runtime.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app (the Crown to the watch face, another app) pauses, like the phone — only in the
            // background: inactive is the wrist down / a banner, and counting goes on through those (the runtime
            // session keeps it). Pausing saves the draft and ends the runtime session (decision watch-extra-fixes A).
            if phase == .background, !paused, finished == nil { togglePause(); return }
            if phase != .active { saveDraft(now: true) }
        }
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
            // The phone's counter, ported (WatchTasbeehPort.swift): TasbeehCountView — the count
            // within the hundred, beads round the outside, the hundreds as dots below the number —
            // under NeuCircularProgressView's "fine" ring. Just the number: nothing says what's
            // being recited (owner: privacy).
            WatchTasbeehCountView(tasbeeh: count)
            WatchNeuProgressRing(progress: fraction, animating: !paused)
                .allowsHitTesting(false)
            // Double Tap counts through the page's background (body).
            if crownMode {
                // Tap the badge (or the note) to let screen taps count again.
                Button { setCrownMode(false) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "digitalcrown.arrow.clockwise")
                            .font(.system(size: 12, weight: .light))
                        if crownNote {
                            Text("Counting with the Crown")
                                .font(.system(size: 11, weight: .light, design: .rounded))
                            Text("tap here for tap & pinch")
                                .font(.system(size: 9, weight: .light, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .offset(y: crownNote ? 50 : 38)
                .transition(.opacity)
            } else if let task, !task.countMode, !postSalah {
                // Timed task: a quiet "4:12 left" (owner: fine for privacy).
                Text(timeLeftText(task))
                    .font(.system(size: 11, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(y: 34)
            }
            if postSalah {
                // One up, one down (owner): the phrase above the centred count, "7 of 33" and the
                // three bars below it, evenly inside the ring (scaled with it).
                let k = WatchNeu.scale / 0.665
                WatchPostSalahPhrase(count: count).offset(y: -34 * k)
                WatchPostSalahStrip(count: count).offset(y: 31 * k)
            }
            if showHint {
                VStack(spacing: 2) {
                    Image(systemName: "hand.pinch")
                    Text("Pinch to count, or turn the Crown")
                    Text("(turning it pauses screen taps)")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .offset(y: 46)
                .transition(.opacity)
            }
        }
        .padding(8)
        // The whole screen counts (tap-anywhere, like the phone): the touch layer covers it all, so no touch reaches
        // the background under it — Double Tap's button.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(countGesture)
        .scaleEffect(paused && !reduceMotion ? 0.94 : 1)
        // The crown counts here (nothing on this screen scrolls). Snapped to detents; detent
        // haptics are off, so the only buzz is the count's own — you feel exactly what counted.
        .focusable(!paused && finished == nil)
        .focused($crownFocused)
        .digitalCrownRotation(detent: $crown, from: -1_000_000, through: 1_000_000, by: 1,
                              sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: false,
                              onIdle: { crownGate.idle() })
        .onChange(of: crown) { _, value in crownTurned(to: value) }
        .opacity(paused ? 0 : 1)
    }

    private func timeLeftText(_ task: WatchTask) -> String {
        let left = max(0, Int(Double(task.goal * 60) - config.startSeconds - activeSeconds(at: now)))
        return String(format: "%d:%02d left", left / 60, left % 60)
    }

    private func setCrownMode(_ on: Bool) {
        WKInterfaceDevice.current().play(.click)
        withAnimation(.easeInOut(duration: 0.25)) { crownMode = on; crownNote = false }
        saveDraft()
    }

    /// A tap / pump on the screen: a count, unless counting with the Crown.
    private func screenCount() {
        guard crownMode else { increment(); return }
        // No buzz (owner): it felt like a count that didn't happen. The note says why instead.
        withAnimation(.easeOut(duration: 0.2)) { crownNote = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.easeIn(duration: 0.3)) { crownNote = false } }
    }

    /// A step the counting way counts once (WatchCrownGate); the other way reloads. Ignored with
    /// the wrist down (dimmed screen), so a sleeve brushing the crown doesn't count.
    private func crownTurned(to value: Double) {
        guard !paused, finished == nil, !wristDown else { crownGate.reset(to: value); return }
        guard crownGate.turned(to: value, at: Date()) else { return }
        if !crownMode { withAnimation(.easeOut(duration: 0.25)) { crownMode = true } }
        increment()
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
                    screenCount()
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
                if !dragCounted && moved < 12 { screenCount() }
            }
    }

    private func increment() {
        if showHint { withAnimation(.easeIn(duration: 0.3)) { showHint = false } }
        let before = count
        count = min(count + tapWorth, 10_000)
        lastCountAt = Date()
        lastCountActive = activeSeconds(at: Date())
        // One haptic per count: the stronger one replaces the count's on a milestone (watchOS drops a
        // haptic played right after another, so playing both lost the milestone). Finishing plays
        // its own in finish().
        let finishing = postSalah ? count >= WatchPostSalah.total
                                  : (task.map { $0.countMode && count >= $0.goal && before < $0.goal } ?? false)
        let milestone = postSalah ? WatchPostSalah.phase(at: count).index > WatchPostSalah.phase(at: before).index
                                  : count / 100 > before / 100
        if finishing { reachedGoal(); return }
        if milestone { WatchHaptics.milestone() } else if tapWorth > 1 { WatchHaptics.set() } else { WatchHaptics.count() }
        saveDraft()
    }

    private var sessionName: String { postSalah ? WatchPostSalah.name : task?.name ?? config.zikrName ?? config.draft?.name ?? "" }
    /// Freestyle's title: the zikr it counts under, else "Freestyle".
    private var freestyleTitle: String {
        let name = config.zikrName ?? config.draft?.name ?? ""
        return name.isEmpty ? "Freestyle" : name
    }
    private var sessionMode: Int { postSalah ? 2 : task.map { $0.countMode ? 2 : 1 } ?? config.draft?.mode ?? 0 }
    private var sessionTargetCount: Int { postSalah ? WatchPostSalah.total : task.map { $0.countMode ? $0.goal : 0 } ?? config.draft?.targetCount ?? 0 }

    /// The session so far, so closing the app never loses it. Taps save at most every 2 s; a
    /// pause, leaving the app and finishing save at once.
    private func saveDraft(now force: Bool = false) {
        guard force else {
            draftToken += 1
            let token = draftToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if token == draftToken && finished == nil { saveDraft(now: true) }
            }
            return
        }
        guard finished == nil, sessionCount > 0 else {
            // Only this session's own draft is cleared, never a newer one's.
            if WatchZikrStore.shared.draft?.sessionID == sessionID { WatchZikrStore.shared.draft = nil }
            return
        }
        WatchZikrStore.shared.draft = WatchDraft(
            taskID: task?.id ?? config.draft?.taskID, name: sessionName,
            mode: sessionMode,
            targetMin: task.map { $0.countMode ? 0 : $0.goal } ?? config.draft?.targetMin ?? 0,
            targetCount: sessionTargetCount,
            startCount: config.startCount, startSeconds: config.startSeconds, count: count,
            startedAt: startedAt, pausedTotal: pausedTotal, pausedAt: pausedAt,
            lastCountActive: lastCountActive, countingInSets: countingInSets,
            dayStart: WatchZikrStore.shared.dayStart(at: startedAt), savedAt: Date(), crownMode: crownMode,
            postSalah: postSalah ? true : nil, sessionID: sessionID)
    }

    private func minus() {
        // − sits where the pause screen's ‹ was: a quick second tap on ‹ mustn't take one off.
        guard Date().timeIntervalSince(resumedAt) > 0.7 else { return }
        guard count > config.startCount else { return }
        count = max(count - tapWorth, config.startCount)
        WatchHaptics.minus()
        saveDraft()
    }

    private func togglePause() {
        WatchHaptics.tick()
        withAnimation(.easeInOut(duration: 0.32)) {
            if let p = pausedAt {
                pausedTotal += Date().timeIntervalSince(p)
                pausedAt = nil
                resumedAt = Date()
                runtime.start()
                crownFocused = true
            } else {
                pausedAt = Date()
                pausePage = 0
                finishArmed = false
                runtime.stop()      // a paused session doesn't need to outlive a lowered wrist
            }
        }
        saveDraft(now: true)
    }

    private func reachedGoal() { finish() }   // finish() plays the milestone onto the results

    private func finish() {
        let seconds = activeSeconds(at: Date())
        guard sessionCount > 0 else { close(); return }
        let record = WatchZikrRecord(
            id: UUID().uuidString,
            taskID: task?.id,
            name: sessionName,
            mode: sessionMode,
            targetMin: task.map { $0.countMode ? 0 : $0.goal } ?? config.draft?.targetMin ?? 0,
            targetCount: sessionTargetCount,
            count: sessionCount,
            start: startedAt,
            seconds: seconds,
            perCount: lastCountActive / Double(max(sessionCount, 1)),
            postSalah: postSalah ? true : nil)
        clearOwnDraft()
        WatchZikrStore.shared.record(record)
        runtime.stop()
        WatchHaptics.milestone()   // onto the results: one level above a count
        withAnimation(.easeOut(duration: 0.25)) { finished = record }
    }

    private func clearOwnDraft() {
        if WatchZikrStore.shared.draft?.sessionID == sessionID { WatchZikrStore.shared.draft = nil }
    }

    private func close() {
        clearOwnDraft()
        runtime.stop()
        dismiss()
    }

    // MARK: Pause

    /// Two pages, each on one screen with no scrolling (owner, 2026-09-29): the phone's pause bento
    /// with Resume / Finish early, and a swipe away the settings as toggle chips. On a watch too
    /// short for the finish tile beside the bento (`WatchScreen.roomy` false) it moves to page 2.
    private var pauseScreen: some View {
        TabView(selection: $pausePage) {
            WatchPauseStats(
                name: postSalah ? WatchPostSalah.name : task?.title ?? freestyleTitle,
                memoTask: task.flatMap { $0.memo != nil || WatchMemoButton.demo ? $0 : nil },
                count: sessionCount,
                seconds: lastCountActive,
                usualPace: postSalah ? WatchZikrStore.shared.postSalahPace : task?.pace,
                finish: WatchScreen.roomy ? finishEstimate : nil,
                finishArmed: finishArmed,
                finishEarly: tappedFinish)
                .tag(0)
            WatchPauseSettings(
                finish: WatchScreen.roomy ? nil : finishEstimate,
                crownOnly: crownMode,
                setCrownOnly: setCrownMode)
                .tag(1)
        }
        .tabViewStyle(.page)
    }

    /// A count goal's finish, at this session's pace: time left and the clock time.
    private var finishEstimate: (left: TimeInterval, at: Date)? {
        let goal = postSalah ? WatchPostSalah.total : (task.map { $0.countMode ? $0.goal : 0 } ?? 0)
        guard goal > count, sessionCount > 0, lastCountActive > 0 else { return nil }
        let left = Double(goal - count) * lastCountActive / Double(sessionCount)
        return (left, Date().addingTimeInterval(left))
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
        if record.postSalah == true { return "Tasbih Fatimah · sent to your iPhone" }
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
    /// The ring alone (beside the zikr's name on the pause screen).
    var compact = false
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
                .opacity(url == nil ? 0.5 : 1)
                if !compact {
                    Text(url == nil ? "getting the memo…" : (player.isPlaying ? "playing" : "hear how it's said"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(url == nil ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, compact ? 0 : 4)
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
        if ending != nil {                                  // a quick pause → resume
            wantsStart = true
            // If the old one never reports its end, start anyway after a second.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard self.wantsStart, self.ending != nil else { return }
                self.ending = nil
                self.wantsStart = false
                self.start()
            }
            return
        }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    func stop() {
        wantsStart = false
        retried = false
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
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async { self.retried = false }
    }
    /// The hour a mindfulness session gets is nearly up: a buzz so a long session isn't silently
    /// dropped (the count stays on screen; finishing still saves it).
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WKInterfaceDevice.current().play(.notification)
    }
}

// MARK: - Settings page

struct WatchSettingsPage: View {

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                Text("counting")
                    .font(.system(size: 10, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Tap anywhere, or drag down", systemImage: "hand.tap")
                    Label("Pinch finger and thumb (Double Tap)", systemImage: "hand.pinch")
                    Label("Turn the Digital Crown a step to count, a step back to get the next one ready", systemImage: "digitalcrown.arrow.clockwise")
                }
                .font(.system(size: 12, design: .rounded))
                Text("Tap and pinch count together. Turning the Crown switches that session to the Crown alone; tap its badge to switch back.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                WatchCrownDirectionPicker()
                // Each count is a soft tap, each 100 a stronger one (no choice; owner). watchOS pairs
                // its haptics with a soft tone unless the watch is silenced; apps can't play the tap alone.
                Label("For silent counting (in a masjid), turn on Silent Mode in Control Center.", systemImage: "bell.slash")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Double Tap needs Apple Watch Series 9 or Ultra 2 or later. The crown doesn't count while your wrist is down.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                // The build on this watch, like the phone's line (owner: tell a fresh install apart).
                Text(WatchBuildInfo.line)
                    .font(.system(size: 9, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .id("bottom")
            }
            .padding(.horizontal, 4)
        }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-watchSettingsBottom") { proxy.scrollTo("bottom", anchor: .bottom) } }
        #endif
        }
    }
}

/// Which way the Crown counts (owner, decision watch-crown-direction A): by default the session's
/// first turn picks it; Settings can fix it forward or back. The other way reloads.
enum WatchCrownDirection: String, CaseIterable {
    case auto, forward, backward
    static let key = "watch.crownDirection"
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
    var fixed: Int? { self == .forward ? 1 : self == .backward ? -1 : nil }
    var label: String {
        switch self {
        case .auto: "Whichever way I start"
        case .forward: "Forward"
        case .backward: "Backward"
        }
    }
}

/// Settings: the Crown's counting direction — rows like the haptics picker's.
struct WatchCrownDirectionPicker: View {
    @AppStorage(WatchCrownDirection.key) private var raw = WatchCrownDirection.auto.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Crown counts")
                .font(.system(size: 13, design: .rounded))
                .padding(.top, 4)
            ForEach(WatchCrownDirection.allCases, id: \.rawValue) { option in
                Button {
                    WKInterfaceDevice.current().play(.click)
                    raw = option.rawValue
                } label: {
                    HStack {
                        Text(option.label).font(.system(size: 15, design: .rounded))
                        Spacer()
                        if raw == option.rawValue {
                            Image(systemName: "checkmark").foregroundStyle(Color.green)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(raw == option.rawValue ? Color.green.opacity(0.15) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            Text("The other way gets the next count ready. Whichever way I start: a session's first turn picks.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// The phone's post-salah zikr (PostSalahTasbeeh): Subhanallah 33 · Alhamdulillah 33 ·
/// Allahu Akbar 34, saved once under "Tasbih Fatimah".
enum WatchPostSalah {
    static let name = "Tasbih Fatimah"
    static let phases: [(name: String, arabic: String, count: Int)] = [
        ("Subhanallah", "سُبْحَانَ ٱللَّٰهِ", 33),
        ("Alhamdulillah", "ٱلْحَمْدُ لِلَّٰهِ", 33),
        ("Allahu Akbar", "ٱللَّٰهُ أَكْبَرُ", 34),
    ]
    static var total: Int { phases.reduce(0) { $0 + $1.count } }

    static func phase(at count: Int) -> (index: Int, done: Int, of: Int) {
        var start = 0
        for (i, p) in phases.enumerated() {
            if count < start + p.count || i == phases.count - 1 { return (i, min(count - start, p.count), p.count) }
            start += p.count
        }
        return (0, 0, phases[0].count)
    }
}

/// The Tasbih Fatimah phrase in Arabic, above the count.
struct WatchPostSalahPhrase: View {
    let count: Int

    var body: some View {
        Text(WatchPostSalah.phases[WatchPostSalah.phase(at: count).index].arabic)
            .font(.system(size: WatchScreen.small ? 13 : 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: WatchNeu.scale * 150)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: WatchPostSalah.phase(at: count).index)
    }
}

/// Under the count: "7 of 33" (within the current phrase) and the three phrase bars.
struct WatchPostSalahStrip: View {
    let count: Int

    var body: some View {
        let p = WatchPostSalah.phase(at: count)
        VStack(spacing: 1) {
            Text("\(p.done) of \(p.of)")
                .font(.system(size: 10, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i < p.index ? Color.watchSage : i == p.index ? Color.watchSage.opacity(0.6) : Color.white.opacity(0.15))
                        .frame(width: 18, height: 3)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// Digital Crown counting, one count per deliberate nudge (owner, build 12: "too sensitive … easy to
/// overshoot" — every detent of a turn counted, so a flick ran on). A nudge is the first detent
/// forward after the crown has been still for `still` seconds (or gone idle); the rest of that
/// movement is dropped, not queued, so a flick or a long turn counts once. Pause, then nudge again.
/// Backwards only moves the baseline.
struct WatchCrownGate {
    static let still: TimeInterval = 0.3
    private(set) var base: Double = 0
    private var lastMove: Date = .distantPast
    private var armed = true
    /// Which way counts: +1 forward, -1 back; nil until the session's first step picks it
    /// ("Whichever way I start"), or set from Settings.
    private(set) var direction: Int?

    init(direction: Int? = nil) { self.direction = direction }

    /// A new detent value; true = count one.
    /// The phone's drag pump (owner, idea E2FW): a step the counting way counts once; a step the
    /// other way "reloads" — the next step counts at once, no pause needed. A pause (`still`) or the
    /// Crown going idle reloads too, as before. Further steps the counting way without a reload
    /// (a flick, a long turn) don't count. A step is the smallest turn the watch reports.
    mutating func turned(to value: Double, at now: Date) -> Bool {
        if now.timeIntervalSince(lastMove) >= Self.still { armed = true }
        lastMove = now
        let delta = value - base
        if direction == nil {
            guard abs(delta) >= 1 else { return false }
            direction = delta > 0 ? 1 : -1   // the first turn picks the way for the session
        }
        let along = delta * Double(direction ?? 1)
        if along <= -1 { base = value; armed = true; return false }   // the other way: reload
        guard along >= 1 else { return false }
        base = value
        guard armed else { return false }
        armed = false
        return true
    }

    /// The crown stopped (the system's own idle): the next nudge counts.
    mutating func idle() { armed = true }

    /// Paused / wrist down: follow the crown without counting.
    mutating func reset(to value: Double) { base = value }

    #if DEBUG
    /// `-demoWatchCrownTest`: detent sequences (seconds between detents) through the gate, before
    /// (every detent counted) vs now. Printed as CROWNTEST lines.
    static func selfTest() {
        let profiles: [(String, [TimeInterval], Int)] = [
            ("five slow nudges (0.7 s apart)", [0, 0.7, 0.7, 0.7, 0.7], 5),
            ("six quick nudges (0.35 s apart)", [0, 0.35, 0.35, 0.35, 0.35, 0.35], 6),
            ("one nudge, 2 detents", [0, 0.06], 1),
            ("normal flick, 8 detents in 0.5 s", [0, 0.04, 0.04, 0.05, 0.06, 0.08, 0.1, 0.13], 1),
            ("hard flick, 20 detents in 1.1 s", [0] + Array(repeating: 0.03, count: 12) + [0.05, 0.06, 0.08, 0.1, 0.13, 0.17, 0.22], 1),
            ("long steady turn, 12 detents in 2 s", [0] + Array(repeating: 0.18, count: 11), 1),
            ("flick, pause, flick", [0, 0.04, 0.05, 0.08, 0.6, 0.04, 0.05, 0.08], 2),
        ]
        var passed = 0
        for (name, gaps, want) in profiles {
            var gate = WatchCrownGate()
            var t = Date(), value = 0.0, got = 0
            for gap in gaps {
                t = t.addingTimeInterval(gap); value += 1
                if gate.turned(to: value, at: t) { got += 1 }
            }
            if got == want { passed += 1 }
            print("CROWNTEST \(got == want ? "✅" : "❌") \(name): before \(gaps.count), now \(got) (want \(want))")
        }
        // Rocking quickly (0.1 s apart, never still): forward counts, back reloads — 4 counts.
        var rock = WatchCrownGate(); var t1 = Date(); var rocked = 0
        for v in [1.0, 0, 1, 0, 1, 0, 1] { t1 += 0.1; if rock.turned(to: v, at: t1) { rocked += 1 } }
        let rockOK = rocked == 4
        print("CROWNTEST \(rockOK ? "✅" : "❌") forward-back rocking, 0.1 s apart: \(rocked) (want 4)")
        // Started backwards: back counts, forward reloads.
        var down = WatchCrownGate(); var t2 = Date(); var downs = 0
        for v in [-1.0, -2, -1, -2, -3] { t2 += 0.1; if down.turned(to: v, at: t2) { downs += 1 } }
        let downOK = downs == 2 && down.direction == -1
        print("CROWNTEST \(downOK ? "✅" : "❌") started backwards: \(downs) (want 2)")
        // Set to Forward: turning back first never counts.
        var fwd = WatchCrownGate(direction: 1); let t3 = Date()
        let fwdOK = [fwd.turned(to: -1, at: t3), fwd.turned(to: 0, at: t3 + 0.1)] == [false, true]
        print("CROWNTEST \(fwdOK ? "✅" : "❌") Forward setting: back first doesn't count, then forward does")
        passed += [rockOK, downOK, fwdOK].filter { $0 }.count
        print("CROWNTEST \(passed)/\(profiles.count + 3) passed")
    }
    #endif
}

/// Freestyle's zikr: "Just count" or one of your azkar (from the phone). The pick is remembered.
struct WatchZikrPicker: View {
    @Binding var isPresented: Bool
    @ObservedObject private var store = WatchZikrStore.shared

    var body: some View {
        List {
            row("Just count", selected: store.freestylePick == nil) { store.freestylePick = nil }
            ForEach(store.azkar, id: \.self) { name in
                row(name, selected: store.freestylePick == name) { store.freestylePick = name }
            }
        }
        .navigationTitle("Freestyle")
    }

    private func row(_ title: String, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            WatchHaptics.tick()
            pick()
            isPresented = false
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(title == "Just count" ? Color.secondary : Color.primary)
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.watchSage) }
            }
        }
    }
}

/// 40 / 41 mm faces (under ~180 pt wide): a touch smaller, so everything clears the ring.
enum WatchScreen {
    static let width = WKInterfaceDevice.current().screenBounds.width
    static let height = WKInterfaceDevice.current().screenBounds.height
    static var small: Bool { width < 180 }
    /// Room for the finish tile on the pause screen's first page (45 mm and up: 240 pt tall and
    /// more); smaller watches show it on the second page.
    static var roomy: Bool { height >= 240 }
}

// MARK: - Pause pages

/// The pause screen's first page: the phone's ZikrBento, small — count over time on the left, the
/// rate on the right (tap: per count ⇄ per tasbeeh, with how it compares with your usual pace), the
/// finish tile for a count goal (tap: "1m 32s left" ⇄ "Finishing at 1:52"), then Resume and a
/// two-tap Finish early. Sized to one screen: nothing scrolls.
struct WatchPauseStats: View {
    let name: String
    /// The task whose zikr has a voice memo: its play ring sits beside the name.
    let memoTask: WatchTask?
    let count: Int
    /// Active seconds up to the last count (the phone's rate uses the same).
    let seconds: Double
    let usualPace: Double?
    let finish: (left: TimeInterval, at: Date)?
    let finishArmed: Bool
    let finishEarly: () -> Void
    @State private var perCount = true
    @State private var showFinishTime = false

    private var gap: CGFloat { WatchScreen.small ? 4 : 5 }
    private var tileH: CGFloat { WatchScreen.small ? 31 : 36 }
    private var pace: Double { count > 0 ? seconds / Double(count) : 0 }

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: WatchScreen.small ? 14 : 15, weight: .light, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let memoTask { WatchMemoButton(task: memoTask, compact: true) }
            }
            .frame(height: 22)
            HStack(spacing: gap) {
                VStack(spacing: gap) {
                    tile { row("circle.hexagonpath", "\(count)", "count") }
                    tile { row("gauge.with.needle", clock(seconds), "time") }
                }
                rateTile
            }
            .frame(height: tileH * 2 + gap)
            if let finish { finishTile(finish) }
            Spacer(minLength: 0)
            // Finish early in the big capsule (owner, idea GUSV: easier to tap; Resume is the ‹ top
            // left). Two taps, like the phone: the first arms it (green), it disarms after 3 s. Our own
            // capsule: the system's bordered button is ~50 pt tall on a watch.
            Button(action: finishEarly) {
                Text(finishArmed ? "Tap again to finish" : "Finish early")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(finishArmed ? Color.green : .primary)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchScreen.small ? 30 : 34)
                    .background(Capsule().fill(finishArmed ? Color.green.opacity(0.22) : Color.white.opacity(0.12)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)   // the page dots
    }

    private var rateTile: some View {
        tile {
            VStack(spacing: 1) {
                Text("rate").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
                ZStack {
                    valueStack(count > 0 ? String(format: "%.2fs", pace) : "–", "per count")
                        .opacity(perCount ? 1 : 0).offset(y: perCount ? 0 : -8)
                    valueStack(count > 0 ? minutesText(pace * 100) : "–", "per tasbeeh")
                        .opacity(perCount ? 0 : 1).offset(y: perCount ? 8 : 0)
                }
                if let a = comparison(perCount: true), let b = comparison(perCount: false) {
                    ZStack {
                        comparisonText(a).opacity(perCount ? 1 : 0)
                        comparisonText(b).opacity(perCount ? 0 : 1)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { flipMark.padding(6) }
        }
        .onTapGesture {
            WatchHaptics.tick()
            withAnimation(.easeInOut(duration: 0.3)) { perCount.toggle() }
        }
    }

    private func finishTile(_ finish: (left: TimeInterval, at: Date)) -> some View {
        tile {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    Text("\(minutesText(finish.left)) left")
                        .opacity(showFinishTime ? 0 : 1).offset(y: showFinishTime ? -8 : 0)
                    (Text("Finishing at ") + Text(finish.at, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                        .opacity(showFinishTime ? 1 : 0).offset(y: showFinishTime ? 0 : 8)
                }
                .font(.system(size: 13, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                flipMark
            }
            .padding(.horizontal, 8)
        }
        .frame(height: WatchScreen.small ? 26 : 28)
        .onTapGesture {
            WatchHaptics.tick()
            withAnimation(.easeInOut(duration: 0.3)) { showFinishTime.toggle() }
        }
    }

    /// The phone's rule: "0.7s faster" / "1m 10s slower" (per tasbeeh) / "about your usual" within
    /// 5 %. Nil without a usual pace.
    private func comparison(perCount: Bool) -> (text: String, faster: Bool?)? {
        guard let usual = usualPace, usual > 0, pace > 0 else { return nil }
        let diff = pace - usual
        if abs(diff) / usual < 0.05 { return ("about your usual", nil) }
        let amount = abs(diff) * (perCount ? 1 : 100)
        let text: String
        if perCount {
            text = amount < 0.1 ? String(format: "%.2fs", amount) : String(format: "%.1fs", amount)
        } else {
            let whole = Int(amount.rounded())
            text = whole >= 60 ? "\(whole / 60)m \(whole % 60)s" : "\(whole)s"
        }
        return ("\(text) \(diff < 0 ? "faster" : "slower")", diff < 0)
    }

    private func comparisonText(_ line: (text: String, faster: Bool?)) -> some View {
        Text(line.text)
            .font(.system(size: 9, weight: line.faster == true ? .medium : .regular, design: .rounded))
            .foregroundStyle(line.faster == true ? Color.watchSage : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
    }

    private var flipMark: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    /// "01:32" like the phone's stopwatch; "1:02:05" past an hour.
    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%02d:%02d", t / 60, t % 60)
    }

    private func row(_ icon: String, _ value: String, _ caption: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: WatchScreen.small ? 14 : 16, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption).font(.system(size: 8, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private func valueStack(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: WatchScreen.small ? 17 : 19, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 8, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The pause screen's second page: toggle chips (owner, 2026-09-29) — the haptics, cycling like the
/// phone's chip (silent → soft → medium → strong, a sample on each change), and how you count
/// (Tap & pinch ⇄ Crown only, the same switch as before). On a small watch the finish tile sits
/// on top of them.
struct WatchPauseSettings: View {
    let finish: (left: TimeInterval, at: Date)?
    let crownOnly: Bool
    let setCrownOnly: (Bool) -> Void
    @State private var showFinishTime = false

    var body: some View {
        VStack(spacing: WatchScreen.small ? 6 : 8) {
            if let finish {
                Button {
                    WatchHaptics.tick()
                    withAnimation(.easeInOut(duration: 0.3)) { showFinishTime.toggle() }
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "flag.checkered").font(.system(size: 11, weight: .light)).foregroundStyle(.secondary)
                        ZStack {
                            Text("\(minutesText(finish.left)) left").opacity(showFinishTime ? 0 : 1)
                            (Text("Finishing at ") + Text(finish.at, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())).opacity(showFinishTime ? 1 : 0)
                        }
                        .font(.system(size: 14, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            section("count with") {
                chip(crownOnly ? "Crown only" : "Tap & pinch",
                     crownOnly ? "digitalcrown.arrow.clockwise" : "hand.tap",
                     lit: crownOnly) { setCrownOnly(!crownOnly) }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)   // the page dots
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func chip(_ text: String, _ symbol: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: symbol)
                .font(.system(size: 14, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(lit ? Color.green : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(lit ? Color.green.opacity(0.15) : Color.white.opacity(0.08)))
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
    }
}

