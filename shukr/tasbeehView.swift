import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer
import Foundation


struct tasbeehView: View {
    @Binding var isPresented: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
    
    // AppStorage properties
    @AppStorage("inactivityToggle") var toggleInactivityTimer = false
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5
    @AppStorage("currentVibrationMode") private var currentVibrationMode: HapticFeedbackType = .medium
    
    // State properties
//    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timerbb: Timer? = nil
    @State private var paused = false
    @State private var tasbeeh = 0
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var pauseStartTime: Date? = nil
    @State private var autoStop = true

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
    @State private var savedSession: SessionDataModel? = nil
    
    @State private var postNamazSequence: [(title: String, targetCount: Int)] = [
                (title: "Subhanallah", targetCount: 33),
                (title: "Alhamdulillah", targetCount: 33),
                (title: "Allahu Akbar", targetCount: 34)
            ]
    @State private var currentSessionIndex: Int = 0
    @State private var tasbeehColorMode = false

    
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
                pauseScreen_StatsSettingsBG(
                    paused: paused,
                    tasbeeh: tasbeeh,
                    secsToReport: secsPassedAtPause,
                    newAvrgTPC: newAvrgTPC,
                    tasbeehRate: tasbeehRate,
                    togglePause: { togglePause() },
                    stopTimer: { stopTimer() },
                    takingNotes: takingNotes,
                    toggleInactivityTimer: $toggleInactivityTimer,
                    inactivityDimmer: $inactivityDimmer,
                    autoStop: $autoStop,
                    tasbeehColorMode: $tasbeehColorMode,
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
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.red.opacity(0.4))
                                .padding()
                                .background(.gray.opacity(0.08))
                                .cornerRadius(10)
//                            Label {
//                                Text("Exit")
//                                    .font(.system(size: 20, weight: .medium))
//                            } icon: {
//                                Image(systemName: "xmark")
//                                    .font(.system(size: 24, weight: .bold))
//                            }
//                                .foregroundColor(.red.opacity(0.4))
//                                .padding()
//                                .background(.gray.opacity(0.08))
//                                .cornerRadius(10)
                        }
                    }
                    else {
                        HStack{
                            TopOfSessionButton( // Minus Button
                                symbol: "minus", actionToDo: decrementTasbeeh,
                                paused: paused, togglePause: togglePause)
                            
                            TopOfSessionButton( // Plus 100 Button (for testing)
                                symbol: "infinity", actionToDo: {simulateTasbeehClicks(times: 100)},
                                paused: paused, togglePause: togglePause)
                            
//                            TopOfSessionButton( // Add Note Button (new feature coming soon)
//                                symbol: "note", actionToDo: {showNotesModal = true},
//                                paused: paused, togglePause: togglePause)
//                            .sheet(isPresented: $showNotesModal) {
//                                NoteModalView(savedText: $noteModalText, showSheet: $showNotesModal, takingNotes: $takingNotes)
//                            }
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
//                completeButton(stopTimer: stopTimer)
//                    .opacity(stopCondition ? 1 : 0)
//                    .disabled(!stopCondition)
//                    .animation(.easeInOut, value: stopCondition)
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
                        savedSession: session // Pass the saved session
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
            tasbeehColorMode = colorScheme == .dark ? true : false
            
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
        .onChange(of: tasbeehColorMode){oldVal, newVal in
            print("tasbeehView: old tasbeehColorMode: \(oldVal), newVal: \(newVal)")
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

        .preferredColorScheme(tasbeehColorMode ? .dark : .light)
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
//            sharedState.showingOtherPages = false
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
                }
            }
        }

        
        triggerSomeVibration(type: .success)
        
//        UIApplication.shared.isIdleTimerDisabled = true
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
            // allow idle timer again
