import SwiftUI
import QuartzCore
import Foundation


struct MainCircleView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var locationManager: EnvLocationManager
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @State private var ogText = true  // to control the toggle text in the middle
    @State private var dismissChainZikrItem: DispatchWorkItem? // Manage the dismissal timer
    
    @Binding var showQiblaMap: Bool
    @Binding var showChainZikrButton: Bool
    let animationStyle: Animation = .spring
    
    private var prayer: PrayerModel? { viewModel.relevantPrayer }
    
    var body: some View {
        ZStack {
            // main outer circle
            Circle()
                .fill(Color(.clear))
                .stroke(Color(.secondarySystemFill), lineWidth: 12)
                .frame(width: 200, height: 200)
            
            //Inner Content
            if let prayer = prayer {
                var progress: Double {
                    guard prayer.status() == .current else { return 1 }
                    let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
                    let elapsed = currentTime.timeIntervalSince(prayer.startTime)
                    let endVal = elapsed / totalDuration
                    return endVal
                }
                var progressColor: Color {
                    if progress >= 1 { return .clear }
                    else if progress >= 0.75 { return .red }
                    else if progress >= 0.5 { return .yellow }
                    else { return .green }
                }
                var timeText: Text{
                    switch prayer.status() {
                    case .current:
                        return Text(prayer.endTime, style: ogText ? .relative : .time)
                    case .upcoming:
                        if ogText { return Text("in \(prayer.startTime, style: .relative)") }
                        else { return Text("at \(prayer.startTime, style: .time)") }
                    default :
                        return Text("Missed")
                    }
                }
                
                ZStack{
                    // progress arc
                    Circle()
                        .trim(from: 0, to: progress) // Adjust progress value (0 to 1)
                        .stroke( progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(animationStyle, value: progress)
                    
                    // Inner content
                    ZStack{
                        VStack{
                            HStack(alignment: .center){
                                Image(systemName: prayerIcon(for: prayer.name))
                                Text(prayer.name)
                                    .fontWeight(.bold)
                            }
                            .animation(animationStyle, value: prayer.name)
                            .font(.title)
                            timeText
                                .foregroundColor(.primary.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .animation(animationStyle, value: ogText)
                            
                        }
                    }
                }
            }
            else {
                summaryCircle(ogText: $ogText)
            }
            
            // tappable circle on top (cant mix with outer circle cuz then the progress goes under the circle stroke)
            Circle()
                .fill(Color(.systemBackground).opacity(0.001))
                .frame(width: 200, height: 200)
                .onTapGesture {
                    handleTap()  // Toggle the trigger
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if let prayer = prayer, prayer.status() != .upcoming {
                                viewModel.togglePrayerCompletion(for: prayer)
                                showTemporaryMessage(workItem: &dismissChainZikrItem, boolToShow: $showChainZikrButton, delay: 5)
                            }
                        }
                )
            
            
            
            // Qibla Arrow
            Image(systemName: "chevron.up")
                .font(.subheadline)
                .foregroundColor(locationManager.qibla.aligned ? .green : .primary)
                .background(
                    Circle() // this is to increase tappable aread
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 44, height: 44)
                )
                .opacity(0.5)
                .offset(y: -80)
                .rotationEffect(Angle(degrees: locationManager.qibla.aligned ? 0 : locationManager.qibla.heading))
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: locationManager.qibla.aligned)
                .onChange(of: locationManager.qibla.aligned) { _, newIsAligned in
                    checkToTriggerQiblaHaptic(aligned: newIsAligned)
                }
                .onTapGesture { showQiblaMap = true }
            
        }
        .fullScreenCover(isPresented: $showQiblaMap) {
            LocationMapContentView()
                .onAppear { sharedState.allowQiblaHaptics = false }
                .onDisappear{ sharedState.allowQiblaHaptics = true }
        }
        .onAppear {
            locationManager.startUpdating() // Start location updates
            sharedState.allowQiblaHaptics = true
        }
        .onDisappear {
            sharedState.allowQiblaHaptics = false
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
            currentTime = newTime
        }
    }

    private func checkToTriggerQiblaHaptic(aligned: Bool){
        guard aligned else {return}
        if sharedState.allowQiblaHaptics{ triggerSomeVibration(type: .heavy) }
        print("checkToTriggerQiblaHaptic: allowing haptics = \(sharedState.allowQiblaHaptics)")
    }
    
    private func handleTap() {
        timer?.invalidate()
        triggerSomeVibration(type: .light)
        withAnimation{ ogText.toggle() }
        guard !ogText else {return}
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation{ ogText = true }
        }
    }

    
}



struct summaryCircle: View{
    // FIXME: think this through more and make sure it makes sense.
    @EnvironmentObject var viewModel: PrayerViewModel

