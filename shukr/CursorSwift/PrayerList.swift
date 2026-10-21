//
//  PrayerList.swift
//  shukr
//
//  The Salah page's prayer list: TodaysPrayerListView, its rows (PrayerButton — the one row gesture, the mark circle,
//  the marked row's buttons, the time editor and its held saves) and the DEBUG hit-area tint. Moved out of
//  PrayerTimesAndTracker.swift (cleanup-map tangle 1, step 5).
//

import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications
import WidgetKit

// MARK: - Prayer List

struct TodaysPrayerListView: View {

    @Environment(PrayerViewModel.self) var viewModel
    @Binding var showDailyAyahView: Bool
    @Environment(\.circleTheme) private var theme
    /// Pills stand apart; the other looks keep their rows close with dividers.
    private var spacing: CGFloat { theme.rowSpacing }
    private var showsDividers: Bool { theme.showsRowDividers }
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: RowMotion { RowMotion.resolved(motionRaw) }
    /// The day page's picked-row band glides between rows in this space (DayPickBand).
    @Namespace private var pickSpace
    /// The day page's pick (DayPageState; the ring is MainCircleView's). No day card here: that's Journey's (owner,
    /// 2026-10-16: "the salah stays simple").
    private var dayState = DayPageState.shared
    /// Done prayers fold out of the list so it only shows what's left; all five come back once
    /// the day is complete. A prayer just marked stays while the circle's marking moment runs (the stage's `heldRow`:
    /// one clock, the moment's), and then for as long as its post-salah pill is up (owner: "it's really annoying when I
    /// mark something as done and then I go to edit it … it goes away") — not the day's last prayer: all five come back
    /// then anyway, and holding it would keep the day's page waiting.
    @Environment(PagerLiveState.self) private var pagerLive: PagerLiveState?
    private var lingering: Set<String> {
        var rows: Set<String> = CircleStage.shared.heldRow.map { [$0] } ?? []
        if let pill = pagerLive?.postSalahNudge, viewModel.todaysPrayers.contains(where: { !$0.isCompleted }) {
            rows.insert(pill)
        }
        if let row = PrayerRowActions.shared.name { rows.insert(row) }   // G · its buttons are up
        return rows
    }
    /// "3 done" row tapped: show the done ones too (to check a score or unmark one).
    /// "N done" tapped (shared with the soft looks' footer in the chrome, SoftDoneFooter).
    private var fold = PrayerListFold.shared
    private var showDone: Bool {
        get { fold.showDone }
        nonmutating set { fold.showDone = newValue }
    }
    /// Perfect day: bumps to bounce the footer's sparkles; `demoPerfect` shows the footer
    /// for the DEBUG "Test Perfect Day" row even when today isn't one.
    @State private var perfectPulse = 0
    @State private var demoPerfect = false

