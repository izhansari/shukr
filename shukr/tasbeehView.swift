import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer
import Foundation


struct tasbeehView: View {
//    let autoStart: Bool  // New parameter to auto-start the timer
    @Binding var isPresented: Bool
    
    init(isPresented: Binding<Bool>/*, autoStart: Bool*/) {
        self._isPresented = isPresented
//        self.autoStart = autoStart
    }
    
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
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
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5
    
    // State properties
    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    @State private var autoStop = true
    @State private var paused = false
    @State private var tasbeeh = 0
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var pauseStartTime: Date? = nil
    @State private var pauseSinceLastInc: TimeInterval = 0
    @State private var totalPauseInSession: TimeInterval = 0
//    @State private var totalTimePerClick: TimeInterval = 0
//    @State private var timeePerClick: TimeInterval = 0
    @State private var timePassedAtPauseString: String = ""
    @State private var timePassedAtPauseDouble: TimeInterval = 0
    @State private var progressFraction: CGFloat = 0
    @State private var clickStats: [ClickDataModel] = []
    @State private var offsetY: CGFloat = 0
    @State private var highestPoint: CGFloat = 0 // Track highest point during drag
    @State private var lowestPoint: CGFloat = 0 // Track lowest point during drag
    @State private var dragToIncrementBool: Bool = true
//    @State private var showDragColor: Bool = false
//    @State private var myStringOffsetInput: String = ""
    @State private var showNotesModal: Bool = false
    @State private var noteModalText = ""
    @State private var takingNotes: Bool = false
    @State private var currentVibrationMode: HapticFeedbackType = .medium
    @State private var debug_AddingToPausedTimeString : String = ""
    @State private var inactivityTimer: Timer? = nil
    @State private var timeSinceLastInteraction: TimeInterval = 0
    @State private var showInactivityAlert = false
    @State private var countDownForAlert = 0
    @State private var stoppedDueToInactivity: Bool = false
//    @State private var showMantraSheetFromHomePage: Bool = false
//    @State private var bruhForNow: String? = ""
    @State private var newAvrgTimePerClick: TimeInterval = 0 //calculated on increment and decrement by secondsPassed / tasbeeh

    
//    private var avgTimePerClick: TimeInterval{
//        tasbeeh > 0 ? totalTimePerClick / Double(tasbeeh) : 0
//    }
    private var newOne: TimeInterval{
        tasbeeh > 0 ? secondsPassed / Double(tasbeeh) : 0
    }
    
