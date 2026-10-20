//
//  PrayerTimesView.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/29/25.
//

import SwiftUI
import Adhan
import CoreLocation
import SwiftData
import UserNotifications
import WidgetKit


// MARK: - Prayer Times View

struct PrayerTimesView: View {
    #if PERFARGS
    /// The Release perf build's shortcuts (board/perf-recheck-plan.md): `-perfExplore` opens Explore (with `-demoExploreGroup`
    /// / `-demoExploreMember`), `-demoExcused N` starts Excused Mode. Compiled only into that build.
    @State private var perfExplore = false
    #endif
    @Environment(SharedStateClass.self) var sharedState
    @Environment(PrayerViewModel.self) var viewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) var context
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("widgetCompass", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetCompass: Bool = false
    @AppStorage("widgetTasbeeh", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTasbeeh: Bool = false
    @AppStorage("widgetTextToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTextToggle: Bool = false
        
    @State private var showDailyAyahView: Bool = false
    @State private var showMantraSheetFromHomePage: Bool = false
    @State var showTasbeehPage: Bool = false
    @State var showQiblaMap: Bool = false

    @State private var chosenMantra: String? = "" {
        didSet{
            if let text = chosenMantra {
                print("ran chosenMantra's didSet")
                sharedState.titleForSession = text
            }
        }
    }
    /// The row behind `chosenMantra`; the picker sets it first, the onChange below forwards it.
    @State private var chosenMantraObject: MantraModel? = nil
    
    /// Per-frame values written by the pager gesture / scroll (sheet drag, pull, scroll progress).
    /// An @Observable object: only the views that read a property re-render when it changes, so
    /// this screen's body is not re-evaluated on every finger move (that was the old lag).
    @State private var live = PagerLiveState()
    /// The axis of the current pager drag, in a plain box: as @State, setting it at a drag's first move rebuilt this
    /// whole view — a dropped frame at the start of nearly every vertical drag (the sandbox's log, 2026-10-14).
    @State private var dragAxis = DragAxis()
    final class DragAxis {
        var vertical: Bool?
        /// This drag only closed the ☰ menu: it moves nothing (`SalahSheetDrag.dragClosesMenu`).
        var swallowed = false
    }
    @GestureState private var pagerDragActive = false      // a finger on the pager's drag (resets on cancel too)
    /// The Salah sheet follows the finger (SalahSheetDrag): the sheet is its own ScrollView, and this gesture only locks the axis.
    @AppStorage(SalahSheetDrag.key) private var sheetFollows = SalahSheetDrag.defaultOn

    // MARK: - Horizontal pager
    // Three pages side by side in a native paging ScrollView: Zikr | Main | Settings.
    // UIKit drives the finger tracking, so nothing in SwiftUI re-renders per frame.
    // `scrollPage` is written only programmatically (from sharedState.horizontalPage); user
    // swipes flow the other way via onScrollPhaseChange once the scroll settles.
    typealias NavPage = SharedStateClass.HorizontalPage
    @State private var scrollPage: NavPage? = .main
    /// One widget / alarm / What's new open at a time: closing the covers, waiting for them to go, then going. A newer
    /// open replaces one still waiting (`clearCovers`).
    @State var pendingOpen: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Menu destinations (native Menu on the hamburger; pushes on the root NavigationStack)
    @State private var showMapPage = false
    @State var showDailyAyahPage = false
    @State var showMantrasPage = false
    @State private var showSalahHistoryV1 = false
    @State private var showSalahHistoryV2 = false
    @State var showZikrHistory = false
    /// A session sleep mode ended: shown round the Salah circle the next time the page is up.
    @State private var morningSession: SessionDataModel?
    @State private var showInsightsPage = false
    @State private var showOldInsights = false
    @State var showNamesPage = false
    /// The Prayers widget's times list: a marked row opens the app to "Unmark Asr?".
    @State var widgetUnmark: WidgetUnmarkRequest?
    /// Bumped per request, so an older retry loop stops.
    @State var widgetUnmarkToken = 0
    /// Excused from prayer's sheet, from a tap on the circle (Excused.swift).
    @State private var showExcused = false
    /// Something tried to mark a prayer while excused: "Prayers are paused · I'm back" (owner: never a silent no).
    @State var askingResume = false
    /// The prayer tapped, marked once she's back if it's due then.
    @State var resumePrayer: PrayerModel?
    /// Past her estimate: once a day on opening, "Are you back to praying?" (Excused.swift).
    @State private var askingOverdue = false
    /// Its "Not yet": "About how much longer?"
    @State private var showExtend = false
    #if DEBUG
    @State var demoMantra: MantraModel?
    @State var demoNewZikr = false
    @State var demoWhatsNew = false
    @State var demoScheduled = false
    @State var demoExplore = false   // DEBUG `-demoExplore`: Explore shukr over the page
    @State var demoSadaqah = false   // DEBUG `-demoSadaqah`: the Sadaqah page over the page
    #endif

    /// A morning card is waiting: be on the Salah page (circle showing) while the app is away, so the
    /// next open's welcome and the card draw on the real circle from the first frame. Left on the Zikr
    /// page (where the session started), the circle's last frame was off screen and the welcome
    /// started half off the screen (owner, sleep morning). Behind the black curtain, so unseen.
    private func goToSalahForMorningCard() {
        guard SleepMorning.pendingID != nil else { return }
        sharedState.go(to: .main, animated: false)   // in this turn: the curtain's snapshot is next
        SalahSheetDrag.closeQuietly(sharedState)
    }

    /// Sleep mode ended a session: once nothing is over the Salah page, go to it (circle showing) and
    /// open the morning card on its circle — under the welcome while it plays, which lands on the card. It waits on the
    /// stage (the app active; no cover — the session, a pushed page, a sheet, the setup, the map), waking when that
    /// changes: it retried every 0.5 s, 40 times (tr-final).
    private func showMorningCardWhenClear() {
        guard morningSession == nil, SleepMorning.pendingID != nil, SleepMorning.isArmed else { return }
        morningWait?.cancel()
        morningWait = Task { await showMorningCard() }
    }

    private func showMorningCard() async {
        let stage = CircleStage.shared
        // Not waiting for the welcome: the card goes up under it, so the welcome lands on its ring.
        guard await stage.until(deadline: Self.morningCardDeadline, { stage.sceneActive && CircleCover.nothingOverCircle }),
              morningSession == nil, SleepMorning.pendingID != nil, SleepMorning.isArmed,
              let session = SleepMorning.pending(in: context) else { return }
        SalahSheetDrag.closeQuietly(sharedState)
        // The card draws round the circle's frame: mount it once the pager rests on Salah (at once — the page change
        // is quiet — but measured, not guessed: audit D, finding 2).
        await sharedState.navigate(to: .main, animated: false)
        guard !Task.isCancelled, morningSession == nil, SleepMorning.pendingID != nil else { return }
        morningSession = session
    }
    @State private var morningWait: Task<Void, Never>?
    @State private var tourWait: Task<Void, Never>?
    /// Nothing else owns the Salah page: the tour may start, or show (audit A4).
    private var tourCanStart: Bool {
        let stage = CircleStage.shared
        return !stage.pageHidden && stage.sceneActive && stage.lost == nil && morningSession == nil
            && !somethingCovers && !showTasbeehPage && !FirstRunSetup.isShowing && !WelcomeTarget.playing
    }
    private static let morningCardDeadline: Double = 20

    /// The tour's invitation, a breath after the page is the user's (the welcome landed, or the setup ended).
    private func inviteToTour(after seconds: Double) {
        guard TourRuntime.shouldAutoStart else { return }
        tourWait?.cancel()
        tourWait = Task {
            // A breath on the real day after the welcome lands, ring alive, before the invitation (audit L).
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // Deferred, never skipped, while something else owns the page (audit A4): the lost page, the morning
            // card, the reminders card, a cover, a system alert.
            let stage = CircleStage.shared
            guard await stage.until(deadline: 600, recheck: 1, { tourCanStart }) else { return }
            guard !Task.isCancelled, !TourRuntime.shared.active, TourRuntime.shouldAutoStart else { return }
            SalahSheetDrag.closeQuietly(sharedState)
            sharedState.go(to: .main, animated: false)
            TourRuntime.shared.invite()
        }
    }

    /// Widget / control / Action-button opens (one-shot flags in the app group). Held while the
    /// first-run setup is up — the flags stay set and this runs again once it's done
    /// (`FirstRunSetup.finished`), so its hand-off always lands on this page's circle.
    /// Past her estimate: ask once a day, a moment after the page is up (Excused.swift; owner: notifications may be off).
    private func askIfOverdue() {
        guard Excused.shouldAskToday else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard Excused.shouldAskToday, !FirstRunSetup.isShowing, !askingResume, !showExcused else { return }
            Excused.markAskedToday()
            askingOverdue = true
        }
    }


    /// Everything that can cover the pager: the map, a pushed page, the mantra sheet.
    @State var unmarkWait: Task<Void, Never>?
    static let unmarkDeadline: Double = 90
    /// A paused session's pause screen coming in before the prompt goes over it (an observable "paused" from the
    /// session would replace this wait).
    static let sessionPausesDuration: Double = 0.4

    /// The reminders card (NotificationHealth): notifications off, or held for the Scheduled Summary.
    @State var healthCard: NotificationHealth.Issue?
    /// Set by the card's onAppear; bumped per attempt so an older check can't clear a newer card.
    @State var healthCardAppeared = false
    @State private var healthCardToken = 0
    @State var lastDeepLinkAt: TimeInterval = -.infinity   // Uptime, never the wall clock (audit F, F6)

    /// A moment after the app comes forward: the card, if one's due (at most every few days per
    /// kind) and nothing else is going on — not over a tasbeeh session, a cover, the setup, or a
    /// widget's destination.
    private func maybeShowHealthCard() {
        guard !TourRuntime.shared.active else { return }   // never over the tour (Bradley); the next activation asks again
        healthWait?.cancel()
        healthWait = Task {
            // A moment after the app comes forward (not on its first frame), and not while the opening plays (a sheet
            // over it left the page blank): it waits for that on the stage (it retried every 2 s).
            guard await CircleGate.pause(Self.healthCardAfterDuration) else { return }
            let welcome = WelcomeTarget.state
            guard await CircleStage.shared.until(deadline: Self.healthCardDeadline, { !welcome.playing }) else { return }
            let health = NotificationHealth.shared
            await health.refresh()
            // Only on the Salah page with nothing else open: sheets inside the Zikr and Settings
            // pages (task sheets, the city picker, What's new…) aren't in `somethingCovers`.
            guard !Task.isCancelled, FirstRunSetup.isDone, !FirstRunSetup.isShowing, !showTasbeehPage, !somethingCovers,
                  sharedState.horizontalPage == .main, CircleCover.active.isEmpty, healthCard == nil, !demoSheetUp,
                  // The morning card (sleep mode) comes first; this card waits for another open.
                  morningSession == nil, !(SleepMorning.pendingID != nil && SleepMorning.isArmed),
                  Uptime.now - lastDeepLinkAt > 10,
                  let issue = health.cardIssue, health.cardDue(for: issue) else { return }
            healthCard = issue   // marked shown, and a CircleCover, only once it's actually up (the card's onAppear)
            healthCardAppeared = false
            healthCardToken += 1
            let token = healthCardToken
            // Something the guards can't see (a prayer row's unmark alert…) can keep the sheet
            // from presenting. Don't leave it pending — it would block every later card and
            // could pop up at a random moment: drop it if it isn't up in time.
            try? await Task.sleep(for: .seconds(Self.healthCardUpDeadline))
            if token == healthCardToken, !healthCardAppeared, healthCard == issue { healthCard = nil }
        }
    }
    @State private var healthWait: Task<Void, Never>?
    private static let healthCardAfterDuration: Double = 2
    private static let healthCardDeadline: Double = 10
    private static let healthCardUpDeadline: Double = 1.2

    /// DEBUG screenshot sheets the card mustn't cover.
    private var demoSheetUp: Bool {
        #if DEBUG
        return demoScheduled
        #else
        return false
        #endif
    }

    // (CircleCover's closers: the stage, CircleMoments.swift.)
    var somethingCovers: Bool {
        showQiblaMap || showMapPage || showDailyAyahPage || showMantrasPage || showSalahHistoryV1
            || showSalahHistoryV2 || showZikrHistory || showInsightsPage || showOldInsights
            || showNamesPage || showMantraSheetFromHomePage || JourneyPresenter.shared.open
            || healthCard != nil     // the reminders card: a widget's deep link closes it first
    }

    private func dismissCovers() {
        showQiblaMap = false; showMapPage = false; showDailyAyahPage = false; showMantrasPage = false
        showSalahHistoryV1 = false; showSalahHistoryV2 = false; showZikrHistory = false
        showInsightsPage = false; showOldInsights = false; showNamesPage = false
        showMantraSheetFromHomePage = false; JourneyPresenter.shared.open = false
        healthCard = nil
    }

    /// A widget / control / What's new is taking the user somewhere: close what's covering the page, wait until it has
    /// gone (each cover reports itself gone once its dismissal has finished — `stageCover`, the pushed pages below), then
    /// go, so the new page isn't pushed under the leaving one. One open at a time: a newer one replaces this. A running
    /// tasbeeh session is never closed from a widget tap.
    private func openSharedTask() {
        guard TaskSharing.shared.pending != nil, !showTasbeehPage, FirstRunSetup.isDone, !FirstRunSetup.isShowing else { return }
        clearCovers {
            for _ in 0..<40 where WelcomeTarget.playing { try? await Task.sleep(for: .milliseconds(150)) }   // the opening first
            guard await sharedState.navigate(to: .zikr) else { return }
            TaskSharing.shared.zikrPageReady()
        }
    }

    func clearCovers(then go: @escaping @MainActor () async -> Void) {
        guard !showTasbeehPage else { return }
        pendingOpen?.cancel()
        pendingOpen = Task {
            let stage = CircleStage.shared
            let closing = stage.closeAll()   // the ☰ popover, What's new, calibration, a row's time edit, pushed pages
            dismissCovers()                  // and any page asked for that hasn't appeared yet
            if !closing.isEmpty {
                // A cover that never reports goes after the deadline anyway (the old fixed wait was 0.55 s).
                _ = await stage.until(deadline: 1.5) { stage.covers.isDisjoint(with: closing) }
            }
            guard !Task.isCancelled else { return }
            await go()
        }
    }
//    var showTop: Bool { sharedState.navPosition == .top }
    var showMain: Bool { sharedState.navPosition == .main }
    var showBottom: Bool { sharedState.navPosition == .bottom }

    /// The page the pager rests on, for the stage (`restingPage`; `navigate(to:)` and the circle's gate wait on it): a
    /// page once it's idle on one, nil while it moves. Written only on change.
    private func noteRestingPage(progress: CGFloat, phase: ScrollPhase) {
        let index = progress.rounded()
        let resting: NavPage? = phase == .idle && abs(progress - index) < 0.01
            ? (index <= 0 ? .zikr : index >= 2 ? .settings : .main) : nil
        if CircleStage.shared.restingPage != resting { CircleStage.shared.restingPage = resting }
    }

    // MARK: - Salah sheet: swipe up / down (the pop)
    // The finger doesn't drag the sheet. A vertical swipe past `threshold` flips it with a
    // spring, the way it always did; while the finger is down only the chevron nudges
    // (resisted, capped) so the page acknowledges it. Attached to the pager itself so nothing
    // inside a page can block it; a no-op unless the Salah page is showing.
    //
    // Axis lock: the gesture starts at 5 pt and the axis is decided at 6 pt of movement, before
    // the pager's own pan reaches its 10 pt slop. Not `minimumDistance: 0`: a zero-distance drag
    // on the pager claimed every touch, and on iOS 26 that cancelled the Settings Form's row taps
    // (pickers, button rows, navigation rows — dead in build 9 on a 15 Pro, iOS 26.6; fine on
    // iOS 27). A tap never moves 5 pt, so rows get it; drags still lock early enough. Vertical → `live.pagerLocked` (the pager is
    // `.scrollDisabled` while it's set) so sideways drift during a vertical drag can never
    // turn into a page swipe; horizontal → this gesture stays out of it. Cleared on release.
    private var abstractedDragGesture: some Gesture {
        let resistanceFactor = 0.5
        let maxOffset: CGFloat = 20
        let threshold: CGFloat = 30
        let decideAt: CGFloat = 6

        return DragGesture(minimumDistance: 5, coordinateSpace: .global)
            // True while a finger is on it; SwiftUI puts it back on its own when the drag ends *or is cancelled*
            // (`pagerDragReleased` — audit B14: a cancelled drag never reached onEnded and left the pager dead).
            .updating($pagerDragActive) { _, active, _ in active = true }
            .onChanged { value in
                if dragAxis.vertical == nil { // decide the axis once per drag
                    let t = value.translation
                    guard abs(t.width) > decideAt || abs(t.height) > decideAt else { return }
                    dismissKeyboard()
                    dragAxis.vertical = abs(t.height) > abs(t.width)
                    dragAxis.swallowed = SalahSheetDrag.dragClosesMenu(up: dragAxis.vertical == true && t.height < 0)
                    // A horizontal drag past either end (right on Zikr, left on Settings) rubber-bands with the
                    // scroll view's own resistance (owner, 2026-10-19: "allow “trying” to swipe other way but hit w
                    // resistance"); it used to be refused for the whole drag, when the pull showed white past the edge —
                    // PagerBackdrop paints past both ends now.
                    if dragAxis.vertical == true {
                        live.pagerLocked = true
                    }
                }
                if dragAxis.vertical == true {
                    guard sharedState.horizontalPage == .main, !dragAxis.swallowed else { return }
                    if sheetFollows {
                        // Vertical live dragging (round 5): the list and ring follow the finger.
                        guard CircleStage.shared.lost == nil, !TourRuntime.shared.holdsSheet else { return }
                        let spring = live.sheetSpring
                        if !spring.dragging { spring.begin() }
                        spring.drag(value.translation.height)
                        // Pulled down on the closed page: toward the ☰ menu (the chevron says so).
                        let reach = spring.startedClosed ? max(value.translation.height, 0) / SalahSheetDrag.refreshPull : 0
                        if live.refreshReach != reach { live.refreshReach = reach }
                        return
                    }
                    let nudged = min(max(value.translation.height * resistanceFactor, -maxOffset), maxOffset)
                    live.pull = showBottom ? max(0, nudged) : nudged   // no upward nudge once open
                    live.refreshReach = showBottom ? 0 : max(value.translation.height, 0) / threshold
                }
            }
            .onEnded { value in
                let vertical = dragAxis.vertical == true && !dragAxis.swallowed
                dragAxis.vertical = nil
                dragAxis.swallowed = false
                live.pagerLocked = false
                // Vertical live dragging: the let-go lands it with the finger's speed; a pull-down past the line on the
                // closed page opens ☰ (as the pop does).
                if live.sheetSpring.dragging {
                    let spring = live.sheetSpring
                    let wasOpen = !spring.startedClosed
                    let open = spring.release(velocityY: value.velocity.height)
                    if open != wasOpen { triggerSomeVibration(type: .light) }
                    if !wasOpen, !open, value.translation.height > SalahSheetDrag.refreshPull, !TourRuntime.shared.active {
                        NotificationCenter.default.post(name: SalahSheetDrag.openMenu, object: nil)
                        triggerSomeVibration(type: .light)
                    }
                    live.refreshReach = 0
                    return
                }
                // The sheet's own move is the page's and the chrome's implicit animation (rule 6); this one is the
                // chevron's nudge settling.
                live.refreshReach = 0
                withAnimation(CircleMotion.page) {
                    live.pull = 0
                    // The tour holds the list where its step needs it (audit E17); only its list step opens it.
                    guard vertical, sharedState.horizontalPage == .main, !sheetFollows,
                          !TourRuntime.shared.holdsSheet else { return }
                    let draggedDown = value.translation.height > threshold
                    let draggedUp = value.translation.height < -threshold
                    switch sharedState.navPosition {
                    case .main:
                        if draggedUp { sharedState.navPosition = .bottom; triggerSomeVibration(type: .light) }
                        // Pull down: the ☰ menu (owner: "instead of doing a refresh, it opens the hamburger menu";
                        // refreshing the location stays in Settings). Not during the tour: only its step's move.
                        if draggedDown && !TourRuntime.shared.active {
                            NotificationCenter.default.post(name: SalahSheetDrag.openMenu, object: nil)
                            triggerSomeVibration(type: .light)
                        }
                    case .bottom:
                        if draggedDown { sharedState.navPosition = .main; triggerSomeVibration(type: .light) }
                    default:
                        break
                    }
                }
            }
    }

    /// The pager's drag let go — ended or cancelled: unlock the pager and settle the nudge. After an ended drag
    /// onEnded has done this already (nothing changes); after a cancelled one, nothing else would.
    private func pagerDragReleased() {
        dragAxis.vertical = nil
        dragAxis.swallowed = false
        if live.sheetSpring.dragging { live.sheetSpring.release(velocityY: 0) }   // a cancelled drag lands where it was
        if live.pagerLocked { live.pagerLocked = false }
        if live.pull != 0 { withAnimation(CircleMotion.page) { live.pull = 0 } }
        if live.refreshReach != 0 { live.refreshReach = 0 }
    }

    #if DEBUG
    /// What may hide the tour's callout right now, plus the page and the list, for the log.
    private var tourHiddenReason: String {
        var why: [String] = []
        if somethingCovers { why.append("somethingCovers") }
        if showTasbeehPage { why.append("tasbeeh") }
        if CircleStage.shared.lost != nil { why.append("lost") }
        if morningSession != nil { why.append("morningCard") }
        if !CircleStage.shared.sceneActive { why.append("sceneInactive") }
        if !CircleStage.shared.covers.isEmpty { why.append("covers=\(CircleStage.shared.covers)") }
        why.append("page=\(sharedState.horizontalPage) list=\(sharedState.navPosition)")
        return why.joined(separator: " ")
    }
    #endif

    var body: some View {
        let _ = viewModel.revision   // redraw after marks / edits, as on objectWillChange (step 8)
        ZStack {
            // The backdrop, status-bar strip included: pages are clipped to the pager, which
            // starts below the top safe area, and the Salah page is transparent. It slides with
            // the pager (see PagerBackdrop) — it used to switch colour at the page commit, which
            // flashed the whole Salah page gray mid-swipe (owner, 2026-09-25).
            PagerBackdrop(live: live)

            // MARK: - Pager: Zikr | Main | Settings
            // Native paging ScrollView: pages track the finger at UIKit speed, rubber-band at the
            // ends, and settle with the system's velocity curve. All three stay mounted (plain
            // HStack, not lazy) so the main circle's timers and Settings' state survive paging.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    // Each page is clipped: the center page hides its side menu by pushing it 200pt
                    // off-screen to the left, which would otherwise draw over the Zikr page.
                    ZikrPageView(
                        showMantraSheetFromHomePage: $showMantraSheetFromHomePage,
                        showTasbeehPage: $showTasbeehPage
                    )
                    .containerRelativeFrame(.horizontal)
                    .clipped()
                    .id(NavPage.zikr)
                    
                    centerPage
                        .containerRelativeFrame(.horizontal)
                        .clipped()
                        .modifier(SalahPageAnchor())
                        .id(NavPage.main)
                    
                    // Settings, the right page again (owner, 2026-10-19: "I want the settings back in the right-hand side. I'm not
                    // a fan of having Journey there … put Journey back in the hamburger menu only").
                    SettingsPage { sharedState.horizontalPage = .main }
                        .equatable()
                        .environment(viewModel)
                        .containerRelativeFrame(.horizontal)
                        .clipped()
                        .id(NavPage.settings)
                }
                .scrollTargetLayout()
                .modifier(PagerStretch())
                .background { PagerPanLock(live: live) }
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollPage)
            .defaultScrollAnchor(.center)
            .modifier(PagerLock(live: live))     // .scrollDisabled(live.pagerLocked), see PagerLiveState
            .environment(live)
            .ignoresSafeArea(edges: .bottom)
            // The vertical drag (sheet open/close, pull-to-refresh) lives on the ScrollView
            // itself, not on views inside it: the scroll view's pan gets first claim on every
            // touch, takes horizontal ones for paging, and hands vertical ones to this gesture.
            // Nothing inside a page can block paging that way.
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                // Page position, live: 0 = Zikr, 1 = Salah, 2 = Settings (the chrome reads it),
                // plus the content width so the first, unlaid-out report can be ignored.
                let width = geometry.containerSize.width
                return CGSize(width: geometry.contentSize.width / max(width, 1),
                              height: width > 0 ? geometry.contentOffset.x / width : 1)
            } action: { _, v in
                let progress = v.height
                live.scrollProgress = progress
                if v.width >= 2.5 { noteRestingPage(progress: progress, phase: live.pagerPhase) }
                // Commit the page at the detent — the moment the nearest page changes — not when
                // the scroll lands. A slow drag commits as it crosses the midpoint; a flick a few
                // frames into the coast. Landing then confirms a state that's already true, so
                // the tick isn't late. (The old idle-time commit felt like it fired after arrival.)
                // Content narrower than 2.5 pages = the first report before the three pages are
                // laid out (midX at 0.5 → "Zikr"); acting on it left the Salah page labelled Zikr.
                guard v.width >= 2.5 else { return }
                // Only the finger / its coast commits here. A programmatic scroll (tab, menu,
                // deep link) already set horizontalPage; committing "nearest page" during its
                // animation would flip it straight back to where it started.
                guard live.pagerPhase == .interacting || live.pagerPhase == .decelerating else { return }
                let index = Int(progress.rounded())
                let page: NavPage = (index <= 0) ? .zikr : (index >= 2) ? .settings : .main
                if sharedState.horizontalPage != page {
                    // This closure runs inside the scroll view's layout pass; a @Published change
                    // made there isn't delivered to every subscriber (the bottom bar kept the old
                    // page highlighted). Publish on the next run-loop turn instead.
                    DispatchQueue.main.async {
                        guard sharedState.horizontalPage != page else { return }
                        sharedState.horizontalPage = page
                        triggerSomeVibration(type: .light)
                    }
                }
            }
            .simultaneousGesture(abstractedDragGesture)
            .onChange(of: sharedState.navPosition) { _, now in
                if FrameMonitor.on { FrameMonitor.shared.note("list → \(now)") }
            }
            .onChange(of: live.pagerLocked) { _, now in
                if FrameMonitor.on { FrameMonitor.shared.note(now ? "lock" : "unlock") }
            }
            .onAppear {
                // `-perfPage zikr|settings`: start on that page (the idle-CPU check, Release builds too).
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-perfPage"),
                   i + 1 < ProcessInfo.processInfo.arguments.count {
                    let page = ProcessInfo.processInfo.arguments[i + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        sharedState.horizontalPage = page == "zikr" ? .zikr : page == "settings" ? .settings : .main
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-perfToggleList") {
                    FrameMonitor.shared.toggleList = { [sharedState] in
                        withAnimation(CircleMotion.page) {
                            sharedState.navPosition = sharedState.navPosition == .main ? .bottom : .main
                        }
                    }
                    FrameMonitor.shared.startIfAsked()
                }
                guard FrameMonitor.on else { return }
                FrameMonitor.shared.context = { [live, sharedState] in
                    String(format: "pager %@ at %.2f, page %@, list %@ pull %.0f locked %@", String(describing: live.pagerPhase),
                           live.scrollProgress, String(describing: sharedState.horizontalPage),
                           String(describing: sharedState.navPosition), live.pull, live.pagerLocked ? "y" : "n")
                }
                FrameMonitor.shared.startIfAsked()
            }
            .onChange(of: pagerDragActive) { _, active in if !active { pagerDragReleased() } }
            .onScrollPhaseChange { _, phase, context in
                live.pagerPhase = phase
                if FrameMonitor.on { FrameMonitor.shared.note("pager \(phase) · \(FrameMonitor.shared.context())") }
                let geometry = context.geometry
                if geometry.containerSize.width > 0, geometry.contentSize.width >= geometry.containerSize.width * 2.5 {
                    noteRestingPage(progress: geometry.contentOffset.x / geometry.containerSize.width, phase: phase)
                }
                // Settled after a user scroll: bring the scrollPosition binding to the page we
                // actually landed on (the user-driven commit above skips it while moving). Left
                // stale, SwiftUI re-applies the old value whenever it re-lays the pager out —
                // returning from the home screen snapped the pager back to Salah.
                guard phase == .idle else { return }
                let width = context.geometry.containerSize.width
                guard width > 0, context.geometry.contentSize.width >= width * 2.5 else { return }
                let index = Int((context.geometry.visibleRect.midX / width).rounded(.down))
                let landed: NavPage = (index <= 0) ? .zikr : (index >= 2) ? .settings : .main
                if scrollPage != landed {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { scrollPage = landed }
                }
                // A programmatic scroll stopped short (a tab tap, then a vertical swipe at once: the lock's
                // `.scrollDisabled` cut its animation) leaves `horizontalPage` naming a page that isn't showing — the
                // bar lit Settings over Salah and every later Settings tap was a no-op (pager-settings-stuck). The page
                // on screen wins. Next turn, and only if nothing has asked for a page since (that sets `scrollPage`).
                if sharedState.horizontalPage != landed {
                    DispatchQueue.main.async {
                        guard live.pagerPhase == .idle, scrollPage == landed,
                              sharedState.horizontalPage != landed else { return }
                        sharedState.horizontalPage = landed
                    }
                }
            }
            .onChange(of: sharedState.horizontalPage) { _, wanted in
                // Programmatic nav (bottom bar, menu, widget deep link): scroll the pager to match, quietly when the
                // change asked for it (`go(to:animated: false)` — this used to spring every change: audit D, bug 7).
                // Not while the finger or the coast owns the pager: that commit came from the
                // scroll itself and it's already heading there.
                let quiet = sharedState.takeQuietPageChange()
                guard live.pagerPhase == .idle || live.pagerPhase == .animating else { return }
                guard scrollPage != wanted else { return }
                if quiet {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { scrollPage = wanted }
                } else {
                    withAnimation(CircleMotion.movement(CircleMotion.page, reduced: reduceMotion)) { scrollPage = wanted }
                }
            }
            // .transition(.move(edge: .leading).combined(with: .opacity))

            // Fixed chrome: top bar (menu + location / page title) and bottom bar, over the
            // pager so they don't travel with the Salah page. Salah + Zikr only; fades out as
            // Settings slides in (Settings brings its own header).
            PagerChromeView(
                live: live,
                showMapPage: $showMapPage, showDailyAyahPage: $showDailyAyahPage,
                showMantrasPage: $showMantrasPage, showSalahHistoryV1: $showSalahHistoryV1,
                showSalahHistoryV2: $showSalahHistoryV2, showZikrHistory: $showZikrHistory,
                showInsightsPage: $showInsightsPage, showOldInsights: $showOldInsights,
                showNamesPage: $showNamesPage, showTasbeehPage: $showTasbeehPage
            )
            // The locked Zikr page's narration is the whole app for a moment: the bars step away (ZikrLock.focus).
            .opacity(ZikrLock.shared.focus ? 0 : 1)
            .allowsHitTesting(!ZikrLock.shared.focus)
            .animation(.easeInOut(duration: 0.5), value: ZikrLock.shared.focus)

            // "shukr lost your location" (circle step 3b): its buttons, and what runs it — the circle shows the rest.
            LostPageLayer()

            // The first-run tour (Tour.swift): its callout over the live app, never over a cover or a session.
            // Any stage cover too (the ☰ menu, the map, a row's time editor): the edit step's "Close it" is its close.
            // Not the scene phase (owner: the tooltip went away and came back with Control Center / a notification):
            // only something truly over the page hides it.
            TourLayer(covered: somethingCovers || showTasbeehPage || CircleStage.shared.lost != nil
                      || morningSession != nil || !CircleStage.shared.covers.isEmpty)
            // A milestone a mark just earned: the first mark's glow and card, in its words (YourJourney.swift).
            MilestoneCelebrationLayer(covered: somethingCovers || showTasbeehPage || CircleStage.shared.lost != nil
                                      || morningSession != nil || !CircleStage.shared.covers.isEmpty)
            #if DEBUG
                // What may hide the tour's callout (Sami's step 1 with nothing on screen): "TOUR cover …" on each change.
                .onChange(of: "\(TourRuntime.shared.step?.rawValue ?? "-") · \(tourHiddenReason)", initial: true) { _, line in
                    if TourRuntime.shared.step != nil { print("TOUR cover \(line)") }
                }
            #endif
            // The session tour's last tips, on the Zikr page (CountTips: History, then "your turn").
            ZikrPageTipsLayer(covered: somethingCovers || showTasbeehPage || !CircleStage.shared.covers.isEmpty,
                              onZikr: sharedState.horizontalPage == .zikr)

            #if DEBUG
            TourDemoLayer()   // `-demoTour circle|list|swipe|count|hintMark [-tourStyle line|callout]`: the pictures
            #endif
        }
        // The tour: from Settings → Show me around again (the Salah page, the list closed), or once after the first-run
        // setup when the page has come back from the welcome. Both open at its door, the invitation (decision
        // onboarding-start A).
        .onReceive(NotificationCenter.default.publisher(for: TourRuntime.start)) { _ in
            sharedState.go(to: .main)
            SalahSheetDrag.closeQuietly(sharedState)
            // Settings → Show me around again: straight in, no invitation (owner: "clearly they do since they
            // pressed that button").
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                TourRuntime.shared.begin()
            }
        }
        .onChange(of: CircleStage.shared.pageHidden, initial: true) { _, hidden in
            guard !hidden else { return }
            inviteToTour(after: 2.5)
        }
        // The setup's end lands on this circle with the page already shown: the breath starts from there, so the
        // invitation doesn't come the instant the setup goes (owner: "a bit of a pause before showing the want a
        // quick look around").
        .onReceive(NotificationCenter.default.publisher(for: FirstRunSetup.finished)) { _ in inviteToTour(after: 3) }
        // A practice mark undone: the post-salah pill it brought goes too.
        .onChange(of: TourRuntime.shared.clearPill) { _, _ in live.postSalahNudge = nil }
        // The first real mark's pill, held through the celebration, comes on its Continue.
        .onChange(of: TourRuntime.shared.pillRelease) { _, _ in
            if let name = TourRuntime.shared.heldPillName { live.postSalahNudge = name }
        }
        // The welcome lands on the Salah circle only if nothing covers it (a widget may have opened
        // Daily Ayah / 99 Names / the map); otherwise it opens out like a doorway.
        .onChange(of: somethingCovers || showTasbeehPage, initial: true) { _, covered in
            WelcomeTarget.canLand = !covered
        }
        // A zikr reminder's "Start now" while the app is open (on a cold / background launch the
        // app-group flags below do it on activation).
        // A deleted task (its zikr deleted, or the task itself) must not stay selected: reading a
        // deleted row's attributes crashes.
        // What's new → "Open in shukr": after its sheet has gone, go to that feature.
        .onReceive(NotificationCenter.default.publisher(for: WhatsNew.go)) { note in
            guard let link = note.object as? String else { return }
            if link == "map" && showQiblaMap { return }     // already there: don't close and reopen it
            // After the sheet has gone (clearCovers waits for it): pushing the library while it was still closing
            // left a second search field in its bottom bar.
            clearCovers {
                switch link {
                case "salah": sharedState.horizontalPage = .main
                case "zikr": sharedState.horizontalPage = .zikr
                case "settings": sharedState.horizontalPage = .settings
                case "history": showZikrHistory = true
                case "azkar": showMantrasPage = true
                case "map": sharedState.horizontalPage = .main; showQiblaMap = true
                case "names": showNamesPage = true
                case "ayah": showDailyAyahPage = true
                case "insights", "journey": JourneyPresenter.shared.open = true
                default: break
                }
            }
        }
        // "I already prayed" on a banner while the app is in front (audit B7): the mark lands in the shared store now
        // and the page used to show it unmarked until the next activation (a re-tap then rescored it).
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in openFromWidgetFlags() }
        // Excused from prayer turned on / off / changed (Excused.swift): the touched days' scores and the streaks.
        .onReceive(NotificationCenter.default.publisher(for: Excused.changed)) { note in
            CircleStage.shared.excused = Excused.current
            // A new estimate or the zikr switch changes no counted day: no recount (review).
            if note.object as? String != Excused.lightChange { viewModel.excusedChanged() }
        }
        // The circle's day line moves on with the day (review: it stayed "Day 3" past midnight).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            CircleStage.shared.excused = Excused.current
        }
        .onReceive(NotificationCenter.default.publisher(for: Excused.openSheet)) { _ in showExcused = true }
        .onReceive(NotificationCenter.default.publisher(for: Excused.askResume)) { note in
            resumePrayer = note.object as? PrayerModel
            askingResume = true
        }
        .alert("Are you back to praying?", isPresented: $askingOverdue) {
            Button("I'm back") { Excused.end() }
            Button("Not yet") { showExtend = true }   // a new estimate (owner)
        } message: {
            Text("You're set as excused from prayer, and your estimate has passed.")
        }
        .sheet(isPresented: $showExtend) { ExcusedExtendSheet().stageCover("excusedExtend") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in askIfOverdue() }
        .onAppear { askIfOverdue() }
        .alert("Prayers are paused", isPresented: $askingResume) {
            Button("I'm back") {
                Excused.end()
                // The prayer she tapped, if it's due now (its time still on), is marked: that's what she meant.
                if let p = resumePrayer, !p.isCompleted, !Excused.covers(start: p.startTime, end: p.endTime), p.startTime <= Date() {
                    viewModel.togglePrayerCompletion(for: p)
                }
                resumePrayer = nil
            }
            Button("Not yet", role: .cancel) { resumePrayer = nil }
        } message: {
            Text("You're set as excused from prayer. Are you back to praying?")
        }
        .sheet(isPresented: $showExcused) { NavigationStack { ExcusedSheet() }.stageCover("excused") }   // its ⓘ pushes
        .onAppear { CircleStage.shared.excused = Excused.current }
        .onReceive(NotificationCenter.default.publisher(for: TaskModel.didDelete)) { note in
            guard let gone = note.object as? Set<PersistentIdentifier>,
                  let selected = sharedState.selectedTask, gone.contains(selected.persistentModelID) else { return }
            sharedState.selectedTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: MantraModel.didDelete)) { note in
            // Only the identifier is read: the row is gone and its properties must not be touched.
            guard let gone = note.object as? PersistentIdentifier,
                  sharedState.mantraForSession?.persistentModelID == gone else { return }
            sharedState.mantraForSession = nil   // audit A8
        }
        // A shared task opened in shukr (TaskSharing): to the Zikr page, where the wheel opens its review — after a
        // session or the setup, if one is up.
        .onReceive(NotificationCenter.default.publisher(for: TaskSharing.received)) { _ in openSharedTask() }
        .onReceive(NotificationCenter.default.publisher(for: FirstRunSetup.finished)) { _ in openSharedTask() }
        .onChange(of: showTasbeehPage) { _, open in if !open { openSharedTask() } }
        .onAppear { openSharedTask() }
        // Zikr's lock: anyone who already used Zikr keeps it open (once per install; ZikrLock).
        .onAppear {
            ZikrLock.shared.checkExisting(in: context)
            FirstZikr.fillMemo(in: context)
        }
        // A zikr's page asked to start one of its tasks: close what covers the pager, then the
        // Zikr page's wheel starts it.
        .onReceive(NotificationCenter.default.publisher(for: ZikrFocus.startNotification)) { _ in
            guard !showTasbeehPage else { return }
            clearCovers {
                // The wheel starts it once the Zikr page has arrived (it was a guessed 0.35 s).
                guard await sharedState.navigate(to: .zikr) else { return }
                NotificationCenter.default.post(name: ZikrFocus.wheelStartNotification, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ZikrReminders.openTask)) { note in
            guard let taskID = note.object as? String, scenePhase == .active else { return }
            lastDeepLinkAt = Uptime.now   // no reminders card over the zikr it opened
            let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
            store?.removeObject(forKey: "widgetZikrTask")
            store?.setValue(false, forKey: "widgetTasbeeh")
            guard !showTasbeehPage else { return }
            clearCovers {
                sharedState.horizontalPage = .zikr
                ZikrFocus.request(taskID)
            }
        }
        .sheet(item: $healthCard) { issue in
            ReminderHealthCard(issue: issue) { healthCard = nil }
                .onAppear {
                    healthCardAppeared = true
                    NotificationHealth.shared.markCardShown(issue)
                }
                .stageCover("healthCard")
        }
        // The first-run setup is done: a widget open that arrived during it, now.
        .onReceive(NotificationCenter.default.publisher(for: FirstRunSetup.finished)) { _ in openFromWidgetFlags() }
        // A widget's intent wrote its flags after the launch had begun (widget-open-chrome): now, not at the next open.
        .onReceive(NotificationCenter.default.publisher(for: DeepLinkSignal.arrived)) { _ in openFromWidgetFlags() }
        // A marked row tapped in the Prayers widget's times list: the app asks (showWidgetUnmarkWhenClear).
        .onChange(of: widgetUnmark != nil) { _, up in CircleCover.set("widgetUnmark", up) }
        // A request that waited out a tasbeeh session: now.
        .onChange(of: showTasbeehPage) { _, up in
            if !up { widgetUnmarkToken += 1; showWidgetUnmarkWhenClear(token: widgetUnmarkToken) }
        }
        .onAppear {
            showMorningCardWhenClear()
            // A cold launch from a widget: straight there as the page first comes up, not after the activation.
            openFromWidgetFlags()
            TourRuntime.repairScoresOnce(viewModel)
        }
        // A page pushed over the pager (☰'s destinations, a widget's page, Settings' pushes) is a cover until the pager is
        // back on screen with the pop finished — UIKit's did-appear (SwiftUI's onAppear comes as the pop starts). Popping
        // closes it (any depth: the flags).
        .background {
            AppearanceProbe(didAppear: { CircleCover.set("pushedPage", false) },
                            didDisappear: { CircleCover.set("pushedPage", true, close: { dismissCovers() }) })
        }
        // The circle shows the morning while its card is up (circle step 3); the card clears it as it leaves.
        .onChange(of: morningSession) { _, session in
            if session != nil || CircleStage.shared.morning != nil { CircleStage.shared.morning = session }
        }
        // The palette's Play → Good morning (SalahLook.swift): the welcome from black onto the card, with the latest
        // session — read only; Done just closes it.
        .onReceive(NotificationCenter.default.publisher(for: SalahLookPlay.morning)) { _ in
            var latest = FetchDescriptor<SessionDataModel>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
            latest.fetchLimit = 1
            guard morningSession == nil, let session = try? context.fetch(latest).first else { return }
            NotificationCenter.default.post(name: SalahLookPlay.welcome, object: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                var quiet = Transaction(); quiet.disablesAnimations = true
                withTransaction(quiet) { morningSession = session }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WelcomeGate.raiseCurtain)) { _ in goToSalahForMorningCard() }
        .overlay {
            if let morningSession {
                MorningCurtain(session: morningSession, onDone: {
                    SleepMorning.clear()
                    self.morningSession = nil
                }, onHistory: {
                    SleepMorning.clear()
                    self.morningSession = nil
                    // History is the Zikr tab's: locked, the Zikr page and its lock instead (ZikrLock).
                    if ZikrLock.shared.locked { sharedState.go(to: .zikr) } else { showZikrHistory = true }
                })
                .transition(.identity)
            }
        }
        // A prayer marked on the Apple Watch (WatchZikrSync): same as after a widget mark.
        .onReceive(NotificationCenter.default.publisher(for: .watchMarkedPrayer)) { note in
            viewModel.reconcileAfterWidgetWrites()
            if let day = note.object as? Date { viewModel.calculateDayScore(for: day) }   // a late mark's own day
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .background || newScenePhase == .active {
                WatchSync.shared.send()   // the watch's prayer times, city and today's ✓s
            }
            if newScenePhase == .background {
                SleepMorning.armIfPending()   // the morning card waits for the next open
                goToSalahForMorningCard()
                // Tasks added / edited / reordered: let the Zikr widget catch up (it reads the
                // shared store, so save first).
                try? context.save()
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.zikr)
                ControlCenter.shared.reloadControls(ofKind: WidgetKinds.zikrControl)
            }
            if newScenePhase == .active {
                showMorningCardWhenClear()

                viewModel.loadTodaysPrayerObjects()
                viewModel.reconcileAfterWidgetWrites() // prayers completed from the widget while we were closed
                viewModel.catchUpMasjidChecks()        // …and which prayers were at a masjid
                
                openFromWidgetFlags()
                maybeShowHealthCard()
                

            }
        }
        #if DEBUG
        .task { await runDemoWidgetUnmark() }
        .task { await runDemoLand() }
        .task { await runDemoMasjid() }
        .task { await runDemoSeeds() }
        #endif
