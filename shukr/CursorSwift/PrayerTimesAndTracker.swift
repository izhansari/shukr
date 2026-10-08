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
    @Environment(SharedStateClass.self) var sharedState
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
    @State private var pendingOpen: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Widget / control / Action-button opens (one-shot flags in the app group). Held while the
    /// first-run setup is up — the flags stay set and this runs again once it's done
    /// (`FirstRunSetup.finished`), so its hand-off always lands on this page's circle.
    private func openFromWidgetFlags() {
        guard !FirstRunSetup.isShowing else { return }
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
            let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
            if FirstRunSetup.deepLinkFlags.contains(where: { store.object(forKey: $0) != nil && store.bool(forKey: $0) })
                || store.string(forKey: "widgetZikrTask") != nil {
                lastDeepLinkAt = Uptime.now   // no reminders card over where a widget just sent you
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
                lastDeepLinkAt = Uptime.now
                clearCovers { sharedState.horizontalPage = .main }
            }
            // A marked row in the widget's times list: ask here, never unmark there.
            if store.string(forKey: WidgetListMarks.unmarkKey) != nil {
                lastDeepLinkAt = Uptime.now
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
            // Every widget open goes straight there: no page slide, no push, no wheel turn (owner: "no animation go
            // straight to the desired task … any widget action honestly"; the welcome is skipped too — WelcomeGate).
            if openAyahFromWidget {
                openFromWidget {
                    sharedState.go(to: .main, animated: false)
                    instantly { showDailyAyahPage = true }
                }
            } else if openNamesFromWidget {
                openFromWidget {
                    sharedState.go(to: .main, animated: false)
                    instantly { showNamesPage = true }
                }
            }

            if openCompassFromWidget, !showQiblaMap {
                openFromWidget {
                    instantly {
                        sharedState.navPosition = .main
                        showQiblaMap = true
                    }
                }
            }
            
            else if openTasbeehFromWidget{
                openFromWidget {
                    // A task row in the Zikr widget: that task's circle already in the middle.
                    if let zikrTaskID { ZikrFocus.request(zikrTaskID, instant: true) }
                    // A turn later: on a cold launch the pager isn't laid out yet, and its first report put it back on
                    // Salah.
                    DispatchQueue.main.async { sharedState.go(to: .zikr, animated: false) }
                }
            }
        }
    }

    /// A widget open: at once when nothing covers the page (a cold launch — no hop through a task, so the page is
    /// already there when the app first shows), else once the covers have gone (`clearCovers`).
    private func openFromWidget(_ go: @escaping @MainActor () -> Void) {
        guard !showTasbeehPage else { return }
        if !somethingCovers && CircleCover.active.isEmpty {
            pendingOpen?.cancel()
            go()
        } else {
            clearCovers { go() }
        }
    }

    /// A change with no animation (a widget open: the page is simply there). The root stack's push is UIKit's and
    /// ignores the transaction, so UIKit's animations are off too for a moment.
    private func instantly(_ change: () -> Void) {
        UIView.setAnimationsEnabled(false)
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet, change)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UIView.setAnimationsEnabled(true) }
    }

    /// "Unmark Asr?" → Unmark, from the widget's times list: today's row goes through the app's own
    /// unmark (as the list's own alert does: day score, streak, widget); a row of another day has
    /// every completed row of it reset, then the day and streaks are redone.
    private func unmarkFromWidget(_ request: WidgetUnmarkRequest) {
        viewModel.reconcileAfterWidgetWrites()   // a widget mark that just landed
        // Every completed row of that prayer on that day (a day can hold duplicates): the one on
        // today's list through the app's own unmark (haptic, day score, streak, widget), the rest reset.
        let shown = viewModel.todaysPrayers.first {
            !TourRuntime.isPracticeAnywhere($0) && $0.isCompleted && $0.name == request.name && Calendar.current.isDate($0.startTime, inSameDayAs: request.start)
        }
        let others = completedRows(request).filter { $0.persistentModelID != shown?.persistentModelID }
        others.forEach { $0.resetPrayer(); PrayerPhotos.discard(for: $0) }
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
        // 2.8.0: the prayer day the request's start falls in, by key.
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forRow: name, startingAt: request.start)))) ?? []
        return rows.filter { $0.name == name && $0.isCompleted }
    }

    /// "Unmark Asr?" appears over whatever is on screen — the Zikr page, Settings, a pushed page, the
    /// map, a sheet or the ☰ popover — with no navigating (owner, CBBBBD1D: it only came up on the Salah
    /// page). It's a UIKit alert in its own window above the app (`OverlayAlert`), so no sheet, popover
    /// or cover can hide it (presented from the root it sat under a sheet SwiftUI had presented from a
    /// nested controller). It waits during the first-run setup and the opening and while the app isn't active; a
    /// tasbeeh session is paused first. Until then the request stays in the app group; the next activation picks it
    /// up again.
    private func showWidgetUnmarkWhenClear(token: Int) {
        unmarkWait?.cancel()
        unmarkWait = Task { await showWidgetUnmark(token: token) }
    }

    /// Waits on the stage — the app active, no setup, no welcome — waking when that changes (it retried every second,
    /// 90 times: tr-final); the request stays in the app group meanwhile, and the next activation tries again.
    private func showWidgetUnmark(token: Int) async {
        let stage = CircleStage.shared
        let welcome = WelcomeTarget.state
        guard token == widgetUnmarkToken, widgetUnmark == nil,
              let store = UserDefaults(suiteName: SharedStore.appGroup),
              store.string(forKey: WidgetListMarks.unmarkKey) != nil,
              await stage.until(deadline: Self.unmarkDeadline, {
                  // …and not during the tour: its list is the practice day (Ben's G7).
                  stage.sceneActive && !welcome.playing && !stage.covers.contains("firstRunSetup")
                      && !TourRuntime.shared.active
              }),
              token == widgetUnmarkToken, OverlayAlert.canShow else { return }
        // A tasbeeh session up: it goes into its pause state first, then the prompt shows over it (owner,
        // CA197AE2 — it used to wait until the session closed). `CircleCover` "tasbeeh" is set by the session
        // itself: this closure's own view copy can read a stale `showTasbeehPage`.
        if showTasbeehPage || stage.covers.contains("tasbeeh") {
            NotificationCenter.default.post(name: TasbeehSession.pauseRequest, object: nil)
            guard await CircleGate.pause(Self.sessionPausesDuration), token == widgetUnmarkToken else { return }
        }
        guard let raw = store.string(forKey: WidgetListMarks.unmarkKey) else { return }
        guard let request = WidgetUnmarkRequest(raw) else { store.removeObject(forKey: WidgetListMarks.unmarkKey); return }
        // Still wanted (not already unmarked meanwhile): show it, and only then take the request.
        store.removeObject(forKey: WidgetListMarks.unmarkKey)
        let rows = completedRows(request)
        guard !rows.isEmpty else { return }
        var shown = request
        shown.displayName = rows.contains(where: \.isJumuah) ? "Jumu'ah" : request.name
        widgetUnmark = shown
        let photo = rows.contains(where: PrayerPhotos.exists(for:))
        let alert = UIAlertController(title: "Unmark \(shown.displayName)?",
                                      message: "Are you sure you want to mark this prayer as incomplete?"
                                        + (photo ? " Its photo will be deleted too." : ""),
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
    @State private var unmarkWait: Task<Void, Never>?
    private static let unmarkDeadline: Double = 90
    /// A paused session's pause screen coming in before the prompt goes over it (an observable "paused" from the
    /// session would replace this wait).
    private static let sessionPausesDuration: Double = 0.4

    /// The reminders card (NotificationHealth): notifications off, or held for the Scheduled Summary.
    @State private var healthCard: NotificationHealth.Issue?
    /// Set by the card's onAppear; bumped per attempt so an older check can't clear a newer card.
    @State private var healthCardAppeared = false
    @State private var healthCardToken = 0
    @State private var lastDeepLinkAt: TimeInterval = -.infinity   // Uptime, never the wall clock (audit F, F6)

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

    private func clearCovers(then go: @escaping @MainActor () async -> Void) {
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
                    guard sharedState.horizontalPage == .main, !sheetFollows else { return }
                    let nudged = min(max(value.translation.height * resistanceFactor, -maxOffset), maxOffset)
                    live.pull = showBottom ? max(0, nudged) : nudged   // no upward nudge once open
                    live.refreshReach = showBottom ? 0 : max(value.translation.height, 0) / threshold
                }
            }
            .onEnded { value in
                let vertical = isDraggingVertically == true
                isDraggingVertically = nil
                live.pagerLocked = false
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
        isDraggingVertically = nil
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
            // The lost page is the Salah page alone (circle step 3b): nothing else to swipe to, as before.
            .scrollDisabled(CircleStage.shared.lost != nil)
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
            .onChange(of: pagerDragActive) { _, active in if !active { pagerDragReleased() } }
            .onScrollPhaseChange { _, phase, context in
                live.pagerPhase = phase
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
            .onChange(of: sharedState.horizontalPage) { left, now in
                // Settings may have changed how times are worked out: refetch on leaving its page.
                if left == .settings, now != .settings { viewModel.fetchPrayerTimes(cameFrom: "left the Settings page") }
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

            // "shukr lost your location" (circle step 3b): its buttons, and what runs it — the circle shows the rest.
            LostPageLayer()

            // The first-run tour (Tour.swift): its callout over the live app, never over a cover or a session.
            // Any stage cover too (the ☰ menu, the map, a row's time editor): the edit step's "Close it" is its close.
            // Not the scene phase (owner: the tooltip went away and came back with Control Center / a notification):
            // only something truly over the page hides it.
            TourLayer(covered: somethingCovers || showTasbeehPage || CircleStage.shared.lost != nil
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
            // The Zikr Tour on the Zikr page (ZikrTour.swift): its offer and its steps there.
            ZikrTourLayer(covered: somethingCovers || showTasbeehPage || !CircleStage.shared.covers.isEmpty,
                          onZikr: sharedState.horizontalPage == .zikr && CircleStage.shared.restingPage == .zikr)

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
            guard !hidden, TourRuntime.shouldAutoStart else { return }
            tourWait?.cancel()
            tourWait = Task {
                // A breath on the real day after the welcome lands, ring alive, before the invitation (audit L).
                try? await Task.sleep(for: .seconds(2.5))
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
                case "insights": showInsightsPage = true
                default: break
                }
            }
        }
        // "I already prayed" on a banner while the app is in front (audit B7): the mark lands in the shared store now
        // and the page used to show it unmarked until the next activation (a re-tap then rescored it).
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.markedElsewhere)) { _ in openFromWidgetFlags() }
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
        .onAppear { ZikrLock.shared.checkExisting(in: context) }
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
            // `-demoJumuahRow <masjid>` (with circle-check's clock on a Friday): today's Dhuhr marked at that masjid, the
            // list open, and its row's masjid line (decision jumuah-name-render B).
            if let masjid = UserDefaults.standard.string(forKey: "demoJumuahRow") {
                try? await Task.sleep(for: .seconds(2))
                guard let dhuhr = viewModel.todaysPrayers.first(where: { $0.name == "Dhuhr" }) else { return }
                dhuhr.mosqueName = masjid
                if !dhuhr.isCompleted {
                    dhuhr.isCompleted = true
                    dhuhr.timeAtComplete = dhuhr.startTime.addingTimeInterval(20 * 60)
                }
                try? context.save()
                sharedState.navPosition = .bottom
                PrayerListFold.shared.showDone = true
                try? await Task.sleep(for: .seconds(3))
                NotificationCenter.default.post(name: PrayerButton.demoMasjidLine, object: nil)
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
                if SessionHandoff.shared.openInPlace() {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { showTasbeehPage = true }
                } else {
                    showTasbeehPage = true
                }
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
                // `-demoLongZikr`: a zikr with a long card (the built-ins' texts, several times over, and a long note —
                // nothing typed from memory), to see how the pause screen holds it.
                if ProcessInfo.processInfo.arguments.contains("-demoLongZikr") {
                    let longName = UserDefaults.standard.string(forKey: "demoLongZikrName") ?? "Long morning azkar"
                    if MantraModel.find(named: longName, in: context) == nil {
                        let builtIns = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? [])
                            .filter { $0.builtInID != nil && !$0.fullText.isEmpty }
                        let body = Array(repeating: builtIns.map(\.fullText).joined(separator: "\n"), count: 3)
                            .joined(separator: "\n")
                        let m = MantraModel(name: longName, fullText: body,
                                            notes: "Said each morning after Fajr, slowly, one line at a time. My teacher asked me to keep it short on busy days, but to read every line on the weekend and to think about what each one means before moving on to the next.")
                        context.insert(m)
                        try? context.save()
                    }
                    // With `-demoZikrMedia` too: the same sample memo and photo as Alhamdulillah's.
                    if ProcessInfo.processInfo.arguments.contains("-demoZikrMedia"),
                       let source = ZikrMediaDemo.seed(in: context),
                       let long = MantraModel.find(named: longName, in: context) {
                        long.imageData = source.imageData
                        long.audioData = source.audioData
                        try? context.save()
                    }
                    UserDefaults.standard.set(longName, forKey: "demoPauseZikr")
                }
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
                withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
                if !ProcessInfo.processInfo.arguments.contains("-demoPrayerStart") { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoDayMilestones") {
                // Streak (fake 12) + on-time streak (fake 5) in the top bar, perfect day in the list.
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
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
                    // `-demoPrayerStartAgo <s>`: already that far into its window instead of starting in 6 s.
                    else if i == target {
                        let ago = UserDefaults.standard.double(forKey: "demoPrayerStartAgo")
                        p.startTime = now.addingTimeInterval(ago > 0 ? -ago : 6); p.endTime = p.startTime.addingTimeInterval(1800)
                    }
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
                        withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
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
            withAnimation(CircleMotion.page) { sharedState.navPosition = .bottom }
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
        // Memories (PrayerMemories.swift), from the ☰ menu or the day page's link: pushed, so it swipes back (decision
        // swipe-back-pages A).
        .navigationDestination(isPresented: Binding(get: { MemoriesPresenter.shared.open },
                                                    set: { MemoriesPresenter.shared.open = $0 })) { MemoriesPage() }
        .onChange(of: chosenMantra) {_, newMantra in
            if let text = newMantra {
                sharedState.titleForSession = text
                sharedState.mantraForSession = chosenMantraObject
            }
        }
        .whatsNewReturnPill()   // after What's new → "Open in shukr" to a pager page
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
        .sheet(isPresented: $demoScheduled) { NavigationStack { YourRemindersView() } }
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
        @EnvironmentObject var viewModel: PrayerViewModel
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
        @AppStorage(SalahSheetDrag.speedKey) private var sheetSpeed = SalahSheetDrag.defaultSpeed
        /// The following sheet's measurements: the circle's and the list's sizes, and the resting places worked out
        /// from them (SheetRests). Not per-frame.
        @State private var circleSize: CGSize = .zero
        @State private var listSize: CGSize = .zero
        @State private var rests = SheetRests()
        @State private var restsReady = false
        /// The sheet's UIScrollView: every move by code goes through it (no `.scrollPosition` binding — its write-back at
        /// the end of a touch cut off whatever scroll was started at the let-go; round 3).
        @State private var sheetScroll = SheetScrollHandle()

        var body: some View {
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
        private var poppingBody: some View {
            let lost = CircleStage.shared.lost
            return VStack {
                Spacer()
                if showBottom {
                    Spacer()
                    Spacer()
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

                Spacer()

                if showBottom {
                    Spacer()
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
                    Spacer()
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
                Spacer()
                circle
                    .padding(.top, lost.map { $0.risen ? $0.titleHeight + 28 : 0 } ?? 0)
                    .padding(.bottom, lost.map { $0.risen ? 28 + $0.reasonsHeight : 0 } ?? 0)
                    .animation(lost.map { $0.risen ? CircleMotion.Lost.rise : CircleMotion.Lost.down }, value: lost?.risen)
                Spacer()
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
                VStack {
                    Spacer()
                    Color.clear.frame(width: circleSize.width, height: circleSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.closedCircleY, false))
                    Spacer()
                    Color.clear.frame(height: closedBottomReserve)
                }
                VStack {
                    Spacer(); Spacer(); Spacer()
                    Color.clear.frame(width: circleSize.width, height: circleSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.openCircleY, false))
                    Spacer(); Spacer()
                    Color.clear.frame(width: listSize.width, height: listSize.height)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(SalahSheetDrag.space)) }, action: measure(\.openListTop, true))
                    Spacer()
                    Color.clear.frame(height: bottomChromeHeight + theme.listFooterRoom)
                }
            }
            .hidden()
            .allowsHitTesting(false)
        }

        private var followingBody: some View {
            let lost = CircleStage.shared.lost
            return GeometryReader { geo in
                let height = geo.size.height
                // The list's run between the rests, and the finger's scroll for it (the run ÷ the speed).
                let run = max((height * SalahSheetDrag.travelShare).rounded(), 1)
                let travel = max((run / CGFloat(max(sheetSpeed, 0.5))).rounded(), 1)
                let dead = SalahSheetDrag.dead
                // The open rest moving (the fold, the list's rows changing) glides, after the first measure.
                let restMotion = restsReady ? RowMotion.resolved(rowMotionRaw)
                    .animation(springy: CircleMotion.movement(CircleMotion.spring, reduced: reduceMotion)) : nil
                ScrollView(.vertical) {
                    ZStack(alignment: .top) {
                        // The track: `travel` between the rests, and dead room past each (no rubber band at a rest).
                        Color.clear.frame(height: height + travel + 2 * dead)
                            .background(SheetScrollFinder(handle: sheetScroll))
                        if lost == nil {
                            // The list's layer, a page tall at the closed rest: held still past the rests (SheetWall).
                            BottomSharedView(showDailyAyahView: $showDailyAyahView)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { if listSize != $0 { listSize = $0 } }
                                .modifier(SheetListFade(live: live))
                                .opacity(CircleStage.shared.pageHidden ? 0 : 1)
                                .animation(CircleMotion.ease(CircleMotion.pageRevealDuration), value: CircleStage.shared.pageHidden)
                                .offset(y: rests.openListTop + run)
                                .animation(restMotion, value: rests.openListTop)
                                .frame(width: geo.size.width, height: height, alignment: .top)
                                .modifier(SheetWall(travel: travel, run: run, page: height))
                                .padding(.top, dead)
                        }
                        closedPage(lost: lost)
                            .frame(width: geo.size.width, height: height)
                            .modifier(SheetPin(travel: travel, page: height, delta: rests.openCircleY - rests.closedCircleY))
                            .animation(restMotion, value: rests.openCircleY - rests.closedCircleY)
                            .padding(.top, dead)
                    }
                }
                .scrollIndicators(.hidden)
                .modifier(SheetLock(live: live, lost: lost != nil))
                .onScrollGeometryChange(for: CGFloat.self) { g in g.contentOffset.y + g.contentInsets.top - dead } action: { old, new in
                    live.sheetOffset = new
                    if live.sheetPhase == .interacting { sheetScroll.sample(new) }
                    if live.sheetTravel != travel { live.sheetTravel = travel }
                    if live.sheetRun != run { live.sheetRun = run }
                    // Pulled down past the closed rest (dead room: nothing moves): the chevron's resisted nudge, as the
                    // pop's drag showed it.
                    let pull = live.sheetPhase == .interacting && new < 0 ? min(-new * 0.5, 20) : 0
                    if live.pull != pull { live.pull = pull }
                    let reach = live.sheetPhase == .interacting && new < 0 ? -new / SalahSheetDrag.refreshPull : 0
                    if live.refreshReach != reach { live.refreshReach = reach }
                    // The first layout (the scroll starts in the dead room): quietly onto the rest navPosition names.
                    if !sheetScroll.placed, live.sheetPhase == .idle {
                        let target: CGFloat = showBottom ? travel : 0
                        if abs(new - target) <= 0.5 { sheetScroll.placed = true } else {
                            DispatchQueue.main.async {
                                guard live.sheetPhase == .idle else { return }
                                sheetScroll.scroll(by: target - live.sheetOffset, animated: false)
                            }
                        }
                    }
                    // The tick: the finger taking the sheet across halfway, like the pager's page tick.
                    if live.sheetPhase == .interacting, (old < travel / 2) != (new < travel / 2) {
                        triggerSomeVibration(type: .light)
                    }
                }
                .onScrollPhaseChange { old, new, context in
                    live.sheetPhase = new
                    let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top - dead
                    if new == .interacting { sheetScroll.stop() }   // a finger takes it, mid-spring or not
                    if old == .interacting, new != .interacting {
                        // Pulled down past the closed rest and let go: the ☰ menu (owner; the refresh is in Settings).
                        if !showBottom, offset < -SalahSheetDrag.refreshPull, !TourRuntime.shared.active {
                            NotificationCenter.default.post(name: SalahSheetDrag.openMenu, object: nil)
                            triggerSomeVibration(type: .light)
                        }
                        if live.pull != 0 { withAnimation(CircleMotion.page) { live.pull = 0 } }
                        if live.refreshReach != 0 { live.refreshReach = 0 }
                        // The let-go: pick the rest from the finger's speed, then spring there starting at that speed
                        // (SheetScrollHandle.spring: no stop between the finger and the landing), and a new finger
                        // takes it at any frame.
                        let velocity = sheetScroll.releaseVelocity
                        let open = SheetRelease.open(at: offset, velocity: velocity, travel: travel)
                        live.sheetPick = open
                        if open != (offset > travel / 2) { triggerSomeVibration(type: .light) }
                        settle(open: open, velocity: velocity, travel: travel)
                        return
                    }
                    // Settled: the resting state, after the fact (the scroll's own layout pass: publish next turn).
                    guard new == .idle, !sheetScroll.springing else { return }
                    // Never left between the rests: whatever stopped it there goes on to where the let-go was going.
                    if offset > 0.5, offset < travel - 0.5 {
                        settle(open: live.sheetPick, velocity: 0, travel: travel)
                        return
                    }
                    noteResting(offset: offset, travel: travel)
                }
                .background { restGhosts }
                .coordinateSpace(.named(SalahSheetDrag.space))
                // Moved by code (the chevron, a widget, a demo, setup): the scroll goes there; the settle confirms it.
                .onChange(of: sharedState.navPosition) { _, _ in rest(travel: travel, dead: dead, animated: true) }
                .onChange(of: travel) { _, _ in rest(travel: travel, dead: dead, animated: false) }
                .onAppear { rest(travel: travel, dead: dead, animated: false) }
                .onChange(of: rests) { _, new in
                    guard !restsReady, new.openListTop > 0 else { return }
                    DispatchQueue.main.async { restsReady = true }
                }
            }
        }

        /// Springs the sheet to a rest from `velocity` (a let-go, or a stop between the rests); navPosition follows
        /// once it rests.
        private func settle(open: Bool, velocity: CGFloat, travel: CGFloat) {
            guard live.sheetPhase != .interacting else { return }
            sheetScroll.spring(by: (open ? travel : 0) - live.sheetOffset, velocity: velocity) {
                noteResting(offset: open ? travel : 0, travel: travel)
            }
        }

        /// The resting state, after the fact (published next turn: a scroll's layout pass doesn't reach every reader).
        private func noteResting(offset: CGFloat, travel: CGFloat) {
            let resting: SharedStateClass.ViewPosition = offset > travel / 2 ? .bottom : .main
            DispatchQueue.main.async {
                guard sharedState.navPosition != resting else { return }
                withAnimation(CircleMotion.page) { sharedState.navPosition = resting }
            }
        }

        /// Scrolls the sheet to the rest `navPosition` names, unless it's there or a finger has it.
        private func rest(travel: CGFloat, dead: CGFloat, animated: Bool) {
            guard live.sheetPhase == .idle || live.sheetPhase == .animating else { return }
            let target: CGFloat = showBottom ? travel : 0
            let quiet = SalahSheetDrag.takeQuiet()
            // A quiet place (the first appear: the scroll starts at 0, in the dead room) always goes; a move only if needed.
            guard !animated || abs(live.sheetOffset - target) > 0.5 else { return }
            // Not in its window yet (the first appear): the idle check in onScrollGeometryChange places it.
            sheetScroll.scroll(by: target - live.sheetOffset, animated: animated && !quiet && UIApplication.shared.applicationState == .active)
        }
    }

    /// The open sheet fades a little with the drag nudge. Its own modifier, so a drag re-renders only this, not the page
    /// and its circle (audit D, finding 7).
    private struct PullFade: ViewModifier {
        let live: PagerLiveState
        func body(content: Content) -> some View { content.opacity(1 - Double(live.pull / 90)) }
    }

    /// Top bar (menu + TopBar on Salah, "Zikr" title on Zikr) and the chevron / bottom bar,
    /// fixed over the pager. Reads `live` so it alone re-renders while scrolling or dragging.
    struct PagerChromeView: View {
        @Environment(SharedStateClass.self) var sharedState
        var live: PagerLiveState
        @ObservedObject private var access = WhatsNewAccess.shared
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
        @EnvironmentObject private var viewModel: PrayerViewModel
        #if DEBUG
        @State private var demoViewer = false
        #endif
        /// The pill's camera is open for this prayer (PrayerPhotos.swift).
        @State private var prayerPhoto: PrayerPhotoTarget?
        /// The pill's prayer, marked and still in its window: its camera section (owner: photos "any time in that window so
        /// long as its marked").
        private var pillPhotoTarget: PrayerPhotoTarget? {
            #if DEBUG
            // `-demoPostSalahOffer -demoPillPhoto`: the pill's camera without a marked prayer (the simulator's walk).
            if let name = live.postSalahNudge, ProcessInfo.processInfo.arguments.contains("-demoPillPhoto") {
                return PrayerPhotoTarget(key: PrayerPhotos.key(dayKey: PrayerDay.key(), name: name), title: "\(name) · 4:52 PM")
            }
            #endif
            guard let name = live.postSalahNudge,
                  let row = viewModel.todaysPrayers.first(where: { ($0.name == name || $0.displayName == name) && $0.isCompleted }),
                  Date() < row.endTime else { return nil }
            return PrayerPhotoTarget.forMarked(row)
        }

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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// How far a top-bar title travels as the pager moves between Salah and Zikr.
        static let titlePush: CGFloat = 150
        /// What follows the live scroll does it in `ChromeFollow` / `ChromeLeaves`: this body reads none of it, so it
        /// isn't re-run on every frame of a swipe (audit D, finding 7).
        private func follow(_ role: ChromeFollow.Role) -> ChromeFollow {
            ChromeFollow(live: live, role: role, sheetFollows: sheetFollows)
        }
        @AppStorage(SalahSheetDrag.key) private var sheetFollows = SalahSheetDrag.defaultOn

        var body: some View {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // The two titles push each other with the pager (owner, 2026-10-01): swiping to Zikr
                    // (the page on the left) brings "Zikr" in from the left and pushes the Salah title
                    // out to the right, following the finger; back again the other way. Only these
                    // offsets read the live scroll — the titles' own bodies don't.
                    ZStack(alignment: .top) {
                        TopBar()
                            #if DEBUG
                            .modifier(DemoTip(tip: SwipeToZikrTip(), on: TourHintDemo.tip == "zikr", edge: .top))
                            #endif
                            .modifier(follow(.salah(push: Self.titlePush)))
                        ZikrPageTitle()
                            .modifier(follow(.zikr(push: Self.titlePush)))
                    }

                    // Menu button: a native Menu instead of the hand-rolled drawer, which
                    // toggled shared state and re-rendered the whole home screen to animate.
                    HStack {
                        // The menu is a popover (a native Menu can't show the wordmark):
                        // "shukr" on top like the old sidebar, then the destinations.
                        ZStack {
                        // Zikr page, top left: History (the Zikr tab reorganisation; symbols only, 2026-10-01).
                        ZikrDoor(title: "History", symbol: "clock.arrow.circlepath") { showZikrHistory = true }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("historyDoor", $0) }
                            .modifier(follow(.zikr(push: 0)))
                            // Locked with the page (ZikrLock): faint and shut.
                            .opacity(ZikrLock.shared.locked ? 0.25 : 1)
                            .allowsHitTesting(!ZikrLock.shared.locked)

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
                                // The tour not yet taken to its end: a green dot (Tour.swift), under the compass's.
                                .overlay(alignment: .topTrailing) {
                                    ZStack { TourMenuBadge(); CompassMenuBadge() }.offset(x: 3, y: -1)
                                }
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
                                menuRow("Memories", "photo.stack") { MemoriesPresenter.shared.open = true }
                                menuRow("Daily Ayah", "book") { showDailyAyahPage = true }
                                menuRow("99 Names", "moon.stars") { showNamesPage = true }
                                CompassMenuRow {
                                    pendingMenuAction = { showCalibration = true }
                                    showMenu = false
                                }
                                // Until the tour is taken to its end (Tour.swift).
                                TourMenuRow {
                                    pendingMenuAction = { NotificationCenter.default.post(name: TourRuntime.start, object: nil) }
                                    showMenu = false
                                }
                                // The Zikr Tour, until it's taken to its end (ZikrTour.swift): its offer on the Zikr page.
                                ZikrTourMenuRow {
                                    pendingMenuAction = {
                                        sharedState.go(to: .zikr)
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .seconds(0.5))
                                            ZikrTour.shared.offer(inAppTour: false)
                                        }
                                    }
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
                            .stageCover("menu")
                        }
                        // A pull down on the Salah page opens it (SalahSheetDrag.openMenu).
                        .onReceive(NotificationCenter.default.publisher(for: SalahSheetDrag.openMenu)) { _ in
                            showMenu = true
                        }
                        .onChange(of: showMenu) { _, open in
                            // The chosen row runs once the popover has faded (its push isn't attempted while the
                            // presentation is still going). Not at its onDisappear: that comes ~0.4 s after it's gone
                            // from the screen, and the row felt slow (sim, tr-pager).
                            guard !open, let action = pendingMenuAction else { return }
                            pendingMenuAction = nil
                            Task {
                                try? await Task.sleep(for: .seconds(CircleMotion.popoverAwayDuration))
                                action()
                            }
                        }
                        .sheet(isPresented: $showWhatsNew) { WhatsNewView().stageCover("whatsNew") }
                        .fullScreenCover(isPresented: $showCalibration) {
                            CompassCalibrationSheet().stageCover("compassCalibration")
                        }
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
                        .modifier(follow(.salah(push: 0)))
                        }
                        Spacer()
                        ZStack(alignment: .trailing) {   // the Azkar door keeps its place beside the Play / palette pair
                        // Zikr page, top right: Azkar (Your tasks is "N of M tasks done" under the wheel).
                        // Skip tour takes this corner while the tour runs (Tour.swift's TourSkipButton).
                        ZikrDoor(title: "Azkar", symbol: "books.vertical") { showMantrasPage = true }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("azkarDoor", $0) }
                            .modifier(follow(.zikr(push: 0)))
                            .opacity(TourRuntime.shared.active && !TourRuntime.showsAzkarDoor ? 0 : ZikrLock.shared.locked ? 0.25 : 1)
                            // The Zikr Tour's Azkar step opens it (its guard lets only that through); shut while locked.
                            .allowsHitTesting((!TourRuntime.shared.active || ZikrTour.shared.step == .azkar) && !ZikrLock.shared.locked)
                        // Salah page, top right, owner only: the look prototype's switcher (SalahLook.swift).
                        if access.available && !TourRuntime.shared.active {
                            HStack(spacing: 0) {
                                SalahPlayButton()
                                SalahLookSwitcher()
                            }
                            .padding(.trailing, 8)
                            .modifier(follow(.salah(push: 0)))
                        }
                        }
                    }
                }

                Spacer()

                ZStack(alignment: .bottom) {
                    // Chevron hint: Salah page, sheet closed. Follows the pull-to-refresh nudge.
                    Button {
                        sharedState.navPosition = showBottom ? .main : .bottom   // the page and the chrome animate it
                    } label: {
                        ChevronHint(live: live)
                    }
                    .modifier(follow(.chevron(sheetOpen: showBottom)))

                    // Bottom bar: Salah with the sheet up, and always on Zikr. Above it, the soft looks' "N done"
                    // (SoftDoneFooter): a fixed spot, fading with the bar on Salah, not moving with the card.
                    VStack(spacing: 0) {
                        SoftDoneFooter()
                            .modifier(follow(.doneFooter(sheetOpen: showBottom)))
                        CustomBottomBar()
                            .modifier(follow(.bottomBar(sheetOpen: showBottom)))
                    }
                }
            }
            // Just prayed: the post-salah pill, always under the top bar — the same spot with the prayer
            // list open or closed, so it never travels across the page (owner, decision
            // post-salah-pill-place C). Chrome, above the pager: dragging it never moves a page.
            .overlay(alignment: .top) {
                if live.postSalahNudge != nil {
                    PostSalahNudgeOnPage(live: live, onPhoto: pillPhotoTarget.map { target in
                        { live.postSalahNudge = nil; prayerPhoto = target }
                    }) {
                        // The tour's pill came from a practice mark: it never opens a real, saved session (audit A1);
                        // ✕ closes it.
                        guard !TourRuntime.shared.active else { return }
                        live.postSalahNudge = nil
                        sharedState.isDoingPostNamazZikr = true
                        // In place (decision post-salah-entry A): the cover with no animation of its own, the session
                        // fading in over the Salah page — list open or closed, nothing measured. The sheet is left as it is.
                        // Refused (another session's cover still closing — Frank's review): the usual sheet, never a cover
                        // with neither a slide nor a fade.
                        if SessionHandoff.shared.openInPlace() {
                            var quiet = Transaction()
                            quiet.disablesAnimations = true
                            withTransaction(quiet) { showTasbeehPage = true }
                        } else {
                            showTasbeehPage = true
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .id(live.postSalahNudge)   // a new mark: a new pill, its 15 s from the start (audit A)
                }
            }
            // The pill's camera: a photo of the prayer just marked (PrayerPhotos.swift).
            .fullScreenCover(item: $prayerPhoto) { target in
                PrayerPhotoCapture(target: target) { prayerPhoto = nil }
            }
            #if DEBUG
            // `-demoPhotoViewer`: the newest saved prayer photo, full screen (the simulator's look at the viewer).
            .fullScreenCover(isPresented: $demoViewer) {
                if let key = PrayerPhotos.newestKey {
                    PrayerPhotoViewer(key: key) { demoViewer = false }.presentationBackground(.clear)
                }
            }
            .task {
                // `-demoMemories`: three weeks of stand-in photos; `-demoMemoriesOpen`: then Memories opens.
                if ProcessInfo.processInfo.arguments.contains("-demoMemories") { await PrayerPhotos.seedDemo() }
                if ProcessInfo.processInfo.arguments.contains("-heicSelfTest") { await PrayerPhotos.heicSelfTest() }
                if ProcessInfo.processInfo.arguments.contains("-demoMemoriesOpen") {
                    try? await Task.sleep(for: .seconds(2))
                    MemoriesPresenter.shared.open = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoPhotoViewer") {
                    try? await Task.sleep(for: .seconds(2))
                    demoViewer = PrayerPhotos.newestKey != nil
                }
            }
            #endif
            // The sheet popping (whoever changed it): the chevron, "N done" and the bar fade with the page's own move.
            .animation(CircleMotion.movement(CircleMotion.page, reduced: reduceMotion), value: showBottom)
            // The pill comes and goes the same way whoever sets it (rule 6); a flick and the timer fade it themselves
            // first, then remove it with no animation.
            .animation(CircleMotion.movement(.easeInOut(duration: CircleMotion.pillDuration), reduced: reduceMotion),
                       value: live.postSalahNudge)
            .ignoresSafeArea(edges: .bottom)
            .modifier(ChromeLeaves(live: live))
            // The opening on the Salah circle (circle step 4): the chrome waits, then fades in as the ring lands.
            .opacity(CircleStage.shared.pageHidden ? 0 : 1)
            .animation(CircleMotion.ease(CircleMotion.pageRevealDuration), value: CircleStage.shared.pageHidden)
        }
    }

    /// A piece of the chrome following the live scroll: its fade, its push and whether it takes taps. Only this
    /// re-renders per frame of a swipe (audit D, finding 7).
    struct ChromeFollow: ViewModifier {
        enum Role {
            /// The Salah page's chrome: gone toward Zikr, pushed right by `push`.
            case salah(push: CGFloat)
            /// The Zikr page's chrome: in from the left by `push`.
            case zikr(push: CGFloat)
            /// The chevron: Salah with the sheet closed.
            case chevron(sheetOpen: Bool)
            /// The soft looks' "N done": Salah with the sheet open.
            case doneFooter(sheetOpen: Bool)
            /// The bottom bar: Salah with the sheet open, and always on Zikr.
            case bottomBar(sheetOpen: Bool)
        }
        let live: PagerLiveState
        let role: Role
        /// The Salah sheet follows the finger (SalahSheetDrag): the sheet's pieces follow its live progress instead of
        /// its resting state.
        var sheetFollows = false

        /// How open the sheet is, 0...1: live when it follows the finger, else the resting state.
        private func sheet(_ open: Bool) -> CGFloat { sheetFollows ? live.sheetProgress : (open ? 1 : 0) }

        func body(content: Content) -> some View {
            /// How far onto the Zikr page we are, 0...1, live from the scroll offset.
            let zikr = min(max(1 - live.scrollProgress, 0), 1)
            let (opacity, push, taps): (CGFloat, CGFloat, Bool) = switch role {
            case .salah(let push): (1 - zikr, zikr * push, zikr < 0.5)
            case .zikr(let push): (zikr, -(1 - zikr) * push, zikr > 0.5)
            case .chevron(let open): ((1 - sheet(open)) * (1 - zikr), 0, sheet(open) < 0.5 && zikr < 0.5)
            case .doneFooter(let open): (sheet(open) * (1 - zikr), 0, sheet(open) >= 0.5 && zikr < 0.5)
            case .bottomBar(let open): (max(sheet(open), zikr), 0, sheet(open) >= 0.5 || zikr > 0.5)
            }
            // "N done" rides up under the list while a finger brings the sheet (its fixed spot is the open rest).
            let rise: CGFloat = if case .doneFooter = role, sheetFollows {
                (1 - live.sheetProgress) * live.sheetRun
            } else { 0 }
            content
                .offset(x: push, y: rise)
                .opacity(Double(opacity))
                .allowsHitTesting(taps)
        }
    }

    /// Toward Settings the chrome leaves WITH the Salah page, so Settings slides over empty space instead of under a
    /// fading top bar (owner, 2026-09-25); it takes no taps past halfway.
    private struct ChromeLeaves: ViewModifier {
        let live: PagerLiveState
        func body(content: Content) -> some View {
            let settings = min(max(live.scrollProgress - 1, 0), 1)
            content
                .allowsHitTesting(settings < 0.5)
                .visualEffect { content, proxy in content.offset(x: -settings * proxy.size.width) }
        }
    }

    /// The chevron hint, nudged by the pull-down drag; while the closed page is pulled down it gives way to a small quiet
    /// line, "Keep pulling for the menu", then "Let go for the menu" (the pull opens ☰ now — owner; it used to refresh).
    private struct ChevronHint: View {
        let live: PagerLiveState
        var body: some View {
            let pulling = live.refreshReach > 0.15
            Image(systemName: "chevron.up")
                .font(.title3)
                .foregroundStyle(TourHints.shared.chevronLine != nil ? Color.secondary
                                 : live.pull != 0 ? Color.secondary : Color(.secondarySystemFill))
                // The tour's words just above the chevron (Tour.swift).
                .overlay(alignment: .bottom) {
                    if let line = TourHints.shared.chevronLine {
                        Text(line).font(.footnote).fontDesign(.rounded).fontWeight(.light)
                            .foregroundStyle(Color(.secondaryLabel)).fixedSize()
                            .offset(y: -30)
                    }
                }
                // The tour's "Swipe up" step points at it.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("chevron", $0) }
                .opacity(pulling ? 0 : 1)
                // An overlay, so the chevron's place is exactly as it was.
                .overlay {
                    Text(live.refreshReach >= 1 ? "Let go for the menu" : "Keep pulling for the menu")
                        .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                        .foregroundStyle(Color(.tertiaryLabel))   // explicit: in the Button's label .tertiary took the tint
                        .fixedSize()
                        .contentTransition(.opacity)
                        .opacity(pulling ? 1 : 0)
                }
            .animation(.easeOut(duration: CircleMotion.quick), value: pulling)
            .animation(.easeOut(duration: CircleMotion.quick), value: live.refreshReach >= 1)
            .padding(.bottom, 30)
            .padding()
            .offset(y: live.pull)
        }
    }

    /// The post-salah pill under the top bar, on the Salah page only.
    private struct PostSalahNudgeOnPage: View {
        let live: PagerLiveState
        var onPhoto: (() -> Void)? = nil
        let onOpen: () -> Void
        var body: some View {
            let zikr = min(max(1 - live.scrollProgress, 0), 1)
            let settings = min(max(live.scrollProgress - 1, 0), 1)
            PostSalahNudge(onOpen: { TourRuntime.shared.event(.pillOpened); onOpen() },
                           onDismiss: {
                               live.postSalahNudge = nil   // the pill animates (or not) itself
                               TourRuntime.shared.event(.pillClosed)   // ✕ or a flick: the tour's to-do (never its expiry)
                           },
                           onPhoto: TourRuntime.shared.active ? nil : onPhoto,
                           shown: zikr < 0.5 && settings < 0.5)
                // The tour's post-salah step points at it, and ends when it goes (Tour.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("pill", $0) }
                .onAppear { TourRuntime.shared.pillVisible = true }
                .onDisappear { TourRuntime.shared.pillVisible = false }
                .padding(.top, 64)
                .opacity(Double(1 - zikr))
                .allowsHitTesting(zikr < 0.5)
        }
    }

    /// The Zikr page's title in the fixed top bar, in TopBar's type (owner, 2026-10-01). It follows the
    /// wheel: a centred task shows its streak ("8 Day Streak", "0 Day Streak" when there's none yet);
    /// freestyle and New task show "Zikr". Each item's label is pushed in the wheel's direction — moving
    /// down, the next one comes up from below and the last goes up and out; moving up, the other way.
    /// A tap on a task's streak toggles "Best N Days" (back to the streak on the next tap or item).
    /// Outline beads; the flame is an outline in grey until today's goal is met, then filled sage.
    struct ZikrPageTitle: View {
        @Query private var tasks: [TaskModel]
        @State private var showBest = false
        private let focus = ZikrWheelFocus.shared
        private static let travel: CGFloat = 12
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // The tour's example tasks too (TourExamples): their streaks show like any task's.
            let task = focus.taskID.flatMap { id in (TourExamples.shared.tasks ?? tasks).first { $0.id == id } }
            let down = focus.movedDown
            // Same metrics as TopBar's location row so the title sits where the city does.
            ZStack {
                // Reduce Motion: the labels fade in place.
                let travel = reduceMotion ? 0 : Self.travel
                label(task)
                    .id(focus.key)
                    .transition(.asymmetric(
                        insertion: .offset(y: down ? travel : -travel).combined(with: .opacity),
                        removal: .offset(y: down ? -travel : travel).combined(with: .opacity)))
            }
            .padding()
            .frame(height: 24, alignment: .center)
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .animation(CircleMotion.label, value: focus.key)
            .onChange(of: focus.key) { _, _ in showBest = false }
            .padding()
        }

        @ViewBuilder private func label(_ task: TaskModel?) -> some View {
            if let task {
                let streak = task.streak()
                HStack(alignment: .center) {
                    Image(systemName: streak.keptToday && streak.current > 0 ? "flame.fill" : "flame")
                        .foregroundColor(streak.keptToday && streak.current > 0 ? Color.sage : .secondary)
                    Group {
                        if showBest {
                            Text("Best \(streak.best) Days").transition(.blurReplace)
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
    /// The Salah sheet's list (the old Salah | Zikr tab under the circle is gone: the Zikr page has its own wheel).
    struct BottomSharedView: View {
        @Binding var showDailyAyahView: Bool

        var body: some View {
            VStack {
                TodaysPrayerListView(showDailyAyahView: $showDailyAyahView)
                    // The card is a fixed width: at the accessibility text sizes a name filled a row, its time wrapped
                    // a character a line or was cut to "7:…", "3 done" broke in two (Frank's largest-text pass). The
                    // list stops growing at the largest standard size, as the circle's words do.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .modifier(SalahLookListFrame())   // the look prototype; today's = 260 pt in FlatBorder
            }
        }
    }

    
    struct CustomBottomBar: View {
        @Environment(SharedStateClass.self) var sharedState
        @Environment(\.circleTheme) private var theme

        var body: some View {
            VStack(spacing: 0){

                    // One surface on every page: the bar wears the theme. It leaves with the Salah page toward Settings
                    // (ChromeLeaves), so a Settings look only ever showed mid-swipe — the bar turned white at the page's
                    // midpoint (bottom-bar-colour, owner: "looks careless").
                    ThemedBarDivider()

                    
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
                            sharedState.horizontalPage = .main   // the pager scrolls itself, like its siblings
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
                            // The tour's last step taps this (audit J: the bar is taught as well as the swipe).
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("settingsTab", $0) }
                        }
                    }
                    .padding(.top, 15)
                    .padding(.bottom, 25)
                    .padding(.horizontal, 45)
                    .opacity(0.8)
//                    .background(Color("bgColor"))
                
            }
            .background(theme.backdrop)
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
            .environment(sharedState)
    }
}

// MARK: - Prayer List

struct TodaysPrayerListView: View {

    @EnvironmentObject var viewModel: PrayerViewModel
    @Binding var showDailyAyahView: Bool
    @Environment(\.circleTheme) private var theme
    /// Pills stand apart; the other looks keep their rows close with dividers.
    private var spacing: CGFloat { theme.rowSpacing }
    private var showsDividers: Bool { theme.showsRowDividers }
    @AppStorage(RowMotion.key) private var motionRaw = RowMotion.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: RowMotion { RowMotion.resolved(motionRaw) }

    /// Done prayers fold out of the list so it only shows what's left; all five come back once
    /// the day is complete. A prayer just marked stays while the circle's marking moment runs (the stage's `heldRow`:
    /// one clock, the moment's).
    private var lingering: Set<String> { CircleStage.shared.heldRow.map { [$0] } ?? [] }
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
        VStack(spacing: 0) {
            if !(outside && visible.isEmpty) {
                VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                ForEach(Array(visible.enumerated()), id: \.element) { index, prayerName in
                    VStack(spacing: 0) {
                        PrayerButton(
                            name: prayerName,
                            viewModel: viewModel
                        )
                        .padding(.bottom, index == visible.count - 1 ? 0 : spacing)

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
                .padding(.horizontal)
                .padding(.vertical, 12)
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
        // A marked row folds when the circle's moment releases it.
        .animation(motion.animation(springy: CircleMotion.rowFold).map { CircleMotion.movement($0, reduced: reduceMotion) },
                   value: CircleStage.shared.heldRow)
        .onChange(of: allDone) { _, isDone in
            if isDone { showDone = false }   // the day's complete: everything's back anyway
        }
        // The list closed: folded again next time, as when this was the list's own @State (shared now with the soft
        // looks' footer; it stayed open until a relaunch — Sami's audit).
        .onDisappear { showDone = false }
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
    /// The row's dot answering a mark.
    private static let dotPress = Animation.spring(response: 0.1, dampingFraction: 0.7)
    /// An unmark from the row's alert: the page settles back (score → prayer, the list's rows) in one ease.
    private static let unmarkFade = Animation.easeInOut(duration: 0.4)
    @Environment(SharedStateClass.self) var sharedState
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0


    
    @State private var toggledText: Bool = false
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
    @State private var isMarkingIncomplete = false // Track if we are marking incomplete
    @State private var showTimePicker = false
    @State private var selectedEditTimeDate = Date()
    @State private var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var searchQuery = ""
    
    private func handlePrayerButtonPress() {
        // Only allow pressing on Future Prayers
        if !isFuturePrayer {
            // The tour lets only its own moves through (Ben's G1 / G2): a light no otherwise.
            guard TourRuntime.shared.allows(marking: !prayerObject.isCompleted, prayerObject) else {
                TourRuntime.shared.nudge()   // the tour: the thing to touch pulses (no buzz — owner)
                return
            }
            if !prayerObject.isCompleted {
                viewModel.togglePrayerCompletion(for: prayerObject)   // the post-salah pill follows (.prayerCompleted)
                TourRuntime.shared.event(.marked(prayerObject, viewModel))   // the tour's Mark step / a first mark
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
    
    private var look: SalahLook { theme.list }
    /// On now: started, not marked, not over.
    private var isCurrentPrayer: Bool { !isFuturePrayer && !prayerObject.isCompleted && prayerObject.endTime > Date() }

    /// The row's surface for the Salah look (SalahLook.swift). Pills: upcoming and missed ones raised, the
    /// current one pressed in, done ones flat on the page (their dot carries the score). Quiet: only the
    /// current one pressed in. Card / well: the rows sit on the card. Today's: the old plain fill.
    @ViewBuilder private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        case .card, .well:
            Color.clear
        }
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

    /// "On time · 88" (PrayerScoring).
    /// The start time as shown: the tour's practice clock moves a practice row's (PracticeClock).
    private var shownStart: Date { PracticeClock.shown(calcStartTime, of: prayerObject) }

    private var completedTimeAndScore: String {
        prayerObject.scoreSummary ?? "Missed"
    }

    /// A tap on the time: flip its text (a started prayer's time doesn't flip). A Jumu'ah shows its masjid instead.
    private func timeTap() {
        guard isFuturePrayer || prayerObject.isCompleted else { return }
        TourTargets.shared.lastTappedRow = prayerObject.name   // its change glows (the tour)
        TourRuntime.shared.event(prayerObject.isCompleted ? .markedRowTapped : .comingRowTapped)   // the tour's list card
        if prayerObject.isJumuah && prayerObject.isCompleted {
            showMasjidLine(!masjidLine)
            return
        }
        withAnimation { toggledText.toggle() }   // ExternalToggleText flips (and flips back after 3 s)
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
        // In the tour only the fix step's Fajr opens (a light no otherwise, as for a mark the tour doesn't want).
        guard TourRuntime.shared.allowsEditing(prayerObject) else {
            TourRuntime.shared.nudge()   // the tour: not yet / not this one — a pulse, no buzz
            return
        }
        // Open on the prayer's own day. The wheel only edits hour/minute and keeps the date it
        // starts with: starting from a tap after midnight (rollover) put every picked time on the
        // next day — always Qaza.
        let marked = prayerObject.timeAtComplete ?? Date()
        selectedEditTimeDate = min(max(marked, editTimeRange.lowerBound), editTimeRange.upperBound)
        showTimePicker = true
        TourRuntime.shared.event(.editorOpened(prayerObject.name))   // the tour's "change the time or place" step
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
                Text(prayerObject.displayName)   // "Jumu'ah" when Friday's Dhuhr was at a masjid
                    // Never squeezed by a long time column (it broke a letter a line and the row grew tall).
                    .fixedSize()
                    .layoutPriority(1)
                    .font(.callout) //.callout
                    // Today's look: exactly the old Color.secondary (the hierarchical .secondary differed a hair).
                    .foregroundStyle(theme.emphasisesCurrentRow && isCurrentPrayer ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(statusBasedOpacity))) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
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
                } else {
                    timeColumn
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
            .contentShape(Rectangle())
            .coordinateSpace(.named(PrayerButton.rowSpace))
            .gesture(rowGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: prayerObject.isCompleted ? "Mark not prayed" : "Mark prayed") { markTap() }
            // Background Effects Container
            .background { rowBackground }
            .animation(Self.dotPress, value: prayerObject.isCompleted)
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
                                isMarkingIncomplete = true
                                // A 0.1 s spring snapped the whole page (score → prayer, the list 5 rows → 1); an
                                // ease lets it settle (Sami's audit, finding 7; his verified fix).
                                withAnimation(Self.unmarkFade) {
                                    viewModel.togglePrayerCompletion(for: prayerObject)
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    }
            .sheet(isPresented: $showTimePicker) {
                PrayerTimeEditSheet(prayer: prayerObject, time: $selectedEditTimeDate, range: editTimeRange,
                                    onCancel: { showTimePicker = false },
                                    onSave: { date, spot in
                                        // A user edit: the recorded time / spot are kept (revertible).
                                        let old = prayerObject.timeAtComplete ?? .distantPast
                                        if abs(date.timeIntervalSince(old)) >= 30 { viewModel.editPrayerTime(prayerObject, to: date) }
                                        if let spot { viewModel.movePrayer(prayerObject, to: spot) }
                                        TourRuntime.shared.event(.editorSaved(prayerObject.name))   // the tour's fix step
                                        showTimePicker = false
                                    })
                // Closed by a widget open: like Cancel (the sheet keeps its edits in a local draft).
                .stageCover("timeEdit.\(prayerObject.name)")
            }
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

                } else if prayerObject.isCompleted && prayerObject.isJumuah {
                    // A Jumu'ah: its time stays; a tap opens the masjid's line under the name (showMasjidLine).
                    Text(shortTimePM(shownStart))
                        .font(timeFontSize)
                        .foregroundColor(.secondary.opacity(statusBasedOpacity))
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                } else if prayerObject.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if prayerObject.timeAtComplete != nil {
                        ExternalToggleText(
                            originalText: shortTimePM(shownStart),
                            toggledText: completedTimeAndScore,
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
                } else {
                    // Current Prayer: Show Start Time
                    Text(shortTimePM(shownStart))
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
}


/// Behind the pager: one panel per page (Zikr, Salah plain; Settings grouped-gray in light mode)
/// offset by the live scroll position, so each page's colour — status-bar strip included —
/// moves with its page. Its own view so only it re-renders per scroll frame.
struct PagerBackdrop: View {
    let live: PagerLiveState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.circleTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                // Zikr and Salah: the theme's page, status-bar strip included.
                theme.backdrop.frame(width: width)
                theme.backdrop.frame(width: width)
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
        // The tour holds the page too: only its swipe step pages (audit E17).
        content.scrollDisabled(live.pagerLocked || live.sheetPhase == .interacting || live.sheetPhase == .decelerating
                               || TourRuntime.shared.locksPager)
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
