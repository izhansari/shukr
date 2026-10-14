//
//  Excused.swift
//  shukr
//
//  Excused from prayer (owner, 2026-10-13; plan board/mocks/excused-days, decisions excused-where B · excused-name A ·
//  excused-zikr A). A woman says once that she's excused (haid, or after childbirth) and roughly for how long. While
//  she is:
//  - no prayer of hers can be marked (the three mark paths check `Excused.covers`),
//  - her streaks and stats skip those prayer days (`Excused.counts(day:)`: a day touched by an excused range is left
//    out, never counted as missed),
//  - prayer notifications, Live Activities and the Fajr alarm are not planned; zikr reminders keep coming unless she
//    pauses them,
//  - on her estimated day, then 2 and 4 days later, one gentle check-in ("Ready to start again?").
//  Nothing ends by itself. The record is one JSON list in the app group (`Excused` in SharedTargetForIntents.swift),
//  so no schema change. Anything new that counts prayers must read its days through `Excused.counts(day:)`.
//

import SwiftUI
import UserNotifications
import WidgetKit

extension Excused {

    // MARK: Days that count

    /// The excused prayer days, worked out once per loop (each range's first and last `PrayerDay.start`): comparing dates,
    /// with no prayer-time maths per call (review: per row × range it thrashed PrayerDay's Fajr cache).
    struct Days {
        let spans: [(first: Date, last: Date?)]
        init(_ list: [ExcusedRange] = Excused.ranges) {
            spans = list.map { (PrayerDay.start(for: $0.start), $0.end.map { PrayerDay.start(for: $0) }) }
        }
        /// A prayer day (a `PrayerDay.start` date) an excused range touches.
        func excludes(_ dayStart: Date) -> Bool {
            spans.contains { $0.first <= dayStart && ($0.last.map { dayStart <= $0 } ?? true) }
        }
    }

    /// Whether a prayer day counts towards streaks and stats: always when all five were prayed (a day she prayed in full
    /// is never taken away — review), else only when no excused range touches it.
    static func counts(day dayStart: Date, fullyPrayed: Bool, in days: Days) -> Bool { fullyPrayed || !days.excludes(dayStart) }

    /// The rows of the prayer days that count (grouped by each row's own prayer day).
    static func countedRows(_ rows: [PrayerModel], in days: Days = Days()) -> [PrayerModel] {
        guard !days.spans.isEmpty else { return rows }
        var byDay: [Date: [PrayerModel]] = [:]
        for r in rows { byDay[r.dayStart, default: []].append(r) }
        return byDay.flatMap { day, list in
            counts(day: day, fullyPrayed: Set(list.filter(\.isCompleted).map(\.name)).count >= 5, in: days) ? list : []
        }
    }

    // MARK: Changes (the app only)

    /// Starts a range. `fromDay` today = now; an earlier day = that prayer day's Fajr, so the days she forgot are excused too.
    @MainActor static func start(kind: ExcusedRange.Kind, fromDay: Date, days: Int, pauseZikr: Bool) {
        let now = Date()
        let start: Date
        // Today (the calendar's, or the prayer day's before Fajr) starts now (review: before Fajr, "today" became a Fajr
        // still to come).
        if Calendar.current.isDateInToday(fromDay) || Calendar.current.isDate(fromDay, inSameDayAs: PrayerDay.date(for: now)) || fromDay > now {
            start = now
        } else {
            start = PrayerDay.fajr(onCalendarDayOf: fromDay) ?? Calendar.current.startOfDay(for: fromDay).addingTimeInterval(3 * 3600)
        }
        let expected = Calendar.current.date(byAdding: .day, value: max(days, 1), to: start) ?? start
        var list = ranges.filter { $0.end != nil }   // only one runs at a time
        list.append(ExcusedRange(kind: kind, start: start, expectedEnd: expected, end: nil, pauseZikr: pauseZikr))
        apply(list, reason: "excused on")
    }

