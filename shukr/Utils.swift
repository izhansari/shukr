import SwiftUI
import AudioToolbox
import MediaPlayer

/// Utility Functions ----------------------------------------------------------------------------------------------------
func roundToTwo(val: Double) -> Double {
    return ((val * 100.0).rounded() / 100.0)
}

func formatSecToMinAndSec(_ totalSeconds: TimeInterval) -> String {
    let minutes = Int(totalSeconds) / 60
    let seconds = Int(totalSeconds) % 60
    
    if minutes > 0 { return "\(minutes)m \(seconds)s"}
    else { return "\(seconds)s" }
}

func formatSecondsToTimerString(_ totalSeconds: Double) -> String {
    let roundedSeconds = Int(round(totalSeconds))
    let hours = roundedSeconds / 3600
    let minutes = (roundedSeconds % 3600) / 60
    let seconds = roundedSeconds % 60
    
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

let MSPMTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "mm:ss.SSS a" // Displays in 12-hour format with AM or PM
    return formatter
}()

let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a" // Displays in 12-hour format with AM or PM
    return formatter
}()

let hmmTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm" // Displays the time as 4:50
    return formatter
}()

// Function to format remaining time as minutes
func mLeftTimeFormatter(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 {
        components.append("\(hours)h")
    }
    
    if minutes > 0 {
        components.append("\(minutes)m")
    }
    
    // Only show seconds if less than a minute
    if totalSeconds < 60 {
        components.append("\(seconds)s")
    }

    // If no time left, return "0s left"
    if components.isEmpty {
        return "0s left"
    }

    // Join components with a space and append "left"
    return components.joined(separator: " ") + " left"
}
//func mLeftTimeFormatter(from timeInterval: TimeInterval) -> String {
//    let minutesLeft = Int(timeInterval / 60)
//    if (timeInterval < 60){
//        return "\(Int(timeInterval))s left"
//    }
//    return "\(minutesLeft)m left"
//}

func todayAt(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
}

// Function to format remaining time as hours, minutes, or seconds
func inMSTimeFormatter(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 {
        components.append("\(hours)h")
    }
    
    if minutes > 0 {
        components.append("\(minutes)m")
    }
    
    // Only show seconds if less than a minute
    if totalSeconds < 60 {
        components.append("\(seconds)s")
    }

    // Join components with a space and prepend "in "
    return "in " + components.joined(separator: " ")
}
//func inMSTimeFormatter(from timeInterval: TimeInterval) -> String {
//    let totalSeconds = Int(timeInterval)
//    let hours = totalSeconds / 3600
//    let minutes = (totalSeconds % 3600) / 60
//    let seconds = totalSeconds % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//// Function to format remaining time as minutes
//func inMSTimeFormatter(from timeInterval: TimeInterval) -> String {
//    let minutesLeft = Int(timeInterval / 60)
//    if (timeInterval < 60){
//        return "in \(Int(timeInterval))s"
//    }
//    return "in \(minutesLeft)m"
//}


/// Vibration Feedback ---------------------------------------------------------------------------------------------------
enum HapticFeedbackType: String, CaseIterable, Identifiable {
    case light = "Light"; case medium = "Medium"
    case heavy = "Heavy"; case soft = "Soft"
    case rigid = "Rigid"; case success = "Success"
    case warning = "Warning"; case error = "Error"
    case vibrate = "Vibrate"; case off = ""
    
    var id: String { self.rawValue }
}

let impactFeedbackGenerator = UIImpactFeedbackGenerator()
let notificationFeedbackGenerator = UINotificationFeedbackGenerator()

func triggerSomeVibration(type: HapticFeedbackType) {
//    impactFeedbackGenerator.prepare()
    
    let userDefaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
//    let vibrateToggle = userDefaults?.bool(forKey: "vibrateToggle") ?? false // Get vibrateToggle value from UserDefaults

//    print("should do it", vibrateToggle)
//    if vibrateToggle {
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
        case .off:
            ()
        }
//    }
}



///                                     vvv--------------------------------------subviews--------------------------------------vvv







/// Custom Buttons ----------------------------------------------------------------------------------------------------------
func toggleButton(_ label: String, isOn: Binding<Bool>, color: Color, checks: Bool) -> some View {
    Toggle(isOn: isOn) {
        if(checks){Text(isOn.wrappedValue ? "✓\(label)" : "✗\(label)")}
        else{Text(isOn.wrappedValue ? "\(label)" : "\(label)")}
    }
    .toggleStyle(.button)
    .tint(color)
    .onChange(of: isOn.wrappedValue) { _, newValue in
        triggerSomeVibration(type: .heavy)
    }
}

struct twoModeToggleButton: View {
    @Binding var boolToToggle: Bool
    let onSymbol: String
    let onColor: Color
    let offSymbol: String
    let offColor: Color
    