//        .onChange(of: sharedState.navPosition){ oldValue, newValue in
//            if oldValue == .top && newValue == .main  {
//                sharedState.resetTasbeehInputs()
//                print("ResetTasbeehInputs cuz we dismissed DailyTasks.")
//            }
//        }
        // Settings' ways in (deep link "settings", the circle's "Alarm 4:45 AM", screenshots args) page to it, whatever
        // covers the Salah page closed first; a jump (the alarm row) once the page has come to rest.
        .onChange(of: SettingsPresenter.shared.open) { _, wanted in
            guard wanted else { return }
            SettingsPresenter.shared.open = false
            let jump = SettingsPresenter.shared.takeJump()
            clearCovers {
                Task { if await sharedState.navigate(to: .settings), let jump { SettingsJump.shared.request(jump) } }
            }
        }
        .onChange(of: sharedState.horizontalPage) { left, now in
            // Settings may have changed how times are worked out: refetch on leaving its page — once the pager has
            // landed (run at the page's commit, mid-swipe, it stalled two frames: perf trace 2026-10-10).
            if left == .settings, now != .settings {
                Task { @MainActor in
                    _ = await CircleStage.shared.until(deadline: 2) { CircleStage.shared.restingPage != nil }
                    viewModel.fetchPrayerTimes(cameFrom: "left the Settings page")
                }
            }
        }
        .navigationDestination(isPresented: $showMapPage) {
            LocationMapContentView()
        }
        .navigationDestination(isPresented: $showDailyAyahPage) { DailyAyahView() }
        .navigationDestination(isPresented: $showMantrasPage) { ZikrAreaPage(start: .azkar) }
        .navigationDestination(isPresented: $showSalahHistoryV1) { SimpleDailyScoreView() }
        .navigationDestination(isPresented: $showSalahHistoryV2) { PrayerEditorView() }
        .navigationDestination(isPresented: $showZikrHistory) { ZikrAreaPage(start: .history) }
        .navigationDestination(isPresented: $showInsightsPage) { InsightsView() }
        .navigationDestination(isPresented: $showOldInsights) { InsightsView(layout: .old) }
        .navigationDestination(isPresented: $showNamesPage) { NamesOfAllahView() }
        // Memories (PrayerMemories.swift), from the ☰ menu or the day page's link: pushed, so it swipes back (decision
        // swipe-back-pages A).
        .navigationDestination(isPresented: Binding(get: { MemoriesPresenter.shared.open },
                                                    set: { MemoriesPresenter.shared.open = $0 })) { MemoriesPage() }
        // Journey (Journey.swift), pushed from ☰, the day page's "Journey ›", To make up's pill and What's new (owner,
        // 2026-10-19: "put Journey back in the hamburger menu only" — it was the pager's right page from 2026-10-17).
        .navigationDestination(isPresented: Binding(get: { JourneyPresenter.shared.open },
                                                    set: { JourneyPresenter.shared.open = $0 })) { JourneyPage() }
        // `-demoJourneyFlightRun N`: Journey opened for its flights' auto run (JourneyMonthHost) — a launch argument only, so
        // the frame log can be read in Release on his phone.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demoJourneyFlightRun") else { return }
            try? await Task.sleep(for: .seconds(1))
            JourneyPresenter.shared.open = true
        }
        .onChange(of: chosenMantra) {_, newMantra in
            if let text = newMantra {
                sharedState.titleForSession = text
                sharedState.mantraForSession = chosenMantraObject
            }
        }
        .whatsNewReturnPill()   // after What's new → "Open in shukr" to a pager page
        #if PERFARGS
        .task {
            Excused.applyDebugArgs()
            try? await Task.sleep(for: .seconds(2))
            if ProcessInfo.processInfo.arguments.contains("-perfExplore") { perfExplore = true }
        }
        .sheet(isPresented: $perfExplore) { NavigationStack { ExploreSimplePage() } }
        #endif
        #if DEBUG
        .sheet(item: $demoMantra) { m in MantraEditorView(mantra: m) }
        .newZikrCard(isPresented: $demoNewZikr)
        .sheet(isPresented: $demoWhatsNew) { WhatsNewView() }
        #if DEBUG
        // `-whatsNewPerf`: close and open it again, to time a warm open (no launch work around it).
        .onReceive(NotificationCenter.default.publisher(for: WhatsNewPerf.reopen)) { _ in
            demoWhatsNew = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { WhatsNewPerf.opened = 0; demoWhatsNew = true }
        }
        #endif
        // DEBUG `-demoScheduledNotifications [-demoReminderPage la|alarm|widget|data]`: Your Notifications / Live Activities / Fajr Alarms / Your Data.
        .sheet(isPresented: $demoScheduled) {
            NavigationStack {
                switch UserDefaults.standard.string(forKey: "demoReminderPage") {
                case "la": ScheduledLiveActivitiesPage()
                case "alarm": FajrAlarmCheckView()
                case "widget": PrayersWidgetAppearancePage()
                case "data": YourDataPage()
                default: YourRemindersView()
                }
            }
            .infoModalHost()   // its ⓘ cards over the sheet (the app's host is under it)
        }
        // DEBUG `-demoSadaqah`: full screen, as Settings pushes it (a sheet put its own sheets on a sheet in the shots).
        .fullScreenCover(isPresented: $demoSadaqah) { NavigationStack { SadaqahPage() } }
        .sheet(isPresented: $demoExplore) {
            NavigationStack {
                switch ExplorePageVariant(rawValue: UserDefaults.standard.string(forKey: ExplorePageVariant.key) ?? "") ?? .simple {
                case .simple: ExploreSimplePage()
                case .grouped: ExploreGroupedPage()
                case .showcase: ExploreShowcasePage()
                case .lean: ExploreLeanPage()
                case .original: ExploreShukrPage()
                }
            }
        }
        #endif
        .sheet(isPresented: $showMantraSheetFromHomePage) {
            MantraPickerView(
                isPresented: $showMantraSheetFromHomePage,
                selectedMantra: $chosenMantra,
                selectedMantraObject: $chosenMantraObject,
                presentation: [.height(400)]
            )
            .stageCover("mantraPicker")
        }
        .fullScreenCover(isPresented: $showTasbeehPage, onDismiss: { SessionHandoff.shared.coverGone() }) {
            // A session opened out of a Zikr ring under the soft look leaves the same way: it plays its close over the
            // wheel (SessionHandoff), then the cover goes with no animation (below, on `.done`). In the background (a
            // sleep finish closes it there, and the morning flow needs it gone in that turn) — and every other
            // session — at once, as before. Nothing here guesses how long the close takes.
            tasbeehView(isPresented: Binding(
                get: { showTasbeehPage },
                set: { up in
                    let handoff = SessionHandoff.shared
                    if !up, handoff.shouldPlayClose(appActive: UIApplication.shared.applicationState == .active) {
                        handoff.requestClose()
                    } else {
                        showTasbeehPage = up
                    }
                }))
            // The session draws its own page; clear behind it only for the soft entry (it fades in over the wheel) —
            // otherwise the usual opaque cover, so the page under it isn't kept drawing (Sami's audit). Read live
            // (observable) until the cover has really gone.
            .presentationBackground(SessionHandoff.shared.soft ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color(.systemBackground)))
            .circleThemeRoot()   // the look, set again on the cover's root (CircleTheme.swift)
        }
        // The session's close has played: the cover goes, with no animation of its own.
        .onChange(of: SessionHandoff.shared.phase == .done) { _, done in
            guard done else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { showTasbeehPage = false }
        }
        
        .edgesIgnoringSafeArea(.bottom)
        .circleThemeRoot()       // the look as one value for everything on the pages (CircleTheme.swift)
    }

    

    // MARK: - Center page
    /// Main circle + bottom sheet, with the top bar / side menu overlaid. Lives inside the pager.
    private var centerPage: some View {
        ZStack {
            Color("bgColor").opacity(0.001)
                .edgesIgnoringSafeArea(.all)

            SalahPageContent(
                live: live,
                showQiblaMap: $showQiblaMap,
                showTasbeehPage: $showTasbeehPage,
                showDailyAyahView: $showDailyAyahView, showMantraSheetFromHomePage: $showMantraSheetFromHomePage
            )
        }
        .navigationBarHidden(true)
    }

    /// The Salah page body: the main circle over the salah sheet, laid out with Spacers the
    /// way it always was. Opening inserts the sheet (move-from-bottom + fade) and the Spacers
    /// carry the circle up; the page animates that itself, whoever changed `navPosition` (swipe,
    /// chevron, a widget — rule 6). The finger never drags the sheet: the
    /// owner tried follow-the-finger versions (a custom gesture, then a native ScrollView) and
    /// asked for this pop back (2026-09-24). `live.pull` is the resisted drag nudge.
    struct SalahPageContent: View {
        @Environment(SharedStateClass.self) var sharedState
        @Environment(PrayerViewModel.self) var viewModel
        @Environment(\.circleTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// The look prototype's row motion, read as state so a change redraws the page (it was read from
        /// UserDefaults in the body: audit D, finding 11).
        @AppStorage(RowMotion.key) private var rowMotionRaw = RowMotion.standard.rawValue
        var live: PagerLiveState
        @Binding var showQiblaMap: Bool
        @Binding var showTasbeehPage: Bool
        @Binding var showDailyAyahView: Bool
        @Binding var showMantraSheetFromHomePage: Bool

        private var showBottom: Bool { sharedState.navPosition == .bottom }
        /// CustomBottomBar's height. The chevron / bottom bar used to sit at the bottom of this
        /// VStack; they're fixed chrome now, so their room is kept and the Spacers split the
        /// page the same way.
        private let bottomChromeHeight: CGFloat = 86
        /// With the sheet closed the circle sits at the centre of the safe area, exactly where the
        /// welcome screen's circle is, so "continue" reads as that circle becoming this one. The
        /// pager ignores the bottom safe area, so reserving the home-indicator inset (instead of
        /// the bar's 86 pt) centres it; 86 pt put it ~26 pt high.
        private let closedBottomReserve: CGFloat = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 34

        @AppStorage(SalahSheetDrag.key) private var follows = SalahSheetDrag.defaultOn
        /// The following sheet's measurements: the circle's and the list's sizes, and the resting places worked out
        /// from them (SheetRests). Not per-frame.
        @State private var circleSize: CGSize = .zero
        @State private var listSize: CGSize = .zero
        @State private var rests = SheetRests()
        @State private var restsReady = false

        var body: some View {
            let _ = viewModel.revision   // redraw after marks / edits, as on objectWillChange (step 8)
            if follows { followingBody } else { poppingBody }
        }

        /// The circle, its box measured for the following sheet's resting layouts.
        private var circle: some View {
            ZStack {
                MainCircleView(showQiblaMap: $showQiblaMap, showTasbeehPage: $showTasbeehPage)
                    .geometryGroup()
                    .onAppear {
                        print("⭐️ prayerTimesView onAppear")
                        viewModel.fetchPrayerTimes(cameFrom: "onAppear pulse circle Circles")
                        viewModel.loadTodaysPrayerObjects()
                        viewModel.checkToResetStreak() //viewModel.calculatePrayerStreak()
                    }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { if circleSize != $0 { circleSize = $0 } }
            #if DEBUG
            .modifier(DemoTip(tip: FlipCircleTip(), on: TourHintDemo.tip == "circle"))
            #endif
        }

        /// The pop (the switch off): the Spacer layout, the sheet inserted and removed with `navPosition`.
        /// The open page's gap between the list's bottom and "N done": it flexes like the other spacers but only within
        /// these bounds (owner, the middle ground: folded it rests where it used to, opening "N done" lets the whole list
        /// drift down a little as it mostly grows upward, and it never comes closer than 16 pt).
        static let listBottomGap: ClosedRange<CGFloat> = 16...44
        /// The gap under the open list for the list's height: 44 pt with two rows, giving up a quarter of every point the
        /// list grows (so opening "N done" moves the whole list down a little as it mostly grows upward — owner: anchored
        /// it "can't even tell"), never below 16 pt.
        private var listGap: CGFloat {
            let grown = max(listSize.height - 2 * SalahLook.raisedRowHeight, 0)
            return min(max(Self.listBottomGap.upperBound - grown * 0.25, Self.listBottomGap.lowerBound), Self.listBottomGap.upperBound)
        }
        /// Between the ring and the open list, at least this much (12 pt on each of the two spacers between them).
        static let ringListMin: CGFloat = 12

        private var poppingBody: some View {
            let lost = CircleStage.shared.lost
            // No spacing and spacers that can shrink to nothing: with five rows open the page ran out of room and the
            // overflow pushed the list down into "N done" (owner's recording); now the circle gives way.
            return VStack(spacing: 0) {
                Spacer(minLength: 0)
                if showBottom {
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                // The lost page (circle step 3b): the circle risen, with room for its title above and what sharing
                // location gives below, and the buttons at the bottom (LostWords / LostPageLayer measure them).

                circle
                // The lost page (circle step 3b): room for its title above and what sharing location gives below, as
                // padding — a height that animates; zero otherwise (an extra view in this stack added its spacing, and
                // inserting / removing one twitched the circle at the hand-off).
                .padding(.top, lost.map { $0.risen ? $0.titleHeight + 28 : 0 } ?? 0)
                .padding(.bottom, lost.map { $0.risen ? 28 + $0.reasonsHeight : 0 } ?? 0)
                // The lost page's rise and the glide back down: the page animates them itself (a transaction from the
                // lost page's runner had to cross into the pager — audit B).
                .animation(lost.map { $0.risen ? CircleMotion.Lost.rise : CircleMotion.Lost.down }, value: lost?.risen)
                .zIndex(3)

                Spacer(minLength: showBottom ? Self.ringListMin : 0)

                if showBottom {
                    Spacer(minLength: Self.ringListMin)   // the ring never closer than 24 pt to the list
                    BottomSharedView(showDailyAyahView: $showDailyAyahView)
                    .modifier(PullFade(live: live))
                    // The opening on the Salah circle (circle step 4): the list waits, then fades in as the ring lands.
                    .opacity(CircleStage.shared.pageHidden ? 0 : 1)
                    .animation(CircleMotion.ease(CircleMotion.pageRevealDuration), value: CircleStage.shared.pageHidden)
                    // Today's look: slides up from the bottom and fades (owner, 2026-10-01: "i liked our initial
                    // transition better"). Soft looks: rises in and drops out `CircleMotion.listTravel` (200 pt) as it
                    // fades — farther than the circle moves, so the ring and the rows never ghost over each other (Izhan).
                    // Reduce Motion: a fade in place.
                    .transition(reduceMotion ? .opacity : theme.listEntrance)
                    // The gap under the list flexes only within `listBottomGap` (never into "N done").
                    Spacer(minLength: Self.listBottomGap.lowerBound).frame(maxHeight: Self.listBottomGap.upperBound)
                }

                // Soft looks: room for "N done" above the bottom bar (SoftDoneFooter, in the chrome).
                Color.clear.frame(height: (showBottom ? bottomChromeHeight + theme.listFooterRoom
                                                      : closedBottomReserve)
                                          + (lost.map { $0.risen ? $0.buttonsHeight : 0 } ?? 0))   // the lost page's buttons
            }
            // The sheet popping up or down: the page animates it itself, whoever changed it — a transaction from the
            // chrome didn't always reach into the pager (audit D, finding 3).
            .animation(CircleMotion.movement(CircleMotion.page, reduced: reduceMotion), value: showBottom)
            // "N done" toggled (in the list, or the soft looks' footer up in the chrome): the page animates the
            // re-centring itself — the chrome's transaction didn't always reach it, so the fold sometimes snapped, the
            // circle jumping ~70 pt (Sami's audit, finding 2).
            .animation(RowMotion.resolved(rowMotionRaw).animation(springy: CircleMotion.movement(CircleMotion.spring, reduced: reduceMotion)),
                       value: PrayerListFold.shared.showDone)
        }

        // MARK: The sheet that follows the finger (SalahSheetDrag)

        /// The page as it rests closed — the pop's closed layout, untouched, so the welcome still lands on it.
        private func closedPage(lost: LostStage?) -> some View {
            VStack {
                Spacer(minLength: 0)
                circle
                    .padding(.top, lost.map { $0.risen ? $0.titleHeight + 28 : 0 } ?? 0)
                    .padding(.bottom, lost.map { $0.risen ? 28 + $0.reasonsHeight : 0 } ?? 0)
                    .animation(lost.map { $0.risen ? CircleMotion.Lost.rise : CircleMotion.Lost.down }, value: lost?.risen)
                Spacer(minLength: 0)
                Color.clear.frame(height: closedBottomReserve + (lost.map { $0.risen ? $0.buttonsHeight : 0 } ?? 0))
            }
        }

        /// The pop's two layouts with empty boxes the circle's and the list's sizes: where each rests, open and closed.
        private var restGhosts: some View {
            let measure = { (key: WritableKeyPath<SheetRests, CGFloat>, top: Bool) in
                { (frame: CGRect) in
                    let v = top ? frame.minY : frame.midY
                    if abs(rests[keyPath: key] - v) > 0.25 { rests[keyPath: key] = v }
                }
            }
            return ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear.frame(width: circleSize.width, height: circleSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.closedCircleY, false))
                    Spacer(minLength: 0)
                    Color.clear.frame(height: closedBottomReserve)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0); Spacer(minLength: 0); Spacer(minLength: 0)
                    Color.clear.frame(width: circleSize.width, height: circleSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.openCircleY, false))
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { f in
                            if DayPageState.shared.salahRing != f { DayPageState.shared.salahRing = f }   // Journey's layout
                        }
                    Spacer(minLength: Self.ringListMin); Spacer(minLength: Self.ringListMin)
                    Color.clear.frame(width: listSize.width, height: listSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.openListTop, true))
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { f in
                            if DayPageState.shared.salahList != f { DayPageState.shared.salahList = f }   // Journey's layout
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(SalahSheetDrag.space)).maxY }) { v in
                            if abs(rests.openListBottom - v) > 0.25 { rests.openListBottom = v }
                        }
                    Color.clear.frame(height: listGap)   // the gap gives as the list grows (`listGap`)
                    Color.clear.frame(height: bottomChromeHeight + theme.listFooterRoom)
                }
            }
            .hidden()
            .allowsHitTesting(false)
        }

        /// Vertical live dragging (round 5, SalahSheetDrag.swift): the pop's closed page and the list laid over the page,
        /// each moved by the sheet's progress (`SheetCircleRide`, `SheetListRide` — the only views reading it, so a
        /// frame never rebuilds the circle or the list). The list runs from under the page's bottom edge to the open
        /// rest the pop's layout gives (`restGhosts`). The drag is the pager's (abstractedDragGesture → SheetSpring).
        private var followingBody: some View {
            let lost = CircleStage.shared.lost
            return GeometryReader { geo in
                let height = geo.size.height
                let openTop = rests.openListTop
                // The list's run: from just under the page's bottom edge to its open top.
                let run = max(height - openTop, 1)
                // The open rest moving (the fold, the list's rows changing) glides, after the first measure.
                let restMotion = restsReady ? RowMotion.resolved(rowMotionRaw)
                    .animation(springy: CircleMotion.movement(CircleMotion.spring, reduced: reduceMotion)) : nil
                ZStack(alignment: .top) {
                    if lost == nil {
                        BottomSharedView(showDailyAyahView: $showDailyAyahView)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { if listSize != $0 { listSize = $0 } }
                            .opacity(CircleStage.shared.pageHidden ? 0 : 1)
                            .animation(CircleMotion.ease(CircleMotion.pageRevealDuration), value: CircleStage.shared.pageHidden)
                            // Anchored at its bottom (the open rest's bottom, as `poppingBody` pins it), slid down by how
                            // closed the sheet is: rows growing or folding move only its top, never its bottom (owner: it
                            // dipped into "N done" while the measured top jumped ahead of the rows' animation).
                            .padding(.bottom, rests.openListBottom > 0 ? height - rests.openListBottom
                                                                       : bottomChromeHeight + theme.listFooterRoom + Self.listBottomGap.upperBound)
                            .frame(width: geo.size.width, height: height, alignment: .bottom)
                            .modifier(SheetListRide(live: live))
                            // Its bottom glides to the new rest with the rows' own curve (it moves only within the gap's range).
                            .animation(restMotion, value: rests.openListBottom)
                    }
                    closedPage(lost: lost)
                        .frame(width: geo.size.width, height: height)
                        .modifier(SheetCircleRide(live: live, delta: rests.openCircleY - rests.closedCircleY))
                        .animation(restMotion, value: rests.openCircleY - rests.closedCircleY)
                }
                .frame(width: geo.size.width, height: height, alignment: .top)
                .background { restGhosts }
                .coordinateSpace(.named(SalahSheetDrag.space))
                .onAppear {
                    setRun(run)
                    let spring = live.sheetSpring
                    spring.onRest = { [sharedState] open in
                        let resting: SharedStateClass.ViewPosition = open ? .bottom : .main
                        DispatchQueue.main.async {
                            guard sharedState.navPosition != resting else { return }
                            withAnimation(CircleMotion.page) { sharedState.navPosition = resting }
                        }
                    }
                    spring.place(open: showBottom)
                }
                .onChange(of: run) { _, new in setRun(new) }
                // Moved by code (the chevron, a widget, the tour, setup): the spring goes there; quietly when asked.
                .onChange(of: sharedState.navPosition) { _, _ in
                    let spring = live.sheetSpring
                    guard !spring.dragging, spring.heading != showBottom || (!spring.isMoving && abs(spring.progress - (showBottom ? 1 : 0)) > 0.01) else { return }
                    let quiet = SalahSheetDrag.takeQuiet()
                    spring.go(open: showBottom, animated: !quiet && UIApplication.shared.applicationState == .active)
                }
                .onChange(of: rests) { _, new in
                    // The day's line centres itself in the open page's room under the ring (106 = the ring's radius + band).
                    let gap = new.openListTop - new.openCircleY - 106
                    if new.openListTop > 0, abs((DayPageState.shared.ringListGap ?? -1) - gap) > 0.5 {
                        DayPageState.shared.ringListGap = max(gap, 0)
                    }
                    guard !restsReady, new.openListTop > 0 else { return }
                    DispatchQueue.main.async { restsReady = true }
                }
            }
        }

        /// The run changed (the first measure, the fold, a rotation): keep the sheet where it is, as a share of the run.
        private func setRun(_ run: CGFloat) {
            let spring = live.sheetSpring
            let p = live.sheetRun > 0 ? spring.progress : (showBottom ? 1 : 0)
            if live.sheetRun != run { live.sheetRun = run }
            if live.sheetTravel != run { live.sheetTravel = run }
            if !spring.dragging, !spring.isMoving { spring.place(open: showBottom) } else { spring.progress = p }
        }
    }

    /// The open sheet fades a little with the drag nudge. Its own modifier, so a drag re-renders only this, not the page
    /// and its circle (audit D, finding 7).
    private struct PullFade: ViewModifier {
        let live: PagerLiveState
        func body(content: Content) -> some View { content.opacity(1 - Double(live.pull / 90)) }
    }

}


