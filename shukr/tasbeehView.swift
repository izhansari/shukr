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

    
    // State properties
    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    @State private var paused = false
    @State private var tasbeeh = 0
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var pauseStartTime: Date? = nil
    @State private var autoStop = true
    @State private var currentVibrationMode: HapticFeedbackType = .medium

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
        
//        let roundedSeconds = Int(round(secsPassed))
//        let hours = roundedSeconds / 3600
//        let minutes = (roundedSeconds % 3600) / 60
//        let seconds = roundedSeconds % 60
//        
//        if hours > 0 {
//            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
//        } else {
//            return String(format: "%02d:%02d", minutes, seconds)
//        }
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
                        isPresented = false
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
                                            progressFraction = CGFloat(Int(secsPassed))/TimeInterval(totalTime)
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
                    }
                    
                    // Pause Screen (background overlay, stats & settings)
                    ZStack {
                        // middle screen when paused
                        pauseStatsAndBG(
                            paused: paused,
                            tasbeeh: tasbeeh,
                            timePassedAtPause: timePassedAtPauseString,
                            avgTimePerClick: newAvrgTPC,
                            tasbeehRate: tasbeehRate,
                            togglePause: { togglePause() },
                            takingNotes: takingNotes
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
                                    Image(systemName: "checkmark.circle.fill" /*"xmark.circle.fill"*/)
                                        .font(.system(size: 26))
                                        .foregroundColor(.green.opacity(0.5))
                                        .padding()
                                        .background(.clear)
                                        .cornerRadius(10)
    
//                                    Image(systemName: "checkmark")
//                                        .font(.system(size: 20, weight: .bold))
//                                        .foregroundColor(.gray.opacity(0.6))
//                                        .frame(width: 10, height: 10)
//                                        .padding()
//                                        .background(.green.opacity(0.18))
//                                        .cornerRadius(100)
//                                        .opacity(1.0)
//                                        .padding(.leading, 4)
                                    
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
                                                
                        // Stop Button when not auto stopping
                            stopButton(stopTimer: stopTimer)
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
                            Spacer()
                            inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                        }
                            .zIndex(1)
                    }
                    .animation(.easeInOut(duration: 0.5), value: toggleInactivityTimer)
                    
                    // results page
                    ZStack{
                        if let session = savedSession{
                            ResultsView(
                                isPresented: $isPresented,
                                savedSession: session  // Pass the saved session
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
        .onDisappear{
            sharedState.titleForSession = ""
        }
        .preferredColorScheme(colorModeToggle ? .dark : .light)
    }
//--------------------------------------functions--------------------------------------
    
    
    private func startTimer() {
        // Reset necessary variables for a new session
        tasbeeh = 0
        
        savedSession = nil
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: sharedState.selectedMinutes, to: startTime!)
        totalPauseInSession = 0
        secsToReport = 0
        timerIsActive = true //this just ensures increment, decrement and reset dont happen outside of session
        
        triggerSomeVibration(type: .success)
        
        UIApplication.shared.isIdleTimerDisabled = true
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change

    }
    
    private func saveSession() -> SessionDataModel {
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
    
//    private func stopTimer() {
//                
//        if(tasbeeh > 0){
//            savedSession = saveSession()  // New function
//            //add call to make function wait 0.5 seconds before continuing
//        }
//                
//        // Stop and invalidate the timer
//        timer?.invalidate()
//        timer = nil
//        
//        // allow idle timer again
//        UIApplication.shared.isIdleTimerDisabled = false
//        
//        // Reset all state variables to clean up the session
//        timerIsActive = false
//
//        endTime = nil
//        startTime = nil
//        
//        progressFraction = 0
//        
//        sharedState.targetCount = ""
//        
//        noteModalText = ""
//        
//        !stoppedDueToInactivity ? triggerSomeVibration(type: .vibrate) : ()
//        
//        stoppedDueToInactivity = false
//        
//        inactivityTimerHandler(run: "stop")
//        
//        toggleInactivityTimer = false
//        
//        paused = false
//        
//        if tasbeeh == 0{
//            isPresented = false
//        }
//
//    }
    
    private func stopTimer() {
        if tasbeeh > 0 {
            savedSession = saveSession()  // New function
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.completeStopTimer() // Continue with the rest of the function after the delay
            }
        } else {
            completeStopTimer() // If tasbeeh is 0 or less, continue without delay
        }
    }

    private func completeStopTimer() {
        // Stop and invalidate the timer
        timer?.invalidate()
        timer = nil
        
        // allow idle timer again
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Reset all state variables to clean up the session
        timerIsActive = false
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
        }
    }
    
    private func togglePause() {
        paused.toggle()
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change
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
            print("tasbeeh on inc:  \(tasbeeh)")
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
        .modelContainer(for: Item.self, inMemory: true)
        .environmentObject(sharedState) // Inject shared state into the environment
}



/*
 Current Improvement Focus:
 
 Improvements needed:
 - break it apart. make it two diff pages.
 - make MantraModel hold all information regarding total count
 */



struct ResultsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Binding var isPresented: Bool
    let savedSession: SessionDataModel  // Add this

    // UI state
    private let textSize: CGFloat = 14
    private let gapSize: CGFloat = 10
    @State private var countRotation: Double = 0
    @State private var timerRotation: Double = 0
    @State private var showingPerCount = false
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
                    action: { isPresented = false }
                )
                .padding(.bottom)
            }
        }
    }
    
    private var completionCard: some View {
        VStack(alignment: .center, spacing: 12) {
            // Checkmark circle
            Circle()
                .fill(Color(colorScheme == .dark ? .systemGray4 : .white))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.green)
                }
            
            // Message
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
                                Text(formatSecondsToTimerString(secsToReport))
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
                                .offset(y: showingPerCount ? -20 : 0)
                                
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
                                .offset(y: showingPerCount ? 0 : 20)
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
    
    private var mantraSelector: some View {
        Text(sharedState.titleForSession.isEmpty ? "no selected mantra" : sharedState.titleForSession)
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
    
//    struct CloseButton: View {
//        let action: () -> Void
//        
//        var body: some View {
//            ZStack {
//                // Background
//                RoundedRectangle(cornerRadius: 10)
//                    .fill(Color.gray.opacity(0.08))
//                
//                // Progress outline
//                RoundedRectangle(cornerRadius: 10)
//                    .stroke(Color.gray, lineWidth: 1.5)
//                
//                // Content
//                VStack(spacing: 4) {
//                    Text("close")
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                }
//            }
//            .frame(width: 100, height: 50)
//            .contentShape(Rectangle())
//            .onTapGesture(perform: action)
//        }
//    }
}

#Preview {
    ResultsView(
        isPresented: .constant(true),
        savedSession: SessionDataModel(
            title: "yo",
            sessionMode: 1,
            targetMin: 1,
            targetCount: Int(5) ?? 0,
            totalCount: 66,
            startTime: Date(),
            secondsPassed: 72,
            avgTimePerClick: 0.54,
            tasbeehRate: "10m 4s"
        )
    )
    .environmentObject(SharedStateClass())
}


//tasbeeh: savedSession.totalCount,
//secsToReport: savedSession.secondsPassed,
//tasbeehRate: savedSession.tasbeehRate,
//newAvrgTPC: savedSession.avgTimePerClick
