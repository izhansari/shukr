import SwiftUI
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox

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
    
    // State properties
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    
    @State private var selectedMinutes = 1
    
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    
    // used during pause
    @State private var paused = false
    @State private var pauseStartTime: Date? = nil
    
    // used outside of pause on click.
    @State private var pauseSinceLastInc: TimeInterval = 0
    @State private var totalPauseInSession: TimeInterval = 0
    
    @State private var totalTimePerClick: TimeInterval = 0
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
    
    @State private var progressFraction: CGFloat = 0
        
    typealias newClickData = (date: Date, pauseTime: TimeInterval, tpc: TimeInterval)
    @State private var clickStats: [newClickData] = []
    
    @State private var isHolding = false
    @State private var holdTimer: Timer? = nil
    @State private var holdDuration: Double = 0
    
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

    //--------------------------------------view--------------------------------------
    
    var body: some View {
        ZStack {
            // the middle
            ZStack {
                //1. the circle
                CircularProgressView(progress: (progressFraction))
                    .contentShape(Circle()) // Only the circle is tappable
                    .onTapGesture {incrementTasbeeh()}
                
                //2. the circle's inside (picker or count)
                if timerIsActive {
                    TasbeehCountView(tasbeeh: tasbeeh)
                } else {
                    MinuteWheelPicker(selectedMinutesBinding: $selectedMinutes)
                }
            }
            .padding(.horizontal)
            
            
            // stats and settings - this part handles the pause overlay
            ZStack {
                // Background blur effect
                Color.black.opacity(paused ? 0.5 : 0.0)
                    .edgesIgnoringSafeArea(.all)
                    .animation(.easeInOut, value: paused)
                    .onTapGesture { togglePause() }

                // Centered stats
                VStack(spacing: 20) {
                    if paused {
                        Text("\(selectedMinutes)m Session")
                            .font(.title2)
                            .bold()

                        Text("Time Passed: \(timePassedAtPause)")
                            .font(.title3)

                        Text("Click Rate: \((String(format: "%.2f", avgTimePerClick)))s")
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
                }


                //2. start/stop button
                if((!timerIsActive || secondsLeft <= 0) && !paused){
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
                        .frame(height: 50)
                        .shadow(radius: 5)
                    })
                    .padding()
                }
            }
            
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
        }
        .frame(maxWidth: .infinity) // makes the whole thing tappable. otherwise tappable area shrinks to width of CircularProgressView
        .background(
            Color.clear // Makes the background tappable
                .contentShape(Rectangle())
                .onTapGesture {
                    if timerIsActive {
                        incrementTasbeeh()
                    }
                }
                .gesture(holdToStopGesture())
        )
        .onDisappear(perform: stopTimer)
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
                    progressFraction = CGFloat(Int(secondsPassed))/TimeInterval(totalTime)
                }
            }
            if (secondsLeft <= 0 && !paused) {
                if(autoStop){
                    stopTimer()
                    print("homeboy auto stopped....")
                    streak += 1 // Increment the streak
                }
            }
        }
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
        
        pauseSinceLastInc = 0
        totalPauseInSession = 0
        
        progressFraction = 0
        
        paused = false
        
        triggerSomeVibration(type: .vibrate)

    }
    
    private func togglePause() {
        paused = !paused
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
        
        print("inc")
        print(clickStats)
        
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        triggerSomeVibration(type: .light)
        
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
            
            print("dec")
            print(clickStats)
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
                    .foregroundColor(.white)
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
    
    struct TasbeehCountView: View {
        let tasbeeh: Int
        
        var body: some View {
            ZStack {
                HStack(spacing: 5) {
                    let circlesCount = tasbeeh / 100
                    ForEach(0..<circlesCount, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                    }
                }
                .offset(y: 40) // Position the circles below the text

                Text("\(tasbeeh % 100)")
                    .font(.largeTitle)
                    .bold()
                    .fontDesign(.rounded)
            }
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

}

#Preview {
    CombinedView()
        .modelContainer(for: Item.self, inMemory: true)
}




//okay game plan
/*
 
 next stuff to tackle
 
 - get average timePerClick during session.
 - reset count button
 - during active timer, hold down for settings (autostop, vibrate, modetoggle, selectedMinutes, formattedSessionTime, average timePerClick, reset count button, stop button)
 - CRUD historical session cards: store each session as its own card to see session data.
 - add notes section to the historical session card
 - slide to stop early...?
 */
