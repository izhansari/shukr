//
//  PrayerTimesView.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/28/25.
//


//
//  PrayerViewModel.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/17/25.
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
    @FocusState private var isNumberEntryFocused
    @AppStorage("widgetCompletion", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetCompletion: Bool = false
    @AppStorage("widgetCompass", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetCompass: Bool = false
    @AppStorage("widgetTasbeeh", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTasbeeh: Bool = false
    @AppStorage("widgetTextToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var widgetTextToggle: Bool = false

    @Query private var prayersFromPersistence: [PrayerModel] = []
    
    @State private var activeTimerId: UUID? = nil
//    @State private var dragOffset: CGFloat = 0.0
//    @State private var horizontalDragOffset: CGFloat = 0.0
    @State private var isDraggingVertically: Bool? = nil  // Current drag direction
    @State private var dragOffsetNew = CGSize.zero       // Current offset of the view

    @State private var showTasbeehPage = false // State to control full-screen cover
    @State private var showMantraSheetFromHomePage: Bool = false
    @State private var chosenMantra: String? = "" {
        didSet{
            if let text = chosenMantra {
                print("ran chosenMantra's didSet")
                sharedState.titleForSession = text
            }
        }
    }
    
    @State private var isAnimating: Bool = false
    @State private var showChainZikrButton: Bool = false
    @State private var isSheetPresented = false
    @State private var settingsViewNavBool: Bool = false
    @State private var duaPageViewNavBool: Bool = false
    @State private var showQiblaMap: Bool = false



    let spacing: CGFloat = 6
    var showBottom: Bool { sharedState.navPosition == .bottom }
    var showMain: Bool { sharedState.navPosition == .main }
//    var showSalahTab: Bool { sharedState.showSalahTab }


    private var startCondition: Bool{
        let timeModeCond = (sharedState.selectedMode == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedMode == 0)
        return (timeModeCond || countModeCond || freestyleModeCond)
    }
        
    private var zikrButtonView: some View {
            
        
        Button {
            showMantraSheetFromHomePage = true
        } label: {
            Text(sharedState.titleForSession.isEmpty
                 ? "select zikr"
                 : sharedState.titleForSession
            )
            .frame(width: 150, height: 40)
            .font(.footnote)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .multilineTextAlignment(.center)
            .padding()
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
        .padding(.top, 60)
        .onChange(of: chosenMantra) {_, newMantra in
            // If the mantra changes (from MantraPickerView),
            // update sharedState.titleForSession
            if let text = newMantra {
                sharedState.titleForSession = text
            }
        }
    }
    
    
    private var zikrLableButtonUnderCircle: some View {
        Button(action: {
            showMantraSheetFromHomePage = true
        }) {
            Text(sharedState.titleForSession != "" ? sharedState.titleForSession : "choose zikr")
                .font(.footnote)
                .fontDesign(.rounded)
                .fontWeight(.thin)
                .multilineTextAlignment(.center)
                .lineLimit(3)
//                .padding()
//                .frame(width: 200)
                .opacity(sharedState.titleForSession != "" ? 0.9 : 0.7)
        }
        .padding()
        .frame(width: 200)
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    sharedState.titleForSession = ""
                }
        )
//        .border(.green)
    }


    
    private var theZikrCircle: some View {
        ZStack{
            TabView (selection: $sharedState.selectedMode) {
                freestyleMode()
                    .tag(0)
                timeTargetMode(selectedMinutesBinding: $sharedState.selectedMinutes)
                    .tag(1)
                countTargetMode(targetCount: $sharedState.targetCount, isNumberEntryFocused: _isNumberEntryFocused)
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Enable paging
            .scrollBounceBehavior(.always)
            .frame(width: 185, height: 185) // Match the CircularProgressView size
            .onChange(of: sharedState.selectedMode) {_, newPage in
                isNumberEntryFocused = false //Dismiss keyboard when switching pages
            }
            .onTapGesture {
                if(startCondition){
                    showTasbeehPage = true // Set to true to show the full-screen cover
                    triggerSomeVibration(type: .medium)
                }
                isNumberEntryFocused = false //Dismiss keyboard when tabview tapped
            }
        }
        .frame(width: 185, height: 185)
        .clipShape(Circle())
    }
    
    private var startZikrOutline: some View {
        // the color outline circle to indicate start button
        Circle()
            .stroke(lineWidth: 2)
            .frame(width: 212, height: 212)
            .foregroundStyle(startCondition ?
                             LinearGradient(
                                gradient: Gradient(colors: colorScheme == .dark ?
                                                   [.yellow.opacity(0.6), .green.opacity(0.8)] :
                                                    [.yellow, .green]
                                                  ),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                             ) :
                                LinearGradient(
                                    gradient: Gradient(colors: []),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
            )
            .animation(.easeInOut(duration: 0.5), value: startCondition)
    }

    
    private var prayerList: some View{
//        let spacing: CGFloat = 6
        VStack(spacing: 0) {  // Change spacing to 0 to control dividers manually
            ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
                PrayerButton(
                    showChainZikrButton: $showChainZikrButton,
                    name: prayerName,
                    viewModel: viewModel
                )
                .padding(.bottom, prayerName == "Isha" ? 0 : spacing)
                
                if prayerName != "Isha" {
                    Divider()
                        .overlay(Color(.secondarySystemFill))
                        .padding(.top, -spacing / 2 - 0.5)
                        .padding(.horizontal, 25)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
        
    private var switchToSalahDoubleTapSGesture: some Gesture{
        TapGesture(count: 2)
            .onEnded {
//                withAnimation{
////                    sharedState.showSalahTab.toggle()
//                    sharedState.newTopMainOrBottom
//                }
                print("Double tap detected!")
            }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private var abstractedDragGesture: some Gesture{
        DragGesture()
            .onChanged { value in
                dismissKeyboard()
                // on first change, decide if its up/down or left/right
                if isDraggingVertically == nil{
                    if abs(value.translation.height) > abs(value.translation.width) {
                        isDraggingVertically = true
                    } else {
                        isDraggingVertically = false
                    }
                }
                // on subsequent changes, we will be updating only one of the two
                if isDraggingVertically == true {
                    dragOffsetNew.height = calculateResistance(value.translation.height)
                }
                else if isDraggingVertically == false {
                    dragOffsetNew.width = calculateResistance(value.translation.width)
                }
            }
            .onEnded { value in
                handleDragEndNew(translation: value.translation, isDraggingVertically: isDraggingVertically)
                isDraggingVertically = nil
            }
    }
    
//    func calculateResistance(_ translation: CGFloat) -> CGFloat {
//            let maxResistance: CGFloat = 40
//            let rate: CGFloat = 0.01
//            let resistance = maxResistance - maxResistance * exp(-rate * abs(translation))
//            return translation < 0 ? -resistance : resistance
//        }
    func calculateResistance(_ translation: CGFloat) -> CGFloat {
        let maxResistance: CGFloat = 40
        let normalizedTranslation = min(abs(translation), 200) // Cap at 200px for smoother response
        let resistance = (normalizedTranslation / 200) * maxResistance // Linear scale
        return translation < 0 ? -resistance : resistance
    }

    
    private func handleDragEndNew(translation: CGSize, isDraggingVertically: Bool?) {
        let threshold: CGFloat = 30
        
        // positive
        var satisfiedDragDown = translation.height > threshold
        var satisfiedDragRight = translation.width > threshold
        
        // negative
        var satisfiedDragUp = translation.height < -threshold
        var satisfiedDragLeft = translation.width < -threshold
                
        // vertical check
        if self.isDraggingVertically == true {
            satisfiedDragLeft = false
            satisfiedDragRight = false
        }
        else if self.isDraggingVertically == false {
            satisfiedDragUp = false
            satisfiedDragDown = false
        }
        
        withAnimation(.smooth(duration: 0.5)) {
            dragOffsetNew = .zero
            isNumberEntryFocused = false
            
            
            guard satisfiedDragUp || satisfiedDragRight || satisfiedDragDown || satisfiedDragLeft  else { return }
            switch sharedState.navPosition {
                case .main:
                    sharedState.cameFromNavPosition = .main
                    if satisfiedDragUp { sharedState.navPosition = .bottom ; triggerSomeVibration(type: .light) }
                    if satisfiedDragDown { sharedState.navPosition = .top ; triggerSomeVibration(type: .light) }
                    if satisfiedDragRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                    if satisfiedDragLeft { sharedState.navPosition = .right ; triggerSomeVibration(type: .light) }
//                    if satisfiedDragLeft { /*sharedState.newTopMainOrBottom = .right*/ settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                case .bottom:
                    sharedState.cameFromNavPosition = .bottom
                    if satisfiedDragDown { sharedState.navPosition = .main ; triggerSomeVibration(type: .light) }
                    if satisfiedDragRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                    if satisfiedDragLeft { /*sharedState.newTopMainOrBottom = .right*/ settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                case .top:
                    sharedState.cameFromNavPosition = .top
                    if satisfiedDragUp { sharedState.navPosition = .main ; triggerSomeVibration(type: .light) }
                    if satisfiedDragRight { sharedState.navPosition = .left ; triggerSomeVibration(type: .light) }
                    if satisfiedDragLeft { /*sharedState.newTopMainOrBottom = .right*/ settingsViewNavBool = true ; triggerSomeVibration(type: .light) }
                case .left:
                    if satisfiedDragLeft { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) ; }
                case .right:
                    if satisfiedDragRight { sharedState.navPosition = sharedState.cameFromNavPosition ; triggerSomeVibration(type: .light) }
                
                
            }
        }
        
    }

    
    var body: some View {
        ZStack {
            
            Color("bgColor").opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { isNumberEntryFocused = false }
                .highPriorityGesture(abstractedDragGesture)
                .simultaneousGesture(switchToSalahDoubleTapSGesture)
            
            
            
            // This is a zstack with SwipeZikrMenu, pulseCircle, (and roundedrectangle just to push up.)
                
            // MARK: - this one works vv
            
            // Combined State
            ZStack {
                if sharedState.navPosition != .left && sharedState.navPosition != .right {
                VStack {
                    
                    ZStack{
                        if sharedState.navPosition == .top {
                            
                            ZStack{
                                
                                theZikrCircle
                                    .zIndex(1)
//                                NeuCircularProgressView(progress: 0)
                                Circle()
                                    .stroke(Color(.secondarySystemFill), lineWidth: 12)
                                    .frame(width: 200, height: 200)
                                    .zIndex(2)
                                startZikrOutline
                                    .zIndex(4)
                                zikrLableButtonUnderCircle
                                    .offset(y: 140)
                            }
                            .offset(y: 70)
                            .offset(dragOffsetNew)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                            ZStack{
                                DailyTasksView(showMantraSheetFromHomePage: $showMantraSheetFromHomePage, showTasbeehPage: $showTasbeehPage)
                            }
                            .frame(width: 260)
//                            .background( NeumorphicBorder() )
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.primary.opacity(0.001)) // Background color
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color(.secondarySystemBackground), lineWidth: 2) // Border color and width
                                    )
                            )
                            .offset(y: -220 )
                            .offset(x: dragOffsetNew.width / 1.75)
                            .offset(y: (dragOffsetNew.height / 1.75) )
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                        }
                    }
                    
                    
                    // Salah Circles
                    if sharedState.navPosition == .main || sharedState.navPosition == .bottom{
                        
                        Spacer()
                        if showBottom {
                            Spacer()
                        }
                        
                        ZStack{
                            ZStack{
//                                Circle()
//                                    .trim(from: 0, to: 1)
//                                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                                    .frame(width: 200, height: 200)
//                                    .rotationEffect(.degrees(-90))
//                                    .foregroundStyle(
//                                        LinearGradient(
//                                            gradient: Gradient(
//                                                colors: colorScheme == .dark
//                                                    ? [.yellow.opacity(0.6), .green.opacity(0.8)]
//                                                    : [.yellow, .green]
//                                            ),
//                                            startPoint: .topLeading,
//                                            endPoint: .bottomTrailing
//                                        )
//                                    )
//                                    .animation(.spring(), value: 0)
//                                    .opacity(0.3)
//                                NeuCircularProgressView(progress: 0)
//                                Circle()
//                                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
//                                    .frame(width: 200, height: 200)
//
//                                
//                                Circle()
//                                    .trim(from: 0, to: 0.4) // Adjust progress value (0 to 1)
//                                    .stroke(
//                                        .green,
//                                        style: StrokeStyle(lineWidth: 2, lineCap: .butt)
//                                    )
//                                    .rotationEffect(.degrees(-90))
//                                    .frame(width: 200, height: 200)


                                
                                
                                if let relevantPrayer = viewModel.relevantPrayer {
                                    PulseCircleView(prayer: relevantPrayer, showQiblaMap: $showQiblaMap)
                                    //.transition(.opacity)
                                        .highPriorityGesture(abstractedDragGesture)
                                } else {
                                    summaryCircle()
                                }
                            }
                        }
                        .offset(dragOffsetNew)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                        .onAppear {
                            print("⭐️ prayerTimesView onAppear")
                            viewModel.fetchPrayerTimes(cameFrom: "onAppear pulse circle Circles")
                            viewModel.loadTodaysPrayers()
                            viewModel.calculatePrayerStreak()
                        }
                        
                        Spacer()
                        
                    }
                    
                    // -- Bottom Content --
                    // ... for Salah
                    if showBottom {
                        ZStack(alignment: .bottom){
                            VStack{
                                Spacer()
//                                Text(relativeDayFormatted(Date()))
//                                    .font(.footnote)
//                                    .fontWeight(.light)
//                                    .foregroundStyle(Color.secondary)
//                                    .offset(y: -10)
////                                    .padding()

                                VStack{
                                    prayerList
                                }
                                .frame(width: 260)
//                                .background( NeumorphicBorder() )
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.primary.opacity(0.001)) // Background color
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color(.secondarySystemBackground), lineWidth: 2) // Border color and width
                                        )
                                )
                                .padding(.bottom, 45)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .offset(x: dragOffsetNew.width / 1.75)
                        .offset(y: dragOffsetNew.height / 1.75)
                        .opacity(1 - Double(dragOffsetNew.height / 90))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .frame(height: 300)
                        .padding(.bottom, 45)
                        
//                        CustomBottomBar()
//                            .offset(y: max(dragOffsetNew.height / 2, 0))
//                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        
                    }
                    
                }
//                .transition(.move(edge: .trailing).combined(with: .opacity))
//                .transition(.move(edge: dragOffsetNew.width < 0 ? .leading : .trailing).combined(with: .opacity)) // doesnt work cuz we set it to zero...
                .transition(.opacity)
                }
                
                // -- “Chevron” to Toggle Main <-> Bottom --
                if showMain {
                    VStack {
                        Spacer()
                        Button {
                            withAnimation {
                                print("tapped the chev")
                                sharedState.navPosition = showBottom ? .main : .bottom
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.title3)
                                .foregroundColor(.gray)
                                .scaleEffect(x: 1, y: (dragOffsetNew.height > 0 || showBottom) ? -1 : 1)
                                .padding(.bottom, 30)
                                .padding()
                                .offset(y: dragOffsetNew.height)
                        }
                    }
                }
            }
            
                    // MARK: - this one works ^^

            // MARK: - WIP Smooth SettingsView
            /// needs to make top, main, bottom exit to the leading side.
            ZStack{
                VStack{
                    HStack{
                        Button("<Back"){
                            dismissKeyboard()
                            withAnimation(.spring(duration: 0.5)) {
                                sharedState.navPosition = sharedState.cameFromNavPosition
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, 20)
                    
                    SettingsView()
                        .background(Color(.systemBackground))
                }
                
                HStack(){
                    Color("bgColor").opacity(0.001)
                        .frame(width: 20)
                    Spacer()
                }
                .edgesIgnoringSafeArea(.all)
                .highPriorityGesture(abstractedDragGesture)

            }
//            .background(Color("bgColor"))
//                .padding()
            .offset(x: dragOffsetNew.width > 0 ? dragOffsetNew.width : 0)
            .offset(x: sharedState.navPosition == .right ? 0 : UIScreen.main.bounds.width)
            .transition(.move(edge: .leading).combined(with: .opacity))

            
            // MARK: - Smooth DuaPageView
            VStack{
                HStack{
                    Spacer()
                    Button("Back>"){
                        dismissKeyboard()
                        withAnimation(.spring(duration: 0.5)) {
                            sharedState.navPosition = sharedState.cameFromNavPosition
                        }
                    }
                }
                .padding(.trailing, 20)
                
                DuaPageView()
            }
            .background(Color(.systemBackground))
            .padding()
            .offset(x: dragOffsetNew.width < 0 ? dragOffsetNew.width : 0)
            .offset(x: sharedState.navPosition == .left ? 0 : -UIScreen.main.bounds.width)
            .transition(.move(edge: .leading).combined(with: .opacity))
            
            // in the case of having a valid location (everything except pulsecirlce):
            if viewModel.hasValidLocation {
                VStack {
                    // This ZStack holds the manraSelector, floatingChainZikrButton, and TopBar
                    ZStack(alignment: .top) {
                        FloatingChainZikrButton(showTasbeehPage: $showTasbeehPage, showChainZikrButton: $showChainZikrButton)
                        if sharedState.navPosition != .left {
                            TopBar()
                                .offset(x: dragOffsetNew.width / 1.75)
//                                .offset(y: dragOffsetNew.height / 1.75)
                                .transition(.opacity)
                        }
                    }
                                        
                    Spacer()
                    
                }
                .navigationBarHidden(true)
            }
            // Page we get when they authorization for location has not been granted or denied
            else if viewModel.locationAuthorizationStatus != .authorizedWhenInUse {
                VStack {
                    Text("Location Access Required")
                        .font(.headline)
                        .padding()
                    Text("Please allow location access to fetch accurate prayer times.")
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Allow Location Access") {
                        viewModel.requestLocationAuthorization()
                    }
                    .padding()
                }
            }
            
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .active {

                
                if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
                    let completionFromStore     = store.bool(forKey: "widgetCompletion")
                    let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
                    let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
                    store.setValue(false, forKey: "widgetCompletion")
                    store.setValue(false, forKey: "widgetCompass")
                    store.setValue(false, forKey: "widgetTasbeeh")

                    if completionFromStore{
                        withAnimation(.spring(duration: 0.5)) { sharedState.navPosition = .bottom }
//                        sharedState.navPosition = .bottom
                        if let relevantPrayer = viewModel.relevantPrayer {
                            viewModel.togglePrayerCompletion(for: relevantPrayer)
                        }
                    }
                    
                    else if openCompassFromWidget{
                        sharedState.navPosition = .main
                        showQiblaMap = true
                    }
                    
                    else if openTasbeehFromWidget{
                        withAnimation(.spring(duration: 0.5)) { sharedState.navPosition = .top }
                    }
                }
                

            }
        }
        .onChange(of: sharedState.navPosition){ oldValue, newValue in
            if oldValue == .top && newValue == .main  {
                sharedState.resetTasbeehInputs()
                print("ResetTasbeehInputs cuz we dismissed DailyTasks.")
            }
        }
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
                    sharedState.showingPulseView = false
                }
                .onDisappear{
                    sharedState.showingPulseView = true
                }
        }
        
        .edgesIgnoringSafeArea(.bottom)
    }

    
    // MARK: - Other Helper Structs
    
    struct summaryCircle: View{
        // FIXME: think this through more and make sure it makes sense.
        @State private var nextFajr: (start: Date, end: Date)?
        @EnvironmentObject var viewModel: PrayerViewModel
        @State var summaryInfo: [String : Double?] = [:]
        @State private var textTrigger = false
        @State private var currentTime = Date()

        private var fajrAtString: String{
            guard let fajrTime = nextFajr else { return "" }
            return "Farj at \(shortTimePM(fajrTime.start))"
        }
        
        private var sunriseAtString: String{
            guard let fajrTime = nextFajr else { return "" }
            return "Sunrise at \(shortTimePM(fajrTime.end))"
        }
        
        private func getTheSummaryInfo(){
            for name in viewModel.orderedPrayerNames {
                if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }){
                    summaryInfo[name] = prayer.numberScore
                    print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with scores: \(prayer.numberScore ?? 0)")
                }
            }
        }
        
        func setTheRightFajrTime(){
            if let todaysFajr = viewModel.getPrayerTime(for: "Fajr", on: Date()){
                if todaysFajr.start > Date(){
                    nextFajr = todaysFajr
                }
                else{
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    nextFajr = viewModel.getPrayerTime(for: "Fajr", on: tomorrow)
                }
            }
        }
        
        func calculateScoreDotPosition(_ score: Double, from: CGFloat, to: CGFloat) -> CGPoint {
            let angle = CGFloat(-90.0) + 360.0 * (CGFloat(score) * (to - from) + from)
            let radius: CGFloat = 90 // Adjust based on your circle size
            let radians = angle * .pi / 180
            return CGPoint(x: cos(radians) * radius, y: sin(radians) * radius)
        }

        var body: some View{
            ZStack{
                NeuCircularProgressView(progress: 0)
                
    //            ForEach(0..<5) { index in
    //                let prayerSpace = 360.0 / 5 // 360 degrees / 5 sections
    //                let startAngle = CGFloat(index) * prayerSpace
    //
    //                // Separator lines
    //                Rectangle()
    //                    .fill(Color.secondary.opacity(0.2))
    //                    .frame(width: 2, height: 12)
    //                    .offset(y: -100) // Based on circle size of 200x200
    //                    .rotationEffect(.degrees(Double(startAngle)))
    //
    //                Circle()
    //                    .trim(from: 0, to: 0.2)
    //                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
    //                    .frame(width: 200, height: 200)
    //                    .foregroundStyle(.secondary)
    //                    .rotationEffect(.degrees(Double(startAngle)))
    //
    //
    //                // Dot on the circle
    //                let score: CGFloat = 0.25 // Example prayer score
    //                let dotAngle = startAngle + ((1 - score) * prayerSpace) // Place dot at 1 - score from end
    //                let scoreColor: Color = .secondary // Replace with your dynamic color variable
    //                Circle()
    //                    .stroke(scoreColor.opacity(0.5), lineWidth: 0.5) // Dot stroke with scoreColor
    //                    .frame(width: 10, height: 10) // Dot size
    //                    .offset(y: -100) // Radius positioning
    //                    .rotationEffect(.degrees(Double(dotAngle))) // Dot position in section
    //            }

                            
                VStack{
                    Text("done")
                    if let fajrTime = nextFajr {
                        
                        ExternalToggleText(
                            originalText: fajrAtString,
                            toggledText: sunriseAtString,
                            externalTrigger: $textTrigger,  // Pass the binding
                            fontDesign: .rounded,
                            fontWeight: .thin,
                            hapticFeedback: true
                        )
                    }
                }
                
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 200, height: 200)
                    .onTapGesture {
                        textTrigger.toggle()  // Toggle the trigger
                    }
            }
            .onAppear {
                setTheRightFajrTime()
                getTheSummaryInfo()
            }
        }
        

    }
    
    struct CustomBottomBar: View {
        @EnvironmentObject var sharedState: SharedStateClass

        var body: some View {
            VStack(spacing: 0){

                    Divider()
                        .foregroundStyle(.primary)
                    
                    HStack {
                        
                        
                        Button(action: {
                            withAnimation(.spring(duration: 0.5)) {
                                sharedState.navPosition = .left
                            }
                        }) {
                            VStack(spacing: 6){
                                Image(systemName: "book")
                                    .font(.system(size: 20))
                                Text("Duas")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                            }
                            .foregroundColor( sharedState.navPosition == .left ? .green : .gray)
                            .frame(width: 100)
                        }

                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(duration: 0.5)) {
                                sharedState.navPosition = .bottom
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait")
                                    .font(.system(size: 20))
                                Text("Salah")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                            }
                            .foregroundColor( sharedState.navPosition == .bottom ? .green : .gray)
                            .frame(width: 100)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(duration: 0.5)) {
                                sharedState.navPosition = .top
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "circle.hexagonpath")
                                    .font(.system(size: 20))
                                Text("Zikr")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                            }
                            .foregroundColor(sharedState.navPosition == .top ? .green : .gray)
                            .frame(width: 100)
                        }
                    }
                    .padding(.top, 15)
                    .padding(.bottom, 25)
                    .padding(.horizontal, 45)
                    .opacity(0.8)
                    .background(Color("bgColor"))
                
            }
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


