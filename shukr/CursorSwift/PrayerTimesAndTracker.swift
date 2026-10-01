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
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) var context
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("widgetCompass", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetCompass: Bool = false
    @AppStorage("widgetTasbeeh", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTasbeeh: Bool = false
    @AppStorage("widgetTextToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTextToggle: Bool = false
        
    @State private var showDailyAyahView: Bool = false
    @State private var showMantraSheetFromHomePage: Bool = false
    @State private var settingsViewNavBool: Bool = false
    @State private var showTasbeehPage: Bool = false
    @State private var showQiblaMap: Bool = false

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
    @State private var isDraggingVertically: Bool? = nil   // axis of the current pager drag

    // MARK: - Horizontal pager
    // Three pages side by side in a native paging ScrollView: Zikr | Main | Settings.
    // UIKit drives the finger tracking, so nothing in SwiftUI re-renders per frame.
    // `scrollPage` is written only programmatically (from sharedState.horizontalPage); user
    // swipes flow the other way via onScrollPhaseChange once the scroll settles.
    typealias NavPage = SharedStateClass.HorizontalPage
    @State private var scrollPage: NavPage? = .main
    private let pageSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    // Menu destinations (native Menu on the hamburger; pushes on the root NavigationStack)
    @State private var showMapPage = false
    @State private var showDailyAyahPage = false
    @State private var showMantrasPage = false
    @State private var showSalahHistoryV1 = false
    @State private var showSalahHistoryV2 = false
    @State private var showZikrHistory = false
    /// A session sleep mode ended: shown round the Salah circle the next time the page is up.
    @State private var morningSession: SessionDataModel?
    @State private var showInsightsPage = false
    @State private var showOldInsights = false
    @State private var showNamesPage = false
    /// The Prayers widget's times list: a marked row opens the app to "Unmark Asr?".
    @State private var widgetUnmark: WidgetUnmarkRequest?
    /// Bumped per request, so an older retry loop stops.
    @State private var widgetUnmarkToken = 0
    #if DEBUG
    @State private var demoMantra: MantraModel?
    @State private var demoNewZikr = false
    @State private var demoWhatsNew = false
    @State private var demoScheduled = false
    #endif

    /// Widget / control / Action-button opens (one-shot flags in the app group). Held while the
    /// first-run setup is up — the flags stay set and this runs again once it's done
    /// (`FirstRunSetup.finished`), so its hand-off always lands on this page's circle.
    /// Sleep mode ended a session: once nothing is over the Salah page, go to it (circle showing) and
    /// open the morning card on its circle — under the welcome while it plays, which lands on the card.
    /// A morning card is waiting: be on the Salah page (circle showing) while the app is away, so the
    /// next open's welcome and the card draw on the real circle from the first frame. Left on the Zikr
    /// page (where the session started), the circle's last frame was off screen and the welcome
    /// started half off the screen (owner, sleep morning). Behind the black curtain, so unseen.
    private func goToSalahForMorningCard() {
        guard SleepMorning.pendingID != nil else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            sharedState.horizontalPage = .main
            sharedState.navPosition = .main
        }
    }

    private func showMorningCardWhenClear(tries: Int = 0) {
        guard morningSession == nil, SleepMorning.pendingID != nil, SleepMorning.isArmed, tries < 40 else { return }
        // Not waiting for the welcome: the card goes up under it, so the welcome lands on its ring.
        if showTasbeehPage || somethingCovers || FirstRunSetup.showingAtLaunch || scenePhase != .active {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showMorningCardWhenClear(tries: tries + 1) }
            return
        }
        guard let session = SleepMorning.pending(in: context) else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            sharedState.horizontalPage = .main
            sharedState.navPosition = .main
        }
        // Let the circle settle where it lives (its frame is what the card draws round).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { morningSession = session }
    }

    private func openFromWidgetFlags() {
        guard !FirstRunSetup.isShowing else { return }
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
            let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
            if FirstRunSetup.deepLinkFlags.contains(where: { store.object(forKey: $0) != nil && store.bool(forKey: $0) })
                || store.string(forKey: "widgetZikrTask") != nil {
                lastDeepLinkAt = Date()   // no reminders card over where a widget just sent you
            }
            // Clear only when set: every write to the group suite invalidates every
            // @AppStorage bound to it and re-renders Settings.
            if openCompassFromWidget { store.setValue(false, forKey: "widgetCompass") }
            if openTasbeehFromWidget { store.setValue(false, forKey: "widgetTasbeeh") }
            let openAyahFromWidget  = store.bool(forKey: "widgetDailyAyah")
            let openNamesFromWidget = store.bool(forKey: "widgetNames")
            if openAyahFromWidget { store.setValue(false, forKey: "widgetDailyAyah") }
            if openNamesFromWidget { store.setValue(false, forKey: "widgetNames") }
            // Whatever is covering the page (the map, a pushed page) goes first, or the
            // widget's page opened behind it (owner, 2026-09-26).
            let zikrTaskID = store.string(forKey: "widgetZikrTask")
            if zikrTaskID != nil { store.removeObject(forKey: "widgetZikrTask") }
            // The Fajr alarm's "I'm up — open Fajr" (AlarmKit): the Salah page, nothing over it.
            if store.bool(forKey: "alarmOpenSalah") {
                store.set(false, forKey: "alarmOpenSalah")
                lastDeepLinkAt = Date()
                clearCovers { sharedState.horizontalPage = .main }
            }
            // A marked row in the widget's times list: ask here, never unmark there.
            if store.string(forKey: WidgetListMarks.unmarkKey) != nil {
                lastDeepLinkAt = Date()
                widgetUnmarkToken += 1
                showWidgetUnmarkWhenClear(token: widgetUnmarkToken)
            }
            // A prayer marked from the widget's list, possibly on another prayer day than the app's
            // (a list drawn before Fajr, tapped after): that day's score and the streaks.
            if store.object(forKey: WidgetListMarks.markedDayKey) != nil {
                let day = Date(timeIntervalSince1970: store.double(forKey: WidgetListMarks.markedDayKey))
                store.removeObject(forKey: WidgetListMarks.markedDayKey)
                viewModel.reconcileAfterWidgetWrites()
                viewModel.calculateDayScore(for: day)
                viewModel.recomputeStreaks()
            }
            if openAyahFromWidget {
                clearCovers {
                    sharedState.horizontalPage = .main
                    showDailyAyahPage = true
                }
            } else if openNamesFromWidget {
                clearCovers {
                    sharedState.horizontalPage = .main
                    showNamesPage = true
                }
            }

            if openCompassFromWidget, !showQiblaMap {
                clearCovers {
                    sharedState.navPosition = .main
                    showQiblaMap = true
                }
            }
            
            else if openTasbeehFromWidget{
                clearCovers {
                    sharedState.horizontalPage = .zikr
                    // A task row in the Zikr widget: bring that task's circle to the middle.
                    if let zikrTaskID { ZikrFocus.request(zikrTaskID) }
                }
            }
        }
    }

    /// "Unmark Asr?" → Unmark, from the widget's times list: today's row goes through the app's own
    /// unmark (as the list's own alert does: day score, streak, widget); a row of another day has
    /// every completed row of it reset, then the day and streaks are redone.
    private func unmarkFromWidget(_ request: WidgetUnmarkRequest) {
        viewModel.reconcileAfterWidgetWrites()   // a widget mark that just landed
        // Every completed row of that prayer on that day (a day can hold duplicates): the one on
        // today's list through the app's own unmark (haptic, day score, streak, widget), the rest reset.
        let shown = viewModel.todaysPrayers.first {
            $0.isCompleted && $0.name == request.name && Calendar.current.isDate($0.startTime, inSameDayAs: request.start)
        }
        let others = completedRows(request).filter { $0.persistentModelID != shown?.persistentModelID }
        others.forEach { $0.resetPrayer() }
        if let shown {
            viewModel.togglePrayerCompletion(for: shown)   // rescores the day and the streak, pushes the widget
        } else if !others.isEmpty {
            viewModel.calculateDayScore(for: request.start)
            viewModel.recomputeStreaks()
            viewModel.pushCompletionsToWidget()
        }
    }

    /// The completed rows of the request's prayer on its calendar day.
    private func completedRows(_ request: WidgetUnmarkRequest) -> [PrayerModel] {
        let name = request.name
        let dayStart = Calendar.current.startOfDay(for: request.start)
        let dayEnd = dayStart.addingTimeInterval(86_399)
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate {
            $0.name == name && $0.startTime >= dayStart && $0.startTime <= dayEnd
        }))) ?? []
        return rows.filter(\.isCompleted)
    }

    /// "Unmark Asr?" appears over whatever is on screen — the Zikr page, Settings, a pushed page, the
    /// map, a sheet or the ☰ popover — with no navigating (owner, CBBBBD1D: it only came up on the Salah
    /// page). It's a UIKit alert in its own window above the app (`OverlayAlert`), so no sheet, popover
    /// or cover can hide it (presented from the root it sat under a sheet SwiftUI had presented from a
    /// nested controller). It waits during the first-run setup and the opening, while the app
    /// isn't active and during a tasbeeh session (taps there count; it comes up once the session closes).
    /// Until then the request stays in the app group and this retries every second for a while; the next
    /// activation picks it up again.
    private func showWidgetUnmarkWhenClear(token: Int, attempt: Int = 0, sessionPaused: Bool = false) {
        guard token == widgetUnmarkToken, widgetUnmark == nil,
              let store = UserDefaults(suiteName: SharedStore.appGroup),
              let raw = store.string(forKey: WidgetListMarks.unmarkKey) else { return }
        guard let request = WidgetUnmarkRequest(raw) else { store.removeObject(forKey: WidgetListMarks.unmarkKey); return }
        func later() {
            guard attempt < 90 else { return }   // the request stays: the next activation tries again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showWidgetUnmarkWhenClear(token: token, attempt: attempt + 1) }
        }
        let blocked = FirstRunSetup.isShowing || WelcomeTarget.playing || UIApplication.shared.applicationState != .active
        guard !blocked, OverlayAlert.canShow else { later(); return }
        // A tasbeeh session up: it goes into its pause state first, then the prompt shows over it (owner,
        // CA197AE2 — it used to wait until the session closed). `CircleCover` "tasbeeh" is set by the session
        // itself: this closure's own view copy can read a stale `showTasbeehPage`.
        if !sessionPaused, showTasbeehPage || CircleCover.active.contains("tasbeeh") {
            NotificationCenter.default.post(name: TasbeehSession.pauseRequest, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showWidgetUnmarkWhenClear(token: token, attempt: attempt + 1, sessionPaused: true)
            }
            return
        }
        // Still wanted (not already unmarked meanwhile): show it, and only then take the request.
        store.removeObject(forKey: WidgetListMarks.unmarkKey)
        let rows = completedRows(request)
        guard !rows.isEmpty else { return }
        var shown = request
        shown.displayName = rows.contains(where: \.isJumuah) ? "Jumu'ah" : request.name
        widgetUnmark = shown
        let alert = UIAlertController(title: "Unmark \(shown.displayName)?",
                                      message: "Are you sure you want to mark this prayer as incomplete?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            widgetUnmark = nil
            OverlayAlert.finish()
        })
        alert.addAction(UIAlertAction(title: "Unmark", style: .destructive) { _ in
            widgetUnmark = nil
            OverlayAlert.finish()
            unmarkFromWidget(shown)
        })
        OverlayAlert.show(alert)
    }

    /// Everything that can cover the pager: the map, a pushed page, the mantra sheet.
    /// The reminders card (NotificationHealth): notifications off, or held for the Scheduled Summary.
    @State private var healthCard: NotificationHealth.Issue?
    /// Set by the card's onAppear; bumped per attempt so an older check can't clear a newer card.
    @State private var healthCardAppeared = false
    @State private var healthCardToken = 0
    @State private var lastDeepLinkAt = Date.distantPast

    /// A moment after the app comes forward: the card, if one's due (at most every few days per
    /// kind) and nothing else is going on — not over a tasbeeh session, a cover, the setup, or a
    /// widget's destination.
    private func maybeShowHealthCard(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in
                // Not while the opening plays (a sheet over it left the page blank): try again.
                if WelcomeTarget.playing {
                    if attempt < 5 { maybeShowHealthCard(attempt: attempt + 1) }
                    return
                }
                let health = NotificationHealth.shared
                await health.refresh()
                // Only on the Salah page with nothing else open: sheets inside the Zikr and Settings
                // pages (task sheets, the city picker, What's new…) aren't in `somethingCovers`.
                guard FirstRunSetup.isDone, !FirstRunSetup.isShowing, !showTasbeehPage, !somethingCovers,
                      sharedState.horizontalPage == .main, CircleCover.active.isEmpty, healthCard == nil, !demoSheetUp,
                      // The morning card (sleep mode) comes first; this card waits for another open.
                      morningSession == nil, !(SleepMorning.pendingID != nil && SleepMorning.isArmed),
                      Date().timeIntervalSince(lastDeepLinkAt) > 10,
                      let issue = health.cardIssue, health.cardDue(for: issue) else { return }
                healthCard = issue   // marked shown, and a CircleCover, only once it's actually up (the card's onAppear)
                healthCardAppeared = false
                healthCardToken += 1
                let token = healthCardToken
                // Something the guards can't see (a prayer row's unmark alert…) can keep the sheet
                // from presenting. Don't leave it pending — it would block every later card and
                // could pop up at a random moment: drop it if it isn't up within a second.
                try? await Task.sleep(for: .seconds(1.2))
                if token == healthCardToken, !healthCardAppeared, healthCard == issue { healthCard = nil }
            }
        }
    }

    /// DEBUG screenshot sheets the card mustn't cover.
    private var demoSheetUp: Bool {
        #if DEBUG
        return demoScheduled
        #else
        return false
        #endif
    }

    private var somethingCovers: Bool {
        showQiblaMap || showMapPage || showDailyAyahPage || showMantrasPage || showSalahHistoryV1
            || showSalahHistoryV2 || showZikrHistory || showInsightsPage || showOldInsights
            || showNamesPage || showMantraSheetFromHomePage || settingsViewNavBool
            || healthCard != nil     // the reminders card: a widget's deep link closes it first
    }

    private func dismissCovers() {
        showQiblaMap = false; showMapPage = false; showDailyAyahPage = false; showMantrasPage = false
        showSalahHistoryV1 = false; showSalahHistoryV2 = false; showZikrHistory = false
        showInsightsPage = false; showOldInsights = false; showNamesPage = false
        showMantraSheetFromHomePage = false; settingsViewNavBool = false
        healthCard = nil
    }

    /// A widget / control is taking the user somewhere: close what's covering the page first, then
    /// go (after the dismissal, so the new page isn't pushed under the leaving one). A running
    /// tasbeeh session is never closed from a widget tap.
    private func clearCovers(then go: @escaping () -> Void) {
        guard !showTasbeehPage else { return }
        if somethingCovers {
            dismissCovers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { go() }
        } else {
            go()
        }
    }