struct ContentView3_Previews: PreviewProvider {
    static var previews: some View {
        let sharedState = SharedStateClass()
        
        // Create a preview ModelContainer
        let previewModelContainer: ModelContainer = {
            let schema = Schema([
                PrayerModel.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer for preview: \(error)")
            }
        }()

        // Create a preview context
        let context = previewModelContainer.mainContext

        // Create a preview PrayerTimesView
        return PrayerTimesView(/*context: context*/)
            .environment(sharedState)
    }
}

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
                                    onTime: { date in save { $0.time = date; $0.revertTime = false } },
                                    onRevertTime: { save { $0.time = nil; $0.revertTime = true } },
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
        if let date = edit.time, abs(date.timeIntervalSince(prayerObject.timeAtComplete ?? .distantPast)) >= 30 {
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
                          let prayedAt = prayerObject.timeAtComplete {
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
                    if let prayedAt = prayerObject.timeAtComplete {
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

// MARK: - Pager live state + salah page geometry

/// Per-frame values from the pager's gesture and scroll. @Observable so only the views that
/// read a given property re-render when it changes; PrayerTimesView's body reads none of them.
@Observable final class PagerLiveState {
    /// Just prayed (post-salah prompt style "nudge"): the prayer's name while the bottom nudge is
    /// up; nil hides it. Set by MainCircleView, cleared by the nudge or when the next prayer begins.
    var postSalahNudge: String?
    /// Pager scroll position in pages: 0 = Zikr, 1 = Salah, 2 = Settings.
    var scrollProgress: CGFloat = 1
    /// The Salah page's vertical drag nudge in points (resisted, ±20): the chevron follows it
    /// and the open sheet fades a little. Zero whenever no finger is down.
    var pull: CGFloat = 0
    /// The pager's scroll phase; programmatic page changes only scroll it when it's idle.
    var pagerPhase: ScrollPhase = .idle
    /// The pager is `.scrollDisabled` while this is set. Set by the pager's own drag gesture
    /// once a drag is decided vertical (so sideways drift can't turn into a page swipe) and by
    /// the post-salah pill while a finger is on it. Cleared on release.
    var pagerLocked = false
    /// The Salah sheet that follows the finger (SalahSheetDrag): its scroll from the closed rest in points (negative
    /// while pulled down, past `sheetTravel` while pushed up), the distance between the rests, and its scroll phase
    /// (the pager is locked while it moves).
    var sheetOffset: CGFloat = 0
    var sheetTravel: CGFloat = 1
    /// How far the list runs between the rests (the finger's travel × the speed).
    var sheetRun: CGFloat = 1
    var sheetPhase: ScrollPhase = .idle
    /// How far a pull-down on the closed page is toward refreshing, 1 = let go now (both drags). The chevron turns into
    /// "Keep pulling to refresh" (owner, round 3).
    var refreshReach: CGFloat = 0
    /// Where the last let-go goes (SheetRelease): true = open.
    @ObservationIgnored var sheetPick = false
    /// 0 closed … 1 open.
    var sheetProgress: CGFloat { min(max(sheetOffset / max(sheetTravel, 1), 0), 1) }
    /// The following sheet's finger and landing (SalahSheetDrag.swift, round 5).
    @ObservationIgnored lazy var sheetSpring = SheetSpring(live: self)
}


/// Behind the pager: one panel per page (Zikr, Salah plain; Settings grouped-gray in light mode)
/// offset by the live scroll position, so each page's colour — status-bar strip included —
/// moves with its page. Its own view so only it re-renders per scroll frame.
/// A pull past either end page meets heavy resistance (owner, 2026-10-19: "decrease rubber bandness. i want like a lot of
/// resistance"; a 1.8× stretch just before was "woah woah"): while the pager is past an end, the pages are drawn `extra`
/// of the overscroll back, so they give only part of the scroll view's own rubber-band; the spring back is the system's.
/// The scroll view can't be told its own stretch. PagerBackdrop's panels past each end cover the edge. A visual effect:
/// no body reads it.
struct PagerStretch: ViewModifier {
    /// Added to the system's give: −0.7 → the pages move 30 % as far.
    static let extra: CGFloat = -0.7

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            let f = proxy.frame(in: .scrollView(axis: .horizontal))
            let width = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? f.width / 3
            let over = f.minX > 0 ? f.minX : (f.maxX < width ? f.maxX - width : 0)
            return view.offset(x: over * Self.extra)
        }
    }
}

/// The Salah page stays anchored while you page (owner, 2026-10-19: "salah tab stays more anchored than others rather
/// than drag pushing it out as much pulling the others in"): it moves at `follows` of the finger and fades out by `goneAt`
/// of the way, so the side page comes in over nothing. A visual effect read per frame by the render pass, not a body:
/// PrayerTimesView's body still reads no per-frame value.
/// Tried first: Zikr and Settings drawn above it on their own solid page colour — on his phone the Zikr page's edge cut
/// through the Salah ring as it slid over ("i don't wanna see the page covering it. looks real bad"); dropped for the fade.
struct SalahPageAnchor: ViewModifier {
    /// How much of the drag the Salah page moves with.
    static let follows: CGFloat = 0.3
    /// Fully faded this far through the swipe (the incoming page's ring is still off its side).
    static let goneAt: CGFloat = 0.45
    @Environment(SharedStateClass.self) private var sharedState

    func body(content: Content) -> some View {
        content
            // Resting on Zikr or Settings, the faded page is still drawn 70 % over it (the offset below) and above Zikr in
            // the pager's order, and a faded view still takes touches: it swallowed the Zikr ring's tap and marked / unmarked
            // prayers from the Zikr tab (owner, 2026-10-20: "same for me … i could unmark prayers while on zikr tab"). It
            // takes touches only while it's the page you're on (`horizontalPage` changes on a settled swipe, never per frame).
            .allowsHitTesting(sharedState.horizontalPage == .main)
            .visualEffect { view, proxy in
                let x = proxy.frame(in: .scrollView(axis: .horizontal)).minX
                let moved = min(abs(x) / max(proxy.size.width, 1), 1)
                return view
                    .offset(x: -x * (1 - Self.follows))
                    .opacity(Double(max(0, 1 - moved / Self.goneAt)))
            }
    }
}

struct PagerBackdrop: View {
    let live: PagerLiveState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.circleTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let settings = Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground)
            HStack(spacing: 0) {
                // Past the ends: the edge page's own colour. A rubber-band pull past Zikr (or Settings) slid the panels off
                // and showed the window's stark white (owner, 2026-10-19: "need to fix background of app when swiping zikr
                // (edge most page) all the way. see stark white").
                theme.backdrop.frame(width: width)
                // Zikr and Salah: the theme's page, status-bar strip included.
                theme.backdrop.frame(width: width)
                theme.backdrop.frame(width: width)
                settings.frame(width: width)   // Settings' page
                settings.frame(width: width)   // past Settings
            }
            .frame(width: width * 5, alignment: .leading)
            .offset(x: -(live.scrollProgress + 1) * width)
        }
        .ignoresSafeArea()
    }
}

