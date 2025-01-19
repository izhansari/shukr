import SwiftUI
import AudioToolbox
import MediaPlayer
import Adhan
import SwiftData

// MARK: - Utility Functions
func roundToTwo(val: Double) -> Double {
    return ((val * 100.0).rounded() / 100.0)
}

// MARK: - Time Formatters

// Displays as "in 2h 3m" or "in 3m" or "in 32s"
func timeUntilStart(_ startTime: Date) -> String {
    let interval = startTime.timeIntervalSince(Date())
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    let seconds = Int(interval) % 60

    if hours > 0 {
        return "in \(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "in \(minutes)m"
    } else {
        return "in \(seconds)s"
    }
}

//// Displays as "3m 46s" or "32s"
//func formatSecToMinAndSec(_ totalSeconds: TimeInterval) -> String {
//    let minutes = Int(totalSeconds) / 60
//    let seconds = Int(totalSeconds) % 60
//    
//    if minutes > 0 { return "\(minutes)m \(seconds)s"}
//    else { return "\(seconds)s" }
//}

// Displays as "01:32:49" or "25:07"
func timerStyle(_ totalSeconds: Double) -> String {
    let roundedSeconds = Int(round(totalSeconds))
    let hours = roundedSeconds / 3600
    let minutes = (roundedSeconds % 3600) / 60
    let seconds = roundedSeconds % 60
    
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds) // 00:00:00
    } else {
        return String(format: "%02d:%02d", minutes, seconds) // 00:00
    }
}

// DIsplays as 2:01
func shortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm"
    return formatter.string(from: date)
}

// DIsplays as 2:01 AM
func shortTimePM(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

// Displays as 5:41 AM 12/05
func shortTimePMDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a MM/dd"
    return formatter.string(from: date)
}

// Displays as 2:01:14 AM
func shortTimeSecPM(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm:ss a"
    return formatter.string(from: date)
}

// Displays as "3h 24m left", "24m left" or "43s left"
func timeLeftString(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 { components.append("\(hours)h") }
    
    if minutes > 0 { components.append("\(minutes)m") }
    
    if totalSeconds < 60 { components.append("\(seconds)s") } // Only show seconds if less than a minute

    if components.isEmpty { return "0s left" } // If no time left, return "0s left"

    return components.joined(separator: " ") + " left"
}

// returns "h + m", "m", or"s" as string
func formatTimeInterval(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    let seconds = Int(interval) % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(seconds)s"
    }
}

// returns "h+m+s", "m+s", or"s" as string
func formatTimeIntervalWithS(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    let seconds = Int(interval) % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m \(seconds)s"
    } else if minutes > 0 {
        return "\(minutes)m" + " \(seconds)s"
    } else {
        return "\(seconds)s"
    }
}

// Use to return a custom time in today
func todayAt(_ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
}

// Displays as "in 3h 24m", "in 24m" or "in 43s"
func inMinSecStyle(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 { components.append("\(hours)h") }
    
    if minutes > 0 { components.append("\(minutes)m") }
    
    if totalSeconds < 60 { components.append("\(seconds)s") } // Only show seconds if less than a minute

    // Join components with a space and prepend "in "
    return "in " + components.joined(separator: " ")
}