    @ViewBuilder private func doneFooter(done: Int, foldedCount: Int, allDone: Bool, visibleIsEmpty: Bool,
                                         divider: Bool) -> some View {
                // The folded ones, as a footer row: a divider like the rows', then "✓ 3 done ⌄"
                // centred with the same air above and below as a row (2026-09-25 — the old line
                // hung under the list with a bare 10 pt gap and no divider, which read off).
                // Kept while the last prayer's row lingers (the circle's flourish): hiding it at the
                // mark shortened the list and dropped the circle ~19 pt mid-moment (2026-09-27).
        if (foldedCount > 0 || showDone) && (!allDone || !lingering.isEmpty) {
                    VStack(spacing: 0) {
                        if divider && !visibleIsEmpty {
                            Divider()
                                .frame(height: 1)
                                .background(Color(.secondarySystemFill))
                                .padding(.horizontal, 25)
                        }
                        Button {
                            triggerSomeVibration(type: .light)
                            showDone.toggle()   // the page animates the fold itself (SalahPageContent)
                            TourRuntime.shared.event(.foldTapped)   // the user's tap, not a fold the app made
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                // Same words open or closed (swapping to "hide done" morphed oddly
                                // mid-spring — owner); only the chevron turns.
                                Text("\(done) done")
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showDone ? 180 : 0))
                            }
                            .font(.footnote)
                            .fontDesign(.rounded)
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, visibleIsEmpty ? 0 : 12)
                            .padding(.bottom, 2)
                            .contentShape(Rectangle())
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("doneFold", $0) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, visibleIsEmpty ? 0 : spacing)
                    .transition(.opacity)
                }

    }

    @ViewBuilder private func perfectLine(perfect: Bool) -> some View {
                // All five Early today.
        if (perfect && lingering.isEmpty) || demoPerfect {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: perfectPulse)
                        Text("perfect day")
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
    }

    var body: some View {
        let _ = viewModel.revision   // redraw after marks / edits, as on objectWillChange (step 8)
        // Only prayers that are loaded: PrayerButton fatalErrors on a missing one, and
        // this list is now in the tree from launch, before loadTodaysPrayerObjects runs.
        let loaded = viewModel.orderedPrayerNames.filter { name in viewModel.todaysPrayers.contains { $0.name == name } }
        let done = Set(loaded.filter { name in viewModel.todaysPrayers.first { $0.name == name }?.isCompleted == true })
        let allDone = !loaded.isEmpty && done.count == loaded.count
        let visible = loaded.filter { name in
            !done.contains(name) || lingering.contains(name) || showDone || (allDone && lingering.isEmpty)
        }
        let foldedCount = loaded.count - visible.count
        let perfect = allDone && loaded.allSatisfy { name in   // all five Early
            (viewModel.todaysPrayers.first { $0.name == name }?.numberScore ?? 0) >= 0.9999
        }

        // Today's look: the "N done" footer and "perfect day" sit inside the bordered card, as before. The soft
        // looks (SalahLook.swift) draw the card round the rows only, with those two lines under it (owner,
        // 2026-10-01: "move "done" text outside of the prayer list card").
        let outside = theme.listFooterOutside
        // The day page: all five marked and the page up (the tour's practice day isn't one).
        let dayPage = allDone && dayState.up && !TourRuntime.shared.active
        // A whole excused day: every prayer excused, none marked, and every window over — only then the card keeps its
        // size with a symbol and a line in it. Through the day the rows stay, each dot pausing once its window has begun
        // (owner, 2026-10-15: "show the pause in them once we are in that prayers window. when the full day ends, then we
        // show the card").
        let ranges = Excused.ranges
        let now = Date()
        let excusedDay = loaded.count == 5 && done.isEmpty && Excused.isActive
            && viewModel.todaysPrayers.allSatisfy { Excused.covers(start: $0.startTime, end: $0.endTime, in: ranges) && $0.endTime <= now }
        VStack(spacing: 0) {
            if !(outside && visible.isEmpty) {
                Group {
                VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                if excusedDay {
                    ExcusedDayCard(line: Excused.current.map { "You're excused · \(Excused.dayLine($0))" } ?? "You're excused")
                } else {
                ForEach(Array(visible.enumerated()), id: \.element) { index, prayerName in
                    VStack(spacing: 0) {
                        if let row = PrayerButton(name: prayerName, viewModel: viewModel) {
                            row.padding(.bottom, index == visible.count - 1 ? 0 : spacing)
                        }

                        if index < visible.count - 1 && showsDividers {
                            Divider()
                                .frame(height: 1)
                                .background(Color(.secondarySystemFill))
                                .padding(.top, -spacing / 2 - 0.5)
                                .padding(.horizontal, 25)
                        }
                    }
                    // RowMotion (the look prototype); today's = slide in, shrink out. Reduce Motion: a fade.
                    .transition(reduceMotion ? .opacity : motion.transition)
                }

                    if !outside {
                        doneFooter(done: done.count, foldedCount: foldedCount, allDone: allDone,
                                   visibleIsEmpty: visible.isEmpty, divider: true)
                        perfectLine(perfect: perfect)
                    }
                }
                }
                .modifier(SalahListInsets())   // the raised list's band reaches the card's edges (Journey's card too)
                }
                // The day page's picked band, behind every row (DayPickBandLayer).
                .background {
                    DayPickBandLayer(picked: dayPage ? dayState.picked.flatMap { DayRing.order.indices.contains($0) ? DayRing.order[$0] : nil } : nil,
                                     look: theme.list)
                }
                .environment(\.dayPickSpace, pickSpace)
                // The Salah tab keeps only the prayer list: the day card is Journey's (owner, 2026-10-16: "the salah
                // stays simple. the journey one gets extra stuff").
                .modifier(SalahLookCard(raised: allDone && DayPageState.shared.lifted && !TourRuntime.shared.active))
                // The tour's list steps put their bubble above this, never over the rows (audit J).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("prayerList", $0) }
            }
            if outside {
                // "N done" lives in the chrome above the bottom bar (SoftDoneFooter); only its count is set here.
                perfectLine(perfect: perfect)
            }
        }
        .onChange(of: outside && (foldedCount > 0 || showDone) && (!allDone || !lingering.isEmpty) ? done.count : -1,
                  initial: true) { _, count in
            fold.softFooterCount = count >= 0 ? count : nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .perfectDay)) { note in
            // ▶︎ / DEBUG: the footer shows a while even when today isn't a perfect day.
            if note.object as? Bool == true {
                withAnimation { demoPerfect = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { withAnimation { demoPerfect = false } }
            }
        }
        // The cascade (the stage starts it once the mark's moment is over): a light tap per dot as they pop
        // (PrayerButton, on the same count), then the sparkles bounce.
        .task(id: CircleStage.shared.perfectCascade) {
            guard CircleStage.shared.perfectCascade > 0,
                  await CircleGate.pause(CircleMotion.perfectBeatDuration) else { return }
            for i in 0..<5 {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5 + 0.1 * Double(i))
                guard await CircleGate.pause(CircleMotion.perfectStepDuration) else { return }
            }
            guard await CircleGate.pause(CircleMotion.perfectStepDuration * 1.8) else { return }
            perfectPulse += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        // A marked row folds when the circle's moment and its pill have both let it go.
        .animation(motion.animation(springy: CircleMotion.rowFold).map { CircleMotion.movement($0, reduced: reduceMotion) },
                   value: lingering)
        .onChange(of: allDone) { _, isDone in
            if isDone { showDone = false }   // the day's complete: everything's back anyway
        }
        // The list closed: folded again next time, as when this was the list's own @State (shared now with the soft
        // looks' footer; it stayed open until a relaunch — Sami's audit).
        .onDisappear { showDone = false }
        // The day page over (a row unmarked, the day turned): nothing picked, the front up. On `allDone`, not `dayPage`:
        // a push drops `up` too, and the back must still be there on the way back (Bradley's review).
        .onChange(of: allDone) { _, done in if !done { dayState.leaveDay() } }

    }

}

