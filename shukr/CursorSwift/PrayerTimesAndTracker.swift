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
    @State private var showChainZikrButton: Bool = false
    @State private var settingsViewNavBool: Bool = false
    @State private var showTasbeehPage: Bool = false
    @State private var showQiblaMap: Bool = false
    @State private var dismissChainZikrItem: DispatchWorkItem? // Manage the dismissal timer

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
    @State private var showInsightsPage = false
    @State private var showOldInsights = false
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
    // Axis lock: `minimumDistance: 0` and the axis is decided after 6 pt of movement, before
    // the pager's own pan reaches its 10 pt slop. Vertical → `live.pagerLocked` (the pager is
    // `.scrollDisabled` while it's set) so sideways drift during a vertical drag can never
    // turn into a page swipe; horizontal → this gesture stays out of it. Cleared on release.
    private var abstractedDragGesture: _EndedGesture<_ChangedGesture<DragGesture>> {
        let resistanceFactor = 0.5
        let maxOffset: CGFloat = 20
        let threshold: CGFloat = 30
        let decideAt: CGFloat = 6

        return DragGesture(minimumDistance: 0, coordinateSpace: .global)
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
            // The status-bar strip. Pages are clipped to the pager, which starts below the top
            // safe area, so no page can paint up there; this layer wears the current page's
            // color instead (Settings is grouped-gray in light mode, everything else plain).
            Color(sharedState.horizontalPage == .settings && colorScheme == .light
                  ? .secondarySystemBackground : .systemBackground)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.15), value: sharedState.horizontalPage)

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
                showInsightsPage: $showInsightsPage, showOldInsights: $showOldInsights
            )
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .active {

                viewModel.loadTodaysPrayerObjects()
                viewModel.reconcileAfterWidgetWrites() // prayers completed from the widget while we were closed
                
                if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
                    let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
                    let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
                    // Clear only when set: every write to the group suite invalidates every
                    // @AppStorage bound to it and re-renders Settings.
                    if openCompassFromWidget { store.setValue(false, forKey: "widgetCompass") }
                    if openTasbeehFromWidget { store.setValue(false, forKey: "widgetTasbeeh") }

                    if openCompassFromWidget{
                        sharedState.navPosition = .main
                        showQiblaMap = true
                    }
                    
                    else if openTasbeehFromWidget{
                        sharedState.horizontalPage = .zikr
                    }
                }
                

            }
        }
        #if DEBUG
        .task {
            // Simulator check of the completion moment: launch with -demoPrayerCompletion. Uses
            // the dev "test prayer times" (minutes around now), opens the salah sheet, then
            // marks the current prayer and a missed one.
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
            if ProcessInfo.processInfo.arguments.contains("-demoInsights") {
                try? await Task.sleep(for: .seconds(1))
                showInsightsPage = true
                return
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
            LocationMapContentView().onDisappear { sharedState.allowQiblaHaptics = true }
        }
        .navigationDestination(isPresented: $showDailyAyahPage) { DailyAyahView() }
        .navigationDestination(isPresented: $showMantrasPage) { MantrasView() }
        .navigationDestination(isPresented: $showSalahHistoryV1) { SimpleDailyScoreView() }
        .navigationDestination(isPresented: $showSalahHistoryV2) { PrayerEditorView() }
        .navigationDestination(isPresented: $showZikrHistory) { HistoryPageView() }
        .navigationDestination(isPresented: $showInsightsPage) { InsightsView() }
        .navigationDestination(isPresented: $showOldInsights) { InsightsView(layout: .old) }
        .onChange(of: chosenMantra) {_, newMantra in
            if let text = newMantra {
                sharedState.titleForSession = text
                sharedState.mantraForSession = chosenMantraObject
            }
        }
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
                .onAppear{
                    print("showNewPage (from tabview): \(showTasbeehPage)")
                    sharedState.allowQiblaHaptics = false
                }
                .onDisappear{
                    sharedState.allowQiblaHaptics = true
                }
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
                showQiblaMap: $showQiblaMap, showChainZikrButton: $showChainZikrButton,
                showTasbeehPage: $showTasbeehPage, dismissChainZikrItem: $dismissChainZikrItem,
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
        @Binding var showChainZikrButton: Bool
        @Binding var showTasbeehPage: Bool
        @Binding var dismissChainZikrItem: DispatchWorkItem?
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
                    MainCircleView(showQiblaMap: $showQiblaMap, showChainZikrButton: $showChainZikrButton, showTasbeehPage: $showTasbeehPage)
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
                        showChainZikrButton: $showChainZikrButton,
                        dismissChainZikrItem: $dismissChainZikrItem,
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
            .overlay(alignment: .top) {
                // Post-salah chain-zikr prompt; floats near the top of this page only.
                FloatingChainZikrButton(showTasbeehPage: $showTasbeehPage, showChainZikrButton: $showChainZikrButton)
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

        @State private var showMenu = false
        @State private var pendingMenuAction: (() -> Void)? = nil

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
        private var settingsness: CGFloat { min(max(live.scrollProgress - 1, 0), 1) }
        /// Sheet open-progress on the Salah page, 0...1.
        private var sheetP: CGFloat { showBottom ? 1 : 0 }

        var body: some View {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Group {
                        if sharedState.horizontalPage == .zikr {
                            ZikrPageTitle()
                        } else {
                            TopBar()
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: sharedState.horizontalPage)

                    // Menu button: a native Menu instead of the hand-rolled drawer, which
                    // toggled shared state and re-rendered the whole home screen to animate.
                    HStack {
                        // The menu is a popover (a native Menu can't show the wordmark):
                        // "shukr" on top like the old sidebar, then the destinations.
                        Button { showMenu = true } label: {
                            Image(systemName: "line.3.horizontal")
                                .background(.white.opacity(0.01))
                                .frame(width: 24, height: 24)
                                .font(.system(size: 20))
                                .fontWeight(.light)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray.opacity(0.8))
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
                                menuRow("Mantras", "text.quote") { showMantrasPage = true }
                                menuRow("Zikr History", "clock.arrow.circlepath") { showZikrHistory = true }
                                #if DEBUG
                                Divider()
                                menuRow("Salah History (V1)", "hammer") { showSalahHistoryV1 = true }
                                menuRow("Salah History (V2)", "hammer") { showSalahHistoryV2 = true }
                                menuRow("Test Streak Celebration", "heart") {
                                    // Fake values (streak 11 → 12, on time 4 → 5); the real ones are untouched.
                                    NotificationCenter.default.post(name: .prayerStreakContinued, object: 12)
                                    NotificationCenter.default.post(name: .onTimeStreakContinued, object: 5)
                                }
                                menuRow("Old Insights", "chart.bar.xaxis") { showOldInsights = true }
                                menuRow("Test Perfect Day", "sparkles") {
                                    NotificationCenter.default.post(name: .perfectDay, object: true)   // true = demo
                                }
                                #endif
                            }
                            .padding(.bottom, 8)
                            .frame(width: 250)
                            .presentationCompactAdaptation(.popover)
                        }
                        .onChange(of: showMenu) { _, open in
                            // Run the chosen action once the popover is away, so the push isn't
                            // attempted while a presentation is still dismissing.
                            guard !open, let action = pendingMenuAction else { return }
                            pendingMenuAction = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
                        }
                        Spacer()
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
                    .opacity(Double((1 - sheetP) * (1 - zikrness)))
                    .allowsHitTesting(sheetP < 0.5 && zikrness < 0.5)

                    // Bottom bar: Salah with the sheet up, and always on Zikr.
                    CustomBottomBar()
                        .opacity(Double(max(sheetP, zikrness)))
                        .allowsHitTesting(max(sheetP, zikrness) > 0.5)
                }
            }
            .opacity(Double(1 - settingsness))
            .allowsHitTesting(settingsness < 0.5)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The Zikr page's title in the fixed top bar, styled like TopBar's location label.
    struct ZikrPageTitle: View {
        var body: some View {
            // Same metrics as TopBar's location row so the title sits where the city does.
            HStack {
                Image(systemName: "circle.hexagonpath")
                    .foregroundColor(.secondary)
                Text("Zikr")
            }
            .padding()
            .frame(height: 24, alignment: .center)
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .padding()
        }
    }
    struct BottomSharedView: View {
        @EnvironmentObject var sharedState: SharedStateClass
        
        // Bindings coming from the parent view
        @Binding var showChainZikrButton: Bool
        @Binding var dismissChainZikrItem: DispatchWorkItem?
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
                        showChainZikrButton: $showChainZikrButton,
                        dismissChainZikrItem: $dismissChainZikrItem,
                        showDailyAyahView: $showDailyAyahView
                    )
                    
                    
                    /*
                    InfiniteDaysScrollView(selectedDate: $selectedDate)
                        .frame(height: 30)
                        .frame(width: 260) // Same width as PrayerListView
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    SomedaysPrayerListView(
                        showChainZikrButton: $showChainZikrButton,
                        dismissChainZikrItem: $dismissChainZikrItem,
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
    @Binding var showChainZikrButton: Bool
    @Binding var dismissChainZikrItem: DispatchWorkItem?
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
    /// When the perfect-day cascade starts after the notification (rows are back by then).
    static let perfectDayCascadeStart: Double = 1.5

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
                            showChainZikrButton: $showChainZikrButton, dismissChainZikrItem: $dismissChainZikrItem,
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

                // The folded ones, as one quiet line.
                if (foldedCount > 0 || showDone) && !allDone {
                    Button {
                        triggerSomeVibration(type: .light)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showDone.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showDone ? "chevron.up" : "checkmark.circle")
                            Text(showDone ? "hide done" : "\(done.count) done")
                        }
                        .font(.caption)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, visible.isEmpty ? 0 : 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            lingering.insert(event.name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    _ = lingering.remove(event.name)
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
    @Binding var showChainZikrButton: Bool
    @Binding var dismissChainZikrItem: DispatchWorkItem?
    @Binding var showDailyAyahView: Bool
    let selectedDate: Date
    let spacing: CGFloat = 6
    
    var body: some View {
        VStack{
            VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
                    PrayerButton(forDate: selectedDate, name: prayerName, viewModel: viewModel,
                        showChainZikrButton: $showChainZikrButton, dismissChainZikrItem: $dismissChainZikrItem)
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

// MARK: - Prayer Button


import MapKit
struct PrayerButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0


    @Binding var showChainZikrButton: Bool
    @Binding var dismissChainZikrItem: DispatchWorkItem? // Manage the dismissal timer
    
    @State private var toggledText: Bool = false
    /// Bumps when this prayer is marked done, popping the dot (CompletionDotPop).
    @State private var completionPulse = 0
    @State private var showMarkIncompleteAlert = false // State for showing alert
    @State private var isMarkingIncomplete = false // Track if we are marking incomplete
    @State private var showTimePicker = false
    @State private var selectedEditTimeDate = Date()
    @State private var selectedLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var searchQuery = ""
    @State private var timer: Timer?
    
    private func handlePrayerButtonPress() {
        // Only allow pressing on Future Prayers
        if !isFuturePrayer {
            if !prayerObject.isCompleted {
                viewModel.togglePrayerCompletion(for: prayerObject)
                showTemporaryMessage(workItem: &dismissChainZikrItem, boolToShow: $showChainZikrButton, delay: 5)
            }
            else {
                showMarkIncompleteAlert = true
            }
        }
    }
    
    let prayerObject: PrayerModel
    let name: String
        
    init(showChainZikrButton: Binding<Bool>, dismissChainZikrItem: Binding<DispatchWorkItem?>, name: String, viewModel: PrayerViewModel) {
        guard let foundPrayer = viewModel.todaysPrayers.first(where: { $0.name == name }) else {
            fatalError("PrayerModel not found for name: \(name)")
        }
        self._showChainZikrButton = showChainZikrButton
        self._dismissChainZikrItem = dismissChainZikrItem
        self.prayerObject = foundPrayer
        self.name = name
    }
  
    // added this so we can get the prayerList for another date other than today.
    init(forDate: Date, name: String, viewModel: PrayerViewModel, showChainZikrButton: Binding<Bool>, dismissChainZikrItem: Binding<DispatchWorkItem?>) {
        let updatingToday = Calendar.current.isDate(forDate, inSameDayAs: Date())
        let objectsToCheck: [PrayerModel] = updatingToday ? viewModel.todaysPrayers : viewModel.loadPrayerObjects(for: forDate)

        self._showChainZikrButton = showChainZikrButton
        self._dismissChainZikrItem = dismissChainZikrItem
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

    /// "On time · 88" (PrayerScoring).
    private var completedTimeAndScore: String {
        prayerObject.numberScore.map(PrayerScoring.summary(for:)) ?? "Missed"
    }
    
    
    var body: some View {
            HStack {
                // Status Circle
//                Button(action: {
//                    handlePrayerButtonPress()
//                }) {
//                    Image(systemName: statusImageName)
//                        .foregroundColor(grayCircleStyle)
//                        .frame(width: 24, height: 24, alignment: .leading)
//                        .overlay{
//                            Image(systemName: "circle")
//                                .foregroundColor(overlayCircleColor.opacity(overlayCircleColor == .red  && colorScheme == .dark ? 0.5 : overlayCircleColor == .yellow  && colorScheme == .light ? 1 : 0.7))
//                                .frame(width: 24, height: 24, alignment: .leading)
//                                .fontWeight(.medium)
//                        }
//                }
//                    .buttonStyle(PlainButtonStyle())
                // Status Circle
                Button(action: {
                    handlePrayerButtonPress()
                }) {
                        // Outer circle with a stroke of the appropriate status color.
                    Image(systemName: "circle")
                            .foregroundColor(outerCircleStyle)
                            .frame(width: 14, height: 14)
                            .fontWeight(.light)
                            .overlay{
                                Image(systemName: "circle.fill")
                                    .resizable()
                                    .foregroundStyle(overlayCircleColor.opacity(overlayCircleColor == .red  && colorScheme == .dark ? 0.5 : overlayCircleColor == .yellow  && colorScheme == .light ? 1 : 0.7))
                                    .frame(width: 12, height: 12)
                                    .modifier(CompletionDotPop(pulse: completionPulse, color: overlayCircleColor))
                            }
                        
                        // Inner circle that’s filled (or clear) depending on whether the prayer is completed.

                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 24, alignment: .leading)

                // Prayer Name Label
                Text(name /*nameToDisplay*/ )
                    .font(.callout) //.callout
                    .foregroundColor(.secondary.opacity(statusBasedOpacity)) //1
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                
                Spacer()
                
                // Time Display Section
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

                } else if prayerObject.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if let completedTime = prayerObject.timeAtComplete {
                        ExternalToggleText(
                            originalText: shortTimePM(calcStartTime),
                            //originalText:  "@ \(shortTimePM(completedTime))",
                            toggledText: completedTimeAndScore,
                            /*(prayerObject.numberScore == 0 ? "Kaza" : "\((prayerObject.numberScore ?? 00)*100, specifier: "%.0f")% left" ),*/
                            externalTrigger: $toggledText,
                            font: timeFontSize,
                            fontDesign: .rounded,
                            fontWeight: .light,
                            hapticFeedback: true
                        )
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    }
                } else {
                    // Current Prayer: Show Start Time
                    Text(shortTimePM(calcStartTime))
                        .font(timeFontSize)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
                
                // Chevron Arrow
//                if name == "Fajr"{
//                    ChevronTap()
//                        .opacity(statusBasedOpacity)
//                }else{
//                    ChevronTap2()
//                        .opacity(statusBasedOpacity)
//                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            // Background Effects Container
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(backgroundColor)

                //
                /*
                 Group {
                    if isFuturePrayer || !prayerObject.isCompleted {
                        // Plain Effect: Future Prayer (No Shadow) or Current
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor)
                    } else {
                        // Neumorphic Effect: Completed Prayer
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor
                                  // Indent/Outdent Effects
                                .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 1, x: -shadowXOffset, y: -shadowYOffset))
                                .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 1, x: shadowXOffset, y: shadowYOffset))
                            )
                    }
                }
                 */
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
            .sheet(isPresented: $showTimePicker) {
                PrayerTimeEditSheet(prayer: prayerObject, time: $selectedEditTimeDate, range: editTimeRange,
                                    onCancel: { showTimePicker = false },
                                    onSave: { date in
                                        prayerObject.setPrayerScore(atDate: date)
                                        viewModel.calculatePrayerStreak()
                                        viewModel.calculateDayScore(for: prayerObject.startTime)
                                        showTimePicker = false
                                    })
            }
            .onTapGesture {
                if isFuturePrayer {
                    withAnimation {
                        toggledText.toggle()
                    }
                }
                else if prayerObject.isCompleted{
                    timer?.invalidate()

                    withAnimation {
                        toggledText.toggle()
                    }
                    
                    if toggledText {
                        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                            withAnimation{
                                toggledText = false
                            }
                        }
                    }
                }
            }
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in
                        if prayerObject.isCompleted {
                            // Open on the prayer's own day. The wheel only edits hour/minute and
                            // keeps the date it starts with: starting from a tap after midnight
                            // (rollover) put every picked time on the next day — always Qaza.
                            let marked = prayerObject.timeAtComplete ?? Date()
                            selectedEditTimeDate = min(max(marked, editTimeRange.lowerBound), editTimeRange.upperBound)
                            showTimePicker = true
                        }
                    }
            )
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