// Displays as "in 3h 24m", "in 24m and 20s" or "in 43s"
func inMinSecStyle2(from timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(timeInterval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    // Building the formatted string
    var components: [String] = []

    if hours > 0 { components.append("\(hours)h") }
    
    if minutes > 0 { components.append("\(minutes)m") }
    
    if minutes > 0 { components.append("& \(seconds)s") } // Only show seconds if less than a minute

    // Join components with a space and prepend "in "
    return "in " + components.joined(separator: " ")
}

// Turns Date type into 1/12/24
func formatDateToShorthand(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "M/d/y"
    return dateFormatter.string(from: date)
}



// MARK: - Vibration Feedback
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
    
//    let userDefaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
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



// MARK: - Subviews



//MARK: - Custom Buttons
///most of these  are found in the tasbeeh pause page

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
    @Binding var toggleInactivityTimer: Bool
    @Binding var tasbeehColorMode: Bool
    let onSymbol: String = "bed.double.fill"
    let onColor: Color = .orange
    let offSymbol: String = "bed.double"
    let offColor: Color = .gray
    
    var body: some View {
        Button(action: {
            toggleInactivityTimer.toggle()
            if toggleInactivityTimer == true && tasbeehColorMode == false {
                tasbeehColorMode.toggle()
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
    @Binding var tasbeehColorMode: Bool

    var body: some View {
        twoModeToggleButton(
            boolToToggle: $tasbeehColorMode,
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

struct ExitButton: View{ //FIXME: maybe use this as the complete button we have now.
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



//MARK: - Tasbeeh Mode Selection Views
struct freestyleMode: View {
    var body: some View {
        Circle()
            .frame(width: 30, height: 30)
            .foregroundStyle(Color("NeuRing"))
            .shadow(
                color: Color("NeuDarkShad"), // shadow top lighter
                radius: 1,
                x: 2,
                y: 2
            )
            .shadow(
                color: Color("NeuLightShad")/*Color(.white).opacity(0.1)*/, // shadow top lighter
                radius: 1,
                x: -2,
                y: -2
            )
    }
}

struct timeTargetMode: View {
    @Binding var selectedMinutesBinding: Int

    var body: some View {
        Picker("Minutes", selection: $selectedMinutesBinding) {
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
                .multilineTextAlignment(.center) // Align text in the center
                .padding()
                .keyboardType(.numberPad) // Limits input to numbers only
                .frame(width: 90)
                .background(Color("NeuRing"))
                .cornerRadius(15)
                .shadow(
                    color: Color("NeuDarkShad"), // shadow top lighter
                    radius: 4,
                    x: 2,
                    y: 2
                )
                .shadow(
                    color: Color("NeuLightShad"), // shadow top lighter
                    radius: 4,
                    x: -3,
                    y: -3
                )
                .onTapGesture {
                    isNumberEntryFocused = true
                }
        }
    }
}

struct inputOffsetSubView: View { //used in count
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



// MARK: - Tasbeeh Views

struct oldCircularProgressView: View {
    let progress: CGFloat
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    var body: some View {
        ZStack {
            // Outer Circle with Dynamic Shadow
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundColor(colorScheme == .dark ? Color(.secondarySystemBackground) : Color("wheelColor"))
                .shadow(
                    color: colorScheme == .dark
                        ? .white.opacity(0.1) // Light shadow for dark mode
                        : .black.opacity(0.1), // Dark shadow for light mode
                    radius: 10,
                    x: colorScheme == .dark ? -10 : 10,
                    y: colorScheme == .dark ? -10 : 10
                )
            
            // Inner Circle with Dynamic Gradient
            Circle()
                .stroke(lineWidth: 0.34)
                .frame(width: 175, height: 175)
                .foregroundStyle( colorScheme == .dark ?
                    LinearGradient(
                        gradient: Gradient(
                            colors: [.white.opacity(0.05), .clear]
                        ),
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    )
                                  :
                    LinearGradient(
                        gradient: Gradient(
                            colors: [.black.opacity(0.3), .clear]
                        ),
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            colorScheme == .dark
                                ? .white.opacity(0.1)
                                : .black.opacity(0.1),
                            lineWidth: 2
                        )
                        .blur(radius: 5)
                        .mask {
                            Circle()
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors: colorScheme == .dark
                                                ? [.white, .clear]
                                                : [.black, .clear]
                                        ),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                }
            
            // Progress Indicator with Dynamic Gradient
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: colorScheme == .dark
                                ? [.yellow.opacity(0.6), .green.opacity(0.8)]
                                : [.yellow, .green]
                        ),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.spring(), value: progress)
        }
    }
}


struct NeuCircularProgressView: View {
    let progress: CGFloat
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme

    var body: some View {
        ZStack {
            // Outer Circle with Dynamic Shadow
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundColor(Color("NeuRing"))
                .shadow(
                    color: Color("NeuDarkShad"), // shadow top lighter
                    radius: 4,
                    x: 2,
                    y: 2
                )
                .shadow(
                    color: Color("NeuLightShad"), // shadow top lighter
                    radius: 6,
                    x: -2,
                    y: -2
                )
            
            // Progress Indicator with Dynamic Gradient
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: colorScheme == .dark
                                ? [.yellow.opacity(0.6), .green.opacity(0.8)]
                                : [.yellow, .green]
                        ),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.spring(), value: progress)
        }
    }
}


// Preview Provider
struct NeumorphicProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        ZStack{
            Rectangle().fill(Color("NeuRing")).frame(width: 400, height: 400)
            NeuCircularProgressView(progress: 0)
        }
    }
}

struct TasbeehCountView: View { // YEHSIRRR we got purples doing same thing from top down now. No numbers. Clean.
    let tasbeeh: Int
    let circleSize: CGFloat = 10 // Circle size
    let arcRadius: CGFloat = 60 // Distance of the grey circles from the number (radius of the arc)
    let purpleArcRadius: CGFloat = 40 // Distance of the purple circles from the center (larger radius)
    
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
                .fontDesign(.rounded)

            // GeometryReader to help position circles
            GeometryReader { geometry in
                let beadCount = tasbeeh % 100
                let circlesCount = tasbeeh / 100
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ZStack{
                    // Border circles representing each bed
                    ForEach(0..<100) { index in
                        NeumorphicBead()
                            .opacity(index < beadCount ? 1 : 0)
//                        Circle()
//                            .fill(index < beadCount ? Color.green : Color.clear)
//                            .frame(width: 5, height: 5) // Adjust size as needed
                            .position(beadPosition(for: index, center: center)) // Purple circles further out
                    }
                }
                .rotationEffect(.degrees(180+(360/100)))
                
                // Purple circles at the top, further from the center
                ZStack {
                    ForEach(0..<min(circlesCount / 10, 10), id: \.self) { index in
                        Circle()
                            .fill(colorScheme == .dark ? Color.green.opacity(0.6) : Color.green)
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
    }
    
    // Function to calculate the position of each grey circle like clock positions (now with 10 hands)
    func beadPosition(for index: Int, center: CGPoint) -> CGPoint {
        let stepAngle: CGFloat = 2 * .pi / 100 // Divide the circle into 100 positions (like a clock with 100 hands)
        let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
        let angle = startAngle + stepAngle * CGFloat(index)
        let x = center.x + 140 * cos(angle) // X position using cosine
        let y = center.y + 140 * sin(angle) // Y position using sine
        return CGPoint(x: x, y: y)
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
        let x = center.x + purpleArcRadius * cos(angle) // Push further out and flip vertically
        let y = center.y + purpleArcRadius * sin(angle) // Flip vertically for top positioning
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
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @EnvironmentObject var sharedState: SharedStateClass
    @State private var showMantraSheetFromPausedPage = false
    @State private var chosenMantra: String? = ""
    @State private var rateTextToggle = false  // to control the toggle text in the middle
        
    let paused: Bool
    let tasbeeh: Int
    let secsToReport: TimeInterval
    let avgTimePerClick: TimeInterval
    let tasbeehRate: String
    let togglePause: () -> Void // Closure for the togglePause function
    let stopTimer: () -> Void // Closure for the togglePause function
    let takingNotes: Bool
    @Binding var toggleInactivityTimer: Bool
    @Binding var inactivityDimmer: Double
    @Binding var autoStop: Bool
    @Binding var tasbeehColorMode: Bool
    @Binding var currentVibrationMode: HapticFeedbackType
    
//    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    var colorModeToggle = false
//    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased



    
    // UI state
    private let textSize: CGFloat = 14
    private let gapSize: CGFloat = 10
    @State private var countRotation: Double = 0
    @State private var timerRotation: Double = 0
    @State private var showingPerCount = false
    @State private var showMantraSheetFromResultsPage = false
    @State private var chosenMantraFromResultsPage: String? = ""
    
    // Computed variables for est time completion (only for target count mode)
    private var remainingCount: Int{
        return (Int(sharedState.targetCount) ?? 0) - Int(tasbeeh)
    }
    private var timeLeft : TimeInterval{
        return avgTimePerClick * Double(remainingCount)
    }
    private var finishTime: Date{
        return Date().addingTimeInterval(timeLeft)
    }


    
    var body: some View {
        
        
        Color("pauseColor")
            .edgesIgnoringSafeArea(.all)
            .animation(.easeOut(duration: 0.3), value: paused)
            .onTapGesture { togglePause() }
            .opacity(paused ? 1 : 0.0)
        
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
                HStack{
                    Spacer()
                    Button(action: {
                        stopTimer()
                    }) {
                        Text("Complete")
                            .font(.headline)
                            .bold()
                            .foregroundColor(Color(.secondaryLabel))
                            .padding()
                            .cornerRadius(10)
                    }
                    .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 7)

                    Spacer()
                }
            }
            .padding()
            .padding(.bottom, 20)
            .opacity(paused ? 1.0 : 0.0)
        }
        
    }
    
    
    private var completionCard: some View {
        VStack(alignment: .center, spacing: 12) {
            
            //The Mode Text
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
                                // Per tasbeeh view
                                VStack(spacing: 2) {
                                    Text(String(format: "%.2f", avgTimePerClick))
                                        .font(.system(size: textSize, weight: .medium))
                                        .monospacedDigit()
                                    Text("per count")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .opacity(showingPerCount ? 0 : 1)
                                .offset(y: showingPerCount ? -20 : 0)
                                
                                // Per count view
                                VStack(spacing: 2) {
                                    Text(tasbeehRate)
                                        .font(.system(size: textSize, weight: .medium))
                                        .monospacedDigit()
                                    Text("per tasbeeh")
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
    var startTimer: () -> Void
    
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
        ),
        startTimer: {}
    )
    .environmentObject(SharedStateClass())
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


// MARK: - Effect Modifier Views
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




// MARK: - RingStyles

struct RingStyle0 {
    @AppStorage("qibla_sensitivity") static var alignmentThreshold: Double = 3.5
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: PrayerModel,
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
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: PrayerModel,
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
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: PrayerModel,
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
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: PrayerModel,
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
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool

    init(prayer: PrayerModel,
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

struct RingStyle5 {
    let prayer: PrayerModel
    let progress: Double
    let progressColor: Color
    let isCurrentPrayer: Bool
    let isAnimating: Bool
    let colorScheme: ColorScheme
    let isQiblaAligned: Bool
    
    init(prayer: PrayerModel,
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
    let prayer: PrayerModel
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

struct RingStyle7 {
    let prayer: PrayerModel
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
//                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
                .foregroundColor(colorScheme == .dark ? Color(.secondarySystemBackground) : Color("wheelColor"))
                .shadow(
                    color: colorScheme == .dark
                        ? .white.opacity(0.1) // Light shadow for dark mode
                        : .black.opacity(0.1), // Dark shadow for light mode
                    radius: 10,
                    x: colorScheme == .dark ? -10 : 10,
                    y: colorScheme == .dark ? -10 : 10
                )
            
            // uncomment this if you want the unprogressed part of the track to be colored instead of clear
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundStyle(progressColor.opacity(0.15))
            
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
//                .foregroundStyle(progressColor == .white ? .gray : .white)
                .foregroundStyle(colorScheme == .dark ? .white : isCurrentPrayer ? .white : .gray)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
        }
    }
}

struct RingStyle8 {
    let prayer: PrayerModel
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
                    .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)

                //this is so pulse gets hidden behind the other transparent layers.
                Circle()
                    .frame(width: 224, height: 224)
                    .foregroundStyle(Color("bgColor"))
            }

            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
            NeuCircularProgressView(progress: 0)
            
            // uncomment this if you want the unprogressed part of the track to be colored instead of clear
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor.opacity(0.15))
            
            if isCurrentPrayer {
                // Main progress arc with gradient
                Circle()
                    .trim(from: finalAnimation >= 1 ? 0 : (isInFinalSeconds ? (clockwiseProgress * finalAnimation) : 0),
                          to: finalAnimation >= 1 ? 0 : clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 14,
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
                        lineWidth: 14,
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
                        lineWidth: 14,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(clockwiseProgress >= 0.99 || clockwiseProgress <= 0.01 ? 1 : 0)
            }
            
            // Qibla indicator
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
                .foregroundStyle(colorScheme == .dark ? .white : isCurrentPrayer ? .white : .gray)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
        }
    }
}

struct RingStyle9 {
    let prayer: PrayerModel
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
    
    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
        return CGPoint(
            x: radius * cos(progressAngle.radians),
            y: radius * sin(progressAngle.radians)
        )
    }
    
    var body: some View {
        ZStack {
            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
//            NeuCircularProgressView(progress: 0)
                        
            if isCurrentPrayer {
                
                Circle()
                    .trim(from: finalAnimation >= 1 ? 0 : (isInFinalSeconds ? (clockwiseProgress * finalAnimation) : 0),
                          to: finalAnimation >= 1 ? 0 : clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    ))
                    .fill(
                        Color("bgColor")
                        //indent
                            .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -2, y: 2))
                            .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 2, y: -2))
                    )
                    //outdented
                    .shadow(color: Color("NeuDarkShad"), radius: 1, x: -2, y: 2)
                    .shadow(color: Color("NeuLightShad"), radius: 1, x: 2, y: -2)
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .opacity(isInFinalSeconds ? (1 - finalAnimation)*3.5 : 1) // Fade out gradient
                
                // Ring tip with shadow
                Circle()
                    .trim(from: finalAnimation >= 1 ?  0 :     clockwiseProgress - 0.001,
                          to:   finalAnimation >= 1 ?   0 :     clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(finalAnimation > 0.05 ? 1 - finalAnimation : 1) // Fade out tip
                    .zIndex(1)
                
                // dot at the top for the animation so we can make everything opacity 0 and keep animation crisp.
                Circle()
                    .trim(from:  0,
                          to:   0.001)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(clockwiseProgress >= 0.99 || clockwiseProgress <= 0.01 ? 1 : 0)
            
                // Thin pulsing band
                Circle()
                    .stroke(lineWidth: 2)
                    .frame(width: 222, height: 222)
                    .opacity(isAnimating ? -0.15 : 1)
                    .foregroundStyle(colorScheme == .dark ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
            }
            


            
            // Qibla indicator
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
                .foregroundStyle(colorScheme == .dark ? .white : isCurrentPrayer ? .white : .gray)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
        }
    }
}

