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
    
    // State properties
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    @State private var selectedMinutes = 1
    @State private var startTime: Date? = nil
    @State private var currentTime = Date()
    @State private var endTime: Date? = nil
    @State private var isHolding = false
    
    let feedbackTypes: [UINotificationFeedbackGenerator.FeedbackType] = [.success, .error, .warning]
    @State private var feedbackIndex = 0
    @State private var vibrationChoice: HapticFeedbackType = .light
    
    @State private var autoStop = true
    @State private var vibrateToggle = true
    @State private var modeToggle = false

    
    private enum HapticFeedbackType: String, CaseIterable, Identifiable {
        case light = "Light"
        case medium = "Medium"
        case heavy = "Heavy"
        case soft = "Soft"
        case rigid = "Rigid"
        case success = "Success"
        case warning = "Warning"
        case error = "Error"
        case vibrate = "Vibrate"
        
        var id: String { self.rawValue }
    }

    
    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                ZStack {
                    CircularProgressView(progress: timerProgress())
                        .contentShape(Circle()) // Only the circle is tappable
                        .onTapGesture {
                            if timerIsActive {
                                decrementTasbeeh()
                            }
                        }
                        .onLongPressGesture(minimumDuration: 2) { _ in
                        } perform: {
                            if timerIsActive {
                                resetTasbeeh()
                            }
                        }
                    
                    if timerIsActive {
                        TasbeehCountView(tasbeeh: tasbeeh)
                    } else {
                        Picker("Minutes", selection: $selectedMinutes) {
                            ForEach(1..<60) { minute in
                                Text("\(minute)m").tag(minute)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(width: 100)
                        .padding()
                    }
                }
                .padding(.horizontal)
            }
            
            // Floating Start/Stop Button
            VStack {
                Spacer()
                
//                Picker("vibration type", selection: $vibrationChoice) {
//                    ForEach(HapticFeedbackType.allCases) { type in
//                        Text(type.rawValue).tag(type)
//                    }
//                }
//                .pickerStyle(.palette)
                
                
                if(!timerIsActive){
                    HStack{
                        Toggle(autoStop ? "✓ AutoStop":"✗ AutoStop", isOn: $autoStop)
                            .toggleStyle(.button)
                            .tint(.mint)

                        Toggle(vibrateToggle ? "✓ Vibrate":"✗ Vibrate", isOn: $vibrateToggle)
                            .toggleStyle(.button)
                            .tint(.yellow)
                            .onChange(of: vibrateToggle) { _, newValue in
                                if newValue {
                                    // Trigger vibration when the toggle is turned on
                                    triggerSomeVibration(type: .heavy)
                                }
                            }

                        Toggle(modeToggle ? "🌙":"☀️", isOn: $modeToggle)
                            .toggleStyle(.button)
                            .tint(.white)
                    }
                }


                
                //start button at the bottom
                if(!timerIsActive || currentTime >= endTime ?? Date()){ // YO YO YO I JUST ADDED THIS BUT ITLL NEVER HIT CUZ WE STOPTIMER WHEN SECOND CONDITION IS MET... NVM i added autostop toggle.
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
                        .animation(isHolding ? .easeInOut(duration: 2) : .easeOut(duration: 0.5), value: isHolding)
                }
            }
        }
        .frame(maxWidth: .infinity) // makes the whole thing tappable. otherwises tappable area shrinks to width of CircularProgressView
        .background(
            Color.clear // Makes the background tappable
                .contentShape(Rectangle())
                .onTapGesture {
                    if timerIsActive {
                        incrementTasbeeh()
                    }
                }
                .onLongPressGesture(minimumDuration: 2.5) { isPressing in
                    isHolding = isPressing
                } perform: {
                    if timerIsActive {
                        stopTimer()
                    }
                    isHolding = false
                }
        )
        .onAppear(perform: setupTimer)
        .onDisappear(perform: stopTimer)
        .preferredColorScheme(modeToggle ? .dark : .light)
    }
    
    private func toggleTimer() {
        if timerIsActive {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        timerIsActive = true
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: selectedMinutes, to: startTime!)
        triggerSomeVibration(type: .success)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            withAnimation {
                currentTime = Date()
            }
            if let endTime = endTime, currentTime >= endTime {
                if(autoStop){
                    stopTimer()
                    streak += 1 // Increment the streak
                }
            }
        }
    }
    
    private func timerProgress() -> CGFloat {
        if let startTime = startTime, let endTime = endTime {
            let totalTime = endTime.timeIntervalSince(startTime)
            let elapsedTime = currentTime.timeIntervalSince(startTime)
            return CGFloat(elapsedTime / totalTime)
        }
        return 0.0
    }
    
    private func setupTimer() {
        currentTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        triggerSomeVibration(type: .vibrate)
        timer = nil
        timerIsActive = false
        endTime = nil
    }
    
    private func incrementTasbeeh() {
        triggerSomeVibration(type: .light)
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        onFinishTasbeeh()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func onFinishTasbeeh(){
        if(tasbeeh % 100 == 0 && tasbeeh != 0){
            triggerSomeVibration(type: .heavy)
        }
    }
    
    private func decrementTasbeeh() {
        triggerSomeVibration(type: .rigid)
        tasbeeh = max(tasbeeh - 1, 0) // Adjust minimum value as needed
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func resetTasbeeh() {
        triggerSomeVibration(type: .error)
        tasbeeh = 0
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func triggerSomeVibration(type: HapticFeedbackType) {
        if(vibrateToggle){
            switch type {
            case .light:
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                
            case .medium:
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
            case .heavy:
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            
            case .soft:
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.impactOccurred()
                
            case .rigid:
                let generator = UIImpactFeedbackGenerator(style: .rigid)
                generator.impactOccurred()
                
            case .success:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
            case .warning:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                
            case .error:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                
            case .vibrate:
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }
    
    // Subviews integrated into CombinedView
    struct CircularProgressView: View {
        let progress: CGFloat
        
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
//                    .transition(.scale) // Built-in slide transition
//                    .animation(.snappy, value: tasbeeh) // Spring animation for smoothness
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
 get rid of hold down functions... i dont like em.
 
 insteam when you hold down, it shows the settings
 
 - night mode
 - vibrations on/off
 - shows time passed
 - reset count button
 - shows presses/min
 - stop button at bottom. slide to stop early...?
 */
