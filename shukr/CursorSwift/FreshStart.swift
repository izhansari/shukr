import SwiftUI

// A fresh start (owner, 2026-10-18): a clean slate for stats that might put someone off coming back — "Journey page may be
// something they look at and get turned off and they think theres no way they can come back from such a low %age". One
// prayer day, kept in Settings; nothing is deleted and an undo brings the whole history back. "A big deal - not a nilly
// willy feature to the user. With an emotional moment before they commit": a page that says what changes and a hold to
// begin. Owed prayers stay ("keep qaza forsure"). Every count reads it through PrayerStats (PrayerGoal.swift); what counts
// from it and what stays lifetime: board/goal-reset-inventory.md, his picks 2026-10-18 ("your pick for all").

/// The fresh start: one prayer day ("YYYY-MM-DD", the day turns at Fajr), or none.
enum FreshStart {
    static let key = "freshStartDay"
    /// Posted when it's set or undone.
    static let changed = Notification.Name("FreshStart.changed")

    static var dayKey: String? { UserDefaults.standard.string(forKey: key) }
    /// Midnight at the start of its day.
    static var start: Date? { dayKey.flatMap(PrayerDay.start(ofKey:)) }

    /// Whether it cleared the prayers to make up too (owner, 2026-10-19: "lets give them option to keep or start fresh with
    /// their made up prayers too … it says i have like 400 to make up but its not accurate for me"). Off by default — owed
    /// prayers stay ("keep qaza forsure", 2026-10-18). Nothing is deleted: To make up and Prayer scores' count just read
    /// from the fresh start's day; Undo brings them all back.
    static let makeUpKey = "freshStartClearsMakeUp"
    static var clearsMakeUp: Bool { dayKey != nil && UserDefaults.standard.bool(forKey: makeUpKey) }
    /// The prayer day ("YYYY-MM-DD") owed prayers count from, or nil for all of them.
    static var makeUpFromKey: String? { clearsMakeUp ? dayKey : nil }
    static var makeUpFrom: Date? { clearsMakeUp ? start : nil }

    /// Day 1 on the fresh start's own day, by the prayer day.
    static func dayNumber(now: Date = Date()) -> Int? {
        guard let start else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: PrayerDay.start(for: now)).day ?? 0
        return max(days, 0) + 1
    }

    /// From today's prayer day — or, between midnight and Fajr, the one that starts at Fajr: the prayer day still showing
    /// then is yesterday's and already over (Isha ended at 11:59 PM), and starting it would put its record (a missed Isha)
    /// inside the fresh start (Fable's audit #3). Day 1 until Fajr, then Day 1 again.
    @MainActor static func begin(clearMakeUp: Bool = false, now: Date = Date()) {
        let calendarDay = Calendar.current.startOfDay(for: now)
        let key = calendarDay > PrayerDay.start(for: now) ? PrayerNotificationID.dayKey(calendarDay) : PrayerDay.key(for: now)
        UserDefaults.standard.set(key, forKey: Self.key)
        UserDefaults.standard.set(clearMakeUp, forKey: makeUpKey)
        JourneyMakeUpPage.last = nil   // To make up opens on fresh entries, not the list from before (a flash of the old count)
        NotificationCenter.default.post(name: changed, object: nil)
        PrayerStats.changed()
    }

    /// Back to an earlier fresh start: Undo right after starting again on a later visit (owner, 2026-10-19).
    @MainActor static func restore(dayKey: String, clearsMakeUp: Bool) {
        UserDefaults.standard.set(dayKey, forKey: Self.key)
        UserDefaults.standard.set(clearsMakeUp, forKey: makeUpKey)
        JourneyMakeUpPage.last = nil   // To make up opens on fresh entries, not the list from before (a flash of the old count)
        NotificationCenter.default.post(name: changed, object: nil)
        PrayerStats.changed()
    }

    @MainActor static func undo() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: makeUpKey)
        JourneyMakeUpPage.last = nil   // To make up opens on fresh entries, not the list from before (a flash of the old count)
        NotificationCenter.default.post(name: changed, object: nil)
        PrayerStats.changed()
    }
}

