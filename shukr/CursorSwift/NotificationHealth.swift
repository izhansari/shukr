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
    /// What's scheduled, for Settings' status row and Your reminders: how many are waiting, the last
    /// one before the last-resort reminder, and that reminder's date.
    @Published private(set) var pendingCount = 0
    @Published private(set) var scheduledThrough: Date?
    @Published private(set) var keepAliveDate: Date?

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
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        func fire(_ r: UNNotificationRequest) -> Date? {
            (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        }
        let keepAlive = pending.first { $0.identifier.hasPrefix(NotificationScheduler.keepAlivePrefix) }.flatMap(fire)
        let through = pending.filter { !$0.identifier.hasPrefix(NotificationScheduler.keepAlivePrefix) }.compactMap(fire).max()
        if pendingCount != pending.count { pendingCount = pending.count }
        if scheduledThrough != through { scheduledThrough = through }
        if keepAliveDate != keepAlive { keepAliveDate = keepAlive }
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
                    line("bell.badge", "a nudge 30 min in and with 30 min left")
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
    @ObservedObject private var betaAccess = WhatsNewAccess.shared

    /// The status IS the way in (owner, 2026-09-28): "Reminders are on · On time · scheduled through
    /// Mon, Oct 5" opens Your reminders; when something's wrong it says so in the warning style, with
    /// a plain button per fix under it.
    var body: some View {
        let issues = health.issues
        Group {
            if health.checked {
                if UpcomingReminders.isPublic || betaAccess.beta {
                    NavigationLink { YourRemindersView() } label: { statusRow(issues) }
                } else {
                    statusRow(issues)
                }
                if health.authorization == .notDetermined {
                    fix("Allow notifications") { NotificationStatus.shared.request() }
                }
                ForEach(issues, id: \.self) { issue in
                    switch issue {
                    case .off: fix("Turn on notifications", SettingsLinks.notifications)
                    case .held: fix("Turn on Time Sensitive or Immediate Delivery", SettingsLinks.notifications)
                    case .timeSensitiveOff: fix("Turn on Time Sensitive", SettingsLinks.notifications)
                    case .backgroundRefreshOff: fix("Turn on Background App Refresh", SettingsLinks.app)
                    }
                }
            }
        }
        .task { await health.refresh() }
    }

    private func statusRow(_ issues: [NotificationHealth.Issue]) -> some View {
        let (title, subtitle): (String, String) = {
            if health.authorization == .notDetermined { return ("Reminders need notifications", "Allow them so shukr can remind you") }
            switch issues.first {
            case .off: return ("Reminders are off", "Notifications are off for shukr")
            case .held: return ("Reminders may arrive late", "Held for the Scheduled Summary")
            case .timeSensitiveOff: return ("Reminders are on", "Time Sensitive is off: Focus may hold them")
            case .backgroundRefreshOff: return ("Reminders are on", "Background refresh is off: open shukr every few days")
            case nil:
                let through = health.scheduledThrough.map { " · scheduled through " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
                return ("Reminders are on", "On time" + through)
            }
        }()
        let fine = issues.isEmpty && health.authorization != .notDetermined
        // The setup's look: a light symbol in sage (or its soft orange), rounded type, a light detail.
        return HStack(spacing: 14) {
            Image(systemName: fine ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(fine ? Color.sage : Color.orange.opacity(0.9))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded)).foregroundStyle(.primary)
                Text(subtitle).font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func fix(_ title: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(Color.sage)
        }
    }
}

// MARK: - Upcoming reminders (Settings → Notifications)

/// Whether "Upcoming reminders" is in everyone's Settings. **The one line to flip to make it public**
/// (feedback E37CE0F0): `true` shows it in the App Store build too; the beta-only card previews in its
/// Details section stay behind `WhatsNewAccess` either way.
enum UpcomingReminders {   // (the page is YourRemindersView)
    static let isPublic = false
}

/// Every notification shukr has waiting with iOS (out of its 64), grouped by prayer day, with what
/// each one is; today's delivered ones greyed at the end; the technical bits in a collapsed Details.
struct YourRemindersView: View {
    @ObservedObject private var health = NotificationHealth.shared
    @ObservedObject private var betaAccess = WhatsNewAccess.shared
    @Environment(\.colorScheme) private var scheme
    @State private var pending: [Item] = []
    @State private var deliveredToday: [Item] = []
    @State private var loaded = false
    @State private var showDetails = Self.debugFlag("-upcomingDetails")
    @State private var previewCard: NotificationHealth.Issue?
    /// The picked day of "This week" (0 = today) and the open "why" tile. DEBUG `-remindersDay N`,
    /// `-remindersWhy N`.
    @State private var selectedDay = Self.debugInt("remindersDay")
    @State private var selectedWhy = Self.debugInt("remindersWhy")

    private static func debugFlag(_ arg: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(arg)
        #else
        return false
        #endif
    }
    private static func debugInt(_ key: String) -> Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: key)
        #else
        return 0
        #endif
    }

    /// One notification, read once from its request.
    struct Item: Identifiable {
        let id: String
        let date: Date?
        let dayKey: String          // its prayer day ("2026-09-28")
        let kind: Kind
        let prayer: String?
        let title: String
        var subtitle = ""
    }
    enum Kind: CaseIterable {
        case start, halfway, endingSoon, zikr, zikrLater, snooze, masjid, keepAlive, other
        var label: String {
            switch self {
            case .start: "starts"
            case .halfway: "30 min in"   // the "Mid" nudge: 30 min after the start (was halfway)
            case .endingSoon: "30 min left"
            case .zikr: "zikr reminder"
            case .zikrLater: "zikr, later"
            case .snooze: "nudge me later"
            case .masjid: "masjid dua"
            case .keepAlive: "reminder to open shukr"
            case .other: "reminder"
            }
        }
    }

    // MARK: colours — iOS-native (owner, 49171DB2: the muted brand tones read "dull … too android"):
    // sage stays the accent (the ok ink, the week rings, the picked tile); the bead kinds use the
    // system tints, which adapt to light / dark; free slots a clear system grey.

    private static let startColor = Color(.systemGreen)                                // starts
    private static let halfColor = Color(.systemYellow)                                // 30 min in (the 🟡 nudge)
    private static let endColor = Color(.systemRed)                                    // 30 min left
    private static let zikrColor = Color(.systemBlue)                                  // zikr
    private static let laterColor = Color(.systemPurple)                               // later
    private static let otherColor = Color(.systemGray)                                 // other
    private var freeColor: Color { Color(.systemGray4) }
    /// Tile / day switches: one spring for the content swap and the card's height.
    private static let switchSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)
    private var okInk: Color { Color.sage }
    private var warnInk: Color { Color.orange.opacity(0.9) }                              // the setup's Nudge
    private var okTint: Color { Color.sage.opacity(scheme == .dark ? 0.22 : 0.14) }
    private var warnTint: Color { Color.orange.opacity(0.08) }
    /// The setup's small uppercase caption ("today").
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func color(_ kind: Kind) -> Color {
        switch kind {
        case .start: Self.startColor
        case .halfway: Self.halfColor
        case .endingSoon: Self.endColor
        case .zikr, .zikrLater: Self.zikrColor
        case .snooze: Self.laterColor
        case .masjid, .keepAlive, .other: Self.otherColor
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 18) {
                // What this page is for, before any numbers (owner, 49171DB2).
                Text("iOS keeps up to 64 notifications per app. shukr budgets them carefully. Here\u{2019}s how.")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                hero
                week
                whyTiles
                whyCard.id("whyCard")
                detailsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        #if DEBUG
        // `-remindersScroll`: down to the open tile's card (screenshots).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-remindersScroll") else { return }
            try? await Task.sleep(for: .seconds(1.2))
            proxy.scrollTo("whyCard", anchor: .bottom)
        }
        #endif
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())   // white / near-black cards on it
        .navigationTitle("Your reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Your reminders").font(.system(.headline, design: .rounded, weight: .regular))
            }
        }
        .fontDesign(.rounded)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $previewCard) { issue in
            ReminderHealthCard(issue: issue) { previewCard = nil }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: hero — 64 beads, one per iOS slot

    /// Beads in order: starts, halfway, 30 min left, zikr, later, other, then the free slots.
    private var beadKinds: [Kind?] {
        let order: [Kind] = [.start, .halfway, .endingSoon, .zikr, .zikrLater, .snooze, .masjid, .other, .keepAlive]
        var list: [Kind?] = order.flatMap { k in Array(repeating: Optional(k), count: pending.filter { $0.kind == k }.count) }
        if list.count < NotificationScheduler.limit { list += Array(repeating: nil, count: NotificationScheduler.limit - list.count) }
        return Array(list.prefix(NotificationScheduler.limit))
    }

    private var hero: some View {
        let kinds = beadKinds
        let problem: (text: String, warn: Bool) = {
            if health.authorization == .denied { return ("reminders off", true) }
            if health.authorization == .notDetermined { return ("not set up yet", true) }
            if health.issues.contains(.held) { return ("may be late", true) }
            return ("on time", false)
        }()
        return VStack(spacing: 10) {
            ZStack {
                ForEach(0..<kinds.count, id: \.self) { i in
                    let a = -Double.pi / 2 + Double(i) / Double(kinds.count) * 2 * .pi
                    let r: CGFloat = kinds[i] == nil ? 4 : 5.2
                    Circle()
                        .fill(kinds[i].map(color) ?? freeColor)
                        .frame(width: r * 2, height: r * 2)
                        .position(x: 132 + 118 * cos(a), y: 132 + 118 * sin(a))
                }
                VStack(spacing: 2) {
                    Label(problem.text, systemImage: problem.warn ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(problem.warn ? warnInk : okInk)
                    Text("\(pending.count)")
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("of 64 waiting")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let through = health.scheduledThrough ?? pending.compactMap(\.date).max() {
                        Text("through " + through.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.sage)
                            .padding(.top, 6)
                    }
                }
            }
            .frame(width: 264, height: 264)
            // The legend: the kinds that are there, and free.
            HStack(spacing: 12) {
                ForEach(legend, id: \.label) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.label)
                    }
                }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: [(label: String, color: Color)] {
        let present = Set(pending.map(\.kind))
        var list: [(label: String, color: Color)] = []
        if present.contains(.start) { list.append(("starts", Self.startColor)) }
        if present.contains(.halfway) { list.append(("30 min in", Self.halfColor)) }
        if present.contains(.endingSoon) { list.append(("30 min", Self.endColor)) }
        if present.contains(.zikr) || present.contains(.zikrLater) { list.append(("zikr", Self.zikrColor)) }
        if present.contains(.snooze) { list.append(("later", Self.laterColor)) }
        if !present.isDisjoint(with: [.masjid, .other, .keepAlive]) { list.append(("other", Self.otherColor)) }
        list.append(("free", freeColor))
        return list
    }

    // MARK: this week

    /// Today through the last day anything is scheduled for (the plan can reach an eighth prayer day
    /// after Fajr), at least a week — so the rings add up to the hero's count.
    private var weekDays: [Date] {
        let today = PrayerDay.date()
        let lastKey = pending.map(\.dayKey).max()
        let last = lastKey.flatMap { Self.dayKeyFormatter.date(from: $0) }
        let span = last.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today), to: $0).day ?? 6 } ?? 6
        return (0...max(6, min(span, 9))).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func items(on day: Date) -> [Item] {
        let key = PrayerNotificationID.dayKey(day)
        return pending.filter { $0.dayKey == key }
    }

    private var week: some View {
        let days = weekDays
        let counts = days.map { items(on: $0).count }
        let most = max(counts.max() ?? 1, 1)
        let pick = min(max(selectedDay, 0), days.count - 1)
        return VStack(alignment: .leading, spacing: 10) {
            caption("This week")
                .padding(.horizontal, 4)
            HStack(spacing: 4) {
                ForEach(days.indices, id: \.self) { i in
                    let dayItems = items(on: days[i])
                    let nudges = dayItems.contains { $0.kind == .halfway || $0.kind == .endingSoon }
                    let selected = i == pick
                    VStack(spacing: 4) {
                        Text(days[i].formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(.caption, design: .rounded, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? okInk : .secondary)
                        ZStack {
                            Circle().fill(selected ? okTint : .clear)
                            Circle().stroke(Color(.systemGray5), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: CGFloat(counts[i]) / CGFloat(most))
                                .stroke(nudges ? Color.sage : Color.sage.opacity(0.55),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(counts[i])")
                                .font(.system(.subheadline, design: .rounded, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? okInk : .primary)
                                .monospacedDigit()
                        }
                        .frame(width: days.count > 7 ? 34 : 40, height: days.count > 7 ? 34 : 40)
                        Circle().fill(nudges ? Color.sage : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerSomeVibration(type: .light)
                        withAnimation(Self.switchSpring) { selectedDay = i }
                    }
                }
            }
            dayCard(days[pick], items: items(on: days[pick]))
        }
    }

    /// The picked day: each prayer with its times ("Dhuhr 1:07 · 3:13 · 4:49"), zikr by task, and
    /// whether it has its nudges yet.
    private func dayCard(_ day: Date, items: [Item]) -> some View {
        let key = PrayerNotificationID.dayKey(day)
        let nudges = items.contains { $0.kind == .halfway || $0.kind == .endingSoon }
        let anyNudgeSetting = PrayerNotificationID.prayers.contains {
            NotificationScheduler.settings($0).notify && NotificationScheduler.settings($0).nudges
        }
        let tag = nudges ? "with nudges"
            : (anyNudgeSetting && items.contains { $0.kind == .start })
                ? "starts only · nudges added \(nudgesAddedOn(key) ?? "later")" : ""
        let title: String = {
            let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            switch dayTitle(key) {
            case "Today": return "Today · \(date)"
            case "Tomorrow": return "Tomorrow · \(date)"
            default: return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
        }()
        // The card stays put; only its content crossfades, and its height follows with the same spring
        // (owner, 49171DB2: swapping the whole card overlapped the two and jumped).
        return card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(.body, design: .rounded, weight: .medium))
                    Spacer(minLength: 8)
                    Text(tag).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if items.isEmpty {
                    Text(loaded ? "Nothing scheduled this day." : " ")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                }
                ForEach(dayLines(items), id: \.name) { line in
                    HStack(spacing: 12) {
                        Image(systemName: line.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.sage)
                            .frame(width: 22)
                        Text(line.name).font(.system(.subheadline, design: .rounded)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(line.times).font(.system(.footnote, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .id(key)
            .transition(.sheetContent(offset: 6))   // the old goes quickly, the new comes a beat later: no ghosting
        }
    }

    private func dayLines(_ items: [Item]) -> [(name: String, symbol: String, times: String)] {
        var lines: [(name: String, symbol: String, times: String, first: Date)] = []
        for prayer in PrayerNotificationID.prayers {
            let mine = items.filter { $0.prayer == prayer && [.start, .halfway, .endingSoon].contains($0.kind) }
            guard !mine.isEmpty else { continue }
            lines.append((prayer, prayerSymbol(prayer), mine.map(shortTime).joined(separator: " · "), mine.compactMap(\.date).min() ?? .distantFuture))
        }
        for item in items where ![.start, .halfway, .endingSoon].contains(item.kind) {
            let (name, symbol): (String, String) = {
                switch item.kind {
                case .zikr, .zikrLater: ("Zikr · \(item.title.isEmpty ? "reminder" : item.title)", "circle.dotted.circle")
                case .snooze: ("Later · \(item.prayer ?? item.title)", "clock.arrow.circlepath")
                case .keepAlive: ("Reminder to open shukr", "arrow.clockwise.circle")
                case .masjid: (line(for: item), "building.columns")
                default: (item.title.isEmpty ? "Reminder" : item.title, "bell")
                }
            }()
            lines.append((name + (lines.contains { $0.name == name } ? " " : ""), symbol, shortTime(item), item.date ?? .distantFuture))
        }
        return lines.sorted { $0.first < $1.first }.map { ($0.name, $0.symbol, $0.times) }
    }

    /// "1:07", no AM / PM (the canvas's day lines).
    private func shortTime(_ item: Item) -> String {
        item.date.map { Self.hmFormatter.string(from: $0) } ?? "–"
    }
    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()

    // MARK: the three whys

    private struct Point {
        let big: String; let small: String; let symbol: String; let warn: Bool
        /// Explaining, not about his settings: drawn in grey, never red.
        var neutral = false
    }

    private var whyTiles: some View {
        let tiles: [(String, String)] = [("Why only 64?", "questionmark.circle"), ("Tops itself up", "arrow.triangle.2.circlepath"),
                                          ("Arrives on time", "clock.badge.checkmark")]
        return HStack(spacing: 8) {
            ForEach(tiles.indices, id: \.self) { i in
                // The setup's option cards: a sage tint and edge on the picked one.
                let picked = i == selectedWhy
                VStack(spacing: 8) {
                    Image(systemName: tiles[i].1).font(.system(size: 20, weight: .regular)).foregroundStyle(Color.sage)
                    Text(tiles[i].0).font(.system(.footnote, design: .rounded, weight: picked ? .medium : .regular))
                        .foregroundStyle(picked ? Color.sage : .primary)
                        .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? okTint : Color(.secondarySystemGroupedBackground)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(picked ? Color.sage.opacity(0.7) : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerSomeVibration(type: .light)
                    withAnimation(Self.switchSpring) { selectedWhy = i }
                }
            }
        }
    }

    private var lateCombination: Bool { health.summaryOn && health.timeSensitive != .enabled }

    /// A card's headline, its points, and (Arrives on time) a separate neutral explainer under a heading.
    private var why: (head: String, points: [Point], explainHead: String?, explain: [Point]) {
        switch selectedWhy {
        case 1:
            let lastRun = UserDefaults.standard.double(forKey: NotificationHealth.lastRefreshKey)
            let ran = lastRun == 0 ? "" : " Last ran " + Self.whenText(Date(timeIntervalSince1970: lastRun)) + "."
            let bgOn = health.backgroundRefresh == .available
            let keep = health.keepAliveDate.map { " (\($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))" } ?? ""
            return ("Your week keeps topping itself up.", [
                bgOn ? Point(big: "Background refresh is on", small: "iOS wakes shukr now and then to add the next days." + ran, symbol: "arrow.triangle.2.circlepath", warn: false)
                     : Point(big: "Background refresh is off", small: "Turn it on in Settings, or open shukr every few days.", symbol: "arrow.triangle.2.circlepath", warn: true),
                Point(big: "Opening shukr tops it up too", small: "Any time you open the app, the week refills.", symbol: "iphone", warn: false),
                Point(big: "Never a silent stop", small: "If iOS can’t refresh, your last reminder\(keep) asks you to open shukr.", symbol: "bell.badge", warn: false),
            ], nil, [])
        case 2:
            // First HIS settings and what they mean for him — red only where one is really a problem —
            // then, separately and neutrally, how iOS delivers notifications (owner, 9E5AC5BF: the red
            // "late" row read as his own setting being wrong).
            let off = health.authorization == .denied
            let ts = health.timeSensitive == .enabled
            let tsOff = health.timeSensitive == .disabled
            let head = off ? "Notifications are off for shukr."
                : lateCombination ? "Yours may arrive late." : "Yours arrive on time."
            var mine: [Point] = []
            mine.append(off
                ? Point(big: "Notifications: off", small: "shukr can’t remind you at all until you turn them on.", symbol: "bell.slash", warn: true)
                : Point(big: "Notifications: on", small: "shukr can remind you.", symbol: "bell", warn: false))
            if !off {
                mine.append(ts
                    ? Point(big: "Time Sensitive: on", small: "Reminders come through Focus modes and the Scheduled Summary.", symbol: "clock", warn: false)
                    : Point(big: "Time Sensitive: \(tsOff ? "off" : "not available")", small: "A Focus mode can hold reminders back.", symbol: "clock", warn: tsOff))
                mine.append(health.summaryOn
                    ? Point(big: "Scheduled Summary: on", small: ts ? "Reminders still come right away (Time Sensitive lets them through)."
                                                                       : "Reminders wait for the next summary, so they can arrive late.",
                            symbol: "tray.full", warn: !ts)
                    : Point(big: "Scheduled Summary: off", small: "Reminders come right away.", symbol: "checkmark.circle", warn: false))
            }
            let explain = [
                Point(big: "Time Sensitive", small: "Lets a reminder through Focus modes and the Scheduled Summary. shukr marks prayer reminders Time Sensitive.", symbol: "clock", warn: false, neutral: true),
                Point(big: "Scheduled Summary", small: "Collects notifications and delivers them at the times you choose, instead of right away.", symbol: "tray.full", warn: false, neutral: true),
                Point(big: "Focus", small: "Silences notifications, except apps you allow and Time Sensitive ones.", symbol: "moon", warn: false, neutral: true),
                Point(big: "Together", small: "With the Summary on and Time Sensitive off, reminders wait for the next summary — that’s the one setup that makes them late.", symbol: "info.circle", warn: false, neutral: true),
            ]
            return (head, mine, "How iOS delivers notifications", explain)
        default:
            let n = NotificationScheduler.nudgeDaysAhead
            let free = max(NotificationScheduler.limit - pending.count, 0)
            return ("How the 64 are spent.", [
                Point(big: "Every start, all week", small: "Each prayer’s start is scheduled \(NotificationScheduler.daysAhead) days ahead.", symbol: "calendar", warn: false),
                Point(big: "Nudges for the next \(n == 2 ? "2" : "\(n)") days", small: "The 30-min-in and 30-min-left nudges (the dotted days) are added as each day comes closer.", symbol: "bell.badge", warn: false),
                Point(big: "\(free) slot\(free == 1 ? "" : "s") free", small: "Room for snoozes and zikr reminders.", symbol: "circle.dashed", warn: false),
            ], nil, [])
        }
    }

    private var whyCard: some View {
        let why = why
        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text(why.head).font(.system(.title3, design: .rounded, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if why.explainHead != nil {
                    caption("Your settings")
                }
                ForEach(why.points.indices, id: \.self) { i in
                    pointRow(why.points[i])
                }
                if selectedWhy == 2 && (lateCombination || health.authorization == .denied || health.timeSensitive == .disabled) {
                    // The setup's primary button: sage text on a soft sage tint with a sage edge.
                    Button { SettingsLinks.notifications() } label: {
                        Text("Fix in Settings").font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.sage)
                            .frame(maxWidth: .infinity).frame(minHeight: 48)
                            .background(Capsule().fill(Color.sage.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.sage.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if let explainHead = why.explainHead {
                    Divider().padding(.vertical, 2)
                    caption(explainHead)
                    ForEach(why.explain.indices, id: \.self) { i in
                        pointRow(why.explain[i])
                    }
                }
            }
            // Only the content swaps (out, then in); the card and its height follow `switchSpring`.
            .id(selectedWhy)
            .transition(.sheetContent(offset: 6))
        }
    }

    /// The setup's why-row: a light symbol (sage; the setup's orange when it needs a hand; grey for
    /// the neutral explainer), a title and a light detail.
    private func pointRow(_ p: Point) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: p.symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(p.neutral ? Color.secondary : p.warn ? warnInk : okInk)
                .frame(width: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.big).font(.system(.body, design: .rounded))
                    .foregroundStyle(p.warn && !p.neutral ? warnInk : .primary)
                Text(p.small).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func whenText(_ date: Date) -> String {
        let t = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "today, \(t)" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday, \(t)" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", \(t)"
    }

    /// A notification as it reads, so it can be recognised.
    private func line(for item: Item) -> String {
        switch item.kind {
        case .start, .halfway, .endingSoon: "\(item.prayer ?? "Prayer") · \(item.kind.label)"
        case .zikr, .zikrLater: "Zikr · \(item.title.isEmpty ? "reminder" : item.title)"
        case .snooze: [item.prayer, item.title.isEmpty ? "nudge me later" : "\u{201C}\(item.title)\u{201D}"]
            .compactMap { $0 }.joined(separator: " · ")
        case .masjid: [item.title, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        case .keepAlive: "Reminder to open shukr"
        case .other: item.title.isEmpty ? "Reminder" : item.title
        }
    }

    /// A starts-only day's nudges are planned once it's within `nudgeDaysAhead` prayer days — i.e.
    /// the day before it, when shukr re-plans (opening it, or iOS's background refresh).
    private func nudgesAddedOn(_ key: String) -> String? {
        guard let day = Self.dayKeyFormatter.date(from: key),
              let before = Calendar.current.date(byAdding: .day, value: -(NotificationScheduler.nudgeDaysAhead - 1), to: day)
        else { return nil }
        let today = PrayerDay.date()
        if PrayerNotificationID.dayKey(before) == PrayerNotificationID.dayKey(today) { return "later today" }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today),
           PrayerNotificationID.dayKey(before) == PrayerNotificationID.dayKey(tomorrow) { return "tomorrow" }
        return before.formatted(.dateTime.weekday(.abbreviated))
    }

    private func time(_ item: Item) -> String {
        item.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–"
    }

    /// Background refresh, the raw checks and (beta) the card previews: collapsed, at the bottom.
    private var detailsCard: some View {
        card {
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Background refresh", value: refreshStatus)
                    LabeledContent("Last ran in the background", value: lastRefresh)
                    LabeledContent("Notifications", value: authText)
                    LabeledContent("Scheduled Summary", value: health.summaryOn ? "on" : "off")
                    LabeledContent("Time Sensitive", value: settingText(health.timeSensitive))
                    LabeledContent("Waiting, by kind", value: kindCounts)
                    LabeledContent("Delivered today", value: "\(deliveredToday.count)")
                    if betaAccess.beta {
                        // Testing the reminders card (feedback E37CE0F0): it follows rules, so it
                        // doesn't come every time — these show it now, whatever the rules say.
                        Divider()
                        Text("The reminders card")
                            .font(.subheadline.weight(.medium))
                        Text("Shows on the Salah page with nothing else open, not during the opening or within 10 s of a widget, at most every 3 days per kind, and not for 3 days after a \"no\" in the setup.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Off card: \(nextCardText(.off))\nHeld card: \(nextCardText(.held))")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Preview the card: off") { previewCard = .off }
                            .tint(Color.sage)
                        Button("Preview the card: held") { previewCard = .held }
                            .tint(Color.sage)
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .padding(.top, 10)
            } label: {
                Text("Details").font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }

    private func nextCardText(_ issue: NotificationHealth.Issue) -> String {
        let applies = health.cardIssue == issue
        let next = health.nextCardDate(for: issue)
        let when = next.map { "from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "any time"
        return applies ? "applies now · may appear \(when)" : "doesn't apply now · would appear \(when)"
    }

    // MARK: data

    private func dayTitle(_ key: String) -> String {
        let today = PrayerNotificationID.dayKey(PrayerDay.date())
        let tomorrow = PrayerNotificationID.dayKey(Calendar.current.date(byAdding: .day, value: 1, to: PrayerDay.date()) ?? Date())
        if key == today { return "Today" }
        if key == tomorrow { return "Tomorrow" }
        // The weekday alone: the card's date sits beside it.
        return Self.dayKeyFormatter.date(from: key).map { $0.formatted(.dateTime.weekday(.wide)) } ?? key
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
        #if DEBUG
        // `-demoRemindersSample`: a full-looking week for screenshots (the simulator's notifications
        // can't be switched on): starts all week, nudges for two days, a few zikr and one "later".
        if ProcessInfo.processInfo.arguments.contains("-demoRemindersSample") {
            pending = Self.sampleItems()
            loaded = true
            return
        }
        #endif
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        pending = requests.filter { Self.shown($0.identifier) }
            .map { item(id: $0.identifier, date: Self.nextDate($0), content: $0.content) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let todayStart = PrayerDay.sessionDayStart()
        deliveredToday = await center.deliveredNotifications()
            .filter { $0.date >= todayStart && Self.shown($0.request.identifier) }
            .map { item(id: $0.request.identifier, date: $0.date, content: $0.request.content) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        loaded = true
    }

    #if DEBUG
    private static func sampleItems() -> [Item] {
        let times: [(String, Int, Int)] = [("Fajr", 5, 58), ("Dhuhr", 13, 7), ("Asr", 16, 28), ("Maghrib", 19, 3), ("Isha", 20, 13)]
        var items: [Item] = []
        for d in 0..<7 {
            guard let day = Calendar.current.date(byAdding: .day, value: d, to: PrayerDay.date()) else { continue }
            let key = PrayerNotificationID.dayKey(day)
            let windows = NotificationScheduler.windows(for: day)
            for (name, h, m) in times {
                // The real window when there's a location (as the scheduler: 🟡 30 min in, 🔴 30 min before
                // the end, no 🟡 under 75 min); else a 2.5 h stand-in.
                let start = windows?[name]?.start ?? Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
                let end = windows?[name]?.end ?? start?.addingTimeInterval(9000)
                items.append(Item(id: "\(key).\(name)Start", date: start, dayKey: key, kind: .start, prayer: name, title: name))
                if d < 2, let start, let end {
                    if end.timeIntervalSince(start) >= 75 * 60 {
                        items.append(Item(id: "\(key).\(name)Mid", date: start.addingTimeInterval(1800), dayKey: key, kind: .halfway, prayer: name, title: name))
                    }
                    items.append(Item(id: "\(key).\(name)End", date: end.addingTimeInterval(-1800), dayKey: key, kind: .endingSoon, prayer: name, title: name))
                }
            }
            if d < 5 {
                let at = Calendar.current.date(bySettingHour: 6, minute: 10, second: 0, of: day)
                items.append(Item(id: "zikr.sample.\(key)", date: at, dayKey: key, kind: .zikr, prayer: nil, title: "After Fajr"))
            }
        }
        items.append(Item(id: "snooze-sample", date: Date().addingTimeInterval(600), dayKey: PrayerNotificationID.dayKey(PrayerDay.date()),
                          kind: .snooze, prayer: "Asr", title: ""))
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    #endif

    /// The DEBUG scheduler test's snoozes never show outside DEBUG builds.
    private static func shown(_ id: String) -> Bool {
        #if DEBUG
        return true
        #else
        return !id.hasPrefix("snooze-debug-")
        #endif
    }

    private func item(id: String, date: Date?, content: UNNotificationContent) -> Item {
        let title = content.title
        let fallbackDay = PrayerNotificationID.dayKey(PrayerDay.date(for: date ?? Date()))
        if let p = PrayerNotificationID.parse(id) {
            let kind: Kind = p.kind == "Start" ? .start : p.kind == "Mid" ? .halfway : .endingSoon
            return Item(id: id, date: date, dayKey: p.dayKey ?? fallbackDay, kind: kind, prayer: p.prayer, title: title)
        }
        let kind: Kind = id.hasPrefix("zikrlater.") ? .zikrLater : id.hasPrefix(ZikrReminders.prefix) ? .zikr
            : id.hasPrefix("snooze") ? .snooze : id.hasPrefix("masjidArrival.") ? .masjid
            : id.hasPrefix(NotificationScheduler.keepAlivePrefix) ? .keepAlive : .other
        // A zikr reminder's id ends in its prayer day ("zikr.<task>.2026-09-28"): group by that.
        let zikrDay = kind == .zikr ? String(id.suffix(10)) : nil
        let day = zikrDay.flatMap { Self.dayKeyFormatter.date(from: $0) != nil ? $0 : nil } ?? fallbackDay
        // A "Nudge me later" follow-up carries its prayer (the original notification's userInfo).
        let prayer = kind == .snooze ? content.userInfo["prayerName"] as? String : nil
        return Item(id: id, date: date, dayKey: day, kind: kind, prayer: prayer, title: title, subtitle: content.subtitle)
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