    var body: some View {
        Button(action: {
            boolToToggle.toggle()
        }) {
            Image(systemName: boolToToggle ? onSymbol : offSymbol)
                .font(.system(size: 24))
                .foregroundColor(boolToToggle ? onColor : offColor)
                .padding()
        }
        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)
        .onChange(of: boolToToggle, {triggerSomeVibration(type: .medium)})
    }
}

struct DebugToggleButton: View {
    @Binding var showDragColor: Bool
    var body: some View {
        twoModeToggleButton(
            boolToToggle: $showDragColor,
            onSymbol: "ladybug.fill",
            onColor: .red,
            offSymbol: "ladybug",
            offColor: .gray)
    }
}

struct SleepModeToggleButton: View {
//    @Binding var toggleInactivityTimer: Bool
////    var body: some View {
////        twoModeToggleButton(
////            boolToToggle: $toggleInactivityTimer,
////            onSymbol: "bed.double.fill",
////            onColor: .orange,
////            offSymbol: "bed.double",
////            offColor: .gray)
////    }
    
    @Binding var toggleInactivityTimer: Bool
    @Binding var colorModeToggle: Bool
    let onSymbol: String = "bed.double.fill"
    let onColor: Color = .orange
    let offSymbol: String = "bed.double"
    let offColor: Color = .gray
    
    var body: some View {
        Button(action: {
            toggleInactivityTimer.toggle()
            if toggleInactivityTimer == true && colorModeToggle == false {
                colorModeToggle.toggle()
            }
        }) {
            Image(systemName: toggleInactivityTimer ? onSymbol : offSymbol)
                .font(.system(size: 24))
                .foregroundColor(toggleInactivityTimer ? onColor : offColor)
                .padding()
        }
        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)
        .onChange(of: toggleInactivityTimer, {triggerSomeVibration(type: .medium)})
    }
}

struct ColorSchemeModeToggleButton: View {
    @Binding var colorModeToggle: Bool
    var body: some View {
        twoModeToggleButton(
            boolToToggle: $colorModeToggle,
            onSymbol: "moon.fill",
            onColor: .yellow,
            offSymbol: "sun.max.fill",
            offColor: .yellow)
    }
}

struct AutoStopToggleButton: View {
    @Binding var autoStop: Bool
    var body: some View {
        twoModeToggleButton(
            boolToToggle: $autoStop,
            onSymbol: "arrow.clockwise.circle",
            onColor: .gray,
            offSymbol: "arrow.clockwise.circle.fill",
            offColor: .green)
    }
}

struct VibrationModeToggleButton: View {
    @Binding var currentVibrationMode: HapticFeedbackType

    // Function to toggle between vibration modes
    private func toggleVibrationMode() {
        switch currentVibrationMode {
        case .off:
            currentVibrationMode = .light
        case .light:
            currentVibrationMode = .medium
        case .medium:
            currentVibrationMode = .heavy
        case .heavy:
            currentVibrationMode = .off
        default:
            currentVibrationMode = .medium
        }
    }

    // Function to get the appropriate SF Symbol based on the mode
    private func getIconForVibrationMode() -> String {
        switch currentVibrationMode {
        case .heavy:
            return "speaker.wave.3.fill"  // High mode icon
        case .medium:
            return "speaker.wave.2.fill"  // Medium mode icon
        case .light:
            return "speaker.wave.1.fill"  // Low mode icon
        case .off:
            return "speaker.slash.fill"   // Off mode icon
        default:
            return "speaker.wave.2.fill"  // Medium mode icon
        }
    }
    
    var body: some View {
        Button(action: {
            toggleVibrationMode()
        }) {
            Image(systemName: getIconForVibrationMode())
                .font(.system(size: 24))
                .foregroundColor(currentVibrationMode == .off ? .gray : .blue)
                .padding()
        }
        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)
        .onChange(of: currentVibrationMode){
            triggerSomeVibration(type: currentVibrationMode)
        }
    }
}

struct PlayPauseButton: View {
    let togglePause: () -> Void
    let paused: Bool
    
    var body: some View {
        Button(action: togglePause) {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(paused ? .gray.opacity(0.8) : .gray.opacity(0.3))
                .padding()
                .background(paused ? .clear : .gray.opacity(0.08))
                .cornerRadius(10)
        }
    }
}

struct ExitButton: View{
    let stopTimer: () -> Void
    
    var body: some View{
        Button(action: { stopTimer() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
                .padding()
        }
        .background(BlurView(style: .systemUltraThinMaterial))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)
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



/// Mode Selection Views ---------------------------------------------------------------------------------------------------
struct freestyleMode: View {
    var body: some View {
        Text(Image(systemName: "circle.fill"))
            .font(.title)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 3, y: 3)
    }
}

struct timeTargetMode: View {
    @Binding var selectedMinutesBinding: Int

