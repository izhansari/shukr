import SwiftUI
import AVFAudio
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
    /// Sessions without a mantra keep their quick-add step here (mantras keep theirs on the row).
    @AppStorage(QuickAddSteps.noMantraKey) private var noMantraQuickAdd = 0
    /// The session's mantra row: the picked object, else looked up by the session title
    /// (post-salah sequences and older launchers only set the title).
    @State private var sessionMantra: MantraModel?
    private var secondaryStep: Int { sessionMantra?.quickAddStep ?? noMantraQuickAdd }
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5
    @AppStorage("currentVibrationMode") private var currentVibrationMode: HapticFeedbackType = .medium
    
    // State properties
//    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timerbb: Timer? = nil
    @State private var paused = false
    @State private var tasbeeh = 0
    /// Counts / seconds already done today when continuing a task: on the ring, not saved again.
    @State private var countOffset = 0
    @State private var timeOffset: TimeInterval = 0
    /// What this session itself counted (the saved total).
    private var sessionCount: Int { tasbeeh - countOffset }
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
    
    /// Post-salah: which of the three phrases the count is in (for the phase-change haptic).
    @State private var postSalahPhase = 0
    /// Which reminder the post-salah session shows (one per session, picked at random).
    @State private var reminderVariant: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments   // -reminderVariant N (screenshots)
        if let i = args.firstIndex(of: "-reminderVariant"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return Int.random(in: 0..<PostSalahReminder.count)
    }()
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
                    mantra: sessionMantra,
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
                    // Always there, faded out and inert while paused (Finish / Resume live on the
                    // pause screen). Removing them popped the layout on every pause / resume.
                    Group {
                        HStack{
                            TopOfSessionButton( // Minus Button
                                symbol: "minus", actionToDo: decrementTasbeeh,
                                paused: paused, togglePause: togglePause)
                            
                            if secondaryStep > 0 {
                                TopOfSessionButton( // Quick add: +N in one tap (the mantra's own step)
                                    text: "+\(secondaryStep)", actionToDo: { simulateTasbeehClicks(times: secondaryStep) },
                                    paused: paused, togglePause: togglePause)
                            }
                            
                            
//                            TopOfSessionButton( // Add Note Button (new feature coming soon)
//                                symbol: "note", actionToDo: {showNotesModal = true},
//                                paused: paused, togglePause: togglePause)
//                            .sheet(isPresented: $showNotesModal) {
//                                NoteModalView(savedText: $noteModalText, showSheet: $showNotesModal, takingNotes: $takingNotes)
//                            }
                        }
                        .opacity(paused ? 0 : 1)
                        .allowsHitTesting(!paused)
                    }
                    
                    
                    Spacer()
                    
                    // dynamic pause / play button shown in active session
                    PlayPauseButton(togglePause: togglePause, paused: paused)
                        .opacity(paused ? 0 : 1)
                        .disabled(paused)
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
                        PostSalahPhaseStrip(count: tasbeeh)
                            .padding(.top, 120)
                            .allowsHitTesting(false)
                            // Fades under the pause screen with it (removing it popped; left on,
                            // it drew through the pause screen).
                            .opacity(paused ? 0 : 1)
                            .animation(.easeInOut, value: paused)
                    }
                    Spacer()
                    inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                }
                .zIndex(1)

                // Post-salah: why it's worth it, low on the screen, clear of the beads.
                if sharedState.isDoingPostNamazZikr {
                    VStack {
                        Spacer()
                        PostSalahReminder(variant: reminderVariant)
                            .padding(.horizontal, 36)
                            .padding(.bottom, 12)
                    }
                    .allowsHitTesting(false)
                    .opacity(paused ? 0 : 1)
                    .animation(.easeInOut, value: paused)
                }
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
            resolveSessionMantra()
            
            if !timerIsActive{
//                timerIsActive = true // ensures functions dont happen outside of session AND not reenabling the onAppear
                print("a1 tasbeehView onappear (timerIsActive?: \(timerIsActive) @ \(Date())) ")
                if sharedState.isDoingPostNamazZikr {
                    PostSalahTasbeeh.prepare(sharedState, in: context)
                    resolveSessionMantra()
                }
                startTimer()
                paused = false // sometimes appstorage had paused = true. so clear it.
                inactivityTimerHandler(run: "restart")
            }
        }
        .onChange(of: sharedState.titleForSession) { _, _ in resolveSessionMantra() }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoPostSalah") {
                try? await Task.sleep(for: .seconds(1.5))
                simulateTasbeehClicks(times: 45)
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
                try? await Task.sleep(for: .seconds(1))
                simulateTasbeehClicks(times: 12)
                try? await Task.sleep(for: .seconds(1))
                togglePause()
                if ProcessInfo.processInfo.arguments.contains("-demoResults") {
                    try? await Task.sleep(for: .seconds(1))
                    stopTimer()
                }
            }
        }
        #endif
        .onChange(of: tasbeehColorMode){oldVal, newVal in
            print("tasbeehView: old tasbeehColorMode: \(oldVal), newVal: \(newVal)")
        }
        .onChange(of: tasbeeh){_, newTasbeeh in
            inactivityTimerHandler(run: "restart")
            if sharedState.isDoingPostNamazZikr {
                // A phrase finished (33, 66): a success buzz as the next one starts.
                let phase = PostSalahTasbeeh.phase(at: newTasbeeh).index
                if phase > postSalahPhase { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                postSalahPhase = phase
            }
            
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
        .onDisappear {
            sharedState.isDoingPostNamazZikr = false
            UIApplication.shared.isIdleTimerDisabled = false // never leave this on after the cover closes
        }

        .preferredColorScheme(tasbeehColorMode ? .dark : .light)
    }
//--------------------------------------functions--------------------------------------

    private func resolveSessionMantra() {
        let title = sharedState.titleForSession
        if let picked = sharedState.mantraForSession, picked.name == title || title.isEmpty {
            sessionMantra = picked
        } else {
            sessionMantra = title.isEmpty ? nil : MantraModel.find(named: title, in: context)
        }
    }

    /// Keep the screen awake only while a session is actively counting.
    /// Paused, stopped, or dismissed → hand control back to the system auto-lock.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = timerIsActive && !paused
    }
    
    private func startTimer() {
        guard !timerIsActive else {
            print("Timer is already active")
            return
        }
        
        // Reset necessary variables for a new session
        print("ran a start.")
        countOffset = sharedState.resumeCount
        timeOffset = sharedState.resumeSeconds
        sharedState.resumeCount = 0
        sharedState.resumeSeconds = 0
        tasbeeh = countOffset
        
        savedSession = nil
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: sharedState.selectedMinutes, to: startTime!)
        totalPauseInSession = 0
        secsToReport = 0
        timerIsActive = true //this just ensures increment, decrement and reset dont happen outside of session
        
        timerbb = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        
            withAnimation {
                if !paused && (sharedState.selectedMode == 1){
                    progressFraction = CGFloat(Int(secsPassed + timeOffset))/TimeInterval(totalTime)
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
        updateIdleTimer()
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
        updateIdleTimer()
        if sessionCount > 0 {
            savedSession = saveSession()
            
            print("saved session: \(savedSession == nil ? "nil" : "\(savedSession!.title) with \(savedSession!.totalCount)")")
            sharedState.selectedTask = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.completeStopTimer()
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
        
        
        if sessionCount <= 0 {
            isPresented = false
//            sharedState.showingOtherPages = false
            resetSharedState()
        }
    }
    
    private func saveSession() -> SessionDataModel {
        print("ran a saveSession().")
        // Generate session data after the timer stops
        let placeholderTitle = (sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled")
        
        secsToReport = paused ? secsPassedAtPause : secsPassed
        
        // Only a session launched from a task card counts toward that task. Freestyle (mode 0)
        // and the post-salah sequence never link, even if a card is still "selected" underneath.
        let linkedTask = (sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr)
            ? sharedState.selectedTask : nil
        
        let item = SessionDataModel(
            title: placeholderTitle,
            sessionMode: sharedState.selectedMode,
            targetMin: sharedState.selectedMinutes,
            targetCount: Int(sharedState.targetCount) ?? 0,
            totalCount: sessionCount,
            startTime: startTime ?? Date(),
            secondsPassed: secsToReport,
            avgTimePerClick: newAvrgTPC,
            tasbeehRate: tasbeehRate,
            task: linkedTask,
            // Picked from a task/picker (or Tasbih Fatimah for post-salah) → we have the row.
            mantra: sharedState.mantraForSession ?? MantraModel.find(named: placeholderTitle, in: context)
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
        sharedState.mantraForSession = nil
        sharedState.selectedMode = 1
    }
    
    private func togglePause() {
        print("ran a togglePause().")
        paused.toggle()
        updateIdleTimer()
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
            newAvrgTPC = (sessionCount > 0 ? (secsPassed / Double(sessionCount)) : 0)
            triggerSomeVibration(type: currentVibrationMode)
            vibrateOnFinishOfTasbeeh()
        }
    }
    
    private func decrementTasbeeh() {
        if timerIsActive {
            tasbeeh = max(tasbeeh - 1, countOffset) // never below where a continued task started
            newAvrgTPC = (sessionCount > 0 ? (secsPassed / Double(sessionCount)) : 0)
            triggerSomeVibration(type: .rigid)
        }
    }
    
    private func resetTasbeeh() { //not being used but just keeping incase need later
        if timerIsActive {
            tasbeeh = 0
            triggerSomeVibration(type: .error)
        }
    }
        
    private func vibrateOnFinishOfTasbeeh(){
        if(tasbeeh % 100 == 0 && tasbeeh != 0){
            triggerSomeVibration(type: .error)
        }
    }
    
    // MARK: - Helper Structs (basically moved from Utils)
    
    /// After Finish (restyled 2026-09-25 to match the pause screen): a sage check that pops in,
    /// "saved to your history", the mantra card (tap to put the session on another mantra —
    /// not for a task's session, which stays on its task's mantra), the shared bento, and Done.
    struct ResultsView: View {
        @Environment(\.modelContext) private var context
        @EnvironmentObject var sharedState: SharedStateClass
        @Binding var isPresented: Bool
        let savedSession: SessionDataModel

        @State private var showMantraPicker = false
        @State private var chosenMantraName: String? = ""
        @State private var chosenMantraObject: MantraModel? = nil
        @State private var checkShown = false
        @State private var showHistory = false

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
        private var isTasbihFatimah: Bool {
            (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        /// A task's session keeps its task's mantra; Tasbih Fatimah is always Tasbih Fatimah.
        private var locked: Bool {
            savedSession.task != nil || (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        private var title: String { savedSession.mantra?.name ?? savedSession.title }

        /// A task's session: where the task stands today ("5 of 100 today"), since a continued
        /// session saves only its own counts.
        private var taskToday: String? {
            guard let task = savedSession.task else { return nil }
            let mine = task.sessions.filter { $0.startTime >= PrayerDay.sessionDayStart() }
            let p = TaskProgress(count: mine.reduce(0) { $0 + $1.totalCount },
                                 seconds: mine.reduce(0) { $0 + $1.secondsPassed })
            return task.isCountMode ? "\(p.count) of \(task.goal) today"
                                    : "\(Int(p.seconds / 60)) of \(task.goal) min today"
        }

        private var sessionLabel: String {
            switch savedSession.sessionMode {
            case 1: return "\(savedSession.targetMin) min session"
            case 2: return "\(savedSession.targetCount) count session"
            default: return "freestyle session"
            }
        }

        var body: some View {
            ZStack {
                Color("pauseColor")
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.sage)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.sage.opacity(0.16)))
                            .scaleEffect(checkShown ? 1 : 0.4)
                            .opacity(checkShown ? 1 : 0)
                        Text("saved to your history")
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        mantraCard
                        ZikrBento(count: savedSession.totalCount, seconds: savedSession.secondsPassed,
                                  secondsPerCount: savedSession.avgTimePerClick,
                                  perTasbeeh: savedSession.tasbeehRate)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)

                    Button {
                        triggerSomeVibration(type: .success)
                        isPresented = false
                        sharedState.titleForSession = ""
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.sage)
                            .background(Capsule().fill(Color.sage.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Button {
                        triggerSomeVibration(type: .light)
                        showHistory = true
                    } label: {
                        Label("View zikr history", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
                .fontDesign(.rounded)
            }
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.15)) { checkShown = true }
            }
            .onChange(of: chosenMantraName) {
                guard let newName = chosenMantraName, !newName.isEmpty else { return }
                withAnimation {
                    sharedState.titleForSession = newName
                    sharedState.mantraForSession = chosenMantraObject
                    savedSession.title = newName   // the saved session moves to that mantra
                    savedSession.mantra = chosenMantraObject
                    do { try context.save() } catch { print("Error saving context: \(error)") }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryPageView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showHistory = false }
                            }
                        }
                }
            }
        }

        private var mantraCard: some View {
            Button { showMantraPicker = true } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title.isEmpty ? "choose a mantra" : title)
                                .font(.system(size: 24, weight: .light, design: .rounded))
                                .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if !locked {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(isTasbihFatimah ? "33 · 33 · 34 after salah"
                             : locked ? "\(sessionLabel) · \(taskToday ?? "from your task")" : sessionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(cardShape.fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .contentShape(cardShape)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!locked)   // not .disabled: that grayed the card out
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

    
    /// The pause screen (redesigned 2026-09-25 — owner: the bottom buttons "didn't feel on
    /// brand", keep the bento, and make the mantra's full text and notes reachable). Top to
    /// bottom: "paused · 33 count session", the mantra card (name → picker, the full mantra, notes,
    /// its quick-add step, ✎ → the mantra's page), the stats bento, the finish estimate, then
    /// labelled setting chips and Finish / Resume. Tapping the dimmed background still resumes.
    struct pauseScreen_StatsSettingsBG: View {
        @EnvironmentObject var sharedState: SharedStateClass
        let paused: Bool
        let mantra: MantraModel?
        let tasbeeh: Int
        let secsToReport: TimeInterval
        let newAvrgTPC: TimeInterval
        let tasbeehRate: String
        let togglePause: () -> Void
        let stopTimer: () -> Void
        let takingNotes: Bool
        @Binding var toggleInactivityTimer: Bool
        @Binding var inactivityDimmer: Double
        @Binding var autoStop: Bool
        @Binding var tasbeehColorMode: Bool
        @Binding var currentVibrationMode: HapticFeedbackType

        // UI state
        @State private var finishArmed = false
        @State private var showMantraPicker = false
        @State private var chosenMantraName: String? = ""
        @State private var chosenMantraObject: MantraModel? = nil
        @State private var editingMantra: MantraModel?
        @State private var fullTextExpanded = false

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

        /// Count goal, not post-salah, started and not done: the bento adds the finish tile.
        private var showsFinishEstimate: Bool {
            sharedState.selectedMode == 2 && remainingCount > 0 && !sharedState.isDoingPostNamazZikr && tasbeeh > 0
        }

        private var sessionLabel: String {
            switch sharedState.selectedMode {
            case 1: return "\(sharedState.selectedMinutes) min session"
            case 2: return "\(sharedState.targetCount) count session"
            default: return "freestyle session"
            }
        }

        /// Launched from a task card: the session counts toward that task, so its mantra stays
        /// (same rule as `saveSession`'s task link).
        private var isTaskSession: Bool {
            sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr && sharedState.selectedTask != nil
        }
        /// Task and post-salah sessions keep their mantra; only free sessions can switch.
        private var mantraLocked: Bool { isTaskSession || sharedState.isDoingPostNamazZikr }

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

        var body: some View {
            Color("pauseColor")
                .edgesIgnoringSafeArea(.all)
                .animation(.easeOut(duration: 0.3), value: paused)
                .opacity(paused ? 1 : 0.0)
                .onTapGesture { togglePause() }
                .allowsHitTesting(paused)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill").font(.caption2)
                    Text(sharedState.isDoingPostNamazZikr ? "paused · Tasbih Fatimah" : "paused · \(sessionLabel)")
                }
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary)
                .padding(.top, 18)

                ScrollView {
                    VStack(spacing: 12) {
                        // Tasbih Fatimah is its own thing (owner): the three phrases and where the
                        // count is, instead of the mantra card (no edit, no count-in-sets).
                        if sharedState.isDoingPostNamazZikr {
                            PostSalahPauseCard(count: tasbeeh)
                        } else {
                            mantraCard
                        }
                        ZikrBento(count: tasbeeh, seconds: secsToReport, secondsPerCount: newAvrgTPC,
                                  perTasbeeh: tasbeehRate,
                                  finish: showsFinishEstimate ? (timeLeft, finishTime) : nil)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)

                controls
            }
            .fontDesign(.rounded)
            .opacity(paused ? 1.0 : 0.0)
            .animation(.easeInOut, value: paused)
            .allowsHitTesting(paused)
            .onChange(of: chosenMantraName) {
                if let newSetMantra = chosenMantraName, !newSetMantra.isEmpty {
                    withAnimation {
                        sharedState.mantraForSession = chosenMantraObject
                        sharedState.titleForSession = newSetMantra
                        fullTextExpanded = false
                    }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
            .sheet(item: $editingMantra, onDismiss: {
                // A rename: the session's title (what gets saved and shown) follows the mantra.
                if let mantra, sharedState.titleForSession != mantra.name {
                    sharedState.mantraForSession = mantra
                    sharedState.titleForSession = mantra.name
                }
            }) { mantra in
                MantraCardEditor(mantra: mantra)
            }
        }

        // MARK: mantra card

        private var mantraCard: some View {
            let title = sharedState.titleForSession
            return VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Button { showMantraPicker = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(title.isEmpty ? "choose a mantra" : title)
                                    .font(.system(size: 24, weight: .light, design: .rounded))
                                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                if !mantraLocked {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if isTaskSession {
                                Label("from your task", systemImage: "checklist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!mantraLocked)   // not .disabled: that grayed the name out
                    Spacer(minLength: 8)
                    if let mantra {
                        Button {
                            triggerSomeVibration(type: .light)
                            editingMantra = mantra
                        } label: {
                            Image(systemName: "pencil")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.sage)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.sage.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit mantra")
                    }
                }

                if let mantra {
                    let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !full.isEmpty {
                        // Arabic lines in the Uthmani face, the rest (transliteration,
                        // meaning) in the app's light rounded type.
                        VStack(spacing: 6) {
                            ForEach(Array(full.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let text = line.trimmingCharacters(in: .whitespaces)
                                if !text.isEmpty {
                                    let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                                    Text(text)
                                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: 26) : .system(size: 15, weight: .light, design: .rounded))
                                        .foregroundStyle(arabic ? .primary : .secondary)
                                        .lineSpacing(arabic ? 8 : 2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .lineLimit(fullTextExpanded ? nil : 4)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: fullTextExpanded ? nil : 190, alignment: .top)
                        .clipped()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy) { fullTextExpanded.toggle() }
                        }
                    }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.tertiary)
                            Text(notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                    if full.isEmpty && notes.isEmpty {
                        Button { editingMantra = mantra } label: {
                            Label("add the full mantra or notes", systemImage: "plus")
                                .font(.footnote)
                                .foregroundStyle(Color.sage)
                        }
                        .buttonStyle(.plain)
                    }
                } else if title.isEmpty {
                    Text("its full text, notes and sets show up here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                QuickAddStepRow(mantra: mantra)
                    .font(.subheadline)
            }
            .padding(16)
            .background(cardShape.fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }

        // MARK: controls

        private var controls: some View {
            VStack(spacing: 14) {
                if toggleInactivityTimer {
                    // Sleep mode's dimmer.
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill").font(.caption)
                        Slider(value: $inactivityDimmer, in: 0...1.0)
                            .tint(Color.sage)
                        Image(systemName: "sun.max.fill").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                // Tasbih Fatimah: just Finish / Resume (owner: none of the settings chips).
                if !sharedState.isDoingPostNamazZikr {
                HStack(spacing: 8) {
                    if sharedState.selectedMode != 0 {   // freestyle has no goal to stop at
                        chip(autoStop ? "stops at goal" : "keeps going",
                             icon: autoStop ? "flag.checkered" : "arrow.clockwise",
                             on: !autoStop) { autoStop.toggle() }
                    }
                    chip("sleep", icon: toggleInactivityTimer ? "moon.zzz.fill" : "moon.zzz", on: toggleInactivityTimer) {
                        toggleInactivityTimer.toggle()
                        if toggleInactivityTimer && !tasbeehColorMode { tasbeehColorMode = true }
                    }
                hapticsChip
                    chip(tasbeehColorMode ? "dark" : "light", icon: tasbeehColorMode ? "moon.fill" : "sun.max.fill",
                         on: false) { tasbeehColorMode.toggle() }
                }
                }
                HStack(spacing: 12) {
                    // Two taps (owner: cleaner than an "are you sure?"): the first arms it — a
                    // green edge and green text, "Tap to finish" — the second finishes; it
                    // disarms after 3 s. (Red read as a warning; owner.)
                    Button {
                        if finishArmed {
                            triggerSomeVibration(type: .medium)
                            finishArmed = false
                            stopTimer()
                        } else {
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy(duration: 0.2)) { finishArmed = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.snappy(duration: 0.2)) { finishArmed = false }
                            }
                        }
                    } label: {
                        Text(finishArmed ? "Tap to finish" : "Finish")
                            .fontWeight(.medium)
                            .contentTransition(.opacity)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(finishArmed ? Color.green : Color.primary)
                            .background(Capsule().strokeBorder(finishArmed ? Color.green : Color.primary.opacity(0.18),
                                                               lineWidth: finishArmed ? 1.5 : 1))
                            .contentShape(Capsule())
                    }
                    Button { togglePause() } label: {
                        Label("Resume", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.sage)
                            .background(Capsule().fill(Color.sage.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(.snappy(duration: 0.25), value: toggleInactivityTimer)
        }

        /// The phone with waves either side: one wave lit for light taps, two for medium, all
        /// three for strong (the symbols' variable value); the waves ripple outward and the
        /// phone buzzes each time it changes. Off: the phone with every wave dimmed.
        private var hapticsChip: some View {
            let level: Double = switch currentVibrationMode {
            case .off: 0
            case .light: 0.2     // a wave lights once the value passes 0, ⅓, ⅔
            case .heavy: 1
            default: 0.5
            }
            return Button {
                withAnimation(.snappy(duration: 0.2)) { cycleHaptics() }
            } label: {
                VStack(spacing: 6) {
                    // Our own "iphone.radiowaves": the phone between two three-wave symbols
                    // (the stock one has only two waves a side, so medium = strong).
                    HStack(spacing: 1) {
                        Image(systemName: "wave.3.left", variableValue: level)
                            .symbolEffect(.variableColor.iterative.nonReversing, options: .speed(1.6), value: currentVibrationMode)
                        Image(systemName: "iphone")
                            .font(.system(size: 17, weight: .light))
                            .symbolEffect(.bounce, value: currentVibrationMode)
                        Image(systemName: "wave.3.right", variableValue: level)
                            .symbolEffect(.variableColor.iterative.nonReversing, options: .speed(1.6), value: currentVibrationMode)
                    }
                    .font(.system(size: 11, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 20)
                    Text(hapticLabel)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(Color.primary.opacity(currentVibrationMode == .off ? 0.45 : 0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        private var hapticLabel: String {
            switch currentVibrationMode {
            case .off: return "no taps"
            case .light: return "light taps"
            case .heavy: return "strong taps"
            default: return "medium taps"
            }
        }

        private func cycleHaptics() {
            switch currentVibrationMode {
            case .off: currentVibrationMode = .light
            case .light: currentVibrationMode = .medium
            case .medium: currentVibrationMode = .heavy
            case .heavy: currentVibrationMode = .off
            default: currentVibrationMode = .medium
            }
            triggerSomeVibration(type: currentVibrationMode)
        }

        /// A labelled setting: symbol over a short word, soft tile; sage while on.
        private func chip(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(.snappy(duration: 0.2)) { action() }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .light))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 20)
                    Text(title)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(on ? Color.sage : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }

    }

    
    struct TopOfSessionButton: View{
        var symbol: String? = nil   // an SF Symbol…
        var text: String? = nil     // …or a short label like "+10"
        let actionToDo: () -> Void
        let paused: Bool
        let togglePause: () -> Void

        init(symbol: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void) {
            self.symbol = symbol; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
        }
        init(text: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void) {
            self.text = text; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
        }
        
        var body: some View{
            Button(action: paused ? togglePause : actionToDo) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 20, height: 20)
                    } else {
                        Text(text ?? "")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(minWidth: 20, minHeight: 20)
                    }
                }
                    .foregroundColor(.gray.opacity(0.3))
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


/// Post-salah zikr (redesigned 2026-09-25): one 100-count session — Subhanallah ×33,
/// Alhamdulillah ×33, Allahu Akbar ×34 — saved once, under a "Tasbih Fatimah" mantra (the
/// traditional name for it), instead of three chained sessions that each reset the count, saved
/// separately and ended without a results screen. The phrase follows the count.
enum PostSalahTasbeeh {
    static let mantraName = "Tasbih Fatimah"
    static let phases: [(name: String, arabic: String, count: Int)] = [
        ("Subhanallah", "سُبْحَانَ ٱللَّٰهِ", 33),
        ("Alhamdulillah", "ٱلْحَمْدُ لِلَّٰهِ", 33),
        ("Allahu Akbar", "ٱللَّٰهُ أَكْبَرُ", 34),
    ]
    static var total: Int { phases.reduce(0) { $0 + $1.count } }

    /// The phrase at a total count, and how far into it (0-based index; `done` of `of`).
    static func phase(at count: Int) -> (index: Int, done: Int, of: Int) {
        var start = 0
        for (i, p) in phases.enumerated() {
            if count < start + p.count || i == phases.count - 1 {
                return (i, min(count - start, p.count), p.count)
            }
            start += p.count
        }
        return (0, 0, phases[0].count)
    }

    /// Sets up the session: a 100-count goal on the Tasbih Fatimah mantra (made on first use,
    /// with the three phrases as its full text so the pause card shows them).
    static func prepare(_ state: SharedStateClass, in context: ModelContext) {
        let mantra = MantraModel.find(named: mantraName, in: context) ?? {
            let text = phases.map { "\($0.arabic)  ×\($0.count)" }.joined(separator: "\n")
                + "\nSubhanallah · Alhamdulillah · Allahu Akbar"
            let new = MantraModel(name: mantraName, fullText: text,
                                  notes: "After each obligatory prayer: 33, 33 and 34 — 100 in all.")
            context.insert(new)
            return new
        }()
        state.selectedMode = 2
        state.selectedMinutes = 0
        state.targetCount = String(total)
        state.mantraForSession = mantra
        state.titleForSession = mantra.name
    }
}

/// Under the circle during post-salah zikr: why it's worth the minute (owner asked for a
/// reminder of its significance). Both narrations are the well-known ones: the 33/33/34 after
/// each obligatory prayer (Sahih Muslim, from Ka'b ibn 'Ujrah) and the Prophet ﷺ teaching the
/// same words to Fatimah as better than a servant (Bukhari and Muslim, from 'Ali).
struct PostSalahReminder: View {
    var variant = 0

    /// Why this zikr matters, to move people to do it (owner): a short headline — the reason — and
    /// the narration behind it. One per session. Well-known narrations, paraphrased; no hadith
    /// numbers until checked.
    static let reminders: [(title: String, text: String, source: String)] = [
        ("Never let down",
         "Whoever says these after every obligatory prayer is never disappointed.",
         "Sahih Muslim"),
        ("Keep pace with the best",
         "The poor feared the wealthy were ahead of them in charity. The Prophet ﷺ gave them these words after every prayer: no one would surpass them, except one who did the same.",
         "Sahih al-Bukhari · Sahih Muslim"),
        ("They fill the scales",
         "Alhamdulillah fills the Scale, and Subhanallah with Alhamdulillah fill what is between the heavens and the earth.",
         "Sahih Muslim"),
        ("Better than a servant",
         "Worn out by her work, Fatimah asked for a servant. The Prophet ﷺ gave her these hundred words instead, and said they were better for her.",
         "Sahih al-Bukhari · Sahih Muslim"),   // its text doesn't say when — it was taught for bedtime
    ]
    static var count: Int { reminders.count }

    var body: some View {
        let r = Self.reminders[variant % Self.count]
        VStack(spacing: 8) {
            Text(r.title)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
            Text(r.text)
                .font(.footnote.weight(.light))
                .foregroundStyle(.secondary)
            Text(r.source)
                .font(.caption2)
                .foregroundStyle(Color.sage)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .fontDesign(.rounded)
    }
}

/// The pause screen's card for Tasbih Fatimah: the three phrases as rows — done ✓, the current
/// one with its count, the rest to come — plus the hadith's line. Replaces the mantra card
/// (nothing to edit here; owner: "it's a special one").
struct PostSalahPauseCard: View {
    let count: Int

    var body: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        VStack(alignment: .leading, spacing: 14) {
            Text(PostSalahTasbeeh.mantraName)
                .font(.system(size: 24, weight: .light, design: .rounded))
            VStack(spacing: 8) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, phrase in
                    let done = i < now.index || (i == now.index && now.done >= now.of)
                    let current = i == now.index && !done
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phrase.name)
                                .font(.system(size: 16, weight: current ? .regular : .light, design: .rounded))
                                .foregroundStyle(current ? .primary : .secondary)
                            Text(done ? "done" : current ? "\(now.done) of \(phrase.count)" : "\(phrase.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(done ? Color.green : .secondary)
                        }
                        Spacer(minLength: 8)
                        Text(phrase.arabic)
                            .font(.custom("KFGQPCUthmanTahaNaskh", size: 24))
                            .foregroundStyle(current ? .primary : .secondary)
                            .environment(\.layoutDirection, .rightToLeft)
                        Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(done ? Color.green : current ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(width: 22)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(current ? Color.green.opacity(0.08) : Color.primary.opacity(0.03))
                    )
                }
            }
            Text("Never disappointed — Sahih Muslim")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

/// Above the circle during post-salah zikr: the current phrase (Arabic + name), its own count,
/// and three segments that fill phrase by phrase.
struct PostSalahPhaseStrip: View {
    let count: Int

    var body: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        let phrase = PostSalahTasbeeh.phases[now.index]
        VStack(spacing: 8) {
            Text(phrase.arabic)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 30))
                .id(now.index)
                .transition(.blurReplace)
            HStack(spacing: 6) {
                Text(phrase.name)
                Text("·").foregroundStyle(.tertiary)
                Text("\(now.done) of \(now.of)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(now.done)))
            }
            .font(.subheadline.weight(.light))
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, p in
                    let fill: Double = i < now.index ? 1 : i > now.index ? 0 : Double(now.done) / Double(p.count)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.sage).frame(width: geo.size.width * fill)
                        }
                    }
                    .frame(width: 44, height: 4)
                }
            }
        }
        .fontDesign(.rounded)
        .animation(.snappy(duration: 0.3), value: count)
    }
}

/// Count, time and rate as glass tiles (same material and light rounded type as the pause
/// screen's mantra card), shared by the pause and results screens. Count and time stacked on
/// the left, rate on the right — tap it to flip per count ↔ per tasbeeh. With `finish` (a count goal in progress) a full-width tile underneath says when
/// you'll be done — "in 1m 20s", tap → "6:42 PM" — a tile so it reads as something to tap
/// (owner, 2026-09-25; it used to be loose caption text under the boxes).
struct ZikrBento: View {
    let count: Int
    let seconds: TimeInterval
    let secondsPerCount: Double
    let perTasbeeh: String
    var finish: (timeLeft: TimeInterval, at: Date)? = nil
    /// Lifetime use (a mantra's page): "25m 56s" instead of a stopwatch, other captions, and
    /// flat grouped-list tiles instead of glass.
    var timeText: String? = nil
    var countCaption = "count"
    var timeCaption = "time"
    var grouped = false

    @State private var showingPerCount = true
    @State private var showingFinishTime = false

    private let gap: CGFloat = 10
    private let tileHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    // Count and time just show (the old spin-and-buzz on tap did nothing — owner).
                    tile {
                        row(icon: "circle.hexagonpath", value: count.formatted(), caption: countCaption)
                    }
                    tile {
                        row(icon: "gauge.with.needle", value: timeText ?? timerStyle(seconds), caption: timeCaption)
                    }
                }

                tile {
                    VStack(spacing: 4) {
                        Text("rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        flip(showingPerCount,
                             String(format: "%.2fs", secondsPerCount), "per count",
                             perTasbeeh, "per tasbeeh", size: 30)
                    }
                }
                .frame(height: tileHeight * 2 + gap)
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingPerCount.toggle() }
                }
            }

            if let finish {
                tile {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        ZStack(alignment: .leading) {
                            sentence(String(inMinSecStyle2(from: finish.timeLeft).dropFirst(3)), "left until you finish")
                                .opacity(showingFinishTime ? 0 : 1)
                                .offset(y: showingFinishTime ? -16 : 0)
                            sentence(shortTime(finish.at), "is your estimated finish")
                                .opacity(showingFinishTime ? 1 : 0)
                                .offset(y: showingFinishTime ? 0 : 16)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: tileHeight)
                }
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingFinishTime.toggle() }
                }
                .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // tiles keep their height outside a ScrollView
    }

    /// "1m 37s left until you finish" as one line: the number first in the tiles' type, the
    /// words after it, quiet (owner, 2026-09-25).
    private func sentence(_ value: String, _ words: String) -> some View {
        (Text(value).font(.system(size: 22, weight: .light, design: .rounded))
            + Text(" " + words).font(.subheadline).foregroundColor(.secondary))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: tileHeight)
            .background {
                if grouped {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(grouped ? 0 : 0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(grouped ? 0 : 0.1), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(icon: String, value: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            valueStack(value, caption, size: 22, leading: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: tileHeight)
    }

    /// Two value / caption pairs in one place; the shown one slides up and out as the other
    /// slides in (the rate box's old flip).
    private func flip(_ showFirst: Bool, _ v1: String, _ c1: String, _ v2: String, _ c2: String,
                      size: CGFloat, leading: Bool = false) -> some View {
        ZStack(alignment: leading ? .leading : .center) {
            valueStack(v1, c1, size: size, leading: leading)
                .opacity(showFirst ? 1 : 0)
                .offset(y: showFirst ? 0 : -16)
            valueStack(v2, c2, size: size, leading: leading)
                .opacity(showFirst ? 0 : 1)
                .offset(y: showFirst ? 16 : 0)
        }
    }

    private func valueStack(_ value: String, _ caption: String, size: CGFloat, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: leading ? 0 : 2) {
            Text(value)
                .font(.system(size: size, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, leading ? 0 : 10)
    }
}

#Preview {
    @Previewable @StateObject var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool)
        .environmentObject(sharedState) // Inject shared state into the environment
}
