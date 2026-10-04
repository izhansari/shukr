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
//  setup's review uses the same checks, and Settings → Notifications → Your reminders
//  (`YourRemindersView`, everyone) lists everything waiting.
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
    @State private var whySheet: ReminderWhy?

    /// The status is the way in, in every build (owner, reminders-page-way-in: a dev Release install had none; then the
    /// extra "Your reminders ›" row above it was crossed out — one row): "Reminders are on · On time · scheduled through
    /// Mon, Oct 5" opens Your reminders; when something's wrong it says so in the warning style and opens the sheet that
    /// explains it (Arrives on time, or Tops itself up for background refresh — owner, reminders-page-g2), with a plain
    /// button per fix under it.
    var body: some View {
        let issues = health.issues
        Group {
            if health.checked {
                if issues.isEmpty {
                    NavigationLink { YourRemindersView() } label: { statusRow(issues) }
                } else {
                    Button { whySheet = ReminderWhy.forIssues(issues) } label: {
                        HStack {
                            statusRow(issues)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .tint(Color(.label))
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
        .sheet(item: $whySheet) { ReminderWhySheet(kind: $0) }
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
        // The setup's look: a light symbol in the toggles' green (or its soft orange), rounded type, a light detail.
        return HStack(spacing: 14) {
            Image(systemName: fine ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(fine ? Color(.systemGreen) : Color.orange.opacity(0.9))
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
    /// The explanation open as a sheet (ReminderWhy). DEBUG `-remindersSheet N` opens one (screenshots).
    @State private var whySheet: ReminderWhy?

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
            case .halfway: "halfway"   // the "Mid" nudge: halfway through the window (owner, 2026-10-03; 30 min in for a day)
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

    // MARK: the page (decision reminders-page-g2, owner, 2026-10-04)
    // G's order (Sami's study) made calm: the status and the 64 as one green bar, the week, the picked day's prayers —
    // each row says all its reminders (start, halfway, 30 min left; owner: "not clear that it's three"), the day's total
    // in its header — zikr on their own, the three explanations as rows opening sheets (orange ! when a setting is in
    // the way), and everything scheduled behind one row. The toggles' green only; the Salah list's grey prayer symbols;
    // rounded type.

    private var green: Color { Color(.systemGreen) }
    private var fine: Bool { health.issues.isEmpty && health.authorization != .notDetermined }

    var body: some View {
        let days = Array(weekDays.prefix(7))
        let day = days.indices.contains(selectedDay) ? days[selectedDay] : PrayerDay.date()
        let dayItems = items(on: day).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let prayers = PrayerNotificationID.prayers.filter { p in dayItems.contains { $0.prayer == p && Self.prayerKinds.contains($0.kind) } }
        let zikr = dayItems.filter { $0.kind == .zikr || $0.kind == .zikrLater }
        let others = dayItems.filter { [.masjid, .keepAlive, .other].contains($0.kind) }
        return List {
            Section {
                statusRow
                usageBar
            } footer: {
                Text("iOS lets each app keep 64 notifications waiting. shukr plans a week ahead and tops them up when you open it.")
            }

            Section { weekStrip(days) } header: { Text("This week") }

            Section {
                if prayers.isEmpty && others.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(.secondary)
                }
                ForEach(prayers, id: \.self) { prayerRow($0, dayItems) }
                ForEach(others) { item in
                    plainRow(symbol: "bell", title: line(for: item), time: time(item))
                }
            } header: {
                HStack {
                    Text(dayTitle(PrayerNotificationID.dayKey(day)))
                    Spacer()
                    Text("\(dayItems.count) reminder\(dayItems.count == 1 ? "" : "s")")
                }
            }

            if !zikr.isEmpty {
                Section("Zikr") {
                    ForEach(zikr) { item in
                        plainRow(symbol: "circle.dotted.circle", title: item.title.isEmpty ? "Zikr reminder" : item.title, time: time(item))
                    }
                }
            }

            Section("About your reminders") {
                ForEach(ReminderWhy.allCases) { kind in
                    Button { whySheet = kind } label: {
                        // Explicit colours: inside a Button's label the hierarchical styles took the tint (blue rows).
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol).foregroundStyle(Color(.secondaryLabel)).frame(width: 26)
                            Text(kind.title).foregroundStyle(Color(.label))
                            Spacer()
                            if kind.needsHand(health) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
            }

            Section {
                NavigationLink("All \(pending.count) scheduled") { allScheduled }
            }
        }
        .listStyle(.insetGrouped)
        .fontDesign(.rounded)
        .navigationTitle("Your reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Your reminders").font(.system(.headline, design: .rounded, weight: .regular))
            }
        }
        .refreshable { await load() }
        .task {
            await load()
            #if DEBUG
            if let n = UserDefaults.standard.string(forKey: "remindersSheet").flatMap(Int.init),
               let kind = ReminderWhy(rawValue: n) { whySheet = kind }
            #endif
        }
        .sheet(item: $previewCard) { issue in
            ReminderHealthCard(issue: issue) { previewCard = nil }
        }
        .sheet(item: $whySheet) { ReminderWhySheet(kind: $0, pendingCount: pending.count) }
    }

    private static let prayerKinds: [Kind] = [.start, .halfway, .endingSoon, .snooze]

    private var statusRow: some View {
        let off = health.authorization == .denied
        let title = off ? "Reminders are off" : fine ? "Reminders are on" : "Reminders need a hand"
        let through = health.scheduledThrough ?? pending.compactMap(\.date).max()
        let subtitle = off ? "Notifications are off for shukr"
            : fine ? "On time" + (through.map { " · scheduled through " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "")
            : "See Arrives on time below"
        return HStack(spacing: 14) {
            Image(systemName: fine ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(fine ? green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// One colour: used in green, free in grey; the numbers in words.
    private var usageBar: some View {
        let used = min(pending.count, NotificationScheduler.limit)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(used) of \(NotificationScheduler.limit) in use · \(max(0, NotificationScheduler.limit - used)) free")
                .font(.footnote).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(green).frame(width: geo.size.width * CGFloat(used) / CGFloat(NotificationScheduler.limit))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    /// The Calendar's week: the picked day filled green, today's number green; a grey dot under days with nudges.
    private func weekStrip(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(days.indices, id: \.self) { i in
                let d = days[i]
                let nudged = items(on: d).contains { $0.kind == .halfway || $0.kind == .endingSoon }
                Button {
                    triggerSomeVibration(type: .light)
                    selectedDay = i
                } label: {
                    VStack(spacing: 6) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        Text(d.formatted(.dateTime.day()))
                            .foregroundStyle(selectedDay == i ? Color.white : (i == 0 ? green : Color.primary))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(selectedDay == i ? green : .clear))
                        Circle().fill(nudged ? Color(.tertiaryLabel) : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// One row per prayer: its grey symbol, the name, how many reminders; under it every one of them with its time —
    /// "Start 1:07 · Halfway 2:41 · 30 min left 3:46" — so a nudged prayer reads as three.
    private func prayerRow(_ prayer: String, _ dayItems: [Item]) -> some View {
        let mine = dayItems.filter { $0.prayer == prayer && Self.prayerKinds.contains($0.kind) }
        let parts = mine.map { item -> String in
            let label = switch item.kind {
            case .start: "Start"
            case .halfway: "Halfway"
            case .endingSoon: "30 min left"
            default: "Later"
            }
            return "\(label) \(Self.hm(item.date))"
        }
        return HStack(spacing: 12) {
            Image(systemName: prayerSymbol(prayer)).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(prayer)
                Text(parts.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 3) {
                Text("\(mine.count)").monospacedDigit()
                Image(systemName: "bell").font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(mine.count) reminder\(mine.count == 1 ? "" : "s")")
        }
    }

    private func plainRow(symbol: String, title: String, time: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 26)
            Text(title)
            Spacer()
            Text(time).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private static func hm(_ date: Date?) -> String {
        guard let date else { return "–" }
        return hmFormatter.string(from: date)
    }
    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()

    /// Everything waiting, by prayer day, and the raw checks (Details).
    private var allScheduled: some View {
        let keys = Array(Set(pending.map(\.dayKey))).sorted()
        return List {
            ForEach(keys, id: \.self) { key in
                let list = pending.filter { $0.dayKey == key }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                Section {
                    ForEach(list) { item in
                        HStack {
                            Text(line(for: item))
                            Spacer()
                            Text(time(item)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    HStack { Text(dayTitle(key)); Spacer(); Text("\(list.count)") }
                }
            }
            Section { details }
        }
        .listStyle(.insetGrouped)
        .fontDesign(.rounded)
        .navigationTitle("All scheduled")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
    private var details: some View {
        Group {
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
                            .tint(Color(.systemGreen))
                        Button("Preview the card: held") { previewCard = .held }
                            .tint(Color(.systemGreen))
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
                // The real window when there's a location (as the scheduler: 🟡 halfway, 🔴 30 min before the end,
                // no 🟡 under 90 min); else a 2.5 h stand-in.
                let start = windows?[name]?.start ?? Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
                let end = windows?[name]?.end ?? start?.addingTimeInterval(9000)
                items.append(Item(id: "\(key).\(name)Start", date: start, dayKey: key, kind: .start, prayer: name, title: name))
                if d < 2, let start, let end {
                    let length = end.timeIntervalSince(start)
                    if length >= NotificationScheduler.halfwayMinimumWindow {
                        items.append(Item(id: "\(key).\(name)Mid", date: start.addingTimeInterval(length / 2), dayKey: key, kind: .halfway, prayer: name, title: name))
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