    var body: some View {
        Picker("Minutes", selection: $selectedMinutesBinding) {
//            Text("")
            ForEach(0..<60) { minute in
                Text("\(minute)m").tag(minute)
                    .fontWeight(.thin)
                    .fontDesign(.rounded)

            }
        }
        .pickerStyle(WheelPickerStyle())
        .frame(width: 100)
        .padding()
    }
}

struct countTargetMode: View {
    @Binding var targetCount: String
    @FocusState var isNumberEntryFocused: Bool
    
    var body: some View {
        VStack {
            Text(Image(systemName: "number"))
                .font(.title)
                .fontDesign(.rounded)
                .fontWeight(.thin)
            TextField("", text: $targetCount)
                .focused($isNumberEntryFocused)
                .fontDesign(.rounded)
                .fontWeight(.thin)
                .padding()
                .keyboardType(.numberPad) // Limits input to numbers only
                .frame(width: 90)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(15)
                .fontDesign(.rounded)
                .multilineTextAlignment(.center) // Align text in the center
                .onTapGesture {
                    isNumberEntryFocused = true
                }
        }
    }
}

struct inputOffsetSubView: View {
    @Binding var targetCount: String
    @FocusState var isNumberEntryFocused: Bool
    
    var body: some View {
        VStack {
            Text(Image(systemName: "gear"))
                .font(.title)
                .fontDesign(.rounded)
                .fontWeight(.thin)
            TextField("", text: $targetCount)
                .focused($isNumberEntryFocused)
                .fontDesign(.rounded)
                .fontWeight(.thin)
                .padding()
                .keyboardType(.numberPad) // Limits input to numbers only
                .frame(width: 75)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(15)
                .multilineTextAlignment(.center) // Align text in the center
                .onTapGesture {
                    isNumberEntryFocused = true
                }
        }
    }
}



/// Main Views -------------------------------------------------------------------------------------------------------------
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
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [.yellow.opacity(0.6), .green.opacity(0.8)] : [.yellow, .green]), startPoint: .topLeading, endPoint: .bottomTrailing))
                .animation(.spring(), value: progress)
        }
    }
}

struct TasbeehCountView: View { // YEHSIRRR we got purples doing same thing from top down now. No numbers. Clean.
    let tasbeeh: Int
    let circleSize: CGFloat = 10 // Circle size
    let arcRadius: CGFloat = 40 // Distance of the grey circles from the number (radius of the arc)
    let purpleArcRadius: CGFloat = 60 // Distance of the purple circles from the center (larger radius)
    
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    
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
                .fontWeight(.thin)
//                .bold()
                .fontDesign(.rounded)