/// The pager's longer holds — the tour's (audit E17: only its swipe step pages) and the Zikr lock's narration — as
/// `.scrollDisabled`, in its own modifier (read in PrayerTimesView's body it re-rendered the whole tree). Rare, and they
/// reach the scroll views inside the pages too, which the tour relies on. The per-drag holds are `PagerPanLock`.
struct PagerLock: ViewModifier {
    var live: PagerLiveState
    func body(content: Content) -> some View {
        content.scrollDisabled(TourRuntime.shared.locksPager || ZikrLock.shared.focus)
    }
}

/// The per-drag holds (`live.pagerLocked`: a vertical drag on Salah, a finger on the
/// post-salah pill; and the live sheet's drag) switch the pager's own pan off and on in UIKit. As `.scrollDisabled` each
/// switch went down through every view in all three pages (the Settings form, the wheel, the list): 8–12 ms twice per
/// vertical swipe, a dropped frame each (perf trace 2026-10-10).
struct PagerPanLock: UIViewRepresentable {
    var live: PagerLiveState
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ view: Finder, context: Context) {
        // The lost page is the Salah page alone (circle step 3b): nothing else to swipe to. Here, not `.scrollDisabled` on
        // the pager: that reached every scroll view in the pages, and Journey's grid and calendar wouldn't scroll with no
        // location (sim, 2026-10-18).
        view.locked = live.pagerLocked || live.sheetPhase == .interacting || live.sheetPhase == .decelerating
            || CircleStage.shared.lost != nil
    }

    /// Sits in the pager's content: the nearest UIScrollView above it is the pager.
    final class Finder: UIView {
        private weak var pager: UIScrollView?
        var locked = false { didSet { if locked != oldValue { apply() } } }
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            pager = v as? UIScrollView
            apply()
        }
        private func apply() { pager?.panGestureRecognizer.isEnabled = !locked }
    }
}