    /// While it runs: a new estimate or the zikr switch.
    @MainActor static func update(expectedEnd: Date? = nil, pauseZikr: Bool? = nil) {
        var list = ranges
        guard let i = list.lastIndex(where: { $0.end == nil }) else { return }
        if let expectedEnd { list[i].expectedEnd = expectedEnd }
        if let pauseZikr { list[i].pauseZikr = pauseZikr }
        apply(list, reason: "excused changed", light: true)
    }

    /// "Not yet": n more days, from today once the estimate has passed (owner: "ask for 2 more days or 3 more days").
    @MainActor static func extend(days n: Int) {
        guard let r = current else { return }
        let from = max(r.expectedEnd, Date())
        update(expectedEnd: Calendar.current.date(byAdding: .day, value: n, to: from) ?? from)
    }

    /// Past her estimate and not yet asked today: the app asks once a day too (owner: notifications may be off).
    static var shouldAskToday: Bool {
        guard let r = current, Date() >= r.expectedEnd else { return false }
        return UserDefaults.standard.string(forKey: askedDayKey) != PrayerNotificationID.dayKey(Date())
    }
    static let askedDayKey = "excused.askedDay"
    static func markAskedToday() { UserDefaults.standard.set(PrayerNotificationID.dayKey(Date()), forKey: askedDayKey) }

    /// She's back: everything is planned again from now. A start ended within half an hour was a mistake: it's removed,
    /// so it leaves no excused day behind (review). `planNotifications: false` = the caller awaits the plan itself.
    @MainActor static func end(at date: Date = Date(), planNotifications: Bool = true) {
        var list = ranges
        guard let i = list.lastIndex(where: { $0.end == nil }) else { return }
        if date.timeIntervalSince(list[i].start) < 30 * 60 { list.remove(at: i) } else { list[i].end = max(date, list[i].start) }
        apply(list, reason: "excused off", planNotifications: planNotifications)
    }

    /// Saves, then tells everything that plans or counts.
    /// `changed`'s object for a change that moves no day in or out (the estimate, the zikr switch).
    static let lightChange = "light"

    @MainActor private static func apply(_ list: [ExcusedRange], reason: String, planNotifications: Bool = true, light: Bool = false) {
        let starting = !isActive && list.contains { $0.end == nil }
        save(list)
        NotificationCenter.default.post(name: changed, object: light ? lightChange : nil)   // the Salah page recounts
        if starting { clearPrayerBanners() }
        if planNotifications { NotificationScheduler.topUp(reason: reason) }   // notifications, then the Fajr alarm
        PrayerLiveActivities.plan(reason: reason)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        WatchSync.shared.send()
    }