//    var showTop: Bool { sharedState.navPosition == .top }
    var showMain: Bool { sharedState.navPosition == .main }
    var showBottom: Bool { sharedState.navPosition == .bottom }
        
    private var switchToSalahDoubleTapSGesture: some Gesture{
        TapGesture(count: 2)
            .onEnded {
                // left this incase we want to use it for an action.
                print("Double tap: no action assigned yet...")
            }
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
    private var abstractedDragGesture: _EndedGesture<_ChangedGesture<DragGesture>> {
        let resistanceFactor = 0.5
        let maxOffset: CGFloat = 20
        let threshold: CGFloat = 30
        let decideAt: CGFloat = 6

        return DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                // A touch that starts on the Zikr page's task strip belongs to the strip: hold
                // the pager from the first move so a drag past the strip's last card can't chain
                // into a page turn. (The strip's own touch-down lock isn't always early enough
                // on device; this gesture sits on the pager itself and always is.)
                if !live.pagerLocked, live.stripFrame.contains(value.startLocation) { live.pagerLocked = true }
                if isDraggingVertically == nil { // decide the axis once per drag
                    let t = value.translation
                    guard abs(t.width) > decideAt || abs(t.height) > decideAt else { return }
                    dismissKeyboard()
                    isDraggingVertically = abs(t.height) > abs(t.width)
                    if isDraggingVertically == true {
                        live.pagerLocked = true
                    } else {
                        // No overscroll: a horizontal drag that could only rubber-band (finger
                        // moving right on the first page, left on the last) is refused for the
                        // whole drag. Bounce stays on, so real page turns keep their physics.
                        let page = sharedState.horizontalPage
                        if (page == .zikr && t.width > 0) || (page == .settings && t.width < 0) {
                            live.pagerLocked = true
                        }
                    }
                }
                if isDraggingVertically == true {
                    guard sharedState.horizontalPage == .main else { return }
                    let nudged = min(max(value.translation.height * resistanceFactor, -maxOffset), maxOffset)
                    live.pull = showBottom ? max(0, nudged) : nudged   // no upward nudge once open
                }
            }
            .onEnded { value in
                let vertical = isDraggingVertically == true
                isDraggingVertically = nil
                live.pagerLocked = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    live.pull = 0
                    guard vertical, sharedState.horizontalPage == .main else { return }
                    let draggedDown = value.translation.height > threshold
                    let draggedUp = value.translation.height < -threshold
                    switch sharedState.navPosition {
                    case .main:
                        sharedState.bottomTabPosition = .salah
                        if draggedUp { sharedState.navPosition = .bottom; triggerSomeVibration(type: .light) }
                        if draggedDown { viewModel.refreshCityAndPrayerTimes(); triggerSomeVibration(type: .light) }
                    case .bottom:
                        if draggedDown { sharedState.navPosition = .main; triggerSomeVibration(type: .light) }
                    default:
                        break
                    }
                }
            }
    }

    var body: some View {
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
                        .id(NavPage.main)
                    
                    SettingsPage { sharedState.horizontalPage = .main }
                        .equatable()
                        .environmentObject(viewModel)
                        .containerRelativeFrame(.horizontal)
                        .clipped()
                        .id(NavPage.settings)
                }
                .scrollTargetLayout()
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
            .simultaneousGesture(switchToSalahDoubleTapSGesture)
            .simultaneousGesture(abstractedDragGesture)
            .onScrollPhaseChange { _, phase, context in
                live.pagerPhase = phase
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
            }
            .onChange(of: sharedState.horizontalPage) { _, wanted in
                // Programmatic nav (bottom bar, menu, widget deep link): scroll the pager to match.
                // Not while the finger or the coast owns the pager: that commit came from the
                // scroll itself and it's already heading there.
                guard live.pagerPhase == .idle || live.pagerPhase == .animating else { return }
                if scrollPage != wanted { withAnimation(pageSpring) { scrollPage = wanted } }
            }
            
            // MARK: - (Parked) Duas page — used to live at .left. Kept in case we bring it back.
            // VStack{
            //     DuaPageView()
            // }
            // .background(Color(.systemBackground))
            // .padding()
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
            // Well after the sheet has gone: pushing the library while it was still closing
            // left a second search field in its bottom bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
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
                    case "insights": showInsightsPage = true
                    default: break
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TaskModel.didDelete)) { note in
            guard let gone = note.object as? Set<PersistentIdentifier>,
                  let selected = sharedState.selectedTask, gone.contains(selected.persistentModelID) else { return }
            sharedState.selectedTask = nil
        }
        // A zikr's page asked to start one of its tasks: close what covers the pager, then the
        // Zikr page's wheel starts it.
        .onReceive(NotificationCenter.default.publisher(for: ZikrFocus.startNotification)) { _ in
            guard !showTasbeehPage else { return }
            clearCovers {
                sharedState.horizontalPage = .zikr
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: ZikrFocus.wheelStartNotification, object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ZikrReminders.openTask)) { note in
            guard let taskID = note.object as? String, scenePhase == .active else { return }
            lastDeepLinkAt = Date()   // no reminders card over the zikr it opened
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
                    CircleCover.set("healthCard", true)
                }
                .onDisappear { CircleCover.set("healthCard", false) }
        }
        // The first-run setup is done: a widget open that arrived during it, now.
        .onReceive(NotificationCenter.default.publisher(for: FirstRunSetup.finished)) { _ in openFromWidgetFlags() }
        // A marked row tapped in the Prayers widget's times list: the app asks (showWidgetUnmarkWhenClear).
        .onChange(of: widgetUnmark != nil) { _, up in CircleCover.set("widgetUnmark", up) }
        // A request that waited out a tasbeeh session: now.
        .onChange(of: showTasbeehPage) { _, up in
            if !up { widgetUnmarkToken += 1; showWidgetUnmarkWhenClear(token: widgetUnmarkToken) }
        }
        .onAppear { showMorningCardWhenClear() }
        .onReceive(NotificationCenter.default.publisher(for: WelcomeGate.raiseCurtain)) { _ in goToSalahForMorningCard() }
        .overlay {
            if let morningSession {
                MorningCardView(session: morningSession, onDone: {
                    SleepMorning.clear()
                    self.morningSession = nil
                }, onHistory: {
                    SleepMorning.clear()
                    self.morningSession = nil
                    showZikrHistory = true
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
        .task {
            // `-demoWidgetUnmarkAfter <seconds>`: what a marked row's tap in the widget's times list
            // does — the request for today's first marked prayer, then the widget hand-off (combine
            // with a page's demo arg, or move about the app meanwhile).
            let after = UserDefaults.standard.double(forKey: "demoWidgetUnmarkAfter")
            guard after > 0 else { return }
            try? await Task.sleep(for: .seconds(after))
            // With `-demoPauseScreen`: only once the session is really up (it opens late).
            if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
                for _ in 0..<40 where !CircleCover.active.contains("tasbeeh") { try? await Task.sleep(for: .milliseconds(250)) }
                try? await Task.sleep(for: .seconds(1))
            }
            if let p = viewModel.todaysPrayers.first(where: \.isCompleted) {
                UserDefaults(suiteName: SharedStore.appGroup)?
                    .set("\(p.name)|\(p.startTime.timeIntervalSince1970)", forKey: WidgetListMarks.unmarkKey)
                openFromWidgetFlags()
            }
        }
        .task {
            // Masjid detection check: a late Friday Dhuhr at your first favourite masjid (+ one
            // 400 m away) → the first should come back as Jumu'ah, scored Early; the second not.
            if ProcessInfo.processInfo.arguments.contains("-demoMasjidCheck"), let fav = MosqueFavorites.all.first {
                let cal = Calendar.current
                var friday = cal.startOfDay(for: Date())
                while cal.component(.weekday, from: friday) != 6 { friday = cal.date(byAdding: .day, value: -1, to: friday)! }
                let start = friday.addingTimeInterval(13 * 3600), end = start.addingTimeInterval(3 * 3600)
                let atMasjid = PrayerModel(name: "Dhuhr", startTime: start, endTime: end,
                                           latitude: fav.latitude + 0.0002, longitude: fav.longitude)
                let away = PrayerModel(name: "Asr", startTime: end, endTime: end.addingTimeInterval(7200),
                                       latitude: fav.latitude + 0.004, longitude: fav.longitude)
                for p in [atMasjid, away] {
                    p.isCompleted = true
                    p.setPrayerScore(atDate: p.startTime.addingTimeInterval(2.5 * 3600))
                    context.insert(p)
                }
                NSLog("MASJIDCHECK before: \(atMasjid.displayName) \(atMasjid.numberScore ?? -1)")
                let days = await MasjidDetector.check([atMasjid, away], in: context)
                NSLog("MASJIDCHECK after: \(atMasjid.displayName) score=\(atMasjid.numberScore ?? -1) masjid=\(atMasjid.mosqueName ?? "nil") | away masjid=\(away.mosqueName ?? "nil") rescoredDays=\(days.count)")
                context.delete(atMasjid); context.delete(away); try? context.save()
            }
            // What a Zikr-widget row tap does, without the widget: Zikr page, last task centred.
            if ProcessInfo.processInfo.arguments.contains("-demoZikrFocus") {
                try? await Task.sleep(for: .seconds(1.5))
                let tasks = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
                if let last = tasks.last {
                    sharedState.horizontalPage = .zikr
                    ZikrFocus.request(last.id.uuidString)
                }
            }
        }
        .task {
            // Simulator check of the completion moment: launch with -demoPrayerCompletion. Uses
            // the dev "test prayer times" (minutes around now), opens the salah sheet, then
            // marks the current prayer and a missed one.
            if ProcessInfo.processInfo.arguments.contains("-demoPinRender") { await PickPinRender.run() }
            if ProcessInfo.processInfo.arguments.contains("-demoTasbeehRing") {
                // Writes the tasbeeh progress ring at 65 % to <app data>/tmp/tasbeeh-ring.png.
                let renderer = ImageRenderer(content: NeuCircularProgressView(progress: 0.65).padding(40).background(Color(.systemBackground)))
                renderer.scale = 3
                if let data = renderer.uiImage?.pngData() {
                    try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "tasbeeh-ring.png"))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoShareCard") {
                // Writes today's ayah share card to <app data>/tmp/share-card.png.
                let vm = DailyAyahViewModel()
                try? await Task.sleep(for: .seconds(1))
                if let ayah = vm.currentAyah {
                    let name = vm.surahs.first(where: { $0.number == ayah.surah })?.englishName ?? "Surah \(ayah.surah)"
                    let card = AyahShareCard(arabic: ayah.arabic, english: ayah.english, translator: ayah.translator,
                                             reference: "\(name) · \(ayah.surah):\(ayah.ayah)")
                    var lightGrain = card; lightGrain.style = .grain; lightGrain.darkBase = false
                    if let data = lightGrain.render()?.pngData() {
                        try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "share-card-grain-light.png"))
                    }
                    for style in AyahShareStyle.allCases {
                        var styled = card; styled.style = style
                        if let data = styled.render()?.pngData() {
                            try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "share-card-\(style.rawValue).png"))
                        }
                    }

                }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoMosques") || UserDefaults.standard.string(forKey: "demoMapLayer") != nil {
                try? await Task.sleep(for: .seconds(2.5))
                showQiblaMap = true   // the real map (the circle's arrow); mosque mode / `-demoMapLayer` from there
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoZikrMedia") {
                // Alhamdulillah with a sample photo + memo; its page opens unless `-demoPauseScreen`
                // (then the pause card shows them). `-demoZikrPane memo|photo` picks the tab.
                try? await Task.sleep(for: .seconds(1))
                let m = ZikrMediaDemo.seed(in: context)
                if !ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") { demoMantra = m; return }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoNewZikr") {
                // A new zikr's card: editing, every box empty (its placeholders).
                try? await Task.sleep(for: .seconds(1))
                demoNewZikr = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoZikrEmpty") {
                // A zikr's page by name (`-demoZikrName <name>`, default Astaghfirullah — no photo / memo).
                try? await Task.sleep(for: .seconds(1))
                let name = UserDefaults.standard.string(forKey: "demoZikrName") ?? "Astaghfirullah"
                if let m = MantraModel.find(named: name, in: context) { demoMantra = m; return }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoScheduledNotifications") {
                try? await Task.sleep(for: .seconds(1.5))
                demoScheduled = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoWhatsNew") {
                // The What's new page; `-demoWhatsNewTopic <id>` opens that card's detail.
                try? await Task.sleep(for: .seconds(1))
                demoWhatsNew = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoMantraPage") {
                try? await Task.sleep(for: .seconds(1))
                showMantrasPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoHealthThenCompass") {
                // With `-healthPretend off`: once the reminders card is up, a Qibla widget tap
                // arrives (the flag + the activation path) — the card must close and the map open.
                for _ in 0..<40 where !healthCardAppeared { try? await Task.sleep(for: .milliseconds(250)) }
                print("HEALTHTEST card up=\(healthCardAppeared)")
                try? await Task.sleep(for: .seconds(1))
                UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.set(true, forKey: "widgetCompass")
                openFromWidgetFlags()
                try? await Task.sleep(for: .seconds(2.5))
                print("HEALTHTEST after: card=\(healthCard != nil) map=\(showQiblaMap) canLand=\(WelcomeTarget.canLand)")
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoZikrHistory") {
                try? await Task.sleep(for: .seconds(1))
                showZikrHistory = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoDailyAyah") {
                // The Daily Ayah page (+ `-demoAyahUnrevealed`, `-demoAyahReveal`; screenshots).
                try? await Task.sleep(for: .seconds(1))
                showDailyAyahPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoSettings") {
                try? await Task.sleep(for: .seconds(1.5))   // once the pager is up
                sharedState.horizontalPage = .settings   // the Settings page (screenshots)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartPreview") {
                // What Settings → My Dev Stuff → Preview prayer begins does (from the Settings page).
                sharedState.horizontalPage = .settings
                try? await Task.sleep(for: .seconds(2))
                NotificationCenter.default.post(name: PrayerStartPreview.request, object: nil)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoManyTasks") {
                // Six zikr tasks, one with a very long name (the Zikr widget's rows; simulator).
                try? await Task.sleep(for: .seconds(1))
                let existing = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
                if existing < 6 {
                    let names = [("Alhamdulillah", "After Fajr, before the morning walk to the masjid"), ("Astaghfirullah", ""),
                                 ("Subhanallah", "Evening"), ("Allahu Akbar", ""), ("Alhamdulillah", "Before bed"),
                                 ("Astaghfirullah", "After Isha")]
                    for (i, (mantra, own)) in names.prefix(6 - existing).enumerated() {
                        let t = TaskModel(mantra: MantraModel.find(named: mantra, in: context),
                                          isCountMode: true, goal: [100, 33, 1000, 34, 50, 70][i], sortOrder: existing + i)
                        t.customName = own.isEmpty ? nil : own
                        context.insert(t)
                    }
                    try? context.save()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoZikrPage") {
                // The Zikr page's circle wheel, with a few tasks if there are none (simulator).
                try? await Task.sleep(for: .seconds(1))
                if ((try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0) == 0 {
                    for (i, (name, count, goal)) in [("Alhamdulillah", true, 100), ("Astaghfirullah", true, 33),
                                                     ("Subhanallah", false, 10)].enumerated() {
                        context.insert(TaskModel(mantra: MantraModel.find(named: name, in: context),
                                                 isCountMode: count, goal: goal, sortOrder: i))
                    }
                    try? context.save()
                }
                sharedState.horizontalPage = .zikr
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPostSalah") {
                try? await Task.sleep(for: .seconds(1))
                sharedState.isDoingPostNamazZikr = true
                showTasbeehPage = true
                return
            }
            if UserDefaults.standard.object(forKey: "demoTasbeehCount") != nil {
                // A freestyle session for `-demoTasbeehCount` (tasbeehView counts it).
                try? await Task.sleep(for: .seconds(1))
                sharedState.selectedMode = 0
                showTasbeehPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
                // A 33-count Alhamdulillah session, paused (tasbeehView counts and pauses it).
                // `-demoPauseZikr <name>` counts another zikr (e.g. one with a slower usual pace).
                try? await Task.sleep(for: .seconds(1))
                let zikrName = UserDefaults.standard.string(forKey: "demoPauseZikr") ?? "Alhamdulillah"
                if let mantra = MantraModel.find(named: zikrName, in: context) {
                    if mantra.fullText.isEmpty && zikrName == "Alhamdulillah" {
                        mantra.fullText = "الْحَمْدُ لِلَّهِ\nAl-ḥamdu lillāh — all praise is for Allah"
                        mantra.notes = "Read after every salah, 33 times."
                    }
                    sharedState.mantraForSession = mantra
                }
                sharedState.titleForSession = zikrName
                sharedState.selectedMode = 2
                sharedState.targetCount = "33"
                showTasbeehPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoNames") {
                try? await Task.sleep(for: .seconds(1))
                showNamesPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoInsights") {
                try? await Task.sleep(for: .seconds(1))
                showInsightsPage = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerListOpen") {
                // The prayer list up (to tap its rows); with `-demoPrayerStart`, its prayers to come too.
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sharedState.navPosition = .bottom }
                if !ProcessInfo.processInfo.arguments.contains("-demoPrayerStart") { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoDayMilestones") {
                // Streak (fake 12) + on-time streak (fake 5) in the top bar, perfect day in the list.
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sharedState.navPosition = .bottom }
                try? await Task.sleep(for: .seconds(1.5))
                NotificationCenter.default.post(name: .prayerStreakContinued, object: 12)
                NotificationCenter.default.post(name: .onTimeStreakContinued, object: 5)
                NotificationCenter.default.post(name: .perfectDay, object: true)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerStart") {
                // A prayer comes into its window 6 s after launch (simulator only): test prayer
                // times, then Asr's window closed and Maghrib moved to start in 6 s.
                try? await Task.sleep(for: .seconds(1))
                // The loaded prayer day's rows, moved in memory (works at any hour; test prayer
                // times fell outside the day after midnight).
                let now = Date()
                // `-demoPrayerStartPrayer Fajr` picks which prayer starts (default Maghrib); Fajr
                // starts from the day-summary circle.
                let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
                let target = order.firstIndex(of: UserDefaults.standard.string(forKey: "demoPrayerStartPrayer") ?? "Maghrib") ?? 3
                for p in viewModel.todaysPrayers {
                    p.isCompleted = false
                    let i = order.firstIndex(of: p.name) ?? 0
                    if i < target { p.startTime = now.addingTimeInterval(-3600); p.endTime = now.addingTimeInterval(-60); p.isCompleted = true }
                    else if i == target { p.startTime = now.addingTimeInterval(6); p.endTime = now.addingTimeInterval(1800) }
                    else { p.startTime = now.addingTimeInterval(3600 * Double(i - target)); p.endTime = p.startTime.addingTimeInterval(1800) }
                }
                viewModel.objectWillChange.send()
                // `-demoPrayerStartThenMark`: mark it 4 s after it starts → the circle moves on to the
                // next (not started) prayer and the track shrinks back to dashed after the sweep.
                if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartThenMark") {
                    // `-demoPrayerStartSheetOpen`: with the prayer list up (the list's path; marking
                    // Isha then completes the day).
                    if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartSheetOpen") {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sharedState.navPosition = .bottom }
                        try? await Task.sleep(for: .seconds(8))
                    } else {
                        try? await Task.sleep(for: .seconds(10))
                    }
                    if let now = viewModel.relevantPrayer, now.status() == .current {
                        viewModel.togglePrayerCompletion(for: now)
                    }
                    return
                }
                // `-demoPrayerStartOnZikr`: be on the Zikr page when it starts (must not play).
                if ProcessInfo.processInfo.arguments.contains("-demoPrayerStartOnZikr") {
                    sharedState.horizontalPage = .zikr
                }
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("-demoPrayerCompletion") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            viewModel.useTestPrayers = true
            viewModel.fetchPrayerTimes(cameFrom: "demoPrayerCompletion")
            viewModel.loadTodaysPrayerObjects()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sharedState.navPosition = .bottom }
            for name in ["Asr", "Dhuhr", "Fajr"] {
                try? await Task.sleep(for: .seconds(3))
                if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }), !prayer.isCompleted {
                    viewModel.togglePrayerCompletion(for: prayer)
                }
            }
        }
        #endif
