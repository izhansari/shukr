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
                    factsOrWelcome
                    Spacer(minLength: 12)
                }
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .scrollBounceBehavior(.basedOnSize)
            buttons
        }
        .background { ZStack { theme.surface; glow }.ignoresSafeArea() }
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ticks?.cancel() }
    }

    // MARK: Pieces

    private var heading: some View {
        let (title, line): (String, String) =
            // No date on the day itself: before Fajr the prayer day is still yesterday's date, which reads wrong as "today".
            if justBegan { ("Bismillah", "Your fresh start begins today.") }
            else { ("A fresh start", "Your past doesn't define you. Start counting again from today.") }
        return VStack(spacing: 8) {
            ZStack {   // the old and new words overlap while they swap, never side by side
                // The app's page title (Give to Causes, Kinds of giving): 30 pt light rounded (owner, 2026-10-19: "match it").
                Text(title).font(.system(size: 30, weight: .light, design: .rounded))
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
            .frame(width: size - 92)
            // What to do, in the ring you do it to — quiet, low in the ring, outside the verse's centring (owner,
            // 2026-10-19: "Center all the ayah stuff in center of the ring. and hold the ring make it look clearly secondary
            // and calmly animate it with something sleek").
            FreshStartHint(text: "Hold the ring")
                .offset(y: size * 0.32)
                .opacity(on || holding ? 0 : 1)
                .animation(.smooth(duration: 0.3), value: holding)
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
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 21))
                .environment(\.layoutDirection, .rightToLeft)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("“Despair not of the Mercy of Allah.”").font(.footnote).italic()
            Text("Az-Zumar 39:53").font(.caption2).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// Before: what changes and what stays. After the hold, the app answers back in the same room (owner, 2026-10-19: "the
    /// copy on the page not changing much after the reset feels cold … we just made an effort to be better"): the list
    /// fades and blurs away and a few warm words come in — both stay laid out, so nothing moves.
    private var factsOrWelcome: some View {
        ZStack {
            facts
                .opacity(justBegan ? 0 : 1)
                .blur(radius: justBegan && !reduceMotion ? 6 : 0)
                .allowsHitTesting(!justBegan)
                .accessibilityHidden(justBegan)
            welcome
                .opacity(justBegan ? 1 : 0)
                .blur(radius: !justBegan && !reduceMotion ? 6 : 0)
                .animation(.smooth(duration: 0.7).delay(justBegan ? 0.35 : 0), value: justBegan)
                .accessibilityHidden(!justBegan)
        }
    }

    /// A few words back after the hold. The hadith: Sahih al-Bukhari 6464 (also Muslim 783), from 'Aishah — written from
    /// memory, to check with the other sources (CLAUDE.md's ⚠️ note).
    private var welcome: some View {
        VStack(spacing: 12) {
            Text("One prayer at a time.").font(.system(size: 22, weight: .light, design: .rounded))
            Text("“The most beloved of deeds to Allah are those done consistently, even if they are small.”")
                .font(.callout).italic()
            Text("Sahih al-Bukhari 6464").font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
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

    /// Prayers to make up: kept by default; before the hold, a toggle to reset them too (owner, 2026-10-19: "the switch looks
    /// weak and out of place. maybe a toggle button?"). Its line reads the count once: "Your 412 stay on your list" /
    /// "start again from zero". After, what was chosen. Laid out as every other row, so the hourglass never moves.
    @ViewBuilder private var makeUpRow: some View {
        if canHold {
            row("hourglass", "Reset prayers to make up", makeUpChoiceLine, detailID: clearMakeUp) {
                Toggle("Reset prayers to make up", isOn: $clearMakeUp.animation(.snappy(duration: 0.25)))
                    .labelsHidden()
                    .tint(Color.sage)
            }
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
        return clearMakeUp ? "\(yours ?? "They") start again from zero." : "\(yours ?? "They") stay on your list."
    }

    private func row(_ icon: String, _ lead: String, _ detail: String) -> some View {
        row(icon, lead, detail, detailID: false) { EmptyView() }
    }

    /// One row: the symbol on the lead's first line, a lead and a quieter line, and an optional control at the end,
    /// centred on both lines (it never moves the symbol or the words).
    private func row<Trailing: View>(_ icon: String, _ lead: String, _ detail: String, detailID: Bool,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: icon).font(.body).foregroundStyle(.secondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lead).font(.body)
                    ZStack(alignment: .leading) {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                            .id(detailID).transition(swap)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
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
                    // Under the date line, Undo fresh start is a size and a shade quieter (owner, 2026-10-19: "both have
                    // same type face... make it clearer undo is secondary to it").
                    Text(justBegan ? "Undo" : day != nil ? "Undo fresh start" : "Not now")
                        .font(!justBegan && day != nil ? .footnote : .subheadline)
                        .foregroundStyle(!justBegan && day != nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
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

    /// Sage light rising from the bottom of the page, as the Live Activity glows when a prayer is marked (LAWash): faint at
    /// rest, growing with the hold, blooming when it completes (owner, 2026-10-19: "a green glow curving and reaching out
    /// from bottom slightly"). Its strength rides `held`, so it follows the hold's own animation and winds back with it.
    private var glow: some View {
        let strength = justBegan ? 1.0 : 0.25 + 0.45 * held
        return GeometryReader { g in
            EllipticalGradient(colors: [Color.sage.opacity(0.45), Color.sage.opacity(0)], center: .center,
                               startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: g.size.width * 1.8, height: 520)
                .position(x: g.size.width / 2, y: g.size.height + 80)
                .scaleEffect(justBegan ? 1.08 : 1, anchor: .bottom)
        }
        .opacity(strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// "Hold the ring": a quiet caption with a soft light passing over it every few seconds — a pause, then one sweep (none
/// with Reduce Motion).
private struct FreshStartHint: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).font(.caption.weight(.medium))
        label.foregroundStyle(.tertiary)
            .overlay {
                if !reduceMotion {
                    KeyframeAnimator(initialValue: CGFloat(-0.6), repeating: true) { x in
                        GeometryReader { g in
                            LinearGradient(colors: [.clear, Color.primary.opacity(0.75), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: g.size.width * 0.5)
                                .offset(x: x * g.size.width)
                        }
                        .mask(label)
                    } keyframes: { _ in
                        LinearKeyframe(-0.6, duration: 1.6)
                        CubicKeyframe(1.1, duration: 1.4)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}
