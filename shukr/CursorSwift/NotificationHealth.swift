//
//  NotificationHealth.swift
//  shukr
//
//  Will the reminders actually reach you? (owner, 2026-09-28, notes: notifications health, build 12.)
//  `NotificationHealth` reads iOS's notification settings and Background App Refresh on launch and on
//  every activation (one `notificationSettings()` call, publishing only what changed; nothing written
//  to the app group) and turns them into issues:
//  - off: notifications denied → a calm card (`ReminderHealthCard`) on the Salah page, at most every
//    few days, never over a tasbeeh session, a cover or the setup;
//  - held: Scheduled Summary on and Time Sensitive off (prayer notifications are `.timeSensitive`,
//    so with it on the summary lets them through) → the same kind of card;
//  - Time Sensitive off alone, Background App Refresh off → no card, a quiet line in Settings.
//  Settings → Notifications shows the overall status at the top (`NotificationHealthRows`), the
//  setup's review uses the same checks, and beta builds get Settings → Scheduled notifications
//  (`ScheduledNotificationsView`: what's pending out of iOS's 64, by kind, the days covered, when
//  background refresh last ran).
//

import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class NotificationHealth: ObservableObject {
    static let shared = NotificationHealth()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var summaryOn = false
    @Published private(set) var timeSensitive: UNNotificationSetting = .notSupported
    @Published private(set) var backgroundRefresh: UIBackgroundRefreshStatus = .available
    @Published private(set) var checked = false

    enum Issue: String {
        case off, held, timeSensitiveOff, backgroundRefreshOff
    }

    /// Everything that isn't right, the most serious first.
    var issues: [Issue] {
        guard checked else { return [] }
        var list: [Issue] = []
        if authorization == .denied { list.append(.off); return list + refreshIssue }
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else { return refreshIssue }
        if summaryOn && timeSensitive != .enabled { list.append(.held) }
        else if timeSensitive == .disabled { list.append(.timeSensitiveOff) }
        return list + refreshIssue
    }
    private var refreshIssue: [Issue] { backgroundRefresh == .available ? [] : [.backgroundRefreshOff] }

    /// The one that earns a card (off, or held for the summary); the others are only quiet lines.
    var cardIssue: Issue? { issues.first { $0 == .off || $0 == .held } }

    func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        let refresh = UIApplication.shared.backgroundRefreshStatus
        if authorization != s.authorizationStatus { authorization = s.authorizationStatus }
        let summary = s.scheduledDeliverySetting == .enabled
        if summaryOn != summary { summaryOn = summary }
        if timeSensitive != s.timeSensitiveSetting { timeSensitive = s.timeSensitiveSetting }
        if backgroundRefresh != refresh { backgroundRefresh = refresh }
        if !checked { checked = true }
        #if DEBUG
        // `-healthPretend off|held|ts|bg`: report that state (the simulator can't switch these).
        switch UserDefaults.standard.string(forKey: "healthPretend") {
        case "off": authorization = .denied
        case "held": authorization = .authorized; summaryOn = true; timeSensitive = .disabled
        case "ts": authorization = .authorized; summaryOn = false; timeSensitive = .disabled
        case "bg": backgroundRefresh = .denied
        default: break
        }
        #endif
    }

    // MARK: the card's cadence

    private static func shownKey(_ issue: Issue) -> String { "reminderHealthCard.\(issue.rawValue).lastShown" }
    /// At most every few days per kind.
    static let cardInterval: TimeInterval = 3 * 24 * 3600

    func cardDue(for issue: Issue) -> Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "healthPretend") != nil { return true }   // screenshots
        #endif
        let last = UserDefaults.standard.double(forKey: Self.shownKey(issue))
        return last == 0 || Date().timeIntervalSince1970 - last > Self.cardInterval
    }
    func markCardShown(_ issue: Issue) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.shownKey(issue))
    }

    // MARK: background refresh, for the dev screen

    static let lastRefreshKey = "bgRefresh.lastRun"
    nonisolated static func noteBackgroundRefreshRan() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
    }
}