//        .onChange(of: sharedState.navPosition){ oldValue, newValue in
//            if oldValue == .top && newValue == .main  {
//                sharedState.resetTasbeehInputs()
//                print("ResetTasbeehInputs cuz we dismissed DailyTasks.")
//            }
//        }
        .navigationDestination(isPresented: $settingsViewNavBool) {
            SettingsView()
        }
        .navigationDestination(isPresented: $showMapPage) {
            LocationMapContentView()
        }
        .navigationDestination(isPresented: $showDailyAyahPage) { DailyAyahView() }
        .navigationDestination(isPresented: $showMantrasPage) { AzkarPage() }
        .navigationDestination(isPresented: $showSalahHistoryV1) { SimpleDailyScoreView() }
        .navigationDestination(isPresented: $showSalahHistoryV2) { PrayerEditorView() }
        .navigationDestination(isPresented: $showZikrHistory) { ZikrHistoryPage() }
        .navigationDestination(isPresented: $showInsightsPage) { InsightsView() }
        .navigationDestination(isPresented: $showOldInsights) { InsightsView(layout: .old) }
        .navigationDestination(isPresented: $showNamesPage) { NamesOfAllahView() }
        .onChange(of: chosenMantra) {_, newMantra in
            if let text = newMantra {
                sharedState.titleForSession = text
                sharedState.mantraForSession = chosenMantraObject
            }
        }
        .whatsNewReturnPill()   // after What's new → "Open in shukr" to a pager page
        #if DEBUG
        .sheet(item: $demoMantra) { m in MantraEditorView(mantra: m) }
        .sheet(isPresented: $demoNewZikr) { MantraEditorView(mantra: nil) }
        .sheet(isPresented: $demoWhatsNew) { WhatsNewView() }
        #if DEBUG
        // `-whatsNewPerf`: close and open it again, to time a warm open (no launch work around it).
        .onReceive(NotificationCenter.default.publisher(for: WhatsNewPerf.reopen)) { _ in
            demoWhatsNew = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { WhatsNewPerf.opened = 0; demoWhatsNew = true }
        }
        #endif
        .sheet(isPresented: $demoScheduled) { NavigationStack { YourRemindersView() } }
        #endif
        .sheet(isPresented: $showMantraSheetFromHomePage) {
            MantraPickerView(
                isPresented: $showMantraSheetFromHomePage,
                selectedMantra: $chosenMantra,
                selectedMantraObject: $chosenMantraObject,
                presentation: [.height(400)]
            )
        }
        .fullScreenCover(isPresented: $showTasbeehPage) {
            tasbeehView(isPresented: $showTasbeehPage)

        }
        
        .edgesIgnoringSafeArea(.bottom)
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
    /// carry the circle up; all of it animates from the `withAnimation` around the
    /// `navPosition` change (swipe, chevron, bottom bar). The finger never drags the sheet: the
    /// owner tried follow-the-finger versions (a custom gesture, then a native ScrollView) and
    /// asked for this pop back (2026-09-24). `live.pull` is the resisted drag nudge.
    struct SalahPageContent: View {
        @EnvironmentObject var sharedState: SharedStateClass
        @EnvironmentObject var viewModel: PrayerViewModel
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

        var body: some View {
            VStack {
                Spacer()
                if showBottom {
                    Spacer()
                    Spacer()
                }

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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)

                Spacer()

                if showBottom {
                    Spacer()
                    BottomSharedView(
                        showDailyAyahView: $showDailyAyahView,
                        showMantraSheetFromHomePage: $showMantraSheetFromHomePage,
                        showTasbeehPage: $showTasbeehPage
                    )
                    .opacity(1 - Double(live.pull / 90))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    Spacer()
                }

                Color.clear.frame(height: showBottom ? bottomChromeHeight : closedBottomReserve)
            }
        }
    }

    /// Top bar (menu + TopBar on Salah, "Zikr" title on Zikr) and the chevron / bottom bar,
    /// fixed over the pager. Reads `live` so it alone re-renders while scrolling or dragging.
    struct PagerChromeView: View {
        @EnvironmentObject var sharedState: SharedStateClass
        var live: PagerLiveState
        @Binding var showMapPage: Bool
        @Binding var showDailyAyahPage: Bool
        @Binding var showMantrasPage: Bool
        @Binding var showSalahHistoryV1: Bool
        @Binding var showSalahHistoryV2: Bool
        @Binding var showZikrHistory: Bool
        @Binding var showInsightsPage: Bool
        @Binding var showOldInsights: Bool
        @Binding var showNamesPage: Bool
        @Binding var showTasbeehPage: Bool

        @State private var showMenu = false
        @State private var pendingMenuAction: (() -> Void)? = nil
        /// "What's new" (tap the build line in the menu; DEBUG / TestFlight only).
        @State private var showWhatsNew = false
        /// The compass calibration sheet (the line under the circle, or ☰ → Calibrate compass).
        @State private var showCalibration = false

        /// One row of the hamburger popover; closes it and runs `action` after it's gone.
        private func menuRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
            Button {
                pendingMenuAction = action
                showMenu = false
            } label: {
                Label(title, systemImage: symbol)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var showBottom: Bool { sharedState.navPosition == .bottom }
        /// How far onto the Zikr / Settings page we are, 0...1 each, live from the scroll offset.
        private var zikrness: CGFloat { min(max(1 - live.scrollProgress, 0), 1) }
        /// How far a top-bar title travels as the pager moves between Salah and Zikr.
        static let titlePush: CGFloat = 150
        private var settingsness: CGFloat { min(max(live.scrollProgress - 1, 0), 1) }
        /// Sheet open-progress on the Salah page, 0...1.
        private var sheetP: CGFloat { showBottom ? 1 : 0 }

        var body: some View {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // The two titles push each other with the pager (owner, 2026-10-01): swiping to Zikr
                    // (the page on the left) brings "Zikr" in from the left and pushes the Salah title
                    // out to the right, following the finger; back again the other way. Only these
                    // offsets read the live scroll — the titles' own bodies don't.
                    ZStack(alignment: .top) {
                        TopBar()
                            .offset(x: zikrness * Self.titlePush)
                            .opacity(Double(1 - zikrness))
                            .allowsHitTesting(zikrness < 0.5)
                        ZikrPageTitle()
                            .offset(x: -(1 - zikrness) * Self.titlePush)
                            .opacity(Double(zikrness))
                            .allowsHitTesting(zikrness > 0.5)
                    }

                    // Menu button: a native Menu instead of the hand-rolled drawer, which
                    // toggled shared state and re-rendered the whole home screen to animate.
                    HStack {
                        // The menu is a popover (a native Menu can't show the wordmark):
                        // "shukr" on top like the old sidebar, then the destinations.
                        ZStack {
                        // Zikr page, top left: History (the Zikr tab reorganisation; symbols only, 2026-10-01).
                        ZikrDoor(title: "History", symbol: "clock.arrow.circlepath") { showZikrHistory = true }
                            .opacity(Double(zikrness))
                            .allowsHitTesting(zikrness > 0.5)

                        Button { showMenu = true } label: {
                            Image(systemName: "line.3.horizontal")
                                .background(.white.opacity(0.01))
                                .frame(width: 24, height: 24)
                                .font(.system(size: 20))
                                .fontWeight(.light)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray.opacity(0.8))
                                // The compass needs calibrating: a red dot (its own small view, so the
                                // chrome doesn't redraw with the compass).
                                .overlay(alignment: .topTrailing) { CompassMenuBadge().offset(x: 3, y: -1) }
                                .padding()
                        }
                        .popover(isPresented: $showMenu, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("shukr")
                                    .font(.largeTitle)
                                    .fontWeight(.thin)
                                    .fontDesign(.rounded)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 18)
                                    .padding(.bottom, 10)
                                Divider()
                                menuRow("Insights", "chart.bar.xaxis") { showInsightsPage = true }
                                menuRow("Daily Ayah", "book") { showDailyAyahPage = true }
                                menuRow("99 Names", "moon.stars") { showNamesPage = true }
                                CompassMenuRow {
                                    pendingMenuAction = { showCalibration = true }
                                    showMenu = false
                                }
                                // Which build this is (BuildInfo): when it was built + the commit.
                                // Tap → What's new (DEBUG / TestFlight).
                                BuildLineButton {
                                    pendingMenuAction = { showWhatsNew = true }
                                    showMenu = false
                                }
                                    .font(.caption2)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                            }
                            .padding(.bottom, 8)
                            .frame(width: 250)
                            .presentationCompactAdaptation(.popover)
                        }
                        .onChange(of: showMenu) { _, open in
                            CircleCover.set("menu", open)
                            // Run the chosen action once the popover is away, so the push isn't
                            // attempted while a presentation is still dismissing.
                            guard !open, let action = pendingMenuAction else { return }
                            pendingMenuAction = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
                        }
                        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
                        .onChange(of: showWhatsNew) { _, open in CircleCover.set("whatsNew", open) }
                        .fullScreenCover(isPresented: $showCalibration) { CompassCalibrationSheet() }
                        .onChange(of: showCalibration) { _, open in CircleCover.set("compassCalibration", open) }
                        .onReceive(NotificationCenter.default.publisher(for: CompassHealth.openSheet)) { _ in
                            showCalibration = true
                        }
                        #if DEBUG
                        .task {   // `-demoCalibrationSheet` / `-demoMenuOpen`: the sheet / ☰ menu a few s in (screenshots)
                            let args = ProcessInfo.processInfo.arguments
                            if args.contains("-demoMenuOpen") {
                                try? await Task.sleep(for: .seconds(6))
                                showMenu = true
                            }
                            guard args.contains("-demoCalibrationSheet") else { return }
                            try? await Task.sleep(for: .seconds(4))
                            showCalibration = true
                        }
                        #endif
                        .opacity(Double(1 - zikrness))
                        .allowsHitTesting(zikrness < 0.5)
                        }
                        Spacer()
                        // Zikr page, top right: Azkar (Your tasks is "N of M tasks done" under the wheel).
                        ZikrDoor(title: "Azkar", symbol: "books.vertical") { showMantrasPage = true }
                            .opacity(Double(zikrness))
                            .allowsHitTesting(zikrness > 0.5)
                    }
                }

                Spacer()

                ZStack(alignment: .bottom) {
                    // Chevron hint: Salah page, sheet closed. Follows the pull-to-refresh nudge.
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            sharedState.navPosition = showBottom ? .main : .bottom
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.title3)
                            .foregroundStyle(live.pull != 0 ? Color.secondary : Color(.secondarySystemFill))
                            .padding(.bottom, 30)
                            .padding()
                            .offset(y: live.pull)
                    }
                    .opacity(Double((1 - sheetP) * (1 - zikrness)) * (live.postSalahNudge == nil ? 1 : 0))
                    .allowsHitTesting(sheetP < 0.5 && zikrness < 0.5 && live.postSalahNudge == nil)

                    // Bottom bar: Salah with the sheet up, and always on Zikr.
                    CustomBottomBar()
                        .opacity(Double(max(sheetP, zikrness)))
                        .allowsHitTesting(max(sheetP, zikrness) > 0.5)
                }
            }
            // Just prayed: the post-salah pill. Bottom of the page (in the chevron's place) with the
            // sheet closed; with the prayer list open it would cover the last prayer, so it docks
            // under the top bar instead. Chrome, above the pager: dragging it never moves a page.
            .overlay(alignment: showBottom ? .top : .bottom) {
                if live.postSalahNudge != nil {
                    PostSalahNudge(
                        onOpen: {
                            live.postSalahNudge = nil
                            sharedState.isDoingPostNamazZikr = true
                            showTasbeehPage = true
                        },
                        onDismiss: { live.postSalahNudge = nil },  // the pill animates (or not) itself
                        shown: zikrness < 0.5 && settingsness < 0.5
                    )
                    .padding(.top, showBottom ? 64 : 0)
                    .padding(.bottom, showBottom ? 0 : 34)
                    .opacity(Double(1 - zikrness))
                    .allowsHitTesting(zikrness < 0.5)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBottom)
            .allowsHitTesting(settingsness < 0.5)
            .ignoresSafeArea(edges: .bottom)
            // Toward Settings the chrome leaves WITH the Salah page, so Settings slides over
            // empty space instead of under a fading top bar (owner, 2026-09-25).
            .visualEffect { [settingsness] content, proxy in
                content.offset(x: -settingsness * proxy.size.width)
            }
        }
    }

    /// The Zikr page's title in the fixed top bar, in TopBar's type (owner, 2026-10-01). It follows the
    /// wheel: a centred task shows its streak ("8 Day Streak", "0 Day Streak" when there's none yet);
    /// freestyle and New task show "Zikr". Each item's label is pushed in the wheel's direction — moving
    /// down, the next one comes up from below and the last goes up and out; moving up, the other way.
    /// A tap on a task's streak toggles "Max N Days" (back to the streak on the next tap or item).
    /// Outline beads; the flame is an outline in grey until today's goal is met, then filled sage.
    struct ZikrPageTitle: View {
        @Query private var tasks: [TaskModel]
        @State private var showBest = false
        private let focus = ZikrWheelFocus.shared
        private static let travel: CGFloat = 12

        var body: some View {
            let task = focus.taskID.flatMap { id in tasks.first { $0.id == id } }
            let down = focus.movedDown
            // Same metrics as TopBar's location row so the title sits where the city does.
            ZStack {
                label(task)
                    .id(focus.key)
                    .transition(.asymmetric(
                        insertion: .offset(y: down ? Self.travel : -Self.travel).combined(with: .opacity),
                        removal: .offset(y: down ? -Self.travel : Self.travel).combined(with: .opacity)))
            }
            .padding()
            .frame(height: 24, alignment: .center)
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .animation(.spring, value: focus.key)
            .onChange(of: focus.key) { _, _ in showBest = false }
            .padding()
        }

        @ViewBuilder private func label(_ task: TaskModel?) -> some View {
            if let task {
                let streak = task.streak()
                HStack(alignment: .center) {
                    Image(systemName: streak.keptToday ? "flame.fill" : "flame")
                        .foregroundColor(streak.keptToday ? Color.sage : .secondary)
                    Group {
                        if showBest {
                            Text("Max \(streak.best) Days").transition(.blurReplace)
                        } else {
                            Text("\(streak.current) Day Streak").transition(.blurReplace)
                        }
                    }
                    .fixedSize()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerSomeVibration(type: .light)
                    withAnimation { showBest.toggle() }
                }
            } else {
                HStack {
                    Image(systemName: "circle.hexagonpath")
                        .foregroundColor(.secondary)
                    Text("Zikr")
                }
            }
        }
    }
    struct BottomSharedView: View {
        @EnvironmentObject var sharedState: SharedStateClass
        
        // Bindings coming from the parent view
        @Binding var showDailyAyahView: Bool
        @Binding var showMantraSheetFromHomePage: Bool
        @Binding var showTasbeehPage: Bool
        @State private var selectedDate: Date = Date()
        @State private var someIndex: Int = 0
        // Generate dates for a year (adjust as needed)
        let days: [Date] = [Date(), Date().addingTimeInterval(-86400), Date().addingTimeInterval(-172800)]
        
        // Add a property to receive the gesture


        // DateFormatter for M/d format
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter
        }()
        
        var body: some View {
            VStack {
                // Shared container for both views
//                ZStack {
                if sharedState.bottomTabPosition == .salah {
                    TodaysPrayerListView(
                        showDailyAyahView: $showDailyAyahView
                    )
                    
                    
                    /*
                    InfiniteDaysScrollView(selectedDate: $selectedDate)
                        .frame(height: 30)
                        .frame(width: 260) // Same width as PrayerListView
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    SomedaysPrayerListView(
                        showDailyAyahView: $showDailyAyahView,
                        selectedDate: selectedDate
                    )
                    */
                    .transition(.opacity)
                    .frame(width: 260)  // Same width as PrayerListView
                    .background(FlatBorder())
                
                } else if sharedState.bottomTabPosition == .zikr{
                    DailyTasksView(
                        showMantraSheetFromHomePage: $showMantraSheetFromHomePage,
                        showTasbeehPage: $showTasbeehPage
                    )
                    .transition(.opacity)
                    .frame(width: 260)  // Same width as PrayerListView
                    .background(FlatBorder())
                    .padding(.bottom, 30)
                }
            }
//            .transition(.opacity)
//            .frame(width: 260)  // Same width as PrayerListView
//            .background(FlatBorder())

            .animation(.easeOut, value: sharedState.bottomTabPosition)
        }
    }

    
    struct CustomBottomBar: View {
        @EnvironmentObject var sharedState: SharedStateClass

        var body: some View {
            VStack(spacing: 0){

                    Divider()
                    .frame(height: 2)
                    .background(Color(.secondarySystemBackground))

                    
                    HStack {
                        
                        
                        Button(action: {
                            sharedState.horizontalPage = .zikr
                        }) {
                            VStack(spacing: 6){
                                Image(systemName: "circle.hexagonpath")
                                    .font(.system(size: 20))
                                Text("Zikr")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor( sharedState.horizontalPage == .zikr ? .green : .gray)
                            .frame(width: 100)
                        }

                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                sharedState.bottomTabPosition = .salah
                                sharedState.horizontalPage = .main
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait")
                                    .font(.system(size: 20))
                                Text("Salah")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor(sharedState.horizontalPage == .main ? .green : .gray) // by page, like its siblings
                            .frame(width: 100)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            sharedState.horizontalPage = .settings
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 20))
                                Text("Settings")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor(sharedState.horizontalPage == .settings ? .green : .gray)
                            .frame(width: 100)
                        }
                    }
                    .padding(.top, 15)
                    .padding(.bottom, 25)
                    .padding(.horizontal, 45)
                    .opacity(0.8)
//                    .background(Color("bgColor"))
                
            }
            .background(Color(UIColor.systemBackground))
        }
        
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
            .environmentObject(sharedState)
    }
}

