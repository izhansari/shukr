import SwiftUI

struct ShukrTimer: View {
    
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
            
        VStack {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.2), lineWidth: 20)
                
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
                    .stroke(.green.opacity(0.4), style: StrokeStyle(
                        lineWidth: 20,
                        lineCap: .round,
                        lineJoin: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: currentTime)
                
                VStack {
                    Text("timer:")
                        .font(.largeTitle)
                    Text(displayedTime)
                        .font(.system(size: 70))
                        .bold()
                }
                .fontDesign(.rounded)
            }
            .padding(.horizontal, 50)
            
            Spacer()
            
            if(!timerIsActive){
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(1..<60) { minute in
                        Text("\(minute)m").tag(minute)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(width: 100)
                .padding()
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
                        .foregroundStyle(timerIsActive ? .red.opacity(0.5) : .green.opacity(0.5))
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
    ShukrTimer()
}



//Old
/*
//import SwiftUI
//
//struct ShukrTimer: View {
//    
//    @AppStorage("streak") var streak = 0
//    @State private var timeRemaining = 60
//    @State private var timerIsActive = false
//    @State private var timer: Timer? = nil
//    @State private var selectedMinutes = 1
//    
//    
//
//    var formattedTime: String {
//        if timerIsActive {
//            let minutes = timeRemaining / 60
//            let seconds = timeRemaining % 60
//            if timeRemaining >= 60 {
//                return seconds > 0 ? "\(minutes + 1)m" : "\(minutes)m"
//            } else {
//                return "\(seconds)s"
//            }
//        } else {
//            return "\(selectedMinutes)m"
//        }
//    }
//
//    var body: some View {
//            
//        VStack {
//            Spacer()
//            
//            ZStack {
//                Circle()
//                    .stroke(.gray.opacity(0.2), lineWidth: 20)
//                
//                //counting down
////                Circle()
////                    .trim(from: 0, to: timerIsActive ? CGFloat(timeRemaining) / CGFloat(selectedMinutes * 60) :  1.0)
////                    .stroke(.green.opacity(0.4), style: StrokeStyle(
////                        lineWidth: 20,
////                        lineCap: .round,
////                        lineJoin: .round))
////                    .rotationEffect(.degrees(-90))
//                
//                //counting up
//                Circle()
//                    .trim(from: 0, to: timerIsActive ? CGFloat(selectedMinutes * 60 - timeRemaining) / CGFloat(selectedMinutes * 60) :  0.0)
//                    .stroke(.green.opacity(0.4), style: StrokeStyle(
//                        lineWidth: 20,
//                        lineCap: .round,
//                        lineJoin: .round))
//                    .rotationEffect(.degrees(-90))
//                
//                VStack {
//                    Text("timer:")
//                        .font(.largeTitle)
//                    Text(formattedTime)
//                        .font(.system(size: 70))
//                        .bold()
//                }
//                .fontDesign(.rounded)
//            }
//            .padding(.horizontal, 50)
//            
//            Spacer()
//            
//            Picker("Minutes", selection: $selectedMinutes) {
//                ForEach(1..<60) { minute in
//                    Text("\(minute)m").tag(minute)
//                }
//            }
//            .pickerStyle(WheelPickerStyle())
//            .frame(width: 100)
//            .padding()
//            
//            Button(action: {
//                if timerIsActive {
//                    // Stop the timer
//                    timer?.invalidate()
//                    timer = nil
//                    timerIsActive = false
//                } else {
//                    // Start the timer
//                    timerIsActive = true
//                    timeRemaining = selectedMinutes * 60
//                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//                        if timeRemaining > 0 {
//                            timeRemaining -= 1
//                        } else {
//                            // Timer has reached zero
//                            timer?.invalidate()
//                            timer = nil
//                            timerIsActive = false
//                            streak += 1 // Increment the streak
//                        }
//                    }
//                }
//            }, label: {
//                ZStack {
//                    RoundedRectangle(cornerRadius: 20)
//                        .foregroundStyle(.gray.opacity(0.2))
//                    RoundedRectangle(cornerRadius: 20)
//                        .foregroundStyle(timerIsActive ? .red.opacity(0.5) : .green.opacity(0.5))
//                    Text(timerIsActive ? "stop" : "start")
//                        .foregroundStyle(.white)
//                        .font(.title3)
//                        .fontDesign(.rounded)
//                }
//                .frame(height: 50)
//            })
//            .padding()
//        }
//    }
//}
//
//#Preview {
//    ShukrTimer()
//}
*/