#if DEBUG
/// `-debugHitAreas old|new` tints where a tap marks a prayer in the list (to compare the old dot
/// with the new circle). DEBUG only.
enum HitAreaDebug {
    static let mode = UserDefaults.standard.string(forKey: "debugHitAreas")
    static let tint = Color.red.opacity(0.28)
    /// Laid over the 14 pt dot: the old Button was the dot itself; now a circle of `markRadius`.
    @ViewBuilder static var overlay: some View {
        switch mode {
        case "old": Circle().fill(tint).frame(width: 14, height: 14)
        case "new": Circle().fill(tint).frame(width: PrayerButton.markRadius * 2, height: PrayerButton.markRadius * 2)
        default: EmptyView()
        }
    }
}
#endif

// MARK: - Prayer Button


import MapKit
struct PrayerButton: View {
    /// The row's dot answering a mark.
    private static let dotPress = Animation.spring(response: 0.1, dampingFraction: 0.7)
    /// An unmark from the row's alert: the page settles back (score → prayer, the list's rows) in one ease.
    private static let unmarkFade = Animation.easeInOut(duration: 0.4)
    @Environment(SharedStateClass.self) var sharedState
    @Environment(PrayerViewModel.self) var viewModel
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0


    
    @State private var toggledText: Bool = false
    /// G · a prayed row's tap: its score where the name sits, in step with the time's flip (3 s, a second tap undoes).
    @State private var scoreShown = false
    @State private var scoreShownTask: Task<Void, Never>?
    /// A Jumu'ah row's tap: "at <masjid>" in a line under the name for a few seconds (decision jumuah-name-render B).
    @State private var masjidLine = false
    @State private var masjidLineTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The masjid line's height (a caption line, with the text size), so it hangs just under the row's name.
    @ScaledMetric(relativeTo: .caption) private var masjidLineHeight: CGFloat = 16
    #if DEBUG
    /// `-demoJumuahRow <masjid>`: the Jumu'ah row opens its masjid's line (screenshots).
    static let demoMasjidLine = Notification.Name("PrayerButton.demoMasjidLine")
    #endif
    /// The dot's centre in the row (`rowSpace`), for `rowGesture`.
    @State private var dotCenter = CGPoint(x: 23, y: 22)
    /// Bumps when this prayer is marked done, popping the dot (CompletionDotPop).
    @State private var completionPulse = 0
    @AppStorage(PrayerDotStyle.key) private var dotStyleRaw = PrayerDotStyle.muted.rawValue
    @Environment(\.circleTheme) private var theme
    @State private var showMarkIncompleteAlert = false // State for showing alert
    @State private var showTimePicker = false
    /// The day page: a saved edit waits for the sheet to go down, then plays (CircleMotion.dayEdit) where it can be seen.
    /// The editor's saves held while the day page is up: its ring and score move once the sheet is out of the way.
    @State private var pendingEdit: HeldEdit?
    
    private func handlePrayerButtonPress() {
        // Not a prayer to come, unless it's marked: a marked prayer always unmarks (mark audit #8).
        if !isFuturePrayer || prayerObject.isCompleted {
            // The tour lets only its own moves through (Ben's G1 / G2): a light no otherwise.
            guard TourRuntime.shared.allows(marking: !prayerObject.isCompleted, prayerObject) else {
                TourRuntime.shared.nudge()   // the tour: the thing to touch pulses (no buzz — owner)
                return
            }
            if !prayerObject.isCompleted {
                // G · the prayer on now marked from the list: its row takes the post-salah moment (PrayerRowActions),
                // unless it's the day's last prayer (the day page comes) or the tour runs.
                if look.behavesLikeG, isCurrentPrayer, !TourRuntime.shared.active,
                   viewModel.todaysPrayers.filter({ !$0.isCompleted }).count > 1 {
                    PrayerRowActions.shared.name = prayerObject.name
                }
                // Its time over: ask first, in its time or making it up (LateMarkAsk, prayer-metrics phase 6).
                if LateMarkAsk.wouldBeLate(prayerObject) {
                    let row = prayerObject, vm = viewModel
                    LateMarkAsk.shared.askBeforeMarking(row) { inTime in
                        vm.markLate(row, inTime: inTime)
                        if let container = row.modelContext?.container { MilestoneCelebration.shared.check(container: container) }
                    }
                    return
                }
                viewModel.togglePrayerCompletion(for: prayerObject)   // the post-salah pill follows (.prayerCompleted)
                TourRuntime.shared.event(.marked(prayerObject, viewModel))   // the tour's Mark step / a first mark
                if let container = prayerObject.modelContext?.container { MilestoneCelebration.shared.check(container: container) }
            }
            else if !UnmarkPrompt.ask(for: prayerObject, onUnmark: {
                withAnimation(Self.unmarkFade) { viewModel.togglePrayerCompletion(for: prayerObject) }
            }) {
                showMarkIncompleteAlert = true   // another overlay up: the system alert
            }
        }
    }
    
