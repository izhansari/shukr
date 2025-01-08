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
    @Query private var sessionItems: [SessionDataModel]
    
    // AppStorage properties
    @AppStorage("streak") var streak = 0
    @AppStorage("inactivityToggle") var toggleInactivityTimer = false
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5
    @AppStorage("vibrateToggle") var vibrateToggle = true
    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("currentVibrationMode") private var currentVibrationMode: HapticFeedbackType = .medium
    //    @AppStorage("inactivityToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    //    var toggleInactivityTimer = false
    //    @AppStorage("vibrateToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    //    var vibrateToggle = true
    
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






import AppIntents
import Adhan

/// Utility class for shared functionality
struct PrayerUtils {
    /// Fetches user location from UserDefaults
    static func getUserCoordinates() throws -> Coordinates {
        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
        
        guard latitude != 0, longitude != 0 else {
            throw PrayerError(message: "Location not available. Please open the app first.")
        }
        
        return Coordinates(latitude: latitude, longitude: longitude)
    }
    
    /// Fetches calculation parameters based on UserDefaults
    static func getCalculationParameters() -> CalculationParameters {
        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
        
        let calculationMethod: CalculationMethod = {
            switch calcMethodInt {
            case 1: return .karachi
            case 2: return .northAmerica
            case 3: return .muslimWorldLeague
            case 4: return .ummAlQura
            case 5: return .egyptian
            case 7: return .tehran
            case 8: return .dubai
            case 9: return .kuwait
            case 10: return .qatar
            case 11: return .singapore
            case 12, 14: return .other
            case 13: return .turkey
            default: return .northAmerica
            }
        }()
        
        var params = calculationMethod.params
        params.madhab = madhab
        return params
    }
    
    /// Fetches prayer times for a specific date
    static func getPrayerTimes(for date: Date, coordinates: Coordinates, params: CalculationParameters) throws -> PrayerTimes {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        
        guard let prayerTimes = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) else {
            throw PrayerError(message: "Unable to calculate prayer times for \(date).")
        }
        
        return prayerTimes
    }
    
    /// Generic prayer time retrieval
    static func getPrayerTime(for prayer: enumPrayer, in times: PrayerTimes) -> Date {
        switch prayer {
        case .fajr: return times.fajr
        case .sunrise: return times.sunrise
        case .dhuhr: return times.dhuhr
        case .asr: return times.asr
        case .maghrib: return times.maghrib
        case .isha: return times.isha
        }
    }
}

/// Custom error for prayer intents
struct PrayerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// AppEnum for Prayer Selection
enum enumPrayer: String, AppEnum {
    case fajr = "Fajr"
    case sunrise = "Sunrise"
    case dhuhr = "Dhuhr"
    case asr = "Asr"
    case maghrib = "Maghrib"
    case isha = "Isha"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static var caseDisplayRepresentations: [enumPrayer: DisplayRepresentation] = [
        .fajr: "Fajr",
        .sunrise: "Sunrise",
        .dhuhr: "Dhuhr",
        .asr: "Asr",
        .maghrib: "Maghrib",
        .isha: "Isha"
    ]
}

/// AppEnum for Prayer Selection
enum enumFajrSunrisePrayer: String, AppEnum {
    case fajr = "Fajr"
    case sunrise = "Sunrise"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static var caseDisplayRepresentations: [enumFajrSunrisePrayer: DisplayRepresentation] = [
        .fajr: "Fajr",
        .sunrise: "Sunrise",
    ]
}

/// AppEnum for Reference Point
enum ReferencePoint: String, AppEnum {
    case after = "after"
    case before = "before"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reference Point"
    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
        .after: "after",
        .before: "before"
    ]
}

/// Intent: Get Time of Chosen Prayer
struct GetSomePrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time of Chosen Prayer"
    static var description: LocalizedStringResource = "Returns the time for the selected prayer."
    
    @Parameter(title: "Prayer", description: "Select which prayer time you want.")
    var prayer: enumPrayer
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get start time for \(\.$prayer)")
    }
    
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        return .result(value: nextPrayerTime, dialog: IntentDialog(stringLiteral: "\(prayer) will be at \(shortTimePM(nextPrayerTime))"))
    }
}

