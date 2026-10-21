//
//  SundayOffer.swift
//  shukr
//
//  The Sunday offer: one step up the goal ladder after three strong weeks, one step back after two that weren't (rules:
//  PrayerMetrics.goalOffer, Fable). Once, on Sunday's first open of the app, on the Salah page (owner, 2026-10-21, on Zoe's
//  A · B · C: "B"). The guide's glass sheet: your goal as its window's thirds, sweeping to the offered step; a light title,
//  one grey line, one ink pill, a quiet line (owner, on Zoe's first try: "a massive text block … no visual … no clear
//  button"; on Frank's canvas https://claude.ai/artifact/T1hh4B26y7iP93z1h8Ypj4: "hero and sunday sheets are great"; its look
//  is parked to beautify later, Plan item sunday-sheet-beautify). Built from Zoe's WIP (board/zoe-goal-ladder-wip.patch):
//  her timing, her thirds ring and its sweep; the words are the canvas's.
//

import SwiftUI

/// A goal as its window's thirds (owner, 2026-10-21, on Your goal's ring: "we need to make sure the ring abides by our new
/// thirds style"): Opening green · Middle yellow · Closing red, the thirds the goal accepts lit and the rest faint; Prayed
/// adds a thin grey ring outside (even after the window). `level` animates: one step lights or dims one third.
struct GoalThirdsRing: View, Animatable {
    /// 1 the Opening … 3 the whole window, 4 the window and after.
    var level: Double
    var size: CGFloat = 140
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    static func level(_ goal: PrayerGoal) -> Double {
        switch goal {
        case .perfect: 1
        case .onTime: 2
        case .inWindow: 3
        case .prayed: 4
        }
    }

    var body: some View {
        let band: CGFloat = 11
        let colors = [PrayerScoring.color(for: 1), PrayerScoring.color(for: 0.9), PrayerScoring.color(for: 0.7)]
        ZStack {
            // One unbroken ring, the colour changing at each third (owner, 2026-10-21, on a ring with gaps between its
            // parts: "it's like broken at the divides").
            ForEach(0..<3, id: \.self) { k in
                let lit = min(max(level - Double(k), 0), 1)
                let from = Double(k) / 3, to = Double(k + 1) / 3
                Circle().trim(from: from, to: to)
                    .stroke(colors[k].opacity(0.16), style: StrokeStyle(lineWidth: band, lineCap: .butt))
                // Lit from the third's start, so a step down drains it back and a step up fills it.
                Circle().trim(from: from, to: from + (to - from) * lit)
                    .stroke(colors[k], style: StrokeStyle(lineWidth: band, lineCap: .butt))
                    .opacity(lit > 0.01 ? 1 : 0)
            }
            .rotationEffect(.degrees(-90))
            .padding(band / 2 + 8)
            Circle()
                .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [2, 5]))
                .opacity(min(max(level - 3, 0), 1))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension PrayerGoal {
    /// The step in a few words, inside the offer's ring and on its pill: "the Opening", "before Closing", "in its window",
    /// "every prayer".
    var offerName: String {
        switch self {
        case .perfect: "the Opening"
        case .onTime: "before Closing"
        case .inWindow: "in its window"
        case .prayed: "every prayer"
        }
    }
}

/// The offer as a sheet. Words (owner, 2026-10-21, "make it speak better"): up — "3 strong weeks in a row", "Every prayer in its
/// window, three weeks running. Ready for the next step?", "Aim for before Closing" · "Not now"; back — "A tough couple of
/// weeks", "Every prayer in its window has been hard to keep lately. For now, count every prayer you pray, made up ones too.",
/// "Step back for now" · "Keep my goal".
struct GoalOfferSheet: View {
    let offer: PrayerMetrics.GoalOffer
    let from: PrayerGoal
    let weekStart: Date
    /// My Dev Stuff's look at it: the pill and the quiet line only close it (your goal and the week's answer untouched).
    var preview = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var level: Double
    @State private var swept = false
    @State private var height: CGFloat = 520

    init(offer: PrayerMetrics.GoalOffer, from: PrayerGoal, weekStart: Date, preview: Bool = false) {
        self.offer = offer
        self.from = from
        self.weekStart = weekStart
        self.preview = preview
        _level = State(initialValue: GoalThirdsRing.level(from))
    }

    private var up: Bool { if case .up = offer { true } else { false } }
    private var next: PrayerGoal { offer.goal }