            // GeometryReader to help position circles
            GeometryReader { geometry in
                let circlesCount = tasbeeh / 100
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Purple circles at the top, further from the center
                ZStack {
                    ForEach(0..<min(circlesCount / 10, 10), id: \.self) { index in
                        Circle()
                            .fill(colorScheme == .dark ? Color.green.opacity(0.6) : Color.green)
//                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [.yellow.opacity(0.6), .green.opacity(0.8)] : [.yellow, .green]), startPoint: .topLeading, endPoint: .bottomTrailing))
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
        .frame(width: 200, height: 200) //i want this to be a circle though
//            .background(.yellow)
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

struct pauseStatsAndBG: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @State private var showMantraSheetFromPausedPage = false
    @State private var chosenMantra: String? = ""
    @State private var rateTextToggle = false  // to control the toggle text in the middle
        
    let paused: Bool
    let tasbeeh: Int
    let timePassedAtPause: String
    let avgTimePerClick: TimeInterval
    let tasbeehRate: String
    let togglePause: () -> Void // Closure for the togglePause function
    let takingNotes: Bool
    
    
    var body: some View {
        
        
        Color("pauseColor")
            .edgesIgnoringSafeArea(.all)
            .animation(.easeOut(duration: 0.3), value: paused)
            .onTapGesture { togglePause() }
            .opacity(paused ? 1 : 0.0)
        
        
        VStack(spacing: 20){
            
            //The Mode Text
            switch sharedState.selectedMode {
            case 1:
                Text("\(sharedState.selectedMinutes)m Session")
                    .font(.title2)
                    .bold()
            case 2:
                Text("\(sharedState.targetCount) Count Session")
                    .font(.title2)
                    .bold()
            default:
                Text("Freestyle Session")
                    .font(.title2)
                    .bold()
            }
            
            //The Mantra Picker
            Text("\(sharedState.titleForSession != "" ? sharedState.titleForSession : "No Selected Mantra")")
                .frame(width: 150)
                .fontDesign(.rounded)
                .fontWeight(.thin)
                .multilineTextAlignment(.center)
                .padding()
                .background(.gray.opacity(0.08))
                .cornerRadius(10)
                .onTapGesture {
                    showMantraSheetFromPausedPage = true
                }
                .onChange(of: chosenMantra){
                    if let newSetMantra = chosenMantra{
                        sharedState.titleForSession = newSetMantra
                    }
                }
                .sheet(isPresented: $showMantraSheetFromPausedPage) {
                    MantraPickerView(isPresented: $showMantraSheetFromPausedPage, selectedMantra: $chosenMantra, presentation: [.large])
                }
            
            
            
            //The Stats
            if paused && !takingNotes {
                
                Text("Count: \(tasbeeh)")
                    .fontWeight(.thin)
                    .fontDesign(.rounded)
                
                Text("Time: \(timePassedAtPause)")
                    .fontWeight(.thin)
                    .fontDesign(.rounded)
                
                ExternalToggleText(
                    originalText: "Time Per Tasbeeh: \(tasbeehRate)",
                    toggledText: "Time Per Click: \((String(format: "%.2f", avgTimePerClick)))s",
                    externalTrigger: $rateTextToggle,  // Pass the binding
                    fontDesign: .rounded,
                    fontWeight: .thin,
                    hapticFeedback: true
                )
            }
        }
        .padding()
        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the stats box
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
        .padding(.horizontal, 30)
        .opacity(paused ? 1.0 : 0.0)
        .animation(.easeInOut, value: paused)
        
    }
}

struct inactivityAlert: View {
    let countDownForAlert: Int
    let showOn: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Text("You still there?")
            Text("(autostopping in \(countDownForAlert))")
                .multilineTextAlignment(.center)
        }
        .fontDesign(.rounded)
        .fontWeight(.thin)
        .padding()
        .background(.gray.opacity(0.08))
        .cornerRadius(10)
        .onTapGesture {
            action() //to dismiss and not increment... i think lol
        }
        .opacity(showOn ? 1 : 0.0)
        .padding(.bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(1)
        .animation(.easeInOut, value: showOn)
    }
}

struct stopButton: View {
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


struct startStopButton: View {
    let timerIsActive: Bool
    let toggleTimer: () -> Void
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    
    var body: some View{


        Button(action: toggleTimer, label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .foregroundStyle(.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 20)
//                    .foregroundStyle(timerIsActive ? .green.opacity(0.5) : .blue.opacity(0.5))
                    .foregroundStyle(timerIsActive ?
                                     LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [.yellow.opacity(0.6), .green.opacity(0.8)] : [.yellow, .green]), startPoint: .topLeading, endPoint: .bottomTrailing)
                                     :
                                        LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [.blue.opacity(0.5), .blue.opacity(0.5)] : [.blue.opacity(0.6), .blue.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing))
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

struct NoteModalView: View {
    @Binding var savedText: String
    @Binding var showSheet: Bool
    @Binding var takingNotes: Bool
    @State private var tempText = ""
    
    var body: some View {
        NavigationView {
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
        }
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


/// Effect Modifier Views -------------------------------------------------------------------------------------------------------------
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

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}





struct RingStyle0 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }
    
    var body: some View {
        ZStack {
            // Pulsing outer circle for current prayer
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
            } else {
                // Placeholder circle to maintain size consistency
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }
            
            // Main colored ring
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            if isCurrentPrayer {
                // Progress arc that changes size over time
                CustomArc(progress: progress)
                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(0))
                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
                    .overlay(
                        // Small circle indicator at the end of the progress arc
                        Circle()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2),
                                   y: 100 * sin(2 * .pi * progress - .pi / 2))
                            .animation(.smooth, value: progress)
                            .animation(.smooth, value: progressColor)
                    )
                    .animation(.smooth, value: progress)
                    .animation(.smooth, value: progressColor)
            }
            
            // Inner gradient circle for depth effect
            Circle()
                .stroke(lineWidth: 0.34)
                .frame(width: 175, height: 175)
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                .overlay {
                    // Blurred inner circle border for additional depth
                    Circle()
                        .stroke(.black.opacity(0.1), lineWidth: 2)
                        .blur(radius: 5)
                        .mask {
                            Circle()
                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                }
            
            // Add Qibla indicator at the top
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
        }
    }
}

struct RingStyle1 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }
    
    var body: some View {
        ZStack {
            // Pulsing outer circle for current prayer
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
            } else {
                // Placeholder circle to maintain size consistency
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }
            
            // Main colored ring
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            if isCurrentPrayer {
                // Progress arc that changes size over time
                CustomArc(progress: progress)
                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .butt))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(0))
                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
                    .overlay(
                        // Small circle indicator at the end of the progress arc
                        Circle()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(progressColor)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2),
                                   y: 100 * sin(2 * .pi * progress - .pi / 2))
                            .animation(.smooth, value: progress)
                            .animation(.smooth, value: progressColor)
                    )
                    .animation(.smooth, value: progress)
                    .animation(.smooth, value: progressColor)
            }
            
            // Inner gradient circle for depth effect
            Circle()
                .stroke(lineWidth: 0.34)
                .frame(width: 175, height: 175)
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                .overlay {
                    // Blurred inner circle border for additional depth
                    Circle()
                        .stroke(.black.opacity(0.1), lineWidth: 2)
                        .blur(radius: 5)
                        .mask {
                            Circle()
                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                }
            
            // Add Qibla indicator at the top
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
        }
    }
}

