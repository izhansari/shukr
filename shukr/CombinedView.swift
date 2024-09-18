import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer

// to get rid of keyboard
extension UIApplication {
    func endEditing(_ force: Bool) {
        self.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct CombinedView: View {
    
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
    @AppStorage("paused", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var paused = false
    
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
         (
            progressFraction >= 1 /*secondsLeft <= 0*/ ||
            (!timerIsActive && selectedPage != 2) ||
            (!timerIsActive && selectedPage == 2 && Int(targetCount) ?? 0 > 0))
         )
    }
    
    @State private var progressFraction: CGFloat = 0
        
    typealias newClickData = (date: Date, pauseTime: TimeInterval, tpc: TimeInterval)
    @State private var clickStats: [newClickData] = []
    
    @State private var isHolding = false
    @State private var holdTimer: Timer? = nil
    @State private var holdDuration: Double = 0
    
    @State private var selectedPage = 1 // Default to page 2 (index 1)
    @State private var targetCount: String = ""
    
    
    private var debug: Bool = false
    @State private var debug_AddingToPausedTimeString : String = ""
    private var debug_secLeft_secPassed_progressFraction: String{
        "time left: \(roundToTwo(val: secondsLeft)) | secPassed: \(roundToTwo(val: secondsPassed)) | proFra: \(roundToTwo(val: progressFraction))"
    }
        
    // Reusable haptic feedback generators
    let impactFeedbackGenerator = UIImpactFeedbackGenerator()
    let notificationFeedbackGenerator = UINotificationFeedbackGenerator()


    private enum HapticFeedbackType: String, CaseIterable, Identifiable {
        case light = "Light"; case medium = "Medium"
        case heavy = "Heavy"; case soft = "Soft"
        case rigid = "Rigid"; case success = "Success"
        case warning = "Warning"; case error = "Error"
        case vibrate = "Vibrate"
        
        var id: String { self.rawValue }
    }
    
    func roundToTwo(val: Double) -> Double{
        return ((val * 100.0).rounded() / 100.0)
    }

    private func simulateTasbeehClicks(times: Int) {
        // Simulate multiple tasbeeh clicks
        for _ in 1...times {
            incrementTasbeeh()
        }
    }

    //--------------------------------------view--------------------------------------
    
    var body: some View {
        ZStack {
            // the middle
            ZStack {
                //2. the circle's inside (picker or count)
                if timerIsActive {
                    TasbeehCountView(tasbeeh: tasbeeh)
//                        .onAppear { simulateTasbeehClicks(times: 199) }
                } else {
//                    MinuteWheelPicker(selectedMinutesBinding: $selectedMinutes)
                    // the middle with a scrollable view
                    TabView (selection: $selectedPage) {
                        // Page 1
                        Text(Image(systemName: "infinity"))
                            .font(.title)
                            .fontDesign(.rounded)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(0)
                        
                        // Page 2 with MinuteWheelPicker
                        MinuteWheelPicker(selectedMinutesBinding: $selectedMinutes)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(1)
                        
                        // Page 3
                        VStack {
                            Text(Image(systemName: "number"))
                                .font(.title)
                                .fontDesign(.rounded)
                            TextField("", text: $targetCount)
                                .focused($isNumberEntryFocused)
                                .padding()
                                .keyboardType(.numberPad) // Limits input to numbers only
                                .frame(width: 75)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(15)
                                .fontDesign(.rounded)
                                .multilineTextAlignment(.center) // Align text in the center
                                .onTapGesture {
                                    isNumberEntryFocused = true
                                }
                        }
                        .tag(2)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Enable paging
                    .frame(width: 200, height: 200) // Match the CircularProgressView size
                    .onChange(of: selectedPage) {_, newPage in
//                        UIApplication.shared.endEditing(true) // Dismiss keyboard when switching pages
                        isNumberEntryFocused = false
                        print("User is on page: \(newPage) | paused = \(paused)")
                    }
                }
                
                //1. the circle
                CircularProgressView(progress: (progressFraction))
                    .contentShape(Circle()) // Only the circle is tappable
                    .onTapGesture {
//                        incrementTasbeeh()
//                        print("okay taped")
                    }
//                    .gesture(holdToStopGesture())
                    .onLongPressGesture(minimumDuration: 0.2) {
                        timerIsActive ? simulateTasbeehClicks(times: 100) : ()
                    }

            }
            .padding(.horizontal)
            
            // stats and settings - this part handles the pause overlay
            ZStack {
                Color("pauseColor")
                    .edgesIgnoringSafeArea(.all)
                    .animation(.easeOut(duration: 0.3), value: paused)
                    .onTapGesture { togglePause() }
                    .opacity(paused ? 1 : 0.0)

                // Centered stats
                VStack(spacing: 20) {
                    if paused {
                        if(selectedPage == 0) {
                            Text("Freestyle Session")
                                .font(.title2)
                            .bold()
                        } else if(selectedPage == 1) {
                            Text("\(selectedMinutes)m Session")
                                .font(.title2)
                            .bold()
                        } else if(selectedPage == 2) {
                            Text("\(targetCount) Target Session")
                                .font(.title2)
                            .bold()
                        }

                        Text("Count: \(tasbeeh)")
                            .font(.title3)
                        
                        Text("Time Passed: \(timePassedAtPause)")
                            .font(.title3)

                        Text("Last Time / Click: \((String(format: "%.2f", timePerClick)))s")
                            .font(.title3)
                        
                        Text("Avg Time / Click: \((String(format: "%.2f", avgTimePerClick)))s")
                            .font(.title3)

                        Text("Tasbeeh Rate: \(tasbeehRate)")
                            .font(.title3)
                    }
                }
                .padding()
                .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the stats box
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
                .padding(.horizontal, 30)
                .opacity(paused ? 1.0 : 0.0)
                .animation(.easeInOut, value: paused)

                // Settings toggles pinned to the bottom
                VStack {
                    
                    Spacer()

                    HStack {
                        toggleButton("AutoStop", isOn: $autoStop, color: .mint, checks: true).foregroundColor(!modeToggle ? .white : .none)
                        toggleButton("Vibrate", isOn: $vibrateToggle, color: .yellow, checks: true).foregroundColor(!modeToggle ? .white : .none)
                        toggleButton(modeToggle ? "🌙" : "☀️", isOn: $modeToggle, color: .white, checks: false)

                        // Exit button to stop the timer
                        Button(action: {
                            stopTimer()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                                .padding()
                        }
                        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
                        .cornerRadius(15)
                        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
                    }
                    .padding()
                    .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for settings
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40) // Space above the edge of the screen
                    .opacity(paused ? 1.0 : 0.0)
                    .animation(.easeInOut, value: paused)
                }
            }.animation(.easeInOut, value: paused)



            VStack {
                Spacer()
                
                if timerIsActive {
                    Text("hold to stop the timer...")
                        .font(.title3)
                        .fontDesign(.rounded)
                        .foregroundColor(.gray)
                        .padding(.bottom, isHolding ? 30 : 0)
                        .opacity(isHolding ? 1 : 0)
                        .animation(isHolding ? .easeInOut(duration: 1) : .easeOut(duration: 0.5), value: isHolding)
                }
            }

            
            // Floating Settings & Start/Stop
            VStack {
                
                //0. buttons
                if(timerIsActive){
                    // buttons
                    HStack {
                        if(debug){
                            Text(debug_AddingToPausedTimeString)
                            Text(debug_secLeft_secPassed_progressFraction)
                        }
                        Button(action: decrementTasbeeh) {
                            Image(systemName: "minus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.gray.opacity(0.3))
                                .padding()
                                .cornerRadius(10)
                                .opacity(paused ? 0 : 1.0)
                        }
                        .disabled(paused)
                        .animation(.easeOut, value: paused)
                        
                        Spacer()

                        Button(action: togglePause) {
                            Image(systemName: paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(paused ? .gray.opacity(0.8) : .gray.opacity(0.3))
                                .padding()
                                .cornerRadius(10)
                        }.animation(paused ? .easeOut : .easeIn, value: paused)
                    }
                    .padding()
                }
                
                Spacer()

                // 1. setting toggles
                if(!timerIsActive){
                    HStack{
                        toggleButton("AutoStop", isOn: $autoStop, color: .mint, checks: true)
                        toggleButton("Vibrate", isOn: $vibrateToggle, color: .yellow, checks: true)
                        toggleButton(modeToggle ? "🌙":"☀️", isOn: $modeToggle, color: .white, checks: false)
                    }
                    .padding(.bottom)
                }


                //2. start/stop button
                if(showStartStopCondition){
                    Button(action: toggleTimer, label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .foregroundStyle(.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 20)
                                .foregroundStyle(timerIsActive ? .green.opacity(0.5) : .blue.opacity(0.5))
                            Text(timerIsActive ? "complete" : "start")
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
        .frame(maxWidth: .infinity) // makes the whole thing tappable. otherwise tappable area shrinks to width of CircularProgressView
//        .background(Color(.gray)) // This will use your custom color for both light and dark mode
        .background(
            Color.init("bgColor") // Makes the background tappable
                .contentShape(Rectangle()).edgesIgnoringSafeArea(.all)
                .onTapGesture {
//                    UIApplication.shared.endEditing(true) // Dismiss keyboard when tapping outside
                    isNumberEntryFocused = false
                    if timerIsActive {
                        incrementTasbeeh()
                    }
                }
                .gesture(holdToStopGesture())
        )
        .onDisappear {
            stopTimer() // i think this is useless since this view is the main app and it NEVER disappears...
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
//                        print("0: \(selectedPage) profra: \(progressFraction)")
//                        print("top: \(CGFloat(Int(secondsPassed))) bot: \(TimeInterval(totalTime))")
                    } else if (selectedPage == 2){
                        progressFraction = CGFloat(tasbeeh)/CGFloat(Int(targetCount) ?? 0)
//                        print("2: \(selectedPage) profra: \(progressFraction)")
//                        print("top: \(CGFloat(tasbeeh)) bot: \(CGFloat(Int(targetCount) ?? 0))")

                    }
                }
            }
            if ((/*secondsLeft <= 0 || */progressFraction >= 1) && !paused) {
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
        
        triggerSomeVibration(type: .vibrate)

    }
    
    private func togglePause() {
        paused.toggle()
        WidgetCenter.shared.reloadAllTimelines() // Ensure widget reflects this change
        triggerSomeVibration(type: .medium)
        if(paused){
            pauseStartTime = Date()
            timePassedAtPause = formatTimePassed // cant use calculated var cuz it keeps changing if view ever updated
        }else{
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
        
        if(paused){return}
        
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
        
        let newData: newClickData = (date: rightNow, pauseTime: pauseSinceLastInc, tpc: timePerClick)
        clickStats.append(newData)
        
        pauseSinceLastInc = 0
        
//        print("inc")
//        print(clickStats)
        
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        triggerSomeVibration(type: .medium)
        
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
            triggerSomeVibration(type: .vibrate)
        }
    }

    private func holdToStopGesture(minimumHoldDuration: Double = 2.5) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isHolding = true
                if holdTimer == nil {
                    // Start the timer when the user starts dragging
                    holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        holdDuration += 0.1
                        if holdDuration >= minimumHoldDuration {
                            // Perform the action after holding for the required duration
                            if timerIsActive { stopTimer() }
                            resetHoldTimer()
                        }
                    }
                }
            }
            .onEnded { _ in
                resetHoldTimer()
                isHolding = false
            }
    }
    
    private func resetHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdDuration = 0
    }
    
    private func toggleButton(_ label: String, isOn: Binding<Bool>, color: Color ,checks: Bool) -> some View {
        Toggle(isOn: isOn) {
            if(checks){Text(isOn.wrappedValue ? "✓ \(label)" : "✗ \(label)")}
            else{Text(isOn.wrappedValue ? "\(label)" : "\(label)")}
        }
        .toggleStyle(.button)
        .tint(color)
        .onChange(of: isOn.wrappedValue) { _, newValue in
            triggerSomeVibration(type: .heavy)
        }
    }
    
    private func triggerSomeVibration(type: HapticFeedbackType) {
            if vibrateToggle {
                switch type {
                case .light:
                    impactFeedbackGenerator.impactOccurred(intensity: 0.5)
                case .medium:
                    impactFeedbackGenerator.impactOccurred(intensity: 0.75)
                case .heavy:
                    impactFeedbackGenerator.impactOccurred(intensity: 1.0)
                case .soft:
                    impactFeedbackGenerator.impactOccurred(intensity: 0.3)
                case .rigid:
                    impactFeedbackGenerator.impactOccurred(intensity: 0.9)
                case .success:
                    notificationFeedbackGenerator.notificationOccurred(.success)
                case .warning:
                    notificationFeedbackGenerator.notificationOccurred(.warning)
                case .error:
                    notificationFeedbackGenerator.notificationOccurred(.error)
                case .vibrate:
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
    
//--------------------------------------subviews--------------------------------------
    
    struct CircularProgressView: View {
        let progress: CGFloat
        @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
        
        var body: some View {
            ZStack {
                Circle()
                    .stroke(lineWidth: 24)
                    .frame(width: 200, height: 200)
                    .foregroundColor(Color("wheelColor"))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
                
                Circle()
                    .stroke(lineWidth: 0.34)
                    .frame(width: 175, height: 175)
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.1), lineWidth: 2)
                            .blur(radius: 5)
                            .mask {
                                Circle()
                                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                    }
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .animation(.spring(), value: progress)
            }
        }
    }
    
    // YEHSIRRR we got purples doing same thing from top down now. No numbers. Clean.
    struct TasbeehCountView: View {
        let tasbeeh: Int
        let circleSize: CGFloat = 10 // Circle size
        let arcRadius: CGFloat = 40 // Distance of the grey circles from the number (radius of the arc)
        let purpleArcRadius: CGFloat = 60 // Distance of the purple circles from the center (larger radius)

        @State private var rotationAngle: Double = 0 // State variable to handle grey circle rotation
        @State private var purpleRotationAngle: Double = 0 // State variable to handle purple circle rotation

        private var justReachedToA1000: Bool {
            tasbeeh % 1000 == 0
        }
        private var showPurpleCircle: Bool {
            tasbeeh >= 1000
        }

        var body: some View {
            ZStack {
                // Display the number in the center
                Text("\(tasbeeh % 100)")
                    .font(.largeTitle)
                    .bold()
                    .fontDesign(.rounded)

                // GeometryReader to help position circles
                GeometryReader { geometry in
                    let circlesCount = tasbeeh / 100
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Purple circles at the top, further from the center
                    ZStack {
                        ForEach(0..<min(circlesCount / 10, 10), id: \.self) { index in
                            Circle()
                                .fill(Color.purple)
                                .frame(width: circleSize, height: circleSize)
                                .position(purpleClockPosition(for: index, center: center)) // Purple circles further out
                        }
                    }
                    .rotationEffect(.degrees(purpleRotationAngle)) // Rotate purple circles
                    .opacity(showPurpleCircle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: showPurpleCircle)

                    // Grey circles in a clock pattern for 1-9 tasbeehs
                    ZStack {
                        ForEach(0..<max(circlesCount % 10, justReachedToA1000 ? 9 : 0), id: \.self) { index in
                            Circle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: circleSize, height: circleSize)
                                .position(clockPosition(for: index, center: center)) // Grey circles at default radius
                                .opacity(justReachedToA1000 ? 0 : 1)
                                .animation(.easeInOut(duration: 0.5), value: justReachedToA1000)
                        }
                    }
                    .rotationEffect(.degrees(rotationAngle)) // Rotate based on grey tasbeeh count
                    .onChange(of: circlesCount % 10) {_, newValue in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            if newValue > 1 && newValue % 10 != 0 {
                                rotationAngle = Double(18 * (newValue - 1)) // Rotate by 18 degrees for each grey circle added
                            } else if newValue == 1 {
                                rotationAngle = 0 // Reset grey circle rotation for a new cycle
                            }
                        }
                    }
                    
                    // Update purple circle rotation logic
                    .onChange(of: circlesCount / 10) {_, newValue in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            if newValue > 1 && newValue % 10 != 0 {
                                purpleRotationAngle = Double(18 * (newValue - 1)) // Rotate by 18 degrees for each purple circle added
                            } else if newValue == 1 {
                                purpleRotationAngle = 0 // Reset purple circle rotation for a new cycle
                            }
                        }
                    }
                }
                .frame(height: 100) // Adjust frame height to ensure there's enough space
            }
        }

        // Function to calculate the position of each grey circle like clock positions (now with 10 hands)
        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
            let angle = angleForClockPosition(at: index)
            let x = center.x + arcRadius * cos(angle) // X position using cosine
            let y = center.y + arcRadius * sin(angle) // Y position using sine
            return CGPoint(x: x, y: y)
        }

        // Function to calculate the position of each purple circle, placed further out and rotated
        func purpleClockPosition(for index: Int, center: CGPoint) -> CGPoint {
            let angle = angleForClockPosition(at: index) // Same angle logic
            let x = center.x + purpleArcRadius * cos(angle - .pi) // Push further out and flip vertically
            let y = center.y + purpleArcRadius * sin(angle - .pi) // Flip vertically for top positioning
            return CGPoint(x: x, y: y)
        }

        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward, now with 10 even spots)
        func angleForClockPosition(at index: Int) -> CGFloat {
            let stepAngle: CGFloat = 2 * .pi / 10 // Divide the circle into 10 positions (like a clock with 10 hands)
            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
            return startAngle - stepAngle * CGFloat(index)
        }
    }







    
    struct MinuteWheelPicker: View {
        @Binding var selectedMinutesBinding: Int

        var body: some View {
            Picker("Minutes", selection: $selectedMinutesBinding) {
                ForEach(1..<60) { minute in
                    Text("\(minute)m").tag(minute)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(width: 100)
            .padding()
        }
    }

    
    struct BlurView: UIViewRepresentable {
        var style: UIBlurEffect.Style

        func makeUIView(context: Context) -> UIVisualEffectView {
            return UIVisualEffectView(effect: UIBlurEffect(style: style))
        }

        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
    }
    
    struct GlassMorphicView: View {
        var body: some View {
            ZStack {
                // The frosted glass effect
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.1))  // Base color with transparency
                    .background(
                        Color.white.opacity(0.4) // Adds a translucent layer
                            .blur(radius: 10) // Creates a blur effect
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1) // Subtle white border
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 10) // Adds depth with shadow
            }
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