//            UIApplication.shared.isIdleTimerDisabled = false
            
            print("saved session: \(savedSession == nil ? "nil" : "\(savedSession!.title) with \(savedSession!.totalCount)")")
            sharedState.selectedTask = nil
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
//            sharedState.showingOtherPages = false
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
//        sharedState.targetCount = ""
        sharedState.isDoingPostNamazZikr = false
        sharedState.targetCount = ""
        sharedState.selectedMinutes = 0
        sharedState.titleForSession = ""
        sharedState.selectedMode = 1
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
    
    // MARK: - Helper Structs (basically moved from Utils)
    
    struct ResultsView: View {
        @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
        @Environment(\.modelContext) private var context
        @EnvironmentObject var sharedState: SharedStateClass
        @Binding var isPresented: Bool
        let savedSession: SessionDataModel  // Add this

        // UI state
        private let textSize: CGFloat = 14
        private let gapSize: CGFloat = 10
        @State private var countRotation: Double = 0
        @State private var timerRotation: Double = 0
        @State private var showingPerCount = true
        @State private var showMantraSheetFromResultsPage = false
        @State private var chosenMantraFromResultsPage: String? = ""
        
        // Computed properties from savedSession
        private var tasbeeh: Int { savedSession.totalCount }
        private var secsToReport: Double { savedSession.secondsPassed }
        private var tasbeehRate: String { savedSession.tasbeehRate }
        private var newAvrgTPC: Double { savedSession.avgTimePerClick }
        
        var body: some View {
            ZStack {
                
                Color("pauseColor")
                    .edgesIgnoringSafeArea(.all)
                
                completionCard
                    .padding(.horizontal, 16)
                
                VStack {
                    Spacer()
                    
                    CloseButton(
                        action: {
                            isPresented = false
    //                        sharedState.showingOtherPages = false
                            sharedState.titleForSession = ""
                        }
                    )
                    .padding(.bottom)
                }
            }
        }
        
        private var completionCard: some View {
            VStack(alignment: .center, spacing: 12) {
                // TOP:
                // TOP1. Checkmark circle
                Circle()
                    .fill(Color(colorScheme == .dark ? .systemGray4 : .white))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.green)
                    }
                
                // TOP2. Message
                Text("Nice! I'll add this to your history!")
                    .font(.system(size: 16, weight: .regular))
                    .multilineTextAlignment(.center)
                
                // Boxes
                VStack(alignment: .center, spacing: gapSize) {
                    // Mantra selector
                    mantraSelector
                        .transition(.opacity)
                    
                    // Stats Grid
                    HStack(alignment: .top, spacing: gapSize) {
                        // Left Column
                        VStack(spacing: gapSize) {
                            // Count Box
                            statsBox {
                                HStack {
                                    Image(systemName: "circle.hexagonpath")
                                        .font(.system(size: 20))
                                        .foregroundColor(.primary)
                                        .rotationEffect(.degrees(-countRotation))
                                        .animation(.spring(duration: 0.5), value: countRotation)
                                    Spacer()
                                    Text("\(tasbeeh)")
                                        .font(.system(size: textSize, weight: .medium))
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                            }
                            .frame(height: 44)  // Fixed height for count
                            .onTapGesture {
                                triggerSomeVibration(type: .medium)
                                countRotation += 60 // Rotate by 45 degrees (360° ÷ 8)
                            }

                            // Timer Box
                            statsBox {
                                HStack {
                                    Image(systemName: "gauge.with.needle")
                                        .font(.system(size: 20))
                                        .foregroundColor(.primary)
                                        .rotationEffect(.degrees(timerRotation))
                                        .animation(.spring(duration: 0.3), value: timerRotation)
                                    Spacer()
                                    Text(timerStyle(secsToReport))
                                        .font(.system(size: textSize, weight: .medium))
                                        .monospacedDigit()
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                            }
                            .frame(height: 44)  // Fixed height for timer
                            .onTapGesture {
                                triggerSomeVibration(type: .medium)
                                timerRotation += 45 // Rotate by 45 degrees (360° ÷ 8)
                             }

                        }
                        
                        // Rate Box
                        statsBox {
                            VStack(spacing: 6) {
                                Text("Rate")
                                    .font(.system(size: 18, weight: .medium))
                                    .underline()
                                
                                ZStack {
                                    // Per count view
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.2fs", newAvrgTPC))
                                            .font(.system(size: textSize, weight: .medium))
                                            .monospacedDigit()
                                        Text("per count")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .opacity(showingPerCount ? 1 : 0)
                                    .offset(y: showingPerCount ? 0 : -20)
                                    
                                    // Per tasbeeh view
                                    VStack(spacing: 2) {
                                        Text(tasbeehRate)
                                            .font(.system(size: textSize, weight: .medium))
                                            .monospacedDigit()
                                        Text("per tasbeeh")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .opacity(showingPerCount ? 0 : 1)
                                    .offset(y: showingPerCount ? 20 : 0)
                                }
                            }
                        }
                        .frame(height: 96)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                triggerSomeVibration(type: .medium)
                                showingPerCount.toggle()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            .padding(20)
            .frame(width: 280)
            .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the stats box
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
        }
        
        private func statsBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
        }
        
        // zikrflag 3
        private var mantraSelector: some View {
            Text(sharedState.titleForSession.isEmpty ? "no selected zikr" : sharedState.titleForSession)
                .font(.system(size: 16, weight: sharedState.titleForSession.isEmpty ? .ultraLight : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    showMantraSheetFromResultsPage = true
                }
                .onChange(of: chosenMantraFromResultsPage) {
                    if let newSetMantra = chosenMantraFromResultsPage {
                        withAnimation {
                            sharedState.titleForSession = newSetMantra
                            savedSession.title = newSetMantra  // Update the saved session directly
                            do {
                                try context.save()  // Save the context to persist the changes
                            } catch {
                                print("Error saving context: \(error)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showMantraSheetFromResultsPage) {
                    MantraPickerView(
                        isPresented: $showMantraSheetFromResultsPage,
                        selectedMantra: $chosenMantraFromResultsPage,
                        presentation: [.large]
                    )
                }
        }
        
        struct CloseButton: View {
            let action: () -> Void
            @State private var isPressed = false
            
            var body: some View {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        triggerSomeVibration(type: .success)
                        isPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isPressed = false
                        action()
                    }
                }) {
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.08))
                        
                        // Outline
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                        
                        // Content
                        Text("close")
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .foregroundColor(.primary)
                    }
                    .frame(width: 100, height: 50)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    #Preview {
        ResultsView(
            isPresented: .constant(true),
            savedSession: SessionDataModel(
                title: "yo",
                sessionMode: 1,
                targetMin: 1,
                targetCount: 5,
                totalCount: 66,
                startTime: Date(),
                secondsPassed: 72,
                avgTimePerClick: 0.54,
                tasbeehRate: "10m 4s"
            )
        )
        .environmentObject(SharedStateClass())
    }

    
    struct pauseScreen_StatsSettingsBG: View {
        @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
        @EnvironmentObject var sharedState: SharedStateClass
        @State private var showMantraSheetFromPausedPage = false
        @State private var chosenMantra: String? = ""
        @State private var rateTextToggle = false  // to control the toggle text in the middle
            
        let paused: Bool
        let tasbeeh: Int
        let secsToReport: TimeInterval
        let newAvrgTPC: TimeInterval
        let tasbeehRate: String
        let togglePause: () -> Void // Closure for the togglePause function
        let stopTimer: () -> Void // Closure for the togglePause function
        let takingNotes: Bool
        @Binding var toggleInactivityTimer: Bool
        @Binding var inactivityDimmer: Double
        @Binding var autoStop: Bool
        @Binding var tasbeehColorMode: Bool
        @Binding var currentVibrationMode: HapticFeedbackType
        
        @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased



        
        // UI state
        private let textSize: CGFloat = 14
        private let gapSize: CGFloat = 10
        @State private var countRotation: Double = 0
        @State private var timerRotation: Double = 0
        @State private var showingPerCount = true
        @State private var showMantraSheetFromResultsPage = false
        @State private var chosenMantraFromResultsPage: String? = ""
        
        // Computed variables for est time completion (only for target count mode)
        private var remainingCount: Int{
            return (Int(sharedState.targetCount) ?? 0) - Int(tasbeeh)
        }
        private var timeLeft : TimeInterval{
            return newAvrgTPC * Double(remainingCount)
        }
        private var finishTime: Date{
            return Date().addingTimeInterval(timeLeft)
        }


        
        var body: some View {
            
            
            Color("pauseColor")
                .edgesIgnoringSafeArea(.all)
                .animation(.easeOut(duration: 0.3), value: paused)
                .opacity(paused ? 1 : 0.0)
                .onTapGesture { togglePause() }
            
            VStack{
                VStack {
                    completionCard
                        .padding(.horizontal, 16)
                }
                
                if sharedState.selectedMode == 2 && remainingCount > 0 && !sharedState.isDoingPostNamazZikr && tasbeeh > 0 {
                    estimatedFinishTime
                }
            }
            .opacity(paused ? 1.0 : 0.0)
            .animation(.easeInOut, value: paused)
            
            VStack {
                Spacer()
                
                // bottom settings bar when paused
                VStack {
                    if(toggleInactivityTimer){
                        Slider(value: $inactivityDimmer, in: 0...1.0)
                        .tint(.white)
                        .frame(width: 250)
                        .padding()
                    }
                    HStack{
                        AutoStopToggleButton(autoStop: $autoStop)
                        SleepModeToggleButton(toggleInactivityTimer: $toggleInactivityTimer, tasbeehColorMode: $tasbeehColorMode)
                        VibrationModeToggleButton(currentVibrationMode: $currentVibrationMode)
                        ColorSchemeModeToggleButton(tasbeehColorMode: $tasbeehColorMode)
                    }
//                    HStack{
//                        Spacer()
//                        Button(action: {
//                            stopTimer()
//                        }) {
//                            Text("Complete")
//                                .font(.headline)
//                                .bold()
//                                .foregroundColor(Color(.secondaryLabel))
//                                .padding()
//                                .cornerRadius(10)
//                        }
//                        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
//                        .cornerRadius(15)
//                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)
//
//                        Spacer()
//                    }
                }
                .padding()
                .padding(.bottom, 20)
                .opacity(paused ? 1.0 : 0.0)
            }
            
        }
        
        
        private var completionCard: some View {
            VStack(alignment: .center, spacing: 12) {
                
                //TOP: The Mode Text
                switch sharedState.selectedMode {
                case 1:
                    Text("\(sharedState.selectedMinutes)m Session")
                        .font(.title3)
                        .bold()
                case 2:
                    Text("\(sharedState.targetCount) Count Session")
                        .font(.title3)
                        .bold()
                default:
                    Text("Freestyle Session")
                        .font(.title3)
                        .bold()
                }

                
                // Boxes
                VStack(alignment: .center, spacing: gapSize) {
                    // Mantra selector
                    mantraSelector
                        .transition(.opacity)
                    
                    // Stats Grid
                    HStack(alignment: .top, spacing: gapSize) {
                        // Left Column
                        VStack(spacing: gapSize) {
                            // Count Box
                            statsBox {
                                HStack {
                                    Image(systemName: "circle.hexagonpath")
                                        .font(.system(size: 20))
                                        .foregroundColor(.primary)
                                        .rotationEffect(.degrees(-countRotation))
                                        .animation(.spring(duration: 0.5), value: countRotation)
                                    Spacer()
                                    Text("\(tasbeeh)")
                                        .font(.system(size: textSize, weight: .medium))
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                            }
                            .frame(height: 44)  // Fixed height for count
                            .onTapGesture {
                                triggerSomeVibration(type: .medium)
                                countRotation += 60 // Rotate by 45 degrees (360° ÷ 8)
                            }

                            // Timer Box
                            statsBox {
                                HStack {
                                    Image(systemName: "gauge.with.needle")
                                        .font(.system(size: 20))
                                        .foregroundColor(.primary)
                                        .rotationEffect(.degrees(timerRotation))
                                        .animation(.spring(duration: 0.3), value: timerRotation)
                                    Spacer()
                                    Text(timerStyle(secsToReport))
                                        .font(.system(size: textSize, weight: .medium))
                                        .monospacedDigit()
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                            }
                            .frame(height: 44)  // Fixed height for timer
                            .onTapGesture {
                                triggerSomeVibration(type: .medium)
                                timerRotation += 45 // Rotate by 45 degrees (360° ÷ 8)
                             }

                        }
                        
                        // Rate Box
                        statsBox {
                            VStack(spacing: 6) {
                                Text("Rate")
                                    .font(.system(size: 18, weight: .medium))
                                    .underline()
                                
                                ZStack {
                                    // Per count view
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.2fs", newAvrgTPC))
                                            .font(.system(size: textSize, weight: .medium))
                                            .monospacedDigit()
                                        Text("per count")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .opacity(showingPerCount ? 1 : 0)
                                    .offset(y: showingPerCount ? 0 : -20)
                                    
                                    // Per tasbeeh view
                                    VStack(spacing: 2) {
                                        Text(tasbeehRate)
                                            .font(.system(size: textSize, weight: .medium))
                                            .monospacedDigit()
                                        Text("per tasbeeh")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .opacity(showingPerCount ? 0 : 1)
                                    .offset(y: showingPerCount ? 20 : 0)
                                }
                            }
                        }
                        .frame(height: 96)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                triggerSomeVibration(type: .medium)
                                showingPerCount.toggle()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            .padding(20)
            .frame(width: 280)
            .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the stats box
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
        }
        
        private var estimatedFinishTime: some View {
            ExternalToggleText(
                originalText: "you'll finish \(inMinSecStyle2(from: timeLeft))",
                toggledText: "you'll finish around \(shortTime(finishTime))",
                externalTrigger: $rateTextToggle,  // Pass the binding
                font: .caption,
                fontDesign: .rounded,
                fontWeight: .thin,
                hapticFeedback: true
            )
            .opacity(0.8)
            .padding()
            .background(Color("pauseColor").opacity(0.001))
        }
        
        private func statsBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
        }
        
        // zikrflag 2
        private var mantraSelector: some View {
            Text(sharedState.titleForSession.isEmpty ? "no selected zikr" : sharedState.titleForSession)
                .font(.system(size: 16, weight: sharedState.titleForSession.isEmpty ? .ultraLight : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    showMantraSheetFromResultsPage = true
                }
                .onChange(of: chosenMantraFromResultsPage) {
                    if let newSetMantra = chosenMantraFromResultsPage {
                        withAnimation {
                            sharedState.titleForSession = newSetMantra
                        }
                    }
                }
                .sheet(isPresented: $showMantraSheetFromResultsPage) {
                    MantraPickerView(
                        isPresented: $showMantraSheetFromResultsPage,
                        selectedMantra: $chosenMantraFromResultsPage,
                        presentation: [.large]
                    )
                }
        }

    }

    
    struct TopOfSessionButton: View{
        let symbol: String
        let actionToDo: () -> Void
        let paused: Bool
        let togglePause: () -> Void
        
        var body: some View{
            Button(action: paused ? togglePause : actionToDo) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.gray.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .padding()
                    .background(paused ? .clear : .gray.opacity(0.08))
                    .cornerRadius(100)
                    .opacity(paused ? 0 : 1.0)
            }
        }
    }
    
    struct NoteModalView: View {
        @Binding var savedText: String
        @Binding var showSheet: Bool
        @Binding var takingNotes: Bool
        @State private var tempText = ""
        
        var body: some View {
                TextEditor(text: $tempText)
                    .padding()
                    .navigationTitle("Edit Text")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showSheet = false
                        },
                        trailing: Button("Save") {
                            if !tempText.isEmpty {
                                savedText = tempText
                                showSheet = false
                            }
                        }
                        .disabled(tempText.isEmpty)
                    )
            .presentationDetents([.medium])

            .onAppear {
                takingNotes = true
                tempText = savedText
            }
            .onDisappear{
                takingNotes = false
            }
        }
    }
    
    struct PlayPauseButton: View {
        let togglePause: () -> Void
        let paused: Bool
        
        var body: some View {
            // eventually use this to toggle the settings modal that replaces the pause stats modal.
            /*
            if paused{
                Button(action: togglePause) {
                    Image(systemName: "gear")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray.opacity(0.8))
                        .padding()
                        .background(/*paused ? .clear : */.gray.opacity(0.08))
                        .cornerRadius(10)
                }
            }
             */
            Button(action: togglePause) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(paused ? .gray.opacity(0.8) : .gray.opacity(0.3))
                    .padding()
                    .background(/*paused ? .clear : */.gray.opacity(0.08))
                    .cornerRadius(10)
            }
        }
    }



    
    struct completeButton: View {
        let stopTimer: () -> Void
        @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
        
        var body: some View{
            Button(action: stopTimer, label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(
                                         LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [.yellow.opacity(0.6), .green.opacity(0.8)] : [.yellow, .green]), startPoint: .topLeading, endPoint: .bottomTrailing)
                                         )
                    Text("complete")
                        .foregroundStyle(.white)
                        .font(.title3)
                        .fontDesign(.rounded)
                }
                .frame(width: 300,height: 50)
                .shadow(radius: 5)
            })
            .padding([.leading, .bottom, .trailing])
        }
    }
    
    

    
}


#Preview {
    @Previewable @StateObject var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool)
        .environmentObject(sharedState) // Inject shared state into the environment
}
