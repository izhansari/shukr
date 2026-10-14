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
    /// How many are waiting, the last-resort reminder left out (Settings' "12 scheduled through …").
    @Published private(set) var scheduledCount = 0
    /// The next one to arrive (Settings' Your Notifications row: "Next 4:53 PM").
    @Published private(set) var nextAt: Date?
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
        let keepAlive = pending.first { NotificationScheduler.isLastKeepAlive($0.identifier) }.flatMap(fire)
        let dates = pending.filter { !$0.identifier.hasPrefix(NotificationScheduler.keepAlivePrefix) }.compactMap(fire)
        let through = dates.max()
        if scheduledCount != dates.count { scheduledCount = dates.count }
        let now = Date()
        let next = dates.filter { $0 > now }.min()
        if nextAt != next { nextAt = next }
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

    /// The status is the way in, in every build (owner, reminders-page-way-in: a dev Release install had none; then the
    /// extra "Your reminders ›" row above it was crossed out — one row): "Reminders are on · On time · scheduled through
    /// Mon, Oct 5" opens Your reminders; when something's wrong it says so in the warning style, and the page opens with
    /// the sheet that explains it already up (Notification settings, or Tops itself up for background refresh — owner,
    /// reminders-page-g2), with a plain button per fix under the row.
    var body: some View {
        let issues = health.issues
        Group {
            if health.checked {
                // Always the way into Your reminders; with something wrong the page opens with that explanation's sheet
                // already up (owner: "clicking that thing in the settings should take us to that sheet"; Bradley's
                // review: the page itself must stay reachable in every state).
                // All well: no row (owner, decision reminders-status-row B — the tiles first, Your Notifications under
                // them, "Scheduled through …" under the card). Something in the way: this row, in the warning style.
                if !issues.isEmpty || health.authorization == .notDetermined {
                    NavigationLink {
                        YourRemindersView(openWith: issues.isEmpty ? nil : ReminderWhy.forIssues(issues))
                    } label: { statusRow(issues) }
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
        // (No `.task` here: with nothing to show it made an empty, zero-height row — a hairline under the switch.
        // Settings refreshes the health on appear.)
    }

    private func statusRow(_ issues: [NotificationHealth.Issue]) -> some View {
        let (title, subtitle): (String, String) = {
            if health.authorization == .notDetermined { return ("Notifications aren’t allowed yet", "Allow them so shukr can remind you") }
            switch issues.first {
            case .off: return ("Notifications are off", "Off for shukr in iOS Settings")
            case .held: return ("Notifications may arrive late", "Held for the Scheduled Summary")
            case .timeSensitiveOff: return ("Notifications are on", "Time Sensitive is off: Focus may hold them")
            case .backgroundRefreshOff: return ("Notifications are on", "Background refresh is off: open shukr every few days")
            case nil:
                let through = health.scheduledThrough.map { " · scheduled through " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
                return ("Notifications are on", "On time" + through)
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

/// Settings → Reminders, under the tiles (decision reminders-status-row B): the way into Your Notifications, the next one
/// on the right — as Card Appearance sits on the Live Activities side.
struct YourNotificationsRow: View {
    @ObservedObject private var health = NotificationHealth.shared

    var body: some View {
        NavigationLink {
            YourRemindersView()
        } label: {
            HStack {
                Label {
                    Text("Your Notifications")
                } icon: {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if let next = health.nextAt {
                    Text("Next \(Self.when(next))").foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    /// "4:53 PM" today, else "Mon 4:53 PM".
    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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
    @State private var whyGlass: ReminderWhy?
    /// Opened from Settings with something wrong: that explanation's sheet comes up over the page, once.
    var openWith: ReminderWhy? = nil
    @State private var openedWith = false
    /// Each prayer's reminder setting, the same keys as Settings → Notifications (owner, reminders-runway: "put the start
    /// nudge off matrix thing in this page so they can toggle and see how it changes their runway").
    @AppStorage("fajrNotif") private var fajrNotif = NotificationDefaults.notify("Fajr")
    @AppStorage("dhuhrNotif") private var dhuhrNotif = NotificationDefaults.notify("Dhuhr")
    @AppStorage("asrNotif") private var asrNotif = NotificationDefaults.notify("Asr")
    @AppStorage("maghribNotif") private var maghribNotif = NotificationDefaults.notify("Maghrib")
    @AppStorage("ishaNotif") private var ishaNotif = NotificationDefaults.notify("Isha")
    @AppStorage("fajrNudges") private var fajrNudges = NotificationDefaults.nudges("Fajr")
    @AppStorage("dhuhrNudges") private var dhuhrNudges = NotificationDefaults.nudges("Dhuhr")
    @AppStorage("asrNudges") private var asrNudges = NotificationDefaults.nudges("Asr")
    @AppStorage("maghribNudges") private var maghribNudges = NotificationDefaults.nudges("Maghrib")
    @AppStorage("ishaNudges") private var ishaNudges = NotificationDefaults.nudges("Isha")
    private var settingsKey: [Bool] {
        [fajrNotif, dhuhrNotif, asrNotif, maghribNotif, ishaNotif, fajrNudges, dhuhrNudges, asrNudges, maghribNudges, ishaNudges]
    }

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
        // Whole weeks, this week's first day on (past days and days with nothing planned greyed).
        let days = calendarDays
        let day = Calendar.current.date(byAdding: .day, value: selectedDay, to: PrayerDay.date()) ?? PrayerDay.date()
        let dayItems = items(on: day).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let isToday = selectedDay == 0
        // Every prayer the day still has: scheduled ones, ones off in his settings, and (later days) ones not planned yet.
        let prayers = PrayerNotificationID.prayers.filter { p in
            dayItems.contains { $0.prayer == p && Self.prayerKinds.contains($0.kind) } || !isToday
        }
        // Everything else the day has (zikr reminders, a masjid dua, the "open shukr" reminder) in the same list, in time
        // order with the prayers (owner: "move the zikr reminders into the list of notifs showing for the day").
        let others = dayItems.filter { !Self.prayerKinds.contains($0.kind) }
        let rows = dayRows(prayers: prayers, others: others, dayItems: dayItems, day: day)
        return List {
            Section {
                // The status and Notification settings in one row (owner): the settings row's shield, the status's words,
                // a tap opens Notification settings.
                statusRow
                // The bar opens every scheduled reminder (owner: its own chevron; the "All N scheduled" row is gone).
                NavigationLink { allScheduled } label: { usageBar }
                // Why the bar stops at 64 and how it tops itself up, right under it (owner).
                whyRow(.budget)
                whyRow(.topsUp)
            }

            // (The per-prayer bells live in Settings only — owner: "we don't need it there".)

            // One card (owner): the weeks, then the picked day's name and its total as the card's own row, then its
            // prayers.
            Section {
                ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { start in
                    weekStrip(days, from: start)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(dayTitle(PrayerNotificationID.dayKey(day)))
                            .font(.system(.headline, design: .rounded))
                        Spacer()
                        Text("\(dayItems.count) notification\(dayItems.count == 1 ? "" : "s")")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    // Full day, or starts only for now (owner), under the day's name.
                    dayFullness(prayers: prayers, dayItems: dayItems, dayKey: PrayerNotificationID.dayKey(day))
                }
                .padding(.top, 6)
                .contentTransition(.opacity)
                if rows.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    switch row.kind {
                    case .prayer(let name):
                        // A prayer switched off sends nothing: not listed (owner).
                        if NotificationScheduler.settings(name).notify {
                            prayerRow(name, dayItems, dayKey: PrayerNotificationID.dayKey(day))
                        }
                    case .other(let item): otherRow(item)
                    }
                }
            } header: { Text("Days ahead") }

        }
        .reminderPageTitle("Your Notifications")
        .refreshable { await load() }
        // A bell changed: the plan is redone (prayerCol re-fetches), then the page reads it again.
        .onChange(of: settingsKey) { _, _ in
            Task {
                try? await Task.sleep(for: .seconds(1))
                await load()
                await health.refresh()
            }
        }
        .task {
            await load()
            if let openWith, !openedWith {
                openedWith = true
                open(openWith)
            }
            #if DEBUG
            if let n = UserDefaults.standard.string(forKey: "remindersSheet").flatMap(Int.init),
               let kind = ReminderWhy(rawValue: n) { open(kind) }
            #endif
        }
        .sheet(item: $previewCard) { issue in
            ReminderHealthCard(issue: issue) { previewCard = nil }
        }
        // Pushed, not a sheet (owner) — Notification settings.
        .navigationDestination(item: $whySheet) { ReminderWhySheet(kind: $0, pendingCount: pending.count) }
        // Why only 64? / Tops itself up: a sheet over the page in glass (owner).
        // Why only 64? / Tops itself up: the app's floating ⓘ card (owner: "use the tooltip modal … just no sheets").
        .infoModal(isPresented: Binding(get: { whyGlass == .budget }, set: { if !$0 { whyGlass = nil } }),
                   title: ReminderWhy.budget.title, symbol: ReminderWhy.budget.symbol(health)) {
            ReminderWhyInfo(kind: .budget, pendingCount: pending.count)
        }
        .infoModal(isPresented: Binding(get: { whyGlass == .topsUp }, set: { if !$0 { whyGlass = nil } }),
                   title: ReminderWhy.topsUp.title, symbol: ReminderWhy.topsUp.symbol(health)) {
            ReminderWhyInfo(kind: .topsUp, pendingCount: pending.count)
        }
    }

    private static let prayerKinds: [Kind] = [.start, .halfway, .endingSoon, .snooze]

    /// Notifications are on / off / need a hand, how far ahead they're planned, and the way into Notification settings
    /// (merged, owner): the shield is green with a check when his iOS settings let them through, orange when not.
    private var statusRow: some View {
        let off = health.authorization == .denied
        let bad = ReminderWhy.onTime.needsHand(health)
        let title = off ? "Notifications are off" : fine ? "Notifications are on" : "Notifications need a hand"
        let through = health.scheduledThrough ?? pending.compactMap(\.date).max()
        let subtitle = off ? "Off for shukr in iOS Settings"
            : fine ? "On time" + (through.map { d in
                // The runway in days (owner, reminders-runway): it grows when fewer reminders a day are scheduled; and
                // how far the full days go (plan v2: "full reminders through Wed · starts through Sun").
                let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                            to: Calendar.current.startOfDay(for: d)).day ?? 0) + 1
                let fullThrough = pending.filter { $0.kind == .halfway || $0.kind == .endingSoon }.compactMap(\.date).max()
                let full = fullThrough.map { " · full reminders through " + $0.formatted(.dateTime.weekday(.abbreviated)) } ?? ""
                return full + " · scheduled through " + d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " (\(days) days)"
            } ?? "")
            : "Tap to see what's in the way"
        return ReminderPageStatus(good: !(bad || !fine), title: title, subtitle: subtitle,
                                  note: bad ? "Needs a look" : nil) { whySheet = .onTime }
    }

    /// One colour: used in green, free in grey; the numbers in words.
    /// One of the "why" rows: its symbol, title, and a look-at-it note when it needs one; opens its explanation.
    /// Why only 64? and Tops itself up rise as glass sheets (owner); Notification settings is still pushed.
    private func open(_ kind: ReminderWhy) {
        if kind == .budget || kind == .topsUp { whyGlass = kind } else { whySheet = kind }
    }

    private func whyRow(_ kind: ReminderWhy) -> some View {
        let bad = kind.needsHand(health)
        return ReminderWhyLink(symbol: kind.symbol(health), title: kind.title, needsLook: bad,
                               tint: kind == .onTime ? green : Color(.secondaryLabel),
                               trailing: kind == .onTime ? "All set" : nil) { open(kind) }
    }

    /// The 64 in parts (owner: show "that we have set aside some of that space"): prayer reminders, zikr reminders,
    /// reminders to open shukr, anything else (snoozes), the slots kept for snoozes, and what's free.
    private var usageBar: some View {
        let limit = NotificationScheduler.limit
        func n(_ kinds: [Kind]) -> Int { pending.filter { kinds.contains($0.kind) }.count }
        let prayers = n([.start, .halfway, .endingSoon])
        let zikr = n([.zikr, .zikrLater])
        let open = n([.keepAlive])
        let other = n([.snooze, .masjid, .other])
        let used = min(prayers + zikr + open + other, limit)
        let kept = min(NotificationScheduler.spare, limit - used)
        let free = max(limit - used - kept, 0)
        return ReminderSlotsBar(
            caption: "\(used) of \(limit) in use · \(kept) kept for snoozes" + (free > 0 ? " · \(free) free" : ""),
            limit: limit,
            parts: [
                .init(count: prayers, color: green, label: "Prayers"), .init(count: zikr, color: Color(.systemTeal), label: "Zikr"),
                .init(count: open, color: Color(.systemOrange), label: "Open shukr"),
                .init(count: other, color: Color(.systemIndigo), label: "Other"),
                .init(count: kept, color: Color(.systemGray3), label: "Kept for snoozes"),
            ])
    }

    /// The Calendar's week: the picked day filled green, today's number green; a grey dot under days with nudges.
    /// The days grid (owner: "always show 7 days in days ahead. show today, and gray out past or future days that dont
    /// have notifs"): whole calendar weeks, from this week's first day through the week of the last planned day.
    private var calendarDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: PrayerDay.date())
        let first = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let last = cal.startOfDay(for: weekDays.last ?? today)
        let end = cal.dateInterval(of: .weekOfYear, for: last)?.end ?? cal.date(byAdding: .day, value: 7, to: first) ?? today
        var days: [Date] = []
        var d = first
        while d < end, days.count < 21 {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end
        }
        return days
    }

    /// Days from today (0 = today; negative = earlier this week).
    private func offset(_ d: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: PrayerDay.date()), to: cal.startOfDay(for: d)).day ?? 0
    }

    /// One week of the grid: the picked day filled green, today's number green; past days and days with nothing planned
    /// in grey (they can't be picked); a grey dot under days with nudges.
    private func weekStrip(_ days: [Date], from start: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(start..<min(start + 7, days.count), id: \.self) { i in
                let d = days[i]
                let off = offset(d)
                let dayItems = off < 0 ? [] : items(on: d)
                let enabled = off == 0 || (off > 0 && !dayItems.isEmpty)
                let picked = off == selectedDay
                let nudged = dayItems.contains { $0.kind == .halfway || $0.kind == .endingSoon }
                Button {
                    triggerSomeVibration(type: .light)
                    selectedDay = off
                } label: {
                    VStack(spacing: 6) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                            .foregroundStyle(enabled ? Color(.secondaryLabel) : Color(.tertiaryLabel))
                        Text(d.formatted(.dateTime.day()))
                            .foregroundStyle(picked ? Color.white : off == 0 ? green : enabled ? Color(.label) : Color(.tertiaryLabel))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(picked ? green : .clear))
                        // Under the number: a filled dot for a full day, an empty ring for a starts-only one (owner) — the
                        // same reading as the line under the picked day (`startsOnly`).
                        let planned = dayItems.contains { Self.prayerKinds.contains($0.kind) }
                        let startsOnly = planned && !Self.isFull(dayItems, day: d)   // not full: the empty ring
                        ZStack {
                            Circle().fill(Color(.tertiaryLabel)).opacity(planned && !startsOnly ? 1 : 0)
                            Circle().stroke(Color(.tertiaryLabel), lineWidth: 1).opacity(startsOnly ? 1 : 0)
                        }
                        .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
            }
        }
        .padding(.vertical, 2)
    }

    /// One row per prayer, and how the day compares with his setting (owner, reminders-runway: "shows us how it compares
    /// to our set preferences … that way us acknowledging it … shows user that its intended"): every reminder it has with
    /// its time ("Start 1:07 · Halfway 2:41 · 30 min left 3:46"), then why it's that — start only as he set it, nudges
    /// still to come on a later day, off in his settings, or not planned yet (past the runway).
    private func prayerRow(_ prayer: String, _ dayItems: [Item], dayKey: String) -> some View {
        let mine = dayItems.filter { $0.prayer == prayer && Self.prayerKinds.contains($0.kind) }
        let setting = NotificationScheduler.settings(prayer)
        let hasNudges = mine.contains { $0.kind == .halfway || $0.kind == .endingSoon }
        let parts = mine.map { item -> String in
            let label = switch item.kind {
            case .start: "Start"
            case .halfway: "Halfway"
            case .endingSoon: "30 min left"
            default: "Later"
            }
            return "\(label) \(Self.hm(item.date))"
        }
        let note: String? = {
            if !setting.notify { return "Off in your settings" }
            if mine.isEmpty { return "Not planned yet — added as the day comes closer" }
            if !setting.nudges { return "Start only, as you set" }
            if !hasNudges { return "Nudges added \(nudgesAddedOn(dayKey) ?? "closer to the day")" }
            return nil
        }()
        let line = ([parts.joined(separator: " · ")] + [note].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · ")
        let quiet = !setting.notify || mine.isEmpty
        return HStack(spacing: 12) {
            Image(systemName: prayerSymbol(prayer)).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(prayer).foregroundStyle(quiet ? Color.secondary : Color.primary)
                Text(line).font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 3) {
                Text("\(mine.count)").monospacedDigit()
                Image(systemName: mine.isEmpty ? "bell.slash" : "bell").font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(mine.count) reminder\(mine.count == 1 ? "" : "s")")
        }
    }

    /// A row of the day's list: a prayer (with all its reminders) or one other reminder; ordered by time.
    private struct DayRow: Identifiable {
        enum Kind { case prayer(String), other(Item) }
        let id: String
        let kind: Kind
        let at: Date
    }

    private func dayRows(prayers: [String], others: [Item], dayItems: [Item], day: Date) -> [DayRow] {
        let windows = NotificationScheduler.windows(for: day)
        var rows: [DayRow] = prayers.enumerated().map { i, name in
            // A prayer sits at its start: its scheduled start, else today's window, else its place in the day.
            let start = dayItems.first { $0.prayer == name && $0.kind == .start }?.date
                ?? windows?[name]?.start
                ?? Calendar.current.startOfDay(for: day).addingTimeInterval(Double(i + 1) * 3 * 3600)
            return DayRow(id: "p." + name, kind: .prayer(name), at: start)
        }
        rows += others.map { DayRow(id: $0.id, kind: .other($0), at: $0.date ?? .distantFuture) }
        return rows.sorted { $0.at < $1.at }
    }

    /// Any other reminder, in the prayer rows' shape: what it is, its time in the grey line, the count on the right.
    private func otherRow(_ item: Item) -> some View {
        let (symbol, title, what): (String, String, String) = switch item.kind {
        case .zikr, .zikrLater: ("circle.dotted.circle", item.title.isEmpty ? "Zikr reminder" : item.title, "Zikr reminder")
        case .masjid: ("building.columns", item.title.isEmpty ? "Masjid dua" : item.title, "Masjid dua")
        // Plan v2's three warnings, each saying what it is.
        case .keepAlive where item.id.hasPrefix(NotificationScheduler.headsUpPrefix):
            ("calendar.badge.exclamationmark", "Heads-up", "Your reminders run out in 2 days")
        case .keepAlive where item.id.hasPrefix(NotificationScheduler.easeOffPrefix):
            ("bell.badge", "Easing off", "Just the starts from the next day")
        case .keepAlive: ("arrow.clockwise.circle", "Open shukr", "The last reminder before they run out")
        default: ("bell", line(for: item), "Reminder")
        }
        return HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(what) \(Self.hm(item.date))").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Text("1").monospacedDigit()
                Image(systemName: "bell").font(.caption)
            }
            .foregroundStyle(.secondary)
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
        return (0...max(6, min(span, NotificationScheduler.maxDaysAhead + 1))).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
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
        case .keepAlive: item.id.hasPrefix(NotificationScheduler.headsUpPrefix) ? "Heads-up: reminders run out in 2 days"
            : item.id.hasPrefix(NotificationScheduler.easeOffPrefix) ? "Easing off to just the starts"
            : "Reminder to open shukr"
        case .other: item.title.isEmpty ? "Reminder" : item.title
        }
    }

    /// A starts-only day's nudges are planned once it's within `nudgeDaysAhead` prayer days — i.e.
    /// the day before it, when shukr re-plans (opening it, or iOS's background refresh).
    /// The picked day at a glance (owner: "whether that day is a full day, like it respects our settings properly, or …
    /// where we only show the starts"): read from what's scheduled — a prayer set to Nudge that has its start but no
    /// nudge yet makes it a starts-only day for now (NotificationScheduler adds nudges `nudgeDaysAhead` days out).
    /// A prayer set to Nudge has its start that day but no nudge yet.
    /// The day has everything its settings ask for (owner: the dots must say full vs not). Plan v2 adds nudges to later
    /// days only while slots are free, so a day can be partly full: some nudges, not all. For each prayer that's on: every
    /// notification it would send that's still ahead must be there — its start, and on Nudge its halfway (windows of 90
    /// min+) and 30 minutes left. A prayer with nothing today was prayed or has passed.
    private static func isFull(_ dayItems: [Item], day: Date) -> Bool {
        guard let windows = NotificationScheduler.windows(for: day) else { return true }
        let now = Date()
        let isToday = Calendar.current.isDate(day, inSameDayAs: PrayerDay.date())
        for p in PrayerNotificationID.prayers {
            let setting = NotificationScheduler.settings(p)
            guard setting.notify, let w = windows[p] else { continue }
            let mine = dayItems.filter { $0.prayer == p }
            if mine.isEmpty && isToday { continue }
            var wanted: [(Kind, String)] = [(.start, "Start")]
            if setting.nudges {
                if w.window >= NotificationScheduler.halfwayMinimumWindow { wanted.append((.halfway, "Mid")) }
                wanted.append((.endingSoon, "End"))
            }
            for (kind, name) in wanted {
                guard let (at, _) = NotificationScheduler.prayerNotification(name, prayer: p, window: w), at > now else { continue }
                if !mine.contains(where: { $0.kind == kind }) { return false }
            }
        }
        return true
    }

    @ViewBuilder private func dayFullness(prayers: [String], dayItems: [Item], dayKey: String) -> some View {
        let planned = dayItems.contains { Self.prayerKinds.contains($0.kind) }
        let startsOnly = Self.dayKeyFormatter.date(from: dayKey).map { !Self.isFull(dayItems, day: $0) } ?? false
        if planned {
            HStack(spacing: 6) {
                Image(systemName: startsOnly ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(startsOnly ? Color.secondary : green)
                Text(startsOnly ? "Not every nudge yet · added \(nudgesAddedOn(dayKey) ?? "closer to the day")"
                                : "Full day · everything you set")
                    .foregroundStyle(startsOnly ? Color.secondary : Color.primary)
            }
            .font(.system(.subheadline, design: .rounded))
            .contentTransition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private func nudgesAddedOn(_ key: String) -> String? {
        guard let day = Self.dayKeyFormatter.date(from: key),
              let before = Calendar.current.date(byAdding: .day, value: -(NotificationScheduler.nudgeDaysAhead - 1), to: day)
        else { return nil }
        let today = PrayerDay.date()
        if PrayerNotificationID.dayKey(before) == PrayerNotificationID.dayKey(today) { return "later today" }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today),
           PrayerNotificationID.dayKey(before) == PrayerNotificationID.dayKey(tomorrow) { return "by tomorrow" }
        // The date, not the weekday (owner: "Nudges added 22nd"). "By": the 3 sure days are a floor — opening shukr
        // often brings full days sooner (plan v2's runway).
        return "by the " + (Self.ordinal.string(from: NSNumber(value: Calendar.current.component(.day, from: before))) ?? "")
    }
    private static let ordinal: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .ordinal; return f }()

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
        _ = (today, tomorrow)
        // The calendar day (owner): "Sun, Oct 11".
        return Self.dayKeyFormatter.date(from: key).map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? key
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
            // The real plan when the store is there (plan v2's checks), else the stand-in week.
            if let container = NotificationScheduler.appContainer {
                let budget = NotificationScheduler.limit - NotificationScheduler.spare
                pending = NotificationScheduler.choose(NotificationScheduler.plan(context: container.mainContext), budget: budget)
                    .filter { Self.shown($0.id) }.map { item(id: $0.id, date: $0.date, content: $0.content) }
                    .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            } else {
                pending = Self.sampleItems()
            }
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
