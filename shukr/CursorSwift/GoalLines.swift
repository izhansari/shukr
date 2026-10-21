//
//  GoalLines.swift
//  shukr
//
//  The goal ladder's morning line on the Salah page (prayer-metrics rethink, row 9; the rule and the words are
//  PrayerMetrics' — Fable's — the look and the place are Zoe's), and the Dev Stuff rows for the ladder's hard-to-reach
//  views. The week hero and the Sunday offer are Frank's (JourneyWeekHero.swift, SundayOffer.swift).
//

import SwiftUI
import SwiftData

/// Dev previews of the states you can't make happen on demand (owner, 2026-10-21: "give me links to all these views in the
/// dev settings section … especially things i wouldn't be able to normally see on my phone"): My Dev Stuff's toggles, or
/// the same `-demo<Key>` launch argument in the sim. DEBUG only; docs/see-it.md lists every one.
enum DevPreview {
    static let morningLine = "MorningLine", morningAsk = "MorningAsk"
    static func on(_ key: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo" + key) || UserDefaults.standard.bool(forKey: "devPreview." + key)
        #else
        false
        #endif
    }
    #if DEBUG
    static func set(_ key: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: "devPreview." + key) }
    #endif
}

/// The line the morning after a missed prayer (plan-v3 §16, "never miss twice" as warm copy): from Fajr until Dhuhr
/// begins, just above the open prayer list (owner, 2026-10-21: "show it when the prayer list is open above the prayer
/// list … it'll probably convert better this way"; "no i said i want it displayed when the list is visble" — it sat under
/// the ring, alone on the closed page). Some of yesterday unmarked: "You missed Isha / 3 prayers yesterday", a tap opens To
/// make up (his A: the tap leads somewhere; was: a tap put it away for the day). Nothing marked yesterday (a no-record day,
/// NoRecordDays): it asks instead, and a tap opens the pick sheet (owner, 2026-10-21: "did you pray them in their windows
/// and forget to mark it … and then it pulls up [the pick sheet]"; his B words). The list lays it out at zero size over
/// its top edge, so nothing moves. Away while the day's page is up (its ring has the make-up pill).
struct MorningMissLine: View {
    @Environment(PrayerViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @State private var line: String?
    /// Yesterday, when nothing was marked on it: the line asks, and a tap fills it in.
    @State private var unrecorded: Date?
    @State private var filling: FillDay?
    @State private var preview = false

    struct FillDay: Identifiable { let day: Date; var id: Date { day } }

    var body: some View {
        let show = line != nil && !DayPageState.shared.up
        Button {
            triggerSomeVibration(type: .light)
            if let unrecorded {
                filling = FillDay(day: unrecorded)
            } else {
                // To make up alone, in one push (Frank's cc01de66; it slid Journey in, then To make up on top — owner:
                // "it double hops pages. fix that").
                JourneyPresenter.shared.makeUpAsked = true
            }
        } label: {
            // One sentence a line (the plain wrap left "it up. ›" alone on the second), a chevron after it as the make-up
            // line's "See all ›" has: the line goes somewhere.
            (Text((line ?? " ").replacingOccurrences(of: "yesterday. ", with: "yesterday.\n")) + Text("  ") + Text(Image(systemName: "chevron.right")).font(.system(size: 10, weight: .medium)))
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 290)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(show ? 1 : 0)
        .allowsHitTesting(show)
        .animation(.easeInOut(duration: 0.3), value: show)
        .accessibilityHidden(!show)
        .accessibilityHint(unrecorded == nil ? "Opens To make up" : "Pick which you prayed")
        .sheet(item: $filling) { f in
            NoRecordPickSheet(day: f.day) { picked in
                guard !preview else { return }   // Dev Stuff's look: nothing written
                NoRecordDays.fill(f.day, picked: picked, viewModel: viewModel)   // posts the change → refresh
            }
            .stageCover("morningFill")
        }
        .task { refresh() }
        .onChange(of: JourneyStore.shared.log?.version) { _, _ in refresh() }
        // A fill-in, a mark or an outside mark: the log is stale now, so this reads again (nothing else reloads it here).
        // A turn later, so JourneyStore's own observer has marked it stale whatever order they were added in (Frank).
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in DispatchQueue.main.async { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private static let askWords = "Nothing marked yesterday. Did you pray and forget to mark?"

    /// Yesterday's unmarked prayers, or the ask when nothing was marked, while it's still morning (before Dhuhr).
    private func refresh() {
        let now = Date()
        let rows = viewModel.todaysPrayers
        #if DEBUG
        preview = DevPreview.on(DevPreview.morningLine) || DevPreview.on(DevPreview.morningAsk)
        if DevPreview.on(DevPreview.morningAsk) {
            unrecorded = Calendar.current.date(byAdding: .day, value: -1, to: PrayerDay.start())
            line = Self.askWords
            return
        }
        if DevPreview.on(DevPreview.morningLine) {
            unrecorded = nil
            line = "You missed 3 prayers yesterday. You can still make them up."
            return
        }
        #endif
        guard let dhuhr = rows.first(where: { $0.name == "Dhuhr" }), now < dhuhr.startTime else { line = nil; unrecorded = nil; return }
        // Nothing marked yesterday (and it's a day the no-record question asks about: not excused, not answered).
        if let day = NoRecordDays.next(in: context, now: now),
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: PrayerDay.start(for: now)),
           Calendar.current.isDate(day, inSameDayAs: yesterday) {
            unrecorded = day
            line = Self.askWords
            return
        }
        unrecorded = nil
        guard let log = JourneyStore.shared.log, !JourneyStore.shared.stale else {
            if line == Self.askWords { line = nil }   // just filled in: the ask goes, the count comes when the log lands
            JourneyStore.shared.loadIfNeeded(container: context.container, today: PrayerDay.start())   // lands → refresh
            return
        }
        // Without "Today's Asr is at 3:43 PM": the ring right above says the next prayer and its time (show a fact once).
        line = PrayerMetrics.morningLine(in: log, excused: Excused.Days(), next: nil, now: now)
    }
}

#if DEBUG
/// My Dev Stuff's "Dev · Goal ladder": the views that only show in a certain week or morning.
struct GoalLadderDevSection: View {
    @State private var offer: GoalOfferItem?
    @State private var morning = DevPreview.on(DevPreview.morningLine)
    @State private var ask = DevPreview.on(DevPreview.morningAsk)

    var body: some View {
        Section {
            Button("Sunday sheet: one step up") { offer = Self.preview(up: true) }
            Button("Sunday sheet: one step down") { offer = Self.preview(up: false) }
            Toggle("Morning after a miss (Salah page)", isOn: $morning)
                .onChange(of: morning) { _, on in DevPreview.set(DevPreview.morningLine, on) }
            Toggle("Morning ask: nothing marked yesterday", isOn: $ask)
                .onChange(of: ask) { _, on in DevPreview.set(DevPreview.morningAsk, on) }
        } header: {
            Text("Dev · Goal ladder")
        } footer: {
            Text("The toggles show their view until you turn them off. Every hard-to-reach view is listed in docs/see-it.md.")
        }
        .sheet(item: $offer) { i in GoalOfferSheet(offer: i.offer, from: i.from, weekStart: i.weekStart, preview: true) }
    }

    /// One step from your goal (on Prayed, down pretends In its window; on the Opening, up pretends Middle).
    private static func preview(up: Bool) -> GoalOfferItem {
        let g = PrayerGoal.current
        let from = up ? (g.up == nil ? PrayerGoal.onTime : g) : (g.down == nil ? PrayerGoal.inWindow : g)
        let offer: PrayerMetrics.GoalOffer = up ? .up(from.up ?? .perfect) : .down(from.down ?? .prayed)
        return GoalOfferItem(offer: offer, from: from, weekStart: .distantPast)
    }
}
#endif
