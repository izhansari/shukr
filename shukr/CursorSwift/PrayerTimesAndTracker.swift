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
    @State var showZikrHistory = false
    /// A session sleep mode ended: shown round the Salah circle the next time the page is up.
    @State var morningSession: SessionDataModel?
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

    @State var morningWait: Task<Void, Never>?
    @State private var tourWait: Task<Void, Never>?
    /// Nothing else owns the Salah page: the tour may start, or show (audit A4).
    private var tourCanStart: Bool {
        let stage = CircleStage.shared
        return !stage.pageHidden && stage.sceneActive && stage.lost == nil && morningSession == nil
            && !somethingCovers && !showTasbeehPage && !FirstRunSetup.isShowing && !WelcomeTarget.playing
    }

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
        showQiblaMap || showMapPage || showDailyAyahPage || showMantrasPage
            || showZikrHistory
            || showNamesPage || showMantraSheetFromHomePage || JourneyPresenter.shared.open
            || healthCard != nil     // the reminders card: a widget's deep link closes it first
    }

    private func dismissCovers() {
        showQiblaMap = false; showMapPage = false; showDailyAyahPage = false; showMantrasPage = false
        showZikrHistory = false
        showNamesPage = false
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
                showMantrasPage: $showMantrasPage, showZikrHistory: $showZikrHistory,
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
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in
            openFromWidgetFlags()
            LateMarkAsk.shared.checkOutsideMarks(in: context)   // a late "I already prayed": in its time, or made up?
        }
        .lateMarkAsk()   // the late-mark question (LateMarkAsk, prayer-metrics phase 6)
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
        .onAppear {
            askIfOverdue()
            LateMarkAsk.shared.checkOutsideMarks(in: context)   // a cold open: marks made from outside while closed
        }
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
        .overlay { morningCard }
        // A prayer marked on the Apple Watch (WatchZikrSync): same as after a widget mark.
        .onReceive(NotificationCenter.default.publisher(for: .watchMarkedPrayer)) { note in
            viewModel.reconcileAfterWidgetWrites()
            if let day = note.object as? Date { viewModel.calculateDayScore(for: day) }   // a late mark's own day
            LateMarkAsk.shared.checkOutsideMarks(in: context)
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
                LateMarkAsk.shared.checkOutsideMarks(in: context)   // …and any marked after their time: asked once
                
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
        .navigationDestination(isPresented: $showZikrHistory) { ZikrAreaPage(start: .history) }
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