struct RingStyle9old {
    let prayer: PrayerModel
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
    
    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
        return CGPoint(
            x: radius * cos(progressAngle.radians),
            y: radius * sin(progressAngle.radians)
        )
    }
    
    var body: some View {
        ZStack {
            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
            NeuCircularProgressView(progress: 0)
                        
            if isCurrentPrayer {
                // Main progress arc with gradient
                Circle()
                    .trim(from: finalAnimation >= 1 ? 0 : (isInFinalSeconds ? (clockwiseProgress * finalAnimation) : 0),
                          to: finalAnimation >= 1 ? 0 : clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
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
                    .opacity(0.6)
                    .opacity(isInFinalSeconds ? (1 - finalAnimation)*3.5 : 1) // Fade out gradient
                
                // Ring tip with shadow
                Circle()
                    .trim(from: finalAnimation >= 1 ?  0 :     clockwiseProgress - 0.001,
                          to:   finalAnimation >= 1 ?   0 :     clockwiseProgress)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(finalAnimation > 0.05 ? 1 - finalAnimation : 1) // Fade out tip
                    .zIndex(1)
                
                // dot at the top for the animation so we can make everything opacity 0 and keep animation crisp.
                Circle()
                    .trim(from:  0,
                          to:   0.001)
                    .stroke(style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    ))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(progressColor)
                    .opacity(clockwiseProgress >= 0.99 || clockwiseProgress <= 0.01 ? 1 : 0)
            
                // Thin pulsing band
                Circle()
                    .stroke(lineWidth: 2)
                    .frame(width: 222, height: 222)
                    .opacity(isAnimating ? -0.15 : 1)
                    .foregroundStyle(colorScheme == .dark ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
            }
            


            
            // Qibla indicator
            Circle()
                .frame(width: 8, height: 8)
                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
                .foregroundStyle(colorScheme == .dark ? .white : isCurrentPrayer ? .white : .gray)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
        }
    }
}


