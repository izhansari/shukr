import SwiftUI
import QuartzCore
import Foundation
import SwiftData


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
    @Binding var showTasbeehPage: Bool
    let animationStyle: Animation = .spring
    
//    private var prayer: PrayerModel? { viewModel.relevantPrayer }
//    @State private var prayer: PrayerModel?

    
    var body: some View {
        ZStack {
            // main outer circle
            Circle()
                .fill(Color(.clear))
                .stroke(Color(.secondarySystemFill), lineWidth: 12)
                .frame(width: 200, height: 200)
            
            //Inner Content
            if sharedState.bottomTabPosition == .zikr {
//                Text("Zikr")
                VStack{
                    HStack(alignment: .center){
                        Image(systemName: "circle.hexagonpath")
                        Text("Zikr")
                            .fontWeight(.bold)
                    }
                    .font(.title)
                    Text("click to freestyle")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
                Circle()
                    .stroke(Color.green, lineWidth: 2) // Green outline
                    .frame(width: 200, height: 200)
                    .shadow(color: Color.green.opacity(0.5), radius: 5)
                    .shadow(color: Color.green.opacity(0.3), radius: 10)
                    .shadow(color: Color.green.opacity(0.2), radius: 15)
                    .background(Color.clear) // Ensures the inside remains transparent
            }
            else if let prayer = viewModel.relevantPrayer, !(prayer.status() == .upcoming && prayer.name == "Fajr") {
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
                        .animation(animationStyle, value: currentTime/*progress*/)
                        .animation(animationStyle, value: prayer.name)
                    
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
                           // Going back to the old way (want h and m with no comma. Better cleaner transition):
                            if prayer.status() == .current{
                                ExternalToggleText(
                                    originalText: "ends \(shortTimePM(prayer.endTime))",
                                    toggledText: timeLeftString(from: prayer.endTime.timeIntervalSinceNow),
                                    externalTrigger: $ogText,  // Pass the binding
                                    fontDesign: .rounded,
                                    fontWeight: .thin,
                                    hapticFeedback: true
                                )
                            }
                            else if prayer.status() ==  .upcoming{
                                ExternalToggleText(
                                    originalText: "at \(shortTimePM(prayer.startTime))",
                                    toggledText: timeUntilStart(prayer.startTime),
                                    externalTrigger: $ogText,  // Pass the binding
                                    fontDesign: .rounded,
                                    fontWeight: .thin,
                                    hapticFeedback: true
                                )
                            }else {
                                Text("Missed")
                            }
                            
                            
//                            timeText
////                                .foregroundColor(.primary.opacity(0.7))
//                                .fontDesign(.rounded)
//                                .fontWeight(.thin)
//                                .foregroundStyle(.secondary)
//                                .multilineTextAlignment(.center)
////                                .animation(animationStyle, value: ogText)
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
                            if let prayer = viewModel.relevantPrayer, prayer.status() != .upcoming {
                                viewModel.togglePrayerCompletion(for: prayer)
                                showTemporaryMessage(workItem: &dismissChainZikrItem, boolToShow: $showChainZikrButton, delay: 5)
                            }
                        }
                )
            
            
            
            if sharedState.bottomTabPosition != .zikr {
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
                
                
                // Alligned Indicator Cirlc
                Circle()
                    .fill(Color(.systemGray)/*.primary*/)
                    .frame(width: 8, height: 8)
                    .offset(y: -100)
                    .opacity(locationManager.qibla.aligned ? 1.0 : 0)
//                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: locationManager.qibla.aligned)
            }
            

        }
        .transition(.opacity)
        .fullScreenCover(isPresented: $showQiblaMap) {
            LocationMapContentView()
//                .onAppear { sharedState.allowQiblaHaptics = false }
                .onDisappear{ sharedState.allowQiblaHaptics = true }
        }
        .onAppear {
            locationManager.startUpdating() // Start location updates
            sharedState.allowQiblaHaptics = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.calculateDayScore(for: Date())
            }
        }
        .onDisappear {
            sharedState.allowQiblaHaptics = false
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
            currentTime = newTime
//            prayer = viewModel.relevantPrayer
        }
    }

    private func checkToTriggerQiblaHaptic(aligned: Bool){
        guard aligned else {return}
        if sharedState.allowQiblaHaptics{ triggerSomeVibration(type: .heavy) }
        print("checkToTriggerQiblaHaptic: allowing haptics = \(sharedState.allowQiblaHaptics)")
    }
    
    private func handleTap() {
        if sharedState.navPosition == .bottom && sharedState.bottomTabPosition == .zikr { startFreestyleTasbeehSession() }
        timer?.invalidate()
        triggerSomeVibration(type: .light)
        withAnimation{ ogText.toggle() }
        guard !ogText else {return}
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation{ ogText = true }
        }
        
        func startFreestyleTasbeehSession(){
            sharedState.targetCount = ""
            sharedState.titleForSession = ""
            sharedState.selectedMinutes = 0
            sharedState.selectedMode = 0
            showTasbeehPage = true
        }
    }
    
}