/// Intent: Get Next Fajr Time
struct GetNextFajrIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Fajr Time"
    static var description: LocalizedStringResource = "Returns the next Fajr prayer time."
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let nextFajr = Date() > todayTimes.fajr ? tomorrowTimes.fajr : todayTimes.fajr
        return .result(value: nextFajr, dialog: IntentDialog(stringLiteral: "Fajr will be at \(shortTimePM(nextFajr))"))
    }
}

/// Intent: Get Offset Time Relative to Any Prayer
struct GetOffsetTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Offset Time Relative to Prayer"
    static var description: LocalizedStringResource = "Returns a time offset from any prayer."
    
    @Parameter(title: "Minutes", description: "Number of minutes to offset.")
    var offsetMinutes: Int
    
    @Parameter(title: "Reference Point", description: "Offset after or before the prayer.")
    var referencePoint: ReferencePoint
    
    @Parameter(title: "Prayer", description: "Select the prayer reference.")
    var prayer: enumPrayer
    
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get time \(\.$offsetMinutes) minutes \(\.$referencePoint) \(\.$prayer)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        let offset = TimeInterval(offsetMinutes * 60)
        let resultTime = referencePoint == .after ? nextPrayerTime.addingTimeInterval(offset) : nextPrayerTime.addingTimeInterval(-offset)
        
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: "\(offsetMinutes) minutes \(referencePoint) \(prayer) will be at \(shortTimePM(resultTime))"))
    }
}



/// Intent: Get Offset Time Relative to Fajr or Sunrise
struct SetFajrAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Autopilot Fajr Alarm Time"
    static var description: LocalizedStringResource = "Dynamically returns a time offset from Fajr or Sunrise (rules defined in the Shukr app settings)"
        
    @AppStorage("alarmEnabled") private var alarmEnabled: Bool = false
    @AppStorage("alarmOffsetMinutes") private var alarmOffsetMinutes: Int = 0
    @AppStorage("alarmIsBefore") private var alarmIsBefore: Bool = false
    @AppStorage("alarmIsFajr") private var alarmIsFajr: Bool = false

    /// Custom Error for Disabled Alarm
    struct AlarmDisabledError: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Daily Fajr Alarm is disabled. Please enable it in the Shukr app settings."
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        
        // 1) Stop if alarm is disabled:
        if !alarmEnabled {
            throw AlarmDisabledError()
        }
        
        let coordinates = try PrayerUtils.getUserCoordinates()
        let params = PrayerUtils.getCalculationParameters()
        
        let todayTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
        let tomorrowTimes = try PrayerUtils.getPrayerTimes(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, coordinates: coordinates, params: params)
        
        let prayer: enumPrayer = alarmIsFajr ? .fajr : .sunrise
        
        let prayerTime = PrayerUtils.getPrayerTime(for: prayer, in: todayTimes)
        let nextPrayerTime = Date() > prayerTime ? PrayerUtils.getPrayerTime(for: prayer, in: tomorrowTimes) : prayerTime
        
        let offset = TimeInterval(alarmOffsetMinutes * 60)
        let resultTime = nextPrayerTime.addingTimeInterval((alarmIsBefore ? -offset : offset))
        
        let offsetMinutesText = "\(alarmOffsetMinutes) minute\(alarmOffsetMinutes == 1 ? "" : "s")"
        let message = "\(offsetMinutesText) \(alarmOffsetMinutes) \(prayer) will be at \(shortTimePM(resultTime))"
        
        print("\(message)")
        
        return .result(value: resultTime, dialog: IntentDialog(stringLiteral: message))
    }
}