/// Settings' row: "Off", or the day it's on.
struct FreshStartSettingsRow: View {
    @State private var day: Int? = FreshStart.dayNumber()
    var body: some View {
        NavigationLink { FreshStartPage() } label: {
            HStack(spacing: 12) {
                Image(systemName: "leaf").frame(width: 24)
                Text("Fresh start").lineLimit(1)
                Spacer(minLength: 8)
                Text(day.map { "Day \($0)" } ?? "Off").foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .onReceive(NotificationCenter.default.publisher(for: FreshStart.changed)) { _ in day = FreshStart.dayNumber() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in day = FreshStart.dayNumber() }
        .onAppear { day = FreshStart.dayNumber() }
    }
}

/// The page (Design, direction A with the verse inside, owner 2026-10-19: "lets see what mixing A with the verse inside
/// feels like instead of the leaf thing … better copy explaining it … better visual hierarchy"; canvas
/// board/mocks/fresh-start-page). In the soft look: a light title over one grey line; the hero is a ring pressed into the
/// page with Az-Zumar 39:53 inside it, and the ring is what you hold — the sage arc draws under the thumb, let go and it
/// winds back from where it is. When it closes, the ring rises off the page (NeuLiftCard, pressed → raised) and the verse
/// gives way to Day 1. Under it, a flat list says what changes and what stays. The bottom slot holds the instruction, then
/// Done; under it the quiet line. Nothing moves when something changes: every swap happens in a slot of fixed size.
/// Motion is the system's: `.blurReplace` for every swap (plain fades with Reduce Motion), `.numericText` for the day,
/// `.smooth` springs for the lift and the wind-back; the hold itself is a linear dial.
struct FreshStartPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The day it's on (nil = off), and whether it was begun on this visit (the moment's words and Undo).
    @State private var day: Int? = FreshStart.dayNumber()
    @State private var justBegan = false
    /// The fresh start this visit replaced (a later visit's hold starts again today): Undo brings it back.
    @State private var replaced: (key: String, clears: Bool)?
    /// The hold, 0…1: the arc.
    @State private var held: CGFloat = 0
    @State private var holding = false
    @State private var ticks: Task<Void, Never>?
    @State private var askUndo = false
    @State private var pageHeight: CGFloat = 0
    /// Keep or start fresh with the prayers to make up — chosen before the hold, applied when it completes.
    @State private var clearMakeUp = FreshStart.clearsMakeUp
    /// How many are owed now (shown while choosing, the first time).
    @State private var owed: Int?
    @Environment(\.modelContext) private var context

    /// How long the ring is held to begin.
    static let holdTime = 1.5
    static let ringSize: CGFloat = 256   // room for "Hold the ring" under the verse (owner, 2026-10-19)

