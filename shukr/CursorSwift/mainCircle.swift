import SwiftUI
import QuartzCore
import Foundation
import SwiftData


struct MainCircleView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var locationManager: EnvLocationManager   // only to start updates; publishes rarely
    @EnvironmentObject var compass: CompassState                 // heading/qibla, per update
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @State private var ogText = true  // to control the toggle text in the middle
    /// A prayer was just marked done: the flourish plays over the circle, then clears.
    @State private var flourish: PrayerCompletionEvent?
    @State private var flourishID = 0
    @State private var dismissChainZikrItem: DispatchWorkItem? // Manage the dismissal timer
    /// Just prayed: the circle offers the post-salah tasbih (tap to begin) until it's started,
    /// dismissed ("not now"), or the next prayer begins. The prayer it's for.
    @State private var postSalahFor: String?
    @AppStorage(PostSalahPromptStyle.key) private var promptStyleRaw = PostSalahPromptStyle.nudge.rawValue
    /// The prayer on the circle just came into its window, on screen: the moment plays once.
    @State private var startMoment: PrayerStartStyle?
    @State private var startMomentID = 0
    /// Settings → My Dev Stuff → Preview (`PrayerStartPreview`): the circle draws its prayer in this
    /// state instead of the real one — "next", then "now" as the moment plays. Visual only.
    @State private var preview: PrayerModel.prayerStatus?
    @AppStorage(PrayerStartStyle.key) private var startStyleRaw = PrayerStartStyle.fade.rawValue
    /// When the circle last appeared: a flip in the first moments (launch, coming back) doesn't play.
    @State private var appearedAt = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var promptInCircle: Bool { promptStyleRaw == PostSalahPromptStyle.circle.rawValue }
    private var promptAsNudge: Bool { promptStyleRaw == PostSalahPromptStyle.nudge.rawValue }
    /// The pager's live state — the bottom nudge lives in the chrome and reads it.
    @Environment(PagerLiveState.self) private var live: PagerLiveState?
    
    
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
                // Where the welcome's ring lands (WelcomeAnimation.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { WelcomeTarget.circleFrame = $0 }
            
            //Inner Content — hidden while a completion flourish plays over it (PrayerCompletionFX)
            Group {
                //Inner Content
                if postSalahFor != nil {
                    PostSalahCircleOffer()
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                else if sharedState.bottomTabPosition == .zikr {
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
                else if let prayer = viewModel.relevantPrayer, preview != nil || !(prayer.status() == .upcoming && prayer.name == "Fajr") {
                    // The real state, or the dev preview's.
                    let status = preview ?? prayer.status()
                    var progress: Double {
                        // Not started: 0, so when it starts the arc grows from nothing (it was 1 in
                        // a clear colour, and sprang back from full to empty, green, at the start).
                        if status == .upcoming { return 0 }
                        guard status == .current else { return 1 }
                        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
                        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
                        let endVal = elapsed / totalDuration
                        return max(endVal, 0)
                    }
                    /// The score you'd get marking it now (PrayerScoring): green Early, yellow On time,
                    /// red Late. Was elapsed-time bands (yellow past 50 %) that didn't match the score.
                    var progressColor: Color {
                        if progress >= 1 { return .clear }
                        return PrayerScoring.color(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: currentTime))
                    }
                    var timeText: Text{
                        switch status {
                        case .current:
                            return Text(prayer.endTime, style: ogText ? .relative : .time)
                        case .upcoming:
                            if ogText { return Text("in \(prayer.startTime, style: .relative)") }
                            else { return Text("at \(prayer.startTime, style: .time)") }
                        default :
                            return Text("Missed")
                        }
                    }
                    let upcoming = status == .upcoming
                    ZStack{
                        // "Next" → "now" crossfades (ring, NEXT, the name's dimming) instead of
                        // flipping when the window opens (2026-09-27).
                        NextPrayerRing()
                            .opacity(upcoming ? 1 : 0)
                            .animation(.easeInOut(duration: 0.8), value: upcoming)
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
                                // Same type as the Insights ring: large, light, rounded.
                                HStack(alignment: .center, spacing: 8){
                                    Image(systemName: prayerIcon(for: prayer.name))
                                        .font(.system(size: 22, weight: .light))
                                    Text(prayer.name)
                                        .font(.system(size: 32, weight: .light, design: .rounded))
                                }
                                .foregroundStyle(upcoming ? Color.primary.opacity(0.55) : Color.primary)
                                .animation(.easeInOut(duration: 0.8), value: upcoming)
                                // Not started yet: "NEXT" above the name (owner: an empty ring read
                                // like a prayer that's on). An overlay, so the name sits at the same
                                // spot whether the prayer is next or current — it used to jump.
                                .overlay(alignment: .top) {
                                    Text("next")
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .tracking(2)
                                        .textCase(.uppercase)
                                        .foregroundStyle(.tertiary)
                                        .fixedSize()
                                        .offset(y: -13)
                                        .opacity(upcoming ? 1 : 0)
                                        .animation(.easeInOut(duration: 0.5), value: upcoming)
                                }
                                .animation(animationStyle, value: prayer.name)
                               // Going back to the old way (want h and m with no comma. Better cleaner transition):
                                if status == .current{
                                    ExternalToggleText(
                                        originalText: "ends \(shortTimePM(prayer.endTime))",
                                        toggledText: timeLeftString(from: prayer.endTime.timeIntervalSinceNow),
                                        externalTrigger: $ogText,  // Pass the binding
                                        font: .subheadline,
                                        fontDesign: .rounded,
                                        fontWeight: .thin,
                                        hapticFeedback: true
                                    )
                                    .foregroundStyle(.secondary)
                                }
                                else if status ==  .upcoming{
                                    ExternalToggleText(
                                        originalText: "at \(shortTimePM(prayer.startTime))",
                                        toggledText: timeUntilStart(prayer.startTime),
                                        externalTrigger: $ogText,  // Pass the binding
                                        font: .subheadline,
                                        fontDesign: .rounded,
                                        fontWeight: .thin,
                                        hapticFeedback: true
                                    )
                                    .foregroundStyle(.secondary)
                                }else {
                                    Text("missed")
                                        .font(.subheadline)
                                        .fontDesign(.rounded)
                                        .fontWeight(.thin)
                                        .foregroundStyle(.secondary)
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
                    .transition(.opacity)
                }
                else {
                    summaryCircle(ogText: $ogText)
                        .transition(.opacity)
                }
            }
            // The day summary ↔ a prayer crossfades (e.g. at Fajr the summary circle — the day's
            // score / next Fajr — becomes Fajr's ring as the prayer begins, 2026-09-27).
            .animation(.easeInOut(duration: 0.7), value: showsPrayer)
            .opacity(flourish == nil ? 1 : 0)
            .blur(radius: flourish == nil ? 0 : 8)
            .animation(.easeInOut(duration: 0.45), value: flourish == nil)

            if let flourish {
                CompletionFlourish(event: flourish)
                    .id(flourishID)
                    .transition(.opacity)
            }

            if let startMoment {
                PrayerStartMoment(style: startMoment)
                    .id(startMomentID)
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
                            // While the circle offers the tasbih it isn't showing a prayer, so a
                            // hold mustn't mark / unmark one behind it.
                            if postSalahFor == nil, let prayer = viewModel.relevantPrayer, prayer.status() != .upcoming {
                                viewModel.togglePrayerCompletion(for: prayer)
                                // The post-salah offer: in the circle (after the flourish, see
                                // .prayerCompleted) or the old pill, per the dev setting.
                                if promptStyleRaw == PostSalahPromptStyle.pill.rawValue {   // only the old top pill; the circle / bottom pill come from .prayerCompleted
                                    dismissChainZikrItem?.cancel(); withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showChainZikrButton = true }   // stays until swiped away or tapped (owner)
                                }
                            }
                        }
                )
            
            
            
            // "not now" inside the circle, above the tap layer (a tap elsewhere on it begins).
            if postSalahFor != nil {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.3)) { postSalahFor = nil }
                } label: {
                    Text("not now")
                        .font(.footnote)
                        .fontWeight(.light)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .offset(y: 56)
                .transition(.opacity)
            }

            // The qibla arrow hides while the circle offers the tasbih.
            if sharedState.bottomTabPosition != .zikr && postSalahFor == nil {
                // Qibla Arrow
                Image(systemName: "chevron.up")
                    .font(.subheadline)
                    .foregroundColor(compass.qibla.aligned ? .green : .primary)
                    .background(
                        Circle() // this is to increase tappable aread
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 44, height: 44)
                    )
                    .opacity(0.5)
                    .offset(y: -80)
                    .rotationEffect(Angle(degrees: compass.qibla.aligned ? 0 : compass.qibla.heading))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: compass.qibla.aligned)
                    .onChange(of: compass.qibla.aligned) { _, newIsAligned in
                        checkToTriggerQiblaHaptic(aligned: newIsAligned)
                    }
                    .onTapGesture { showQiblaMap = true }
                
                
                // Alligned Indicator Cirlc
                Circle()
                    .fill(Color(.systemGray)/*.primary*/)
                    .frame(width: 8, height: 8)
                    .offset(y: -100)
                    .opacity(compass.qibla.aligned ? 1.0 : 0)
