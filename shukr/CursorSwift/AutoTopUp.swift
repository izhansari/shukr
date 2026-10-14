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

// MARK: - The in-app "topped up" banner (owner, 2026-10-14: "something that appears in the app … that acknowledges that it
// was refreshed properly … with all reminders being refreshed as well") — after the last card's ↻, or opening shukr once the
// cards had run out. Relative terms (owner), a tap opens what's set, each row opens its page.

enum TopUpBanner {
    static let shown = Notification.Name("TopUpBannerShown")

    /// What's set after a top-up.
    struct Summary {
        var cards = 0
        /// The last card's prayer, in words ("tonight's Maghrib").
        var cardsThrough: String?
        var notifications = 0
        var notificationDays: Int?
        var alarmDays: Int?
        /// "5 prayer cards · notifications for 6 days · Fajr alarms for 60 days".
        var line: String {
            var parts = ["\(cards) prayer card\(cards == 1 ? "" : "s")"]
            if let d = notificationDays { parts.append("notifications for \(TopUpBanner.days(d))") }
            if let d = alarmDays { parts.append("Fajr alarms for \(TopUpBanner.days(d))") }
            return parts.joined(separator: " · ")
        }
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
    /// Days from today to that day, counting both ends ("today" = 1).
    static func daysAhead(_ d: Date) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0) + 1
    }

    @MainActor private static var lastShown = Date.distantPast
    @MainActor static func show() async {
        guard Date().timeIntervalSince(lastShown) > 10 else { return }   // once (the ↻ and the open's refill both ask)
        lastShown = Date()
        var s = Summary()
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        s.notifications = pending.count
        s.notificationDays = pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }.max().map(daysAhead)
        s.alarmDays = FajrAlarms.scheduled().filter { !$0.test && ($0.date ?? .distantPast) > Date() }
            .compactMap(\.date).max().map(daysAhead)
        if #available(iOS 26.0, *) {
            let held = Activity<PrayerWindowAttributes>.activities.filter { $0.activityState == .pending || $0.activityState == .active }
            s.cards = held.count
            if let last = held.max(by: { $0.content.state.start < $1.content.state.start })?.content.state {
                let cal = Calendar.current
                s.cardsThrough = cal.isDateInToday(last.start) ? ((last.label == "Maghrib" || last.label == "Isha" ? "tonight's " : "today's ") + last.label)
                    : cal.isDateInTomorrow(last.start) ? "tomorrow's \(last.label)"
                    : last.start.formatted(.dateTime.weekday(.wide)) + "'s \(last.label)"
            }
        }
        TopUpLog.add("banner: \(s.line)")
        NotificationCenter.default.post(name: shown, object: s)
    }
}

/// The banner: a glass card at the top for a few seconds; a tap opens the sheet (what's set, each row → its page).
struct TopUpBannerHost: ViewModifier {
    @State private var summary: TopUpBanner.Summary?
    @State private var sheet: TopUpBanner.Summary?
    @State private var hide: Task<Void, Never>?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let summary {
                Button {
                    sheet = summary
                    withAnimation(.easeOut(duration: 0.25)) { self.summary = nil }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All reminders topped up").font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(summary.line).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 360, alignment: .leading)
                    .mapGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(get: { sheet.map(SummaryBox.init) }, set: { sheet = $0?.summary })) { box in
            TopUpSheet(summary: box.summary)
        }
        #if DEBUG
        .task {   // `-demoTopUpSheet`: the sheet with sample numbers (screenshots)
            guard ProcessInfo.processInfo.arguments.contains("-demoTopUpSheet") else { return }
            try? await Task.sleep(for: .seconds(2))
            sheet = TopUpBanner.Summary(cards: 5, cardsThrough: "tonight's Maghrib", notifications: 60, notificationDays: 7, alarmDays: 60)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: TopUpBanner.shown)) { note in
            guard let s = note.object as? TopUpBanner.Summary else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { summary = s }
            hide?.cancel()
            hide = Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { summary = nil }
            }
        }
    }
    private struct SummaryBox: Identifiable { let summary: TopUpBanner.Summary; var id: Int { 0 } }
}

/// What the top-up set, in ReminderHealthCard's look (owner: "the no location or no notifications sheet … we can copy
/// that"): the thin sage ring with a light symbol, a light title and line, one sage-symbol line per kind — each opens its
/// page (owner: "takes them to that scheduler page") — and Done. The sheet fits that, and goes full height while a page is
/// open. Your Fajr Alarms opens on beta builds only, as in Settings.
struct TopUpSheet: View {
    let summary: TopUpBanner.Summary
    @ObservedObject private var betaAccess = WhatsNewAccess.shared
    @Environment(\.dismiss) private var dismiss
    private enum Page: Hashable { case cards, notifications, alarms }
    @State private var path: [Page] = []
    @State private var detent: PresentationDetent = .height(TopUpSheet.height)
    static let height: CGFloat = 430

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.sage.opacity(0.18), lineWidth: 1.2)
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .light)).foregroundStyle(Color.sage)
                }
                .frame(width: 64, height: 64)
                .padding(.top, 26)
                Text("All reminders topped up")
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28).padding(.top, 16)
                Text("shukr set these up ahead, so they keep coming:")
                    .font(.system(.callout, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32).padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    line(.cards, "platter.filled.bottom.iphone",
                         "\(summary.cards) prayer card\(summary.cards == 1 ? "" : "s")" + (summary.cardsThrough.map { ", through \($0)" } ?? ""))
                    if let d = summary.notificationDays {
                        line(.notifications, "bell", "notifications for the next \(TopUpBanner.days(d))")
                    }
                    if let d = summary.alarmDays {
                        line(betaAccess.beta ? .alarms : nil, "alarm", "Fajr alarms for the next \(TopUpBanner.days(d))")
                    }
                }
                .padding(.horizontal, 36).padding(.top, 14)
                Spacer(minLength: 16)
                PrimaryButton(title: "Done") { dismiss() }
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.clear, for: .navigation)   // the sheet's own glass shows through (owner)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .cards: ScheduledLiveActivitiesPage()
                case .notifications: YourRemindersView()
                case .alarms: FajrAlarmCheckView()
                }
            }
        }
        .fontDesign(.rounded)
        .infoModalHost()   // the pages' ⓘ cards over the sheet
        .modifier(TopUpSheetGlass())
        .presentationDetents([.height(Self.height), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // A page needs the room: full height while one is open, back when it closes.
        .onChange(of: path) { _, p in withAnimation { detent = p.isEmpty ? .height(Self.height) : .large } }
    }

    /// ReminderHealthCard's line — a light sage symbol and light words — with a small chevron when it opens a page.
    private func line(_ page: Page?, _ symbol: String, _ text: String) -> some View {
        Button { if let page { path.append(page) } } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .light)).foregroundStyle(Color.sage).frame(width: 20)
                Text(text).font(.system(.subheadline, design: .rounded, weight: .light)).foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if page != nil {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(page == nil)
    }
}

/// iOS 26 gives a partial-height sheet Liquid Glass by itself (with nothing painted over it); before 26, the material.
private struct TopUpSheetGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content } else { content.presentationBackground(.regularMaterial) }
    }
}

extension View {
    func topUpBannerHost() -> some View { modifier(TopUpBannerHost()) }
}