//enum enumPrayer: String, AppEnum {
//    case fajr = "Fajr"
//    case sunrise = "Sunrise"
//    case dhuhr = "Dhuhr"
//    case asr = "Asr"
//    case maghrib = "Maghrib"
//    case isha = "Isha"
//    
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
//    static var caseDisplayRepresentations: [enumPrayer: DisplayRepresentation] = [
//        .fajr: "Fajr",
//        .sunrise: "Sunrise",
//        .dhuhr: "Dhuhr",
//        .asr: "Asr",
//        .maghrib: "Maghrib",
//        .isha: "Isha"
//    ]
//}
//
//struct GetNextPrayerTimeIntent: AppIntent {
//    static var title: LocalizedStringResource = "Get Next Prayer Time"
//    static var description: LocalizedStringResource = "Returns the next time for the selected prayer"
//    
//    @Parameter(title: "Prayer", description: "Select which prayer time you want")
//    var prayer: enumPrayer
//    
//    @MainActor
//    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
//        // Get coordinates from UserDefaults
//        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
//        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
//        
//        guard latitude != 0, longitude != 0 else {
//            throw Error("Location not available. Please open the app first.")
//        }
//        
//        // Set up coordinates and calculation parameters
//        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
//        
//        // Get calculation method from UserDefaults
//        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
//        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
//        
//        let calculationMethod: CalculationMethod = {
//            switch calcMethodInt {
//            case 1: return .karachi
//            case 2: return .northAmerica
//            case 3: return .muslimWorldLeague
//            case 4: return .ummAlQura
//            case 5: return .egyptian
//            case 7: return .tehran
//            case 8: return .dubai
//            case 9: return .kuwait
//            case 10: return .qatar
//            case 11: return .singapore
//            case 12, 14: return .other
//            case 13: return .turkey
//            default: return .northAmerica
//            }
//        }()
//        
//        var params = calculationMethod.params
//        params.madhab = madhab
//        
//        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
//        let tmmComponents = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
//        
//        guard let todayPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                                date: todayComponents,
//                                                calculationParameters: params) else {
//            throw Error("Unable to calculate today's prayer times")
//        }
//        
//        guard let tmmPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                              date: tmmComponents,
//                                              calculationParameters: params) else {
//            throw Error("Unable to calculate tomorrow's prayer times")
//        }
//        
//        // Get the prayer time based on selection
//        func getPrayerTime(_ times: PrayerTimes) -> Date {
//            switch prayer {
//            case .fajr: return times.fajr
//            case .sunrise: return times.sunrise
//            case .dhuhr: return times.dhuhr
//            case .asr: return times.asr
//            case .maghrib: return times.maghrib
//            case .isha: return times.isha
//            }
//        }
//        
//        let x = todayPrayerTimes.nextPrayer()
//        let todayTime = getPrayerTime(todayPrayerTimes)
//        let nextTime = Date() > todayTime ? getPrayerTime(tmmPrayerTimes) : todayTime
//        
//        return .result(value: nextTime)
//    }
//}
//
//// Custom error type
//extension GetNextPrayerTimeIntent {
//    struct Error: Swift.Error {
//        let message: String
//        
//        init(_ message: String) {
//            self.message = message
//        }
//    }
//}
//
//import AppIntents
//import Adhan
//
//struct GetNextFajrIntent: AppIntent {
//    static var title: LocalizedStringResource = "Get Next Fajr Time"
//    static var description: LocalizedStringResource = "Returns the next Fajr prayer time"
//    
//    @MainActor
//    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
//        // Get coordinates from UserDefaults
//        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
//        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
//        
//        guard latitude != 0, longitude != 0 else {
//            throw Error("Location not available. Please open the app first.")
//        }
//        
//        // Set up coordinates and calculation parameters
//        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
//        
//        // Get calculation method from UserDefaults
//        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
//        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
//        
//        let calculationMethod: CalculationMethod = {
//            switch calcMethodInt {
//            case 1: return .karachi
//            case 2: return .northAmerica
//            case 3: return .muslimWorldLeague
//            case 4: return .ummAlQura
//            case 5: return .egyptian
//            case 7: return .tehran
//            case 8: return .dubai
//            case 9: return .kuwait
//            case 10: return .qatar
//            case 11: return .singapore
//            case 12, 14: return .other
//            case 13: return .turkey
//            default: return .northAmerica
//            }
//        }()
//        
//        var params = calculationMethod.params
//        params.madhab = madhab
//        
//        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
//        let tmmComponents = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
//        
//        guard let todayPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                                date: todayComponents,
//                                                calculationParameters: params) else {
//            throw Error("Unable to calculate today's prayer times")
//        }
//        
//        guard let tmmPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                              date: tmmComponents,
//                                              calculationParameters: params) else {
//            throw Error("Unable to calculate tomorrow's prayer times")
//        }
//        
//        let nextFajr = Date() > todayPrayerTimes.fajr ? tmmPrayerTimes.fajr : todayPrayerTimes.fajr
//        
//        // Convert the Date to IntentTime
//        return .result(value: nextFajr)
//    }
//}
//
//// Custom error type
//extension GetNextFajrIntent {
//    struct Error: Swift.Error {
//        let message: String
//        
//        init(_ message: String) {
//            self.message = message
//        }
//    }
//}
//