struct summaryCircle: View{
    // FIXME: think this through more and make sure it makes sense.
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var sharedState: SharedStateClass
    @Query private var scores: [DailyPrayerScore]

    @Binding var ogText: Bool  // to control the toggle text in the middle
    @State private var animationBool: Bool = false
    @State private var nextFajr: (start: Date, end: Date)?
//    @State private var summaryInfo: [String : Double?] = [:]
//    @State private var todaysScore : Double = 0.0
    
 
//    private func getTheSummaryInfo(){
//        todaysScore = 0
//        for name in viewModel.orderedPrayerNames {
//            if let prayer = viewModel.todaysPrayers.first(where: { $0.name == name }){
//                //let thisWeightedScore = prayer.weightedSummaryScoreFromEnglishScore()
//                let thisWeightedScore = prayer.weightedSummaryScoreFromNumberScore()
////                summaryInfo[name] = thisWeightedScore
//                todaysScore += thisWeightedScore
//                print("\(prayer.isCompleted ? "☑" : "☐") \(prayer.name) with score: \(thisWeightedScore)")
//            }
//        }
//        
//        todaysScore = todaysScore / 5
//        
//    }
    private func changeInDailyScore() -> Text {
        let changeWithSign = viewModel.todaysScore - getYesterdayScore()
        let improvement = changeWithSign > 0
        let absChange = abs(changeWithSign)
        let percentageAbs = String(format: "%.1f%%", absChange * 100)
        return Text(changeWithSign < 0 ? "↓\(percentageAbs)" : "↑\(percentageAbs)").foregroundStyle(improvement ? Color(.systemGreen) : Color(.systemRed))
        
        func getYesterdayScore() -> Double {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            let startOfDay = Calendar.current.startOfDay(for: yesterday)
            
            let dailyScore = scores.first { score in
                Calendar.current.isDate(score.date, inSameDayAs: startOfDay)
            }
            
            return dailyScore?.averageScore ?? 0
        }
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
            if sharedState.navPosition == .bottom && sharedState.bottomTabPosition == .salah{
                // The Summary Score
                VStack{
                    Text("Today's Score:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                    Text(String(format: "%.1f%%", /*todaysScore*/ viewModel.todaysScore * 100))
                        .font(.title)
                        .fontWeight(.medium)
                        .fontDesign(.rounded)
                    changeInDailyScore()
                        .opacity(0.7)
                        .font(.caption)
                        .fontDesign(.rounded)
                }
            }else {
                // Fajr Icon, Title, Time:
                VStack{
                    HStack(alignment: .center){
                        Image(systemName: prayerIcon(for: "Fajr"))
                        Text("Fajr")
                            .fontWeight(.bold)
                    }
                    .font(.title)
                    
                    // Displayed Fajr Time:
                    if let fajrTime = nextFajr{
                        ZStack{
                            if ogText{
                                Text("in \(fajrTime.start, style: .relative)")
                            }
                            else {
                                Text("\(shortTime(fajrTime.start)) - \(shortTimePM(fajrTime.end))")
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(.primary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fontDesign(.rounded)
                        .fontWeight(.thin)
                        .transition(.blurReplace)
                    }
                }
            }
        }
        .transition(.opacity)


        .onAppear {
            getTheNextFajrTime()
//            getTheSummaryInfo()
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