    @Binding var ogText: Bool  // to control the toggle text in the middle

    @State private var nextFajr: (start: Date, end: Date)?
    @State private var summaryInfo: [String : Double?] = [:]
    @State private var todaysScore : Double = 0.0
    
    private var timeText: Text{
        guard let fajrTime = nextFajr else { return Text("") }
        if ogText{
            return Text("in \(fajrTime.start, style: .relative)")
        }
        else {
            return Text("\(shortTime(fajrTime.start)) - \(shortTimePM(fajrTime.end))")
        }
    }
    
    private func getTheSummaryInfo(){
        for name in viewModel.orderedPrayerNames {
            if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }){
                summaryInfo[name] = prayer.numberScore
                todaysScore += prayer.numberScore ?? 0.0
                print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with scores: \(prayer.numberScore ?? 0)")
            }
        }
        
        todaysScore = todaysScore / 5
        
    }
    
    func getTheNextFajrTime() {
        if let todaysFajr = viewModel.getPrayerTime(for: "Fajr", on: Date()){
            if todaysFajr.start > Date(){
                nextFajr = todaysFajr
            }
            else{
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                nextFajr = viewModel.getPrayerTime(for: "Fajr", on: tomorrow)
            }
        }
    }

    var body: some View{
        ZStack{
                        
                ZStack{
                    VStack{
                        HStack(alignment: .center){
                            Image(systemName: prayerIcon(for: "Fajr"))
                            Text("Fajr")
                                .fontWeight(.bold)
                        }
                        //.animation(.spring, value: prayer.name)
                        .font(.title)
                        timeText
                            .foregroundColor(.primary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .animation(.spring, value: ogText)

                    }
                    Text(String(format: "%.1f%%", todaysScore * 100))
                        .offset(y: 60)
                        .foregroundColor(.primary.opacity(0.7))
                        .font(.footnote)
                }

        }
        .onAppear {
            getTheNextFajrTime()
            getTheSummaryInfo()
        }
    }
    

}












/*
 class DisplayLink: ObservableObject { // updates every frame... very resource intensive... 60-120HZ
     private var displayLink: CADisplayLink?
     private var callback: ((Date) -> Void)?
     
     func start(callback: @escaping (Date) -> Void) {
         self.callback = callback
         displayLink = CADisplayLink(target: self, selector: #selector(update))
         displayLink?.add(to: .main, forMode: .common)
     }
     
     func stop() {
         displayLink?.invalidate()
         displayLink = nil
     }
     
     @objc private func update(displayLink: CADisplayLink) {
         callback?(Date())
     }
 }
 
 @StateObject private var displayLink = DisplayLink() // Replace Timer.publish with DisplayLink
 @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 9

 @State private var showTimeUntilText: Bool = true
 @State private var showEndTime: Bool = true  // Add this line
 @State private var isAnimating = false
 private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()


 private var progressZone: Int {
     if progress > 0.5 { return 3 }      // Green zone
     else if progress > 0.25 { return 2 } // Yellow zone
     else if progress > 0 { return 1 }    // Red zone
     else { return 0 }                    // No zone (upcoming)
 }
 
 private var pulseRate: Double {
     if progress > 0.5 { return 3 }
     else if progress > 0.25 { return 2 }
     else { return 1 }
 }
 
private var showingPulseView: Bool{
    sharedState.showingPulseView
}

private func startPulseAnimation() {
//        if isPraying {return}
    // First, clean up existing timer
    timer?.invalidate()
    timer = nil
    
    // Only start animation for current prayer
    if isCurrentPrayer {
        
        // Create new timer
        timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
            triggerPulse()
//                if !sharedState.showingOtherPages { triggerPulse() }
        }
    }
}

private func triggerPulse() {
    isAnimating = false
    if sharedState.showingPulseView && (sharedState.navPosition == .bottom || sharedState.navPosition == .main) /*sharedState.showSalahTab*/{
        triggerSomeVibration(type: .medium)
    }
    print("triggerPulse: showing pulseView \(sharedState.showingPulseView) (still calling it)")

    withAnimation(.easeOut(duration: pulseRate)) {
        isAnimating = true
    }
}
 
 private var timeLeftString: String {
     let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
     return formatTimeInterval(timeLeft) + " left"
 }
 
 private var timeUntilStartString: String {
     let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//        return inMinSecStyle(from: timeUntilStart)
     return inMinSecStyle2(from: timeUntilStart)
 }
 
 private var isMissedPrayer: Bool {
     currentTime >= prayer.endTime && !prayer.isCompleted
 }

 private func formatTime(_ date: Date) -> String {
     let formatter = DateFormatter()
     formatter.dateFormat = "HH:mm:ss.SSS"
     return formatter.string(from: date)
 }
*/
