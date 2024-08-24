import SwiftUI
import WidgetKit
import SwiftData

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
    
    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                ZStack {
                    CircularProgressView(progress: timerProgress())
                        .contentShape(Circle()) // Only the circle is tappable
                    
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
                
                if(!timerIsActive){
                    Button(action: toggleTimer, label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .foregroundStyle(.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 20)
                                .foregroundStyle(.blue.opacity(0.5))
                            Text("start")
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
                    Text("Hold to stop the timer...")
                        .font(.headline)
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
                .onLongPressGesture(minimumDuration: 3) { isPressing in
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            withAnimation {
                currentTime = Date()
            }
            if let endTime = endTime, currentTime >= endTime {
                stopTimer()
                streak += 1 // Increment the streak
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerIsActive = false
        endTime = nil
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
    
    private func incrementTasbeeh() {
        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
        WidgetCenter.shared.reloadAllTimelines()
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
            }
        }
    }
}

#Preview {
    CombinedView()
        .modelContainer(for: Item.self, inMemory: true)
}
