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
    @AppStorage("widgetCompletion", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetCompletion: Bool = false
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
    
    @State private var isDraggingVertically: Bool? = nil  // Current drag direction
    @State private var dragOffset = CGSize.zero       // Current offset of the view
    private var chevDragValue: CGFloat{ // this is cool, i made it into an if, else if, else statement lol.
        showBottom ?
            max(0, dragOffset.height)  // Prevent upward movement when showing bottom
//        : showTop ?
//            min(0, dragOffset.height)  // Prevent downward movement when showing top
        :
            dragOffset.height  // Normal behavior when neither top nor bottom is showing
    }


//    var showTop: Bool { sharedState.navPosition == .top }
    var showMain: Bool { sharedState.navPosition == .main }
    var showBottom: Bool { sharedState.navPosition == .bottom }
    var showCenter: Bool { sharedState.navPosition == .main /*|| sharedState.navPosition == .top*/ || sharedState.navPosition == .bottom }
        
    private var switchToSalahDoubleTapSGesture: some Gesture{
        TapGesture(count: 2)
            .onEnded {
                // left this incase we want to use it for an action.
                print("Double tap: no action assigned yet...")
            }
    }
    
    private var abstractedDragGesture: _EndedGesture<_ChangedGesture<DragGesture>> {
        let resistanceFactor = 0.5
        let maxOffset: CGFloat = 20
        let threshold: CGFloat = 30

        return DragGesture()
            .onChanged { value in
                
                if isDraggingVertically == nil { // to decide if up/down or left/right
                    dismissKeyboard()
                    isDraggingVertically = abs(value.translation.height) > abs(value.translation.width)
                }
                
                if isDraggingVertically == true { // now, we will be updating only one of the two
                    dragOffset.height = min(max(value.translation.height * resistanceFactor, -maxOffset), maxOffset)
                } else {
                    dragOffset.width = min(max(value.translation.width * resistanceFactor, -maxOffset), maxOffset)
                }
                
            }
            .onEnded { value in
                handleDragEnd(translation: value.translation, isDraggingVertically: isDraggingVertically)
                isDraggingVertically = nil
            }
        
        
        
        func handleDragEnd(translation: CGSize, isDraggingVertically: Bool?) {
            
            var draggedDown = false, draggedRight = false, draggedUp = false, draggedLeft = false
            // vertical check
            if self.isDraggingVertically == true {
                draggedDown = translation.height > threshold // positive
                draggedUp = translation.height < -threshold // negative
            }
            else if self.isDraggingVertically == false {
                draggedRight = translation.width > threshold // positive
                draggedLeft = translation.width < -threshold // negative
            }
            
            withAnimation(.spring()) {
                dragOffset = .zero
                
                guard draggedUp || draggedRight || draggedDown || draggedLeft else { return }
                /*
                switch sharedState.navPosition {
                    case .main:
                        sharedState.cameFromNavPosition = .main
                        sharedState.bottomTabPosition = .salah
                        if draggedUp { sharedState.navPosition = .bottom ; triggerSomeVibration(type: .light) }
//                        if draggedDown { sharedState.navPosition = .top ; triggerSomeVibration(type: .light) }
                        if draggedRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                        if draggedLeft { settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                    case .bottom:
                        sharedState.cameFromNavPosition = .bottom
                        if draggedDown { sharedState.navPosition = .main ; sharedState.bottomTabPosition = .salah ; triggerSomeVibration(type: .light) }
                        if draggedRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                        if draggedLeft { settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                    case .top:
//                        sharedState.cameFromNavPosition = .top
//                        if draggedUp { sharedState.navPosition = .main ; triggerSomeVibration(type: .light) }
//                        if draggedRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
//                        if draggedLeft { settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                        print("not")
                    case .left:
                        if draggedLeft { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) ; }
                    case .right:
                        if draggedRight { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) }
                }
                */
                switch sharedState.navPosition {
                    case .main:
                        sharedState.cameFromNavPosition = .main
                        sharedState.bottomTabPosition = .salah
                        if draggedUp { sharedState.navPosition = .bottom ; triggerSomeVibration(type: .light) }
                        if draggedDown { viewModel.refreshCityAndPrayerTimes()  ; triggerSomeVibration(type: .light) }
                        if draggedRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                        if draggedLeft { sharedState.navPosition = .bottom ; sharedState.bottomTabPosition = .zikr /*settingsViewNavBool = true*/ ; triggerSomeVibration(type: .light) }
                    case .bottom:
                        sharedState.cameFromNavPosition = .bottom
                        if draggedDown { sharedState.navPosition = .main ; sharedState.bottomTabPosition = .salah ; triggerSomeVibration(type: .light) }
                    if draggedRight {
                        if sharedState.bottomTabPosition == .zikr{
                            sharedState.bottomTabPosition = .salah ; triggerSomeVibration(type: .light)
                        }
                        else if sharedState.bottomTabPosition == .salah{
                            sharedState.navPosition = .left ; triggerSomeVibration(type: .light)
                        }
                    }
                    if draggedLeft {
                        if sharedState.bottomTabPosition == .salah{
                            sharedState.bottomTabPosition = .zikr ; triggerSomeVibration(type: .light)
                        }
                        else if sharedState.bottomTabPosition == .zikr{
                            settingsViewNavBool = true ; triggerSomeVibration(type: .light)
                        }
                    }
                    case .top:
//                        sharedState.cameFromNavPosition = .top
//                        if draggedUp { sharedState.navPosition = .main ; triggerSomeVibration(type: .light) }
//                        if draggedRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
//                        if draggedLeft { settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                        print("not")
                    case .left:
                        if draggedLeft { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) ; }
                    case .right:
                        if draggedRight { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) }
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            
            Color("bgColor").opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .highPriorityGesture(abstractedDragGesture)
                .simultaneousGesture(switchToSalahDoubleTapSGesture)
            
            
            
            // This is a zstack with SwipeZikrMenu, pulseCircle, (and roundedrectangle just to push up.)
                
            // MARK: - this one works vv
            
            // Combined State
            ZStack {
                if showCenter{
                    VStack {

                        Spacer()
                        
                        if showBottom{
                            Spacer()
                            Spacer()
                        }
                        
                        ZStack{
                            MainCircleView(showQiblaMap: $showQiblaMap, showChainZikrButton: $showChainZikrButton, showTasbeehPage: $showTasbeehPage)
                                .geometryGroup()
                                .highPriorityGesture(abstractedDragGesture)
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
                                    showTasbeehPage: $showTasbeehPage,
                                    dragGesture: abstractedDragGesture
                                )
//                                        .fullScreenCover(isPresented: $showDailyAyahView){
//                                            DailyAyahView()
//                                        }
                            .opacity(1 - Double(dragOffset.height / 90))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            
                            Spacer()
                            

                        }
                        
                        ZStack{
                            Button {
                                withAnimation {
                                    print("tapped the chev")
                                    sharedState.navPosition = showBottom ? .main : .bottom
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.title3)
                                    .foregroundStyle(chevDragValue != 0 ? Color.secondary : Color(.secondarySystemFill))
                                    .animation(.smooth, value: dragOffset.height)
//                                    .scaleEffect(x: 1, y: (dragOffset.height > 0 || showBottom) ? -1 : 1)
                                    .padding(.bottom, 30)
                                    .padding()
                                    .offset(y: chevDragValue)
                            }
                            .opacity(showBottom ? 0 : 1)
                            
                            CustomBottomBar()
                                .opacity(1 - Double(dragOffset.height / 90))
                                .opacity(showBottom ? 1 : 0)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                    }
                    .transition(.opacity)
                    
                    
                    
                }
            }
            

            
            // MARK: - Smooth DuaPageView
            VStack{
                DuaPageView()
            }
            .background(Color(.systemBackground))
            .padding()
            .offset(x: dragOffset.width < 0 ? dragOffset.width : 0)
            .offset(x: sharedState.navPosition == .left ? 0 : -UIScreen.main.bounds.width)
            .transition(.move(edge: .leading).combined(with: .opacity))


            VStack {
                // This ZStack holds the manraSelector, floatingChainZikrButton, and TopBar
                ZStack(alignment: .top) {
                    FloatingChainZikrButton(showTasbeehPage: $showTasbeehPage, showChainZikrButton: $showChainZikrButton)
                    if sharedState.navPosition != .left && sharedState.navPosition != .right {
                        TopBar()
                            .transition(.opacity)
                            // vvvthis is for visually showing refresh... need to make it change text, lag, then display new city
                            //.offset(y: dragOffset.height > 0 && sharedState.navPosition == .main && sharedState.bottomTabPosition == .salah ? dragOffset.height : 0)

                        //Menu Button and Side Menu Stuff
                        HStack{
                                Button(action: {
                                    withAnimation { sharedState.showSideMenu.toggle()}
                                }) {
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
                        
                        // Grayed Out Cover for SideMenu
                        Color(.black).opacity(0.5)
                            .edgesIgnoringSafeArea(.all)
                            .onTapGesture {
                                withAnimation{ sharedState.showSideMenu = false }
                            }
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                                    .onEnded { value in
                                            withAnimation { sharedState.showSideMenu = false }
                                    }
                            )
                            .opacity(sharedState.showSideMenu ? 1 : 0)

                        
                        HStack{
                            sideMenu(viewState: sharedState.navPosition)
                                .frame(width: 180)
                                .offset(x: sharedState.showSideMenu ? 0 : -200)
                                .animation(.spring, value: sharedState.showSideMenu)
                            Spacer()
                        }
                    }
                }
                                    
                Spacer()
                
            }
            .navigationBarHidden(true)
            
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .active {

                viewModel.loadTodaysPrayerObjects()
                
                if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
                    let completionFromStore     = store.bool(forKey: "widgetCompletion")
                    let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
                    let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
                    store.setValue(false, forKey: "widgetCompletion")
                    store.setValue(false, forKey: "widgetCompass")
                    store.setValue(false, forKey: "widgetTasbeeh")

                    if completionFromStore{
                        withAnimation(.spring(duration: 0.3)) { sharedState.navPosition = .bottom }
//                        sharedState.navPosition = .bottom
                        if let relevantPrayer = viewModel.relevantPrayer {
                            viewModel.togglePrayerCompletion(for: relevantPrayer)
                            showTemporaryMessage(workItem: &dismissChainZikrItem, boolToShow: $showChainZikrButton, delay: 5)
                        }
                    }
                    
                    else if openCompassFromWidget{
                        sharedState.navPosition = .main
                        showQiblaMap = true
                    }
                    
                    else if openTasbeehFromWidget{
                        withAnimation(.spring(duration: 0.3)) {
//                            sharedState.navPosition = .top
                            sharedState.bottomTabPosition = .zikr
                            sharedState.navPosition = .bottom
                        }
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
        .onChange(of: chosenMantra) {_, newMantra in
            if let text = newMantra {
                sharedState.titleForSession = text
            }
        }
        .sheet(isPresented: $showMantraSheetFromHomePage) {
            MantraPickerView(
                isPresented: $showMantraSheetFromHomePage,
                selectedMantra: $chosenMantra, //try putting sharedstate.titleforsession in here <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
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

    
    // MARK: - Other Helper Structs
    
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
        var dragGesture: _EndedGesture<_ChangedGesture<DragGesture>>


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
                    .highPriorityGesture(dragGesture)
                    
                    
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
                            withAnimation(.spring()) {
                                sharedState.navPosition = .left
                            }
                        }) {
                            VStack(spacing: 6){
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 20))
                                Text("Notes")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor( sharedState.navPosition == .left ? .green : .gray)
                            .frame(width: 100)
                        }

                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                sharedState.bottomTabPosition = .salah
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
                            .foregroundColor( sharedState.bottomTabPosition == .salah ? .green : .gray)
                            .frame(width: 100)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                sharedState.bottomTabPosition = .zikr
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "circle.hexagonpath")
                                    .font(.system(size: 20))
                                Text("Zikr")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor(sharedState.bottomTabPosition == .zikr ? .green : .gray)
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
                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
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

