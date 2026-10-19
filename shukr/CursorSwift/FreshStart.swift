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

    /// Day 1 on the fresh start's own day, by the prayer day.
    static func dayNumber(now: Date = Date()) -> Int? {
        guard let start else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: PrayerDay.start(for: now)).day ?? 0
        return max(days, 0) + 1
    }

    /// From today's prayer day — or, between midnight and Fajr, the one that starts at Fajr: the prayer day still showing
    /// then is yesterday's and already over (Isha ended at 11:59 PM), and starting it would put its record (a missed Isha)
    /// inside the fresh start (Fable's audit #3). Day 1 until Fajr, then Day 1 again.
    @MainActor static func begin(now: Date = Date()) {
        let calendarDay = Calendar.current.startOfDay(for: now)
        let key = calendarDay > PrayerDay.start(for: now) ? PrayerNotificationID.dayKey(calendarDay) : PrayerDay.key(for: now)
        UserDefaults.standard.set(key, forKey: Self.key)
        NotificationCenter.default.post(name: changed, object: nil)
        PrayerStats.changed()
    }

    @MainActor static func undo() {
        UserDefaults.standard.removeObject(forKey: key)
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
    /// The hold, 0…1: the arc.
    @State private var held: CGFloat = 0
    @State private var holding = false
    @State private var ticks: Task<Void, Never>?
    @State private var askUndo = false
    @State private var pageHeight: CGFloat = 0

    /// How long the ring is held to begin.
    static let holdTime = 1.5
    static let ringSize: CGFloat = 224

    private var startWords: String {
        (FreshStart.start ?? Date()).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    private var startShort: String {
        (FreshStart.start ?? Date()).formatted(.dateTime.month(.abbreviated).day())
    }
    /// Held to begin, or to start again on a later day (not on its own first day — it would change nothing).
    private var canHold: Bool { day == nil || (!justBegan && (day ?? 0) > 1) }
    /// A later visit, holding to start again: the old arc stays faint under the new one.
    private var restarting: Bool { day != nil && !justBegan && holding }
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
            else if day == 1 { ("Fresh start", "Since today. You can start again from tomorrow.") }
            else if day != nil { ("Fresh start", "Since \(startWords)") }   // the ring holds Day N (a fact shows once)
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
        let on = day != nil
        let size = Self.ringSize
        return ZStack {
            NeuLiftCard(shape: Circle(), lift: on ? 1 : 0)
            Circle().inset(by: 16).stroke(Color.primary.opacity(0.06), lineWidth: 10)
            if restarting {
                Circle().inset(by: 16).stroke(Color.sage.opacity(0.25), lineWidth: 10)
            }
            Circle().inset(by: 16)
                .trim(from: 0, to: on && !restarting ? 1 : held)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(held > 0.001 || on ? 1 : 0)
            ZStack {
                if let day {
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
        .accessibilityLabel(day.map { "Fresh start, day \($0)" } ?? "Fresh start. Despair not of the Mercy of Allah.")
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
        }
        .multilineTextAlignment(.center)
    }

    /// What a fresh start changes and what it keeps: a flat list, grey symbols (nothing here is tapped), a line each
    /// and a quieter line under it.
    private var facts: some View {
        VStack(spacing: 0) {
            row("chart.bar", day == nil || justBegan ? "Your stats start from today" : "Your stats start from \(startShort)",
                "Your streak and scores count from here.")
            Divider().padding(.leading, 40)
            row("photo.on.rectangle.angled", "Nothing is deleted", "Your prayers, photos and places stay.")
            Divider().padding(.leading, 40)
            row("hourglass", "Prayers to make up stay", "It doesn't clear what you owe.")
            Divider().padding(.leading, 40)
            row("arrow.uturn.backward", "See it all any time", "Look back, or undo to bring it all back.")
        }
        .padding(.horizontal, 24)
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
                if justBegan || day == 1 {
                    Button { dismiss() } label: { pillLabel("Done") }
                        .buttonStyle(.plain)
                        .transition(swap)
                } else {
                    Text(day == nil ? "Hold the ring to begin" : "Hold the ring to start again today")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .id(day == nil)
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
        FreshStart.begin()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.smooth(duration: 0.55)) {
            holding = false
            justBegan = true
            day = FreshStart.dayNumber()
            held = 1
        }
    }

    private func undo() {
        FreshStart.undo()
        withAnimation(.smooth(duration: 0.45)) {
            justBegan = false
            day = nil
            held = 0
        }
    }
}
