//import SwiftUI
//
//struct PulseCircleView: View {
//    @State private var isAnimating = false
//    @Environment(\.colorScheme) var colorScheme
//    
//    let progress: Double
//    
//    // Helper computed properties
//    private var pulseRate: Double {
//        if progress > 0.5 { return 1.5 }
//        else if progress > 0.25 { return 1.0 }
//        else { return 0.5 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else { return .red }
//    }
//    
//    var body: some View {
//        ZStack {
//            // Main circle
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress circle
//            Circle()
//                .trim(from: 0, to: progress)
//                .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                .frame(width: 200, height: 200)
//                .rotationEffect(.degrees(-90))
//                .foregroundColor(progressColor)
//            
//            // Inner gradient circle
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
//            // Pulsing circle
//            Circle()
//                .stroke(lineWidth: 10)
//                .frame(width: 224, height: 224)
//                .scaleEffect(isAnimating ? 1.1 : 1)
//                .opacity(isAnimating ? 0 : 0.7)
//                .foregroundStyle(colorScheme == .dark ? progressColor : progressColor.opacity(0.7))
//                .animation(
//                    Animation.easeOut(duration: pulseRate)
//                        .repeatForever(autoreverses: false),
//                    value: isAnimating
//                )
//        }
//        .onAppear { isAnimating = true }
//    }
//}
//
//// Preview provider
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack(spacing: 40) {
//            PulseCircleView(progress: 0.88) // Green, slow pulse
//            PulseCircleView(progress: 0.35) // Yellow, medium pulse
//            PulseCircleView(progress: 0.15) // Red, fast pulse
//        }
//    }
//}


//import SwiftUI
//
//struct PulseCircleView: View {
//    @State private var isAnimating = false
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    let progress: Double
//    
//    // Add a computed property to determine the zone (0: red, 1: yellow, 2: green)
//    private var progressZone: Int {
//        if progress > 0.5 { return 2 }      // Green zone
//        else if progress > 0.25 { return 1 } // Yellow zone
//        else { return 0 }                    // Red zone
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.5 }
//        else { return 1 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else { return .red }
//    }
//    
//    private func startPulseAnimation() {
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Initial pulse
//        triggerPulse()
//        
//        // Create new timer
//        timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//            triggerPulse()
//        }
//        
//        print("Started new timer with rate: \(pulseRate)s in zone: \(progressZone)")
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        // Trigger haptic
//        triggerSomeVibration(type: .light)
//        print("💫 Pulse at \(Date().formatted(date: .omitted, time: .standard)) - Rate: \(pulseRate)s - ProgressZone: \(Int(progressZone))")
//        
//        // Reset for next pulse
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    var body: some View {
//        ZStack {
//            
//            // Main circle
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress circle
//            Circle()
//                .trim(from: 0, to: progress)
//                .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                .frame(width: 200, height: 200)
//                .rotationEffect(.degrees(-90))
//                .foregroundColor(progressColor)
//            
//            // Inner gradient circle
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
//            
//            // Pulsing circle
//            Circle()
//                .trim(from: 0, to: progress)
//                .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round))
////                .stroke(lineWidth: 10)
//                .frame(width: 224, height: 224)
//                .rotationEffect(.degrees(-90))
//                .scaleEffect(isAnimating ? 1.1 : 1)
//                .opacity(isAnimating ? -0.05 : 0.7)
//                .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//
//            
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//        }
//        .onChange(of: progressZone) { _, new in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//        }
//    }
//}
//
//// Preview provider
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewWrapper()
//    }
//}
//
//// Preview wrapper to handle state
//private struct PreviewWrapper: View {
//    @State private var progress: Double = 0.8
//    
//    var body: some View {
//        VStack(spacing: 40) {
//            PulseCircleView(progress: progress)
//            
//            // Slider to control progress
//            Slider(value: $progress, in: 0...1) {
//                Text("Progress")
//            } minimumValueLabel: {
//                Text("0%")
//            } maximumValueLabel: {
//                Text("100%")
//            }
//            .padding()
//            
//            // Display current progress value
//            Text("Progress: \(Int(progress * 100))%")
//                .monospacedDigit()
//        }
//        .padding()
//    }
//}


// umm this just has some stupid prints in it but otherwise shes good:
//import SwiftUI
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        let prog = min(max(elapsed / totalDuration, 0), 1)
//        return prog
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.5 }
//        else { return 0.75 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .green}
//    }
//    
//    private func startPulseAnimation() {
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .light)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    var body: some View {
//        ZStack {
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(progressColor)
//                    .animation(.smooth, value: progress) // Add smooth animation
//                    .animation(.smooth, value: progressColor) // Smooth color transitions
//            }
//            
//            // Inner gradient circle
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
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.1 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Inner content
//            VStack {
//                HStack {
//                    Image(systemName: iconName(for: prayer.name))
////                        .font(.title2)
//                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//////                        .fontWeight(.thin)
//////                        .fontDesign(.rounded)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                    Text(prayer.name)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .font(.title2)
////                        .fontWeight(.bold)
////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                }
//                .padding(.bottom, 5)
//                
//                if isCurrentPrayer {
//                    Text(timeLeftString)
////                        .font(.headline)
////                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                    Button(action: toggleCompletion) {
////                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
////                            .font(.title)
////                            .foregroundColor(prayer.isCompleted ? .green : .gray)
////                    }
////                    .padding(.top, 10)
//                } else if isUpcomingPrayer{
//                    Text(showTimeUntilText ? formatTimeWithAMPM(prayer.startTime) : timeUntilStartString)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .onTapGesture {
//                            triggerSomeVibration(type: .light)
//                            showTimeUntilText.toggle()
//                        }
//                }
//                
//                if isMissedPrayer {
//                    Text("Missed")
////                        .font(.headline)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .foregroundColor(.gray)
//                }
//            }
//        }
//        .onAppear {
//            startPulseAnimation()
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        // .onReceive(timeUpdateTimer) { time in
//        //     currentTime = time
//        // }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
//            let oldProgress = progress
//            let oldTime = currentTime
//            currentTime = newTime
//            
//            print("""
//                \n--- Timer Update ---
//                Old Time: \(formatTime(oldTime))
//                New Time: \(formatTime(newTime))
//                Time Diff: \(newTime.timeIntervalSince(oldTime))s
//                Old Progress: \(oldProgress)
//                New Progress: \(progress)
//                Progress Diff: \(progress - oldProgress)
//                Prayer: \(prayer.name)
//                Start: \(formatTime(prayer.startTime))
//                End: \(formatTime(prayer.endTime))
//                ----------------
//                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//


//woah DisplayLink. This thing syncs with refresh rate. perfect and amazing omg... "Taking pics every second vs take a video"
//import SwiftUI
//import QuartzCore
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.5 }
//        else { return 0.75 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .green}
//    }
//    
//    private func startPulseAnimation() {
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .light)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    var body: some View {
//        ZStack {
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .square))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(progressColor)
//                    .animation(.smooth, value: progress) // Add smooth animation
//                    .animation(.smooth, value: progressColor) // Smooth color transitions
//            }
//            
//            // Inner gradient circle
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
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Inner content
//            VStack {
//                HStack {
//                    Image(systemName: iconName(for: prayer.name))
////                        .font(.title2)
//                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//////                        .fontWeight(.thin)
//////                        .fontDesign(.rounded)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                    Text(prayer.name)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .font(.title2)
////                        .fontWeight(.bold)
////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                }
//                .padding(.bottom, 5)
//                
//                if isCurrentPrayer {
//                    Text(timeLeftString)
////                        .font(.headline)
////                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                    Button(action: toggleCompletion) {
////                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
////                            .font(.title)
////                            .foregroundColor(prayer.isCompleted ? .green : .gray)
////                    }
////                    .padding(.top, 10)
//                } else if isUpcomingPrayer{
//                    Text(showTimeUntilText ? formatTimeWithAMPM(prayer.startTime) : timeUntilStartString)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .onTapGesture {
//                            triggerSomeVibration(type: .light)
//                            showTimeUntilText.toggle()
//                        }
//                }
//                
//                if isMissedPrayer {
//                    Text("Missed")
////                        .font(.headline)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .foregroundColor(.gray)
//                }
//            }
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
//            let oldProgress = progress
//            let oldTime = currentTime
//            currentTime = newTime
//            
//            print("""
//                \n--- Timer Update ---
//                Old Time: \(formatTime(oldTime))
//                New Time: \(formatTime(newTime))
//                Time Diff: \(newTime.timeIntervalSince(oldTime))s
//                Old Progress: \(oldProgress)
//                New Progress: \(progress)
//                Progress Diff: \(progress - oldProgress)
//                Prayer: \(prayer.name)
//                Start: \(formatTime(prayer.startTime))
//                End: \(formatTime(prayer.endTime))
//                ----------------
//                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//