/// The pager's Settings page. Equatable and always equal: it has no inputs that change, so when
/// the pager re-renders (every page turn publishes `sharedState`) SwiftUI skips it instead of
/// rebuilding the whole Settings Form. Settings still updates from its own state, @AppStorage
/// and the view model.
struct SettingsPage: View, Equatable {
    var onBack: () -> Void
    static func == (lhs: SettingsPage, rhs: SettingsPage) -> Bool { true }
    var body: some View { SettingsView(onBack: onBack, refetchOnLeave: false) }
}

/// A marked row tapped in the Prayers widget's times list: which prayer, on which day
/// (`WidgetListMarks.unmarkKey`, "Asr|<start, seconds since 1970>").
struct WidgetUnmarkRequest: Identifiable {
    let name: String
    let start: Date
    /// What the alert calls it: "Jumu'ah" for a Friday Dhuhr prayed at a masjid.
    var displayName: String
    var id: String { "\(name)|\(start.timeIntervalSince1970)" }

    init?(_ raw: String) {
        let parts = raw.split(separator: "|")
        guard parts.count == 2, let seconds = Double(parts[1]) else { return nil }
        name = String(parts[0])
        start = Date(timeIntervalSince1970: seconds)
        displayName = name
    }
}

/// An alert over everything in the app, whatever is presented (sheets, popovers, covers — some are
/// presented from nested controllers, out of reach from the root): its own window just above the
/// app's, in the app's own light / dark look. One at a time; `finish()` removes the window.
@MainActor enum OverlayAlert {
    private static var window: UIWindow?

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    static var canShow: Bool { window == nil && scene != nil }

