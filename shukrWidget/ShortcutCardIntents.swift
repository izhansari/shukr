//
//  ShortcutCardIntents.swift
//  shukr (app and widget extension)
//
//  iOS 26: the Shortcuts cards with buttons (time left, today's times, prayed) and their marks.
//  Moved out of SharedTargetForIntents.swift (cleanup-map tangle 3, step 4b).
//

import Foundation
import SwiftUI
import AppIntents
import WidgetKit
import SwiftData

// MARK: - iOS 26: cards with buttons (decision shortcut-buttons-ios26 A)

/// What a mark from Shortcuts marks: the prayer whose time it is, else today's last one still unmarked (a late Isha).
enum PrayerMarkNow {
    static func target(now: Date = Date()) -> PrayerWindows.Window? {
        // Excused: nothing to mark, and every answer stays neutral ("No prayer is on right now"), so a question asked
        // out loud never says why (owner).
        if Excused.isActive { return nil }
        if let c = PrayerWindows.pick(.current, now: now) { return c }
        let done = SharedStore.completedPrayerNamesToday()
        return PrayerWindows.pick(.previous, now: now).flatMap { p in
            PrayerWindows.today(now).contains { $0.start == p.start } && !done.contains(p.name) ? p : nil }
    }
    static func mark(_ c: PrayerWindows.Window) async -> Bool {
        if Excused.covers(start: c.start, end: c.end) { return false }
        if let hook = PrayerWindowHooks.widgetMark { return await hook(c.name, c.start, c.end) }
        return SharedStore.markPrayerComplete(named: c.name, start: c.start, end: c.end)
    }
    static func grade(_ c: PrayerWindows.Window, at: Date) -> String {
        PrayerScoring.grade(for: PrayerScoring.score(start: c.start, end: c.end, markedAt: at)).rawValue
    }
    /// What Siri says once it's marked: "Asr marked as prayed during the Closing window. Score: 66." (a bare "Closing."
    /// out loud sounded like something shutting down).
    static func spoken(_ c: PrayerWindows.Window, at: Date) -> String {
        PrayerScoring.spokenMark(c.name, score: PrayerScoring.score(start: c.start, end: c.end, markedAt: at))
    }
    /// The prayer's card now: running (with a ✓), or marked (with an Undo when asked for).
    static func card(_ c: PrayerWindows.Window, undo: Bool, scheme: ColorScheme) -> AnyView {
        // Its own row, not today's names: a late Isha redrawn after Fajr still reads as marked (review).
        let marked = SharedStore.markedTime(of: c.name, start: c.start)
        let state = PrayerWindowAttributes.ContentState(label: c.name, start: c.start, end: c.end, symbol: prayerIcon(for: c.name),
                                                        markedAt: marked, dark: scheme == .dark)
        // Excused (Excused.swift): no ✓ that would do nothing.
        let mark: PrayerCardSnippet.Action = Excused.covers(start: c.start, end: c.end) ? .none : .mark
        return AnyView(PrayerCardSnippet(state: state, action: marked == nil ? mark : undo ? .undo : .none)
            .environment(\.colorScheme, scheme))
    }
}

/// A card's ✓ (Time Left, Today's Times): marks the prayer the card shows (review: re-working it out at the tap, a card
/// showing Asr tapped after Maghrib began marked Maghrib); the card redraws itself after.
struct MarkPrayerFromCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer from a Card"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult {
        let w: PrayerWindows.Window? = if let name, let start, let end { .init(name: name, start: start, end: end) } else { PrayerMarkNow.target() }
        if let w, SharedStore.markedTime(of: w.name, start: w.start) == nil { _ = await PrayerMarkNow.mark(w) }
        return .result()
    }
}

/// The Time Left card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TimeLeftCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Time Left Card"
    static var isDiscoverable: Bool = false
    /// The prayer it was asked about (redrawn after its ✓ it stays that prayer, even once the next one has begun).
    @Parameter(title: "Prayer") var name: String?
    @Parameter(title: "Start") var start: Date?
    @Parameter(title: "End") var end: Date?
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        if let name, let start, let end {
            return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: false, scheme: scheme))
        }
        if let c = PrayerWindows.pick(.current) { return .result(view: PrayerMarkNow.card(c, undo: false, scheme: scheme)) }
        if let n = PrayerWindows.pick(.next) {
            return .result(view: AnyView(NextPrayerSnippet(name: n.name, start: n.start).environment(\.colorScheme, scheme)))
        }
        return .result(view: AnyView(EmptyView()))
    }
}

/// A Shortcuts answer: what's said, its card, and the value it passes on. Each action builds its own, and shukr's grouped
/// tiles (Ask shukr, ShukrAppShortcuts.swift) give the same one (iOS 27 hides an app's tiles outside a section).
@available(iOS 26.0, *)
struct ShortcutAnswer<Value> {
    let value: Value
    let dialog: IntentDialog
    let card: any SnippetIntent
}