// MARK: - Toggle Text
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


// MARK: - Drag Gestures


//struct DragGestureModifier: ViewModifier {
//    @Binding var dragOffset: CGFloat
//    let onEnd: (CGFloat) -> Void
//    let calculateResistance: (CGFloat) -> CGFloat
//    
//    func body(content: Content) -> some View {
//        content
//            .gesture(
//                DragGesture(minimumDistance: 0)
//                    .onChanged { value in
//                        if value.translation.height != 0 {
//                            dragOffset = calculateResistance(value.translation.height)
//                        }
//                    }
//                    .onEnded { value in
//                        onEnd(value.translation.height)
//                    }
//            )
//    }
//}

//extension View {
//    func applyDragGesture(dragOffset: Binding<CGFloat>, onEnd: @escaping (CGFloat) -> Void, calculateResistance: @escaping (CGFloat) -> CGFloat) -> some View {
//        self.modifier(DragGestureModifier(dragOffset: dragOffset, onEnd: onEnd, calculateResistance: calculateResistance))
//    }
//}


// Function to open to the left
//private func openLeftPage(proxy: ScrollViewProxy) {
//    print("Clicked to go to id 0")
//    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
//    withAnimation{
//        proxy.scrollTo(0, anchor: .center)
//    }
//}



// Color Hex Extension
//extension Color {
//    init(hex: String) {
//        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
//        var int: UInt64 = 0
//        Scanner(string: hex).scanHexInt64(&int)
//        let a, r, g, b: UInt64
//        switch hex.count {
//        case 3: // RGB (12-bit)
//            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
//        case 6: // RGB (24-bit)
//            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
//        case 8: // ARGB (32-bit)
//            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
//        default:
//            (a, r, g, b) = (1, 1, 1, 0)
//        }
//        self.init(
//            .sRGB,
//            red: Double(r) / 255,
//            green: Double(g) / 255,
//            blue:  Double(b) / 255,
//            opacity: Double(a) / 255
//        )
//    }
//}