    let prayerObject: PrayerModel
    let name: String
        
    /// Nil when today's rows don't hold that prayer (the day turning over mid-render, no times yet): the list skips the
    /// row instead of crashing (App Store crash safety — was a fatalError).
    init?(name: String, viewModel: PrayerViewModel) {
        guard let foundPrayer = viewModel.todaysPrayers.first(where: { $0.name == name }) else {
            print("⚠️ PrayerButton: no row for \(name) today — row skipped")
            return nil
        }
        self.prayerObject = foundPrayer
        self.name = name
    }
  
    private var nameToDisplay: String{
        let isTodayFriday = Calendar.current.component(.weekday, from: Date()) == 6
        if (name == "Dhuhr" && isTodayFriday){ return "Jummah" }
        else { return name }
    }
    
    private var look: SalahLook { theme.list }
    /// On now: started, not marked, not over.
    private var isCurrentPrayer: Bool { !isFuturePrayer && !prayerObject.isCompleted && prayerObject.endTime > Date() }

    /// The row's surface for the Salah look (SalahLook.swift). Pills: upcoming and missed ones raised, the
    /// current one pressed in, done ones flat on the page (their dot carries the score). Quiet: only the
    /// current one pressed in. Card / well: the rows sit on the card. Today's: the old plain fill.
    /// The day page's picked row (by its row or its fifth): raised like the prayer on now (owner, 2026-10-16).
    private var pickedOnDayPage: Bool {
        guard DayPageState.shared.up, let i = DayPageState.shared.picked, DayRing.order.indices.contains(i) else { return false }
        return DayRing.order[i] == prayerObject.name
    }

    @ViewBuilder private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if pickedOnDayPage {
            Color.clear   // the list draws the picked band behind all its rows (DayPickBandLayer)
        } else {
        switch look {
        case .today:
            // On a tinted page (Soft ring with Today's look) the plain fill drew black slabs: see-through then.
            RoundedRectangle(cornerRadius: 13).fill(theme.rowFill(backgroundColor))
        case .pills:
            if isCurrentPrayer { NeuPressed(shape: shape) }
            else if prayerObject.isCompleted && !isFuturePrayer { Color.clear }
            else { NeuRaised(shape: shape) }
        case .quiet:
            if isCurrentPrayer { NeuPressed(shape: shape) } else { Color.clear }
        case .raised, .prayedOnTap, .now, .dayNow, .nowLeads, .prayedAt:
            // The prayer on now (or a row with its buttons up) raised: the look's band (SalahRowRaise — the one
            // place it's drawn; the raised list's capsule, G's rounder lift, Sami's C–F block in the well).
            if isCurrentPrayer || showsActions { SalahRowRaise(look: look) } else { Color.clear }
        case .card, .well, .timeline:
            Color.clear
        }
        }
    }

    /// The row's status mark: the chosen dot style, with a soft halo while on now in B (the others raise the row instead).
    @ViewBuilder private var statusGlyph: some View {
        let excused = Excused.covers(start: prayerObject.startTime, end: prayerObject.endTime)
        let dot = PrayerStatusDot(style: PrayerDotStyle(rawValue: dotStyleRaw) ?? .muted,
                                  done: prayerObject.isCompleted && !isFuturePrayer,
                                  future: isFuturePrayer,
                                  scoreColor: prayerObject.getColorForPrayerScore(),
                                  pulse: completionPulse,
                                  excused: excused)
        switch look {
        case .timeline:
            dot.background {
                if isCurrentPrayer { Circle().fill(Color.sage.opacity(0.18)).frame(width: 26, height: 26) }
            }
        default:
            dot
        }
    }

    /// The name's size for the look (Sami's looks; the others keep .callout).
    private var nameFont: Font {
        switch look {
        case .dayNow: .body                                          // D · a size up, with more air
        case .nowLeads: isCurrentPrayer ? .title3 : .subheadline     // E · the one on now leads
        // G · one size for every row (owner: stepping sizes on mark / unmark "looks tacky"); the lift alone sets the one on
        // now apart.
        default: .callout
        }
    }
    /// F · a prayer still to say reads in regular; the rest light (as everywhere). G and the raised list stay light like the
    /// original list (owner: the bolder names changed its type).
    private var nameWeight: Font.Weight { look == .prayedAt && !prayerObject.isCompleted ? .regular : .light }

    private var isFuturePrayer: Bool {
//        withAnimation(.spring(duration: 0.5)) {
            calcStartTime > Date()
//        }
    }
    
    // Status Circle Properties
    private var statusImageName: String {
        if isFuturePrayer { return "circle" }
//        return prayerObject.isCompleted ? "checkmark.circle.fill" : "circle"
        return prayerObject.isCompleted ? "circle.fill" : "circle"
    }
    