/// "Get Time Left" on iOS 26: the same answer, its card with a ✓.
@available(iOS 26.0, *)
struct TimeLeftNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Left"
    static var description = IntentDescription(
        "Minutes left in the prayer whose time it is now — whether or not you've prayed it. Between Sunrise and Dhuhr, minutes until Dhuhr. Passes the minutes on; its card can mark the prayer.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "how long", "remaining", "ends"], resultValueName: "Minutes Left")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<Int> {
        ShortcutTopUp.request()
        let now = Date()
        if let c = PrayerWindows.pick(.current) {
            let mins = max(1, Int((c.end.timeIntervalSince(now) / 60).rounded(.down)))
            return .init(value: mins, dialog: "\(PrayerWindows.span(c.end.timeIntervalSince(now))) left for \(c.name). It ends at \(shortTimePM(c.end)).",
                         card: TimeLeftCardIntent(c))
        }
        guard let n = PrayerWindows.pick(.next) else { throw PrayerTimeUnavailable() }
        let mins = max(1, Int((n.start.timeIntervalSince(now) / 60).rounded(.down)))
        return .init(value: mins, dialog: "\(noPrayerOnLine) \(n.name) starts in \(PrayerWindows.span(n.start.timeIntervalSince(now))).",
                     card: TimeLeftCardIntent())
    }
}

/// Today's Times card, drawn again after its ✓.
@available(iOS 26.0, *)
struct TodaysTimesCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Today's Times Card"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        let now = Date()
        return .result(view: AnyView(TodaysTimesSnippet(rows: TodaysTimesSnippet.rows(now: now), markable: !Excused.isActive, now: now)
            .environment(\.colorScheme, scheme)))
    }
}

/// "Get Today's Prayer Times" on iOS 26: the list, its current prayer markable.
@available(iOS 26.0, *)
struct TodaysTimesNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today’s Prayer Times"
    static var description = IntentDescription(
        "Today's five prayer times with your method and madhab, as a list: what's passed (✓ when you marked it), what's on now (tap to mark it), what's to come.",
        categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "schedule", "timetable", "today"], resultValueName: "Prayer Times")
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<[String]> {
        ShortcutTopUp.request()
        let now = Date()
        let five = PrayerWindows.today(now)
        guard !five.isEmpty else { throw PrayerTimeUnavailable() }
        let spoken = TodaysTimesSnippet.spoken(now: now)
        return .init(value: five.map { "\($0.name) \(shortTimePM($0.start))" }, dialog: IntentDialog(stringLiteral: spoken),
                     card: TodaysTimesCardIntent())
    }
}

/// I Prayed's card: the marked prayer with an Undo that asks in shukr (owner: never an easy undo).
@available(iOS 26.0, *)
struct PrayedCardIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Prayed Card"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Prayer") var name: String
    @Parameter(title: "Start") var start: Date
    @Parameter(title: "End") var end: Date
    init() {}
    init(_ w: PrayerWindows.Window) { name = w.name; start = w.start; end = w.end }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let scheme = await ShortcutLook.scheme()
        return .result(view: PrayerMarkNow.card(.init(name: name, start: start, end: end), undo: true, scheme: scheme))
    }
}

/// "Mark Prayer as Prayed" on iOS 26: marks it, shows its card with Undo.
@available(iOS 26.0, *)
struct MarkPrayedNowIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Prayer as Prayed"
    static var description = IntentDescription("Marks the prayer whose time it is now as prayed, scored like in shukr. Passes the grade on (Perfect, Middle, Closing, Qaza). Undo asks in shukr.",
                                               categoryName: "Prayer Times", searchKeywords: ["salah", "namaz", "prayed", "mark", "done"],
                                               resultValueName: "Grade")
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetIntent {
        let a = try await Self.answer()
        return .result(value: a.value, dialog: a.dialog, snippetIntent: a.card)
    }
    static func answer() async throws -> ShortcutAnswer<String> {
        ShortcutTopUp.request()
        guard let c = PrayerMarkNow.target() else {
            if let n = PrayerWindows.pick(.next) {
                return .init(value: "", dialog: "\(noPrayerOnLine) \(n.name) starts at \(shortTimePM(n.start)).", card: TimeLeftCardIntent())
            }
            throw PrayerTimeUnavailable()
        }
        if SharedStore.completedPrayerNamesToday().contains(c.name) {
            let at = SharedStore.markedTime(of: c.name, start: c.start) ?? Date()
            return .init(value: PrayerMarkNow.grade(c, at: at), dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
        }
        let now = Date()
        let marked = await PrayerMarkNow.mark(c)
        let at = SharedStore.markedTime(of: c.name, start: c.start) ?? now
        let grade = PrayerMarkNow.grade(c, at: at)
        guard marked else {   // review: it said "marked" even when nothing was
            if SharedStore.markedTime(of: c.name, start: c.start) != nil {
                return .init(value: grade, dialog: "\(c.name) is already marked as prayed.", card: PrayedCardIntent(c))
            }
            throw PrayerTimeUnavailable()
        }
        return .init(value: grade, dialog: "\(PrayerMarkNow.spoken(c, at: at))", card: PrayedCardIntent(c))
    }
}