// Good! Version right before starting salah tracker
//import SwiftUI
//import QuartzCore
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = false  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .light)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        return qiblaDirection - locationManager.compassHeading
//    }
//    
//    var body: some View {
//        ZStack {
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0.01, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundColor(progressColor)
//                    .foregroundColor(.white.opacity(0.85))
//                    .animation(.smooth, value: progress) // Add smooth animation
//                    .animation(.smooth, value: progressColor) // Smooth color transitions
//            }
//            
//            // Inner gradient circle
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
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
////                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Inner content
//            ZStack {
//                
//                HStack {
//                    Image(systemName: iconName(for: prayer.name))
////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                        .foregroundColor(isMissedPrayer ? .gray : .primary)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                    Text(prayer.name)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .font(.title2)
////                        .fontWeight(.bold)
////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                }
//                
//                VStack{
////                    Spacer(minLength: 5)
//                    if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showEndTime = true
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                    showEndTime = false
//                                }
//                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showTimeUntilText.toggle()
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
//                .padding(.top, 70)
//                
//            }
//            
//            // Add chevron at the top
//            VStack{
//                Image(systemName: "arrow.up")
//                    .font(.title3)
//                    .foregroundColor(.primary)
//                    .opacity(abs(calculateQiblaDirection()) <= 10 ? 1 : 0.5)
//                Circle()
//                    .fill(Color.primary)
//                    .frame(width: 6, height: 6)
//                    .opacity(abs(calculateQiblaDirection()) <= 10 ? 1 : 0)
//            }
//                .offset(y: -60) // Position just outside the circle
//                .rotationEffect(Angle(degrees: calculateQiblaDirection()))
//                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
//            let oldProgress = progress
//            let oldTime = currentTime
//            currentTime = newTime
//            
//            print("""
//                \n--- Timer Update ---
//                Old Time: \(formatTime(oldTime))
//                New Time: \(formatTime(newTime))
//                Time Diff: \(newTime.timeIntervalSince(oldTime))s
//                Old Progress: \(oldProgress)
//                New Progress: \(progress)
//                Progress Diff: \(progress - oldProgress)
//                Prayer: \(prayer.name)
//                Start: \(formatTime(prayer.startTime))
//                End: \(formatTime(prayer.endTime))
//                ----------------
//                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//


// cool so tracker works but not saving to the struct or marking as completed. Edge case of tracking while salah ends needs to be accounted for.
//import SwiftUI
//import QuartzCore
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = false  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .light)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        return qiblaDirection - locationManager.compassHeading
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    var body: some View {
//        ZStack {
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Show completed prayer arcs
//            ForEach(completedPrayerArcs.indices, id: \.self) { index in
//                Circle()
//                    .trim(from: completedPrayerArcs[index].startProgress,
//                          to: completedPrayerArcs[index].endProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(1))
//                    .shadow(color: .black.opacity(colorScheme == .dark ? 1 : 0.1), radius: 4, x: 0, y: 0)
//            }
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0.01, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundColor(progressColor)
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
//                    .animation(.smooth, value: progress) // Add smooth animation
//                    .animation(.smooth, value: progressColor) // Smooth color transitions
//            }
//            
//            // Inner gradient circle
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
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
////                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Inner content
//            ZStack {
//                
//                HStack {
//                    Image(systemName: iconName(for: prayer.name))
////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                        .foregroundColor(isMissedPrayer ? .gray : .primary)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                    Text(prayer.name)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .font(.title2)
////                        .fontWeight(.bold)
////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                }
//                
//                VStack{
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showEndTime = true
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                    showEndTime = false
//                                }
//                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showTimeUntilText.toggle()
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
//                .padding(.top, 70)
//                
//            }
//            
//            // Add chevron at the top
//            VStack{
//                Image(systemName: "arrow.up")
//                    .font(.title3)
//                    .foregroundColor(.primary)
//                    .opacity(abs(calculateQiblaDirection()) <= 10 ? 1 : 0.5)
//                Circle()
//                    .fill(Color.primary)
//                    .frame(width: 6, height: 6)
//                    .opacity(abs(calculateQiblaDirection()) <= 10 ? 1 : 0)
//            }
//                .offset(y: -60) // Position just outside the circle
//                .rotationEffect(Angle(degrees: calculateQiblaDirection()))
//                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//            
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .medium)
////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            showEndTime.toggle()
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
//            let oldProgress = progress
//            let oldTime = currentTime
//            currentTime = newTime
//            
//            print("""
//                \n--- Timer Update ---
//                Old Time: \(formatTime(oldTime))
//                New Time: \(formatTime(newTime))
//                Time Diff: \(newTime.timeIntervalSince(oldTime))s
//                Old Progress: \(oldProgress)
//                New Progress: \(progress)
//                Progress Diff: \(progress - oldProgress)
//                Prayer: \(prayer.name)
//                Start: \(formatTime(prayer.startTime))
//                End: \(formatTime(prayer.endTime))
//                ----------------
//                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//