extension NotificationHealth.Issue: Identifiable { var id: String { rawValue } }

// MARK: - The card (Salah page, as a sheet)

/// Lighter than LostLocationView: a half sheet in the setup's look. "Turn on" / "Open Settings"
/// goes to shukr's page in iOS Settings; "Not now" closes it (it comes back after a few days).
struct ReminderHealthCard: View {
    let issue: NotificationHealth.Issue
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Color.sage.opacity(0.18), lineWidth: 1.2)
                Image(systemName: issue == .off ? "bell.slash" : "tray.full")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.sage)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 26)
            Text(issue == .off ? "Your prayer reminders are off" : "Your reminders are held for the Scheduled Summary")
                .font(.system(.title2, design: .rounded, weight: .light))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 16)
            Text(issue == .off
                 ? "Notifications are off for shukr, so these can't reach you:"
                 : "iOS saves them for the summary, so they can arrive late. Turn on Time Sensitive for shukr, or set it to Immediate Delivery.")
                .font(.system(.callout, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            if issue == .off {
                VStack(alignment: .leading, spacing: 8) {
                    line("bell", "each prayer as it begins")
                    line("bell.badge", "a nudge halfway and with 30 min left")
                    line("sunrise", "Fajr, before it's too late")
                    line("circle.hexagonpath", "your zikr reminders")
                }
                .padding(.horizontal, 44)
                .padding(.top, 14)
            }
            Spacer(minLength: 16)
            PrimaryButton(title: issue == .off ? "Turn on" : "Open Settings") {
                SettingsLinks.notifications()
                close()
            }
            SecondaryButton(title: "Not now", action: close)
                .padding(.bottom, 12)
        }
        .fontDesign(.rounded)
        .presentationDetents([.height(issue == .off ? 470 : 400)])
        .presentationDragIndicator(.visible)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .light)).foregroundStyle(Color.sage).frame(width: 20)
            Text(text).font(.system(.subheadline, design: .rounded, weight: .light))
        }
    }
}

// MARK: - Settings → Notifications: the status at the top

struct NotificationHealthRows: View {
    @ObservedObject private var health = NotificationHealth.shared

    var body: some View {
        let issues = health.issues
        Group {
            if !health.checked {
                EmptyView()
            } else if issues.isEmpty && health.authorization != .notDetermined {
                Label("Reminders are on and arrive on time", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.sage)
                    .font(.subheadline)
            } else {
                if health.authorization == .notDetermined {
                    row("bell", "Reminders need notifications", "Allow") { NotificationStatus.shared.request() }
                }
                ForEach(issues, id: \.self) { issue in
                    switch issue {
                    case .off:
                        row("bell.slash", "Notifications are off, so reminders can't reach you", "Turn on", SettingsLinks.notifications)
                    case .held:
                        row("tray.full", "Held for the Scheduled Summary: they may arrive late. Turn on Time Sensitive or Immediate Delivery", "Fix", SettingsLinks.notifications)
                    case .timeSensitiveOff:
                        row("moon", "Time Sensitive is off: Focus modes may hold reminders back", "Settings", SettingsLinks.notifications)
                    case .backgroundRefreshOff:
                        row("arrow.clockwise", "Background refresh is off: open shukr every few days so reminders stay topped up", "Settings", SettingsLinks.app)
                    }
                }
            }
        }
        .task { await health.refresh() }
    }

