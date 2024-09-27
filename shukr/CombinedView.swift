import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer
import Foundation


struct CombinedView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessionItems: [SessionDataModel]

    // AppStorage properties
    @AppStorage("count", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var tasbeeh: Int = 10
    @AppStorage("streak") var streak = 0
    @AppStorage("autoStop", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var autoStop = true
    @AppStorage("vibrateToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var vibrateToggle = true
    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var modeToggle = false
    @AppStorage("paused", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var paused = false
    @AppStorage("inactivityToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var toggleInactivityTimer = false
    
    // State properties
    @FocusState private var isNumberEntryFocused
    
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    
    @State private var selectedMinutes = 1
    
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
    
    @State private var timePassedAtPause: String = ""
    
    private var totalTime:  Int {
        selectedMinutes*60
    }
    private var secondsLeft: TimeInterval {
        (endTime?.timeIntervalSince(Date())) ?? 0.0
    }
    private var secondsPassed: TimeInterval{
        timerIsActive ? ((Double(totalTime) - secondsLeft)) : 0
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
            selectedPage != 3 &&
            (
                progressFraction >= 1 /*secondsLeft <= 0*/ ||
                (!timerIsActive && selectedPage != 2) ||
                (!timerIsActive && selectedPage == 2 && (1...10000) ~= Int(targetCount) ?? 0 ))
        )
    }
    
    @State private var progressFraction: CGFloat = 0
    
//    typealias newClickData = (date: Date, pauseTime: TimeInterval, tpc: TimeInterval)
//    @State private var old_clickStats: [newClickData] = []
    
    @State private var clickStats: [ClickDataModel] = []
    
//    @State private var holdTimer: Timer? = nil
//    @State private var holdDuration: Double = 0
    
    @State private var selectedPage = 1 // Default to page 2 (index 1)
    @State private var targetCount: String = ""
    
    @State private var offsetY: CGFloat = 0
    @State private var dragToIncrementBool: Bool = true
    @State private var dragSetting: Bool = true
    @State private var showDragColor: Bool = false
    @State private var myStringOffsetInput: String = ""
    private var InputOffsetY: Double{
        Double(myStringOffsetInput) ?? 60.0
    }
    
//    @State private var sessions: [SessionData] = []
    
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
                        showInactivityAlert = true // Show the alert after 5 minutes
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
    
    //--------------------------------------view--------------------------------------
    
    var body: some View {
        NavigationView{
            ZStack {
                
                // the middle
                ZStack {
                    //2. the circle's inside (picker or count)
                    if timerIsActive {
                        TasbeehCountView(tasbeeh: tasbeeh)
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
                                ScrollView(.vertical, showsIndicators: false) {
                                    ZStack {
                                        
                                        if(!showDragColor){
                                            Color("bgColor").opacity(0.001) // doesnt like clear, so looks clear
                                                .frame(width: geometry.size.width, height: 1000) // Set height larger than the screen
                                        }else{
                                            //for testing
                                            if(offsetY > CGFloat(InputOffsetY)){
                                                Color.green.opacity(0.1)
                                                    .frame(width: geometry.size.width, height: 1000)
                                            } else{
                                                Color.red.opacity(0.1)
                                                    .frame(width: geometry.size.width, height: 1000)
                                            }
                                        }
                                    }
                                    .onTapGesture {
                                        incrementTasbeeh()
                                    }
                                    .offset(y: offsetY)
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            offsetY = value.translation.height
                                            
                                            // Trigger increment when user swipes down more than 50 points
                                            if offsetY > CGFloat(InputOffsetY) {
                                                dragToIncrementBool && dragSetting ? incrementTasbeeh() : ()
                                                dragToIncrementBool = false
                                            }
                                            else {
                                                dragToIncrementBool = true // keep this if you want continuous dragging
                                            }
                                        }
                                        .onEnded { _ in
                                            offsetY = 0 // Reset the offset after the swipe gesture ends
                                            dragToIncrementBool = true
                                        }
                                    )
                                }
                            }
                            .frame(height: geometry.size.height)
                            .background(Color.clear)
                        }
                        
                    } else {
                        // the middle with a scrollable view
                        TabView (selection: $selectedPage) {
                            freestyleMode()
                                .tag(0)
                            
                            timeTargetMode(selectedMinutesBinding: $selectedMinutes)
                                .tag(1)
                            
                            countTargetMode(targetCount: $targetCount, isNumberEntryFocused: _isNumberEntryFocused)
                                .tag(2)
                            
                            inputOffsetSubView(targetCount: $myStringOffsetInput, isNumberEntryFocused: _isNumberEntryFocused)
                                .tag(3)
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Enable paging
                        .frame(width: 200, height: 200) // Match the CircularProgressView size
                        .onChange(of: selectedPage) {_, newPage in
                            isNumberEntryFocused = false //Dismiss keyboard when switching pages
                            //                        debug ? print("User is on page: \(newPage)") : ()
                        }
                        .onTapGesture {
                            isNumberEntryFocused = false //Dismiss keyboard when tabview tapped
                            //                        debug ? print("hit tab view. isnef = \(isNumberEntryFocused)") : ()
                            
                        }
                    }
                    
                    //1. the circle
                    CircularProgressView(progress: (progressFraction))
                        .allowsHitTesting(false) //so taps dont get intercepted.
                }
                
                // Pause Screen (background overlay, stats & settings)
                ZStack {
                    pauseStatsAndBG(
                        paused: paused, selectedPage: selectedPage,
                        selectedMinutes: selectedMinutes, targetCount: targetCount,
                        tasbeeh: tasbeeh, timePassedAtPause: timePassedAtPause,
                        timePerClick: timePerClick, avgTimePerClick: avgTimePerClick,
                        tasbeehRate: tasbeehRate, togglePause: { togglePause() }, takingNotes: takingNotes
                    )
                    VStack {
                        Spacer()
                        
                        VStack { // pause settings (bottom bar in the pause view)
                            HStack{
                                AutoStopToggleButton(autoStop: $autoStop)
                                SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer)
                                VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
                                ColorSchemeModeToggleButton(modeToggle: $modeToggle)
                            }
                            HStack{
                                DebugToggleButton(showDragColor: $showDragColor)
                                ExitButon(stopTimer: {stopTimer()})
                            }
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
                    
                    //0. buttons
                    if(timerIsActive){
                        HStack {
                            // Debug Updating Text In View
                            if(debug){
                                Text(debug_AddingToPausedTimeString)
                                Text(debug_secLeft_secPassed_progressFraction)
                            }
                            
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
                            
//                            ExitButon(stopTimer: {stopTimer()})
//                            .padding()
//                            .opacity(paused ? 1.0 : 0.0)

                            
                            Spacer()
                            
                            // Play Button
                            PlayPauseButton(togglePause: togglePause, paused: paused)
                        }
                        .animation(paused ? .easeOut : .easeIn, value: paused)
                        .padding()
                    }
                    else{
                        VStack {
                            HStack {
                                Spacer()
                                NavigationLink(destination: HistoryPageView()) {
                                    Image(systemName: "rectangle.stack")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding()
                                }
                            }
                            Spacer()
                        }
                    }
                    
                    Spacer()
                    
                    // 1. setting toggles on home screen
                    if(!timerIsActive){
                        HStack{
                            AutoStopToggleButton(autoStop: $autoStop)
                            SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer)
                            VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
                            ColorSchemeModeToggleButton(modeToggle: $modeToggle)
                        }
                        .padding(.bottom)
                    }else{
                        inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                    }
                    
                    //2. start/stop button. (both - Home Screen & In Session)
                    if(showStartStopCondition){
                        startStopButton(timerIsActive: timerIsActive, toggleTimer: toggleTimer)
                    }
                }
                
            }
            .frame(maxWidth: .infinity) // expand to be the whole page (to make it tappable)
            .background(
                Color.init("bgColor") // Dynamic color for dark or light mode
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        isNumberEntryFocused = false // Dismiss keyboard when tapping on background
                    }
            )
            .onAppear{
                paused = false // sometimes appstorage had paused = true. so clear it.
            }
            .onDisappear {
                //            stopTimer() // i think useless cuz view is the main app and NEVER disappears...
            }
            .navigationBarHidden(true) // Hides the default navigation bar
        }
        .preferredColorScheme(modeToggle ? .dark : .light)
        
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
        endTime = Calendar.current.date(byAdding: .minute, value: selectedMinutes, to: startTime!)
        
        clickStats = []
        
        // Mark the timer as active and open the view.
        timerIsActive = true
        triggerSomeVibration(type: .success)
        
        // Start the Timer for visual updates
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation {

                if(!paused){
                    if(selectedPage == 0){
                        //made it so that it never actually gets to 100/100 or else it can auto stop if toggled on.
                        let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
                        progressFraction = CGFloat(Int(numerator))/CGFloat(Int(100))
//                        print("0: \(selectedPage) profra: \(progressFraction)")
//                        print("top: \(CGFloat(Int(numerator))) bot: \(CGFloat(Int(100)))")
                    } else if(selectedPage == 1){
                        progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
//                        print("1: \(selectedPage) profra: \(progressFraction)")
//                        print("top: \(CGFloat(Int(secondsPassed))) bot: \(TimeInterval(totalTime))")
                    } else if (selectedPage == 2){
                        progressFraction = CGFloat(tasbeeh)/CGFloat(Int(targetCount) ?? 0)
//                        print("2: \(selectedPage) profra: \(progressFraction)")
//                        print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(targetCount) ?? 0))")

                    }
                }
            }
            if ((progressFraction >= 1) && !paused) {
                if(autoStop){
                    stopTimer()
                    print("homeboy auto stopped....")
                    streak += 1 // Increment the streak
                }
            }
        }
        
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change

    }
    
    private func stopTimer() {
        // Generate session data after the timer stops
        let placeholderTitle: String = "(placeholder)"
        
        var sessionDuration = ""
        if (stoppedDueToInactivity){
            sessionDuration = formatSecToMinAndSec(clickStats.last?.date.timeIntervalSince(startTime ?? Date()) ?? 0)
        } else {
            sessionDuration = formatTimePassed
        }
        
//        if(!stoppedDueToInactivity){
////            let placeholderTitleForInactiveSesh: String = "???"
//            stoppedDueToInactivity = false // toggle it back to false
//        }
        
        if(tasbeeh > 0){
//            let newSession = generateSessionData(
//                tasbeeh: tasbeeh,
//                startTime: startTime ?? Date(),
//                secondsPassed: secondsPassed,
//                formatTimePassed: formatTimePassed,
//                selectedPage: selectedPage,
//                avgTimePerClick: avgTimePerClick,
//                tasbeehRate: tasbeehRate,
//                targetCount: targetCount,
//                selectedMinutes: selectedMinutes,
//                clickStats: clickStats,
//                title: placeholderTitle
//            )
//            // Old way: Add the new session to the list
//            print("adding a session card")
//            sessions.append(newSession)
            
            let item = SessionDataModel(
                title: placeholderTitle, sessionMode: selectedPage,
                targetMin: selectedMinutes, targetCount: Int(targetCount) ?? 0,
                totalCount: tasbeeh, startTime: startTime ?? Date(),
                secondsPassed: secondsPassed, sessionDuration: sessionDuration,
                avgTimePerClick: avgTimePerClick, tasbeehRate: tasbeehRate,
                clickStats: clickStats)
            // New Way: adding to SwiftData model container.
            print("adding a session card")
            context.insert(item)

        }
        
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
        
        targetCount = ""
        
        noteModalText = ""
        
        !stoppedDueToInactivity ? triggerSomeVibration(type: .vibrate) : ()
        
        stoppedDueToInactivity = false
        
        inactivityTimerHandler(run: "stop")

    }
    
    private func togglePause() {
        paused.toggle()
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change
        triggerSomeVibration(type: .medium)
        if(paused){
            inactivityTimerHandler(run: "stop")
            pauseStartTime = Date()
            timePassedAtPause = formatTimePassed // cant use calculated var cuz it keeps changing if view ever updated
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

        //vvv old way of storing... vvv
//        let newData: newClickData = (date: rightNow, pauseTime: pauseSinceLastInc, tpc: timePerClick)
//        clickStats.append(newData)

        let newClickData = ClickDataModel(date: rightNow, pauseTime: pauseSinceLastInc, tpc: timePerClick)
        clickStats.append(newClickData)

        
        pauseSinceLastInc = 0
        
//        print("inc")
//        print(clickStats)
        
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        
            
//        triggerSomeVibration(type: .medium)
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
    CombinedView()
        .modelContainer(for: Item.self, inMemory: true)
}




//okay game plan
/*
 
 next stuff to tackle
 
 TODO:
 - fix widget to work with code. (currently goes out of bounds on clickStats[])
 - Make a max on the number entry to be 10k.
 - CRUD historical session cards: store each session as its own card to see session data.
 - add notes section to the historical session card
 
 DONE:
 - make it so every 5 tasbeehs make a purple circle instead of gray. otherwise it goes out of the view when theres like 10...
 - Swipe to use different tasbeeh modes.
    > right now its a time based mode. (progressFraction out of target time)
    > add count target mode (progressFraction out of target count)
    > add freestyle mode. (progressFraction out of 100)
 */
