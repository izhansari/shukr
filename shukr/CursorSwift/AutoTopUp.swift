import SwiftUI
import UserNotifications
import ActivityKit

/// One top-up for everything — notifications, then the Fajr alarms (NotificationScheduler runs them after), then the
/// prayer cards — from every moment iOS gives shukr without it being opened (owner, decision topup-every-wake A,
/// 2026-10-14: "we care more about the top-ups when we're not opening the app … already on autopilot"): a card starting,
/// a card's or the widget's ✓, the alarm's Stop, a location update with Always, Background App Refresh, a notification's
/// button, a Shortcut. At most every 3 h unless the moment is iOS's own refresh / a notification button (they always
/// ran); under a background-task assertion so it finishes. Every ask is logged (topups.log in the app group), with how
/// long since shukr was last opened, so we can see what keeps it topped up on autopilot.
@MainActor
enum AutoTopUp {
    static let key = "autoTopUpAt"
    static let every: TimeInterval = 3 * 3600
    private static var running = false

    /// Fire and forget (a card, a widget, the alarm, a location update).
    static func request(_ trigger: String, force: Bool = false) {
        Task { @MainActor in await run(trigger, force: force) }
    }

    /// `force`: run even inside the 3 h (Background App Refresh, a notification's button — as before). Awaited by
    /// Background App Refresh, whose time ends when its closure returns.
    static func run(_ trigger: String, force: Bool = false) async {
        let g = UserDefaults(suiteName: SharedStore.appGroup)
        let now = Date().timeIntervalSince1970
        let last = g?.double(forKey: key) ?? 0
        let state = stateWord
        var force = force
        #if DEBUG
        // The wake test (`-laStartIn`): no 3 h limit for 10 min, across iOS's own relaunches (they come without args).
        if now < UserDefaults.standard.double(forKey: "autoTopUp.noLimitUntil") { force = true }
        #endif
        guard force || now - last > every else {
            TopUpLog.add("\(trigger) · \(state) · skipped, topped up \(ago(now - last)) ago")
            return
        }
        guard !running else { TopUpLog.add("\(trigger) · \(state) · skipped, one running"); return }
        guard let container = NotificationScheduler.appContainer else {
            TopUpLog.add("\(trigger) · \(state) · skipped, no store yet"); return
        }
        running = true
        g?.set(now, forKey: key)
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "auto top-up") {
            TopUpLog.add("\(trigger) · iOS ended the background time before it finished")
            UIApplication.shared.endBackgroundTask(bg); bg = .invalid
        }
        do {
            let t0 = Date()
            await NotificationScheduler.rescheduleNow(context: container.mainContext, reason: "auto: \(trigger)")   // + Fajr alarms
            let cards = PrayerLiveActivities.plan(reason: "auto: \(trigger)")
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let through = pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }.max()
            let alarms = FajrAlarms.scheduled().filter { !$0.test && ($0.date ?? .distantPast) > Date() }
            var held = 0
            if #available(iOS 26.0, *) {
                held = Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active }.count
            }
            TopUpLog.add("\(trigger) · \(state) · ran in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s"
                         + " → notifications \(pending.count)" + (through.map { " through \(day($0))" } ?? "")
                         + " · alarms \(alarms.count)" + (alarms.compactMap(\.date).max().map { " through \(day($0))" } ?? "")
                         + " · cards \(held)" + (cards > 0 ? " (+\(cards))" : ""))
            running = false
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
        }
    }

    /// "bg, opened 9 h ago" — where the app was and how long since it was last opened (the autopilot question).
    private static var stateWord: String {
        let s = UIApplication.shared.applicationState
        let where_ = s == .background ? "bg" : s == .active ? "open" : "inactive"
        let opens = UserDefaults.standard.array(forKey: NotificationScheduler.opensKey) as? [Double] ?? []
        guard let lastOpen = opens.last else { return where_ }
        return "\(where_), opened \(ago(Date().timeIntervalSince1970 - lastOpen)) ago"
    }

    private static func ago(_ s: TimeInterval) -> String {
        s < 3600 ? "\(Int(s / 60)) min" : s < 86_400 * 2 ? String(format: "%.1f h", s / 3600) : "\(Int(s / 86_400)) days"
    }
    private static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
}

/// The top-ups, newest last: app group Library/Application Support/topups.log (pulled from the phone with devicectl).
enum TopUpLog {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Library/Application Support/topups.log", isDirectory: false)
    }
    private static let queue = DispatchQueue(label: "shukr.topUpLog")
    static func add(_ line: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm:ss"
        let text = "\(f.string(from: Date()))  \(line)\n"
        #if DEBUG
        print("🔋 \(line)")
        #endif
        queue.async {
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? Data(text.utf8).write(to: url) }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 500_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? (all.split(separator: "\n").suffix(3000).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