struct RingStyle2 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }
    
    var body: some View {
        ZStack {
            // Outer pulsing circle (only for current prayer)
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
            } else {
                // Placeholder circle for non-current prayers
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }

            // Base ring (background)
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))

//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            // Progress arc (only for current prayer)
            if isCurrentPrayer {
                CustomArc(progress: progress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round,
                        lineJoin: .round
                    ))
                    .frame(width: 200, height: 200)
                    .foregroundStyle(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: progressColor.opacity(0.8), location: 0),
                                .init(color: progressColor, location: progress)
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + (360 * progress))
                        )
                    )
                    .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
            }
            
            // Inner gradient circle for depth effect
            Circle()
                .stroke(lineWidth: 0.34)
                .frame(width: 175, height: 175)
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                .overlay {
                    // Blurred inner circle border for additional depth
                    Circle()
                        .stroke(.black.opacity(0.1), lineWidth: 2)
                        .blur(radius: 5)
                        .mask {
                            Circle()
                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                }
            
            // White circle indicator at the top for Qibla
            Circle()
                .frame(width: 8, height: 8) // Adjust size as needed
                .offset(y: -100) // Half of the ring's width (200/2) to position at top
                .foregroundStyle(progressColor == .white ? .gray : .white) // Only show if Qibla is aligned
                .opacity(isQiblaAligned ? 0.5 : 0) // Only show if Qibla is aligned

        }
    }
}

struct RingStyle3 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }
    
    private var timeRemaining: TimeInterval {
        prayer.endTime.timeIntervalSinceNow
    }
    
    private var isInFinalSeconds: Bool {
        timeRemaining < 4
    }
    
    private var clockwiseProgress: Double {
        1 - progress
    }
    
    private var finalAnimation: Double {
        if isInFinalSeconds {
            // Convert remaining time to 0-1 range with dramatic acceleration
            let progress = 1 - (timeRemaining-1 / 3)
            return pow(progress, 5) // Quartic easing for dramatic effect
        }
        return 0
    }
    
    var body: some View {
        ZStack {
            // Outer pulsing circle (only for current prayer)
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
            } else {
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }

            // Base ring (background)
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            // Progress arc (only for current prayer)
            if isCurrentPrayer {
                // Layer 1: Dynamic trailing background piece
                if clockwiseProgress > 0.1  {
                    Circle()
                        .trim(from: isInFinalSeconds ?
                              max(clockwiseProgress * finalAnimation, 0) :
                                0, to: isInFinalSeconds ?  1 : clockwiseProgress-0.05)
                        .stroke(style: StrokeStyle(
                            lineWidth: 24,
                            lineCap: .round
                        ))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
//                        .foregroundStyle(progressColor)
                        .foregroundStyle(isInFinalSeconds ? .blue.opacity(0.3) : progressColor)
                }
                
                // Layer 2: Small shadow segment
                Circle()
                    .trim(from: isInFinalSeconds ?
                          max(clockwiseProgress - (0.08 * (1 - finalAnimation)), 0) :
                          max(clockwiseProgress - 0.08, 0),
                          to: clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
                    .foregroundStyle(isInFinalSeconds ? .green.opacity(0.3) : progressColor)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
                    .opacity(clockwiseProgress)
                
                // Layer 3: Main progress arc
                Circle()
                    .trim(from: isInFinalSeconds ?
                          max(clockwiseProgress * finalAnimation, 0.1) :
                          (clockwiseProgress > 0.15 ? 0.1 : 0),
                          to: clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
                    .foregroundStyle(isInFinalSeconds ? .orange.opacity(0.3) : progressColor)
            }
            
            // Inner gradient circle for depth effect
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
            
            // Qibla indicator at the top
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
        }
        // .id(timeRemaining) // Forces view to update as time changes
        // .animation(.easeOut(duration: 0.2), value: finalAnimation)
    }
}