// MARK: - Prayer List

struct TodaysPrayerListView: View {

    @EnvironmentObject var viewModel: PrayerViewModel
    @Binding var showDailyAyahView: Bool
    let spacing: CGFloat = 6

    /// Done prayers fold out of the list so it only shows what's left; all five come back once
    /// the day is complete. A prayer just marked lingers ~1 s so its dot can pop first.
    @State private var lingering: Set<String> = []
    /// "3 done" row tapped: show the done ones too (to check a score or unmark one).
    @State private var showDone = false
    /// Perfect day: bumps to bounce the footer's sparkles; `demoPerfect` shows the footer
    /// for the DEBUG "Test Perfect Day" row even when today isn't one.
    @State private var perfectPulse = 0
    @State private var demoPerfect = false
    /// When the perfect-day cascade starts after the notification: after the circle's flourish,
    /// once all five rows have come back (they wait for it).
    static let perfectDayCascadeStart: Double = CompletionFlourish.duration + 0.3

    var body: some View {
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

        VStack{
            VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                ForEach(Array(visible.enumerated()), id: \.element) { index, prayerName in
                    VStack(spacing: 0) {
                        PrayerButton(
                            name: prayerName,
                            viewModel: viewModel
                        )
                        .padding(.bottom, index == visible.count - 1 ? 0 : spacing)

                        if index < visible.count - 1 {
                            Divider()
                                .frame(height: 1)
                                .background(Color(.secondarySystemFill))
                                .padding(.top, -spacing / 2 - 0.5)
                                .padding(.horizontal, 25)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))))
                }