    static func show(_ alert: UIAlertController) {
        guard window == nil, let scene else { return }
        let appWindow = scene.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        // The app's own appearance (shukr's Light / Dark / Auto, not the system's).
        w.overrideUserInterfaceStyle = appWindow?.rootViewController?.traitCollection.userInterfaceStyle ?? .unspecified
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
        root.present(alert, animated: true)
    }

    /// A SwiftUI prompt in the same window (it draws its own dim and card, and calls `finish()` when it's done).
    static func show(prompt: some View) {
        guard window == nil, let scene else { return }
        let appWindow = scene.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.overrideUserInterfaceStyle = appWindow?.rootViewController?.traitCollection.userInterfaceStyle ?? .unspecified
        let root = UIHostingController(rootView: AnyView(prompt))
        root.view.backgroundColor = .clear
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
    }

    /// After an action: hand the keyboard / focus back to the app's window.
    static func finish() {
        let appWindow = scene?.windows.first { $0 !== window && $0.windowLevel == .normal }
        window?.isHidden = true
        window = nil
        appWindow?.makeKey()
    }
}


/// Something presented over the page (a sheet, a full-screen cover, a popover) registers on the stage while it's on
/// screen: from its appearance until its dismissal has finished (onDisappear comes after it has slid away), with how to
/// close it. So a widget / alarm / What's new open closes it and waits until it's really gone (`clearCovers`), and a
/// moment waits for a clear circle (audit D, finding 10 — the waits were guesses: 0.55 s, 0.9 s, 0.25 s).
struct StageCover: ViewModifier {
    let key: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onAppear {
                let dismiss = dismiss
                CircleCover.set(key, true, close: { dismiss() })
            }
            .onDisappear { CircleCover.set(key, false) }
    }
}