//    private var statusColor: Color {
//        if isFuturePrayer { return Color.secondary.opacity(0.2) }
//        return prayerObject.isCompleted ? viewModel.getColorForPrayerScore(prayerObject.numberScore).opacity(0.70) : Color.secondary.opacity(0.5)
//    }
//    
//    private var overlayCircleColor: Color {
//        if isFuturePrayer { return Color.secondary.opacity(0.01) }
//        return prayerObject.isCompleted ? viewModel.getColorForPrayerScore(prayerObject.numberScore) : Color.secondary.opacity(0.5)
//    }
    
    private var statusColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayerObject.isCompleted ? prayerObject.getColorForPrayerScore().opacity(0.70) : Color.secondary.opacity(0.5)
    }
    
    private var overlayCircleColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.01) }
        return prayerObject.isCompleted ? prayerObject.getColorForPrayerScore() : Color.clear/*secondary.opacity(0.5)*/
    }

    private var outerCircleStyle: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayerObject.isCompleted ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.5)
    }
    
    // Text Properties
    private var statusBasedOpacity: Double {
        if isFuturePrayer { return 0.6 }
        if [.now, .dayNow, .nowLeads].contains(look) && prayerObject.isCompleted { return 0.55 }   // prayed ones step back
        return prayerObject.isCompleted ? 1 : 1
    }
    
    // Background Properties
    private var backgroundColor: Color {
        if isFuturePrayer { return Color(.systemBackground) }
        return prayerObject.isCompleted ? Color(.systemBackground) : Color(.systemBackground)
    }
    
    // Shadow Properties
    private var shadowXOffset: CGFloat {
        prayerObject.isCompleted ? -2 : 0
    }
    
    private var shadowYOffset: CGFloat {
        prayerObject.isCompleted ? -2 : 0
    }
    
