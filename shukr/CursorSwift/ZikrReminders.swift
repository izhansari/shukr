//
//  ZikrReminders.swift
//  shukr
//
//  Zikr task reminders (2026-09-27, notes #11 — all decided by the owner):
//  - Only reminders the user sets, one per task, off by default: a clock time, or N minutes before
//    / after a prayer (the Fajr alarm's pickers), on chosen weekdays (`TaskModel.reminder…`).
//  - One-shot notifications per day, a week ahead, through `NotificationScheduler` (shared
//    64-slot budget; ids "zikr.<task uuid>.<prayer day>", owned by the scheduler).
//  - Not on days the task is already done: finishing it removes that day's pending one
//    (`taskMaybeDone`), and the plan skips it.
//  - Actions: Start now (opens that task, like the Zikr widget's rows), Later (30 min). ("Skip
//    today" was dropped, 2026-09-27 review.)
//  - Every task delete goes through `TaskModel.delete(_:in:)`, which reschedules so its reminders
//    go (a deleted task's "Start now" pointed at nothing).
//

import Foundation
import UserNotifications
import SwiftData

enum ZikrReminders {
    static let category = "ZikrReminder"
    static let startAction = "ZIKR_START_ACTION"
    static let laterAction = "ZIKR_LATER_ACTION"
    /// Posted when a reminder asks to open its task while the app is running (object: task id).
    static let openTask = Notification.Name("zikrReminderOpenTask")