//struct PrayerTimeShortcuts: AppShortcutsProvider {
//    static var appShortcuts: [AppShortcut] {
//        AppShortcut(
//            intent: GetNextFajrIntent(),
//            phrases: [
//                "Get Next Fajr time from \(.applicationName)",
//                "When is Fajr",
//                "Get Fajr time from \(.applicationName)",
//                "Fajr time from \(.applicationName)",
//                "Get morning prayer time from \(.applicationName)",
//                "morning prayer time from \(.applicationName)"
//            ],
//            shortTitle: "Fajr Time",
//            systemImageName: "sunrise.fill"
//        )
//    }
//}

struct PrayerTimeShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNextFajrIntent(),
            phrases: [
                "Get Next Fajr time from \(.applicationName)",
                "When is Fajr",
                "Get Fajr time from \(.applicationName)",
                "Fajr time from \(.applicationName)",
                "Get morning prayer time from \(.applicationName)",
                "morning prayer time from \(.applicationName)"
            ],
            shortTitle: "Fajr Time",
            systemImageName: "sunrise.fill"
        )
        
        AppShortcut(
            intent: GetSomePrayerTimeIntent(),
            phrases: [
                "Get next prayer time from \(.applicationName)",
                "When is the next prayer",
                "Next prayer time from \(.applicationName)",
                "What's the upcoming prayer time"
            ],
            shortTitle: "Some Prayer Time",
            systemImageName: "clock.fill"
        )
        
        AppShortcut(
            intent: GetOffsetTimeIntent(),
            phrases: [
                "Get offset prayer time from \(.applicationName)"
            ],
            shortTitle: "Offset Prayer Time",
            systemImageName: "clock.badge.questionmark"
        )
        
    }
}

