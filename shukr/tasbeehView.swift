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
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
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
//    @AppStorage("paused", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    var paused = false
    @AppStorage("inactivityToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var toggleInactivityTimer = false
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5

    @AppStorage("vibrateToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var vibrateToggle = true
    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var colorModeToggle = false
    @AppStorage("currentVibrationMode") private var currentVibrationMode: HapticFeedbackType = .medium

    
    // State properties
    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timerbb: Timer? = nil
    @State private var paused = false
    @State private var tasbeeh = 0
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var pauseStartTime: Date? = nil
    @State private var autoStop = true
//    @State private var currentVibrationMode: HapticFeedbackType = .medium

    @State private var timePassedAtPauseString: String = ""
    @State private var secsPassedAtPause: TimeInterval = 0
    @State private var progressFraction: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var highestPoint: CGFloat = 0 // Track highest point during drag
    @State private var lowestPoint: CGFloat = 0 // Track lowest point during drag
    @State private var dragToIncrementBool: Bool = true
    @State private var showNotesModal: Bool = false
    @State private var noteModalText = ""
    @State private var takingNotes: Bool = false
    @State private var inactivityTimer: Timer? = nil
    @State private var timeSinceLastInteraction: TimeInterval = 0
    @State private var showInactivityAlert = false
    @State private var countDownForAlert = 0
    @State private var stoppedDueToInactivity: Bool = false
    @State private var newAvrgTPC: TimeInterval = 0 //calculated on increment and decrement by secondsPassed / tasbeeh
    @State private var totalPauseInSession: Double = 0
    @State private var secsToReport: TimeInterval = 0
    @State private var showMantraSheetFromResultsPage = false
    @State private var savedSession: SessionDataModel? = nil
    @State private var isCurrentlyDragging = false
    
    @State private var sessionSequence: [(title: String, targetCount: Int)] = []
    @State private var postNamazSequence: [(title: String, targetCount: Int)] = [
                (title: "Subhanallah", targetCount: 33),
                (title: "Alhamdulillah", targetCount: 33),
                (title: "Allahu Akbar", targetCount: 34)
            ]
    @State private var currentSessionIndex: Int = 0
    @State private var isSequentialModeActive: Bool = false
    @State private var inMiddleOfSequence: Bool = false //use this to hide resultsview

    
    private var totalTime:  Int {
        sharedState.selectedMinutes*60
    }
    
    private var secsPassed: TimeInterval{
        if let beg = startTime{
            return Date().timeIntervalSince(beg) - totalPauseInSession
        } else { return 999 }
    }
    
    private var formatTimePassed: String{
        let minutes = Int(secsPassed) / 60
        let seconds = Int(secsPassed) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
        
    private var tasbeehRate: String{
        let to100 = newAvrgTPC*100
        let minutes = Int(to100) / 60
        let seconds = Int(to100) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    
    private var stopCondition: Bool{
        progressFraction >= 1 && !autoStop && !paused
    }
    
    var inactivityLimit: TimeInterval{
        if tasbeeh > 10{
            return max(newAvrgTPC * 3, 10) // max of triple the average tpc or 10
        } else { return 20 }
    }

    private var incrementThreshold: CGFloat = 50 // Threshold for tasbeeh increment
    
    private var debug: Bool = false
        
    private var debug_AutoStopCond : String {
        "progressFraction: \(progressFraction) | paused: \(paused) | autoStop: \(autoStop) | timerIsActive: \(timerIsActive)"
    }
    
    private var debug_AddingToPausedTimeString : String {
        "totaltime: \(roundToTwo(val: Double(totalTime))) | secpased: \(roundToTwo(val: secsPassed))"
    }
    
    private var debug_secLeft_secPassed_progressFraction: String{
        "secPassed: \(roundToTwo(val: secsPassed)) | proFra: \(roundToTwo(val: progressFraction))"
    }
    
    private var debug_avgTPC: String{
        "newOne: \(roundToTwo(val: newAvrgTPC))"
    }
    
    private func simulateTasbeehClicks(times: Int) {
        for _ in 1...times {
            incrementTasbeeh()
        }
    }
    
    private var estTimeLeft: String?{
        // if in targetCount,
        // get rate of clicks
        // multiply remaining by avrgtpc
        if sharedState.selectedMode == 2 {
            
        }
        let timeLeft = Int(roundToTwo(val: Double(totalTime) - secsPassed))
        return "\(timeLeft)s"
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
//                        isPresented = false
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
    }
    

    
    //--------------------------------------view--------------------------------------
    
    var body: some View {
        ZStack {
            
            // the middle
            ZStack {
                // the circle's inside (picker or count)
                TasbeehCountView(tasbeeh: tasbeeh)
                
                GeometryReader { geometry in
                    VStack {
                        ZStack {
                            Color("bgColor").opacity(0.001) // Simulate clear color
                                .frame(width: geometry.size.width, height: geometry.size.height) // Fill the entire geometry
                                .onTapGesture {
                                    //                                            print("Tap gesture detected")
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
                NeuCircularProgressView(progress: (progressFraction))
                    .allowsHitTesting(false) //so taps dont get intercepted.
            }
            
            // Pause Screen (background overlay, stats & settings)
            ZStack {
                // middle screen when paused
                pauseStatsAndBG(
                    paused: paused,
                    tasbeeh: tasbeeh,
                    secsToReport: secsPassedAtPause,
                    avgTimePerClick: newAvrgTPC,
                    tasbeehRate: tasbeehRate,
                    togglePause: { togglePause() },
                    stopTimer: { stopTimer() },
                    takingNotes: takingNotes,
                    toggleInactivityTimer: $toggleInactivityTimer,
                    inactivityDimmer: $inactivityDimmer,
                    autoStop: $autoStop,
                    colorModeToggle: $colorModeToggle,
                    currentVibrationMode: $currentVibrationMode
                )
            }
            .animation(.easeInOut, value: paused)
            
            // Settings & Start/Stop
            VStack {
                
                // The Top Buttons During Session
                HStack {
                    // exit button top left when paused
                    if paused{
                        Button(action: {stopTimer()} ) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.green.opacity(0.5))
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
                    Text(debug_AutoStopCond)
                    Text(debug_AddingToPausedTimeString)
                    Text(debug_secLeft_secPassed_progressFraction)
                    Text(debug_avgTPC)
                }
                
                Spacer()
                
                // Stop Button when not auto stopping
                completeButton(stopTimer: stopTimer)
                    .opacity(stopCondition ? 1 : 0)
                    .disabled(!stopCondition)
                    .animation(.easeInOut, value: stopCondition)
            }
            
            // adding a dark tint for when they click the sleep mode.
            ZStack{
                Color.black.opacity(toggleInactivityTimer ? ((1-inactivityDimmer) * 0.9) : 0)
                    .allowsHitTesting(false)
                    .edgesIgnoringSafeArea(.all)
                
                // The Bottom Inactivity Alert During Session
                VStack{
                    if sharedState.isDoingPostNamazZikr {
                        Text("\(sharedState.titleForSession)")
                            .frame(width: 150, height: 40)
                            .font(.footnote)
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(.gray.opacity(0.08))
                            .cornerRadius(10)
                            .padding(.top, 130)
                    }
                    Spacer()
                    inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                }
                .zIndex(1)
            }
            .animation(.easeInOut(duration: 0.5), value: toggleInactivityTimer)
            
            // results page
            ZStack{
                if /*!inMiddleOfSequence, */let session = savedSession{
                    ResultsView(
                        isPresented: $isPresented,
                        savedSession: session, // Pass the saved session
                        startTimer: {startTimer()}
                    )
                }
            }
            .zIndex(1)
            .opacity(savedSession == nil ? 0 : 1)
            .disabled(savedSession == nil)
            .animation(.easeInOut(duration: 0.5), value: savedSession != nil)
            
            
        }
        .frame(maxWidth: .infinity) // expand to be the whole page (to make it tappable)
        .background(
            Color.init("bgColor") // Dynamic color for dark or light mode
                .edgesIgnoringSafeArea(.all)
        )
        
        .onAppear {
            if !timerIsActive{
//                timerIsActive = true // ensures functions dont happen outside of session AND not reenabling the onAppear
                print("a1 tasbeehView onappear (timerIsActive?: \(timerIsActive) @ \(Date())) ")
                if sharedState.isDoingPostNamazZikr {
                    startSequentialSession()
                } else{
                    startTimer()
                }
                paused = false // sometimes appstorage had paused = true. so clear it.
                inactivityTimerHandler(run: "restart")
                
            }
        }
        .onChange(of: tasbeeh){_, newTasbeeh in
            inactivityTimerHandler(run: "restart")
            
            if(sharedState.selectedMode == 0){
                //made it so that it never actually gets to 100% (cuz auto stop ends at 100%)
                let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
                progressFraction = CGFloat(Int(numerator))/CGFloat(Int(100))
//                    print("0: \(sharedState.selectedMode) profra: \(progressFraction)")
//                    print("top: \(CGFloat(Int(numerator))) bot: \(CGFloat(Int(100)))")
            } else if (sharedState.selectedMode == 2){
//                    print("in 2: \(tasbeeh)")
                progressFraction = CGFloat(tasbeeh)/CGFloat(Int(sharedState.targetCount) ?? 0)
//                    print("2: \(sharedState.selectedMode) profra: \(progressFraction)")
//                    print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(sharedState.targetCount) ?? 0))")
                
            }

        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .inactive || newScenePhase == .background {
                !paused ? togglePause() : ()
                print("scenePhase: \(newScenePhase) (session paused? \(paused)")
            }
        }

        .preferredColorScheme(colorModeToggle ? .dark : .light)
    }
//--------------------------------------functions--------------------------------------

    private func startSequentialSession() {
        print("ran a startSequentialSession().")
        let currentSession = postNamazSequence[currentSessionIndex]
        sharedState.selectedMode = 2 // Count target mode
        sharedState.selectedMinutes = 0
        sharedState.targetCount = String(currentSession.targetCount)
        sharedState.titleForSession = currentSession.title // should be set as true from outside to enter sequence anyways
        startTimer() // Start the first sequence session
    }
    
    private func handleSessionCompletion() {
        print("ran a handleSessionCompletion().")
        // Check if there's a next session in the sequence
        if currentSessionIndex < postNamazSequence.count - 1 {
            currentSessionIndex += 1
            startSequentialSession() // Start the next session
        } else {
            // Reset state when all sessions are complete
            currentSessionIndex = 0
            sharedState.isDoingPostNamazZikr = false
            isPresented = false
            sharedState.showingOtherPages = false
        }
    }
    
    private func startTimer() {
        guard !timerIsActive else {
            print("Timer is already active")
            return
        }
        
        // Reset necessary variables for a new session
        print("ran a start.")
        tasbeeh = 0
        
        savedSession = nil
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: sharedState.selectedMinutes, to: startTime!)
        totalPauseInSession = 0
        secsToReport = 0
        timerIsActive = true //this just ensures increment, decrement and reset dont happen outside of session
        
        timerbb = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        
            withAnimation {
                if !paused && (sharedState.selectedMode == 1){
                    progressFraction = CGFloat(Int(secsPassed))/TimeInterval(totalTime)
                }
            }
           
//            print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)") // for debugging
            if ((progressFraction >= 1) && !paused) {
                if(autoStop && timerIsActive){
                    stopTimer()
                    print("homeboy auto stopped....")
                    streak += 1 // Increment the streak
                }
            }
        }

        
        triggerSomeVibration(type: .success)
        
        UIApplication.shared.isIdleTimerDisabled = true
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change

    }
    
        
    private func stopTimer() {
        guard timerIsActive else {
            print("Timer is not active")
            return
        }
        
        print("ran a stopTimer().")
        //basically save only if tasbeeh > 0
        // give time to show resultsview.
        // skip resultsview if in sequence
        
        timerIsActive = false // this so functions only run during a sesh AND so timer checking when to stopTimer doesnt save multiple sessions.
        if tasbeeh > 0 {
            savedSession = saveSession()
            print("saved session: \(savedSession == nil ? "nil" : "\(savedSession!.title) with \(savedSession!.totalCount)")")
            // if in middle of sequence, run stoptimer() asap
            if sharedState.isDoingPostNamazZikr /*isSequentialModeActive*/{
                self.completeStopTimer()
            }
            // else do with wait
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.completeStopTimer()
                }
            }
        } else {
            completeStopTimer()
        }
    }


    private func completeStopTimer() {
        print("ran a completeStopTimer().")
        
        // Stop and invalidate the timer
        timerbb?.invalidate()
        timerbb = nil
        
        // allow idle timer again
        UIApplication.shared.isIdleTimerDisabled = false
        
        
        // Reset all state variables to clean up the session
        endTime = nil
        startTime = nil
        progressFraction = 0
        sharedState.targetCount = ""
        noteModalText = ""
        
        
        if !stoppedDueToInactivity {
            triggerSomeVibration(type: .vibrate)
        }
        
        stoppedDueToInactivity = false
        inactivityTimerHandler(run: "stop")
        toggleInactivityTimer = false
        paused = false
        
        
        if tasbeeh == 0 {
            isPresented = false
            sharedState.showingOtherPages = false
            resetSharedState()
        }
        if sharedState.isDoingPostNamazZikr /*isSequentialModeActive*/ {
            handleSessionCompletion() // Trigger the next session
        }
    }
    
    private func saveSession() -> SessionDataModel {
        print("ran a saveSession().")
        // Generate session data after the timer stops
        let placeholderTitle = (sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled")
        
        secsToReport = paused ? secsPassedAtPause : secsPassed
        
        let item = SessionDataModel(
            title: placeholderTitle,
            sessionMode: sharedState.selectedMode,
            targetMin: sharedState.selectedMinutes,
            targetCount: Int(sharedState.targetCount) ?? 0,
            totalCount: tasbeeh,
            startTime: startTime ?? Date(),
            secondsPassed: secsToReport,
            avgTimePerClick: newAvrgTPC,
            tasbeehRate: tasbeehRate
        )
        print("adding a session card")
        context.insert(item)
        return item
    }

    
    func resetSharedState(){
        print("ran a resetSharedState().")
        sharedState.targetCount = ""
        sharedState.isDoingPostNamazZikr = false
        sharedState.targetCount = ""
        sharedState.selectedMinutes = 0
        sharedState.titleForSession = ""
        sharedState.selectedMode = 0
    }
    
    private func togglePause() {
        print("ran a togglePause().")
        paused.toggle()
//        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change
        triggerSomeVibration(type: .medium)
        if(paused){
            inactivityTimerHandler(run: "stop")
            pauseStartTime = Date()
            secsPassedAtPause = secsPassed
            timePassedAtPauseString = formatTimePassed // cant use calc var bc keeps changing if view ever updated
        }else{
            inactivityTimerHandler(run: "restart")
            let thisPauseSesh = Date().timeIntervalSince(pauseStartTime ?? Date())
//            pauseSinceLastInc += thisPauseSesh
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
        if timerIsActive {
            tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
            newAvrgTPC = (tasbeeh > 0 ? (secsPassed / Double(tasbeeh)) : 0)
            triggerSomeVibration(type: currentVibrationMode)
            vibrateOnFinishOfTasbeeh()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private func decrementTasbeeh() {
        if timerIsActive {
            tasbeeh = max(tasbeeh - 1, 0) // Adjust minimum value as needed
            newAvrgTPC = (tasbeeh > 0 ? (secsPassed / Double(tasbeeh)) : 0)
            triggerSomeVibration(type: .rigid)
            WidgetCenter.shared.reloadAllTimelines()

        }
    }
    
    private func resetTasbeeh() { //not being used but just keeping incase need later
        if timerIsActive {
            tasbeeh = 0
            triggerSomeVibration(type: .error)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
        
    private func vibrateOnFinishOfTasbeeh(){
        if(tasbeeh % 100 == 0 && tasbeeh != 0){
            triggerSomeVibration(type: .error)
        }
    }
    
}


#Preview {
    @Previewable @StateObject var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool)
        .environmentObject(sharedState) // Inject shared state into the environment
}



/*
 Current Improvement Focus:
 
 Improvements needed:
 - bug where it resets randomly. trying to fix it...
     > i think it has to do with the onappear and ondisappear with the change of scenephase... but not always the case.
     > works fine in simulator. but not on real device
     > put print statements to try and debug
     > also made titleForSession = "set down here" or = "set up here" to understand whats happening
 - next up: make MantraModel hold all information regarding total count
 */