    static let prefix = "zikr."
    static let laterPrefix = "zikrlater."
    static func id(task: UUID, day: Date) -> String { "\(prefix)\(task.uuidString).\(PrayerNotificationID.dayKey(day))" }
    static func owns(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// A delivered reminder from an earlier prayer day (cleared like the prayer ones).
    static func isStaleDelivered(_ id: String, todayKey: String, dayStart: Date) -> Bool {
        if id.hasPrefix(prefix) { return String(id.suffix(10)) < todayKey }
        if id.hasPrefix(laterPrefix), let ts = Double(id.split(separator: ".").last ?? "") {
            return Date(timeIntervalSince1970: ts) < dayStart
        }
        return false
    }

    static func registerCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: startAction, title: "Start now", options: [.foreground]),
                UNNotificationAction(identifier: laterAction, title: "Later (30 min)", options: []),
            ],
            intentIdentifiers: [], options: [])
    }

    // MARK: Describing a reminder

    static let prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    /// "8:00 PM · every day", "20 min after Fajr · Mon, Wed" — nil when off.
    static func summary(_ task: TaskModel) -> String? {
        guard let kind = task.reminderKind else { return nil }
        let when: String
        if kind == "prayer", let prayer = task.reminderPrayer {
            let m = task.reminderOffsetMinutes ?? 0
            when = m == 0 ? "at \(prayer)" : "\(abs(m)) min \(m < 0 ? "before" : "after") \(prayer)"
        } else {
            when = clockString(task.reminderTimeMinutes ?? 20 * 60)
        }
        return "\(when) · \(weekdaysString(task.reminderWeekdays))"
    }
    static func clockString(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return shortTimePM(date)
    }
    static func weekdaysString(_ mask: Int?) -> String {
        guard let mask, mask != 0b111_1111 else { return "every day" }
        if mask == 0b011_1110 { return "weekdays" }
        if mask == 0b100_0001 { return "weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        let on = (0..<7).filter { mask & (1 << $0) != 0 }
        if on.count >= 5 {   // "every day but Sat" reads shorter than six names
            return "every day but " + (0..<7).filter { !on.contains($0) }.map { symbols[$0] }.joined(separator: ", ")
        }
        return on.map { symbols[$0] }.joined(separator: ", ")
    }

    // MARK: Planning (NotificationScheduler)

    /// Today's (prayer-day) sessions, for "already done today".
    static func todaysSessions(_ context: ModelContext) -> [SessionDataModel] {
        let start = PrayerDay.sessionDayStart()
        return (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= start }))) ?? []
    }

    static func items(context: ModelContext, now: Date = Date(), horizon: Date,
                      prayerStart: (String, Date) -> Date?) -> [NotificationScheduler.Item] {
        let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.reminderKind != nil }))) ?? []
        guard !tasks.isEmpty else { return [] }
        let sessions = todaysSessions(context)
        let todayKey = PrayerNotificationID.dayKey(PrayerDay.date(for: now))
        var items: [NotificationScheduler.Item] = []
        if (try? PrayerUtils.getUserCoordinates()) == nil, tasks.contains(where: { $0.reminderKind == "prayer" }) {
            print("⚠️ zikr reminders: no saved location yet — prayer-based reminders skipped until there is one")
        }
        for task in tasks {
            let doneToday = task.isCompleted(with: task.progress(in: sessions))
            // Today's reminder only goes off with the task not done, so its streak is the one still to keep.
            // A later day's isn't known yet (today may be missed): no streak line until that day's
            // reschedule writes it (the diff re-adds a request whose text changed).
            let streak = task.streak(now: now).current
            for fire in fires(task, now: now, horizon: horizon, doneToday: doneToday, todayKey: todayKey, prayerStart: prayerStart) {
                let near = fire.timeIntervalSince(now) < 48 * 3600
                let isToday = PrayerNotificationID.dayKey(PrayerDay.date(for: fire)) == todayKey
                items.append(NotificationScheduler.Item(id: id(task: task.id, day: PrayerDay.date(for: fire)), date: fire,
                                                        priority: near ? 1 : 3,
                                                        content: content(for: task, streak: isToday ? streak : 0)))
            }
        }
        return items
    }

    /// When a task's reminder goes off in the next week (the one rule for the scheduler and the
    /// reminders page): its days, its clock time or prayer ± offset, and not today once the task is
    /// done today.
    static func fires(_ task: TaskModel, now: Date, horizon: Date, doneToday: Bool, todayKey: String,
                      prayerStart: (String, Date) -> Date?) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let weekdayBit = 1 << (cal.component(.weekday, from: day) - 1)
            if let mask = task.reminderWeekdays, mask & weekdayBit == 0 { continue }
            let fire: Date?
            if task.reminderKind == "prayer", let prayer = task.reminderPrayer {
                fire = prayerStart(prayer, day)?.addingTimeInterval(TimeInterval((task.reminderOffsetMinutes ?? 0) * 60))
            } else {
                let m = task.reminderTimeMinutes ?? 20 * 60
                fire = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day)
            }
            guard let fire, fire > now, fire < horizon else { continue }
            if doneToday, PrayerNotificationID.dayKey(PrayerDay.date(for: fire)) == todayKey { continue }
            dates.append(fire)
        }
        return dates
    }

    /// The next time a task's reminder goes off (nil: off, or nothing in the next week — e.g. a
    /// prayer reminder with no saved location).
    @MainActor static func nextFire(_ task: TaskModel, sessions: [SessionDataModel], now: Date = Date()) -> Date? {
        guard task.reminderKind != nil else { return nil }
        let doneToday = task.isCompleted(with: task.progress(in: sessions))
        let todayKey = PrayerNotificationID.dayKey(PrayerDay.date(for: now))
        return fires(task, now: now, horizon: now.addingTimeInterval(8 * 86_400), doneToday: doneToday, todayKey: todayKey) { prayer, day in
            NotificationScheduler.windows(for: day)?[prayer]?.start
        }.first
    }

    /// "After Fajr" / "Bismillah · 50 counts · ~3 min".
    /// `streak`: the days to keep (2 or more adds "🔥 Keep your 12-day streak" on its own line).
    static func content(for task: TaskModel, streak: Int = 0) -> UNNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = task.title
        let goal = task.isCountMode ? "\(task.goal) \(task.goal == 1 ? "count" : "counts")" : "\(task.goal) min"
        c.body = [task.mantraLine, goal, task.estimateNote(TaskProgress())].compactMap { $0 }.joined(separator: " · ")
            + (streak >= 2 ? "\n🔥 Keep your \(streak)-day streak" : "")
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = ["zikrTaskID": task.id.uuidString]
        return c
    }

    // MARK: Done / actions

    /// A session was saved for `task`: if that finished it for today, today's reminder goes.
    @MainActor static func taskMaybeDone(_ task: TaskModel, context: ModelContext) {
        guard task.reminderKind != nil, task.isCompleted(with: task.progress(in: todaysSessions(context))) else { return }
        removeToday(taskID: task.id.uuidString)
    }

    /// Today's pending reminder for the task, and any "later" one.
    static func removeToday(taskID: String) {
        let center = UNUserNotificationCenter.current()
        let todayID = "\(prefix)\(taskID).\(PrayerNotificationID.dayKey(PrayerDay.date()))"
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0 == todayID || $0.hasPrefix("\(laterPrefix)\(taskID).") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Open the task: the Zikr page with its circle in the middle (the widget rows' path —
    /// app-group flags read on activation — plus a post for when the app is already open).
    static func open(taskID: String) {
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        store?.set(taskID, forKey: "widgetZikrTask")
        store?.set(true, forKey: "widgetTasbeeh")
        NotificationCenter.default.post(name: openTask, object: taskID)
    }

    /// "Later (30 min)": the same reminder again, once.
    static func later(_ original: UNNotificationContent, taskID: String, then done: @escaping () -> Void) {
        let request = UNNotificationRequest(
            identifier: "\(laterPrefix)\(taskID).\(Int(Date().timeIntervalSince1970))",
            content: original,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false))
        UNUserNotificationCenter.current().add(request) { _ in done() }
    }
}