//
//
//
//
//
//
//
//import AppIntents
//import Adhan
//
//enum ReferencePoint: String, AppEnum {
//    case after = "after"
//    case before = "before"
//    
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reference Point"
//    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
//        .after: "after",
//        .before: "before"
//    ]
//}
//
//enum PrayerTime: String, AppEnum {
//    case fajr = "Fajr"
//    case sunrise = "Sunrise"
//    
//    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Choose Time"
//    static var caseDisplayRepresentations: [PrayerTime: DisplayRepresentation] = [
//        .fajr: "after Fajr",
//        .sunrise: "before Sunrise"
//    ]
//}
//
//struct GetOffsetTimeIntent: AppIntent {
//    static var title: LocalizedStringResource = "Get Time Relative to Prayer"
//    static var description: LocalizedStringResource = "Returns a time offset from Fajr or Sunrise"
//    
//    @Parameter(title: "Minutes", description: "Number of minutes to offset")
//    var offsetMinutes: Int
//    
//    @Parameter(title: "Prayer Time", description: "Choose the prayer time reference")
//    var prayerTime: PrayerTime
//    
//    static var parameterSummary: some ParameterSummary {
//        Summary("\(\.$offsetMinutes) minutes \(\.$prayerTime)")
//    }
//    
//    @MainActor
//    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
//        // Get coordinates from UserDefaults
//        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
//        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
//        
//        guard latitude != 0, longitude != 0 else {
//            throw Error("Location not available. Please open the app first.")
//        }
//        
//        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
//        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
//        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
//        
//        let calculationMethod: CalculationMethod = {
//            switch calcMethodInt {
//            case 1: return .karachi
//            case 2: return .northAmerica
//            case 3: return .muslimWorldLeague
//            case 4: return .ummAlQura
//            case 5: return .egyptian
//            case 7: return .tehran
//            case 8: return .dubai
//            case 9: return .kuwait
//            case 10: return .qatar
//            case 11: return .singapore
//            case 12, 14: return .other
//            case 13: return .turkey
//            default: return .northAmerica
//            }
//        }()
//        
//        var params = calculationMethod.params
//        params.madhab = madhab
//        
//        // Get prayer times for today and tomorrow
//        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
//        let tmmComponents = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
//        
//        guard let todayPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                                date: todayComponents,
//                                                calculationParameters: params) else {
//            throw Error("Unable to calculate today's prayer times")
//        }
//        
//        guard let tmmPrayerTimes = PrayerTimes(coordinates: coordinates,
//                                              date: tmmComponents,
//                                              calculationParameters: params) else {
//            throw Error("Unable to calculate tomorrow's prayer times")
//        }
//        
//        // Get reference times
//        let getReferenceTime: (PrayerTimes) -> Date = { times in
//            switch self.prayerTime {
//            case .fajr: return times.fajr
//            case .sunrise: return times.sunrise
//            }
//        }
//        
//        let todayReferenceTime = getReferenceTime(todayPrayerTimes)
//        let nextReferenceTime = Date() > todayReferenceTime ? getReferenceTime(tmmPrayerTimes) : todayReferenceTime
//        
//        // Calculate the offset time
//        let offsetInterval = TimeInterval(offsetMinutes * 60) // Convert minutes to seconds
//        let resultTime = prayerTime == .fajr
//            ? nextReferenceTime.addingTimeInterval(offsetInterval)
//            : nextReferenceTime.addingTimeInterval(-offsetInterval)
//        
//        return .result(value: resultTime)
//    }
//}
//
//// Custom error type
//extension GetOffsetTimeIntent {
//    struct Error: Swift.Error {
//        let message: String
//        
//        init(_ message: String) {
//            self.message = message
//        }
//    }
//}
//
//
//
//
//// working one but ugly representation
////import AppIntents
////import Adhan
////
////// Enum for selecting reference prayer
////enum ReferencePoint: String, AppEnum {
////    case afterFajr = "After Fajr"
////    case beforeSunrise = "Before Sunrise"
////
////    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reference Point"
////    static var caseDisplayRepresentations: [ReferencePoint: DisplayRepresentation] = [
////        .afterFajr: "After Fajr Start",
////        .beforeSunrise: "Before Sunrise"
////    ]
////}
////
////struct GetOffsetTimeIntent: AppIntent {
////    static var title: LocalizedStringResource = "Get Time Relative to Prayer"
////    static var description: LocalizedStringResource = "Returns a time offset from Fajr or Sunrise"
////
////    @Parameter(title: "Reference Point", description: "Choose whether to offset from Fajr start or Sunrise")
////    var referencePoint: ReferencePoint
////
////    @Parameter(title: "Minutes", description: "Number of minutes to offset")
////    var offsetMinutes: Int
////
////    @MainActor
////    func perform() async throws -> some IntentResult & ReturnsValue<Date> {
////        // Get coordinates from UserDefaults
////        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
////        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
////
////        guard latitude != 0, longitude != 0 else {
////            throw Error("Location not available. Please open the app first.")
////        }
////
////        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
////        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
////        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
////
////        let calculationMethod: CalculationMethod = {
////            switch calcMethodInt {
////            case 1: return .karachi
////            case 2: return .northAmerica
////            case 3: return .muslimWorldLeague
////            case 4: return .ummAlQura
////            case 5: return .egyptian
////            case 7: return .tehran
////            case 8: return .dubai
////            case 9: return .kuwait
////            case 10: return .qatar
////            case 11: return .singapore
////            case 12, 14: return .other
////            case 13: return .turkey
////            default: return .northAmerica
////            }
////        }()
////
////        var params = calculationMethod.params
////        params.madhab = madhab
////
////        // Get prayer times for today and tomorrow
////        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
////        let tmmComponents = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
////
////        guard let todayPrayerTimes = PrayerTimes(coordinates: coordinates,
////                                                date: todayComponents,
////                                                calculationParameters: params) else {
////            throw Error("Unable to calculate today's prayer times")
////        }
////
////        guard let tmmPrayerTimes = PrayerTimes(coordinates: coordinates,
////                                              date: tmmComponents,
////                                              calculationParameters: params) else {
////            throw Error("Unable to calculate tomorrow's prayer times")
////        }
////
////        // Get reference times
////        let getReferenceTime: (PrayerTimes) -> Date = { times in
////            switch self.referencePoint {
////            case .afterFajr: return times.fajr
////            case .beforeSunrise: return times.sunrise
////            }
////        }
////
////        let todayReferenceTime = getReferenceTime(todayPrayerTimes)
////        let nextReferenceTime = Date() > todayReferenceTime ? getReferenceTime(tmmPrayerTimes) : todayReferenceTime
////
////        // Calculate the offset time
////        let offsetInterval = TimeInterval(offsetMinutes * 60) // Convert minutes to seconds
////        let resultTime = referencePoint == .afterFajr
////            ? nextReferenceTime.addingTimeInterval(offsetInterval)
////            : nextReferenceTime.addingTimeInterval(-offsetInterval)
////
////        return .result(value: resultTime)
////    }
////}
////
////// Custom error type
////extension GetOffsetTimeIntent {
////    struct Error: Swift.Error {
////        let message: String
////
////        init(_ message: String) {
////            self.message = message
////        }
////    }
////}
//
//
//
//
//
//
////import AppIntents
////import Adhan
////
////struct GetNextFajrIntent: AppIntent {
////    static var title: LocalizedStringResource = "Get Next Fajr Time"
////    static var description: LocalizedStringResource = "Returns the next Fajr time"
////
////    func perform() async throws -> some IntentResult & ProvidesDialog {
////        // Use shared UserDefaults to get the last calculated Maghrib time
//////        let defaults = UserDefaults(suiteName: "group.com.yourapp.shukr")
//////        let defaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
//////        UserDefaults.standard.integer(forKey: "school")
////
////        // Get coordinates from UserDefaults
////        let latitude = UserDefaults.standard.double(forKey: "lastLatitude")
////        let longitude = UserDefaults.standard.double(forKey: "lastLongitude")
////
////        guard latitude != 0, longitude != 0 else {
////            return .result(dialog: "Location not available. Please open the app first.")
////        }
////
////        // Set up coordinates and calculation parameters
////        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
////
////        // Get calculation method from UserDefaults
////        let calcMethodInt = UserDefaults.standard.integer(forKey: "calculationMethod")
////        let madhab = UserDefaults.standard.integer(forKey: "school") == 1 ? Madhab.hanafi : Madhab.shafi
////
////        let calculationMethod: CalculationMethod = {
////            switch calcMethodInt {
////            case 1: return .karachi
////            case 2: return .northAmerica
////            case 3: return .muslimWorldLeague
////            case 4: return .ummAlQura
////            case 5: return .egyptian
////            case 7: return .tehran
////            case 8: return .dubai
////            case 9: return .kuwait
////            case 10: return .qatar
////            case 11: return .singapore
////            case 12, 14: return .other
////            case 13: return .turkey
////            default: return .northAmerica
////            }
////        }()
////
////        var params = calculationMethod.params
////        params.madhab = madhab
////
////        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
////        let tmmComponents = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
////
////        guard let todayPayerTimes = PrayerTimes(coordinates: coordinates,
////                                          date: todayComponents,
////                                          calculationParameters: params) else {
////            return .result(dialog: "Unable to calculate prayer times")
////        }
////
////        guard let tmmPrayerTimes = PrayerTimes(coordinates: coordinates,
////                                          date: tmmComponents,
////                                          calculationParameters: params) else {
////            return .result(dialog: "Unable to calculate prayer times")
////        }
////
////        var fajrToReturn = todayPayerTimes.fajr
////
////        if Date() > todayPayerTimes.fajr  {
////            fajrToReturn = tmmPrayerTimes.fajr
////            print("giving tomorrows cuz we past todays")
////        }
////
////        let formatter = DateFormatter()
////        formatter.timeStyle = .short
////        return .result(dialog: "Next Fajr is at \(formatter.string(from: fajrToReturn))")
////    }
////}
////
////struct PrayerTimeShortcuts: AppShortcutsProvider {
////    static var appShortcuts: [AppShortcut] {
////        AppShortcut(
////            intent: GetNextFajrIntent(),
////            phrases: [
////                "Get Next Fajr time",
////                "When is Fajr",
////                "What time is Fajr",
////                "Get Fajr time",
////                "Morning prayer time"
////            ],
////            shortTitle: "Fajr Time",
////            systemImageName: "sunrise.fill"
////        )
////    }
////}