struct RingStyle4 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool

    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }

    private var timeRemaining: TimeInterval {
        prayer.endTime.timeIntervalSinceNow
    }

    private var isInFinalSeconds: Bool {
        timeRemaining < 3
    }

    private var clockwiseProgress: Double {
        1 - progress
    }

    private var startPoint: Double {
        if isInFinalSeconds {
            // Convert the remaining time to a 0-1 progress
            let finalProgress = 1 - (timeRemaining / 3)

            // Apply cubic-bezier easing for acceleration
            let easedProgress = pow(finalProgress, 3) // Cubic easing
            // or for even more dramatic acceleration:
            // let easedProgress = pow(finalProgress, 4) // Quartic easing

            // Calculate the start point position
            return clockwiseProgress * easedProgress
        }
        return clockwiseProgress > 0.85 ? 0.25 : 0  // Changed from 0.75
    }

    var body: some View {
        ZStack {
            // Outer pulsing circle (only for current prayer)
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
            } else {
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }

            // Base ring (background)
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)

            // Progress arc (only for current prayer)
            if isCurrentPrayer {
                // Only show overlap pieces when not in final seconds
                if clockwiseProgress > 0.85 && !isInFinalSeconds {  // Changed from 0.75
                    // Layer 1: Static background piece
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(style: StrokeStyle(
                            lineWidth: 24,
                            lineCap: .round
                        ))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(progressColor)

                    // Layer 2: Overlap effect piece
                    Circle()
                        .trim(from: 0.15, to: 0.3)
                        .stroke(style: StrokeStyle(
                            lineWidth: 24,
                            lineCap: .round
                        ))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(progressColor)
                        .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
                }

                // Main progress arc with animated start point
                Circle()
                    .trim(from: startPoint, to: clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)

                // Shadow segment
                if !isInFinalSeconds {
                    Circle()
                        .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
                        .stroke(style: StrokeStyle(
                            lineWidth: 24,
                            lineCap: .round
                        ))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(progressColor)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
                        .opacity(clockwiseProgress)
                }
            }

            // Inner gradient circle for depth effect
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

            // White circle indicator at the top for Qibla
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: startPoint)
    }
}

//struct RingStyle3OldSimple {
//    let prayer: Prayer
//    let progress: Double
//    let progressColor: Color
//    let isCurrentPrayer: Bool
//    let isAnimating: Bool
//    let colorScheme: ColorScheme
//    let isQiblaAligned: Bool
//
//    init(prayer: Prayer,
//         progress: Double,
//         progressColor: Color,
//         isCurrentPrayer: Bool,
//         isAnimating: Bool,
//         colorScheme: ColorScheme,
//         isQiblaAligned: Bool) {
//        self.prayer = prayer
//        self.progress = progress
//        self.progressColor = progressColor
//        self.isCurrentPrayer = isCurrentPrayer
//        self.isAnimating = isAnimating
//        self.colorScheme = colorScheme
//        self.isQiblaAligned = isQiblaAligned
//    }
//
//    // Convert countdown progress to clockwise progress
//    private var clockwiseProgress: Double {
//        1 - progress // Invert the progress
//    }
//
//    var body: some View {
//        ZStack {
//            // Outer pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
//            } else {
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//
//            // Base ring (background)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//
//            // Progress arc (only for current prayer)
//            if isCurrentPrayer {
//                // Layer 1: Small shadow segment that follows the progress
//                Circle()
//                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
//                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
//                    .opacity(clockwiseProgress)
//
//                // Layer 2: Main progress arc
//                Circle()
//                    .trim(from: 0, to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
//            }
//
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//
//            // Qibla indicator
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//    }
//}

struct RingStyle5 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: Prayer,
         progress: Double,
         progressColor: Color,
         isCurrentPrayer: Bool,
         isAnimating: Bool,
         colorScheme: ColorScheme,
         isQiblaAligned: Bool) {
        self.prayer = prayer
        self.progress = progress
        self.progressColor = progressColor
        self.isCurrentPrayer = isCurrentPrayer
        self.isAnimating = isAnimating
        self.colorScheme = colorScheme
        self.isQiblaAligned = isQiblaAligned
    }
    
    private var clockwiseProgress: Double {
        1 - progress
    }
    
    private var timeRemaining: TimeInterval {
        prayer.endTime.timeIntervalSinceNow
    }
    
    private var isInFinalSeconds: Bool {
        timeRemaining < 3
    }
    
    private var finalAnimation: Double {
        if isInFinalSeconds {
            let progress = 1 - (timeRemaining / 3)
            return pow(progress, 5)
        }
        return 0
    }
    
    private var ringTipShadowOffset: CGPoint {
        let ringTipPosition = tipPosition(progress: clockwiseProgress, radius: 100) // 200/2 for radius
        let shadowPosition = tipPosition(progress: clockwiseProgress + 0.0075, radius: 100)
        return CGPoint(
            x: shadowPosition.x - ringTipPosition.x,
            y: shadowPosition.y - ringTipPosition.y
        )
    }
    
    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
        return CGPoint(
            x: radius * cos(progressAngle.radians),
            y: radius * sin(progressAngle.radians)
        )
    }
    
    var body: some View {
        ZStack {
            // Outer pulsing circle
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
                    .frame(width: 224, height: 224)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(isAnimating ? 1.15 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
            } else {
                Circle()
                    .frame(width: 224, height: 224)
                    .opacity(0)
            }
            
            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)

            // Base ring
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            if isCurrentPrayer {
                // Main progress arc
                Circle()
                    .trim(from: isInFinalSeconds ?
                          (clockwiseProgress * finalAnimation) : 0,
                          to: clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundColor(progressColor)
                
                // Tip shadow as trimmed circle
                Circle()
//                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
            
//                .trim(from: isInFinalSeconds ?
//                  (clockwiseProgress * finalAnimation) :
//                    clockwiseProgress,
//                  to:
//                    isInFinalSeconds ?
//                  (clockwiseProgress * finalAnimation - 0.003) : // Just a tiny segment
//                  (clockwiseProgress - 0.003))
            
                .trim(from: clockwiseProgress - 0.001, // 0.001 = about 0.36 degrees (360° * 0.001)
                  to: clockwiseProgress)            // Difference of just 0.36° creates a dot
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundColor(progressColor)
                    .shadow(
                        color: .black.opacity(0.3),
                        radius: 2.5,
                        x: ringTipShadowOffset.x,
                        y: ringTipShadowOffset.y
                    )
                .opacity(clockwiseProgress)
            }
            
            // Inner gradient circle for depth
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
            
            // Qibla indicator
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: finalAnimation)
    }
}