// MARK: - Deleting a task

extension TaskModel {
    /// The one way to delete a task: its sessions stay in history (nullify), its reminders go.
    @MainActor static func delete(_ task: TaskModel, in context: ModelContext) {
        let ids = (uuids: Set([task.id]), models: Set([task.persistentModelID]))
        context.delete(task)
        try? context.save()
        NotificationScheduler.reschedule(context: context, reason: "task deleted")
        deleted(ids.uuids, models: ids.models)
    }

    /// Posted with the deleted tasks' ids, so nothing keeps pointing at them (the home screen's
    /// `selectedTask`, a pending `ZikrFocus`).
    static let didDelete = Notification.Name("tasksDeleted")
    /// `models` is what observers compare against (a deleted row's attributes can't be read).
    @MainActor static func deleted(_ ids: Set<UUID>, models: Set<PersistentIdentifier>) {
        guard !ids.isEmpty else { return }
        ZikrFocus.forget(ids.map(\.uuidString))
        NotificationCenter.default.post(name: didDelete, object: models)
    }
}

/// Deleting sessions (History's and a zikr page's Edit → Delete): task progress, the widget and
/// the reminders (a task that's no longer done today gets its reminder back) all follow.
enum SessionDeletion {
    @MainActor static func delete(_ sessions: [SessionDataModel], in context: ModelContext) {
        guard !sessions.isEmpty else { return }
        for session in sessions { context.delete(session) }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        NotificationScheduler.reschedule(context: context, reason: "sessions deleted")
    }
}

// MARK: - The picker

import SwiftUI
import WidgetKit

/// A task's reminder while it's being set (applied to the task on Save / on create).
struct ReminderDraft: Equatable {
    var kind: String? = nil            // nil = off, "time", "prayer"
    var timeMinutes = 20 * 60
    var prayer = "Fajr"
    var minutes = 10                   // 0…60, like the Fajr alarm
    var before = false
    var weekdays = 0b111_1111

    init() {}
    init(_ task: TaskModel) {
        kind = task.reminderKind
        timeMinutes = task.reminderTimeMinutes ?? 20 * 60
        prayer = task.reminderPrayer ?? "Fajr"
        let offset = task.reminderOffsetMinutes ?? 10
        minutes = min(abs(offset), 60)
        before = offset < 0
        weekdays = task.reminderWeekdays ?? 0b111_1111
    }
    func apply(to task: TaskModel) {
        task.reminderKind = kind
        task.reminderTimeMinutes = kind == "time" ? timeMinutes : nil
        task.reminderPrayer = kind == "prayer" ? prayer : nil
        task.reminderOffsetMinutes = kind == "prayer" ? (before ? -minutes : minutes) : nil
        task.reminderWeekdays = kind == nil || weekdays == 0b111_1111 ? nil : weekdays
    }
    /// For the row: "20 min after Fajr · every day" / "Off".
    var summary: String {
        guard let kind else { return "Off" }
        let when = kind == "prayer"
            ? (minutes == 0 ? "at \(prayer)" : "\(minutes) min \(before ? "before" : "after") \(prayer)")
            : ZikrReminders.clockString(timeMinutes)
        return "\(when) · \(ZikrReminders.weekdaysString(weekdays))"
    }
}