                // The folded ones, as a footer row: a divider like the rows', then "✓ 3 done ⌄"
                // centred with the same air above and below as a row (2026-09-25 — the old line
                // hung under the list with a bare 10 pt gap and no divider, which read off).
                // Kept while the last prayer's row lingers (the circle's flourish): hiding it at the
                // mark shortened the list and dropped the circle ~19 pt mid-moment (2026-09-27).
                if (foldedCount > 0 || showDone) && (!allDone || !lingering.isEmpty) {
                    VStack(spacing: 0) {
                        if !visible.isEmpty {
                            Divider()
                                .frame(height: 1)
                                .background(Color(.secondarySystemFill))
                                .padding(.horizontal, 25)
                        }
                        Button {
                            triggerSomeVibration(type: .light)
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showDone.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                // Same words open or closed (swapping to "hide done" morphed oddly
                                // mid-spring — owner); only the chevron turns.
                                Text("\(done.count) done")
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
                            .padding(.top, visible.isEmpty ? 0 : 12)
                            .padding(.bottom, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, visible.isEmpty ? 0 : spacing)
                    .transition(.opacity)
                }

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
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .onReceive(NotificationCenter.default.publisher(for: .perfectDay)) { note in
            if note.object as? Bool == true {
                withAnimation { demoPerfect = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { withAnimation { demoPerfect = false } }
            }
            // A light tap per dot as they pop (PrayerButton), then the sparkles bounce.
            let start = Self.perfectDayCascadeStart
            for i in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.13 * Double(i)) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5 + 0.1 * Double(i))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.75) {
                perfectPulse += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompleted)) { note in
            guard let event = note.object as? PrayerCompletionEvent else { return }
            // The row stays (and a completed day's other rows stay folded) until the circle's
            // flourish is done: the list changing height moved the circle mid-sweep (owner, 2026-09-27).
            let name = event.prayerName ?? event.name   // the row's name ("Dhuhr" for a Jumu'ah)
            lingering.insert(name)
            DispatchQueue.main.asyncAfter(deadline: .now() + CompletionFlourish.duration) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    _ = lingering.remove(name)
                }
            }
        }
        .onChange(of: allDone) { _, isDone in
            if isDone { showDone = false }   // the day's complete: everything's back anyway
        }
    }
 
}