//                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: compass.qibla.aligned)
            }
            

        }
        .transition(.opacity)
        .fullScreenCover(isPresented: $showQiblaMap) {
            LocationMapContentView()
//                .onAppear { sharedState.allowQiblaHaptics = false }
                .onDisappear{ sharedState.allowQiblaHaptics = true }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoPostSalahOffer") {
                if promptAsNudge { live?.postSalahNudge = "Asr" } else { postSalahFor = "Asr" }
            }
            #endif
            appearedAt = Date()
            locationManager.startUpdating() // Start location updates
            sharedState.allowQiblaHaptics = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // The prayer day, not the calendar date: after midnight (before the rollover)
                // Date() is tomorrow's rows, so today's score was never set and read 0 %.
                viewModel.calculateDayScore(for: PrayerDay.date())
            }
        }
        .onDisappear {
            sharedState.allowQiblaHaptics = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompleted)) { note in
            guard let event = note.object as? PrayerCompletionEvent else { return }
            flourishID += 1
            let id = flourishID
            withAnimation(.easeInOut(duration: 0.3)) { flourish = event }
            DispatchQueue.main.asyncAfter(deadline: .now() + CompletionFlourish.duration) {
                guard flourishID == id else { return }   // a newer completion took over
                withAnimation(.easeInOut(duration: 0.45)) {
                    flourish = nil
                    if promptInCircle { postSalahFor = event.name }   // the circle offers the tasbih
                    if promptAsNudge { live?.postSalahNudge = event.name }   // or the bottom nudge
                }
            }
        }
        // The offer goes once the next prayer has begun (its moment has passed).
        .onChange(of: viewModel.relevantPrayer?.name) { _, name in
            if let offered = postSalahFor, let name, name != offered,
               viewModel.relevantPrayer?.status() == .current {
                withAnimation(.easeInOut(duration: 0.3)) { postSalahFor = nil }
            }
            if let offered = live?.postSalahNudge, let name, name != offered,
               viewModel.relevantPrayer?.status() == .current {
                withAnimation(.easeInOut(duration: 0.3)) { live?.postSalahNudge = nil }
            }
        }
        // The prayer on the circle came into its window while we watched.
        // Only where the circle can be seen: the Salah page, nothing over it (the map, a pushed page,
        // a tasbeeh session — PrayerTimesView keeps `WelcomeTarget.canLand` for that). It used to
        // buzz from the Zikr page, Settings or under the map. At Fajr the circle was showing the day
        // summary ("next" Fajr lives there, not in a NEXT ring); the summary → Fajr crossfade above
        // carries the moment then.
        .onChange(of: circleStateKey) { old, new in
            guard old.hasSuffix("|next"), new.hasSuffix("|now"),
                  old.dropLast(5) == new.dropLast(4),                // same prayer, next → now
                  scenePhase == .active, Date().timeIntervalSince(appearedAt) > 2,
                  sharedState.horizontalPage == .main, WelcomeTarget.canLand,
                  flourish == nil, postSalahFor == nil else { return }
            playStartMoment()
            print("🌅 prayer begins moment played (\(new))")
        }
        // Dev preview: the Salah page, then this prayer as "next" for a moment, then the look's
        // transition exactly as the real one plays it (haptic included). Visual only — no prayer
        // rows, test times or notifications are touched.
        .onReceive(NotificationCenter.default.publisher(for: PrayerStartPreview.request)) { _ in
            guard viewModel.relevantPrayer != nil, flourish == nil, postSalahFor == nil else { return }
            let onSalah = sharedState.horizontalPage == .main && sharedState.navPosition == .main
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                sharedState.navPosition = .main
                sharedState.horizontalPage = .main
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (onSalah ? 0.1 : 0.8)) {
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { preview = .upcoming }      // straight into "next"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    preview = .current                              // …and it begins
                    playStartMoment()
                    DispatchQueue.main.asyncAfter(deadline: .now() + PrayerStartMoment.duration + 0.6) {
                        preview = nil                               // back to the real state
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { appearedAt = Date() } }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
            currentTime = newTime
//            prayer = viewModel.relevantPrayer
        }
    }

    /// The moment itself (the real start and the dev preview share it).
    private func playStartMoment() {
        startMomentID += 1
        let id = startMomentID
        startMoment = PrayerStartStyle(rawValue: startStyleRaw) ?? .fade
        DispatchQueue.main.asyncAfter(deadline: .now() + PrayerStartMoment.duration) {
            if startMomentID == id { startMoment = nil }
        }
    }

    /// The circle shows a prayer (vs the day summary — e.g. before Fajr, or all done).
    private var showsPrayer: Bool {
        _ = currentTime
        if preview != nil { return true }
        guard postSalahFor == nil, let p = viewModel.relevantPrayer else { return false }
        return !(p.status() == .upcoming && p.name == "Fajr")
    }

    /// "Asr|next" / "Asr|now" for the prayer on the circle (re-read every tick via currentTime).
    private var circleStateKey: String {
        _ = currentTime
        guard let prayer = viewModel.relevantPrayer else { return "" }
        switch prayer.status() {
        case .upcoming: return "\(prayer.name)|next"
        case .current: return "\(prayer.name)|now"
        default: return "\(prayer.name)|missed"
        }
    }

    private func checkToTriggerQiblaHaptic(aligned: Bool){
        guard aligned else {return}
        if sharedState.allowQiblaHaptics{ triggerSomeVibration(type: .heavy) }
        print("checkToTriggerQiblaHaptic: allowing haptics = \(sharedState.allowQiblaHaptics)")
    }
    
    private func handleTap() {
        // Offering the post-salah tasbih: a tap starts it.
        if postSalahFor != nil {
            triggerSomeVibration(type: .success)
            withAnimation(.easeInOut(duration: 0.25)) { postSalahFor = nil }
            sharedState.isDoingPostNamazZikr = true
            showTasbeehPage = true
            return
        }
        if sharedState.navPosition == .bottom && sharedState.bottomTabPosition == .zikr { startFreestyleTasbeehSession() }
        // Only when the circle has text to flip. "Missed" and the day's score have none (a buzz
        // there felt like a broken button); the prayer's "ends / at" text is an
        // ExternalToggleText that buzzes by itself (this used to buzz a second time).
        let flipsOwnText: Bool   // true = ExternalToggleText, haptic included
        if let prayer = viewModel.relevantPrayer, !(prayer.status() == .upcoming && prayer.name == "Fajr") {
            guard prayer.status() == .current || prayer.status() == .upcoming else { return }
            flipsOwnText = true
        } else {
            // Summary circle: the next-Fajr side flips; the score side (salah sheet open) doesn't.
            guard !(sharedState.navPosition == .bottom && sharedState.bottomTabPosition == .salah) else { return }
            flipsOwnText = false
        }
        timer?.invalidate()
        if !flipsOwnText { triggerSomeVibration(type: .light) }
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
    /// A stored day score, `daysBack` prayer days before today (1 = yesterday).
    private func storedScore(daysBack: Int) -> Double {
        let day = Calendar.current.date(byAdding: .day, value: -daysBack, to: PrayerDay.date()) ?? PrayerDay.date()
        return scores.first { Calendar.current.isDate($0.date, inSameDayAs: day) }?.averageScore ?? 0
    }

    /// Before Fajr with nothing marked in a new prayer day, show the day that just finished
    /// instead of a 0 (owner, 2026-09-25). Since the day rolls over at Fajr this only happens
    /// without a saved location (the day then turns at 3 AM).
    private var showingYesterday: Bool {
        guard let fajr = viewModel.todaysPrayers.first(where: { $0.name == "Fajr" }) else { return false }
        return Date() < fajr.startTime && !fajr.isCompleted
    }
    private var shownScore: Double { showingYesterday ? storedScore(daysBack: 1) : viewModel.todaysScore }

    private func changeInDailyScore() -> Text {
        let previous = storedScore(daysBack: showingYesterday ? 2 : 1)
        let changeWithSign = shownScore - previous
        let improvement = changeWithSign > 0
        let absChange = abs(changeWithSign)
        let percentageAbs = String(format: "%.1f%%", absChange * 100)
        return Text(changeWithSign < 0 ? "↓\(percentageAbs)" : "↑\(percentageAbs)").foregroundStyle(improvement ? Color(.systemGreen) : Color(.systemRed))
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

                        
        // Score ↔ next-Fajr content crossfades (opacity + a little scale) inside the same
        // animation that opens the sheet, instead of the old hard switch.
        let p: CGFloat = sharedState.navPosition == .bottom ? 1 : 0
        let scoreness: CGFloat = sharedState.bottomTabPosition == .salah ? min(max((p - 0.35) / 0.3, 0), 1) : 0
        ZStack{
            // The Summary Score
            // Same type as the Insights ring: a large light number over a thin caption.
            VStack(spacing: 2){
                Text(String(format: "%.1f", shownScore * 100))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .contentTransition(.numericText(value: shownScore))
                Text(showingYesterday ? "yesterday's score" : "today's score")
                    .font(.footnote)
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .foregroundColor(.secondary)
                changeInDailyScore()
                    .opacity(0.7)
                    .font(.caption)
                    .fontDesign(.rounded)
                    .padding(.top, 2)
            }
            .opacity(Double(scoreness))
            .scaleEffect(0.9 + 0.1 * scoreness)

            // Fajr Icon, Title, Time:
            VStack{
                HStack(alignment: .center, spacing: 8){
                    Image(systemName: prayerIcon(for: "Fajr"))
                        .font(.system(size: 22, weight: .light))
                    Text("Fajr")
                        .font(.system(size: 32, weight: .light, design: .rounded))
                }

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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .transition(.blurReplace)
                }
            }
            .opacity(Double(1 - scoreness))
            .scaleEffect(1 - 0.1 * scoreness)
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