// MARK: - Prayer Button


import MapKit
struct PrayerButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0


    @Binding var showChainZikrButton: Bool
    @State private var dismissChainZikrItem: DispatchWorkItem? // Manage the dismissal timer
    
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
        
    init(showChainZikrButton: Binding<Bool>, name: String, viewModel: PrayerViewModel) {
        guard let foundPrayer = viewModel.todaysPrayers.first(where: { $0.name == name }) else {
            fatalError("PrayerModel not found for name: \(name)")
        }
        self._showChainZikrButton = showChainZikrButton
        self.prayerObject = foundPrayer
        self.name = name
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
    
    private var statusColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayerObject.isCompleted ? viewModel.getColorForPrayerScore(prayerObject.numberScore).opacity(0.70) : Color.secondary.opacity(0.5)
    }
    
    private var overlayCircleColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.01) }
        return prayerObject.isCompleted ? viewModel.getColorForPrayerScore(prayerObject.numberScore) : Color.secondary.opacity(0.5)
    }
    
    private var grayCircleStyle: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayerObject.isCompleted ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.5)
    }
    
    // Text Properties
    private var statusBasedOpacity: Double {
        if isFuturePrayer { return 0.6 }
        return prayerObject.isCompleted ? 0.7 : 1
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
    
    private var nameFontSize: Font {
        return .callout
    }
    
    private var timeFontSize: Font {
        return .footnote
    }
    
    private var calcStartTime: Date{
        if let timesFromDict = viewModel.prayerTimesForDateDict[name]{
            return timesFromDict.start
        }
        return Date()
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
                Button(action: {
                    handlePrayerButtonPress()
                }) {
                    Image(systemName: statusImageName)
                        .foregroundColor(grayCircleStyle)
                        .frame(width: 24, height: 24, alignment: .leading)
                        .overlay{
                            Image(systemName: "circle")
                                .foregroundColor(overlayCircleColor.opacity(overlayCircleColor == .red  && colorScheme == .dark ? 0.5 : overlayCircleColor == .yellow  && colorScheme == .light ? 1 : 0.7))
                                .frame(width: 24, height: 24, alignment: .leading)
                                .fontWeight(.medium)
                        }
                }
                    .buttonStyle(PlainButtonStyle())
                
                // Prayer Name Label
                Text(name /*nameToDisplay*/ )
                    .font(nameFontSize) //.callout
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
                ChevronTap()
                    .opacity(statusBasedOpacity)
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
                        viewModel.setPrayerScore(for: prayerObject, atDate: selectedEditTimeDate)
                        viewModel.calculatePrayerStreak()
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
        
        NavigationLink(destination: PrayerEditorView()) {
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
    }
}