    private var title: String {
        up ? "\(PrayerMetrics.stepUpWeeks) strong weeks in a row" : "A tough couple of weeks"
    }
    private var line: String {
        let aim = from.aim.prefix(1).uppercased() + from.aim.dropFirst()
        if up {
            let weeks = PrayerMetrics.stepUpWeeks == 3 ? "three" : "\(PrayerMetrics.stepUpWeeks)"
            return "\(aim), \(weeks) weeks running. Ready for the next step?"
        }
        let then = next == .prayed ? "For now, count every prayer you pray, made up ones too." : "For now, aim for \(next.aim)."
        return "\(aim) has been hard to keep lately. \(then)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                GoalThirdsRing(level: level, size: 164)
                VStack(spacing: 2) {
                    Text(swept ? (up ? "aim for" : "for now") : "your goal")
                        .font(.system(size: 12, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    Text(swept ? next.offerName : from.offerName)
                        .font(.system(size: 17, weight: .light, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                }
                .frame(width: 118)
            }
            .padding(.top, 34)
            Text(title)
                .font(.system(size: 26, weight: .light, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 20).padding(.horizontal, 24)
            Text(line)
                .font(.system(size: 16, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 8)
            // Ink, not sage (no sage on the Salah page — owner, 2026-10-15).
            Button {
                triggerSomeVibration(type: .light)
                if !preview {
                    GoalOffers.answer(weekStart)
                    PrayerGoal.set(next)
                }
                dismiss()
            } label: {
                Text(up ? "Aim for \(next.offerName)" : "Step back for now")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(scheme == .dark ? Color.black : .white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(scheme == .dark ? Color.white : .black))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28).padding(.top, 24)
            Button {
                if !preview { GoalOffers.answer(weekStart) }
                dismiss()
            } label: {
                Text(up ? "Not now" : "Keep my goal").font(.system(size: 15, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .frame(width: 200, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        // The prayer editor's glass sheet (owner, 2026-10-21: "glass sheet"): Liquid Glass on iOS 26, a material before.
        .modifier(EditorSheetGlass())
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .task {
            // The ring shows your step first, then sweeps to the one it's offering.
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeInOut(duration: 0.9)) { level = GoalThirdsRing.level(next) }
            withAnimation(.easeInOut(duration: 0.35).delay(0.45)) { swept = true }
        }
    }
}

/// The offer the sheet is up for.
struct GoalOfferItem: Identifiable {
    let offer: PrayerMetrics.GoalOffer
    let from: PrayerGoal
    let weekStart: Date
    var id: Date { weekStart }
}

/// The Sunday offer on the Salah page (owner, 2026-10-21, on Zoe's A · B · C: "B" — the first open of the app that Sunday, so
/// nobody misses it because they didn't visit Journey): once the page is the user's (no late-mark question, setup or tour up),
/// read off the main thread from Journey's log at your goal as it is now; once that week, answered or swiped away. DEBUG
/// `-demoGoalOffer up|down` shows it any day.
struct GoalOfferHost: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var item: GoalOfferItem?
    @State private var checking = false
    @State private var asked: Date?

    func body(content: Content) -> some View {
        content
            .sheet(item: $item, onDismiss: { if let w = asked { GoalOffers.answer(w) } }) { i in
                GoalOfferSheet(offer: i.offer, from: i.from, weekStart: i.weekStart)
                    .stageCover("goalOffer")
            }
            .task { check() }
            .onChange(of: JourneyStore.shared.log?.version) { _, _ in check() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in check() }
    }

    /// This prayer day's week start, when today is the week's first day and its offer hasn't been answered.
    private static func sundayWeek(now: Date = Date()) -> Date? {
        let today = PrayerDay.start(for: now)
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: today)?.start,
              Calendar.current.isDate(start, inSameDayAs: today), !GoalOffers.answered(start) else { return nil }
        return start
    }

    private func check() {
        guard item == nil, asked == nil, !checking else { return }
        var demo: String?
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoGoalOffer"), args.indices.contains(i + 1) { demo = args[i + 1] }
        #endif
        let week = demo != nil ? Calendar.current.dateInterval(of: .weekOfYear, for: PrayerDay.start())?.start : Self.sundayWeek()
        guard let weekStart = week else { return }
        // Only from a log built at your goal as it is now.
        guard let log = JourneyStore.shared.log, log.goal == PrayerGoal.current, !JourneyStore.shared.stale else {
            JourneyStore.shared.loadIfNeeded(container: context.container, today: PrayerDay.start())   // lands → check
            return
        }
        checking = true
        let excused = Excused.Days(), now = Date()
        Task {
            if let demo {
                // On Prayed there's no step back, so the picture pretends In its window; on the Opening, no step up: Middle.
                let g = demo == "down" ? (log.goal.down == nil ? PrayerGoal.inWindow : log.goal)
                    : (log.goal.up == nil ? PrayerGoal.onTime : log.goal)
                let offer: PrayerMetrics.GoalOffer? = demo == "down" ? g.down.map { .down($0) } : g.up.map { .up($0) }
                if let offer { await present(GoalOfferItem(offer: offer, from: g, weekStart: weekStart)) }
                checking = false
                return
            }
            let offer = await Task.detached(priority: .userInitiated) {
                PrayerMetrics.goalOffer(in: log, excused: excused, now: now)
            }.value
            if let offer { await present(GoalOfferItem(offer: offer, from: log.goal, weekStart: weekStart)) }
            checking = false
        }
    }

    /// A moment after the page is up, and never over another question, the setup or the tour.
    @MainActor private func present(_ i: GoalOfferItem) async {
        try? await Task.sleep(for: .seconds(1.2))
        guard item == nil, LateMarkAsk.shared.current == nil, !FirstRunSetup.isShowing, !TourRuntime.shared.active else { return }
        asked = i.weekStart
        item = i
    }
}

extension View {
    func goalOfferAsk() -> some View { modifier(GoalOfferHost()) }
}