// MARK: - V1 Prayers Page Experiment

struct TimeColorFadeProgressBar: View {
    // Example start and end times
    let startTime: Date
    let endTime: Date
    @Binding var completedTime: Date?
    
    // Current time
    @State private var currentTime: Date = Date()
    @State private var completed: Bool = false
    
    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                // Progress bar background with dynamic gradient
                GeometryReader { geometry in
                    let progressWidth = CGFloat(progress) * geometry.size.width
                    let tickPosition = progressWidth
                    
                    // Smooth animated color
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: progColor, location: colorPosition),
                                    .init(color: Color.gray.opacity(0.4), location: colorPosition+0.1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)
//                        .animation(.easeInOut(duration: 0.3), value: progColor) // Animate color transition
//                        .animation(.easeInOut(duration: 0.3), value: colorPosition)
                    
                    // Current time text under the tick
                    if(Date() >= startTime && currentTime <= endTime || completedTime != nil){
                        if completedTime ?? Date() <= endTime{
                            Text(shortTime(completedTime ?? Date()))
                                .foregroundColor(.primary)
                                .font(.caption)
                                .position(x: tickPosition, y: -10) // Align text with the tick mark
                            
                            // White tick mark
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: 2, height: 8)
                                .position(x: tickPosition, y: 2) // Position the tick on the progress
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal)
            .padding(.horizontal)
            .animation(.easeInOut(duration: 1), value: colorPosition)
            .animation(.easeInOut(duration: 0.3), value: progColor) // Animate color transition

            
            // Display the start and end times
            HStack {
                Text(shortTime(startTime))
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text(shortTime(endTime))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
        }
        .onAppear {
            // Update current time when the view appears
            currentTime = Date()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Update current time every second
            withAnimation {
                currentTime = Date()
            }
        }
    }
    
    // Computed property to calculate progress between startTime and endTime
    private var progress: Double {
        let totalInterval = endTime.timeIntervalSince(startTime)
        let currentInterval = currentTime.timeIntervalSince(startTime)
        
        if let completedTime = completedTime {
            let completedInterval = completedTime.timeIntervalSince(startTime)
            
            if completedInterval <= 0 {
                return 0.0 // Before start time
            } else if completedInterval >= totalInterval {
                return 1.0 // After end time
            } else {
                return completedInterval / totalInterval // Between start and end times
            }
        }

        
        if currentInterval <= 0 {
            return 0.0 // Before start time
        } else if currentInterval >= totalInterval {
            return 1.0 // After end time
        } else {
            return currentInterval / totalInterval // Between start and end times
        }
    }
    
    private var colorPosition: Double {
        //this is going to return progress. But if completed, then we set to 1
        if(completedTime != nil){
            return 1
        }
        return progress
    }
    
    // Smooth color transition based on progress
    private var progColor: Color {
        if progress >= 1 && completedTime != nil{
            return Color.gray
        } else if progress >= 1 {
            return Color.gray.opacity(0.4)
        } else if progress > 0.75 {
            return Color.red
        } else if progress > 0.50 {
            return Color.yellow
        } else if progress > 0.00 {
            return Color.green
        } else {
            return Color.gray.opacity(0.4)
        }
    }
}