/*
struct SomedaysPrayerListView: View {

    @EnvironmentObject var viewModel: PrayerViewModel
    @Binding var showDailyAyahView: Bool
    let selectedDate: Date
    let spacing: CGFloat = 6
    
    var body: some View {
        VStack{
            VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
                    PrayerButton(forDate: selectedDate, name: prayerName, viewModel: viewModel)
                    .padding(.bottom, prayerName == "Isha" ? 0 : spacing)
                    
                    if prayerName != "Isha" {
                        Divider()
                            .frame(height: 1)
                            .background(Color(.secondarySystemFill))
                            .padding(.top, -spacing / 2 - 0.5)
                            .padding(.horizontal, 25)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
 
}
*/

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
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0


    
    @State private var toggledText: Bool = false
    /// The dot's centre in the row (`rowSpace`), for `rowGesture`.
    @State private var dotCenter = CGPoint(x: 23, y: 22)
    /// Bumps when this prayer is marked done, popping the dot (CompletionDotPop).
    @State private var completionPulse = 0
    @AppStorage(PrayerDotStyle.key) private var dotStyleRaw = PrayerDotStyle.muted.rawValue
    @State private var showMarkIncompleteAlert = false // State for showing alert
    @State private var isMarkingIncomplete = false // Track if we are marking incomplete
    @State private var showTimePicker = false
    @State private var selectedEditTimeDate = Date()
    @State private var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var searchQuery = ""
    
    private func handlePrayerButtonPress() {
        // Only allow pressing on Future Prayers
        if !isFuturePrayer {
            if !prayerObject.isCompleted {
                viewModel.togglePrayerCompletion(for: prayerObject)   // the post-salah pill follows (.prayerCompleted)
            }
            else {
                showMarkIncompleteAlert = true
            }
        }
    }
    
    let prayerObject: PrayerModel
    let name: String
        
    init(name: String, viewModel: PrayerViewModel) {
        guard let foundPrayer = viewModel.todaysPrayers.first(where: { $0.name == name }) else {
            fatalError("PrayerModel not found for name: \(name)")
        }
        self.prayerObject = foundPrayer
        self.name = name
    }
  
    // added this so we can get the prayerList for another date other than today.
    init(forDate: Date, name: String, viewModel: PrayerViewModel) {
        let updatingToday = Calendar.current.isDate(forDate, inSameDayAs: Date())
        let objectsToCheck: [PrayerModel] = updatingToday ? viewModel.todaysPrayers : viewModel.loadPrayerObjects(for: forDate)
        self.name = name
        // check if the prayerObect is not nil
        // if so, make it. use some viewmodel function.
        if let foundPrayer = objectsToCheck.first(where: { $0.name == name }){
            self.prayerObject = foundPrayer
        } else{
            let newPrayer = viewModel.createPrayerModel(name: name, at: forDate)
            self.prayerObject = newPrayer
        }
    }
        
    private func searchLocation() {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = searchQuery
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            guard let response = response else {
                print("Error: \(error?.localizedDescription ?? "Unknown error").")
                return
            }
            
            if let firstItem = response.mapItems.first {
                selectedLocation = firstItem.placemark.coordinate
            }
        }
    }

    private var nameToDisplay: String{
        let isTodayFriday = Calendar.current.component(.weekday, from: Date()) == 6
        if (name == "Dhuhr" && isTodayFriday){ return "Jummah" }
        else { return name }
    }
    
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
        return .footnote
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

    /// "On time · 88" (PrayerScoring); a Jumu'ah names its masjid instead.
    private var completedTimeAndScore: String {
        prayerObject.scoreSummary ?? "Missed"
    }
    
    
    /// A tap on the time: flip its text (a started prayer's time doesn't flip).
    private func timeTap() {
        guard isFuturePrayer || prayerObject.isCompleted else { return }
        withAnimation { toggledText.toggle() }   // ExternalToggleText flips (and flips back after 3 s)
    }

    /// A tap round the dot: mark / unmark (a prayer that hasn't started can't be marked).
    private func markTap() {
        if !isFuturePrayer { handlePrayerButtonPress() }
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
        // Open on the prayer's own day. The wheel only edits hour/minute and keeps the date it
        // starts with: starting from a tap after midnight (rollover) put every picked time on the
        // next day — always Qaza.
        let marked = prayerObject.timeAtComplete ?? Date()
        selectedEditTimeDate = min(max(marked, editTimeRange.lowerBound), editTimeRange.upperBound)
        showTimePicker = true
    }

    var body: some View {
            // Where a tap marks (owner, 2026-09-29: testers kept missing the dot): a 44 pt circle round the
            // dot (`markRadius`), stopping short of the name; the rest of the row flips the time as before.
            // The dot used to be a Button round its 14 pt circle, the only place a tap marked.
            HStack {
                PrayerStatusDot(style: PrayerDotStyle(rawValue: dotStyleRaw) ?? .muted,
                                done: prayerObject.isCompleted && !isFuturePrayer,
                                future: isFuturePrayer,
                                scoreColor: prayerObject.getColorForPrayerScore(),
                                pulse: completionPulse)
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let f = proxy.frame(in: .named(PrayerButton.rowSpace))
                        return CGPoint(x: f.midX, y: f.midY)
                    } action: { dotCenter = $0 }
                    #if DEBUG
                    .overlay { HitAreaDebug.overlay }
                    #endif
                    .frame(width: 24, height: 24, alignment: .leading)

                // Prayer Name Label
                Text(prayerObject.displayName)   // "Jumu'ah" when Friday's Dhuhr was at a masjid
                    .font(.callout) //.callout
                    .foregroundColor(.secondary.opacity(statusBasedOpacity)) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                // Prayed at a masjid: a small mosque mark by the name.
                if prayerObject.atMasjid {
                    Image(systemName: "building.columns")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.sage)
                }

                Spacer()

                timeColumn
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .coordinateSpace(.named(PrayerButton.rowSpace))
            .gesture(rowGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: prayerObject.isCompleted ? "Mark not prayed" : "Mark prayed") { markTap() }
            // Background Effects Container
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(backgroundColor)
            )
            .animation(.spring(response: 0.1, dampingFraction: 0.7), value: prayerObject.isCompleted)
            .onChange(of: prayerObject.isCompleted) { _, done in
                if done { completionPulse += 1 }
            }
            .onReceive(NotificationCenter.default.publisher(for: .perfectDay)) { _ in
                // Perfect day: the five dots pop one after another, once the list has all
                // five back (TodaysPrayerListView brings them back ~1 s after the last mark).
                let index = Double(viewModel.orderedPrayerNames.firstIndex(of: name) ?? 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + TodaysPrayerListView.perfectDayCascadeStart + 0.13 * index) {
                    completionPulse += 1
                }
            }
            .alert(isPresented: $showMarkIncompleteAlert) {
                        Alert(
                            title: Text("Confirm Action"),
                            message: Text("Are you sure you want to mark this prayer as incomplete?"),
                            primaryButton: .destructive(Text("Yes")) {
                                isMarkingIncomplete = true
                                withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                                    viewModel.togglePrayerCompletion(for: prayerObject)
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    }
            .onChange(of: showTimePicker) { _, open in CircleCover.set("timeEdit.\(prayerObject.name)", open) }
            .sheet(isPresented: $showTimePicker) {
                PrayerTimeEditSheet(prayer: prayerObject, time: $selectedEditTimeDate, range: editTimeRange,
                                    onCancel: { showTimePicker = false },
                                    onSave: { date, spot in
                                        // A user edit: the recorded time / spot are kept (revertible).
                                        let old = prayerObject.timeAtComplete ?? .distantPast
                                        if abs(date.timeIntervalSince(old)) >= 30 { viewModel.editPrayerTime(prayerObject, to: date) }
                                        if let spot { viewModel.movePrayer(prayerObject, to: spot) }
                                        showTimePicker = false
                                    })
            }
    }

    /// The time: the start time, flipping to the countdown (a prayer to come) or the score (a marked
    /// one). Its own tap is off: the row's gesture drives it through `toggledText`.
    @ViewBuilder private var timeColumn: some View {
                if isFuturePrayer {
                    // Future Prayer: Toggleable Time/Countdown
                    ExternalToggleText(
                        originalText: shortTimePM(calcStartTime),
                        toggledText: timeUntilStart(calcStartTime),
                        externalTrigger: $toggledText,
                        font: timeFontSize,
                        fontDesign: .rounded,
                        fontWeight: .light,
                        hapticFeedback: true
                    )
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    .allowsHitTesting(false)

                } else if prayerObject.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if prayerObject.timeAtComplete != nil {
                        ExternalToggleText(
                            originalText: shortTimePM(calcStartTime),
                            toggledText: completedTimeAndScore,
                            externalTrigger: $toggledText,
                            font: timeFontSize,
                            fontDesign: .rounded,
                            fontWeight: .light,
                            hapticFeedback: true
                        )
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                            .allowsHitTesting(false)
                    }
                } else {
                    // Current Prayer: Show Start Time
                    Text(shortTimePM(calcStartTime))
                        .font(timeFontSize)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
    }

        
    struct MiniMapView: View {
        @Binding var coordinate: CLLocationCoordinate2D
        @State private var region: MKCoordinateRegion
        
        init(coordinate: Binding<CLLocationCoordinate2D>) {
            self._coordinate = coordinate
            _region = State(initialValue: MKCoordinateRegion(
                center: coordinate.wrappedValue,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        
        var body: some View {
            Map(coordinateRegion: $region, interactionModes: .all, showsUserLocation: true, userTrackingMode: .none)
                .onTapGesture { location in
                    let coordinate = region.center
                    self.coordinate = coordinate
                }
        }
    }
}

struct ChevronTap: View {
    var body: some View {
//        Image(systemName: "chevron.right")
//            .foregroundColor(.gray)
//            .onTapGesture {
//                triggerSomeVibration(type: .medium)
//                print("chevy hit")
//            }
        
        NavigationLink(destination: /*PrayerEditorView*//*ScrollablePrayerScoreView*/SimpleDailyScoreView()) {
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
    }
}

struct ChevronTap2: View {
    var body: some View {
//        Image(systemName: "chevron.right")
//            .foregroundColor(.gray)
//            .onTapGesture {
//                triggerSomeVibration(type: .medium)
//                print("chevy hit")
//            }
        
        NavigationLink(destination: PrayerEditorView()) {
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
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
    /// The Zikr page's task strip, in global coordinates (written by DailyTasksView); touches
    /// that start inside it hold the pager.
    var stripFrame: CGRect = .zero
    /// The pager is `.scrollDisabled` while this is set. Set by the pager's own drag gesture
    /// once a drag is decided vertical (so sideways drift can't turn into a page swipe) and by
    /// the Zikr page's task strip while a finger is on it (so a drag past the strip's last
    /// card can't chain into a page turn). Cleared on release.
    var pagerLocked = false
}


/// Behind the pager: one panel per page (Zikr, Salah plain; Settings grouped-gray in light mode)
/// offset by the live scroll position, so each page's colour — status-bar strip included —
/// moves with its page. Its own view so only it re-renders per scroll frame.
struct PagerBackdrop: View {
    let live: PagerLiveState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                Color(.systemBackground).frame(width: width * 2)
                Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground).frame(width: width)
            }
            .frame(width: width * 3, alignment: .leading)
            .offset(x: -live.scrollProgress * width)
        }
        .ignoresSafeArea()
    }
}

/// `.scrollDisabled(live.pagerLocked)` in its own modifier: reading `pagerLocked` in
/// PrayerTimesView's body re-rendered the whole tree on every touch-down and release on the
/// task strip; here only this modifier re-evaluates.
struct PagerLock: ViewModifier {
    var live: PagerLiveState
    func body(content: Content) -> some View {
        content.scrollDisabled(live.pagerLocked)
    }
}

/// The pager's Settings page. Equatable and always equal: it has no inputs that change, so when
/// the pager re-renders (every page turn publishes `sharedState`) SwiftUI skips it instead of
/// rebuilding the whole Settings Form. Settings still updates from its own state, @AppStorage
/// and the view model.
struct SettingsPage: View, Equatable {
    var onBack: () -> Void
    static func == (lhs: SettingsPage, rhs: SettingsPage) -> Bool { true }
    var body: some View { SettingsView(onBack: onBack) }
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

    /// After an action: hand the keyboard / focus back to the app's window.
    static func finish() {
        let appWindow = scene?.windows.first { $0 !== window && $0.windowLevel == .normal }
        window?.isHidden = true
        window = nil
        appWindow?.makeKey()
    }
}
