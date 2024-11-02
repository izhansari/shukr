import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer
import Foundation


//class SharedStateClass: ObservableObject {
////    @Published var sessionItems: [SessionDataModel] = []
////    
////    // You can initialize it with data or fetch data from persistence here
////    init(sessionItems: [SessionDataModel]) {
////        self.sessionItems = sessionItems
////    }
//    
//    @Published var selectedPage: Int = 0
//    @Published var selectedMinutes: Int = 0
//    @Published var targetCount: String = ""
//    @Published var titleForSession: String = ""
//    @Published var showingOtherPages: Bool = false
//}

struct tasbeehView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    let autoStart: Bool  // New parameter to auto-start the timer
    @Binding var isPresented: Bool
    
    init(isPresented: Binding<Bool>, autoStart: Bool) {
        self._isPresented = isPresented
        self.autoStart = autoStart
    }
    
    @Environment(\.modelContext) private var context
    @Query private var sessionItems: [SessionDataModel]
    
    // AppStorage properties
//    @AppStorage("count", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    var tasbeeh: Int = 10
    @AppStorage("streak") var streak = 0
//    @AppStorage("autoStop", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    @State private var autoStop = true
    @AppStorage("vibrateToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var vibrateToggle = true
    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var colorModeToggle = false
//    @AppStorage("paused", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    var paused = false
    @AppStorage("inactivityToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var toggleInactivityTimer = false
    
    // State properties
    @FocusState private var isNumberEntryFocused
    
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    @State private var autoStop = true
    @State private var paused = false
    @State private var tasbeeh = 0
    
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    
    // used during pause
    @State private var pauseStartTime: Date? = nil
    
    // used outside of pause on click.
    @State private var pauseSinceLastInc: TimeInterval = 0
    @State private var totalPauseInSession: TimeInterval = 0
    
    @State private var totalTimePerClick: TimeInterval = 0
    @State private var timePerClick: TimeInterval = 0
    private var avgTimePerClick: TimeInterval{
        tasbeeh > 0 ? totalTimePerClick / Double(tasbeeh) : 0
    }
    
    private var formatTimePassed: String{
        let minutes = Int(secondsPassed) / 60
        let seconds = Int(secondsPassed) % 60
        
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    
    @State private var timePassedAtPauseString: String = ""
    @State private var timePassedAtPauseDouble: TimeInterval = 0
    
    
    private var totalTime:  Int {
        sharedState.selectedMinutes*60
    }
    private var secondsLeft: TimeInterval {
        (endTime?.timeIntervalSince(Date())) ?? 0.0
    }
    private var secondsPassed: TimeInterval{
        return timerIsActive ? ((Double(totalTime) - secondsLeft)) : 0
    }
    private var tasbeehRate: String{
        let to100 = avgTimePerClick*100
        let minutes = Int(to100) / 60
        let seconds = Int(to100) % 60
        
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    private var showStartStopCondition: Bool{
        (
            !paused &&
            (
                progressFraction >= 1 /*secondsLeft <= 0*/ ||
                (!timerIsActive && sharedState.selectedPage != 2) ||
                (!timerIsActive && sharedState.selectedPage == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0 ))
        )
    }
    
    @State private var progressFraction: CGFloat = 0
    
    @State private var clickStats: [ClickDataModel] = []
        
    @State private var offsetY: CGFloat = 0
    @State private var highestPoint: CGFloat = 0 // Track highest point during drag
    @State private var lowestPoint: CGFloat = 0 // Track lowest point during drag
    let incrementThreshold: CGFloat = 50 // Threshold for tasbeeh increment
    @State private var dragToIncrementBool: Bool = true
    
    @State private var showDragColor: Bool = false
    @State private var myStringOffsetInput: String = ""
    private var GoalOffset: Double{
        Double(myStringOffsetInput) ?? 60.0
    }
    
    
    // Detect scene phase changes (active, inactive, background)
    @Environment(\.scenePhase) var scenePhase
    
    @State private var showNotesModal: Bool = false
    @State private var noteModalText = ""
    @State private var takingNotes: Bool = false
    
    @State private var currentVibrationMode: HapticFeedbackType = .medium
    
    private var debug: Bool = false
    @State private var debug_AddingToPausedTimeString : String = ""
    private var debug_secLeft_secPassed_progressFraction: String{
        "time left: \(roundToTwo(val: secondsLeft)) | secPassed: \(roundToTwo(val: secondsPassed)) | proFra: \(roundToTwo(val: progressFraction))"
    }
    
    private func simulateTasbeehClicks(times: Int) {
        for _ in 1...times {
            incrementTasbeeh()
        }
    }
    
    @State private var inactivityTimer: Timer? = nil
    @State private var timeSinceLastInteraction: TimeInterval = 0
    var inactivityLimit: TimeInterval{
        if tasbeeh > 10 && clickStats.count >= 5 {
            let lastFiveClicks = clickStats.suffix(5) // Get the last 5 elements
            let lastFiveMovingAvg = lastFiveClicks.reduce(0.0) { sum, stat in
                sum + stat.tpc
            } / Double(lastFiveClicks.count) // Calculate the average
            
            return max(lastFiveMovingAvg * 3, 15) // max of triple the moving average or 15
        } else {
            return 20
        }
    }
    @State private var showInactivityAlert = false
    @State private var countDownForAlert = 0
    @State private var stoppedDueToInactivity: Bool = false
    
    @State private var showMantraSheetFromHomePage: Bool = false
    @State private var bruhForNow: String? = ""
    
    @State private var showingDuaPage: Bool = false
    @State private var showingPrayerPage: Bool = false
    
    let prayersOld = [
        PrayerModel(
            prayerName: "FAJR",
            startTimeDate: Date().addingTimeInterval(-3800),
            endTimeDate: Date().addingTimeInterval(-2600)
        ),
        PrayerModel(
            prayerName: "ZUHR",
            startTimeDate: Date().addingTimeInterval(-60),
            endTimeDate: Date().addingTimeInterval(30)
        ),
        PrayerModel(
            prayerName: "ASR",
            startTimeDate: Date().addingTimeInterval(30),
            endTimeDate: Date().addingTimeInterval(200)
        ),
        PrayerModel(
            prayerName: "MAGHRIB",
            startTimeDate: Date().addingTimeInterval(200),
            endTimeDate: Date().addingTimeInterval(260)
        ),
        PrayerModel(
            prayerName: "ISHA",
            startTimeDate: Date().addingTimeInterval(260),
            endTimeDate: Date().addingTimeInterval(300)
        )
    ]
    let prayers = [
        PrayerModel(
            prayerName: "FAJR",
            startTimeDate: todayAt(hour: 6, minute: 23),
            endTimeDate: todayAt(hour: 7, minute: 34)
        ),
        PrayerModel(
            prayerName: "ZUHR",
            startTimeDate: todayAt(hour: 13, minute: 6),
            endTimeDate: todayAt(hour: 16, minute: 56)
        ),
        PrayerModel(
            prayerName: "ASR",
            startTimeDate: todayAt(hour: 16, minute: 56),
            endTimeDate: todayAt(hour: 18, minute: 37)
        ),
        PrayerModel(
            prayerName: "MAGHRIB",
            startTimeDate: todayAt(hour: 18, minute: 37),
            endTimeDate: todayAt(hour: 19, minute: 48)
        ),
        PrayerModel(
            prayerName: "ISHA",
            startTimeDate: todayAt(hour: 19, minute: 48),
            endTimeDate: todayAt(hour: 23, minute: 59)
        )
    ]
    
    
    func inactivityTimerHandler(run: String) {
        if(toggleInactivityTimer){
            switch run{
            case "restart": do {
                print("start inactivity timer with limit of \(inactivityLimit)")
                inactivityTimer?.invalidate() // Invalidate any existing timer
                showInactivityAlert = false // set it to false just to be sure.
                timeSinceLastInteraction = 0 // Reset time since last interaction
                var localCountDown = 11
                
                inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    timeSinceLastInteraction += 1.0
                    if(offsetY != 0) {
                        print("touching screen -- resetting from \(timeSinceLastInteraction) out of  \(inactivityLimit) AND showInactivityAlert = \(showInactivityAlert)")
                        timeSinceLastInteraction = 0
                        showInactivityAlert = false
                    }
                    if timeSinceLastInteraction >= (showDragColor ? 2 : inactivityLimit){ // run if tasbeeh hasnt changed for span of our limit
                        showInactivityAlert = true
                        localCountDown -= 1
                        countDownForAlert = localCountDown
                    }
                    if localCountDown <= 0 {
                        stoppedDueToInactivity = true
                        stopTimer()
                    }
                    
                }
            }
            case "stop": do {
                print("stopping inactivity timer")
                inactivityTimer?.invalidate()
                showInactivityAlert = false
            }
            default:
                print("yo bro invalid use of inactivityTimerHandler func")
            }
        }
        else{
            print("Not tracking inactivity cuz Bool set to \(toggleInactivityTimer)")
        }
    }
    
    private var startCondition: Bool{
        let timeModeCond = (sharedState.selectedPage == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedPage == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedPage == 0)
        return (timeModeCond || countModeCond || freestyleModeCond) && !timerIsActive
    }
    

    
    //--------------------------------------view--------------------------------------
    
    var body: some View {
        ZStack {
            NavigationView{
                ZStack {
                    
                    // the middle
                    ZStack {
                        // the circle's inside (picker or count)
                        if !timerIsActive {
                            // tabview mode selection.
                            TabView (selection: $sharedState.selectedPage) {
                                
                                timeTargetMode(selectedMinutesBinding: $sharedState.selectedMinutes)
                                    .tag(1)
                                
                                freestyleMode()
                                    .tag(0)
                                
                                countTargetMode(targetCount: $sharedState.targetCount, isNumberEntryFocused: _isNumberEntryFocused)
                                    .tag(2)
                            }
                            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Enable paging
                            .frame(width: 200, height: 200) // Match the CircularProgressView size
                            .onChange(of: sharedState.selectedPage) {_, newPage in
                                isNumberEntryFocused = false //Dismiss keyboard when switching pages
                            }
                            .onTapGesture {
                                if(startCondition){
                                    toggleTimer()
                                }
                                isNumberEntryFocused = false //Dismiss keyboard when tabview tapped
                            }
                        } else {
                            TasbeehCountView(tasbeeh: tasbeeh)
                                .onAppear{
                                    paused = false // sometimes appstorage had paused = true. so clear it.
                                    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                                        withAnimation {

                                            if(!paused){
                                                if(sharedState.selectedPage == 1){
                                                    progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
                                                }
                                            }
                                        }
                                        print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)")
                                        if ((progressFraction >= 1) && !paused) {
                                            if(autoStop){
                                                stopTimer()
                                                print("homeboy auto stopped....")
                                                streak += 1 // Increment the streak
                                            }
                                        }
                                    }
                                }
                                .onDisappear {
                                    timer?.invalidate()
                                    timer = nil
                                }
                                .onAppear {
                                    inactivityTimerHandler(run: "restart")
                                }
                                .onChange(of: tasbeeh){_, newTasbeeh in
                                    inactivityTimerHandler(run: "restart")
                                }
                                .onDisappear{
                                    inactivityTimerHandler(run: "stop")
                                }
                                .onChange(of: scenePhase) {_, newScenePhase in
                                    if newScenePhase == .inactive || newScenePhase == .background {
                                        !paused ? togglePause() : ()
                                        print("scenePhase: \(newScenePhase) (session paused? \(paused)")
                                    }
                                }
                            GeometryReader { geometry in
                                VStack {
                                    ZStack {
                                        if(showDragColor){
                                            VStack {
                                                Text("OffsetY: \(offsetY)")
                                                Text("Highest Point: \(highestPoint)")
                                                Text("Lowest Point: \(lowestPoint)")
                                                Text(dragToIncrementBool ? "Condition To Add: \((offsetY - highestPoint) - incrementThreshold)" : "Condition To Set: \((lowestPoint - offsetY) - incrementThreshold/2)")
                                                
                                                Spacer()
                                            }
                                        }
                                        Color("bgColor").opacity(0.001) // Simulate clear color
                                            .frame(width: geometry.size.width, height: geometry.size.height) // Fill the entire geometry
                                            .onTapGesture {
                                                print("Tap gesture detected")
                                                incrementTasbeeh() // Increment on tap
                                            }
                                            .gesture(
                                                DragGesture(minimumDistance: 0) // Set to 0 for immediate tracking
                                                    .onChanged { value in
                                                        // Track drag distance
                                                        offsetY = value.translation.height
                                                        
                                                        // Update highest and lowest points during drag
                                                        if offsetY < highestPoint {
                                                            highestPoint = offsetY
                                                        }
                                                        if offsetY > lowestPoint {
                                                            lowestPoint = offsetY
                                                        }
                                                        
                                                        // Check if dragged down from highest point by a value of incrementThreshold
                                                        if dragToIncrementBool && offsetY - highestPoint > incrementThreshold {
                                                            dragToIncrementBool = false
                                                            incrementTasbeeh()
                                                            lowestPoint = value.translation.height // need to set it otherwise it will always be the lowest point of the entire drag sesh
                                                            // Check if dragged up from lowest point by a value of incrementThreshold/2
                                                        } else if !dragToIncrementBool && lowestPoint - offsetY > incrementThreshold/2 {
                                                            dragToIncrementBool = true
                                                            highestPoint = value.translation.height
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        // Reset offsets after drag ends
                                                        dragToIncrementBool = true
                                                        offsetY = 0
                                                        highestPoint = 0
                                                        lowestPoint = 0
                                                    }
                                            )
                                    }
                                }
                            }
                        }
                        
                        // the circles we see
                        CircularProgressView(progress: (progressFraction))
                            .allowsHitTesting(false) //so taps dont get intercepted.
//                        if(startCondition){
                            Circle()
                                .stroke(lineWidth: 24)
                                .frame(width: 200, height: 200)
//                                .foregroundStyle(Color.green.opacity(0.30))
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
//                                .animation(.spring(), value: startCondition)
                                .animation(.easeInOut(duration: 0.5), value: startCondition)
//                        }
                    }
                    
                    // Pause Screen (background overlay, stats & settings)
                    ZStack {
                        // middle screen when paused
                        pauseStatsAndBG(
                            paused: paused, selectedPage: sharedState.selectedPage, mantra: sharedState.titleForSession,
                            selectedMinutes: sharedState.selectedMinutes, targetCount: sharedState.targetCount,
                            tasbeeh: tasbeeh, timePassedAtPause: timePassedAtPauseString,
                            timePerClick: timePerClick, avgTimePerClick: avgTimePerClick,
                            tasbeehRate: tasbeehRate, togglePause: { togglePause() }, takingNotes: takingNotes
                        )
                        VStack {
                            Spacer()
                            
                            // bottom settings bar when paused
                            VStack {
                                HStack{
                                    AutoStopToggleButton(autoStop: $autoStop)
                                    SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer)
                                    VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
                                    ColorSchemeModeToggleButton(colorModeToggle: $colorModeToggle)
                                }
//                                HStack{
//                                    DebugToggleButton(showDragColor: $showDragColor)
//                                    ExitButton(stopTimer: {stopTimer()})
//                                }
                            }
                            .padding()
                            .background(BlurView(style: .systemUltraThinMaterial))
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 10)
                            .padding(.bottom, 40)
                            .opacity(paused ? 1.0 : 0.0)
                        }
                    }
                    .animation(.easeInOut, value: paused)
                    
                    // Settings & Start/Stop
                    VStack {
                        
                        // The Top Buttons During Session
                        if(timerIsActive){
                            HStack {
                                // Debug Updating Text In View
                                if(debug){
                                    Text(debug_AddingToPausedTimeString)
                                    Text(debug_secLeft_secPassed_progressFraction)
                                }
                                Text("\(progressFraction)")
                                Text("\(sharedState.selectedPage)")
                                
                                // exit button top left when paused
                                if paused{
                                    Button(action: {stopTimer()} ) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray.opacity(0.8))
                                            .padding()
                                            .background(.clear)
                                            .cornerRadius(10)
                                    }
                                    .opacity(paused ? 1.0 : 0.0)
                                }
                                
                                // minus, 100, and notes button when not paused
                                if !paused{
                                    HStack{
                                        TopOfSessionButton( // Minus Button
                                            symbol: "minus", actionToDo: decrementTasbeeh,
                                            paused: paused, togglePause: togglePause)
                                        
                                        TopOfSessionButton( // Plus 100 Button (for testing)
                                            symbol: "infinity", actionToDo: {simulateTasbeehClicks(times: 100)},
                                            paused: paused, togglePause: togglePause)
                                        
                                        TopOfSessionButton( // Add Note Button (new feature coming soon)
                                            symbol: "note", actionToDo: {showNotesModal = true},
                                            paused: paused, togglePause: togglePause)
                                        .sheet(isPresented: $showNotesModal) {
                                            NoteModalView(savedText: $noteModalText, showSheet: $showNotesModal, takingNotes: $takingNotes)
                                        }
                                    }
                                }

                                
                                Spacer()
                                
                                // dynamic pause / play button shown in active session
                                PlayPauseButton(togglePause: togglePause, paused: paused)
                            }
                            .animation(paused ? .easeOut : .easeIn, value: paused)
                            .padding()
                        }
                        // The Top Buttons On Home Screen
                        else{
                            VStack {
                                HStack {
//                                    // button for dua page
//                                    Button(action: {
//                                        triggerSomeVibration(type: .light)
//                                        withAnimation {
//                                            showingDuaPage = true
//                                        }
//                                    }) {
//                                        Image(systemName: "book")
//                                            .font(.system(size: 24))
//                                            .foregroundColor(.gray)
//                                            .padding()
//                                    }
                                    
                                    
                                    // button for maps page
                                    NavigationLink(destination: LocationMapContentView()) {
                                        Image(systemName: "scribble")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray)
                                            .padding()
                                    }

                                    
                                    Spacer()
                                    
                                    // select mantra button
                                    Text("\(sharedState.titleForSession != "" ? sharedState.titleForSession : "Select Mantra")")
                                        .frame(width: 200, height: 50)
                                        .fontDesign(.rounded)
                                        .fontWeight(.thin)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .background(.gray.opacity(0.08))
                                        .cornerRadius(10)
                                        .onTapGesture {
                                            showMantraSheetFromHomePage = true
                                        }
                                        .onChange(of: bruhForNow){
                                            if let newSetMantra = bruhForNow{
                                                sharedState.titleForSession = newSetMantra
                                            }
                                        }
                                        .sheet(isPresented: $showMantraSheetFromHomePage) {
                                            MantraPickerView(isPresented: $showMantraSheetFromHomePage, selectedMantra: $bruhForNow, presentation: [.large])
                                        }
                                    
                                    
                                    Spacer()
                                    // buton for prayer page
                                    Button(action: {
                                        triggerSomeVibration(type: .light)
                                        withAnimation {
                                            showingPrayerPage = true
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray)
                                            .padding()
                                    }
 
                                }
                                .padding()

                                Spacer()
                            }
                        }
                        
                        Spacer()
                        
                        // Setting Toggles on Home Screen
//                        if(!timerIsActive){
//                            HStack{
//                                AutoStopToggleButton(autoStop: $autoStop)
//                                SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer)
//                                VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
//                                ColorSchemeModeToggleButton(modeToggle: $modeToggle)
//                            }
//                            .padding(.bottom)
//                        }
                        // The Bottom Inactivity Alert During Session
                        if timerIsActive{
                            inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                        }
                        
                        //FIXME: Changed logic quickly to only be stop button. Need to update naming and vars
                        // The Start/Stop Button. (shown in both Home Screen and Active Session)
                        if(showStartStopCondition && timerIsActive){
                            startStopButton(timerIsActive: timerIsActive, toggleTimer: toggleTimer)
                        }
                    }
                    
                    VStack{
                        Color.black.opacity(toggleInactivityTimer ? 0.7 : 0)
                            .allowsHitTesting(false)
                            .edgesIgnoringSafeArea(.all)
                    }
                    .animation(.easeInOut(duration: 0.5), value: toggleInactivityTimer)
                    
                }
                .frame(maxWidth: .infinity) // expand to be the whole page (to make it tappable)
                .background(
                    Color.init("bgColor") // Dynamic color for dark or light mode
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            isNumberEntryFocused = false // Dismiss keyboard when tapping on background
                        }
                )
                .navigationBarHidden(true) // Hides the default navigation bar
            }
            .onChange(of: tasbeeh){_, newTasbeeh in
                if(sharedState.selectedPage == 0){
                    //made it so that it never actually gets to 100% (cuz auto stop ends at 100%)
                    let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
                    progressFraction = CGFloat(Int(numerator))/CGFloat(Int(100))
                    print("0: \(sharedState.selectedPage) profra: \(progressFraction)")
                        print("top: \(CGFloat(Int(numerator))) bot: \(CGFloat(Int(100)))")
                } else if (sharedState.selectedPage == 2){
                    print("in 2: \(tasbeeh)")
                    progressFraction = CGFloat(tasbeeh)/CGFloat(Int(sharedState.targetCount) ?? 0)
                    print("2: \(sharedState.selectedPage) profra: \(progressFraction)")
                    print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(sharedState.targetCount) ?? 0))")

                }
            }
            if(showingDuaPage){
                DuaPageView(showingDuaPageBool: $showingDuaPage)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
            if showingPrayerPage {
                PrayerTimesView()
                .transition(.blurReplace.animation(.easeInOut(duration: 0.4)))
                    .zIndex(1) // Ensure it appears above other content
            }
        }
        .onAppear {
            if autoStart && !timerIsActive {
                startTimer()
            }
        }
        .preferredColorScheme(colorModeToggle ? .dark : .light)

        
}
//--------------------------------------functions--------------------------------------
    
    
    private func toggleTimer() {
        if timerIsActive {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        // Reset necessary variables for a new session
        tasbeeh = 0
        
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: sharedState.selectedMinutes, to: startTime!)
        
        clickStats = []
        
        // Mark the timer as active and open the view.
        timerIsActive = true
        triggerSomeVibration(type: .success)
        
        // Start the Timer for visual updates
//        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
//            withAnimation {
//
//                if(!paused){
//                    if(sharedState.selectedPage == 1){
//                        progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
////                        print("1: \(selectedPage) profra: \(progressFraction)")
////                        print("top: \(CGFloat(Int(secondsPassed))) bot: \(TimeInterval(totalTime))")
//                    }
////                    if(sharedState.selectedPage == 0){
////                        //made it so that it never actually gets to 100/100 or else it can auto stop if toggled on.
//////                        print("in 0: \(tasbeeh)")
////                        let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
//////                        print("in 0: \(tasbeeh)" + " | numerator: \(numerator)")
////                        progressFraction = CGFloat(Int(numerator))/CGFloat(Int(100))
//////                        print("0: \(selectedPage) profra: \(progressFraction)")
//////                        print("top: \(CGFloat(Int(numerator))) bot: \(CGFloat(Int(100)))")
////                    } else if(sharedState.selectedPage == 1){
////                        progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
//////                        print("1: \(selectedPage) profra: \(progressFraction)")
//////                        print("top: \(CGFloat(Int(secondsPassed))) bot: \(TimeInterval(totalTime))")
////                    } else if (sharedState.selectedPage == 2){
////                        print("in 2: \(tasbeeh)")
////                        progressFraction = CGFloat(tasbeeh)/CGFloat(Int(sharedState.targetCount) ?? 0)
//////                        print("2: \(selectedPage) profra: \(progressFraction)")
//////                        print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(targetCount) ?? 0))")
////
////                    }
//                }
//            }
//            print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)")
//            if ((progressFraction >= 1) && !paused) {
//                if(autoStop){
//                    stopTimer()
//                    print("homeboy auto stopped....")
//                    streak += 1 // Increment the streak
//                }
//            }
//        }
        
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change

    }
    
    private func stopTimer() {
        // Generate session data after the timer stops
        let placeholderTitle: String = (sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled")
        
//        var sessionDuration = formatTimePassed
        
//        if(!stoppedDueToInactivity){
////            let placeholderTitleForInactiveSesh: String = "???"
//            stoppedDueToInactivity = false // toggle it back to false
//        }
        var secondsToReport: TimeInterval
        if(paused){
            secondsToReport = timePassedAtPauseDouble
        }
        else {
            secondsToReport = secondsPassed
        }
        
        if(tasbeeh > 0){
            let item = SessionDataModel(
                title: placeholderTitle, sessionMode: sharedState.selectedPage,
                targetMin: sharedState.selectedMinutes, targetCount: Int(sharedState.targetCount) ?? 0,
                totalCount: tasbeeh, startTime: startTime ?? Date(),
                secondsPassed: secondsToReport,
                avgTimePerClick: avgTimePerClick, tasbeehRate: tasbeehRate,
                clickStats: clickStats)
            // New Way: adding to SwiftData model container.
            print("adding a session card")
            context.insert(item)

        }
        
        // clear the title
        sharedState.titleForSession = ""
        
        // Stop and invalidate the timer
        timer?.invalidate()
        timer = nil
        
        // Reset all state variables to clean up the session
        timerIsActive = false

        endTime = nil
        startTime = nil
        
        totalTimePerClick = 0
        timePerClick = 0
        
        pauseSinceLastInc = 0
        totalPauseInSession = 0
        
        progressFraction = 0
        
        paused = false
        
        sharedState.targetCount = ""
        
        noteModalText = ""
        
        !stoppedDueToInactivity ? triggerSomeVibration(type: .vibrate) : ()
        
        stoppedDueToInactivity = false
        
        inactivityTimerHandler(run: "stop")
        
        toggleInactivityTimer = false
        
        isPresented = false // this will change the binding to close the full cover sheet


    }
    
    private func togglePause() {
        paused.toggle()
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change
        triggerSomeVibration(type: .medium)
        if(paused){
            inactivityTimerHandler(run: "stop")
            pauseStartTime = Date()
            timePassedAtPauseDouble = secondsPassed
            timePassedAtPauseString = formatTimePassed // cant use calc var bc keeps changing if view ever updated
        }else{
            inactivityTimerHandler(run: "restart")
            let thisPauseSesh = Date().timeIntervalSince(pauseStartTime ?? Date())
            pauseSinceLastInc += thisPauseSesh
            totalPauseInSession += thisPauseSesh
            endTime = endTime?.addingTimeInterval(thisPauseSesh)
        }
        /*
         - store time at pause (pauseStartTime)
         - calculate time at resume (thisPauseSesh)
         - keep track of how many pauses since last increment (pauseSinceLastInc)
            > (use this to subtract pause time from tPC when incrementing)
         - add to totalPauseInSession
            > (only needed for reset so we can calculate tpc on first click)
         - extend endTime by thisPauseSesh
            
         move end time.
        
         */
    }
    
    private func incrementTasbeeh() {
        
        if(paused){return} // shouldnt happen but just to be safe.
        
        let rightNow = Date()
    
        let timePerClick = rightNow.timeIntervalSince(
            (tasbeeh > 0) ?
                clickStats[tasbeeh-1].date : startTime ?? Date()
        ) - pauseSinceLastInc
        
        totalTimePerClick += timePerClick
        self.timePerClick = timePerClick
        
        /// debug text to demonstrate how paused time is accounted for
        if(debug){
            if(pauseSinceLastInc != 0){
                debug_AddingToPausedTimeString = "accounted \(roundToTwo(val: pauseSinceLastInc)) time"
            }
            else{
                debug_AddingToPausedTimeString = "no pause"
            }
        }

        let newClickData = ClickDataModel(date: rightNow, pauseTime: pauseSinceLastInc, tpc: timePerClick)
        clickStats.append(newClickData)

        
        pauseSinceLastInc = 0
        
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        print("tasbeeh on inc:  \(tasbeeh)")
        
            
        triggerSomeVibration(type: currentVibrationMode)
        
        onFinishTasbeeh()
        WidgetCenter.shared.reloadAllTimelines()
        
    }
    
    private func decrementTasbeeh() {
        if timerIsActive {
            
            if !clickStats.isEmpty{
                let lastClicksData = clickStats[clickStats.count-1]
                let oldPauseTime = pauseSinceLastInc
                totalTimePerClick -= lastClicksData.tpc
                pauseSinceLastInc += lastClicksData.pauseTime
                clickStats.removeLast()
                
                /// debug text to demonstrate how paused time is accounted for
                if(debug){
                    if(pauseSinceLastInc != 0){
                        debug_AddingToPausedTimeString = "\(roundToTwo(val: oldPauseTime)) to \(roundToTwo(val: pauseSinceLastInc)) (+\(roundToTwo(val: lastClicksData.pauseTime)))"
                    }
                }
            }
            
//            print("dec")
//            print(clickStats)
            triggerSomeVibration(type: .rigid)
            tasbeeh = max(tasbeeh - 1, 0) // Adjust minimum value as needed
            
            WidgetCenter.shared.reloadAllTimelines()

        }
    }
    
    private func resetTasbeeh() {
        if (timerIsActive){
            triggerSomeVibration(type: .error)
            tasbeeh = 0
            clickStats = []
            totalTimePerClick = 0
            pauseSinceLastInc = totalPauseInSession
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
        
    private func onFinishTasbeeh(){
        if(tasbeeh % 100 == 0 && tasbeeh != 0){
            triggerSomeVibration(type: .error)
        }
    }
    
}


#Preview {
    @Previewable @StateObject var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool, autoStart: true)
        .modelContainer(for: Item.self, inMemory: true)
//        .environmentObject(sharedState) // Inject shared state into the environment
}



/*
 Current Improvement Focus:
 
 Improvements needed:
 - break it apart. make it two diff pages.
 - make MantraModel hold all information regarding total count
 */