    private var formatTimePassed: String{
        let minutes = Int(secondsPassed) / 60
        let seconds = Int(secondsPassed) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    
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
        let to100 = newAvrgTimePerClick*100
        let minutes = Int(to100) / 60
        let seconds = Int(to100) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    
    private var showStartStopCondition: Bool{
        ( !paused && (
            progressFraction >= 1 /*secondsLeft <= 0*/ ||
            (!timerIsActive && sharedState.selectedMode != 2) ||
            (!timerIsActive && sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0 ))
        )
    }

    let incrementThreshold: CGFloat = 50 // Threshold for tasbeeh increment
    
//    private var GoalOffset: Double{
//        Double(myStringOffsetInput) ?? 60.0
//    }
    
    private var debug: Bool = true
    
    private var debug_secLeft_secPassed_progressFraction: String{
        "time left: \(roundToTwo(val: secondsLeft)) | secPassed: \(roundToTwo(val: secondsPassed)) | proFra: \(roundToTwo(val: progressFraction))"
    }
    
    private var debug_avgTPC: String{
        "newOne: \(roundToTwo(val: newAvrgTimePerClick))"
    }
    
    private func simulateTasbeehClicks(times: Int) {
        for _ in 1...times {
            incrementTasbeeh()
        }
    }
    
    var inactivityLimit: TimeInterval{
        if tasbeeh > 10{
            return max(newAvrgTimePerClick * 3, 10) // max of triple the average tpc or
        } else {
            return 20
        }
        
//        if tasbeeh > 10 && clickStats.count >= 5 {
//            let lastFiveClicks = clickStats.suffix(5) // Get the last 5 elements
//            let lastFiveMovingAvg = lastFiveClicks.reduce(0.0) { sum, stat in
//                sum + stat.tpc
//            } / Double(lastFiveClicks.count) // Calculate the average
//            
//            return max(lastFiveMovingAvg * 3, 15) // max of triple the moving average or 15
//        } else {
//            return 20
//        }
    }    
    
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
                    if timeSinceLastInteraction >= inactivityLimit{ // run if tasbeeh hasnt changed for span of our limit
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
        let timeModeCond = (sharedState.selectedMode == 1 && sharedState.selectedMinutes != 0)
        let countModeCond = (sharedState.selectedMode == 2 && (1...10000) ~= Int(sharedState.targetCount) ?? 0)
        let freestyleModeCond = (sharedState.selectedMode == 0)
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
                        TasbeehCountView(tasbeeh: tasbeeh)
                            .onAppear{
                                paused = false // sometimes appstorage had paused = true. so clear it.
                                
                                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                                
                                    withAnimation {
                                        if !paused && (sharedState.selectedMode == 1){
                                            progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
                                        }
                                    }
                                   
                                    // print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)") // for debugging
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
//                                    if(showDragColor){
//                                        VStack {
//                                            Text("OffsetY: \(offsetY)")
//                                            Text("Highest Point: \(highestPoint)")
//                                            Text("Lowest Point: \(lowestPoint)")
//                                            Text(dragToIncrementBool ? "Condition To Add: \((offsetY - highestPoint) - incrementThreshold)" : "Condition To Set: \((lowestPoint - offsetY) - incrementThreshold/2)")
//                                            
//                                            Spacer()
//                                        }
//                                    }
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
                            paused: paused, selectedPage: sharedState.selectedMode, mantra: sharedState.titleForSession,
                            selectedMinutes: sharedState.selectedMinutes, targetCount: sharedState.targetCount,
                            tasbeeh: tasbeeh, timePassedAtPause: timePassedAtPauseString,
                            avgTimePerClick: newAvrgTimePerClick,
                            tasbeehRate: tasbeehRate, togglePause: { togglePause() }, takingNotes: takingNotes
                        )
                        VStack {
                            Spacer()
                            
                            // bottom settings bar when paused
                            VStack {
                                if(toggleInactivityTimer){
                                    Slider(value: $inactivityDimmer,
                                           in: 0...1.0)
                                    .frame(width: 250)
                                    .padding()
                                }
                                HStack{
                                    AutoStopToggleButton(autoStop: $autoStop)
                                    SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer, colorModeToggle: $colorModeToggle)
                                    VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
                                    ColorSchemeModeToggleButton(colorModeToggle: $colorModeToggle)
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
                        
                        // The Top Buttons During Session
                        HStack {
                            // exit button top left when paused
                            if paused{
                                Button(action: {stopTimer()} ) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.red.opacity(0.8))
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
                        
                        // Debug Updating Text In View
                        if(debug){
                            Text(debug_AddingToPausedTimeString)
                            Text(debug_secLeft_secPassed_progressFraction)
                            Text(debug_avgTPC)
                        }
                        
                        Spacer()
                                                
                        //FIXME: Changed logic quickly to only be stop button. Need to update naming and vars
                        // The Start/Stop Button. (shown in both Home Screen and Active Session)
                        if(showStartStopCondition && timerIsActive){
                            startStopButton(timerIsActive: timerIsActive, toggleTimer: toggleTimer)
                        }
                    }
                    
                    // adding a dark tint for when they click the sleep mode.
                    ZStack{
                        Color.black.opacity(toggleInactivityTimer ? ((1-inactivityDimmer) * 0.9) : 0)
                            .allowsHitTesting(false)
                            .edgesIgnoringSafeArea(.all)
                        
                        // The Bottom Inactivity Alert During Session
                        VStack{
                            Spacer()
                            inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                        }
                            .zIndex(1)
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
                if(sharedState.selectedMode == 0){
                    //made it so that it never actually gets to 100% (cuz auto stop ends at 100%)
                    let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
                    progressFraction = CGFloat(Int(numerator))/CGFloat(Int(100))
                    print("0: \(sharedState.selectedMode) profra: \(progressFraction)")
                    print("top: \(CGFloat(Int(numerator))) bot: \(CGFloat(Int(100)))")
                } else if (sharedState.selectedMode == 2){
                    print("in 2: \(tasbeeh)")
                    progressFraction = CGFloat(tasbeeh)/CGFloat(Int(sharedState.targetCount) ?? 0)
                    print("2: \(sharedState.selectedMode) profra: \(progressFraction)")
                    print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(sharedState.targetCount) ?? 0))")
                    
                }
            }
        }
        .onAppear {
            startTimer()
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
        
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change

    }
    
    private func stopTimer() {
        // Generate session data after the timer stops
        let placeholderTitle: String = (sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled")
        
        var secondsToReport: TimeInterval
        if(paused){
            secondsToReport = timePassedAtPauseDouble
        }
        else {
            secondsToReport = secondsPassed
        }
        
        if(tasbeeh > 0){
            let item = SessionDataModel(
                title: placeholderTitle, sessionMode: sharedState.selectedMode,
                targetMin: sharedState.selectedMinutes, targetCount: Int(sharedState.targetCount) ?? 0,
                totalCount: tasbeeh, startTime: startTime ?? Date(),
                secondsPassed: secondsToReport,
                avgTimePerClick: newAvrgTimePerClick, tasbeehRate: tasbeehRate,
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
        
//        totalTimePerClick = 0
//        timeePerClick = 0
        
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
        
//        totalTimePerClick += timePerClick
//        self.timeePerClick = timePerClick
                
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
        
        newAvrgTimePerClick = (tasbeeh > 0 ? (secondsPassed / Double(tasbeeh)) : 0)
        
        triggerSomeVibration(type: currentVibrationMode)
        
        onFinishTasbeeh()
        WidgetCenter.shared.reloadAllTimelines()
        
    }
    
    private func decrementTasbeeh() {
        if timerIsActive {
            
            if !clickStats.isEmpty{
                let lastClicksData = clickStats[clickStats.count-1]
                let oldPauseTime = pauseSinceLastInc
//                totalTimePerClick -= lastClicksData.tpc
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
            newAvrgTimePerClick = (tasbeeh > 0 ? (secondsPassed / Double(tasbeeh)) : 0)

            WidgetCenter.shared.reloadAllTimelines()

        }
    }
    
    private func resetTasbeeh() {
        if (timerIsActive){
            triggerSomeVibration(type: .error)
            tasbeeh = 0
            clickStats = []
//            totalTimePerClick = 0
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


//#Preview {
//    @Previewable @StateObject var sharedState = SharedStateClass()
//    @Previewable @State var dummyBool: Bool = true
//
//    tasbeehView(isPresented: $dummyBool, autoStart: true)
//        .modelContainer(for: Item.self, inMemory: true)
//        .environmentObject(sharedState) // Inject shared state into the environment
//}



/*
 Current Improvement Focus:
 
 Improvements needed:
 - break it apart. make it two diff pages.
 - make MantraModel hold all information regarding total count
 */