    private var startWords: String {
        (FreshStart.start ?? Date()).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    /// Held to begin. A later visit looks as the first day did (owner, 2026-10-19: "I want the page to look how it did the
    /// first day. That way, they don't have to press undo and then hold the button down again"): its hold starts again
    /// today, and the date it counts from now shows at the bottom.
    private var canHold: Bool { !justBegan }
    private var swap: AnyTransition { reduceMotion ? .opacity : AnyTransition(.blurReplace) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    heading
                    Spacer(minLength: 20)
                    ring
                    Spacer(minLength: 24)
                    facts
                    Spacer(minLength: 12)
                }
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .scrollBounceBehavior(.basedOnSize)
            buttons
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ticks?.cancel() }
    }

    // MARK: Pieces

    private var heading: some View {
        let (title, line): (String, String) =
            // No date on the day itself: before Fajr the prayer day is still yesterday's date, which reads wrong as "today".
            if justBegan { ("Bismillah", "Your fresh start begins today. Every prayer from here is part of it.") }
            else { ("A fresh start", "Your past doesn't define you. Start counting again from today.") }
        return VStack(spacing: 8) {
            ZStack {   // the old and new words overlap while they swap, never side by side
                Text(title).font(.system(size: 32, weight: .light, design: .rounded))
                    .id(title).transition(swap)
            }
            // Two lines' room whatever the words, so nothing under it moves when they change.
            ZStack(alignment: .top) {
                Text("\n").font(.subheadline).hidden()
                Text(line).font(.subheadline).foregroundStyle(.secondary)
                    .id(line).transition(swap)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.top, 8)
    }

    /// The hero: a ring pressed into the page, the verse inside it, held to begin. The arc draws with the hold; done, the
    /// ring rises off the page and holds Day N.
    private var ring: some View {
        let on = justBegan
        let size = Self.ringSize
        return ZStack {
            NeuLiftCard(shape: Circle(), lift: on ? 1 : 0)
            Circle().inset(by: 16).stroke(Color.primary.opacity(0.06), lineWidth: 10)
            Circle().inset(by: 16)
                .trim(from: 0, to: on ? 1 : held)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(held > 0.001 || on ? 1 : 0)
            ZStack {
                if on, let day {
                    VStack(spacing: 0) {
                        Text("Day").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(day)").font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(day)))
                    }
                    .transition(swap)
                } else {
                    verse.transition(swap)
                }
            }
            .frame(width: size - 64)
        }
        .frame(width: size, height: size)
        .scaleEffect(holding ? 0.98 : 1)
        .animation(.snappy(duration: 0.2), value: holding)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 60) {
            if canHold { begin() }
        } onPressingChanged: { pressing in
            guard canHold else { return }
            if pressing {
                holding = true
                withAnimation(.linear(duration: Self.holdTime)) { held = 1 }
                startTicks()
            } else {
                ticks?.cancel()
                // Winds back from wherever it is (an animation retargets from the drawn value); a new press picks up there.
                withAnimation(.smooth(duration: 0.35)) { held = 0; holding = false }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(on ? "Fresh start, day \(day ?? 1)" : "Fresh start. Despair not of the Mercy of Allah.")
        .accessibilityHint(canHold ? (day == nil ? "Hold to begin your fresh start today" : "Hold to start again today") : "")
        .accessibilityAddTraits(canHold ? .isButton : [])
        .accessibilityAction { if canHold { begin() } }
    }

    /// Az-Zumar 39:53, the part that speaks to someone who thinks it's too late: the app's own Quran text and translation
    /// (quran.sqlite, english_hilali.sqlite).
    private var verse: some View {
        VStack(spacing: 6) {
            Text("لا تَقنَطوا مِن رَحمَةِ اللَّهِ")
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 23))
                .environment(\.layoutDirection, .rightToLeft)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("“Despair not of the Mercy of Allah.”").font(.footnote).italic()
            Text("Az-Zumar 39:53").font(.caption2).foregroundStyle(.secondary)
            // What to do, in the ring you do it to (owner, 2026-10-19: "add "hold the ring" to inside of the ring in
            // secondary text"); the bottom no longer says it too.
            Text("Hold the ring").font(.footnote).foregroundStyle(.secondary).padding(.top, 10)
        }
        .multilineTextAlignment(.center)
    }

    /// What a fresh start changes and what it keeps: a flat list, grey symbols (nothing here is tapped), a line each
    /// and a quieter line under it.
    private var facts: some View {
        VStack(spacing: 0) {
            row("chart.bar", "Your stats start from today", "Your streak and scores count from here.")
            Divider().padding(.leading, 40)
            row("photo.on.rectangle.angled", "Nothing is deleted", "Your prayers, photos and places stay.")
            Divider().padding(.leading, 40)
            makeUpRow
            Divider().padding(.leading, 40)
            row("arrow.uturn.backward", "See it all any time", "Look back, or undo to bring it all back.")
        }
        .padding(.horizontal, 24)
    }

    /// Prayers to make up: kept by default; before the hold, a switch to start them fresh too (it reads its line once:
    /// "Your 412 stay on your list" / "reset to zero too"). After, what was chosen.
    @ViewBuilder private var makeUpRow: some View {
        if canHold {
            // The switch at the row's end, centred on both lines: beside the title it squeezed "Prayers to make up" small.
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "hourglass").font(.body).foregroundStyle(.secondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayers to make up").font(.body).lineLimit(1)
                    ZStack(alignment: .leading) {
                        Text(makeUpChoiceLine).font(.subheadline).foregroundStyle(.secondary)
                            .id(clearMakeUp).transition(swap)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                FreshStartMakeUpSwitch(clear: $clearMakeUp)
            }
            .padding(.vertical, 8)
            .task(id: day == nil) {
                guard day == nil else { return }
                owed = await JourneyMakeUpPage.openCount(container: context.container)
            }
        } else if FreshStart.clearsMakeUp {
            row("hourglass", "Prayers to make up start fresh", "Only ones from today on count.")
        } else {
            row("hourglass", "Prayers to make up stay", "It doesn't clear what you owe.")
        }
    }

    private var makeUpChoiceLine: String {
        let yours = day == nil ? owed.flatMap { $0 > 0 ? "Your \($0)" : nil } : nil
        return clearMakeUp ? "\(yours ?? "They") reset to zero too." : "\(yours ?? "They") stay on your list."
    }

    private func row(_ icon: String, _ lead: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(lead).font(.body)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    /// One slot and its quiet line: before, the slot says how to begin (the ring is the button); after, Done · Undo; on a
    /// later visit, how to start again · Undo fresh start. The slot keeps its height, so nothing moves.
    @ViewBuilder private var buttons: some View {
        VStack(spacing: 6) {
            ZStack {
                if justBegan {
                    Button { dismiss() } label: { pillLabel("Done") }
                        .buttonStyle(.plain)
                        .transition(swap)
                } else if day != nil {
                    // A later visit: the fresh start it counts from now — not all time (owner, 2026-10-19).
                    Text("Counting since your fresh start on \(startWords)")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(swap)
                }
            }
            .frame(height: 52)
            Button {
                if justBegan { undo() } else if day != nil { askUndo = true } else { dismiss() }
            } label: {
                ZStack {
                    Text(justBegan ? "Undo" : day != nil ? "Undo fresh start" : "Not now")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .id(justBegan ? 0 : day != nil ? 1 : 2)
                        .transition(swap)
                }
                    .frame(minWidth: 160, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // An alert, not a confirmation dialog: iOS 26 drew the dialog as a popover over the Done pill, and a tap on
            // "Bring it back" reached Done under it — the page closed and nothing was undone (Design, 2026-10-19).
            .alert("Bring back your whole history?", isPresented: $askUndo) {
                Button("Bring it back") { undo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Journey will count from your first prayer again.")
            }
        }
        .padding(.top, 8).padding(.bottom, 8)
    }

    private func pillLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(Color.sage)
            .frame(width: 260, height: 52)
            .background(Capsule().fill(Color.sage.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
    }

    /// A soft tick every fifth of a second while held, firmer as it goes; a success tap at the end.
    private func startTicks() {
        ticks?.cancel()
        ticks = Task { @MainActor in
            let steps = Int(Self.holdTime / 0.2)
            for i in 0..<steps {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3 + 0.6 * CGFloat(i) / CGFloat(steps))
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
        }
    }

    private func begin() {
        ticks?.cancel()
        replaced = FreshStart.dayKey.map { ($0, FreshStart.clearsMakeUp) }
        FreshStart.begin(clearMakeUp: clearMakeUp)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.smooth(duration: 0.55)) {
            holding = false
            justBegan = true
            day = FreshStart.dayNumber()
            held = 1
        }
    }

    /// Right after a hold that started again: back to the fresh start it replaced. Otherwise none.
    private func undo() {
        if justBegan, let replaced {
            FreshStart.restore(dayKey: replaced.key, clearsMakeUp: replaced.clears)
        } else {
            FreshStart.undo()
        }
        replaced = nil
        clearMakeUp = FreshStart.clearsMakeUp
        withAnimation(.smooth(duration: 0.45)) {
            justBegan = false
            day = FreshStart.dayNumber()
            held = 0
        }
    }
}

/// Keep · Start fresh, for the prayers to make up: a capsule switch (a fixed two, the guide's "Sadaqah | Community"); the
/// pick slides between them.
private struct FreshStartMakeUpSwitch: View {
    @Binding var clear: Bool
    @Namespace private var pick

    var body: some View {
        HStack(spacing: 0) {
            option("Keep", on: !clear) { clear = false }
            option("Start fresh", on: clear) { clear = true }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Prayers to make up")
    }

    private func option(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Text(title)
                .font(.footnote.weight(on ? .medium : .regular))
                .foregroundStyle(on ? Color.sage : .secondary)
                .padding(.horizontal, 10).frame(height: 28)
                .background {
                    if on { Capsule().fill(Color.sage.opacity(0.16)).matchedGeometryEffect(id: "pick", in: pick) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
