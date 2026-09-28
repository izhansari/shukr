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
    /// The open cell per day card (day key → "Fajr" … "Zikr" / "Snoozed"); one at a time per card.
    @State private var open: [String: String] = {
        // DEBUG `-upcomingOpen Maghrib`: today's card opens on it (screenshots).
        // `-upcomingOpenDay N`: N days after today instead.
        guard let cell = UserDefaults.standard.string(forKey: "upcomingOpen") else { return [:] }
        let offset = UserDefaults.standard.integer(forKey: "upcomingOpenDay")
        let day = Calendar.current.date(byAdding: .day, value: offset, to: PrayerDay.date()) ?? PrayerDay.date()
        return [PrayerNotificationID.dayKey(day): cell]
    }()

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

    /// The icon cells of a day card: the five prayers, Zikr, and Snoozed when there are any.
    private static let cellNames = PrayerNotificationID.prayers + ["Zikr"]
    private static func cell(of item: Item) -> String {
        switch item.kind {
        case .start, .halfway, .endingSoon: item.prayer ?? "Snoozed"
        case .zikr, .zikrLater: "Zikr"
        case .snooze, .other: "Snoozed"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                if loaded && pending.isEmpty && deliveredToday.isEmpty {
                    card {
                        Text(health.authorization == .denied
                             ? "Notifications are off for shukr, so nothing is scheduled."
                             : PrayerNotificationID.prayers.allSatisfy({ !NotificationScheduler.settings($0).notify })
                             ? "Prayer reminders are off in Settings → Notifications."
                             : "Nothing is scheduled right now. Open shukr and it tops them up.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(Array(days.enumerated()), id: \.element.key) { index, day in
                    dayCard(day.key, items: day.items, note: index == firstStartsOnlyIndex ? startsOnlyNote : nil)
                }
                detailsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// The ring (how many of iOS's 64 are waiting), how far they reach, the one thing to know, and
    /// what they're made of (owner: educate, be transparent, keep it simple).
    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color(.secondarySystemFill), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: min(Double(pending.count) / 64, 1))
                            .stroke(Color.sage, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -2) {
                            Text("\(pending.count)").font(.system(size: 22, weight: .light, design: .rounded)).monospacedDigit()
                            Text("of 64").font(.system(size: 10, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coverText)
                            .font(.system(.headline, design: .rounded, weight: .medium))
                        Text(explainer)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(breakdown, id: \.label) { part in
                        VStack(spacing: 1) {
                            Text("\(part.count)")
                                .font(.system(.title3, design: .rounded, weight: .medium))
                                .monospacedDigit()
                            Text(part.label)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGroupedBackground)))
                    }
                }
            }
        }
    }

    /// iOS's limit, what shukr does with it (from the scheduler's own rule) and what to do.
    private var explainer: String {
        let n = NotificationScheduler.nudgeDaysAhead
        let days = n == 2 ? "two" : "\(n)"
        return "iOS keeps 64 reminders at a time, so shukr schedules every start for the week and your nudges for the next \(days) days. Open shukr every few days to roll them forward."
    }

    /// Starts · Halfway · 30 min left · Zikr, and Snoozed only when there are some.
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

    /// The first day (after today) that only has starts though some prayer is set to nudge: the
    /// scheduler's rule, seen on the page.
    private var firstStartsOnlyIndex: Int? {
        let anyNudges = PrayerNotificationID.prayers.contains { NotificationScheduler.settings($0).nudges && NotificationScheduler.settings($0).notify }
        guard anyNudges else { return nil }
        let days = self.days      // computed: group once
        return days.indices.first { i in
            i >= 1 && !days[i].items.contains { $0.kind == .halfway || $0.kind == .endingSoon }
                && days[i].items.contains { $0.kind == .start }
        }
    }
    private var startsOnlyNote: String {
        let n = NotificationScheduler.nudgeDaysAhead
        return "Starts only from here · nudges are added \(n == 2 ? "two" : "\(n)") days ahead"
    }

    /// A day: title, date, its total; the icon cells with counts; tap one to see what's in it.
    private func dayCard(_ key: String, items: [Item], note: String?) -> some View {
        let isToday = key == PrayerNotificationID.dayKey(PrayerDay.date())
        let delivered = isToday ? deliveredToday : []
        let hasSnoozed = items.contains { Self.cell(of: $0) == "Snoozed" } || delivered.contains { Self.cell(of: $0) == "Snoozed" }
        let names = Self.cellNames + (hasSnoozed ? ["Snoozed"] : [])
        let selected = open[key]
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle(key)).font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Text(daySub(key)).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                    Text("\(items.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.sage)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 28, minHeight: 24)
                        .background(Capsule().fill(Color.sage.opacity(0.15)))
                }
                if let note {
                    Text(note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        let count = items.filter { Self.cell(of: $0) == name }.count
                        let any = count > 0 || delivered.contains { Self.cell(of: $0) == name }
                        iconCell(name, count: count, dimmed: !any, selected: selected == name)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard any else { return }
                                triggerSomeVibration(type: .light)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    open[key] = selected == name ? nil : name
                                }
                            }
                    }
                }
                if let selected {
                    reveal(selected, key: key, items: items.filter { Self.cell(of: $0) == selected },
                           delivered: delivered.filter { Self.cell(of: $0) == selected })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if isToday, let next = items.first(where: { ($0.date ?? .distantPast) > Date() }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                        (Text("Next: ").foregroundStyle(.secondary)
                         + Text("\(Self.cell(of: next) == "Zikr" ? (next.title.isEmpty ? "Zikr" : next.title) : (next.prayer ?? "Reminder")) \(next.kind == .start ? "starts" : next.kind.label) \(time(next))").fontWeight(.medium))
                            .font(.system(.footnote, design: .rounded))
                    }
                }
            }
        }
    }

    private func iconCell(_ name: String, count: Int, dimmed: Bool, selected: Bool) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: cellSymbol(name))
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(dimmed ? Color.secondary : Color.sage)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(dimmed ? Color(.systemGroupedBackground) : Color.sage.opacity(selected ? 0.26 : 0.12)))
                    .overlay(Circle().strokeBorder(Color.sage, lineWidth: selected ? 1.5 : 0))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Color.sage))
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: 5, y: -4)
                }
            }
            Text(name)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .opacity(dimmed ? 0.4 : 1)
    }

    private func cellSymbol(_ name: String) -> String {
        switch name {
        case "Zikr": return "circle.hexagonpath"
        case "Snoozed": return "clock.arrow.circlepath"
        default: return prayerSymbol(name)
        }
    }

    /// What one cell holds: each notification with what it is and when; delivered ones greyed; on a
    /// starts-only day, when the nudges will be added.
    private func reveal(_ cell: String, key: String, items: [Item], delivered: [Item]) -> some View {
        let settings = PrayerNotificationID.prayers.contains(cell) ? NotificationScheduler.settings(cell) : nil
        let startsOnly = settings?.nudges == true && settings?.notify == true
            && !items.isEmpty && !items.contains { $0.kind == .halfway || $0.kind == .endingSoon }
            && key != PrayerNotificationID.dayKey(PrayerDay.date())
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(delivered.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) { revealRow($0, cell: cell, delivered: true) }
            ForEach(items) { revealRow($0, cell: cell, delivered: false) }
            if startsOnly, let added = nudgesAddedOn(key) {
                Text("Halfway and 30-min nudges are added \(added)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGroupedBackground)))
    }

    private func revealRow(_ item: Item, cell: String, delivered: Bool) -> some View {
        let what: String = {
            switch item.kind {
            case .zikr, .zikrLater: item.title.isEmpty ? "reminder" : item.title
            case .start, .halfway, .endingSoon: item.kind.label
            default: "nudge"
            }
        }()
        return HStack {
            Text("\(cell) · \(what)")
                .font(.system(.subheadline, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(delivered ? "delivered \(time(item))" : time(item))
                .font(.system(.subheadline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .opacity(delivered ? 0.45 : 1)
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
        return "on " + before.formatted(.dateTime.weekday(.abbreviated))
    }

    private func time(_ item: Item) -> String {
        item.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–"
    }

    private func daySub(_ key: String) -> String {
        guard let d = Self.dayKeyFormatter.date(from: key) else { return "" }
        let title = dayTitle(key)
        return title == "Today" || title == "Tomorrow"
            ? d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : d.formatted(.dateTime.month(.abbreviated).day())
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
                    if betaAccess.available {
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
                .font(.subheadline)
                .padding(.top, 10)
            } label: {
                Text("Details").font(.subheadline).foregroundStyle(.secondary)
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

    private var days: [(key: String, items: [Item])] {
        var byDay = Dictionary(grouping: pending, by: \.dayKey)
        // Today stays as a card while it has delivered ones, even with nothing left to come.
        if !deliveredToday.isEmpty { byDay[PrayerNotificationID.dayKey(PrayerDay.date()), default: []] += [] }
        return byDay.map { (key: $0.key, items: $0.value) }.sorted { $0.key < $1.key }
    }

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