    /// Starting: today's prayer banners already on the screen and any nudge she'd asked for go (review: a "Nudge in 5
    /// minutes" on a banner from before still nagged).
    private static func clearPrayerBanners() {
        let center = UNUserNotificationCenter.current()
        func prayerOrSnooze(_ id: String) -> Bool {
            PrayerNotificationID.parse(id) != nil || id.hasPrefix(PrayerNotificationID.snoozeHead) || id.hasPrefix("snooze-")
        }
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter {
                $0.hasPrefix(PrayerNotificationID.snoozeHead) || $0.hasPrefix("snooze-") })
        }
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter(prayerOrSnooze))
        }
    }

    // MARK: The check-in (planned with the notifications)

    static let checkInPrefix = "excused.checkin."
    static let checkInCategory = "EXCUSED_CHECKIN"
    static let readyAction = "EXCUSED_READY"
    static let notYetAction = "EXCUSED_NOT_YET"
    static func owns(_ id: String) -> Bool { id.hasPrefix(checkInPrefix) }

    /// Every day at 10 AM from her estimated day until she's back (owner: "to stay safe, we're going to keep notifying you
    /// every day"), two weeks planned at a time (prayers are paused, so there's room); never one in the past. Worded so a
    /// glance at her lock screen says nothing (owner).
    static func checkIns(now: Date = Date()) -> [(id: String, date: Date, content: UNNotificationContent)] {
        guard let r = current else { return [] }
        let cal = Calendar.current
        var first = cal.date(bySettingHour: 10, minute: 0, second: 0, of: r.expectedEnd) ?? r.expectedEnd
        // An estimate already past (a start picked far back): from the next 10 AM, so she still gets them (review).
        if first <= now, let next = cal.nextDate(after: now, matching: DateComponents(hour: 10, minute: 0), matchingPolicy: .nextTime) {
            first = next
        }
        return (0..<14).compactMap { i in
            guard let date = cal.date(byAdding: .day, value: i, to: first), date > now else { return nil }
            let content = UNMutableNotificationContent()
            content.title = "Ready to start again?"
            // The same words for both kinds: "40 days" on a lock screen could say why (review).
            content.body = "Turn your reminders back on whenever you're ready."
            content.categoryIdentifier = checkInCategory
            return ("\(checkInPrefix)\(i)", date, content)
        }
    }

    /// The check-in's buttons: "I'm ready" ends it from the lock screen; "Not yet" leaves it.
    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: checkInCategory,
                               actions: [UNNotificationAction(identifier: readyAction, title: "I'm ready", options: []),
                                         UNNotificationAction(identifier: notYetAction, title: "Not yet", options: [])],
                               intentIdentifiers: [], options: [])
    }

    // MARK: Words

    /// Which day of it this is (the start's day is 1).
    static func dayNumber(_ r: ExcusedRange, now: Date = Date()) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: r.start), to: cal.startOfDay(for: now)).day ?? 0) + 1
    }

    /// "Day 3 of about 7" (the circle, the sheet, the watch).
    static func dayLine(_ r: ExcusedRange, now: Date = Date()) -> String {
        let cal = Calendar.current
        let day = dayNumber(r, now: now)
        let total = max(cal.dateComponents([.day], from: cal.startOfDay(for: r.start), to: cal.startOfDay(for: r.expectedEnd)).day ?? 0, 1)
        return day <= total ? "Day \(day) of about \(total)" : "Day \(day)"
    }

    #if DEBUG
    /// `-demoExcused N`: excused since N days ago (estimate 7), for screenshots; `-demoExcusedOff`: clears it;
    /// `-demoExcusedAsk`: the once-a-day question may come again today.
    @MainActor static func applyDebugArgs() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoExcusedOff") { save([]) }
        if args.contains("-demoExcusedAsk") { UserDefaults.standard.removeObject(forKey: askedDayKey) }   // ask again today
        if args.contains("-demoExcusedIntro") { UserDefaults.standard.removeObject(forKey: introSeenKey) }   // the story again
        if let i = args.firstIndex(of: "-demoExcused"), i + 1 < args.count, let n = Int(args[i + 1]), !isActive {
            let from = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
            start(kind: .haid, fromDay: from, days: 7, pauseZikr: false)
        }
    }
    #endif
}

extension Excused {
    /// The story has been seen (then the ⓘ shows the illustrated rows).
    static let introSeenKey = "excused.introSeen"

    /// A tap on the Salah circle while excused: PrayerTimesView opens the sheet.
    static let openSheet = Notification.Name("ExcusedOpenSheet")
    /// Something in the app tried to mark a prayer while excused (object: the PrayerModel): PrayerTimesView asks.
    static let askResume = Notification.Name("ExcusedAskResume")
}

/// The Salah circle while excused: the word, the day, and how to end it — no countdown, no colour, nothing due.
struct ExcusedFace: View {
    let range: ExcusedRange
    /// The circle's clock: the day line follows it (review: the same input every second, so it never redrew).
    var now: Date = Date()
    var body: some View {
        VStack(spacing: 4) {
            Text("Excused")
                .font(.system(size: 30, weight: .light, design: .rounded))
            Text(Excused.dayLine(range, now: now))
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
            Text("Tap to end")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: 140)
    }
}

// MARK: - Settings → Excused from prayer

/// The Settings row (decision excused-where B: Settings only): "Off", or how far in she is; a tap opens the sheet.
struct ExcusedSettingsRow: View {
    @State private var current: ExcusedRange? = Excused.current
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle").frame(width: 24)
                Text("Excused from prayer").lineLimit(1)
                Spacer(minLength: 8)
                Text(current.map { "Day \(Excused.dayNumber($0))" } ?? "Off").foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { ExcusedSheet() }
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { _ in current = Excused.current }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in current = Excused.current }
        .onAppear { current = Excused.current }
    }
}

