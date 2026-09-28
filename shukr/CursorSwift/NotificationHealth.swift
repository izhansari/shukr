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
//  setup's review uses the same checks, and Settings → Notifications → Upcoming reminders
//  (`UpcomingRemindersView`, beta-only until `UpcomingReminders.isPublic`) lists everything waiting.
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
    /// When the card for `issue` may next come (nil = any time), by the 3-day rule only.
    func nextCardDate(for issue: Issue) -> Date? {
        let last = UserDefaults.standard.double(forKey: Self.shownKey(issue))
        guard last != 0 else { return nil }
        let next = Date(timeIntervalSince1970: last + Self.cardInterval)
        return next > Date() ? next : nil
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

// MARK: - Upcoming reminders (Settings → Notifications)

/// Whether "Upcoming reminders" is in everyone's Settings. **The one line to flip to make it public**
/// (feedback E37CE0F0): `true` shows it in the App Store build too; the beta-only card previews in its
/// Details section stay behind `WhatsNewAccess` either way.
enum UpcomingReminders {
    static let isPublic = false
}

/// Every notification shukr has waiting with iOS (out of its 64), grouped by prayer day, with what
/// each one is; today's delivered ones greyed at the end; the technical bits in a collapsed Details.
struct UpcomingRemindersView: View {
    @ObservedObject private var health = NotificationHealth.shared
    @ObservedObject private var betaAccess = WhatsNewAccess.shared
    @State private var pending: [Item] = []
    @State private var deliveredToday: [Item] = []
    @State private var loaded = false
    @State private var showDetails = ProcessInfo.processInfo.arguments.contains("-upcomingDetails")   // DEBUG screenshots
    @State private var previewCard: NotificationHealth.Issue?

    /// One notification, read once from its request.
    struct Item: Identifiable {
        let id: String
        let date: Date?
        let dayKey: String          // its prayer day ("2026-09-28")
        let kind: Kind
        let prayer: String?
        let title: String
    }
    enum Kind {
        case start, halfway, endingSoon, zikr, zikrLater, snooze, other
        var label: String {
            switch self {
            case .start: "starts"
            case .halfway: "halfway"
            case .endingSoon: "30 min left"
            case .zikr: "zikr reminder"
            case .zikrLater: "zikr, later"
            case .snooze: "nudge"
            case .other: "reminder"
            }
        }
    }

    var body: some View {
        List {
            Section {
                summary
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            }
            if loaded && pending.isEmpty {
                Section {
                    Text(health.authorization == .denied
                         ? "Notifications are off for shukr, so nothing is scheduled."
                         : "Nothing is scheduled right now. Open shukr and it tops them up.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(days, id: \.key) { day in
                Section {
                    ForEach(Self.groups(day.items)) { groupRow($0, faded: false) }
                } header: {
                    // The day's total (zikr and snoozes included) — owner: the counts carry it.
                    Text("\(dayTitle(day.key)) · \(day.items.count)")
                }
            }
            if !deliveredToday.isEmpty {
                Section {
                    ForEach(Self.groups(deliveredToday)) { groupRow($0, faded: true) }
                } header: {
                    Text("Already delivered today")
                }
            }
            details
        }
        .navigationTitle("Upcoming reminders")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $previewCard) { issue in
            ReminderHealthCard(issue: issue) { previewCard = nil }
        }
    }

    // MARK: pieces

    /// The ring (how many of iOS's 64 are waiting), how far they reach, what they're made of, and
    /// the one thing to know: open shukr every few days (owner: educate, be transparent, keep it simple).
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color(.secondarySystemFill), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(Double(pending.count) / 64, 1))
                        .stroke(Color.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(pending.count)").font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                        Text("of 64").font(.system(size: 10, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(coverText)
                        .font(.system(.headline, design: .rounded, weight: .regular))
                    Text("waiting with iOS right now")
                        .font(.system(.caption, design: .rounded, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            // What they are.
            HStack(spacing: 0) {
                ForEach(breakdown, id: \.label) { part in
                    VStack(spacing: 1) {
                        Text("\(part.count)")
                            .font(.system(.title3, design: .rounded, weight: .light))
                            .monospacedDigit()
                        Text(part.label)
                            .font(.system(.caption2, design: .rounded, weight: .light))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            Text("iOS lets an app keep 64 reminders waiting at once. shukr fills them about a week ahead. Open shukr every few days and they stay topped up.")
                .font(.system(.footnote, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    /// Starts · Halfway · 30 min left · Zikr, and the snoozes / later ones only when there are some.
    private var breakdown: [(label: String, count: Int)] {
        let all = pending.map(\.kind)
        func n(_ kinds: Kind...) -> Int { all.filter { kinds.contains($0) }.count }
        var parts: [(label: String, count: Int)] = [("Starts", n(.start)), ("Halfway", n(.halfway)),
                                                     ("30 min left", n(.endingSoon)), ("Zikr", n(.zikr, .zikrLater))]
        let snoozed = n(.snooze, .other)
        if snoozed > 0 { parts.append(("Snoozed", snoozed)) }
        return parts
    }

    private var coverText: String {
        guard let last = pending.compactMap(\.date).max() else { return loaded ? "Nothing scheduled" : " " }
        return "Covers you through \(last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    /// One row per prayer in a day (its start, then its nudges), one for the day's zikr reminders,
    /// one for snoozed nudges.
    struct Group: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let isPrayer: Bool
        let items: [Item]      // by time
    }

    static func groups(_ items: [Item]) -> [Group] {
        var byKey: [String: [Item]] = [:]
        for item in items {
            let key: String
            switch item.kind {
            case .start, .halfway, .endingSoon: key = item.prayer ?? "Prayer"
            case .zikr, .zikrLater: key = "Zikr"
            case .snooze, .other: key = "Snoozed"
            }
            byKey[key, default: []].append(item)
        }
        return byKey.map { key, list in
            let sorted = list.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            let isPrayer = PrayerNotificationID.prayers.contains(key)
            let symbol = isPrayer ? prayerSymbol(key) : key == "Zikr" ? "circle.hexagonpath" : "clock.arrow.circlepath"
            return Group(id: key, title: key == "Snoozed" ? "Nudges you snoozed" : key, symbol: symbol, isPrayer: isPrayer, items: sorted)
        }
        .sorted { ($0.items.first?.date ?? .distantFuture) < ($1.items.first?.date ?? .distantFuture) }
    }

    private func groupRow(_ group: Group, faded: Bool) -> some View {
        let start = group.isPrayer ? group.items.first { $0.kind == .start } : nil
        let rest = group.items.filter { $0.id != start?.id }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: group.symbol)
                .font(.system(size: 15, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(group.isPrayer ? Color.sage : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(.system(.body, design: .rounded, weight: .regular))
                    // How many it has that day: 1 = the start, 2 = + halfway, 3 = + 30 min left.
                    Text("\(group.items.count)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.sage)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(Color.sage.opacity(0.14)))
                }
                if !rest.isEmpty {
                    // The other times, quiet (the count says what they are); each stays whole on a line.
                    Text(rest.map { detail($0, prayer: group.isPrayer).replacingOccurrences(of: " ", with: "\u{00A0}") }
                        .joined(separator: " · "))
                        .font(.system(.caption2, design: .rounded, weight: .light))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let start {
                Text(time(start))
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(faded ? 0.45 : 1)
    }

    /// "halfway 3:13 PM" for a prayer's nudge, "After Fajr 6:10 AM" for a zikr reminder.
    private func detail(_ item: Item, prayer: Bool) -> String {
        if prayer { return "\(item.kind == .start ? "starts" : item.kind.label) \(time(item))" }
        switch item.kind {
        case .zikr, .zikrLater: return "\(item.title.isEmpty ? "Zikr" : item.title) \(time(item))"
        default: return time(item)
        }
    }

    private func time(_ item: Item) -> String {
        item.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–"
    }

    /// Background refresh, the raw checks and (beta) the card previews: collapsed, at the bottom.
    private var details: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetails) {
                LabeledContent("Background refresh", value: refreshStatus)
                LabeledContent("Last ran in the background", value: lastRefresh)
                LabeledContent("Notifications", value: authText)
                LabeledContent("Scheduled Summary", value: health.summaryOn ? "on" : "off")
                LabeledContent("Time Sensitive", value: settingText(health.timeSensitive))
                LabeledContent("Waiting, by kind", value: kindCounts)
                if betaAccess.available {
                    // Testing the reminders card (feedback E37CE0F0): it follows rules, so it
                    // doesn't come every time — these show it now, whatever the rules say.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The reminders card")
                            .font(.subheadline.weight(.medium))
                        Text("Shows on the Salah page with nothing else open, not during the opening or within 10 s of a widget, at most every 3 days per kind, and not for 3 days after a \"no\" in the setup.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Off card: \(nextCardText(.off))\nHeld card: \(nextCardText(.held))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    Button("Preview the card: off") { previewCard = .off }
                        .tint(Color.sage)
                    Button("Preview the card: held") { previewCard = .held }
                        .tint(Color.sage)
                }
            } label: {
                Text("Details").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func nextCardText(_ issue: NotificationHealth.Issue) -> String {
        let applies = health.cardIssue == issue
        let next = health.nextCardDate(for: issue)
        let when = next.map { "from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "any time"
        return applies ? "applies now · may appear \(when)" : "doesn't apply now · would appear \(when)"
    }

    // MARK: data

    private var days: [(key: String, items: [Item])] {
        Dictionary(grouping: pending, by: \.dayKey)
            .map { (key: $0.key, items: $0.value) }
            .sorted { $0.key < $1.key }
    }

    private func dayTitle(_ key: String) -> String {
        let today = PrayerNotificationID.dayKey(PrayerDay.date())
        let tomorrow = PrayerNotificationID.dayKey(Calendar.current.date(byAdding: .day, value: 1, to: PrayerDay.date()) ?? Date())
        if key == today { return "Today" }
        if key == tomorrow { return "Tomorrow" }
        return Self.dayKeyFormatter.date(from: key).map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? key
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var kindCounts: String {
        let all = pending.map(\.kind)
        func n(_ k: Kind) -> Int { all.filter { $0 == k }.count }
        return "\(n(.start)) starts · \(n(.halfway) + n(.endingSoon)) nudges · \(n(.zikr) + n(.zikrLater)) zikr · \(n(.snooze)) snoozes"
    }

    private func load() async {
        await health.refresh()
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        pending = requests.map { item(id: $0.identifier, date: Self.nextDate($0), title: $0.content.title) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let todayStart = PrayerDay.sessionDayStart()
        deliveredToday = await center.deliveredNotifications()
            .filter { $0.date >= todayStart }
            .map { item(id: $0.request.identifier, date: $0.date, title: $0.request.content.title) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        loaded = true
    }

    private func item(id: String, date: Date?, title: String) -> Item {
        let fallbackDay = PrayerNotificationID.dayKey(PrayerDay.date(for: date ?? Date()))
        if let p = PrayerNotificationID.parse(id) {
            let kind: Kind = p.kind == "Start" ? .start : p.kind == "Mid" ? .halfway : .endingSoon
            return Item(id: id, date: date, dayKey: p.dayKey ?? fallbackDay, kind: kind, prayer: p.prayer, title: title)
        }
        let kind: Kind = id.hasPrefix("zikrlater.") ? .zikrLater : id.hasPrefix(ZikrReminders.prefix) ? .zikr
            : id.hasPrefix("snooze") ? .snooze : .other
        // A zikr reminder's id ends in its prayer day ("zikr.<task>.2026-09-28"): group by that.
        let zikrDay = kind == .zikr ? String(id.suffix(10)) : nil
        let day = zikrDay.flatMap { Self.dayKeyFormatter.date(from: $0) != nil ? $0 : nil } ?? fallbackDay
        return Item(id: id, date: date, dayKey: day, kind: kind, prayer: nil, title: title)
    }

    private static func nextDate(_ r: UNNotificationRequest) -> Date? {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
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
        return t == 0 ? "not yet" : Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .shortened)
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