struct RingStyle6 {
    let prayer: Prayer
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    private var clockwiseProgress: Double {
        1 - progress
    }
    
    private var timeRemaining: TimeInterval {
        prayer.endTime.timeIntervalSinceNow
    }
    
    private var isInFinalSeconds: Bool {
        timeRemaining < 3  // Changed from 6 to 4 (total time needed)
    }

    private var finalAnimation: Double {
        if isInFinalSeconds {
            let progress = 1 - ((timeRemaining - 0.4) / 3)  // Changed from (timeRemaining - 2) / 4
            return min(max(pow(progress, 7), 0), 1)
        }
        return 0
    }
    
    private var ringTipShadowOffset: CGPoint {
        let ringTipPosition = tipPosition(progress: clockwiseProgress, radius: 100)
        let shadowPosition = tipPosition(progress: clockwiseProgress + 0.0075, radius: 100)
        return CGPoint(
            x: shadowPosition.x - ringTipPosition.x,
            y: shadowPosition.y - ringTipPosition.y
        )
    }
    
    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
        return CGPoint(
            x: radius * cos(progressAngle.radians),
            y: radius * sin(progressAngle.radians)
        )
    }
    
    var body: some View {
        ZStack {
            // Outer pulsing circle
            if isCurrentPrayer {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
                    .frame(width: 224, height: 224)
                    .scaleEffect(isAnimating ? 1.2 : 1)
                    .opacity(isAnimating ? -0.05 : 0.7)
                    .foregroundStyle(colorScheme == .dark ? progressColor.opacity(0.7) : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)

                //this is so pulse gets hidden behind the other transparent layers.
                Circle()
                    .frame(width: 224, height: 224)
                    .foregroundStyle(Color("bgColor"))
            }

            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
            
            // uncomment this if you want the unprogressed part of the track to be colored instead of clear
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor == .white ? progressColor.opacity(0.6) : progressColor.opacity(0.15))
            
            if isCurrentPrayer {
                // Main progress arc with gradient
                Circle()
                    .trim(from: finalAnimation >= 1 ? 0 : (isInFinalSeconds ? (clockwiseProgress * finalAnimation) : 0),
                          to: finalAnimation >= 1 ? 0 : clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(
                         AngularGradient(
                             gradient: Gradient(colors: [
                                isInFinalSeconds ? progressColor.opacity(max((finalAnimation), 0.5)) : progressColor.opacity(max((1-clockwiseProgress), 0.5)),
                                 progressColor
                             ]),
                             center: .center,
                             startAngle: .degrees(0),
                             endAngle: .degrees((360 * clockwiseProgress))
                        )
                    )
                    .opacity(isInFinalSeconds ? (1 - finalAnimation)*3.5 : 1) // Fade out gradient
                
                // Ring tip with shadow
                Circle()
                    .trim(from: finalAnimation >= 1 ?  0 :     clockwiseProgress - 0.001,
                          to:   finalAnimation >= 1 ?   0 :     clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .shadow(
                        color: .black.opacity(isInFinalSeconds ? 0.3*(1-finalAnimation*2) : min(0.5 * clockwiseProgress, 0.3)),
                        radius: 2.5,
                        x: ringTipShadowOffset.x,
                        y: ringTipShadowOffset.y
                    )
                    .opacity(finalAnimation > 0.05 ? 1 - finalAnimation : 1) // Fade out tip
                    .zIndex(1)
                
                // dot at the top for the animation so we can make everything opacity 0 and keep animation crisp.
                Circle()
                    .trim(from:  0,
                          to:   0.001)
                    .stroke(style: StrokeStyle(
                        lineWidth: 24,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(clockwiseProgress >= 0.99 || clockwiseProgress <= 0.01 ? 1 : 0)
            }
            
            // Inner gradient circle for depth
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
            
            // Qibla indicator
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .foregroundStyle(progressColor == .white ? .gray : .white)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
        }
    }
}























struct ToggleText: View {
    let originalText: String
    let toggledText: String
    let font: Font?
    let fontDesign: Font.Design?
    let fontWeight: Font.Weight?
    let hapticFeedback: Bool
    
    @State private var showOriginal = true
    @State private var timer: Timer?
    
    init(
        originalText: String,
        toggledText: String,
        font: Font? = nil,
        fontDesign: Font.Design? = .rounded,
        fontWeight: Font.Weight? = .thin,
        hapticFeedback: Bool = true
    ) {
        self.originalText = originalText
        self.toggledText = toggledText
        self.font = font
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.hapticFeedback = hapticFeedback
    }
    
    var body: some View {
        Text(showOriginal ? originalText : toggledText)
            .font(font)
            .fontDesign(fontDesign)
            .fontWeight(fontWeight)
            .onTapGesture {
                handleTap()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
    
    private func handleTap() {
        timer?.invalidate()
        
        if hapticFeedback {
            triggerSomeVibration(type: .light)
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showOriginal.toggle()
        }
        
        if !showOriginal {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOriginal = true
                }
            }
        }
    }
}


struct ExternalToggleText: View {
    let originalText: String
    let toggledText: String
    let font: Font?
    let fontDesign: Font.Design?
    let fontWeight: Font.Weight?
    let hapticFeedback: Bool
    
    @State private var showOriginal = true
    @State private var timer: Timer?
    @Binding var externalTrigger: Bool
    
    init(
        originalText: String,
        toggledText: String,
        externalTrigger: Binding<Bool> = .constant(false), // Default to constant false if not provided
        font: Font? = nil,
        fontDesign: Font.Design? = .rounded,
        fontWeight: Font.Weight? = .thin,
        hapticFeedback: Bool = true
    ) {
        self.originalText = originalText
        self.toggledText = toggledText
        self._externalTrigger = externalTrigger
        self.font = font
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.hapticFeedback = hapticFeedback
    }
    
    var body: some View {
        Text(showOriginal ? originalText : toggledText)
            .font(font)
            .fontDesign(fontDesign)
            .fontWeight(fontWeight)
            .onTapGesture {
                handleTap()
            }
            .onChange(of: externalTrigger) { _, _ in
                handleTap()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
    
    private func handleTap() {
        timer?.invalidate()
        
        if hapticFeedback {
            triggerSomeVibration(type: .light)
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showOriginal.toggle()
        }
        
        if !showOriginal {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOriginal = true
                }
            }
        }
    }
}


struct ToggleTextExample: View {
    @State private var autoRevertTimer: Timer?
    @State private var textTrigger = false  // Add this state
    
    var body: some View {
        VStack(spacing: 20) {
            
            ToggleText(
                originalText: "this text is",
                toggledText: "changed"
            )
            ToggleText(
                originalText: "seperate from this",
                toggledText: "changed"
            )
            ExternalToggleText(
                originalText: "hit the blue or this",
                toggledText: "changed",
                externalTrigger: $textTrigger,  // Pass the binding
                fontDesign: .rounded,
                fontWeight: .thin,
                hapticFeedback: true
            )
            Circle()
                .fill(Color.blue)
                .frame(width: 200, height: 200)
                .onTapGesture {
                    textTrigger.toggle()  // Toggle the trigger
                }
        }
        .onDisappear {
            autoRevertTimer?.invalidate()
            autoRevertTimer = nil
        }
    }
}


#Preview {
    ToggleTextExample()
}


struct DragGestureModifier: ViewModifier {
    @Binding var dragOffset: CGFloat
    let onEnd: (CGFloat) -> Void
    let calculateResistance: (CGFloat) -> CGFloat

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation.height != 0 {
                            dragOffset = calculateResistance(value.translation.height)
                        }
                    }
                    .onEnded { value in
                        onEnd(value.translation.height)
                    }
            )
        
    }
}

func calculateResistance(_ translation: CGFloat) -> CGFloat {
        let maxResistance: CGFloat = 40
        let rate: CGFloat = 0.01
        let resistance = maxResistance - maxResistance * exp(-rate * abs(translation))
        return translation < 0 ? -resistance : resistance
    }

extension View {
    func applyDragGesture(dragOffset: Binding<CGFloat>, onEnd: @escaping (CGFloat) -> Void, calculateResistance: @escaping (CGFloat) -> CGFloat) -> some View {
        self.modifier(DragGestureModifier(dragOffset: dragOffset, onEnd: onEnd, calculateResistance: calculateResistance))
    }
}


// Function to open to the left
private func openLeftPage(proxy: ScrollViewProxy) {
    print("Clicked to go to id 0")
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    withAnimation{
        proxy.scrollTo(0, anchor: .center)
    }
}