extension View {
    /// On the root of what's presented (see StageCover).
    func stageCover(_ key: String) -> some View { modifier(StageCover(key: key)) }
}

extension SharedStateClass {
    /// Goes to `page` and returns once the pager rests there (true) — or false: a swipe took it elsewhere, it didn't
    /// arrive in time, or the task was cancelled. What waits for a page waits for this, not for a guessed time (audit D).
    @MainActor @discardableResult
    func navigate(to page: HorizontalPage, animated: Bool = true) async -> Bool {
        go(to: page, animated: animated)
        return await CircleStage.shared.until(deadline: 1.5) { CircleStage.shared.restingPage == page }
    }

    /// The page change now, in this turn (a caller that can't wait: the curtain's snapshot is next). `animated: false`
    /// scrolls the pager at once too.
    @MainActor func go(to page: HorizontalPage, animated: Bool = true) {
        guard horizontalPage != page else { return }
        quietPageChange = !animated
        guard !animated else { horizontalPage = page; return }
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { horizontalPage = page }
    }

    /// The pager asks how to scroll to a changed page (once per change).
    func takeQuietPageChange() -> Bool {
        defer { quietPageChange = false }
        return quietPageChange
    }
}

/// UIKit's appearance callbacks for the page it sits in: did-appear once a pop back to it has finished, did-disappear once
/// something pushed or presented full-screen over it has arrived. (SwiftUI's onAppear comes as a pop starts.)
struct AppearanceProbe: UIViewControllerRepresentable {
    var didAppear: () -> Void
    var didDisappear: () -> Void

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.didAppear = didAppear
        probe.didDisappear = didDisappear
    }

    final class Probe: UIViewController {
        var didAppear: () -> Void = {}
        var didDisappear: () -> Void = {}
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isHidden = true   // shown, even empty and clear, it turned the home indicator white on light pages
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didAppear()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            didDisappear()
        }
    }
}

#if DEBUG
/// `-demoLand salah|zikr|journey|settings`: which page a test launch lands on (no value = Salah). Any `-demo…` arg
/// already skips the welcome / opening, setup and the prompts; this one also passes the zikr lock.
enum DemoLand {
    static let page: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoLand") else { return nil }
        let next = args.indices.contains(i + 1) ? args[i + 1].lowercased() : ""
        return ["zikr", "journey", "settings"].contains(next) ? next : "salah"
    }()
}
#endif


/// The prayer editor's saves, held while the day page is up (PrayerButton.pendingEdit): the last time or ↺, the last spot
/// or ↺.
struct HeldEdit {
    var time: Date?
    var revertTime = false
    var spot: CLLocationCoordinate2D?
    var revertSpot = false
}
