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

    /// From today's prayer day.
    @MainActor static func begin(now: Date = Date()) {
        UserDefaults.standard.set(PrayerDay.key(for: now), forKey: key)
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

/// The page: a leaf in a ring, what a fresh start changes and keeps, and a pill held to begin — the ring draws in
/// with the hold (let go early and it unwinds), then holds Day 1. Opened again later: the day it's on, start again, undo.
/// Excused Mode's look (light title, grey line, a soft card of sage-iconed rows, the outlined pill and its quiet line).
struct FreshStartPage: View {
    @Environment(\.dismiss) private var dismiss
    /// The day it's on (nil = off), and whether it was begun on this visit (the moment's words and Undo).
    @State private var day: Int? = FreshStart.dayNumber()
    @State private var justBegan = false
    /// The hold, 0…1: the ring and the pill's fill.
    @State private var held: CGFloat = 0
    @State private var holding = false
    @State private var ticks: Task<Void, Never>?
    @State private var askUndo = false
    @State private var pageHeight: CGFloat = 0

    /// How long the pill is held to begin.
    static let holdTime = 1.5

    private var startWords: String {
        (FreshStart.start ?? Date()).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    heading
                    Spacer(minLength: 24)
                    ring
                    Spacer(minLength: 24)
                    verse
                    Spacer(minLength: 24)
                    if !justBegan { facts.transition(.opacity) }
                    Spacer(minLength: 8)
                }
                .frame(minHeight: pageHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .scrollBounceBehavior(.basedOnSize)
            buttons
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ticks?.cancel() }
    }

    // MARK: Pieces

    private var heading: some View {
        let (title, line): (String, String) =
            // No date on the day itself: before Fajr the prayer day is still yesterday's date, which reads wrong as "today".
            if justBegan { ("Bismillah", "Your fresh start begins today. Every prayer from here is part of it.") }
            else if let day { ("Fresh start", "Since \(startWords) · Day \(day)") }
            else { ("A fresh start", "However your Journey has gone so far, you can begin again today.") }
        return VStack(spacing: 6) {
            Text(title).font(.system(size: 30, weight: .light, design: .rounded))
                .contentTransition(.opacity)
            Text(line).font(.subheadline).foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }

    /// The hero: a groove, the sage arc the hold draws, and a leaf (new growth; the sunrise is Fajr's, owner) — Day N once it's on.
    private var ring: some View {
        let on = day != nil
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: 12)
            Circle()
                .trim(from: 0, to: on ? 1 : held)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let day {
                VStack(spacing: 0) {
                    Text("Day").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(day)").font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.map { "Fresh start, day \($0)" } ?? "Fresh start, off")
    }

    /// Az-Zumar 39:53, the part that speaks to someone who thinks it's too late: the app's own Quran text and translation
    /// (quran.sqlite, english_hilali.sqlite).
    private var verse: some View {
        VStack(spacing: 8) {
            Text("لا تَقنَطوا مِن رَحمَةِ اللَّهِ")
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 26))
                .environment(\.layoutDirection, .rightToLeft)
            Text("“Despair not of the Mercy of Allah.”").font(.callout).italic()
            Text("Az-Zumar 39:53").font(.footnote).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
    }

    /// What changes and what stays, one line each.
    private var facts: some View {
        VStack(spacing: 0) {
            row("chart.bar", "Your scores and streak count from \(day == nil ? "today" : "your fresh start")")
            Divider().padding(.leading, 52)
            row("clock.arrow.circlepath", "Your history stays. Look back or undo any time")
            Divider().padding(.leading, 52)
            row("hourglass", "Prayers to make up stay with you")
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
        .padding(.horizontal, 20)
    }

    private func row(_ icon: String, _ words: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.sage).frame(width: 24)
            Text(words).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 52)
    }

    /// One pill and its quiet line: hold to begin · Not now; Done · Undo after; on a later visit, hold to start again
    /// (not on its own first day — it would change nothing) · Undo fresh start.
    @ViewBuilder private var buttons: some View {
        VStack(spacing: 6) {
            if justBegan || day == 1 {
                pill("Done") { dismiss() }
            } else {
                holdPill(day == nil ? "Hold to begin" : "Hold to start again today")
            }
            Button {
                if justBegan { undo() } else if day != nil { askUndo = true } else { dismiss() }
            } label: {
                Text(justBegan ? "Undo" : day != nil ? "Undo fresh start" : "Not now")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(minWidth: 160, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // On the button itself: iOS 26 shows it as a popover from the view it's on (on the page, it hung off the top).
            .confirmationDialog("Bring back your whole history?", isPresented: $askUndo, titleVisibility: .visible) {
                Button("Bring it back") { undo() }
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

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(title) }.buttonStyle(.plain)
    }

    /// Held, it fills from the left as the ring draws; let go early, both unwind. A soft tick every fifth of a second,
    /// firmer as it goes; a success tap at the end.
    private func holdPill(_ title: String) -> some View {
        pillLabel(title)
            .background(alignment: .leading) {
                Capsule().fill(Color.sage.opacity(0.22)).frame(width: 260 * held)
            }
            .clipShape(Capsule())
            .scaleEffect(holding ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: holding)
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 60) {
                begin()
            } onPressingChanged: { pressing in
                guard !justBegan else { return }
                holding = pressing
                if pressing {
                    withAnimation(.linear(duration: Self.holdTime)) { held = 1 }
                    startTicks()
                } else {
                    ticks?.cancel()
                    withAnimation(.spring(duration: 0.4)) { held = 0 }
                }
            }
            .accessibilityLabel(title)
            .accessibilityHint("Starts your fresh start from today")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { begin() }
    }

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
        holding = false
        withAnimation(.easeInOut(duration: 0.5)) {
            justBegan = true
            day = FreshStart.dayNumber()
            held = 1
        }
    }

    private func undo() {
        FreshStart.undo()
        withAnimation(.easeInOut(duration: 0.4)) {
            justBegan = false
            day = nil
            held = 0
        }
    }
}