struct TimeProgressViewWithSmoothColorTransition_Previews: PreviewProvider {
    static var previews: some View {
        @Previewable @State var testCompletedTime: Date? = Date()
        // Example preview with specific start and end times
        TimeColorFadeProgressBar(startTime: Date().addingTimeInterval(-4), endTime: Date().addingTimeInterval(2), completedTime: $testCompletedTime)
    }
}


// MARK: - Prayer Views

struct TopBar: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var sharedState: SharedStateClass

    @AppStorage("prayerStreak") var prayerStreak: Int = 0
    @AppStorage("maxPrayerStreak") var maxPrayerStreak: Int = 0

    var viewState: SharedStateClass.ViewPosition { sharedState.newTopMainOrBottom }
//    @GestureState var dragOffset: CGFloat
    
    @State private var showMaxStreakToggle: Bool = false

    
    private var showSalahTab: Bool {
        sharedState.showSalahTab
    }
    
    private var tasbeehModeName: String {
        switch sharedState.selectedMode{
        case 0: return "Freestyle"
        case 1: return "Time Goal"
        case 2: return "Count Goal"
        default: return "Error on page name switch"
        }
    }

    
    var body: some View {
        ZStack{
            VStack{
                if let cityName = viewModel.cityName {
                    ZStack{
                        HStack{ // tasbeeh label
                            Image(systemName: "circle.hexagonpath")
                                .foregroundColor(.secondary)
                            Text("\(tasbeehModeName)")
                            
                        }
                        .opacity(!showSalahTab ? 1 : 0)
                        .offset(x: !showSalahTab ? 0 : 10) // move right
                        
                        
                        HStack{ // location label
                            Image(systemName: "location.fill")
                                .foregroundColor(.secondary)
                            Text(cityName)
                        }
                        .opacity(showSalahTab && viewState != .bottom ? 1 : 0)
                        .offset(y: viewState != .bottom ? 0 : -10) // move up
                        .offset(x: showSalahTab ? 0 : -10) // move left

                        HStack(alignment: .center) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.secondary)
                            ExternalToggleText(
                                originalText: "\(prayerStreak) Prayers",
                                toggledText: "Max \(maxPrayerStreak) Prayers",
                                externalTrigger: $showMaxStreakToggle,  // Pass the binding
                                font: .caption,  // this doesnt take on the parent group's font modifiers. so we define again inside
                                fontDesign: .rounded,
                                fontWeight: .thin,
                                hapticFeedback: true
                            )
                        }
                        .opacity(showSalahTab && viewState == .bottom  ? 1 : 0)
                        .offset(y: viewState == .bottom  ? 0 : 10) // move down
                        .offset(x: showSalahTab ? 0 : -10) // move left

                    }
                    .padding()
                    .frame(height: 24, alignment: .center)
//                    .offset(y: viewState != .bottom && (dragOffset > 0/* || viewState == .top*/) ? dragOffset : 0)
//                    .animation(.easeInOut, value: dragOffset > 0 && viewState != .bottom)
                } else {
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.secondary)
                        Text("Fetching location...")
                    }
                    .frame(height: 24, alignment: .center)
                }
                
                Spacer()
            }
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .padding()
            
            topRightButton(viewState: viewState)
        }
    }
    
    struct topRightButton: View {
        @EnvironmentObject var viewModel: PrayerViewModel
        @EnvironmentObject var sharedState: SharedStateClass
        
        var showSalahTab: Bool { sharedState.showSalahTab }
        var viewState: SharedStateClass.ViewPosition
        var dynamicDestination: AnyView { showSalahTab ? AnyView(SettingsView().environmentObject(viewModel)) : AnyView(HistoryPageView()) }
        var dynamicSFSymbol: String { showSalahTab ? "gear" : "clock" }
        
        
        var body: some View {
//            ZStack{
                VStack{
                    HStack{
    //                    NavigationLink(destination: HistoryPageView()) {
    //                        Image(systemName: "clock")
    //                            .font(.system(size: 24))
    //                            .foregroundColor(.gray)
    //                            .padding(.vertical, 7)
    //                    }
    //                    .frame(width: 30)
    //                    .opacity(!showSalahTab && viewState == .bottom ? 0.7 : 0)
    //                    .opacity(viewState == .top ? 0.7 : 0)

                        Spacer()
                        
//                        NavigationLink(destination: dynamicDestination) {
//                            Image(systemName: dynamicSFSymbol)
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
////                                .padding(.vertical, 7)
//                        }
                        NavigationLink(destination: dynamicDestination) {
                            Image(systemName: dynamicSFSymbol)
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                                .padding()
                        }
                        .opacity(viewState == .bottom ? 0.7 : 0)
                    }
                    Spacer()
                }
        }

    }

}