/// "Remind me": off, at a clock time, or around a prayer (the Fajr alarm's wheels), and which days.
struct TaskReminderSheet: View {
    @State private var draft: ReminderDraft
    let original: ReminderDraft
    /// Notifications allowed? nil = never asked. A reminder with them off would do nothing silently.
    @State private var permission: UNAuthorizationStatus?
    private var hasLocation: Bool { (try? PrayerUtils.getUserCoordinates()) != nil }
    var onCancel: () -> Void
    var onSave: (ReminderDraft) -> Void
    /// Inside another sheet (the new-task flow): no size or grabber of its own (they resized that sheet).
    var embedded = false

    init(draft: ReminderDraft, embedded: Bool = false, onCancel: @escaping () -> Void, onSave: @escaping (ReminderDraft) -> Void) {
        self.embedded = embedded
        _draft = State(initialValue: draft)
        original = draft
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: draft.timeMinutes / 60, minute: draft.timeMinutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            draft.timeMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
    private var kindPick: Binding<String> {
        Binding(get: { draft.kind ?? "off" }, set: { draft.kind = $0 == "off" ? nil : $0 })
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Remind me").font(.title3.weight(.semibold))
                Text("only on days it isn't done yet")
                    .font(.subheadline).fontWeight(.thin).foregroundStyle(.secondary)
            }
            .padding(.top, 26)

            Picker("", selection: kindPick) {
                Text("Off").tag("off")
                Text("At a time").tag("time")
                Text("Around a prayer").tag("prayer")
            }
            .pickerStyle(.segmented)

            Group {
                if draft.kind == "time" {
                    DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                } else if draft.kind == "prayer" {
                    // Same wheels as the Fajr alarm (Settings → Alarm).
                    HStack(spacing: 0) {
                        Picker("", selection: $draft.minutes) {
                            ForEach(0...60, id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Picker("", selection: $draft.before) {
                            Text("After").tag(false)
                            Text("Before").tag(true)
                        }
                        Picker("", selection: $draft.prayer) {
                            ForEach(ZikrReminders.prayers, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                } else {
                    Text("No reminder for this task.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .frame(height: 170)

            if draft.kind != nil {
                weekdayChips
                Text(draft.summary)
                    .font(.footnote).foregroundStyle(.secondary)
                notice
            }

            Spacer(minLength: 0)
            SaveCancelButtons(canSave: draft != original && draft.weekdays != 0, onCancel: onCancel) { onSave(draft) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .fontDesign(.rounded)
        .animation(.snappy, value: draft.kind)
        .task { await refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermission() }   // back from the Settings app
        }
        .modifier(SheetSizing(on: !embedded))
    }

    private struct SheetSizing: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            if on {
                content
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            } else {
                content
            }
        }
    }

    /// Why a reminder couldn't go out: notifications off / never asked, or no location for a
    /// prayer-based one (2026-09-27 review — both used to fail silently).
    @ViewBuilder private var notice: some View {
        if permission == .denied {
            noticeRow("Notifications are off", action: "Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
        } else if permission == .notDetermined {
            noticeRow("shukr can't notify you yet", action: "Allow") {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    Task { await refreshPermission() }
                }
            }
        } else if draft.kind == "prayer" && !hasLocation {
            noticeRow("Needs your location for prayer times", action: nil) {}
        }
    }
    private func noticeRow(_ text: String, action: String?, run: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(text).foregroundStyle(.secondary)
            if let action {
                Text("·").foregroundStyle(.tertiary)
                Button(action, action: run).fontWeight(.medium).foregroundStyle(Color.green)
            }
        }
        .font(.footnote)
    }
    @MainActor private func refreshPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var weekdayChips: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let on = draft.weekdays & (1 << i) != 0
                Button {
                    draft.weekdays ^= (1 << i)
                } label: {
                    Text(symbols[i])
                        .font(.subheadline.weight(.medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(on ? Color.green : Color.secondary)
                        .background(Circle().fill(on ? Color.green.opacity(0.14) : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: draft.weekdays)
    }
}