    private func row(_ symbol: String, _ text: String, _ action: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.orange)
                Text(text).font(.subheadline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(action).font(.subheadline.weight(.semibold)).foregroundStyle(Color.sage)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dev: Scheduled notifications (beta builds, Settings)

/// Read-only: what's pending (out of iOS's 64) by kind, the prayer days covered, when background
/// refresh last ran, and every check above.
struct ScheduledNotificationsView: View {
    @ObservedObject private var health = NotificationHealth.shared
    @State private var pending: [UNNotificationRequest] = []
    @State private var delivered = 0
    @State private var loaded = false

    private struct Counts { var start = 0, mid = 0, end = 0, zikr = 0, zikrLater = 0, snooze = 0, other = 0 }

    private var counts: Counts {
        var c = Counts()
        for r in pending {
            let id = r.identifier
            if let p = PrayerNotificationID.parse(id) {
                switch p.kind { case "Start": c.start += 1; case "Mid": c.mid += 1; default: c.end += 1 }
            } else if id.hasPrefix("zikrlater.") { c.zikrLater += 1 }
            else if id.hasPrefix("zikr.") { c.zikr += 1 }
            else if id.hasPrefix("snooze") { c.snooze += 1 }
            else { c.other += 1 }
        }
        return c
    }

    /// First and last prayer day with a start notification.
    private var daysCovered: String {
        let days = pending.compactMap { r -> String? in
            guard let p = PrayerNotificationID.parse(r.identifier), p.kind == "Start" else { return nil }
            return p.dayKey
        }.sorted()
        guard let first = days.first, let last = days.last else { return "none" }
        return first == last ? first : "\(first) → \(last)"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Pending", value: "\(pending.count) of 64")
                LabeledContent("Delivered, in Notification Center", value: "\(delivered)")
                LabeledContent("Prayer days with a start", value: daysCovered)
            }
            Section("By kind") {
                let c = counts
                LabeledContent("Prayer starts", value: "\(c.start)")
                LabeledContent("Halfway nudges", value: "\(c.mid)")
                LabeledContent("30 min left nudges", value: "\(c.end)")
                LabeledContent("Zikr reminders", value: "\(c.zikr)")
                LabeledContent("Zikr \"later\"", value: "\(c.zikrLater)")
                LabeledContent("Snoozes", value: "\(c.snooze)")
                LabeledContent("Other", value: "\(c.other)")
            }
            Section("Background refresh") {
                LabeledContent("Status", value: refreshStatus)
                LabeledContent("Last ran", value: lastRefresh)
            }
            Section("Checks") {
                LabeledContent("Notifications", value: authText)
                LabeledContent("Scheduled Summary", value: health.summaryOn ? "on" : "off")
                LabeledContent("Time Sensitive", value: settingText(health.timeSensitive))
                LabeledContent("Card due", value: health.cardIssue.map { "\($0.rawValue) (\(health.cardDue(for: $0) ? "yes" : "shown recently"))" } ?? "none")
            }
            Section("Next ten") {
                ForEach(pending.prefix(10), id: \.identifier) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.identifier).font(.caption.monospaced())
                        Text(fireDate(r)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Scheduled notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        await health.refresh()
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        pending = requests.sorted { (nextDate($0) ?? .distantFuture) < (nextDate($1) ?? .distantFuture) }
        delivered = await center.deliveredNotifications().count
        loaded = true
    }

    private func nextDate(_ r: UNNotificationRequest) -> Date? {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
    }
    private func fireDate(_ r: UNNotificationRequest) -> String {
        nextDate(r).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "no trigger"
    }
    private var refreshStatus: String {
        switch health.backgroundRefresh {
        case .available: "on"
        case .denied: "off"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
    }
    private var lastRefresh: String {
        let t = UserDefaults.standard.double(forKey: NotificationHealth.lastRefreshKey)
        return t == 0 ? "never (since this was added)" : Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .shortened)
    }
    private var authText: String {
        switch health.authorization {
        case .authorized: "on"
        case .denied: "off"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        case .notDetermined: "not asked"
        @unknown default: "unknown"
        }
    }
    private func settingText(_ s: UNNotificationSetting) -> String {
        switch s {
        case .enabled: "on"
        case .disabled: "off"
        case .notSupported: "not supported"
        @unknown default: "unknown"
        }
    }
}