struct FloatingChainZikrButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @State private var chainButtonPressed = false
    @Binding var showTasbeehPage: Bool
    @Binding var showChainZikrButton: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                triggerSomeVibration(type: .success)
                chainButtonPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                chainButtonPressed = false
                sharedState.isDoingPostNamazZikr = true
                showTasbeehPage = true
//                sharedState.showingOtherPages = true
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
                Text("post salah zikr?")
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .foregroundColor(.primary)
            }
            .frame(width: 150, height: 50)
            .shadow(radius: 10)
            .scaleEffect(chainButtonPressed ? 0.95 : 1.0)
        }
        .padding()
        .offset(y: showChainZikrButton ? 50 : 0)
        .opacity(showChainZikrButton ? 1 : 0)
        .disabled(!showChainZikrButton)
        .animation(.easeInOut, value: showChainZikrButton)
    }
}




func showTemporaryMessage(
    workItem: inout DispatchWorkItem?,
    boolToShow: Binding<Bool>,
    delay: Int = 2
) {
    // Cancel any existing dismissal timer
    workItem?.cancel()
    
    // Show the message with animation
    withAnimation {
        boolToShow.wrappedValue = true
    }
    
    // Schedule a new dismissal timer
    let newWorkItem = DispatchWorkItem {
        withAnimation {
            boolToShow.wrappedValue = false
        }
        print("just cancelled")
    }
    
    // Schedule the new work item after the specified delay
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: newWorkItem)
    
    // Update the workItem reference
    workItem = newWorkItem
}

