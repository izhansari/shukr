//
//  NotificationSamples.swift
//  shukr
//
//  DEBUG only: every notification shukr sends, today's wording and the proposed one (notification
//  audit, 2026-10-01), delivered to this phone a few seconds apart so the owner sees them as iOS
//  really shows them — banner, Lock Screen, Notification Center, the buttons on a long press.
//  Settings → My Dev Stuff → "Send notification samples". Nothing real happens: the buttons are
//  look-alikes (their own ids, which the app ignores) and nothing is marked or snoozed.
//

#if DEBUG
import UserNotifications

enum NotificationSamples {
    enum Batch: String, CaseIterable, Identifiable {
        case current = "Now"
        case proposed = "Proposed"
        var id: String { rawValue }
    }

    private struct Sample {
        let title: String
        var subtitle = ""
        var body = ""
        var category: String? = nil
        var timeSensitive = true
        var thread: String? = nil
    }

    private static let arabicIn = "اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ"
    private static let arabicOut = "اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ"

    /// What shukr sends today (Asr 4:12–6:48 PM as the example), in the order they'd come.
    private static let current: [Sample] = [
        Sample(title: "Asr Time 🟢", subtitle: "Pray by 6:48 PM", category: "SampleRound1"),
        Sample(title: "Asr At Midpoint 🟡", subtitle: "There's 1h 18m", category: "SampleRound1"),
        Sample(title: "Asr Almost Over! 🔴", subtitle: "There's only 30 min", category: "SampleRound1"),
        Sample(title: "It's been 5 minutes", body: "There's only 30 min", category: "SampleRound2"),
        Sample(title: "😑 Are you being serious? Another 5 minutes?", body: "There's only 30 min", category: "SampleConfirm"),
        Sample(title: "5 more minutes have passed!", body: "There's only 30 min", category: "SampleRound1"),
        Sample(title: "Islamic Center of Morrisville", subtitle: "Entering the masjid",
               body: arabicIn + "\nAllahumma-ftah li abwaba rahmatik — O Allah, open for me the gates of Your mercy."),
        Sample(title: "Islamic Center of Morrisville", subtitle: "Leaving the masjid",
               body: arabicOut + "\nAllahumma inni as'aluka min fadlik — O Allah, I ask You of Your bounty."),
        Sample(title: "After Fajr", body: "Subhanallah · 33 counts · ~1 min", category: "SampleZikr", timeSensitive: false),
        Sample(title: "Open shukr to keep your prayer reminders coming",
               body: "Your scheduled reminders end here. Opening shukr lines up the next week.", timeSensitive: false),
        Sample(title: "Welcome to Makkah",
               body: "May Allah accept your visit to His House. The qibla is all around you now.", timeSensitive: false),
    ]

    /// The proposal (owner, 2026-10-01: only the prayer notifications change; the emoji after the name, no grade
    /// words): at the start, 30 min in (when the ring turns yellow), and with 30 min left.
    private static let proposed: [Sample] = [
        Sample(title: "Asr 🟢", subtitle: "Pray by 6:48 PM", category: "SampleRound1"),
        Sample(title: "Asr 🟡", subtitle: "30 minutes since Asr started · pray by 6:48 PM", category: "SampleRound1"),
        Sample(title: "Asr 🔴", subtitle: "Only 30 minutes left · pray before 6:48 PM", category: "SampleRound1"),
    ]

    /// Look-alike buttons: the same titles as the real ones, ids the app doesn't handle.
    private static func registerCategories() async {
        let center = UNUserNotificationCenter.current()
        func noop(_ id: String, _ title: String, foreground: Bool = false) -> UNNotificationAction {
            UNNotificationAction(identifier: "SAMPLE_NOOP_\(id)", title: title, options: foreground ? [.foreground] : [])
        }
        let prayed = noop("PRAYED", "I already prayed")
        let samples: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: "SampleRound1",
                                   actions: [prayed, noop("S5", "Nudge in 5 minutes"), noop("S10", "Nudge in 10 minutes")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: "SampleRound2", actions: [prayed, noop("R2", "5 more minutes")], intentIdentifiers: []),
            UNNotificationCategory(identifier: "SampleConfirm",
                                   actions: [prayed, noop("YES", "Yes"), noop("NOW", "Lol, I'll pray right now!")], intentIdentifiers: []),
            UNNotificationCategory(identifier: "SampleConfirmNew",
                                   actions: [prayed, noop("YES2", "Yes, 5 more"), noop("NOW2", "I'll pray now")], intentIdentifiers: []),
            UNNotificationCategory(identifier: "SampleZikr",
                                   actions: [noop("START", "Start now"), noop("LATER", "Later (30 min)")], intentIdentifiers: []),
        ]
        // setNotificationCategories replaces the whole set: keep the real ones.
        let existing = await center.notificationCategories()
        let ids = Set(samples.map(\.identifier))
        center.setNotificationCategories(existing.filter { !ids.contains($0.identifier) }.union(samples))
    }

    /// Schedules the batch, the first in 5 s, then one every `gap` seconds. Lock the phone to see them
    /// as you would (in the app they show as banners too).
    static func send(_ batch: Batch, gap: TimeInterval = 6) async {
        await registerCategories()
        let list = batch == .current ? current : proposed
        let center = UNUserNotificationCenter.current()
        for (i, s) in list.enumerated() {
            let c = UNMutableNotificationContent()
            c.title = s.title
            c.subtitle = s.subtitle
            c.body = s.body
            c.sound = .default
            if s.timeSensitive { c.interruptionLevel = .timeSensitive }
            if let cat = s.category { c.categoryIdentifier = cat }
            if let t = s.thread { c.threadIdentifier = "sample.\(batch.rawValue).\(t)" }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 + Double(i) * gap, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "sample.\(batch.rawValue).\(i)", content: c, trigger: trigger))
        }
    }
}
#endif