/// Turning it on, changing it, ending it, and coming back — one sheet in the new-task flow's look (owner: "stay on
/// brand"): the estimate is a number in the Excused ring's dashes with − and + either side (NewTaskFlow's goal page),
/// a tap on it types one; "Started" sits lower down, a secondary thing (owner). No Haid / After childbirth choice: it
/// only set the estimate (owner); ranges are saved as haid.
struct ExcusedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current: ExcusedRange? = Excused.current
    @State private var startDay = Date()
    @State private var days = 7
    @FocusState private var typing: Bool
    @State private var keepZikr = true
    /// Just ended: the welcome back.
    @State private var welcomeBack = false
    /// The first time: the story (owner, decision excused-info B), then the sheet.
    @State private var intro = !UserDefaults.standard.bool(forKey: Excused.introSeenKey) && Excused.current == nil
    /// The ⓘ: the illustrated rows (decision excused-info, C after the story).
    @State private var showInfo = false

    static let maxDays = 60

    var body: some View {
        if intro {
            ExcusedIntroStory {
                UserDefaults.standard.set(true, forKey: Excused.introSeenKey)
                withAnimation(.snappy(duration: 0.3)) { intro = false }
            } close: { dismiss() }
            .presentationDetents([.large])
        } else {
            sheet
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                if !welcomeBack {
                    Button { showInfo = true } label: {
                        Image(systemName: "info")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How Excused works")
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)
            .sheet(isPresented: $showInfo) { ExcusedInfoSheet() }
            ScrollView {
                VStack(spacing: 22) {
                    if welcomeBack { back } else if let current { running(current) } else { starting }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            if !typing { primaryButton.transition(.opacity) }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { typing = false }   // the keypad has no return key
        .fontDesign(.rounded)
        .presentationDetents([.large])
    }

    // MARK: The three states

    private var starting: some View {
        VStack(spacing: 22) {
            // Named plainly (owner: no dodging the words — this was made for her too); the lock screen, Siri and the
            // widget stay neutral, as anyone can see or hear those.
            heading("Excused from prayer", "For your period (haid), or the bleeding after giving birth (nifas). Prayer is lifted for you: your streaks and scores pause, and nothing counts as missed.")
            daysRing(min: 1, caption: "days, about")
            card {
                row("hands.and.sparkles", "Keep zikr reminders") { Toggle("", isOn: $keepZikr).labelsHidden().tint(.sage) }
                Divider().padding(.leading, 52)
                row("calendar", "Started") {
                    DatePicker("", selection: $startDay, in: Calendar.current.date(byAdding: .day, value: -40, to: .now)!...Date.now,
                               displayedComponents: .date).labelsHidden()
                }
            }
            Text("Started earlier? Pick that day so your streak isn't broken.\nAfter your estimate we'll check in once a day until you're back.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private func running(_ r: ExcusedRange) -> some View {
        let today = Excused.dayNumber(r)
        return VStack(spacing: 22) {
            heading("Excused from prayer", "Since \(r.start.formatted(.dateTime.month(.abbreviated).day())) · Day \(today)")
            daysRing(min: today, caption: "days in all, about")
            card {
                row("hands.and.sparkles", "Keep zikr reminders") { Toggle("", isOn: $keepZikr).labelsHidden().tint(.sage) }
            }
            Text("While you're on your period or recovering after birth, your prayer reminders, the Fajr alarm and prayer cards are paused. From your estimated day we'll check in once a day; need longer, add days here.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .onAppear {
            keepZikr = !r.pauseZikr
            let cal = Calendar.current
            days = max(cal.dateComponents([.day], from: cal.startOfDay(for: r.start), to: cal.startOfDay(for: r.expectedEnd)).day ?? 7, 1)
        }
        .onChange(of: keepZikr) { _, keep in if keep == r.pauseZikr { Excused.update(pauseZikr: !keep); refresh() } }
        // A new estimate is saved as the sheet goes (− / + can be held: one save, one re-plan).
        .onDisappear {
            guard !welcomeBack, let r = Excused.current else { return }
            let end = Calendar.current.date(byAdding: .day, value: days, to: r.start) ?? r.expectedEnd
            if !Calendar.current.isDate(end, inSameDayAs: r.expectedEnd) { Excused.update(expectedEnd: end) }
        }
    }

    /// After ending: ghusl, then the prayer that's on (owner: a note, never an automatic mark).
    private var back: some View {
        VStack(spacing: 20) {
            heading("Welcome back", "Make ghusl, then pray.")
            card {
                if let now = PrayerWindows.pick(.current) {
                    row("clock", "\(now.name) is on now") { Text("until \(shortTimePM(now.end))").foregroundStyle(.secondary) }
                } else if let next = PrayerWindows.pick(.next) {
                    row("clock", "Next: \(next.name)") { Text(shortTimePM(next.start)).foregroundStyle(.secondary) }
                }
                Divider().padding(.leading, 52)
                row("flame", "Your streaks") { Text("Kept").foregroundStyle(.secondary) }
            }
            Text("If your period or bleeding ended during a prayer's time, that prayer is due. Some schools also count the prayer before it. Ask the imam at your masjid if you're unsure.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: Pieces

    private func daysRing(min low: Int, caption: String) -> some View {
        ExcusedDaysRing(days: $days, range: low...Self.maxDays, caption: caption, typing: $typing)
    }

    private var primaryButton: some View {
        let title = welcomeBack ? "Done" : current == nil ? "Start" : "I'm back: end it"
        return Button {
            if welcomeBack { dismiss() }
            else if current == nil {
                Excused.start(kind: .haid, fromDay: startDay, days: days, pauseZikr: !keepZikr)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } else {
                Excused.end()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.3)) { welcomeBack = true; current = nil }
            }
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.sage)
                .frame(width: 240, height: 52)
                .background(Capsule().fill(Color.sage.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 8).padding(.bottom, 16)
    }

    private func refresh() { current = Excused.current }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 30, weight: .light, design: .rounded)).multilineTextAlignment(.center)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28).padding(.top, 14)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 20)
    }

    private func row<Value: View>(_ icon: String, _ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.sage).frame(width: 24)
            Text(label).foregroundStyle(.primary)
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// The ☰ button's dot while excused (owner: "something to indicate there's something in this menu"): a soft slate blue —
/// not the tour's green, not red (it reads as blood), not the pinks / lavenders period apps use (it would give it away).
struct ExcusedMenuBadge: View {
    static let ink = Color(red: 0.45, green: 0.56, blue: 0.70)
    var body: some View {
        let show = CircleStage.shared.excused != nil
        Circle()
            .fill(Self.ink)
            .frame(width: 8, height: 8)
            .scaleEffect(show ? 1 : 0.1)
            .opacity(show ? 1 : 0)
            .animation(show ? .spring(response: 0.45, dampingFraction: 0.55).delay(0.6) : .easeOut(duration: 0.25), value: show)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A number of days inside the Excused ring's dashes, − and + either side (held, they keep going), a tap on the number
/// types one (NewTaskFlow's goal page; owner: "stay on brand"). `plus` shows it as "+3" — days added (owner).
struct ExcusedDaysRing: View {
    @Binding var days: Int
    let range: ClosedRange<Int>
    var plus = false
    let caption: String
    var typing: FocusState<Bool>.Binding
    @State private var text = ""

    var body: some View {
        HStack(spacing: 18) {
            RepeatRoundButton(symbol: "minus") { step in days = max(range.lowerBound, days - step) }
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4.5]))
                Circle().stroke(Color.sage.opacity(typing.wrappedValue ? 0.9 : 0), lineWidth: 2).padding(6)
                VStack(spacing: 2) {
                    ZStack {
                        // Typing: an empty field, the number faint behind it; otherwise the number (with its "+").
                        TextField(plus ? "+\(days)" : "\(days)", text: $text)
                            .keyboardType(.numberPad)
                            .focused(typing)
                            .multilineTextAlignment(.center)
                            .opacity(typing.wrappedValue ? 1 : 0)
                            .onChange(of: text) { _, t in
                                let digits = String(t.filter(\.isNumber).prefix(2))
                                if digits != t { text = digits }
                                if let n = Int(digits), n > 0 { days = min(max(n, range.lowerBound), range.upperBound) }
                            }
                        if !typing.wrappedValue {
                            Text(plus ? "+\(days)" : "\(days)").contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 60, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 150)
                    Text(caption).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)
            .contentShape(Circle())
            .onTapGesture { typing.wrappedValue = true }
            RepeatRoundButton(symbol: "plus") { step in days = min(range.upperBound, days + step) }
        }
        .animation(.snappy(duration: 0.15), value: days)
        .onChange(of: typing.wrappedValue) { _, on in if on { text = "" } }
        .padding(.vertical, 4)
    }
}

/// "Not yet" past her estimate (owner: "a number input with a plus and a minus … matching the initial page", and clear
/// that it's days added): "+2 more days" in the Excused ring; the check-ins move with it.
struct ExcusedExtendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var days = 2
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Not yet?").font(.system(size: 30, weight: .light, design: .rounded))
                Text("Add a few more days to your estimate.").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            ExcusedDaysRing(days: $days, range: 1...30, plus: true, caption: days == 1 ? "more day" : "more days", typing: $typing)
            Text("We'll check in again once a day after that.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !typing {
                Button {
                    Excused.extend(days: days)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text("Add \(days) \(days == 1 ? "day" : "days")")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.sage)
                        .frame(width: 240, height: 52)
                        .background(Capsule().fill(Color.sage.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { typing = false }   // the keypad has no return key
        .fontDesign(.rounded)
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
    }
}


// MARK: - How Excused works (decision excused-info: B the first time, C behind the ⓘ)

/// The small pictures both pages share, drawn from the real pieces so they follow light and dark.
enum ExcusedPicture {
    case ring, paused, quiet, checkIn, privacy, elsewhere

    @ViewBuilder func view(big: Bool) -> some View {
        let k: CGFloat = big ? 1 : 0.42
        switch self {
        case .ring:
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4.5]))
                if big {
                    VStack(spacing: 2) {
                        Text("Excused").font(.system(size: 26, weight: .light, design: .rounded))
                        Text("Day 3 of about 7").font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: big ? 170 : 34, height: big ? 170 : 34)
        case .paused:
            VStack(alignment: .leading, spacing: big ? 10 : 4) {
                ForEach(big ? ["Fajr", "Dhuhr", "Asr"] : ["Fajr", "Dhuhr"], id: \.self) { name in
                    HStack(spacing: 10) {
                        PrayerStatusDot(style: .muted, done: false, future: false, scoreColor: .secondary, pulse: 0, excused: true)
                        if big { Text(name).font(.system(size: 17, weight: .light, design: .rounded)).foregroundStyle(.secondary) }
                        else { Capsule().fill(Color.primary.opacity(0.12)).frame(width: 18, height: 3) }
                    }
                }
            }
            .padding(big ? 22 : 0)
            .background(RoundedRectangle(cornerRadius: big ? 22 : 8, style: .continuous).fill(Color.primary.opacity(big ? 0.045 : 0)))
            .scaleEffect(big ? 1 : 0.85)
        case .quiet:
            Image(systemName: "bell.slash").font(.system(size: 64 * k, weight: .light)).foregroundStyle(.secondary)
        case .checkIn:
            HStack(spacing: 8 * k) {
                RoundedRectangle(cornerRadius: 6 * k).fill(Color.sage).frame(width: 26 * k, height: 26 * k)
                if big {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to start again?").font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text("Turn your reminders back on whenever you're ready.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Capsule().fill(Color.primary.opacity(0.12)).frame(width: 18, height: 3)
                }
            }
            .padding(big ? 14 : 5)
            .background(RoundedRectangle(cornerRadius: big ? 18 : 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        case .privacy:
            Image(systemName: "lock.iphone").font(.system(size: 64 * k, weight: .light)).foregroundStyle(Color.sage)
        case .elsewhere:
            HStack(spacing: 10 * k) {
                Image(systemName: "square.grid.2x2")
                Image(systemName: "switch.2")
                Image(systemName: "applewatch")
            }
            .font(.system(size: 34 * k, weight: .light))
            .foregroundStyle(.secondary)
        }
    }
}

/// The first time (decision excused-info B): six pages, one picture each, swiped across like the tour; the last says
/// shukr never tracks her cycle (owner: testers asked "will it know my time of month?").
struct ExcusedIntroStory: View {
    let done: () -> Void
    let close: () -> Void
    @State private var page = 0

    private struct Page { let picture: ExcusedPicture; let title: String; let text: String }
    private static let pages: [Page] = [
        Page(picture: .ring, title: "Made for you",
             text: "For your period (haid), or the bleeding after giving birth (nifas). Prayer is lifted for you, and shukr follows."),
        Page(picture: .paused, title: "Paused, not missed",
             text: "Those days are skipped: your streaks stay exactly where they were, and your list shows each prayer paused."),
        Page(picture: .quiet, title: "Quiet",
             text: "No prayer reminders, prayer cards or Fajr alarm while you're excused. Zikr keeps going, unless you pause its reminders."),
        Page(picture: .checkIn, title: "We'll check in",
             text: "From your estimated day, once a day: ready to start again? Not yet? Add a few more days."),
        Page(picture: .privacy, title: "Private by design",
             text: "shukr never tracks or predicts your cycle. Each month you turn this on yourself, on purpose, so nothing is guessed or kept beyond what you set. It stays on this phone."),
        Page(picture: .elsewhere, title: "Everywhere else",
             text: "Widgets, Siri and your watch still show prayer times. Tapping ✓ asks if you're back, and nothing is ever said out loud."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(page + 1) of \(Self.pages.count)").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 18)
            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    let p = Self.pages[i]
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        p.picture.view(big: true).frame(height: 190)
                        Text(p.title).font(.system(size: 30, weight: .light, design: .rounded))
                        Text(p.text).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 36)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 6) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Color.sage : Color.primary.opacity(0.12)).frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .animation(.snappy(duration: 0.25), value: page)
            .padding(.bottom, 14)
            Button {
                if page < Self.pages.count - 1 { withAnimation(.snappy(duration: 0.3)) { page += 1 } } else { done() }
            } label: {
                Text(page < Self.pages.count - 1 ? "Next" : "Got it")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .frame(width: 240, height: 52)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fontDesign(.rounded)
    }
}

/// The ⓘ after the story (decision excused-info C): one page, a tiny picture of what she'll see beside each row.
struct ExcusedInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    private static let rows: [(ExcusedPicture, String, String)] = [
        (.ring, "The Salah circle", "Shows the time as usual; open your prayer list and it reads \u{201C}Excused \u{00B7} Day 3\u{201D}."),
        (.paused, "Paused, not missed", "Grey pause dots in your list; your streaks stay as they were."),
        (.quiet, "Quiet", "No prayer reminders, prayer cards or Fajr alarm. Zikr keeps going unless you pause it."),
        (.checkIn, "Check-ins", "From your estimated day, once a day. Not yet? Add a few more days."),
        (.privacy, "Private by design", "shukr never tracks or predicts your cycle: you turn this on each month yourself. It stays on this phone."),
        (.elsewhere, "Widgets, Siri, watch", "Prayer times as usual. Tapping \u{2713} asks if you're back; nothing is said out loud."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("How Excused works").font(.system(size: 30, weight: .light, design: .rounded))
                        Text("For your period (haid), or after giving birth (nifas). Prayer is lifted for you.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Divider().padding(.leading, 86) }
                            HStack(alignment: .center, spacing: 14) {
                                r.0.view(big: false)
                                    .frame(width: 58, height: 46)
                                    .clipped()
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.systemBackground)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.1).font(.subheadline.weight(.semibold))
                                    Text(r.2).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fontDesign(.rounded)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