//    private var nameFontSize: Font {
//        return .callout
//    }
    
    private var timeFontSize: Font {
        .footnote
    }
    
    private var calcStartTime: Date{
//        if let timesFromDict = viewModel.prayerTimesForDateDict[name], Calendar.current.isDateInToday(prayerObject.startTime) {
//            return timesFromDict.start
//        }
//        else {
            return prayerObject.startTime
//        }
//        return Date()
    }
    
    /// When the prayer can be marked as prayed: from its start (never before) up to now, and no
    /// later than the day's rollover (past the window is Qaza, e.g. Isha at 12:30 AM).
    private var editTimeRange: ClosedRange<Date> {
        let latest = min(Date(), PrayerDay.rolloverInstant(after: prayerObject.startTime))
        return prayerObject.startTime...max(prayerObject.startTime, latest)
    }

    /// "Middle · 88" (PrayerScoring).
    /// The start time as shown: the tour's practice clock moves a practice row's (PracticeClock).
    private var shownStart: Date { PracticeClock.shown(calcStartTime, of: prayerObject) }

    private var completedTimeAndScore: String {
        prayerObject.scoreSummary ?? "Missed"
    }

    /// A tap on the time: flip its text (a started prayer's time doesn't flip). A Jumu'ah shows its masjid instead.
    private func timeTap() {
        // G · while this row's buttons are up, a tap on it (the name) does nothing — it used to flip and clear them (owner).
        if showsActions { return }
        // The day page (the merge, owner 2026-10-15): a tap on a marked row picks it into the ring, as its fifth does; the
        // score is always under the time there, so the flip has nothing left to show.
        if DayPageState.shared.up && prayerObject.isCompleted && !TourRuntime.shared.active {
            triggerSomeVibration(type: .light)
            withAnimation(CircleMotion.dayPick) { DayPageState.shared.togglePick(name: prayerObject.name) }
            return
        }
        guard isFuturePrayer || prayerObject.isCompleted else { return }
        TourTargets.shared.lastTappedRow = prayerObject.name   // its change glows (the tour)
        TourRuntime.shared.event(prayerObject.isCompleted ? .markedRowTapped : .comingRowTapped)   // the tour's list card
        if prayerObject.isJumuah && prayerObject.isCompleted {
            showMasjidLine(!masjidLine)
            return
        }
        withAnimation { toggledText.toggle() }   // ExternalToggleText flips (and flips back after 3 s)
        if look.behavesLikeG && prayerObject.isCompleted { flipScore() }
    }

    /// G · the name and the score swap with the time's flip, on the same 3 s (ExternalToggleText's own timer).
    private func flipScore() {
        scoreShownTask?.cancel()
        withAnimation { scoreShown.toggle() }
        guard scoreShown else { return }
        scoreShownTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { scoreShown = false }
        }
    }

    /// The masjid's line under a Jumu'ah row, then back after `masjidLineDuration` (as the time's flip comes back). It
    /// opens inside the row's own height — the name lifts, the line fills the space below — so the list never grows
    /// and the circle never moves (owner, decision jumuah-name-render B: "Islamic Center of" was all the time's
    /// column could show).
    private func showMasjidLine(_ shown: Bool) {
        masjidLineTask?.cancel()
        withAnimation(CircleMotion.movement(CircleMotion.ease(), reduced: reduceMotion)) { masjidLine = shown }
        guard shown else { return }
        masjidLineTask = Task { @MainActor in
            guard await CircleGate.pause(Self.masjidLineDuration) else { return }
            withAnimation(CircleMotion.movement(CircleMotion.ease(), reduced: reduceMotion)) { masjidLine = false }
        }
    }
    private static let masjidLineDuration: Double = 3
    /// How far the name rises for the masjid's line: the two lines centred in the row.
    private static let masjidLift: CGFloat = 7
    /// Under the name: the dot's 24 pt and the row's spacing.
    private static let masjidLineIndent: CGFloat = 32

    /// A tap round the dot: mark / unmark (a prayer that hasn't started can't be marked).
    private func markTap() {
        // A marked prayer's dot always unmarks, even one whose start a clock set back put ahead (mark audit #8).
        if prayerObject.isCompleted || !isFuturePrayer { handlePrayerButtonPress() }
    }

    /// G · this row shows the post-mark buttons.
    private var showsActions: Bool {
        look.behavesLikeG && prayerObject.isCompleted && PrayerRowActions.shared.name == prayerObject.name
    }


    /// Radius of the circle round the dot where a tap marks (a 44 pt circle; the dot is 14 pt).
    static let markRadius: CGFloat = 22

    /// The row's one gesture: hold → the time editor (a marked prayer); a tap within `markRadius` of
    /// the dot's centre marks / unmarks, anywhere else flips the time. Exclusive, so letting go of a
    /// hold never also taps (on the dot a tap unmarks: the alert would come up under the editor).
    private var rowGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: SpatialTapGesture(coordinateSpace: .named(PrayerButton.rowSpace)))
            .onEnded { value in
                switch value {
                case .first: openTimeEditor()
                case .second(let tap):
                    let d = hypot(tap.location.x - dotCenter.x, tap.location.y - dotCenter.y)
                    if d <= Self.markRadius { markTap() } else { timeTap() }
                }
            }
    }
    static let rowSpace = "prayerRow"

    private func openTimeEditor() {
        guard prayerObject.isCompleted else { return }
        // In the tour only the fix step's Fajr opens (a light no otherwise, as for a mark the tour doesn't want).
        guard TourRuntime.shared.allowsEditing(prayerObject) else {
            TourRuntime.shared.nudge()   // the tour: not yet / not this one — a pulse, no buzz
            return
        }
        showTimePicker = true
        TourRuntime.shared.event(.editorOpened(prayerObject.name))   // the tour's "change the time or place" step
    }

    var body: some View {
        let _ = viewModel.revision   // redraw after marks / edits, as on objectWillChange (step 8)
            // Where a tap marks (owner, 2026-09-29: testers kept missing the dot): a 44 pt circle round the
            // dot (`markRadius`), stopping short of the name; the rest of the row flips the time as before.
            // The dot used to be a Button round its 14 pt circle, the only place a tap marked.
            HStack {
                statusGlyph
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let f = proxy.frame(in: .named(PrayerButton.rowSpace))
                        return CGPoint(x: f.midX, y: f.midY)
                    } action: { dotCenter = $0 }
                    // The tour's mark hint points at the dot of the prayer in its window (every row reports; the hint
                    // picks the current prayer's).
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        TourTargets.shared.set("prayerDot." + prayerObject.name, frame)
                    }
                    #if DEBUG
                    .overlay { HitAreaDebug.overlay }
                    #endif
                    .frame(width: 24, height: 24, alignment: .leading)

                // Prayer Name Label
                VStack(alignment: .leading, spacing: 1) {
                // G · a tapped prayed row shows its score where its name sits (the time shows when it was prayed).
                Text(look.behavesLikeG && scoreShown && prayerObject.isCompleted ? completedTimeAndScore
                     : prayerObject.displayName)   // "Jumu'ah" when Friday's Dhuhr was at a masjid
                    .id(scoreShown)
                    .transition(.blurReplace)
                    // Never squeezed by a long time column (it broke a letter a line and the row grew tall).
                    .fixedSize()
                    .layoutPriority(1)
                    .font(nameFont)   // Sami's looks try type sizes (nameFont); the others .callout
                    // Today's look: exactly the old Color.secondary (the hierarchical .secondary differed a hair).
                    .foregroundStyle(theme.emphasisesCurrentRow && (isCurrentPrayer || pickedOnDayPage) ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(statusBasedOpacity))) //1
                    .fontDesign(.rounded)
                    .fontWeight(nameWeight)
                    // E · the prayer on now: its time left right under its name.
                    if look == .nowLeads && isCurrentPrayer {
                        NowTimeLeft(start: prayerObject.startTime, end: prayerObject.endTime)
                    }
                }
                // G · the marked row's pencil, right after its name (owner's drawing): the time / place editor.
                if showsActions {
                    PrayerRowActionButton(symbol: "pencil", label: "Edit time or place", size: 26, style: .bare) { openTimeEditor() }
                        .padding(.leading, -6)   // close to the name (owner); the tap area stays 26 pt
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                // Prayed at a masjid: a small mosque mark by the name.
                if prayerObject.atMasjid {
                    Image(systemName: "building.columns")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.sage)
                }

                Spacer()

                if let line = TourHints.shared.markLine, isCurrentPrayer {
                    // The tour's mark hint in the current row's time place (Tour.swift).
                    Text(line).font(.footnote).fontDesign(.rounded).fontWeight(.light).foregroundStyle(.secondary)
                } else if showsActions {
                    PrayerRowActionButtons(
                        showsCamera: prayerObject.endTime > Date() && !PrayerPhotos.exists(for: prayerObject),
                        onCamera: { NotificationCenter.default.post(name: PrayerRowActions.openCamera, object: prayerObject.name) },
                        onTasbih: { NotificationCenter.default.post(name: PrayerRowActions.openTasbih, object: prayerObject.name) })
                } else if look.raisesNow && isCurrentPrayer {
                    if look == .nowLeads {
                        // E · the time left sits under the name; here, when it ends.
                        Text("ends \(shortTimePM(prayerObject.endTime))")
                            .font(timeFontSize).fontDesign(.rounded).fontWeight(.light).foregroundStyle(.secondary)
                    } else {
                        NowTimeLeft(start: prayerObject.startTime, end: prayerObject.endTime)   // in place of its start
                    }
                } else {
                    timeColumn
                        // The tour rings exactly this time when a tap flips it (owner: not a fixed box). Only while the
                        // tour runs.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            if TourRuntime.shared.active { TourTargets.shared.set("rowTime." + prayerObject.name, frame) }
                        }
                }
            }
            // A Jumu'ah's masjid, under the name, inside the row's height (showMasjidLine): drawn over the row, so
            // nothing below it moves.
            .overlay(alignment: .bottomLeading) {
                if prayerObject.isJumuah, let masjid = prayerObject.mosqueName {
                    Text("at \(masjid)")
                        .font(.caption)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                        .foregroundStyle(Color.sage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, Self.masjidLineIndent)
                        .offset(y: masjidLineHeight)   // its top just under the name
                        .opacity(masjidLine ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: masjidLine ? -Self.masjidLift : 0)
            // The tour points at whole rows too (a coming prayer's time, a marked prayer's score).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                TourTargets.shared.set("prayerRow." + prayerObject.name, frame)
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: Self.demoMasjidLine)) { _ in
                if prayerObject.isJumuah { showMasjidLine(true) }
            }
            #endif
            .padding(.horizontal)
            .padding(.vertical, theme.rowVerticalPadding)   // the well's rows a bit shorter (owner, 2026-10-01)
            .frame(minHeight: look == .raised ? SalahLook.raisedRowHeight : nil)   // the raised list: 54 pt rows
            // E · the raised one gets its own room (the rest are compact).
            .padding(.vertical, look == .nowLeads && isCurrentPrayer ? 6 : 0)
            .modifier(DayPickAnchor(name: prayerObject.name))   // where the day page's band goes when it's picked
            .contentShape(Rectangle())
            .coordinateSpace(.named(PrayerButton.rowSpace))
            .gesture(rowGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: prayerObject.isCompleted ? "Mark not prayed" : "Mark prayed") { markTap() }
            // Background Effects Container
            .background { rowBackground }
            .background(alignment: .topLeading) {
                if look.drawsDayLine {
                    // B / D · the day's line through the dots, behind a raised row (PrayerListLooks.swift).
                    let names = viewModel.orderedPrayerNames
                    TimelineSpine(dot: dotCenter, gapBelow: theme.rowSpacing,
                                  showsAbove: names.first != name, showsBelow: names.last != name,
                                  litAbove: !isFuturePrayer, litBelow: !isFuturePrayer && !isCurrentPrayer)
                }
            }
            .animation(Self.dotPress, value: prayerObject.isCompleted)
            .animation(.smooth(duration: 0.45), value: isCurrentPrayer || showsActions)   // G · the lift
            .onChange(of: prayerObject.isCompleted) { _, done in
                if !done, PrayerRowActions.shared.name == prayerObject.name { PrayerRowActions.shared.name = nil }   // unmarked
            }
            .onChange(of: prayerObject.isCompleted) { _, done in
                if done { completionPulse += 1 }
            }
            // Perfect day: the five dots pop one after another, from the stage's cascade (once the last mark's moment is
            // over and all five rows are back).
            .task(id: CircleStage.shared.perfectCascade) {
                let index = Double(viewModel.orderedPrayerNames.firstIndex(of: name) ?? 0)
                guard CircleStage.shared.perfectCascade > 0,
                      await CircleGate.pause(CircleMotion.perfectBeatDuration + CircleMotion.perfectStepDuration * index) else { return }
                completionPulse += 1
            }
            .alert(isPresented: $showMarkIncompleteAlert) {
                        Alert(
                            title: Text("Confirm Action"),
                            message: Text("Are you sure you want to mark this prayer as incomplete?"
                                          + (PrayerPhotos.exists(for: prayerObject) ? " Its photo will be deleted too." : "")),
                            primaryButton: .destructive(Text("Yes")) {
                                // A 0.1 s spring snapped the whole page (score → prayer, the list 5 rows → 1); an
                                // ease lets it settle (Sami's audit, finding 7; his verified fix).
                                withAnimation(Self.unmarkFade) {
                                    viewModel.togglePrayerCompletion(for: prayerObject)
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    }
            .sheet(isPresented: $showTimePicker, onDismiss: {
                // The day page: the ring and the score move once the sheet is out of the way (owner, 2026-10-19).
                guard let edit = pendingEdit else { return }
                pendingEdit = nil
                withAnimation(CircleMotion.dayEdit) { apply(edit) }
            }) {
                // Every box saves itself (N2, owner 2026-10-19: "just fix the time so that it just always saves"): each save
                // lands now, or — with the day page up — is held until the sheet is gone, so the ring still moves after.
                PrayerTimeEditSheet(prayer: prayerObject, range: editTimeRange,
                                    onTime: { date in save { $0.time = date; $0.revertTime = false; $0.timeUnknown = false } },
                                    onRevertTime: { save { $0.time = nil; $0.revertTime = true; $0.timeUnknown = false } },
                                    onTimeUnknown: { save { $0.time = nil; $0.revertTime = false; $0.timeUnknown = true } },
                                    onSpot: { spot in save { $0.spot = spot; $0.revertSpot = false } },
                                    onRevertSpot: { save { $0.spot = nil; $0.revertSpot = true } },
                                    onClose: { showTimePicker = false })
                // Closed by a widget open: every box has already saved itself.
                .stageCover("timeEdit.\(prayerObject.name)")
            }
    }

    /// One save from the editor: held for the day page, else applied now.
    private func save(_ change: (inout HeldEdit) -> Void) {
        if DayPageState.shared.up && !TourRuntime.shared.active {
            var held = pendingEdit ?? HeldEdit()
            change(&held)
            pendingEdit = held
        } else {
            var now = HeldEdit()
            change(&now)
            apply(now)
        }
    }

    /// A user edit: the recorded time / spot are kept (revertible), and ↺ puts them back.
    private func apply(_ edit: HeldEdit) {
        if edit.revertTime { viewModel.revertPrayerTime(prayerObject) }
        if edit.timeUnknown { viewModel.markPrayerTimeUnknown(prayerObject) }
        // A set time always lands on a no-time mark (its tap may be the same clock time, but it wasn't a time).
        if let date = edit.time,
           abs(date.timeIntervalSince(prayerObject.timeAtComplete ?? .distantPast)) >= 30 || prayerObject.timeUnknown {
            viewModel.editPrayerTime(prayerObject, to: date)
        }
        if edit.revertSpot { viewModel.revertPrayerLocation(prayerObject) }
        if let spot = edit.spot { viewModel.movePrayer(prayerObject, to: spot) }
    }

    /// The time: the start time, flipping to the countdown (a prayer to come) or the score (a marked
    /// one). Its own tap is off: the row's gesture drives it through `toggledText`.
    @ViewBuilder private var timeColumn: some View {
                if isFuturePrayer {
                    // Future Prayer: Toggleable Time/Countdown
                    ExternalToggleText(
                        originalText: shortTimePM(shownStart),
                        toggledText: timeUntilStart(calcStartTime),
                        externalTrigger: $toggledText,
                        font: timeFontSize,
                        fontDesign: .rounded,
                        fontWeight: .light,
                        hapticFeedback: true
                    )
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    .allowsHitTesting(false)

                } else if prayerObject.isCompleted && DayPageState.shared.up && !TourRuntime.shared.active,
                          let prayedAt = prayerObject.markedTime {
                    // The day page, Jumu'ah too: when it was prayed, "1:22 PM" (DayRowTime — Journey's rows too).
                    DayRowTime(prayedAt: prayedAt)
                        .allowsHitTesting(false)
                } else if prayerObject.isCompleted && prayerObject.isJumuah {
                    // A Jumu'ah: its time stays; a tap opens the masjid's line under the name (showMasjidLine).
                    Text(shortTimePM(shownStart))
                        .font(timeFontSize)
                        .foregroundColor(.secondary.opacity(statusBasedOpacity))
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                } else if prayerObject.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if prayerObject.timeUnknown {
                        // In its time, no time recorded (MarkKind.timeUnknown): said where the time goes.
                        Text("in its time")
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                            .fontDesign(.rounded)
                            .fontWeight(.light)
                            .allowsHitTesting(false)
                    } else if let prayedAt = prayerObject.timeAtComplete {
                        if DayPageState.shared.up && !TourRuntime.shared.active {
                            // The day page: when it was prayed, "7:45 PM" (DayRowTime — Journey's rows too).
                            DayRowTime(prayedAt: prayedAt)
                                .allowsHitTesting(false)
                        } else {
                        ExternalToggleText(
                            // F · when you prayed it, not when it started (the flip still shows the score).
                            originalText: look == .prayedAt ? "prayed \(shortTimePM(prayedAt))" : shortTimePM(shownStart),
                            // G · the tap shows when you prayed (the score takes the name's place).
                            toggledText: look.behavesLikeG ? "at \(shortTimePM(prayedAt))" : completedTimeAndScore,
                            externalTrigger: $toggledText,
                            font: timeFontSize,
                            fontDesign: .rounded,
                            fontWeight: .light,
                            hapticFeedback: true,
                            fits: true
                        )
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                            .allowsHitTesting(false)
                        }
                    }
                } else {
                    // Current Prayer: Show Start Time
                    Text(shortTimePM(shownStart))
                        .font(timeFontSize)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
    }

        
}

/// The prayer editor's saves, held while the day page is up (PrayerButton.pendingEdit): the last time or ↺, the last spot
/// or ↺.
struct HeldEdit {
    var time: Date?
    var revertTime = false
    /// "I don't remember the time" (MarkKind.timeUnknown).
    var timeUnknown = false
    var spot: CLLocationCoordinate2D?
    var revertSpot = false
}
