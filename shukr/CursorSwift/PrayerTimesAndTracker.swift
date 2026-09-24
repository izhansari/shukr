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
    private var abstractedDragGesture: _EndedGesture<_ChangedGesture<DragGesture>> {
        let resistanceFactor = 0.5
        let maxOffset: CGFloat = 20
        let threshold: CGFloat = 30

        return DragGesture()
            .onChanged { value in
                if isDraggingVertically == nil { // decide the axis once per drag
                    dismissKeyboard()
                    isDraggingVertically = abs(value.translation.height) > abs(value.translation.width)
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
                    
                    SettingsView()
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
            .scrollDisabled(live.pagerLocked)   // see PagerLiveState.pagerLocked
            .environment(live)
            .ignoresSafeArea(edges: .bottom)
            // The vertical drag (sheet open/close, pull-to-refresh) lives on the ScrollView
            // itself, not on views inside it: the scroll view's pan gets first claim on every
            // touch, takes horizontal ones for paging, and hands vertical ones to this gesture.
            // Nothing inside a page can block paging that way.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Page position, live: 0 = Zikr, 1 = Salah, 2 = Settings. Only the chrome reads it.
                let width = geometry.containerSize.width
                return width > 0 ? geometry.contentOffset.x / width : 1
            } action: { _, progress in
                live.scrollProgress = progress
            }
            .simultaneousGesture(switchToSalahDoubleTapSGesture)
            .simultaneousGesture(abstractedDragGesture)
            .onScrollPhaseChange { _, phase, context in
                // Record the page only once the scroll has settled. Doing it mid-drag (as the
                // scrollPosition binding would) re-rendered the home screen while the page was
                // still moving. navPosition is NOT touched: the center page keeps its state.
                guard phase == .idle else { return }
                let width = context.geometry.containerSize.width
                guard width > 0 else { return }
                // The first idle report comes before the three pages are laid out (content one
                // page wide, midX at 0.5 → "Zikr") and the centre anchor then jumps silently.
                // Acting on it left horizontalPage = .zikr on the Salah page at launch.
                guard context.geometry.contentSize.width >= width * 2.5 else { return }
                let index = Int((context.geometry.visibleRect.midX / width).rounded(.down))
                let page: NavPage = (index <= 0) ? .zikr : (index >= 2) ? .settings : .main
                if sharedState.horizontalPage != page {
                    sharedState.horizontalPage = page
                    triggerSomeVibration(type: .light)
                }
            }
            .onChange(of: sharedState.horizontalPage) { _, wanted in
                // Programmatic nav (bottom bar, menu, widget deep link): scroll the pager to match.
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
                showSalahHistoryV2: $showSalahHistoryV2, showZikrHistory: $showZikrHistory
            )
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .active {

                viewModel.loadTodaysPrayerObjects()
                viewModel.reconcileAfterWidgetWrites() // prayers completed from the widget while we were closed
                
                if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
                    let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
                    let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
                    store.setValue(false, forKey: "widgetCompass")
                    store.setValue(false, forKey: "widgetTasbeeh")

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

                Color.clear.frame(height: bottomChromeHeight)
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
                        Menu {
                            Button { showMapPage = true } label: { Label("Map", systemImage: "map") }
                            Button { showDailyAyahPage = true } label: { Label("Daily Ayah", systemImage: "book") }
                            Button { showMantrasPage = true } label: { Label("Mantras", systemImage: "text.quote") }
                            Button { showZikrHistory = true } label: { Label("Zikr History", systemImage: "clock.arrow.circlepath") }
                            Button { sharedState.horizontalPage = .settings } label: { Label("Settings", systemImage: "gear") }
                            #if DEBUG
                            Menu {
                                Button("Salah History (V1)") { showSalahHistoryV1 = true }
                                Button("Salah History (V2)") { showSalahHistoryV2 = true }
                            } label: {
                                Label("Dev's WIP", systemImage: "hammer")
                            }
                            #endif
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .background(.white.opacity(0.01))
                                .frame(width: 24, height: 24)
                                .font(.system(size: 20))
                                .fontWeight(.light)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray.opacity(0.8))
                                .padding()
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
    
    var body: some View {
        VStack{
            VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
                // Only prayers that are loaded: PrayerButton fatalErrors on a missing one, and
                // this list is now in the tree from launch, before loadTodaysPrayerObjects runs.
                let loaded = viewModel.orderedPrayerNames.filter { name in viewModel.todaysPrayers.contains { $0.name == name } }
                ForEach(loaded, id: \.self) { prayerName in
                    PrayerButton(
                        showChainZikrButton: $showChainZikrButton, dismissChainZikrItem: $dismissChainZikrItem,
                        name: prayerName,
                        viewModel: viewModel
                    )
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
    
    private var completedTimeAndScore: String {
        if let score = prayerObject.numberScore, score != 0 {
            String(format: "%.0f%% left", score * 100)
        }else{
            "Kaza"
        }
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
                VStack {
                    Text("Edit Prayer Details for \(name)")
                        .font(.headline)
                        .padding()
                    
                    Text("\(prayerObject.name) Range:")
                    Text("\(shortTime(prayerObject.startTime)) - \(shortTimePM(prayerObject.endTime))")
                    
//                    Text("Completion Time")
                    DatePicker("", selection: $selectedEditTimeDate, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                    
//                    // Add a small map view
//                    MiniMapView(coordinate: $selectedLocation)
//                        .frame(height: 200)
//                        .cornerRadius(10)
//                        .padding()

                    // Add a search bar
//                    TextField("Search location", text: $searchQuery)
//                        .textFieldStyle(RoundedBorderTextFieldStyle())
//                        .padding()
//                        .onSubmit {
//                            searchLocation()
//                        }
                    
                    Button("Save") {
//                        viewModel.setPrayerScore(for: prayerObject, atDate: selectedEditTimeDate)
                        prayerObject.setPrayerScore(atDate: selectedEditTimeDate)
                        viewModel.calculatePrayerStreak()
                        viewModel.calculateDayScore(for: prayerObject.startTime)
                        showTimePicker = false
                    }
                    .padding()
                }
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
                            selectedEditTimeDate = prayerObject.timeAtComplete ?? Date()
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
    /// Set by the Zikr page's task strip while a finger is on it; the pager is scroll-disabled
    /// meanwhile so a drag past the strip's last card can't chain into a page turn.
    var pagerLocked = false
}
