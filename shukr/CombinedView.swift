import SwiftUI
import WidgetKit
import SwiftData

struct CombinedView: View {
    
    @AppStorage("count", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var tasbeeh: Int = 10
    @AppStorage("streak") var streak = 0
    @State private var timerIsActive = false
    @State private var timer: Timer? = nil
    @State private var selectedMinutes = 1
    @State private var startTime: Date? = nil
    @State private var currentTime = Date()
    @State private var endTime: Date? = nil

    var displayedTime: String {
        return "\(selectedMinutes)m"
    }
    
    var body: some View {
        VStack(spacing: 40) {
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
                
                if timerIsActive {
                    Circle()
                        .trim(from: 0, to: {
                            if let startTime = startTime, let endTime = endTime {
                                let totalTime = endTime.timeIntervalSince(startTime)
                                let elapsedTime = currentTime.timeIntervalSince(startTime)
                                return CGFloat(elapsedTime / totalTime)
                            } else {
                                return 0.0
                            }
                        }())
                        .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .animation(.spring(), value: currentTime)
                    
                    ZStack {
                        // The circles beneath the text
                        HStack(spacing: 5) {
                            let circlesCount = tasbeeh / 100
                            ForEach(0..<circlesCount, id: \.self) { _ in
                                Circle()
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .offset(y: 40) // Position the circles below the text

                        // The centered text
                        Text("\(tasbeeh % 100)")
                            .font(.largeTitle)
                            .bold()
                    }
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
            
            HStack(spacing: 60) {
                if timerIsActive {
                    Button(action: {
                        tasbeeh = max(tasbeeh - 1, 0)
                        WidgetCenter.shared.reloadAllTimelines()
                    }, label: {
                        Image(systemName: "minus").font(.title)
                    })
                    
                    Button(action: {
                        tasbeeh = min(tasbeeh + 1, 10000) // Adjust maximum value as needed
                        WidgetCenter.shared.reloadAllTimelines()
                    }, label: {
                        Image(systemName: "plus").font(.title)
                    })
                }
            }
            
            Button(action: {
                if timerIsActive {
                    // Stop the timer
                    timer?.invalidate()
                    timer = nil
                    timerIsActive = false
                    endTime = nil
                } else {
                    // Start the timer
                    timerIsActive = true
                    startTime = Date()
                    endTime = Calendar.current.date(byAdding: .minute, value: selectedMinutes, to: startTime!)
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        withAnimation {
                            currentTime = Date()
                        }
                        if let endTime = endTime, currentTime >= endTime {
                            // Timer has reached zero
                            timer?.invalidate()
                            timer = nil
                            timerIsActive = false
                            streak += 1 // Increment the streak
                        }
                    }
                }
            }, label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(timerIsActive ? .black.opacity(0.5) : .blue.opacity(0.5))
                    Text(timerIsActive ? "stop" : "start")
                        .foregroundStyle(.white)
                        .font(.title3)
                        .fontDesign(.rounded)
                }
                .frame(height: 50)
            })
            .padding()
        }
        .onAppear {
            currentTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                currentTime = Date()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

#Preview {
    CombinedView()
        .modelContainer(for: Item.self, inMemory: true)
}