// before trying to do the custom linecap circles:
//import SwiftUI
//import QuartzCore
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = false  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else if isUpcomingPrayer {return .white}
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .light)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - locationManager.compassHeading
//        
//        return returnVal
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    var body: some View {
//        ZStack {
//            
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
////                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Show completed prayer arcs
//            ForEach(completedPrayerArcs.indices, id: \.self) { index in
//                Circle()
//                    .trim(from: completedPrayerArcs[index].startProgress,
//                          to: completedPrayerArcs[index].endProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(1))
//                    .shadow(color: .black.opacity(colorScheme == .dark ? 1 : 0.1), radius: 4, x: 0, y: 0)
//            }
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
//                    .trim(from: 0.01, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundColor(progressColor)
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
//                    .animation(.smooth, value: progress) // Add smooth animation
//                    .animation(.smooth, value: progressColor) // Smooth color transitions
//            }
//            
//            // Inner gradient circle
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
//
//            
//            // Inner content
//            ZStack {
//                
//                HStack {
//                    Image(systemName: iconName(for: prayer.name))
////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                        .foregroundColor(isMissedPrayer ? .gray : .primary)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                    Text(prayer.name)
//                        .font(.title)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
////                        .font(.title2)
////                        .fontWeight(.bold)
////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                }
//                
//                VStack{
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showEndTime = true
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                    showEndTime = false
//                                }
//                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                showTimeUntilText.toggle()
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
//                .padding(.top, 70)
//                
//            }
//            
//            
//            ZStack {
//                let qiblaAlignmentThreshold = 2.5
//                let isAligned = abs(calculateQiblaDirection()) <= qiblaAlignmentThreshold
//                
//                VStack {
//                    Image(systemName: "chevron.up")
//                    Image(systemName: "suit.diamond"/* "chevron.up"*/)
//                        .opacity(0.0)
//                }
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .opacity(isAligned ? 0 : 0.5)
//                .offset(y: -70)
//                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//                .rotationEffect(Angle(degrees: calculateQiblaDirection()))
//                
//                VStack {
//                    Image(systemName: "chevron.up")
//                    Image(systemName: "suit.diamond"/* "chevron.up"*/)
//                }
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .opacity(isAligned ? 0.5 : 0)
//                .offset(y: -70)
////                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//                .onChange(of: isAligned) { _, newIsAligned in
//                    if newIsAligned {
//                        triggerSomeVibration(type: .heavy)
//                    }
//                }
//            }
//            
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
////                        if !isAnimating{
//                            triggerSomeVibration(type: .medium)
////                            print("fjuihe")
////                        }
//////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            showEndTime.toggle()
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
////            let oldProgress = progress
////            let oldTime = currentTime
//            currentTime = newTime
//            
////            print("""
////                \n--- Timer Update ---
////                Old Time: \(formatTime(oldTime))
////                New Time: \(formatTime(newTime))
////                Time Diff: \(newTime.timeIntervalSince(oldTime))s
////                Old Progress: \(oldProgress)
////                New Progress: \(progress)
////                Progress Diff: \(progress - oldProgress)
////                Prayer: \(prayer.name)
////                Start: \(formatTime(prayer.startTime))
////                End: \(formatTime(prayer.endTime))
////                ----------------
////                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//



// gonna start implementing styles as choices to make coding easier. But heres what i got before that. Looks to be growing from left side. Use progressIndicatorDot so not perfect.
//import SwiftUI
//import QuartzCore
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = true  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else if isUpcomingPrayer {return .white}
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .medium)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - locationManager.compassHeading
//        
//        return returnVal
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    private var adjustedProgPerZone: Double {
//        // get the current progress
//        // get the current color
//        // if green, its an interval from 1 to 0.5 (0.5 of space). so progress may be 0.7. so show (0.7-0.5)/(0.5)
//        // if yellow, its an interval from 0.5 to 0.25 (0.25 of space). so progress may be 0.4. so show (0.4-0.25)/(0.25)
//        // if red, its an interval from 0.25 to 0 (0.25 of space). so progress may be 0.1. so show (0.1-0)/(0.25)
//        // so the formula is ( {progress} - {sum of intervals below} ) / ( {space of current interval} )
//        
//        let greenInterval = (1.0, 0.5)
//        let yellowInterval = (0.5, 0.25)
//        let redInterval = (0.25, 0.0)
//        
//        if progress >= greenInterval.1 {
//            return (progress - greenInterval.1) / (greenInterval.0 - greenInterval.1)
//        } else if progress >= yellowInterval.1 {
//            return (progress - yellowInterval.1) / (yellowInterval.0 - yellowInterval.1)
//        } else {
//            return (progress - redInterval.1) / (redInterval.0 - redInterval.1)
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    var body: some View {
//        ZStack {
//            
//            // Pulsing circle (only for current prayer)
//            if isCurrentPrayer {
//                Circle()
////                    .trim(from: 0, to: progress)
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else { // placeholder circle for upcoming and missed prayers so spacing is consistent
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Main circle (always visible)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(.gray.opacity(0.2))
////                .foregroundColor(Color("wheelColor"))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Show completed prayer arcs
//            ForEach(completedPrayerArcs.indices, id: \.self) { index in
//                Circle()
//                    .trim(from: completedPrayerArcs[index].startProgress,
//                          to: completedPrayerArcs[index].endProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(1))
//                    .shadow(color: .black.opacity(colorScheme == .dark ? 1 : 0.1), radius: 4, x: 0, y: 0)
//            }
//            
//            // Progress circle (only for current prayer)
//            if isCurrentPrayer {
//                CustomArc(progress: progress/*/adjustedprogress*/)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .butt)) // Use .butt for one side
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(0)) // Rotate clockwise by 90 degrees
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
////                    .foregroundStyle(progressColor)
//                    .overlay(
//                        Circle()
//                            .frame(width: 24, height: 24)
////                            .foregroundColor(.white)
//                            .foregroundStyle(progressColor)
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
//                            )
//                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2), y: 100 * sin(2 * .pi * progress - .pi / 2))
//                            .animation(.smooth, value: progress)
//                            .animation(.smooth, value: progressColor)
//                    )
//                    .animation(.smooth, value: progress)
//                    .animation(.smooth, value: progressColor)
//            }
//            
//            // Inner gradient circle
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
//
//            
//            // Inner content
//            ZStack {
//                
////                HStack {
////                    Image(systemName: iconName(for: prayer.name))
//////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
////                        .foregroundColor(isMissedPrayer ? .gray : .primary)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                    Text(prayer.name)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
//////                        .font(.title2)
//////                        .fontWeight(.bold)
//////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
////                }
//                
//                VStack{
//                    
//                    HStack {
//                        Image(systemName: iconName(for: prayer.name))
//    //                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                            .foregroundColor(isMissedPrayer ? .gray : .primary)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        Text(prayer.name)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//    //                        .font(.title2)
//    //                        .fontWeight(.bold)
//    //                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                    }
//                    
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
////                            .onTapGesture {
////                                triggerSomeVibration(type: .light)
////                                showEndTime = true
////                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
////                                    showEndTime = false
////                                }
////                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                withAnimation(.easeIn(duration: 0.2)) {
//                                    showTimeUntilText.toggle()
//                                }
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
////                .padding(.top, 70)
//                
//            }
//            
//            
//            ZStack {
//                let qiblaAlignmentThreshold = 3.5
//                let isAligned = abs(calculateQiblaDirection()) <= qiblaAlignmentThreshold
//                
//                VStack {
//                    Image(systemName: "chevron.up")
//                    Image(systemName: "suit.diamond"/* "chevron.up"*/)
//                        .opacity(0.0)
//                }
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .opacity(isAligned ? 0 : 0.5)
//                .offset(y: -70)
//                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//                .rotationEffect(Angle(degrees: calculateQiblaDirection()))
//                
//                VStack {
//                    Image(systemName: "chevron.up")
//                    Image(systemName: "suit.diamond"/* "chevron.up"*/)
//                }
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .opacity(isAligned ? 0.5 : 0)
//                .offset(y: -70)
//                .animation(.linear(duration: 0.1), value: locationManager.compassHeading)
//                .onChange(of: isAligned) { _, newIsAligned in
//                    if newIsAligned {
//                        triggerSomeVibration(type: .heavy)
//                    }
//                }
//            }
//            
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
////                        if !isAnimating{
//                            triggerSomeVibration(type: .medium)
////                            print("fjuihe")
////                        }
//////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            withAnimation(.easeIn(duration: 0.2)) {
//                                showEndTime = false
//                            }
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                withAnimation(.easeOut(duration: 0.2)) {
//                                    showEndTime = true
//                                }
//                            }
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
////            let oldProgress = progress
////            let oldTime = currentTime
//            currentTime = newTime
//            
////            print("""
////                \n--- Timer Update ---
////                Old Time: \(formatTime(oldTime))
////                New Time: \(formatTime(newTime))
////                Time Diff: \(newTime.timeIntervalSince(oldTime))s
////                Old Progress: \(oldProgress)
////                New Progress: \(progress)
////                Progress Diff: \(progress - oldProgress)
////                Prayer: \(prayer.name)
////                Start: \(formatTime(prayer.startTime))
////                End: \(formatTime(prayer.endTime))
////                ----------------
////                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//struct CustomArc: Shape {
//    var progress: Double
//
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        let startAngle = Angle(degrees: -90)
//        let endAngle = Angle(degrees: -90 + 360 * progress)
//
//        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
//                    radius: rect.width / 2,
//                    startAngle: startAngle,
//                    endAngle: endAngle,
//                    clockwise: false)
//        return path
//    }
//}
//


// got styles. Got the overlapping one. working on last one. Tryan get the closing animation down.
//import SwiftUI
//import QuartzCore
//// Add this line
//import Foundation  // QiblaSettings will be automatically available since it's in your project
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//// Add at the top level, before PulseCircleView
//enum RingStyleType {
//    case style1 // Original style
//    case style2 // New gradient style
//    case style3 // Clockwise gradient style
//}
//
//struct RingStyle1 {
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
//    var body: some View {
//        ZStack {
//            // Pulsing outer circle for current prayer
//            if isCurrentPrayer {
//                Circle()
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else {
//                // Placeholder circle to maintain size consistency
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Main colored ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Progress arc that changes size over time
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .butt))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(0))
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
//                    .overlay(
//                        // Small circle indicator at the end of the progress arc
//                        Circle()
//                            .frame(width: 24, height: 24)
//                            .foregroundStyle(progressColor)
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
//                            )
//                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2),
//                                   y: 100 * sin(2 * .pi * progress - .pi / 2))
//                            .animation(.smooth, value: progress)
//                            .animation(.smooth, value: progressColor)
//                    )
//                    .animation(.smooth, value: progress)
//                    .animation(.smooth, value: progressColor)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // Add Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//    }
//}
//
//struct RingStyle2 {
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
//                // Placeholder circle for non-current prayers
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//
//            // Base ring (background)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//
////                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress arc (only for current prayer)
//            if isCurrentPrayer {
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round,
//                        lineJoin: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .foregroundStyle(
//                        AngularGradient(
//                            gradient: Gradient(stops: [
//                                .init(color: progressColor.opacity(0.8), location: 0),
//                                .init(color: progressColor, location: progress)
//                            ]),
//                            center: .center,
//                            startAngle: .degrees(-90),
//                            endAngle: .degrees(-90 + (360 * progress))
//                        )
//                    )
//                    .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // White circle indicator at the top for Qibla
//            Circle()
//                .frame(width: 8, height: 8) // Adjust size as needed
//                .offset(y: -100) // Half of the ring's width (200/2) to position at top
//                .foregroundStyle(progressColor == .white ? .gray : .white) // Only show if Qibla is aligned
//                .opacity(isQiblaAligned ? 0.5 : 0) // Only show if Qibla is aligned
//
//        }
//    }
//}
//
//struct RingStyle3 {
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
//    // Add this computed property
//    private var isCompleting: Bool {
//        clockwiseProgress > 0.99
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
//                // Layer 1: Dynamic trailing background piece when progress > 0.1 (so he can be overlapped by the main progress arc)
//                if clockwiseProgress > 0.1 {
//                    Circle()
//                        .trim(from: 0, to: clockwiseProgress-0.05)
//                        .stroke(style: StrokeStyle(
//                            lineWidth: 24,
//                            lineCap: .round
//                        ))
//                        .frame(width: 200, height: 200)
//                        .rotationEffect(.degrees(-90))
//                        .foregroundStyle(progressColor)
//                }
//                
//                // Layer 2: Small shadow segment that follows the progress
//                Circle()
//                    .trim(from: max(clockwiseProgress - 0.08, 0), to: clockwiseProgress)
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
//                
//                // Layer 3: Main progress arc (adjusted when > 0.15 so he can move away from start and then overlap the background piece)
//                Circle()
//                    .trim(from: clockwiseProgress > 0.15 ? 0.1 : 0, to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
//
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
//            // Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//    }
//}
//
//
////struct RingStyle4Old {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    private var timeRemaining: TimeInterval {
////        prayer.endTime.timeIntervalSinceNow
////    }
////
////    private var isInFinalSeconds: Bool {
////        timeRemaining < 3
////    }
////
////    private var clockwiseProgress: Double {
////        1 - progress
////    }
////
////    private var startPoint: Double {
////        if isInFinalSeconds {
////            // Convert the remaining time to a 0-1 progress
////            let finalProgress = 1 - (timeRemaining / 3)
////
////            // Apply cubic-bezier easing for acceleration
////            let easedProgress = pow(finalProgress, 3) // Cubic easing
////            // or for even more dramatic acceleration:
////            // let easedProgress = pow(finalProgress, 4) // Quartic easing
////
////            // Calculate the start point position
////            return clockwiseProgress * easedProgress
////        }
////        return clockwiseProgress > 0.85 ? 0.25 : 0  // Changed from 0.75
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Only show overlap pieces when not in final seconds
////                if clockwiseProgress > 0.85 && !isInFinalSeconds {  // Changed from 0.75
////                    // Layer 1: Static background piece
////                    Circle()
////                        .trim(from: 0, to: 0.25)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////
////                    // Layer 2: Overlap effect piece
////                    Circle()
////                        .trim(from: 0.15, to: 0.3)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
////                }
////
////                // Main progress arc with animated start point
////                Circle()
////                    .trim(from: startPoint, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////
////                // Shadow segment
////                if !isInFinalSeconds {
////                    Circle()
////                        .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                        .opacity(clockwiseProgress)
////                }
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // White circle indicator at the top for Qibla
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////        .animation(.easeInOut(duration: 0.2), value: startPoint)
////    }
////}
//
//
////struct RingStyle3OldSimple {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    // Convert countdown progress to clockwise progress
////    private var clockwiseProgress: Double {
////        1 - progress // Invert the progress
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Layer 1: Small shadow segment that follows the progress
////                Circle()
////                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                    .opacity(clockwiseProgress)
////
////                // Layer 2: Main progress arc
////                Circle()
////                    .trim(from: 0, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // Qibla indicator
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////    }
////}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 2  // Add this line
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = true  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else if isUpcomingPrayer {return .white}
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .medium)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - locationManager.compassHeading
//        
//        return returnVal
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    private var adjustedProgPerZone: Double {
//        // get the current progress
//        // get the current color
//        // if green, its an interval from 1 to 0.5 (0.5 of space). so progress may be 0.7. so show (0.7-0.5)/(0.5)
//        // if yellow, its an interval from 0.5 to 0.25 (0.25 of space). so progress may be 0.4. so show (0.4-0.25)/(0.25)
//        // if red, its an interval from 0.25 to 0 (0.25 of space). so progress may be 0.1. so show (0.1-0)/(0.25)
//        // so the formula is ( {progress} - {sum of intervals below} ) / ( {space of current interval} )
//        
//        let greenInterval = (1.0, 0.5)
//        let yellowInterval = (0.5, 0.25)
//        let redInterval = (0.25, 0.0)
//        
//        if progress >= greenInterval.1 {
//            return (progress - greenInterval.1) / (greenInterval.0 - greenInterval.1)
//        } else if progress >= yellowInterval.1 {
//            return (progress - yellowInterval.1) / (yellowInterval.0 - yellowInterval.1)
//        } else {
//            return (progress - redInterval.1) / (redInterval.0 - redInterval.1)
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    // Add this property with other @State properties
//    // @State private var selectedRingStyleYoYo: Int = 1
//    
//    private func chooseRingStyle(style: Int) -> AnyView {
//        switch style {
//        case 1:
//            return AnyView(RingStyle1(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 2:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 3:
//            return AnyView(RingStyle3(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        default:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        }
//    }
//
//    
//    var body: some View {
//        ZStack {
//            
//            chooseRingStyle(style: selectedRingStyle)  // Use selectedRingStyle here
//
//            
//            // Inner content
//            ZStack {
//                
////                HStack {
////                    Image(systemName: iconName(for: prayer.name))
//////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
////                        .foregroundColor(isMissedPrayer ? .gray : .primary)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                    Text(prayer.name)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
//////                        .font(.title2)
//////                        .fontWeight(.bold)
//////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
////                }
//                
//                VStack{
//                    
//                    HStack {
//                        Image(systemName: iconName(for: prayer.name))
//    //                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                            .foregroundColor(isMissedPrayer ? .gray : .primary)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        Text(prayer.name)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//    //                        .font(.title2)
//    //                        .fontWeight(.bold)
//    //                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                    }
//                    
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
////                            .onTapGesture {
////                                triggerSomeVibration(type: .light)
////                                showEndTime = true
////                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
////                                    showEndTime = false
////                                }
////                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                withAnimation(.easeIn(duration: 0.2)) {
//                                    showTimeUntilText.toggle()
//                                }
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
////                .padding(.top, 70)
//                
//            }
//            
//            
//            ZStack {
////                let qiblaAlignmentThreshold = 3.5
//                let isAligned = abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//                
//                Image(systemName: "chevron.up")
//                    .font(.subheadline)
//                    .foregroundColor(.primary)
//                    .opacity(0.5)
//                    .offset(y: -70)
//                    .rotationEffect(Angle(degrees: isAligned ? 0 : calculateQiblaDirection()))
//                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: isAligned)
//                    .onChange(of: isAligned) { _, newIsAligned in
//                        if newIsAligned {
//                            triggerSomeVibration(type: .heavy)
//                        }
//                    }
//            }
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
////                        if !isAnimating{
//                            triggerSomeVibration(type: .medium)
////                            print("fjuihe")
////                        }
//////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            withAnimation(.easeIn(duration: 0.2)) {
//                                showEndTime = false
//                            }
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                withAnimation(.easeOut(duration: 0.2)) {
//                                    showEndTime = true
//                                }
//                            }
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
////            let oldProgress = progress
////            let oldTime = currentTime
//            currentTime = newTime
//            
////            print("""
////                \n--- Timer Update ---
////                Old Time: \(formatTime(oldTime))
////                New Time: \(formatTime(newTime))
////                Time Diff: \(newTime.timeIntervalSince(oldTime))s
////                Old Progress: \(oldProgress)
////                New Progress: \(progress)
////                Progress Diff: \(progress - oldProgress)
////                Prayer: \(prayer.name)
////                Start: \(formatTime(prayer.startTime))
////                End: \(formatTime(prayer.endTime))
////                ----------------
////                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//struct CustomArc: Shape {
//    var progress: Double
//
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        let startAngle = Angle(degrees: -90)
//        let endAngle = Angle(degrees: -90 + 360 * progress)
//
//        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
//                    radius: rect.width / 2,
//                    startAngle: startAngle,
//                    endAngle: endAngle,
//                    clockwise: false)
//        return path
//    }
//}
//
//
//
//
//
//
//
//
//
//
//
//
//


// I got ring style 5. but shadow tip animates seperately from others cuz in seperate zstack...
//import SwiftUI
//import QuartzCore
//// Add this line
//import Foundation  // QiblaSettings will be automatically available since it's in your project
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//// Add at the top level, before PulseCircleView
//enum RingStyleType {
//    case style1 // Original style
//    case style2 // New gradient style
//    case style3 // Clockwise gradient style
//    case style5 // New overlapping gradient style
//}
//
//struct RingStyle1 {
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
//    var body: some View {
//        ZStack {
//            // Pulsing outer circle for current prayer
//            if isCurrentPrayer {
//                Circle()
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else {
//                // Placeholder circle to maintain size consistency
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Main colored ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Progress arc that changes size over time
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .butt))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(0))
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
//                    .overlay(
//                        // Small circle indicator at the end of the progress arc
//                        Circle()
//                            .frame(width: 24, height: 24)
//                            .foregroundStyle(progressColor)
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
//                            )
//                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2),
//                                   y: 100 * sin(2 * .pi * progress - .pi / 2))
//                            .animation(.smooth, value: progress)
//                            .animation(.smooth, value: progressColor)
//                    )
//                    .animation(.smooth, value: progress)
//                    .animation(.smooth, value: progressColor)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // Add Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//    }
//}
//
//struct RingStyle2 {
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
//                // Placeholder circle for non-current prayers
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//
//            // Base ring (background)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//
////                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress arc (only for current prayer)
//            if isCurrentPrayer {
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round,
//                        lineJoin: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .foregroundStyle(
//                        AngularGradient(
//                            gradient: Gradient(stops: [
//                                .init(color: progressColor.opacity(0.8), location: 0),
//                                .init(color: progressColor, location: progress)
//                            ]),
//                            center: .center,
//                            startAngle: .degrees(-90),
//                            endAngle: .degrees(-90 + (360 * progress))
//                        )
//                    )
//                    .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // White circle indicator at the top for Qibla
//            Circle()
//                .frame(width: 8, height: 8) // Adjust size as needed
//                .offset(y: -100) // Half of the ring's width (200/2) to position at top
//                .foregroundStyle(progressColor == .white ? .gray : .white) // Only show if Qibla is aligned
//                .opacity(isQiblaAligned ? 0.5 : 0) // Only show if Qibla is aligned
//
//        }
//    }
//}
//
//struct RingStyle3 {
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
//    private var timeRemaining: TimeInterval {
//        prayer.endTime.timeIntervalSinceNow
//    }
//    
//    private var isInFinalSeconds: Bool {
//        timeRemaining < 4
//    }
//    
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    
//    private var finalAnimation: Double {
//        if isInFinalSeconds {
//            // Convert remaining time to 0-1 range with dramatic acceleration
//            let progress = 1 - (timeRemaining-1 / 3)
//            return pow(progress, 5) // Quartic easing for dramatic effect
//        }
//        return 0
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
//                // Layer 1: Dynamic trailing background piece
//                if clockwiseProgress > 0.1  {
//                    Circle()
//                        .trim(from: isInFinalSeconds ?
//                              max(clockwiseProgress * finalAnimation, 0) :
//                                0, to: isInFinalSeconds ?  1 : clockwiseProgress-0.05)
//                        .stroke(style: StrokeStyle(
//                            lineWidth: 24,
//                            lineCap: .round
//                        ))
//                        .frame(width: 200, height: 200)
//                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
//                        .foregroundStyle(isInFinalSeconds ? .blue.opacity(0.3) : progressColor)
//                }
//                
//                // Layer 2: Small shadow segment
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          max(clockwiseProgress - (0.08 * (1 - finalAnimation)), 0) :
//                          max(clockwiseProgress - 0.08, 0),
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
//                    .foregroundStyle(isInFinalSeconds ? .green.opacity(0.3) : progressColor)
//                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
//                    .opacity(clockwiseProgress)
//                
//                // Layer 3: Main progress arc
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          max(clockwiseProgress * finalAnimation, 0.1) :
//                          (clockwiseProgress > 0.15 ? 0.1 : 0),
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
//                    .foregroundStyle(isInFinalSeconds ? .orange.opacity(0.3) : progressColor)
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
//            // Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//        // .id(timeRemaining) // Forces view to update as time changes
//        // .animation(.easeOut(duration: 0.2), value: finalAnimation)
//    }
//}
//
//
////struct RingStyle4Old {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    private var timeRemaining: TimeInterval {
////        prayer.endTime.timeIntervalSinceNow
////    }
////
////    private var isInFinalSeconds: Bool {
////        timeRemaining < 3
////    }
////
////    private var clockwiseProgress: Double {
////        1 - progress
////    }
////
////    private var startPoint: Double {
////        if isInFinalSeconds {
////            // Convert the remaining time to a 0-1 progress
////            let finalProgress = 1 - (timeRemaining / 3)
////
////            // Apply cubic-bezier easing for acceleration
////            let easedProgress = pow(finalProgress, 3) // Cubic easing
////            // or for even more dramatic acceleration:
////            // let easedProgress = pow(finalProgress, 4) // Quartic easing
////
////            // Calculate the start point position
////            return clockwiseProgress * easedProgress
////        }
////        return clockwiseProgress > 0.85 ? 0.25 : 0  // Changed from 0.75
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Only show overlap pieces when not in final seconds
////                if clockwiseProgress > 0.85 && !isInFinalSeconds {  // Changed from 0.75
////                    // Layer 1: Static background piece
////                    Circle()
////                        .trim(from: 0, to: 0.25)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////
////                    // Layer 2: Overlap effect piece
////                    Circle()
////                        .trim(from: 0.15, to: 0.3)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
////                }
////
////                // Main progress arc with animated start point
////                Circle()
////                    .trim(from: startPoint, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////
////                // Shadow segment
////                if !isInFinalSeconds {
////                    Circle()
////                        .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                        .opacity(clockwiseProgress)
////                }
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // White circle indicator at the top for Qibla
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////        .animation(.easeInOut(duration: 0.2), value: startPoint)
////    }
////}
//
//
////struct RingStyle3OldSimple {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    // Convert countdown progress to clockwise progress
////    private var clockwiseProgress: Double {
////        1 - progress // Invert the progress
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Layer 1: Small shadow segment that follows the progress
////                Circle()
////                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                    .opacity(clockwiseProgress)
////
////                // Layer 2: Main progress arc
////                Circle()
////                    .trim(from: 0, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // Qibla indicator
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////    }
////}
//struct RingStyle5 {
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
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    
//    private var timeRemaining: TimeInterval {
//        prayer.endTime.timeIntervalSinceNow
//    }
//    
//    private var isInFinalSeconds: Bool {
//        timeRemaining < 3
//    }
//    
//    private var finalAnimation: Double {
//        if isInFinalSeconds {
//            let progress = 1 - (timeRemaining / 3)
//            return pow(progress, 5)
//        }
//        return 0
//    }
//    
//    private var ringTipShadowOffset: CGPoint {
//        let ringTipPosition = tipPosition(progress: clockwiseProgress, radius: 100) // 200/2 for radius
//        let shadowPosition = tipPosition(progress: clockwiseProgress + 0.0075, radius: 100)
//        return CGPoint(
//            x: shadowPosition.x - ringTipPosition.x,
//            y: shadowPosition.y - ringTipPosition.y
//        )
//    }
//    
//    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
//        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
//        return CGPoint(
//            x: radius * cos(progressAngle.radians),
//            y: radius * sin(progressAngle.radians)
//        )
//    }
//    
//    var body: some View {
//        ZStack {
//            // Outer pulsing circle
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
//            // Base ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Main progress arc
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          (clockwiseProgress * finalAnimation) : 0,
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(progressColor)
//                
//                // Tip shadow
//                Circle()
//                    .frame(width: 24, height: 24)
//                    .foregroundColor(progressColor)
//                    .offset(
//                        x: 100 * cos(2 * .pi * clockwiseProgress - .pi/2),
//                        y: 100 * sin(2 * .pi * clockwiseProgress - .pi/2)
//                    )
//                    .shadow(
//                        color: .black.opacity(0.3),
//                        radius: 2.5,
//                        x: ringTipShadowOffset.x,
//                        y: ringTipShadowOffset.y
//                    )
//                    .opacity(clockwiseProgress)
//            }
//            
//            // Inner gradient circle for depth
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
//        .animation(.easeOut(duration: 0.2), value: finalAnimation)
//    }
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 2  // Add this line
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = true  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else if isUpcomingPrayer {return .white}
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .medium)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - locationManager.compassHeading
//        
//        return returnVal
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    private var adjustedProgPerZone: Double {
//        // get the current progress
//        // get the current color
//        // if green, its an interval from 1 to 0.5 (0.5 of space). so progress may be 0.7. so show (0.7-0.5)/(0.5)
//        // if yellow, its an interval from 0.5 to 0.25 (0.25 of space). so progress may be 0.4. so show (0.4-0.25)/(0.25)
//        // if red, its an interval from 0.25 to 0 (0.25 of space). so progress may be 0.1. so show (0.1-0)/(0.25)
//        // so the formula is ( {progress} - {sum of intervals below} ) / ( {space of current interval} )
//        
//        let greenInterval = (1.0, 0.5)
//        let yellowInterval = (0.5, 0.25)
//        let redInterval = (0.25, 0.0)
//        
//        if progress >= greenInterval.1 {
//            return (progress - greenInterval.1) / (greenInterval.0 - greenInterval.1)
//        } else if progress >= yellowInterval.1 {
//            return (progress - yellowInterval.1) / (yellowInterval.0 - yellowInterval.1)
//        } else {
//            return (progress - redInterval.1) / (redInterval.0 - redInterval.1)
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    // Add this property with other @State properties
//    // @State private var selectedRingStyleYoYo: Int = 1
//    
//    private func chooseRingStyle(style: Int) -> AnyView {
//        switch style {
//        case 1:
//            return AnyView(RingStyle1(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 2:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 3:
//            return AnyView(RingStyle3(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 5:
//            return AnyView(RingStyle5(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        default:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        }
//    }
//
//    
//    var body: some View {
//        ZStack {
//            
//            chooseRingStyle(style: selectedRingStyle)  // Use selectedRingStyle here
//
//            
//            // Inner content
//            ZStack {
//                
////                HStack {
////                    Image(systemName: iconName(for: prayer.name))
//////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
////                        .foregroundColor(isMissedPrayer ? .gray : .primary)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                    Text(prayer.name)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
//////                        .font(.title2)
//////                        .fontWeight(.bold)
//////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
////                }
//                
//                VStack{
//                    
//                    HStack {
//                        Image(systemName: iconName(for: prayer.name))
//    //                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                            .foregroundColor(isMissedPrayer ? .gray : .primary)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        Text(prayer.name)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//    //                        .font(.title2)
//    //                        .fontWeight(.bold)
//    //                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                    }
//                    
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
////                            .onTapGesture {
////                                triggerSomeVibration(type: .light)
////                                showEndTime = true
////                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
////                                    showEndTime = false
////                                }
////                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                withAnimation(.easeIn(duration: 0.2)) {
//                                    showTimeUntilText.toggle()
//                                }
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
////                .padding(.top, 70)
//                
//            }
//            
//            
//            ZStack {
////                let qiblaAlignmentThreshold = 3.5
//                let isAligned = abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//                
//                Image(systemName: "chevron.up")
//                    .font(.subheadline)
//                    .foregroundColor(.primary)
//                    .opacity(0.5)
//                    .offset(y: -70)
//                    .rotationEffect(Angle(degrees: isAligned ? 0 : calculateQiblaDirection()))
//                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: isAligned)
//                    .onChange(of: isAligned) { _, newIsAligned in
//                        if newIsAligned {
//                            triggerSomeVibration(type: .heavy)
//                        }
//                    }
//            }
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
////                        if !isAnimating{
//                            triggerSomeVibration(type: .medium)
////                            print("fjuihe")
////                        }
//////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            withAnimation(.easeIn(duration: 0.2)) {
//                                showEndTime = false
//                            }
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                withAnimation(.easeOut(duration: 0.2)) {
//                                    showEndTime = true
//                                }
//                            }
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
////            let oldProgress = progress
////            let oldTime = currentTime
//            currentTime = newTime
//            
////            print("""
////                \n--- Timer Update ---
////                Old Time: \(formatTime(oldTime))
////                New Time: \(formatTime(newTime))
////                Time Diff: \(newTime.timeIntervalSince(oldTime))s
////                Old Progress: \(oldProgress)
////                New Progress: \(progress)
////                Progress Diff: \(progress - oldProgress)
////                Prayer: \(prayer.name)
////                Start: \(formatTime(prayer.startTime))
////                End: \(formatTime(prayer.endTime))
////                ----------------
////                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//struct CustomArc: Shape {
//    var progress: Double
//
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        let startAngle = Angle(degrees: -90)
//        let endAngle = Angle(degrees: -90 + 360 * progress)
//
//        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
//                    radius: rect.width / 2,
//                    startAngle: startAngle,
//                    endAngle: endAngle,
//                    clockwise: false)
//        return path
//    }
//}
//
//
//
//
//
//
//
//
//
//
//
//
//
//


// working on style6... almost there. just small issue where the shadow tip goes away at the end...
//import SwiftUI
//import QuartzCore
//// Add this line
//import Foundation  // QiblaSettings will be automatically available since it's in your project
//
//class DisplayLink: ObservableObject {
//    private var displayLink: CADisplayLink?
//    private var callback: ((Date) -> Void)?
//    
//    func start(callback: @escaping (Date) -> Void) {
//        self.callback = callback
//        displayLink = CADisplayLink(target: self, selector: #selector(update))
//        displayLink?.add(to: .main, forMode: .common)
//    }
//    
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//    
//    @objc private func update(displayLink: CADisplayLink) {
//        callback?(Date())
//    }
//}
//
//// Add this struct at the top level
//struct PrayerArc {
//    let startProgress: Double
//    let endProgress: Double
//}
//
//// Add at the top level, before PulseCircleView
//enum RingStyleType {
//    case style1 // Original style
//    case style2 // New gradient style
//    case style3 // Clockwise gradient style
//    case style5 // New overlapping gradient style
//}
//
//struct RingStyle1 {
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
//    var body: some View {
//        ZStack {
//            // Pulsing outer circle for current prayer
//            if isCurrentPrayer {
//                Circle()
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15, lineCap: .square))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: .white.opacity(1), radius: 10, x: 0, y: 0)
//            } else {
//                // Placeholder circle to maintain size consistency
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//            
//            // Main colored ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Progress arc that changes size over time
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .butt))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(0))
//                    .foregroundColor(.white.opacity(colorScheme == .dark ? progressColor == .yellow ? 0.9 : 0.75 : 0.85))
//                    .overlay(
//                        // Small circle indicator at the end of the progress arc
//                        Circle()
//                            .frame(width: 24, height: 24)
//                            .foregroundStyle(progressColor)
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
//                            )
//                            .offset(x: 100 * cos(2 * .pi * progress - .pi / 2),
//                                   y: 100 * sin(2 * .pi * progress - .pi / 2))
//                            .animation(.smooth, value: progress)
//                            .animation(.smooth, value: progressColor)
//                    )
//                    .animation(.smooth, value: progress)
//                    .animation(.smooth, value: progressColor)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // Add Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//    }
//}
//
//struct RingStyle2 {
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
//                // Placeholder circle for non-current prayers
//                Circle()
//                    .frame(width: 224, height: 224)
//                    .opacity(0)
//            }
//
//            // Base ring (background)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//
////                .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Progress arc (only for current prayer)
//            if isCurrentPrayer {
//                CustomArc(progress: progress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round,
//                        lineJoin: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .foregroundStyle(
//                        AngularGradient(
//                            gradient: Gradient(stops: [
//                                .init(color: progressColor.opacity(0.8), location: 0),
//                                .init(color: progressColor, location: progress)
//                            ]),
//                            center: .center,
//                            startAngle: .degrees(-90),
//                            endAngle: .degrees(-90 + (360 * progress))
//                        )
//                    )
//                    .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
//            }
//            
//            // Inner gradient circle for depth effect
//            Circle()
//                .stroke(lineWidth: 0.34)
//                .frame(width: 175, height: 175)
//                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//                .overlay {
//                    // Blurred inner circle border for additional depth
//                    Circle()
//                        .stroke(.black.opacity(0.1), lineWidth: 2)
//                        .blur(radius: 5)
//                        .mask {
//                            Circle()
//                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                        }
//                }
//            
//            // White circle indicator at the top for Qibla
//            Circle()
//                .frame(width: 8, height: 8) // Adjust size as needed
//                .offset(y: -100) // Half of the ring's width (200/2) to position at top
//                .foregroundStyle(progressColor == .white ? .gray : .white) // Only show if Qibla is aligned
//                .opacity(isQiblaAligned ? 0.5 : 0) // Only show if Qibla is aligned
//
//        }
//    }
//}
//
//struct RingStyle3 {
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
//    private var timeRemaining: TimeInterval {
//        prayer.endTime.timeIntervalSinceNow
//    }
//    
//    private var isInFinalSeconds: Bool {
//        timeRemaining < 4
//    }
//    
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    
//    private var finalAnimation: Double {
//        if isInFinalSeconds {
//            // Convert remaining time to 0-1 range with dramatic acceleration
//            let progress = 1 - (timeRemaining-1 / 3)
//            return pow(progress, 5) // Quartic easing for dramatic effect
//        }
//        return 0
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
//                // Layer 1: Dynamic trailing background piece
//                if clockwiseProgress > 0.1  {
//                    Circle()
//                        .trim(from: isInFinalSeconds ?
//                              max(clockwiseProgress * finalAnimation, 0) :
//                                0, to: isInFinalSeconds ?  1 : clockwiseProgress-0.05)
//                        .stroke(style: StrokeStyle(
//                            lineWidth: 24,
//                            lineCap: .round
//                        ))
//                        .frame(width: 200, height: 200)
//                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
//                        .foregroundStyle(isInFinalSeconds ? .blue.opacity(0.3) : progressColor)
//                }
//                
//                // Layer 2: Small shadow segment
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          max(clockwiseProgress - (0.08 * (1 - finalAnimation)), 0) :
//                          max(clockwiseProgress - 0.08, 0),
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
//                    .foregroundStyle(isInFinalSeconds ? .green.opacity(0.3) : progressColor)
//                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
//                    .opacity(clockwiseProgress)
//                
//                // Layer 3: Main progress arc
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          max(clockwiseProgress * finalAnimation, 0.1) :
//                          (clockwiseProgress > 0.15 ? 0.1 : 0),
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
//                    .foregroundStyle(isInFinalSeconds ? .orange.opacity(0.3) : progressColor)
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
//            // Qibla indicator at the top
//            Circle()
//                .frame(width: 8, height: 8)
//                .offset(y: -100)
//                .foregroundStyle(progressColor == .white ? .gray : .white)
//                .opacity(isQiblaAligned ? 0.5 : 0)
//        }
//        // .id(timeRemaining) // Forces view to update as time changes
//        // .animation(.easeOut(duration: 0.2), value: finalAnimation)
//    }
//}
//
//
////struct RingStyle4Old {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    private var timeRemaining: TimeInterval {
////        prayer.endTime.timeIntervalSinceNow
////    }
////
////    private var isInFinalSeconds: Bool {
////        timeRemaining < 3
////    }
////
////    private var clockwiseProgress: Double {
////        1 - progress
////    }
////
////    private var startPoint: Double {
////        if isInFinalSeconds {
////            // Convert the remaining time to a 0-1 progress
////            let finalProgress = 1 - (timeRemaining / 3)
////
////            // Apply cubic-bezier easing for acceleration
////            let easedProgress = pow(finalProgress, 3) // Cubic easing
////            // or for even more dramatic acceleration:
////            // let easedProgress = pow(finalProgress, 4) // Quartic easing
////
////            // Calculate the start point position
////            return clockwiseProgress * easedProgress
////        }
////        return clockwiseProgress > 0.85 ? 0.25 : 0  // Changed from 0.75
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Only show overlap pieces when not in final seconds
////                if clockwiseProgress > 0.85 && !isInFinalSeconds {  // Changed from 0.75
////                    // Layer 1: Static background piece
////                    Circle()
////                        .trim(from: 0, to: 0.25)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////
////                    // Layer 2: Overlap effect piece
////                    Circle()
////                        .trim(from: 0.15, to: 0.3)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: progressColor.opacity(0.3), radius: 5, x: 0, y: 0)
////                }
////
////                // Main progress arc with animated start point
////                Circle()
////                    .trim(from: startPoint, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////
////                // Shadow segment
////                if !isInFinalSeconds {
////                    Circle()
////                        .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                        .stroke(style: StrokeStyle(
////                            lineWidth: 24,
////                            lineCap: .round
////                        ))
////                        .frame(width: 200, height: 200)
////                        .rotationEffect(.degrees(-90))
////                        .foregroundStyle(progressColor)
////                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                        .opacity(clockwiseProgress)
////                }
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // White circle indicator at the top for Qibla
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////        .animation(.easeInOut(duration: 0.2), value: startPoint)
////    }
////}
//
//
////struct RingStyle3OldSimple {
////    let prayer: Prayer
////    let progress: Double
////    let progressColor: Color
////    let isCurrentPrayer: Bool
////    let isAnimating: Bool
////    let colorScheme: ColorScheme
////    let isQiblaAligned: Bool
////
////    init(prayer: Prayer,
////         progress: Double,
////         progressColor: Color,
////         isCurrentPrayer: Bool,
////         isAnimating: Bool,
////         colorScheme: ColorScheme,
////         isQiblaAligned: Bool) {
////        self.prayer = prayer
////        self.progress = progress
////        self.progressColor = progressColor
////        self.isCurrentPrayer = isCurrentPrayer
////        self.isAnimating = isAnimating
////        self.colorScheme = colorScheme
////        self.isQiblaAligned = isQiblaAligned
////    }
////
////    // Convert countdown progress to clockwise progress
////    private var clockwiseProgress: Double {
////        1 - progress // Invert the progress
////    }
////
////    var body: some View {
////        ZStack {
////            // Outer pulsing circle (only for current prayer)
////            if isCurrentPrayer {
////                Circle()
////                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
////                    .frame(width: 224, height: 224)
////                    .rotationEffect(.degrees(-90))
////                    .scaleEffect(isAnimating ? 1.15 : 1)
////                    .opacity(isAnimating ? -0.05 : 0.7)
////                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
////                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
////            } else {
////                Circle()
////                    .frame(width: 224, height: 224)
////                    .opacity(0)
////            }
////
////            // Base ring (background)
////            Circle()
////                .stroke(lineWidth: 24)
////                .frame(width: 200, height: 200)
////                // .foregroundStyle(progressColor == .red ? progressColor.opacity(0.7) : progressColor)
////                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
////                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
////
////            // Progress arc (only for current prayer)
////            if isCurrentPrayer {
////                // Layer 1: Small shadow segment that follows the progress
////                Circle()
////                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
////                    .opacity(clockwiseProgress)
////
////                // Layer 2: Main progress arc
////                Circle()
////                    .trim(from: 0, to: clockwiseProgress)
////                    .stroke(style: StrokeStyle(
////                        lineWidth: 24,
////                        lineCap: .round
////                    ))
////                    .frame(width: 200, height: 200)
////                    .rotationEffect(.degrees(-90))
////                    .foregroundStyle(progressColor)
////            }
////
////            // Inner gradient circle for depth effect
////            Circle()
////                .stroke(lineWidth: 0.34)
////                .frame(width: 175, height: 175)
////                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
////                .overlay {
////                    Circle()
////                        .stroke(.black.opacity(0.1), lineWidth: 2)
////                        .blur(radius: 5)
////                        .mask {
////                            Circle()
////                                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
////                        }
////                }
////
////            // Qibla indicator
////            Circle()
////                .frame(width: 8, height: 8)
////                .offset(y: -100)
////                .foregroundStyle(progressColor == .white ? .gray : .white)
////                .opacity(isQiblaAligned ? 0.5 : 0)
////        }
////    }
////}
//struct RingStyle5 {
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
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    
//    private var timeRemaining: TimeInterval {
//        prayer.endTime.timeIntervalSinceNow
//    }
//    
//    private var isInFinalSeconds: Bool {
//        timeRemaining < 3
//    }
//    
//    private var finalAnimation: Double {
//        if isInFinalSeconds {
//            let progress = 1 - (timeRemaining / 3)
//            return pow(progress, 5)
//        }
//        return 0
//    }
//    
//    private var ringTipShadowOffset: CGPoint {
//        let ringTipPosition = tipPosition(progress: clockwiseProgress, radius: 100) // 200/2 for radius
//        let shadowPosition = tipPosition(progress: clockwiseProgress + 0.0075, radius: 100)
//        return CGPoint(
//            x: shadowPosition.x - ringTipPosition.x,
//            y: shadowPosition.y - ringTipPosition.y
//        )
//    }
//    
//    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
//        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
//        return CGPoint(
//            x: radius * cos(progressAngle.radians),
//            y: radius * sin(progressAngle.radians)
//        )
//    }
//    
//    var body: some View {
//        ZStack {
//            // Outer pulsing circle
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
//            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(Color.white)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//
//            // Base ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Main progress arc
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          (clockwiseProgress * finalAnimation) : 0,
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(progressColor)
//                
//                // Tip shadow as trimmed circle
//                Circle()
////                    .trim(from: max(clockwiseProgress - 0.05, 0), to: clockwiseProgress)
//            
////                .trim(from: isInFinalSeconds ?
////                  (clockwiseProgress * finalAnimation) :
////                    clockwiseProgress,
////                  to:
////                    isInFinalSeconds ?
////                  (clockwiseProgress * finalAnimation - 0.003) : // Just a tiny segment
////                  (clockwiseProgress - 0.003))
//            
//                .trim(from: clockwiseProgress - 0.001, // 0.001 = about 0.36 degrees (360° * 0.001)
//                  to: clockwiseProgress)            // Difference of just 0.36° creates a dot
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(progressColor)
//                    .shadow(
//                        color: .black.opacity(0.3),
//                        radius: 2.5,
//                        x: ringTipShadowOffset.x,
//                        y: ringTipShadowOffset.y
//                    )
//                .opacity(clockwiseProgress)
//            }
//            
//            // Inner gradient circle for depth
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
//        .animation(.easeOut(duration: 0.2), value: finalAnimation)
//    }
//}
//
//struct RingStyle6 {
//    let prayer: Prayer
//    let progress: Double
//    let progressColor: Color
//    let isCurrentPrayer: Bool
//    let isAnimating: Bool
//    let colorScheme: ColorScheme
//    let isQiblaAligned: Bool
//    
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    
//    private var timeRemaining: TimeInterval {
//        prayer.endTime.timeIntervalSinceNow
//    }
//    
//    private var isInFinalSeconds: Bool {
//        timeRemaining < 6  // Increased for earlier animation
//    }
//    
//    private var finalAnimation: Double {
//        if isInFinalSeconds {
//            let progress = 1 - ((timeRemaining - 2) / 4)  // 4 seconds of animation, 2 seconds dead time
//            return min(max(pow(progress, 5), 0), 1)
//        }
//        return 0
//    }
//    
//    private var ringTipShadowOffset: CGPoint {
//        let ringTipPosition = tipPosition(progress: clockwiseProgress, radius: 100)
//        let shadowPosition = tipPosition(progress: clockwiseProgress + 0.0075, radius: 100)
//        return CGPoint(
//            x: shadowPosition.x - ringTipPosition.x,
//            y: shadowPosition.y - ringTipPosition.y
//        )
//    }
//    
//    private func tipPosition(progress: Double, radius: Double) -> CGPoint {
//        let progressAngle = Angle(degrees: (360.0 * progress) - 90.0)
//        return CGPoint(
//            x: radius * cos(progressAngle.radians),
//            y: radius * sin(progressAngle.radians)
//        )
//    }
//    
//    var body: some View {
//        ZStack {
//            // Outer pulsing circle
//            if isCurrentPrayer {
//                Circle()
//                    .stroke(style: StrokeStyle(lineWidth: isAnimating ? 6 : 15))
//                    .frame(width: 224, height: 224)
//                    .rotationEffect(.degrees(-90))
//                    .scaleEffect(isAnimating ? 1.15 : 1)
//                    .opacity(isAnimating ? -0.05 : 0.7)
//                    .foregroundStyle(colorScheme == .dark ? progressColor : progressColor == .red ? progressColor.opacity(0.5) : progressColor.opacity(0.7))
//                    .shadow(color: progressColor.opacity(0.3), radius: 15, x: 0, y: 0)
//            }
//
//            // Clear ring for inner shadow effect (the base ring having opacity 0.15 runied it)
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(Color.white)
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            // Base ring
//            Circle()
//                .stroke(lineWidth: 24)
//                .frame(width: 200, height: 200)
//                .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
//                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//            
//            if isCurrentPrayer {
//                // Main progress arc with gradient
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          (clockwiseProgress * finalAnimation) : 0,
//                          to: clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(
//                        AngularGradient(
//                            gradient: Gradient(colors: [
//                                progressColor.opacity(0.8),
//                                progressColor
//                            ]),
//                            center: .center,
//                            startAngle: .degrees(-90),
//                            endAngle: .degrees(-90 + (360 * clockwiseProgress))
//                        )
//                    )
//                
//                // Ring tip with shadow
//                Circle()
//                    .trim(from: isInFinalSeconds ?
//                          (clockwiseProgress * finalAnimation - 0.001) :
//                          (clockwiseProgress - 0.001),
//                          to:
//                          clockwiseProgress)
//                    .stroke(style: StrokeStyle(
//                        lineWidth: 24,
//                        lineCap: .round
//                    ))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundStyle(progressColor)
//                    .shadow(
//                        color: .black.opacity(0.3),
//                        radius: 2.5,
//                        x: ringTipShadowOffset.x,
//                        y: ringTipShadowOffset.y
//                    )
//            }
//            
//            // Inner gradient circle for depth
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
//        // .animation(.easeOut(duration: 0.2), value: finalAnimation)
//    }
//}
//
//struct PulseCircleView: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 2  // Add this line
//    
//    @State private var showTimeUntilText: Bool = true
//    @State private var showEndTime: Bool = true  // Add this line
//    @State private var isAnimating = false
//    @State private var currentTime = Date()
//    @Environment(\.colorScheme) var colorScheme
//    @State private var timer: Timer?
//    
//    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
//    
//    // Timer for updating currentTime
//    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//    
//    private var isCurrentPrayer: Bool {
//        let now = currentTime
//        let isCurrent = now >= prayer.startTime && now < prayer.endTime
////        print("Is current prayer? \(isCurrent)") // Add debug print
//        return isCurrent
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        if isUpcomingPrayer { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
//    }
//    
//    private var progressZone: Int {
//        if progress > 0.5 { return 3 }      // Green zone
//        else if progress > 0.25 { return 2 } // Yellow zone
//        else if progress > 0 { return 1 }    // Red zone
//        else { return 0 }                    // No zone (upcoming)
//    }
//    
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 1.25 }
//        else { return 0.60 }
//    }
//    
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else if isUpcomingPrayer {return .white}
//        else {return .gray}
//    }
//    
//    private func startPulseAnimation() {
//        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            // Initial pulse
//            triggerPulse()
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
//            }
//        }
//    }
//    
//    private func triggerPulse() {
//        isAnimating = false
//        triggerSomeVibration(type: .medium)
//        
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    private var isMissedPrayer: Bool {
//        currentTime >= prayer.endTime && !prayer.isCompleted
//    }
//    
//    // Add LocationManager
//    @StateObject private var locationManager = LocationManager()
//    
//    // Mecca coordinates
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262
//    
//    private func calculateQiblaDirection() -> Double {
//        guard let userLocation = locationManager.location else { return 0 }
//        
//        let userLat = userLocation.coordinate.latitude * .pi / 180
//        let userLong = userLocation.coordinate.longitude * .pi / 180
//        let meccaLat = meccaLatitude * .pi / 180
//        let meccaLong = meccaLongitude * .pi / 180
//        
//        let y = sin(meccaLong - userLong)
//        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
//        
//        var qiblaDirection = atan2(y, x) * 180 / .pi
//        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
//        
//        let returnVal = qiblaDirection - locationManager.compassHeading
//        
//        return returnVal
//    }
//    
//    // Add these state variables
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
//    
//    // Add this computed property for formatting the ongoing prayer duration
//    private var prayerStatusText: String {
//        guard let startTime = prayerStartTime else { return "00:00" }
//        let duration = currentTime.timeIntervalSince(startTime)
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        return String(format: "%02d:%02d", minutes, seconds)
//    }
//    
//    @State private var completedPrayerArcs: [PrayerArc] = []
//    
//    private func handlePrayerTracking() {
//        triggerSomeVibration(type: .success)
//        
//        if !isPraying {
//            // Start praying
//            isPraying = true
//            timer?.invalidate()
//            timer = nil
//            prayerStartTime = Date()
//            // Store start time persistently
//            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
//        } else {
//            // Finish praying - save the arc
//            let newArc = PrayerArc(
//                startProgress: prayerTrackingCurrentProgress,
//                endProgress: prayerTrackingStartProgress
//            )
//            completedPrayerArcs.append(newArc)
//            
//            isPraying = false
//            guard let startTime = prayerStartTime else { return }
//            let duration = Date().timeIntervalSince(startTime)
//            lastPrayerDuration = duration
//            
//            // Store the prayer duration
//            let key = "prayerDurations_\(prayer.name)"
//            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
//            durations.append(duration)
//            UserDefaults.standard.set(durations, forKey: key)
//            
//            // Clear the start time
//            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
//            prayerStartTime = nil
//        }
//    }
//    
//    private var adjustedProgPerZone: Double {
//        // get the current progress
//        // get the current color
//        // if green, its an interval from 1 to 0.5 (0.5 of space). so progress may be 0.7. so show (0.7-0.5)/(0.5)
//        // if yellow, its an interval from 0.5 to 0.25 (0.25 of space). so progress may be 0.4. so show (0.4-0.25)/(0.25)
//        // if red, its an interval from 0.25 to 0 (0.25 of space). so progress may be 0.1. so show (0.1-0)/(0.25)
//        // so the formula is ( {progress} - {sum of intervals below} ) / ( {space of current interval} )
//        
//        let greenInterval = (1.0, 0.5)
//        let yellowInterval = (0.5, 0.25)
//        let redInterval = (0.25, 0.0)
//        
//        if progress >= greenInterval.1 {
//            return (progress - greenInterval.1) / (greenInterval.0 - greenInterval.1)
//        } else if progress >= yellowInterval.1 {
//            return (progress - yellowInterval.1) / (yellowInterval.0 - yellowInterval.1)
//        } else {
//            return (progress - redInterval.1) / (redInterval.0 - redInterval.1)
//        }
//    }
//    
//    // Add these computed properties to calculate the prayer tracking arc
//    private var prayerTrackingStartProgress: Double {
//        guard let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
//    }
//
//    private var prayerTrackingCurrentProgress: Double {
//        guard isPraying, let startTime = prayerStartTime else { return 0 }
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
//        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
//    }
//    
//    // Add this property with other @State properties
//    // @State private var selectedRingStyleYoYo: Int = 1
//    
//    private func chooseRingStyle(style: Int) -> AnyView {
//        switch style {
//        case 1:
//            return AnyView(RingStyle1(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 2:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 3:
//            return AnyView(RingStyle3(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 5:
//            return AnyView(RingStyle5(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        case 6:
//            return AnyView(RingStyle6(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        default:
//            return AnyView(RingStyle2(
//                prayer: prayer,
//                progress: progress,
//                progressColor: progressColor,
//                isCurrentPrayer: isCurrentPrayer,
//                isAnimating: isAnimating,
//                colorScheme: colorScheme,
//                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//            ).body)
//        }
//    }
//
//    
//    var body: some View {
//        ZStack {
//            
//            chooseRingStyle(style: selectedRingStyle)  // Use selectedRingStyle here
//
//            
//            // Inner content
//            ZStack {
//                
////                HStack {
////                    Image(systemName: iconName(for: prayer.name))
//////                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
////                        .foregroundColor(isMissedPrayer ? .gray : .primary)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                    Text(prayer.name)
////                        .font(.title)
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
//////                        .font(.title2)
//////                        .fontWeight(.bold)
//////                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
////                }
//                
//                VStack{
//                    
//                    HStack {
//                        Image(systemName: iconName(for: prayer.name))
//    //                        .foregroundColor(.gray /*isMissedPrayer ? .gray : .primary*/)
//                            .foregroundColor(isMissedPrayer ? .gray : .primary)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        Text(prayer.name)
//                            .font(.title)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//    //                        .font(.title2)
//    //                        .fontWeight(.bold)
//    //                        .foregroundStyle(isMissedPrayer ? .gray : .primary)
//                    }
//                    
////                    Spacer(minLength: 5)
//                    if isPraying {
//                        Text(prayerStatusText)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                    }
//                    else if isCurrentPrayer {
//                        Text(showEndTime ? "ends \(formatTimeWithAMPM(prayer.endTime))" : timeLeftString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
////                            .onTapGesture {
////                                triggerSomeVibration(type: .light)
////                                showEndTime = true
////                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
////                                    showEndTime = false
////                                }
////                            }
//                        // Text(timeLeftString)
//                        // //                        .font(.headline)
//                        // //                        .font(.title)
//                        //     .fontDesign(.rounded)
//                        //     .fontWeight(.thin)
//                        //                    Button(action: toggleCompletion) {
//                        //                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                        //                            .font(.title)
//                        //                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                        //                    }
//                        //                    .padding(.top, 10)
//                    } else if isUpcomingPrayer{
//                        Text(showTimeUntilText ? "at \(formatTimeWithAMPM(prayer.startTime))" : timeUntilStartString)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .onTapGesture {
//                                triggerSomeVibration(type: .light)
//                                withAnimation(.easeIn(duration: 0.2)) {
//                                    showTimeUntilText.toggle()
//                                }
//                            }
//                    }
//                    
//                    if isMissedPrayer {
//                        Text("Missed")
//                        //                        .font(.headline)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                        //                        .foregroundColor(.gray)
//                    }
//                }
////                .padding(.top, 70)
//                
//            }
//            
//            
//            ZStack {
////                let qiblaAlignmentThreshold = 3.5
//                let isAligned = abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
//                
//                Image(systemName: "chevron.up")
//                    .font(.subheadline)
//                    .foregroundColor(.primary)
//                    .opacity(0.5)
//                    .offset(y: -70)
//                    .rotationEffect(Angle(degrees: isAligned ? 0 : calculateQiblaDirection()))
//                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: isAligned)
//                    .onChange(of: isAligned) { _, newIsAligned in
//                        if newIsAligned {
//                            triggerSomeVibration(type: .heavy)
//                        }
//                    }
//            }
//            // Make the whole circle tappable during current prayer - Move this to the FRONT
////            if isCurrentPrayer {
//                Circle()
//                    .fill(Color.white.opacity(0.01))
//                    .frame(width: 200, height: 200)
//                    .onTapGesture {
////                        if !isAnimating{
//                            triggerSomeVibration(type: .medium)
////                            print("fjuihe")
////                        }
//////                        print("Circle tapped on state: ") // Add debug print
//                        if isCurrentPrayer {
//                            withAnimation(.easeIn(duration: 0.2)) {
//                                showEndTime = false
//                            }
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                withAnimation(.easeOut(duration: 0.2)) {
//                                    showEndTime = true
//                                }
//                            }
//                        }
//                        else if isUpcomingPrayer{
//                            showTimeUntilText.toggle()
//                        }
//                    }
//                    .onLongPressGesture {
////                        print("Circle held on state: ") // Add debug print
//                        if isCurrentPrayer || isPraying {
//                            handlePrayerTracking()
//                        }
//                    }
////                    .opacity(0.001) // Make it invisible but tappable
////            }
//            
//
//            
//            // Show current prayer arc if praying
//            if isPraying {
//                Circle()
//                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
//                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
//                    .frame(width: 200, height: 200)
//                    .rotationEffect(.degrees(-90))
//                    .foregroundColor(.white.opacity(0.8))
//            }
//            
//        }
//        .onAppear {
//            startPulseAnimation()
//            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
//            locationManager.startUpdating() // Start location updates
//            // Check for unfinished prayer session
//            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
//                prayerStartTime = savedStartTime
//                isPraying = true
//            }
//        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
//        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
//        }
//        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
////            let oldProgress = progress
////            let oldTime = currentTime
//            currentTime = newTime
//            
////            print("""
////                \n--- Timer Update ---
////                Old Time: \(formatTime(oldTime))
////                New Time: \(formatTime(newTime))
////                Time Diff: \(newTime.timeIntervalSince(oldTime))s
////                Old Progress: \(oldProgress)
////                New Progress: \(progress)
////                Progress Diff: \(progress - oldProgress)
////                Prayer: \(prayer.name)
////                Start: \(formatTime(prayer.startTime))
////                End: \(formatTime(prayer.endTime))
////                ----------------
////                """)
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm:ss.SSS"
//        return formatter.string(from: date)
//    }
//}
//
//// Simplified preview
//struct PulseCircleView_Previews: PreviewProvider {
//    static var previews: some View {
//        let calendar = Calendar.current
//        let now = Date()
//        let prayer = Prayer(
//            name: "Asr",
//            startTime: calendar.date(byAdding: .second, value: -3, to: now) ?? now,
//            endTime: calendar.date(byAdding: .second, value: 20, to: now) ?? now
//        )
//        
//        PulseCircleView(
//            prayer: prayer,
//            toggleCompletion: {}
//        )
////        .background(.black)
//    }
//}
//
//extension Prayer {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}
//
//struct CustomArc: Shape {
//    var progress: Double
//
//    func path(in rect: CGRect) -> Path {
//        var path = Path()
//        let startAngle = Angle(degrees: -90)
//        let endAngle = Angle(degrees: -90 + 360 * progress)
//
//        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
//                    radius: rect.width / 2,
//                    startAngle: startAngle,
//                    endAngle: endAngle,
//                    clockwise: false)
//        return path
//    }
//}
//
//
//
//
//
//
//
//
//
//
//
//
//
//
