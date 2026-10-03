import SwiftUI
import AVFAudio
import WidgetKit
import SwiftData
import UIKit
import AudioToolbox
import MediaPlayer
import Foundation


struct tasbeehView: View {
    @Binding var isPresented: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opened out of a Zikr ring under the soft look (SessionHandoff): the counter ring starts on that ring's
    /// place and glides to its own while the page, the count and the buttons fade in; nil = the usual sheet.
    @State private var entryFrom: CGRect? = SessionHandoff.shared.freshEntry?.frame
    /// The task's share before the session (the ring's arc lands there as it closes); nil = a plain close.
    @State private var landingBase: Double? = SessionHandoff.shared.freshEntry?.landingBase
    @State private var entryOffset: CGSize = .zero
    /// The soft entry in steps (SessionOpening): the page and the ring, then the count (where the Zikr ring's label
    /// was), then the buttons; all on at once for the usual sheet.
    @State private var pageIn = SessionHandoff.shared.freshEntry == nil
    @State private var countIn = SessionHandoff.shared.freshEntry == nil
    @State private var chromeIn = SessionHandoff.shared.freshEntry == nil
    /// The opening's and the close's sequences (one at a time; a close cancels an opening still playing).
    @State private var sequence: Task<Void, Never>?
    /// The counter ⇄ results hand-over (out, then in), cancelled by a newer one.
    @State private var resultsTask: Task<Void, Never>?
    @State private var openingStyle: SessionOpening = .current
    /// Closing softly: the same steps backwards over the wheel before the cover goes.
    @State private var leaving = false
    /// The Salah look prototype (SalahLook.swift): under the soft look the counter ring sits at the screen's true
    /// centre — where the Zikr wheel's and the Salah page's circles are — not the safe area's (≈14 pt lower: the
    /// ring "shifts down ever so slightly", owner), and the page is the picked palette's surface.
    @Environment(\.circleTheme) private var theme
    private var softLook: Bool { theme.soft }
    /// The ring-above session layout (decision session-flow-build A), apart from the material: `softLook` is the page's
    /// surface and the wheel's soft entry, this is where things go.
    private var ringAbove: Bool { theme.sessionLayout == .ringAbove }
    /// Where the soft look's ring should stand, as a lift from its laid-out place: raised to the pause cards' slot while
    /// paused; once finished, centred (as the Zikr wheel will hold it), only raised if the bottom block needs the room
    /// (a short phone); home for the counter and for a close.
    private var ringLiftTarget: CGFloat {
        guard ringAbove, ringSize.height > 0, ringHomeMid != .zero, !ringToCentre else { return 0 }
        if savedSession != nil {
            guard cardsBottomTop > 0 else { return 0 }
            return min(0, cardsBottomTop - 26 - (ringHomeMid.y + ringSize.height / 2))
        }
        if paused && pauseSlot.height > 0 { return pauseSlot.midY - ringHomeMid.y }
        return 0
    }
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
    
    // AppStorage properties
    @AppStorage("inactivityToggle") var toggleInactivityTimer = false
    /// Sessions without a mantra keep their quick-add step here (mantras keep theirs on the row).
    @AppStorage(QuickAddSteps.noMantraKey) private var noMantraQuickAdd = 0
    /// The session's mantra row: the picked object, else looked up by the session title
    /// (post-salah sequences and older launchers only set the title).
    @State private var sessionMantra: MantraModel?
    private var secondaryStep: Int { sessionMantra?.quickAddStep ?? noMantraQuickAdd }
    /// Count in sets: with the "+N" button switched on, every tap / drag (and −) is worth N
    /// (owner, 2026-09-25: it was a one-shot +N button). Per session, off at the start.
    @State private var countingInSets = false
    private var tapWorth: Int { countingInSets && secondaryStep > 1 ? secondaryStep : 1 }
    @AppStorage("inactivity_dimmer") private var inactivityDimmer: Double = 0.5
    @AppStorage("currentVibrationMode") private var currentVibrationMode: HapticFeedbackType = .medium
    /// The pause screen's haptics chip on "off": no counting haptic plays (each tap, the sets' ticks,
    /// every hundred, −, a Tasbih Fatimah phrase ending, the stop at the goal). Buttons keep theirs.
    private var countingHapticsOff: Bool { currentVibrationMode == .off }
    
    // State properties
//    @FocusState private var isNumberEntryFocused
    @State private var timerIsActive = false
    @State private var timerbb: Timer? = nil
    @State private var paused = false
    @State private var tasbeeh = 0
    /// Counts / seconds already done today when continuing a task: on the ring, not saved again.
    @State private var countOffset = 0
    @State private var timeOffset: TimeInterval = 0
    /// What this session itself counted (the saved total).
    private var sessionCount: Int { tasbeeh - countOffset }
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @State private var pauseStartTime: Date? = nil
    @State private var autoStop = true

    @State private var timePassedAtPauseString: String = ""
    @State private var secsPassedAtPause: TimeInterval = 0
    @State private var progressFraction: CGFloat = 0
    /// One ring (SessionHandoff's landing base): where the ring started, where it stood when the session stopped (the
    /// stop empties it), and the ring kept up while the session goes, until its arc has landed.
    @State private var startFraction: CGFloat = 0
    @State private var ringAtStop: CGFloat?
    @State private var ringHeld = false
    /// Closing onto the wheel: the living fill settles into the wheel's solid arc as it lands (decision
    /// circle-ring-handover B).
    @State private var arcSettled = false
    /// A soft close from the pause screen or the results: the ring under their cards waits hidden until they've gone
    /// (circle rule 3, out then in — it showed through them as they faded, its arc sweeping over the tiles; Sami's
    /// step-5 check, 2026-10-02).
    @State private var ringOut = false
    /// The results are in: they come once the counter under them (its ring, count and buttons) has gone — out, then in
    /// (owner, 2026-10-02: "from ring to completion page" — the "11" ring showed through the cards as they faded in).
    @State private var resultsIn = false
    /// The soft look's one ring through pause and finish (decision session-flow-build A): where it's laid out (global,
    /// the screen's centre, and its size), where the pause cards want it, the cards' bottom block's top, and how far it's lifted now.
    @State private var ringSize: CGSize = .zero
    @State private var ringHomeMid: CGPoint = .zero
    @State private var pauseSlot: CGRect = .zero
    @State private var cardsBottomTop: CGFloat = 0
    @State private var ringLift: CGFloat = 0
    /// The ring's move in flight (a wait for the cards, Reduce Motion's fade): a newer move cancels it.
    @State private var ringMoveTask: Task<Void, Never>?
    /// The pause screen's sleep chip (global): the sleep dim has a hole there while paused.
    @State private var sleepChipFrame: CGRect = .zero
    /// Reduce Motion: the ring fades out, changes place, and fades back in instead of travelling.
    @State private var ringDimmed = false
    /// Finished from the pause screen: its tiles and buttons stay up into the results (only the ring moves).
    @State private var cardsStay = false
    /// A soft close from the pause screen or the results: the ring comes home to the centre before it lands.
    @State private var ringToCentre = false
    /// The close's steps (`playClose`), each awaited to its end — no step is timed off another's guessed length: the
    /// cards (or the count and buttons) go, the arc lands where the wheel's stands, the page goes, then the ring fades
    /// over the wheel's — only once the page has gone, so the wheel's ring is whole under it (the two differ a touch in
    /// glow: removed at once it stepped; faded while the page still was, it dimmed).
    @State private var offsetY: CGFloat = 0
    @State private var highestPoint: CGFloat = 0 // Track highest point during drag
    @State private var lowestPoint: CGFloat = 0 // Track lowest point during drag
    @State private var dragToIncrementBool: Bool = true
    @State private var showNotesModal: Bool = false
    @State private var noteModalText = ""
    @State private var takingNotes: Bool = false
    @State private var inactivityTimer: Timer? = nil
    @State private var timeSinceLastInteraction: TimeInterval = 0
    @State private var showInactivityAlert = false
    @State private var countDownForAlert = 0
    @State private var stoppedDueToInactivity: Bool = false
    /// Set by `finishAsleep`; saved on the session (`SessionDataModel.endedAsleep`).
    @State private var endedAsleep = false
    @State private var newAvrgTPC: TimeInterval = 0 //calculated on increment and decrement by secondsPassed / tasbeeh
    /// Session seconds (pauses excluded) at the last tap: a session sleep mode ends is saved as
    /// ending here, not at the countdown's end or when the phone was locked (owner, idea F3BR).
    @State private var secsAtLastTap: TimeInterval = 0
    /// The clock time of the last tap, for the morning card's "ended around" (the session's own
    /// seconds leave pauses out).
    @State private var lastTapAt: Date?
    /// Sleep mode saved the session while the app was up: the screen stays black ("saved") until the
    /// phone locks — nothing bright lights up while he sleeps (owner, sleep-mode-fixes).
    @State private var sleptSaved = false
    /// The results after a sleep finish have been up a while: black until the lock (or a tap).
    @State private var sleptDark = false
    static let sleptResultsSeconds: Double = 15
    /// What "Keep counting" needs to carry the session on after sleep mode saved it (owner,
    /// sleep-keep-going): taken just before the save, since the stop clears these a beat later.
    private struct SleepResume {
        var startTime: Date?, endTime: Date?, totalPause: Double
        var targetCount: String, task: TaskModel?, lastTapAt: Date?
    }
    @State private var sleepResume: SleepResume?
    /// Keep counting was tapped before the stop's cleanup ran: resume as soon as it has.
    @State private var resumeWanted = false
    /// The results came from a sleep finish: dimmed (stays through their fade-out on Keep counting).
    @State private var resultsDimmed = false
    /// The stop's cleanup has run, so resuming can't be undone by it.
    @State private var sleepResumeReady = false
    @State private var totalPauseInSession: Double = 0
    @State private var secsToReport: TimeInterval = 0
    @State private var savedSession: SessionDataModel? = nil
    
    /// Post-salah: which of the three phrases the count is in (for the phase-change haptic).
    @State private var postSalahPhase = 0
    /// Which reminder the post-salah session shows (one per session, picked at random).
    @State private var reminderVariant: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments   // -reminderVariant N (screenshots)
        if let i = args.firstIndex(of: "-reminderVariant"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return Int.random(in: 0..<PostSalahReminder.count)
    }()
    @State private var tasbeehColorMode = false
    /// The app's own look (Light / Dark / Auto) when the session opened: the counter follows it,
    /// fixed for the session (Auto passing Maghrib mid-count doesn't flip it); sleep mode goes dark
    /// and turning sleep off comes back here (owner: the light / dark chip is gone).
    @State private var appLookDark = false

    
    private var totalTime:  Int {
        sharedState.selectedMinutes*60
    }
    
    private var secsPassed: TimeInterval{
        if let beg = startTime{
            return Date().timeIntervalSince(beg) - totalPauseInSession
        } else { return 999 }
    }
    
    private var formatTimePassed: String{
        let minutes = Int(secsPassed) / 60
        let seconds = Int(secsPassed) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
        
    private var tasbeehRate: String{
        let to100 = newAvrgTPC*100
        let minutes = Int(to100) / 60
        let seconds = Int(to100) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s"}
        else { return "\(seconds)s" }
    }
    
    /// A count or time goal session has reached its goal (Tasbih Fatimah ends at its 100 itself).
    /// On "continuous" the session carries on: the chip locks and "goal reached" shows at the bottom.
    private var goalReached: Bool {
        (sharedState.selectedMode == 1 || sharedState.selectedMode == 2) && !sharedState.isDoingPostNamazZikr
            && timerIsActive && progressFraction >= 1
    }
    /// "goal reached" tapped once: "Tap again to finish" (disarms after 3 s, like Finish early).
    @State private var goalFinishArmed = false
    @State private var goalFinishToken = 0
    
    /// Sleep mode's rule (owner, 2026-09-30, sleep-timer-rule A): no tap for 45 s, then the silent
    /// 10 s "You still there?" countdown, then the session is saved ending at the last tap.
    var inactivityLimit: TimeInterval {
        #if DEBUG
        // -sleepLimit N: a shorter wait for testing sleep mode in the simulator.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-sleepLimit"), i + 1 < args.count, let n = Double(args[i + 1]) { return n }
        #endif
        return 45
    }

    private var incrementThreshold: CGFloat = 50 // Threshold for tasbeeh increment
    
    private var debug: Bool = false
        
    private var debug_AutoStopCond : String {
        "progressFraction: \(progressFraction) | paused: \(paused) | autoStop: \(autoStop) | timerIsActive: \(timerIsActive)"
    }
    
    private var debug_AddingToPausedTimeString : String {
        "totaltime: \(roundToTwo(val: Double(totalTime))) | secpased: \(roundToTwo(val: secsPassed))"
    }
    
    private var debug_secLeft_secPassed_progressFraction: String{
        "secPassed: \(roundToTwo(val: secsPassed)) | proFra: \(roundToTwo(val: progressFraction))"
    }
    
    private var debug_avgTPC: String{
        "newOne: \(roundToTwo(val: newAvrgTPC))"
    }
    
    private func simulateTasbeehClicks(times: Int) {
        for _ in 1...times {
            incrementTasbeeh(by: 1)
        }
    }
    
    private var estTimeLeft: String?{
        // if in targetCount,
        // get rate of clicks
        // multiply remaining by avrgtpc
        if sharedState.selectedMode == 2 {
            
        }
        let timeLeft = Int(roundToTwo(val: Double(totalTime) - secsPassed))
        return "\(timeLeft)s"
    }
    
    func inactivityTimerHandler(run: String) {
        if(toggleInactivityTimer){
            switch run{
            case "restart": do {
                print("start inactivity timer with limit of \(inactivityLimit)")
                inactivityTimer?.invalidate() // Invalidate any existing timer
                showInactivityAlert = false // set it to false just to be sure.
                timeSinceLastInteraction = 0 // Reset time since last interaction
                var localCountDown = 11
                
                inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    timeSinceLastInteraction += 1.0
                    if(offsetY != 0) {
                        print("touching screen -- resetting from \(timeSinceLastInteraction) out of  \(inactivityLimit) AND showInactivityAlert = \(showInactivityAlert)")
                        timeSinceLastInteraction = 0
                        showInactivityAlert = false
                    }
                    if timeSinceLastInteraction >= inactivityLimit{ // run if tasbeeh hasnt changed for span of our limit
                        showInactivityAlert = true
                        localCountDown -= 1
                        countDownForAlert = localCountDown
                    }
                    if localCountDown <= 0 {
                        finishAsleep()
//                        isPresented = false
                    }
                    
                }
            }
            case "stop": do {
                print("stopping inactivity timer")
                inactivityTimer?.invalidate()
                showInactivityAlert = false
            }
            default:
                print("yo bro invalid use of inactivityTimerHandler func")
            }
        }
    }
    

    
    //--------------------------------------view--------------------------------------
    
    /// The soft entry (SessionHandoff): once the counter ring is laid out, put it on the tapped Zikr ring, then
    /// let it glide home (Reduce Motion: in place) as the page, the count and the buttons fade in.
    private func placeEntry(at frame: CGRect) {
        guard let from = entryFrom, !pageIn, frame.width > 0 else { return }
        entryFrom = nil
        openingStyle = reduceMotion ? .fade : SessionOpening.current
        // Normally nothing to glide (both rings at the screen's true centre); a phone where they differ still lands.
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            entryOffset = reduceMotion ? .zero : CGSize(width: from.midX - frame.midX, height: from.midY - frame.midY)
        }
        sequence?.cancel()
        sequence = Task { @MainActor in
            guard await CircleGate.nextFrame() else { return }   // the offset drawn before it glides home
            withAnimation(Self.entryGlide) { entryOffset = .zero }
            if openingStyle == .fade {
                withAnimation(.easeInOut(duration: Self.entryFadeDuration)) { pageIn = true; countIn = true; chromeIn = true }
                return
            }
            // While the wheel's label and the other circles go: the page and ring come up behind, then the count where
            // the label was, then the buttons — one choreography, its starts a beat apart.
            guard await CircleGate.pause(Self.entryPageAfter) else { return }
            withAnimation(.easeInOut(duration: Self.entryStepDuration)) { pageIn = true }
            guard await CircleGate.pause(Self.entryCountAfter - Self.entryPageAfter) else { return }
            withAnimation(.easeOut(duration: Self.entryStepDuration)) { countIn = true }
            guard await CircleGate.pause(Self.entryChromeAfter - Self.entryCountAfter) else { return }
            withAnimation(.easeOut(duration: Self.entryStepDuration)) { chromeIn = true }
        }
    }

    // The opening's choreography (its own, one place).
    private static let entryGlide = Animation.spring(response: 0.5, dampingFraction: 0.9)
    private static let entryFadeDuration: Double = 0.35
    private static let entryStepDuration: Double = 0.45
    private static let entryPageAfter: Double = 0.15
    private static let entryCountAfter: Double = 0.35
    private static let entryChromeAfter: Double = 0.5
    private static let entryFallbackAfter: Double = 0.6

    /// Closing softly onto the wheel (the host asked: SessionHandoff `.leaving`): the same steps backwards, each
    /// awaited to its end, then `.done` — the host removes the cover. One sequence: the host, the session and the wheel
    /// kept time off a hand-summed `leaveDelay` before (audit E3).
    private func playClose() {
        sequence?.cancel()
        sequence = Task { @MainActor in
            // Whatever happens (cancelled, the app sent away mid-close: completions stop), the cover still goes.
            defer { SessionHandoff.shared.finishClose() }
            let handoff = SessionHandoff.shared
            if openingStyle == .fade {
                withAnimation(.easeIn(duration: Self.fadeCloseDuration)) { leaving = true }
                guard await CircleGate.pause(Self.fadeCloseDuration) else { return }
                handoff.reveal()
                return
            }
            var arc: Task<Void, Never>?   // the counter's close lands the arc alongside its other steps
            if paused || savedSession != nil {
                if ringAbove {
                    // The ring is on screen with the cards: they go, it comes home to the centre (where the wheel's is).
                    ringToCentre = true
                    await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) {
                        leaving = true; countIn = false; chromeIn = false
                    }
                } else {
                    // Their cards go first over the page, the ring under them held hidden (not showing through), and the
                    // counter under them goes at once ("3" showed under "1.61s"); then the ring comes back where it stood.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { ringOut = true; countIn = false; chromeIn = false }
                    await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) { leaving = true }
                    withAnimation(.easeOut(duration: CircleMotion.sessionRingOverDuration)) { ringOut = false }
                }
                guard !Task.isCancelled else { return }
                await landRing()                                   // its arc to where the wheel's stands
            } else {
                // From the counter: backwards — the count and the buttons go the opening's way while the arc lands.
                arc = Task { @MainActor in await landRing() }
                await CircleMotion.animate(.easeIn(duration: CircleMotion.sessionCountOutDuration)) {
                    leaving = true; countIn = false; chromeIn = false
                }
            }
            guard !Task.isCancelled else { return }
            handoff.reveal()                                       // the wheel's label and arc back, under the page
            await CircleMotion.animate(.easeInOut(duration: CircleMotion.sessionPageOutDuration)) { pageIn = false }
            await arc?.value                                       // landed before it fades over the wheel's
            guard !Task.isCancelled else { return }
            await CircleMotion.animate(.easeOut(duration: CircleMotion.sessionRingOverDuration)) { ringHeld = false }
        }
    }
    private static let fadeCloseDuration: Double = 0.3

    var body: some View {
        ZStack {
            
            // the middle
            ZStack {
                // the circle's inside (picker or count)
                TasbeehCountView(tasbeeh: tasbeeh)
                    .offset(entryOffset)
                    .modifier(SessionAppear(shown: countIn, style: openingStyle))
                    .modifier(RingLift(lift: ringAbove ? ringLift : nil, dimmed: ringDimmed))
                
                GeometryReader { geometry in
                    VStack {
                        ZStack {
                            Color("bgColor").opacity(0.001) // Simulate clear color
                                .frame(width: geometry.size.width, height: geometry.size.height) // Fill the entire geometry
                                .onTapGesture {
                                    //                                            print("Tap gesture detected")
                                    incrementTasbeeh() // Increment on tap
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0) // Set to 0 for immediate tracking
                                        .onChanged { value in
                                            
                                            // Track drag distance
                                            offsetY = value.translation.height
                                            
                                            // Update highest and lowest points during drag
                                            if offsetY < highestPoint {
                                                highestPoint = offsetY
                                            }
                                            if offsetY > lowestPoint {
                                                lowestPoint = offsetY
                                            }
                                            
                                            // Check if dragged down from highest point by a value of incrementThreshold
                                            if dragToIncrementBool && offsetY - highestPoint > incrementThreshold {
                                                dragToIncrementBool = false
                                                incrementTasbeeh()
                                                lowestPoint = value.translation.height // need to set it otherwise it will always be the lowest point of the entire drag sesh
                                                // Check if dragged up from lowest point by a value of incrementThreshold/2
                                            } else if !dragToIncrementBool && lowestPoint - offsetY > incrementThreshold/2 {
                                                dragToIncrementBool = true
                                                highestPoint = value.translation.height
                                            }
                                        }
                                        .onEnded { _ in
                                            // Reset offsets after drag ends
                                            dragToIncrementBool = true
                                            offsetY = 0
                                            highestPoint = 0
                                            lowestPoint = 0
                                        }
                                )
                        }
                    }
                }
                
                
                // The ring's home, on something that never moves: centred like the ring, never lifted (the ring's own
                // frame moves with its lift — measured there, the lift chased itself; Sami's review of b3ed3e3).
                if ringAbove {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .onGeometryChange(for: CGPoint.self) { proxy in
                            let f = proxy.frame(in: .global)
                            return CGPoint(x: f.midX, y: f.midY)
                        } action: { ringHomeMid = $0 }
                }

                // the circles we see
                NeuCircularProgressView(progress: (progressFraction), settled: arcSettled)
                    .allowsHitTesting(false) //so taps dont get intercepted.
                    // Its place as laid out (measured inside the offset, which is zero then): the soft entry's start.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        if frame.width > 0 { ringSize = frame.size }   // its place moves with the lift; the anchor has that
                        placeEntry(at: frame)
                    }
                    // Finished (soft look): the task's title in the ring, "Saved to your history" over it, after the
                    // count has gone (out, then in). On the ring itself, so it is wherever the ring is mid-move (a view
                    // added beside it took the move's end at once). Not under the ring's allowsHitTesting(false): a free
                    // session's name opens the picker.
                    .overlay {
                        if ringAbove, let session = savedSession {
                            SessionDoneFace(session: session)
                                .modifier(SoftCardsFade(shown: resultsIn && !leaving))
                                .allowsHitTesting(resultsIn && !leaving)
                        }
                    }
                    .offset(entryOffset)
                    // One piece: faded layer by layer, its half-clear track darkened the wheel's identical arc under it
                    // as it handed over (a 2-frame dip, circle-ring-handover).
                    .compositingGroup()
                    .opacity((pageIn || ringHeld) && !ringOut ? 1 : 0)
                    .modifier(RingLift(lift: ringAbove ? ringLift : nil, dimmed: ringDimmed))
            }
            // Soft look: centred on the whole screen (the circles it opens out of are), not the safe area.
            .ignoresSafeArea(.container, edges: softLook ? .all : [])
            
            // Pause Screen (background overlay, stats & settings)
            ZStack {
                // middle screen when paused
                pauseScreen_StatsSettingsBG(
                    paused: paused,
                    mantra: sessionMantra,
                    tasbeeh: tasbeeh,
                    secsToReport: secsPassedAtPause,
                    newAvrgTPC: newAvrgTPC,
                    tasbeehRate: tasbeehRate,
                    togglePause: { togglePause() },
                    stopTimer: { stopTimer() },
                    takingNotes: takingNotes,
                    toggleInactivityTimer: $toggleInactivityTimer,
                    inactivityDimmer: $inactivityDimmer,
                    autoStop: $autoStop,
                    tasbeehColorMode: $tasbeehColorMode,
                    appLookDark: appLookDark,
                    goalReached: goalReached,
                    currentVibrationMode: $currentVibrationMode,
                    ringAbove: ringAbove,
                    timeOffset: timeOffset,
                    results: ringAbove ? savedSession.map { session in
                        .init(session: session,
                              keepCounting: sleptSaved && sleepResume != nil ? { requestKeepCounting() } : nil,
                              done: { finishFromResults() })
                    } : nil,
                    cardsShown: paused || resultsIn || (savedSession != nil && cardsStay),
                    resultsIn: resultsIn,
                    onRingSlot: { if $0.height > 0 { pauseSlot = $0 } },
                    // Frozen once finished: re-reported as the block's words changed, it moved the ring's target
                    // mid-move (the ring held, then jumped ~85 pt; Sami's B1).
                    onBottomTop: { if savedSession == nil { cardsBottomTop = $0 } },
                    onSleepChipFrame: { sleepChipFrame = $0 }
                )
            }
            .animation(.easeInOut, value: paused)
            .modifier(SessionAppear(shown: !leaving, style: openingStyle))   // a soft close from the pause screen
            
            // Settings & Start/Stop
            VStack {
                
                // The Top Buttons During Session
                HStack {
                    // Always there, faded out and inert while paused (Finish / Resume live on the
                    // pause screen). Removing them popped the layout on every pause / resume.
                    Group {
                        HStack{
                            TopOfSessionButton( // Minus Button
                                symbol: "minus", actionToDo: decrementTasbeeh,
                                paused: paused, togglePause: togglePause)
                            
                            if secondaryStep > 1 {
                                TopOfSessionButton( // Count in sets: switches every tap to +N
                                    text: "+\(secondaryStep)", actionToDo: {
                                        triggerSomeVibration(type: .light)
                                        withAnimation(.easeInOut(duration: CircleMotion.quick)) { countingInSets.toggle() }
                                    },
                                    paused: paused, togglePause: togglePause, active: countingInSets)
                                .accessibilityLabel(countingInSets ? "Counting in sets of \(secondaryStep), on" : "Count in sets of \(secondaryStep)")
                            }
                            
                            
//                            TopOfSessionButton( // Add Note Button (new feature coming soon)
//                                symbol: "note", actionToDo: {showNotesModal = true},
//                                paused: paused, togglePause: togglePause)
//                            .sheet(isPresented: $showNotesModal) {
//                                NoteModalView(savedText: $noteModalText, showSheet: $showNotesModal, takingNotes: $takingNotes)
//                            }
                        }
                        .opacity(paused ? 0 : 1)
                        .allowsHitTesting(!paused)
                    }
                    
                    
                    Spacer()
                    
                    // dynamic pause / play button shown in active session
                    PlayPauseButton(togglePause: togglePause, paused: paused)
                        .opacity(paused ? 0 : 1)
                        .allowsHitTesting(!paused)   // a disabled button still swallowed the pause screen's taps
                }
                .animation(paused ? .easeOut(duration: ringAbove ? 0.15 : 0.35) : .easeIn, value: paused)
                .padding()
                .modifier(SessionAppear(shown: chromeIn, style: openingStyle))
                // Finished: the soft results sit under this layer (the ring's, not a cover) — no stray ⏸ over Done.
                .allowsHitTesting(savedSession == nil)
                
                // Debug Updating Text In View
                if(debug){
                    Text(debug_AutoStopCond)
                    Text(debug_AddingToPausedTimeString)
                    Text(debug_secLeft_secPassed_progressFraction)
                    Text(debug_avgTPC)
                }
                
                Spacer()
                
                // Stop Button when not auto stopping
//                completeButton(stopTimer: stopTimer)
//                    .opacity(stopCondition ? 1 : 0)
//                    .disabled(!stopCondition)
//                    .animation(.easeInOut, value: stopCondition)
            }
            
            // adding a dark tint for when they click the sleep mode.
            ZStack{
                // Also on under a sleep finish's results (dimmed themselves), so the two crossfade at
                // one darkness — it faded out while they faded in and the screen brightened (owner).
                Color.black.opacity(toggleInactivityTimer || (resultsDimmed && savedSession != nil)
                                    ? ((1-inactivityDimmer) * 0.9) : 0)
                    // Paused under sleep mode, the sleep chip is never dimmed: it's how sleep goes off again, and at
                    // the darkest setting nothing could be seen (owner, decision sleep-dimmer-place: "the sleep button
                    // is always visible when pausing"). A hole in the dim, the chip's shape.
                    .mask {
                        Rectangle()
                            .overlay {
                                if paused && toggleInactivityTimer && sleepChipFrame.width > 0 {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .frame(width: sleepChipFrame.width, height: sleepChipFrame.height)
                                        .position(x: sleepChipFrame.midX, y: sleepChipFrame.midY)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                    .edgesIgnoringSafeArea(.all)
                
                // The Bottom Inactivity Alert During Session
                VStack{
                    if sharedState.isDoingPostNamazZikr {
                        PostSalahPhaseStrip(count: tasbeeh)
                            .padding(.top, 120)
                            .allowsHitTesting(false)
                            // Fades under the pause screen with it (removing it popped; left on,
                            // it drew through the pause screen), and for the results (ring-above: they don't cover it).
                            .opacity(paused || savedSession != nil ? 0 : 1)
                            .animation(.easeInOut, value: paused || savedSession != nil)
                    }
                    Spacer()
                    inactivityAlert(countDownForAlert: countDownForAlert, showOn: showInactivityAlert, action: {inactivityTimerHandler(run: "restart")})
                }
                .zIndex(1)

                // Keeps going, past the goal: a quiet way to end it without pausing (owner), low on
                // the screen just above the home indicator.
                if goalReached && !autoStop && savedSession == nil && !showInactivityAlert {
                    VStack {
                        Spacer()
                        goalReachedLine
                    }
                    .opacity(paused ? 0 : 1)
                    .allowsHitTesting(!paused)
                    .transition(.opacity)
                    .zIndex(2)
                }

                // Post-salah: why it's worth it, low on the screen, clear of the beads.
                if sharedState.isDoingPostNamazZikr {
                    VStack {
                        Spacer()
                        PostSalahReminder(variant: reminderVariant)
                            .padding(.horizontal, 36)
                            .padding(.bottom, 12)
                    }
                    .allowsHitTesting(false)
                    .opacity(paused || savedSession != nil ? 0 : 1)   // ring-above results sit under it (Sami's B4)
                    .animation(.easeInOut, value: paused || savedSession != nil)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: toggleInactivityTimer)
            
            // results page
            ZStack{
                if !ringAbove, let session = savedSession {   // ring-above: the results are the pause cards' (above)
                    ResultsView(
                        isPresented: $isPresented,
                        savedSession: session, // Pass the saved session
                        // From the first frame (it popped in half a second late and moved the page);
                        // a tap before the stop's cleanup has run waits for it (`resumeWanted`).
                        keepCounting: sleptSaved && sleepResume != nil ? { requestKeepCounting() } : nil,
                        asleep: sleptSaved
                    )
                }
                // …under sleep mode's dim, at his dimmer setting: no bright page for someone asleep
                // (owner). On the results layer itself, so on Keep counting it fades out with them over
                // the counter's own dim (already on) — the same darkness throughout, no bright flash.
                if resultsDimmed && !ringAbove {   // ring-above: the counter's own dim is over its results already
                    Color.black.opacity((1 - inactivityDimmer) * 0.9)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .zIndex(1)
            // One piece: faded leaf by leaf, the results' dim was half on while the page was half in
            // (a brief brighter frame on a sleep finish).
            .compositingGroup()
            .opacity(resultsIn ? 1 : 0)
            .disabled(savedSession == nil)
            .modifier(SessionAppear(shown: !leaving, style: openingStyle))   // a soft close from the results

            // After a while it goes black — he's most likely asleep and not looking (owner): OLED pixels
            // off, and black is the curtain the next open's welcome starts from. A tap brings it back.
            if sleptDark {
                Color.black
                    .ignoresSafeArea()
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
                    .zIndex(5)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { sleptDark = false } }
                    .transition(.opacity)
            }
            // Sleep mode saved it with the app open (the countdown): the results screen above stays up
            // until the phone auto-locks (owner: "show the completion screen until the phone auto
            // locks - not that full black thing"); the lock closes the cover in the background and the
            // morning card waits for the next open. Done on it = he's awake: no card (onDisappear).
        }
        .frame(maxWidth: .infinity) // expand to be the whole page (to make it tappable)
        .background(
            Group {
                // Soft look: the picked palette's surface, the Zikr page's own (owner: "match the stone color pallete").
                if softLook { NeuSurface() } else { Color.init("bgColor") } // Dynamic color for dark or light mode
            }
                .opacity(pageIn ? 1 : 0)   // the soft entry brings the page in over the wheel
                .edgesIgnoringSafeArea(.all)
        )
        .opacity(leaving && openingStyle == .fade ? 0 : 1)
        .allowsHitTesting(!leaving)   // no stray count while it goes
        // The host reads the close's length as it asks for it (before the leave below runs): kept current here, so the
        // cover isn't removed mid-fade (it cut the wheel's label in at once — Sami's step-5 strip).
        // Out, then in (circle rule 3): the counter goes, then the results come; Keep counting, the other way round.
        .onChange(of: savedSession != nil) { _, results in
            if results {
                cardsStay = paused
                // Soft look: the ring stays — it comes down from the pause cards (or stays put) and takes the task's title.
                // The counter's words out, then (once that fade is done, not a guess of it) the results in.
                resultsTask?.cancel()
                resultsTask = Task { @MainActor in
                    await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) {
                        ringOut = !ringAbove; countIn = false; chromeIn = false
                    }
                    guard !Task.isCancelled, savedSession != nil else { return }
                    withAnimation(.easeOut(duration: CircleMotion.resultsInDuration)) { resultsIn = true }
                }
            } else if resultsIn {
                resultsTask?.cancel()
                guard !leaving else {   // a close: the close sequence runs the rest
                    withAnimation(.easeOut(duration: CircleMomentTiming.out)) { resultsIn = false }
                    return
                }
                resultsTask = Task { @MainActor in
                    await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) { resultsIn = false }
                    guard !Task.isCancelled, savedSession == nil, !leaving else { return }
                    withAnimation(.easeOut(duration: CircleMomentTiming.in)) { ringOut = false; countIn = true; chromeIn = true }
                }
            }
        }
        // One ring, moved by a spring (CircleMotion.ringMove): interrupted (Resume while it rises), it turns back with the
        // speed it has. Coming down to finish or to close it waits a beat for the cards under it to go first; Resume
        // moves it at once (its cards go quicker).
        .onChange(of: ringLiftTarget) { old, new in
            moveRing(to: new, waitForCards: new > old && (savedSession != nil || ringToCentre))
        }
        // The host asked for the soft close (SessionHandoff): play it, then say it's done.
        .onChange(of: SessionHandoff.shared.phase == .leaving) { _, leavingNow in
            if leavingNow { playClose() }
        }

        // Belt and braces: if the ring's place never came (the entry never placed), show the session anyway.
        .task {
            guard entryFrom != nil, await CircleGate.pause(Self.entryFallbackAfter), !pageIn else { return }
            withAnimation(.easeInOut(duration: Self.entryFadeDuration)) {
                entryOffset = .zero; pageIn = true; countIn = true; chromeIn = true
            }
        }
        .onAppear {
            _ = SessionHandoff.shared.takeEntry()   // read (entryFrom, landingBase); the next session opens as it should
            CircleCover.set("tasbeeh", true)   // a session is up: prompts wait (e.g. the widget's "Unmark?")
            appLookDark = colorScheme == .dark
            tasbeehColorMode = appLookDark
            // Post-salah: the Tasbih Fatimah zikr is set up BEFORE anything resolves the pick (audit A8).
            if !timerIsActive, sharedState.isDoingPostNamazZikr { PostSalahTasbeeh.prepare(sharedState, in: context) }
            resolveSessionMantra()
            
            if !timerIsActive{
//                timerIsActive = true // ensures functions dont happen outside of session AND not reenabling the onAppear
                print("a1 tasbeehView onappear (timerIsActive?: \(timerIsActive) @ \(Date())) ")
                startTimer()
                paused = false // sometimes appstorage had paused = true. so clear it.
                inactivityTimerHandler(run: "restart")
            }
        }
        .onChange(of: sharedState.titleForSession) { _, _ in resolveSessionMantra() }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoPostSalah") {
                try? await Task.sleep(for: .seconds(1.5))
                simulateTasbeehClicks(times: 45)
            }
            #if DEBUG
            // `-demoAutoCount N`: N counts a beat after any session opens (however it was opened — the wheel's
            // rings included), to reach a goal on the simulator.
            let auto = UserDefaults.standard.integer(forKey: "demoAutoCount")
            if auto > 0 {
                try? await Task.sleep(for: .seconds(1.5))
                simulateTasbeehClicks(times: auto)
            }
            #endif
            // `-demoTasbeehCount N [-demoTasbeehTaps M]`: jump to N, then M more taps (watch comparison shots).
            if UserDefaults.standard.object(forKey: "demoTasbeehCount") != nil {
                try? await Task.sleep(for: .seconds(1))
                let n = UserDefaults.standard.integer(forKey: "demoTasbeehCount")
                if n > 0 { simulateTasbeehClicks(times: n) }
                for _ in 0..<UserDefaults.standard.integer(forKey: "demoTasbeehTaps") {
                    try? await Task.sleep(for: .seconds(0.6))
                    incrementTasbeeh(by: 1)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPauseScreen") {
                try? await Task.sleep(for: .seconds(1))
                // -demoPauseClicks N: where it pauses (e.g. 32 of 33, to test the goal).
                let args = ProcessInfo.processInfo.arguments
                let clicks = args.firstIndex(of: "-demoPauseClicks").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 12
                if args.contains("-demoKeepsGoing") { autoStop = false }   // past the goal: "goal reached"
                simulateTasbeehClicks(times: clicks)
                try? await Task.sleep(for: .seconds(1))
                if !args.contains("-demoNoPause") { togglePause() }
                // -demoPauseCycle: resume, pause, then Resume a quarter second into the rise (the spring turning back
                // mid-move), and pause again — the soft ring's moves without taps.
                if args.contains("-demoPauseCycle") {
                    for wait in [1.5, 1.2, 0.25, 1.2] {
                        try? await Task.sleep(for: .seconds(wait))
                        togglePause()
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-demoResults") {
                    try? await Task.sleep(for: .seconds(1))
                    stopTimer()
                }
            }
        }
        #endif
        .onChange(of: tasbeehColorMode){oldVal, newVal in
            print("tasbeehView: old tasbeehColorMode: \(oldVal), newVal: \(newVal)")
        }
        .onChange(of: secondaryStep) { _, step in
            if step <= 1 { countingInSets = false }   // the mantra changed on the pause screen
        }
        .onChange(of: tasbeeh){_, newTasbeeh in
            inactivityTimerHandler(run: "restart")
            if sharedState.isDoingPostNamazZikr {
                // A phrase finished (33, 66): a success buzz as the next one starts.
                let phase = PostSalahTasbeeh.phase(at: newTasbeeh).index
                if phase > postSalahPhase && !countingHapticsOff { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                postSalahPhase = phase
            }
            
            refreshCountProgress()

        }
        // Something needs him mid-session (the widget's "Unmark?"): into the usual pause state first.
        .onReceive(NotificationCenter.default.publisher(for: TasbeehSession.pauseRequest)) { _ in
            if !paused { togglePause() }
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            // Sent away mid-close: no frames, so no completions — the close is cut short (its defer ends it) rather
            // than left waiting for the app to come back.
            if newScenePhase == .background, leaving { sequence?.cancel() }
            // Sleep mode on and counting: the phone locking or leaving the app means he's asleep —
            // finish and save, ending at the last tap (he woke up on the pause screen before:
            // pausing stopped the inactivity timer).
            // Saved by the countdown and now the phone has locked: close quietly in the background.
            if sleptSaved {
                if newScenePhase == .background {
                    NotificationCenter.default.post(name: WelcomeGate.raiseCurtain, object: nil)   // black before iOS's picture
                    closeAfterSleep()
                }
                return
            }
            // Paused with sleep on counts too: auto-lock would leave him on the pause screen (or iOS
            // would kill the app and lose the session).
            // Inactive alone (the task switcher, Control Center) pauses as usual — he brings the pause
            // screen up that way (owner); the lock (inactive, then background) then finishes it.
            if toggleInactivityTimer && timerIsActive && newScenePhase == .background {
                finishAsleep()
                return
            }
            if newScenePhase == .inactive || newScenePhase == .background {
                writeDraft()   // audit A7: iOS may evict the suspended app
                !paused ? togglePause() : ()
                print("scenePhase: \(newScenePhase) (session paused? \(paused)")
            }
        }
        .onDisappear {
            CircleCover.set("tasbeeh", false)
            if sleptSaved { SleepMorning.clear() }   // Done on the results after a sleep finish: awake, no card
            sharedState.isDoingPostNamazZikr = false
            UIApplication.shared.isIdleTimerDisabled = false // never leave this on after the cover closes
        }

        .preferredColorScheme(tasbeehColorMode ? .dark : .light)
    }
//--------------------------------------functions--------------------------------------

    /// "goal reached", subtle (secondary, the counter's own dim over it); a tap makes it "Tap again to
    /// finish" in green, the second tap ends the session (the Finish early pattern).
    private var goalReachedLine: some View {
        Button {
            if goalFinishArmed {
                triggerSomeVibration(type: .medium)
                goalFinishArmed = false
                stopTimer()
            } else {
                // No buzz on the first tap: a tap's buzz on the counter reads as a count (owner). The
                // second, finishing tap keeps its haptic.
                goalFinishToken += 1
                let token = goalFinishToken
                goalFinishArmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if token == goalFinishToken { goalFinishArmed = false }
                }
            }
        } label: {
            ZStack {
                // The app's sage in the counter's light type: quiet in both looks (grey on the dark
                // counter read as greyed-out chrome — owner).
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("goal reached")
                }
                .foregroundStyle(Color.sage.opacity(0.85))
                .opacity(goalFinishArmed ? 0 : 1)
                .blur(radius: goalFinishArmed ? 3 : 0)
                Text("Tap again to finish")
                    .foregroundStyle(Color.green)
                    .opacity(goalFinishArmed ? 1 : 0)
                    .blur(radius: goalFinishArmed ? 0 : 3)
            }
            .font(.system(size: 15, weight: .light, design: .rounded))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.3), value: goalFinishArmed)
        }
        .buttonStyle(.plain)
    }

    private func resolveSessionMantra() {
        let title = sharedState.titleForSession
        if let picked = sharedState.mantraForSession, picked.isDeleted || picked.modelContext == nil {
            sharedState.mantraForSession = nil   // audit A8: deleted since it was picked
        }
        if let picked = sharedState.mantraForSession, picked.name == title || title.isEmpty {
            sessionMantra = picked
        } else {
            sessionMantra = title.isEmpty ? nil : MantraModel.find(named: title, in: context)
        }
    }

    /// Keep the screen awake only while a session is actively counting.
    /// Paused, stopped, or dismissed → hand control back to the system auto-lock.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = timerIsActive && !paused
    }
    
    private func startTimer() {
        guard !timerIsActive else {
            print("Timer is already active")
            return
        }
        
        // Reset necessary variables for a new session
        print("ran a start.")
        countOffset = sharedState.resumeCount
        timeOffset = sharedState.resumeSeconds
        sharedState.resumeCount = 0
        sharedState.resumeSeconds = 0
        tasbeeh = countOffset
        // The ring starts where the session does, at once (a timed Continue swept up from empty on the first tick).
        refreshCountProgress()
        if sharedState.selectedMode == 1 && totalTime > 0 {
            progressFraction = CGFloat(Int(timeOffset)) / TimeInterval(totalTime)
        }
        startFraction = progressFraction
        ringAtStop = nil
        
        savedSession = nil
        startTime = Date()
        endTime = Calendar.current.date(byAdding: .minute, value: sharedState.selectedMinutes, to: startTime!)
        totalPauseInSession = 0
        secsToReport = 0
        timerIsActive = true //this just ensures increment, decrement and reset dont happen outside of session
        
        startTicker()
        triggerSomeVibration(type: .success)
        updateIdleTimer()
    }

    /// The 0.1 s tick: the timed ring and the stop at the goal.
    private func startTicker() {
        timerbb?.invalidate()
        timerbb = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        
            withAnimation {
                if !paused && (sharedState.selectedMode == 1){
                    progressFraction = CGFloat(Int(secsPassed + timeOffset))/TimeInterval(totalTime)
                }
            }
           
//            print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)") // for debugging
            if ((progressFraction >= 1) && !paused) {
                if(autoStop && timerIsActive){
                    stopTimer()
                    print("homeboy auto stopped....")
                }
            }
        }
    }
    
        
    private func stopTimer() {
        ZikrAudio.stopAll()     // a memo started on the pause card doesn't play on into the results
        guard timerIsActive else {
            print("Timer is not active")
            return
        }
        
        print("ran a stopTimer().")
        //basically save only if tasbeeh > 0
        // give time to show resultsview.
        // skip resultsview if in sequence
        
        timerIsActive = false // this so functions only run during a sesh AND so timer checking when to stopTimer doesnt save multiple sessions.
        resultsDimmed = endedAsleep
        updateIdleTimer()
        if sessionCount == 0 { SessionDraft.clear() }   // audit A7: nothing to keep
        if sessionCount > 0 {
            savedSession = saveSession()
            
            print("saved session: \(savedSession == nil ? "nil" : "\(savedSession!.title) with \(savedSession!.totalCount)")")
            // Shared-state writes re-render the whole home screen under this cover, so they wait
            // until the results screen is up (completeStopTimer, after its fade) instead of
            // landing in the same frame as it — part of the "lag before the completion page"
            // (owner, 2026-09-25).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sharedState.selectedTask = nil
                self.completeStopTimer()
                // The Zikr widget reads the shared store: save, then let it redraw.
                try? self.context.save()
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.zikr)
            }
        } else {
            completeStopTimer()
        }
    }


    /// Sleep mode ended the session (no tap for a while, or the app left while counting): saved now
    /// — the app may be suspended any moment — ending at the last tap, marked `endedAsleep`.
    private func finishAsleep() {
        guard timerIsActive else { return }
        stoppedDueToInactivity = true
        endedAsleep = true
        sleepResume = SleepResume(startTime: startTime, endTime: endTime, totalPause: totalPauseInSession,
                                  targetCount: sharedState.targetCount, task: sharedState.selectedTask,
                                  lastTapAt: lastTapAt)
        sleepResumeReady = false
        stopTimer()
        try? context.save()
        // Off now, not 0.5 s later in completeStopTimer: iOS can kill the app before that runs, and
        // sleep mode was still on for the next session (seen on his phone). The countdown timer is
        // stopped first — the handler does nothing once sleep is off, so completeStopTimer can't.
        inactivityTimerHandler(run: "stop")
        toggleInactivityTimer = false
        let inBackground = UIApplication.shared.applicationState == .background
        if let savedSession {
            SleepMorning.remember(savedSession, endedAt: lastTapAt ?? Date(), armed: inBackground)
        }
        // iOS's own auto-lock takes over from here: the screen must never stay on after he's
        // asleep (owner: "so long as we dont risk the screen never turning off").
        UIApplication.shared.isIdleTimerDisabled = false
        if inBackground {
            NotificationCenter.default.post(name: WelcomeGate.raiseCurtain, object: nil)   // black before iOS's picture
            closeAfterSleep()          // locked while counting: no results screen on wake
        } else {
            sleptSaved = true          // the countdown ended it: the results screen until the lock…
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleptResultsSeconds) {
                if sleptSaved { withAnimation(.easeInOut(duration: 1.2)) { sleptDark = true } }   // …then black
            }
        }
        #if DEBUG
        print("😴 finished asleep · background \(inBackground) · idle timer disabled: \(UIApplication.shared.isIdleTimerDisabled)")
        #endif
    }

    /// Close the counter after sleep mode ended a session — never through the results screen.
    private func closeAfterSleep() {
        sleptSaved = false
        sleptDark = false
        sleepResume = nil
        resumeWanted = false
        isPresented = false
        resetSharedState()
    }

    /// The ring for a counted session: freestyle goes round every 100 (never quite full — a full
    /// ring means the goal), a count goal fills to it. Timed sessions follow the ticker.
    private func refreshCountProgress() {
        if sharedState.selectedMode == 0 {
            let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
            progressFraction = CGFloat(numerator) / 100
        } else if sharedState.selectedMode == 2 {
            progressFraction = CGFloat(tasbeeh) / CGFloat(Int(sharedState.targetCount) ?? 0)
        }
    }

    private func requestKeepCounting() {
        if sleepResumeReady { keepCountingAfterSleep() } else { resumeWanted = true }
    }

    /// "Keep counting" on the results after a sleep finish: he was only dozing. The saved row goes and
    /// the same session carries on at the same count with sleep still on; the doze (last tap → now)
    /// counts as a pause, so it's saved once at its real end and the pace stays honest.
    private func keepCountingAfterSleep() {
        guard let r = sleepResume, sleepResumeReady else { return }
        let toDelete = savedSession
        savedSession = nil   // audit A9: the results card is still on screen for its fade; it must not read a deleted row
        if let toDelete {
            // Once the results (which read it) have faded off — then it can go.
            Task { @MainActor in
                _ = await CircleGate.pause(CircleMomentTiming.outDone + CircleMotion.quick)
                SessionDeletion.delete([toDelete], in: context)
            }
        }
        SleepMorning.clear()
        let doze = Date().timeIntervalSince(r.lastTapAt ?? Date())
        savedSession = nil
        sleptSaved = false
        sleptDark = false
        sleepResume = nil
        sleepResumeReady = false
        startTime = r.startTime ?? Date()
        totalPauseInSession = r.totalPause + max(doze, 0)
        endTime = r.endTime?.addingTimeInterval(max(doze, 0))
        sharedState.targetCount = r.targetCount
        sharedState.selectedTask = r.task
        // The ring where it was (the stop emptied it; it used to wait for the next tap).
        if sharedState.selectedMode == 1 {
            if totalTime > 0 { progressFraction = CGFloat(Int(secsPassed + timeOffset)) / TimeInterval(totalTime) }   // the ticker's own
        } else {
            refreshCountProgress()
        }
        paused = false
        timerIsActive = true
        // The counter's dim on at once, under the results' own (fading with them): never a frame
        // without either — its usual 0.5 s fade-in was the bright flash (owner).
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { toggleInactivityTimer = true }
        startTicker()
        inactivityTimerHandler(run: "restart")
        updateIdleTimer()
        triggerSomeVibration(type: .light)
    }

    private func completeStopTimer() {
        print("ran a completeStopTimer().")
        
        // Stop and invalidate the timer
        timerbb?.invalidate()
        timerbb = nil
        ringAtStop = progressFraction   // the resets below empty the ring; the soft close lands it from here

        // Nothing counted, opened out of a Zikr ring (soft close, the app on screen): close while the pause screen is
        // still exactly as seen, and reset the rest once it's gone — reset first, the ring emptied, the pause screen
        // went and the counter showed through mid-fade (owner's recording, 2026-10-02).
        if sessionCount <= 0 && SessionHandoff.shared.soft && UIApplication.shared.applicationState == .active {
            inactivityTimerHandler(run: "stop")
            if !stoppedDueToInactivity && !endedAsleep && !countingHapticsOff { triggerSomeVibration(type: .vibrate) }
            SessionHandoff.shared.afterClose { finishStopReset() }
            isPresented = false
            return
        }
        
        // Reset all state variables to clean up the session
        endTime = nil
        startTime = nil
        // The ring stays where it stood: it goes out under the results as they come (emptied here, its arc wound back
        // as it faded — owner's "from ring to completion page"); a soft close lands it from here (`ringAtStop`).
        sharedState.targetCount = ""
        noteModalText = ""
        
        
        if !stoppedDueToInactivity && !endedAsleep && !countingHapticsOff {   // never buzz someone asleep
            triggerSomeVibration(type: .vibrate)
        }
        
        stoppedDueToInactivity = false
        endedAsleep = false
        inactivityTimerHandler(run: "stop")
        toggleInactivityTimer = false
        paused = false
        sleepResumeReady = sleepResume != nil
        goalFinishArmed = false
        if resumeWanted { resumeWanted = false; keepCountingAfterSleep() }
        
        
        if sessionCount <= 0 {
            isPresented = false
//            sharedState.showingOtherPages = false
            resetSharedState()
        }
    }

    /// Closing softly out of a wheel ring: the ring stays while the rest goes and its arc moves to where the wheel's
    /// will stand — today's share before the session plus what this one added (a Start over's count joins the earlier
    /// one, freestyle fills back up) — then, once the page has gone, fades over the wheel's identical one (decision
    /// zikr-ring-progress B).
    private func landRing() async {
        guard let base = landingBase, openingStyle != .fade, !reduceMotion else { return }
        landingBase = nil
        let stood = ringAtStop ?? progressFraction
        let landing = min(max(CGFloat(base) + stood - startFraction, 0), 1)
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { progressFraction = stood; ringHeld = true }
        await CircleMotion.animate(.easeInOut(duration: CircleMotion.arcMoveDuration)) {
            progressFraction = landing
            arcSettled = true
        }
    }

    /// The soft look's ring to its place (`ringLiftTarget`): a spring, or under Reduce Motion out, there, in.
    /// The wait is a task, never `.delay` on the spring: a delayed spring retargeted mid-move doesn't carry the move's
    /// speed (Sami's B1). A newer move cancels this one; each moves to the target as it is then.
    private func moveRing(to target: CGFloat, waitForCards: Bool) {
        ringMoveTask?.cancel()
        ringMoveTask = Task { @MainActor in
            if reduceMotion {
                await CircleMotion.animate(.easeOut(duration: CircleMotion.quick)) { ringDimmed = true }
                guard !Task.isCancelled else { return }
                await CircleMotion.animate(nil) { ringLift = ringLiftTarget }
                withAnimation(.easeIn(duration: CircleMotion.quick)) { ringDimmed = false }
                return
            }
            if waitForCards {
                guard await CircleGate.pause(CircleMotion.ringMoveDownDelay) else { return }
            }
            withAnimation(CircleMotion.ringMove) { ringLift = ringLiftTarget }
        }
    }

    /// Done on the soft results (ResultsView's Done).
    private func finishFromResults() {
        // Cleared once the session has gone: under a soft close the results are still fading.
        SessionHandoff.shared.afterClose {
            sharedState.titleForSession = ""
            sharedState.mantraForSession = nil   // audit A8: a stale pick outlived a deleted zikr
        }
        isPresented = false
    }

    /// completeStopTimer's resets, after a soft close with nothing counted (the cover is gone by then).
    private func finishStopReset() {
        endTime = nil
        startTime = nil
        progressFraction = 0
        sharedState.targetCount = ""
        noteModalText = ""
        stoppedDueToInactivity = false
        endedAsleep = false
        toggleInactivityTimer = false
        paused = false
        sleepResumeReady = sleepResume != nil
        goalFinishArmed = false
        resumeWanted = false
        resetSharedState()
    }
    
    /// The running session as a draft (audit A7): written on pause, on going inactive / background and every few
    /// counts; cleared when the session saves. A draft found at the next launch becomes a saved session.
    private func writeDraft() {
        guard timerIsActive, sessionCount > 0, let start = startTime else { return }
        let linkedTask = (sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr) ? sharedState.selectedTask : nil
        let picked = sharedState.mantraForSession
        let mantraID = (picked != nil && !picked!.isDeleted && picked!.modelContext != nil) ? picked!.id : nil
        SessionDraft.write(SessionDraft(
            title: sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled",
            mode: sharedState.selectedMode, targetMin: sharedState.selectedMinutes,
            targetCount: Int(sharedState.targetCount) ?? 0, count: sessionCount, startTime: start,
            secondsPassed: paused ? secsPassedAtPause : secsPassed, avgTimePerClick: newAvrgTPC, tasbeehRate: tasbeehRate,
            mantraID: mantraID, taskID: linkedTask?.id, postSalah: sharedState.isDoingPostNamazZikr, savedAt: Date()))
    }

    private func saveSession() -> SessionDataModel {
        print("ran a saveSession().")
        // Generate session data after the timer stops
        let placeholderTitle = (sharedState.titleForSession != "" ? sharedState.titleForSession : "Untitled")
        
        secsToReport = endedAsleep && secsAtLastTap > 0 ? secsAtLastTap : (paused ? secsPassedAtPause : secsPassed)
        
        // Only a session launched from a task card counts toward that task. Freestyle (mode 0)
        // and the post-salah sequence never link, even if a card is still "selected" underneath.
        let linkedTask = (sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr)
            ? sharedState.selectedTask : nil
        
        let item = SessionDataModel(
            title: placeholderTitle,
            sessionMode: sharedState.selectedMode,
            targetMin: sharedState.selectedMinutes,
            targetCount: Int(sharedState.targetCount) ?? 0,
            totalCount: sessionCount,
            startTime: startTime ?? Date(),
            secondsPassed: secsToReport,
            avgTimePerClick: newAvrgTPC,
            tasbeehRate: tasbeehRate,
            task: linkedTask,
            // Picked from a task/picker (or Tasbih Fatimah for post-salah) → we have the row.
            mantra: sharedState.mantraForSession ?? MantraModel.find(named: placeholderTitle, in: context)
        )
        item.endedAsleep = endedAsleep
        print("adding a session card")
        context.insert(item)
        SessionDraft.clear()   // saved for real (audit A7)
        // Finished the task for today: its reminder for today goes (ZikrReminders).
        if let linkedTask { ZikrReminders.taskMaybeDone(linkedTask, context: context) }
        return item
    }

    
    func resetSharedState(){
        print("ran a resetSharedState().")
//        sharedState.targetCount = ""
        sharedState.isDoingPostNamazZikr = false
        sharedState.targetCount = ""
        sharedState.selectedMinutes = 0
        sharedState.titleForSession = ""
        sharedState.mantraForSession = nil
        sharedState.selectedMode = 1
    }
    
    private func togglePause() {
        print("ran a togglePause().")
        paused.toggle()
        if paused { writeDraft() }   // audit A7
        if !paused { ZikrAudio.stopAll() }   // Resume: the pause card's memo stops
        updateIdleTimer()
        triggerSomeVibration(type: .medium)
        if(paused){
            inactivityTimerHandler(run: "stop")
            pauseStartTime = Date()
            secsPassedAtPause = secsPassed
            timePassedAtPauseString = formatTimePassed // cant use calc var bc keeps changing if view ever updated
        }else{
            inactivityTimerHandler(run: "restart")
            let thisPauseSesh = Date().timeIntervalSince(pauseStartTime ?? Date())
//            pauseSinceLastInc += thisPauseSesh
            totalPauseInSession += thisPauseSesh
            endTime = endTime?.addingTimeInterval(thisPauseSesh)
        }
        /*
         - store time at pause (pauseStartTime)
         - calculate time at resume (thisPauseSesh)
         - keep track of how many pauses since last increment (pauseSinceLastInc)
            > (use this to subtract pause time from tPC when incrementing)
         - add to totalPauseInSession
            > (only needed for reset so we can calculate tpc on first click)
         - extend endTime by thisPauseSesh
            
         move end time.
        
         */
    }
    
    private func incrementTasbeeh() {
        incrementTasbeeh(by: tapWorth)
    }

    /// One tap's worth of counts: 1, or the set size while counting in sets (one buzz either way).
    private func incrementTasbeeh(by step: Int) {
        if timerIsActive {
            let before = tasbeeh
            tasbeeh = min(tasbeeh + step, 10000) // Adjust maximum value as needed
            secsAtLastTap = secsPassed
            lastTapAt = Date()
            newAvrgTPC = (sessionCount > 0 ? (secsPassed / Double(sessionCount)) : 0)
            if sessionCount % 5 == 0 || step > 1 { writeDraft() }   // audit A7
            triggerSomeVibration(type: currentVibrationMode)
            if step > 1 && !countingHapticsOff {
                // Counting in sets: a quick ta-ta-ta instead of one tap, so it's felt, not just
                // seen (owner kept counting in sets after a pause without noticing).
                let tick = UIImpactFeedbackGenerator(style: .light)
                tick.prepare()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { tick.impactOccurred(intensity: 0.8) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { tick.impactOccurred(intensity: 0.6) }
            }
            // Every hundred crossed (a set can jump over the exact multiple).
            if tasbeeh / 100 > before / 100 && !countingHapticsOff { triggerSomeVibration(type: .error) }
            // A count goal ends on the tap that reaches it — the 0.1 s ticker let a quick double tap
            // save 34 of 33. A set that jumps past it (30 + 5) keeps its whole set: 35 (owner).
            if autoStop && sharedState.selectedMode == 2,
               let target = Int(sharedState.targetCount), target > 0, tasbeeh >= target {
                stopTimer()
            }
        }
    }
    
    private func decrementTasbeeh() {
        if timerIsActive {
            tasbeeh = max(tasbeeh - tapWorth, countOffset) // undoes one tap; never below where a continued task started
            secsAtLastTap = secsPassed
            lastTapAt = Date()
            newAvrgTPC = (sessionCount > 0 ? (secsPassed / Double(sessionCount)) : 0)
            if !countingHapticsOff { triggerSomeVibration(type: .rigid) }
        }
    }
    
    private func resetTasbeeh() { //not being used but just keeping incase need later
        if timerIsActive {
            tasbeeh = 0
            triggerSomeVibration(type: .error)
        }
    }
        
    
    // MARK: - Helper Structs (basically moved from Utils)
    
    /// After Finish (restyled 2026-09-25 to match the pause screen): a sage check that pops in,
    /// "saved to your history", the mantra card (tap to put the session on another mantra —
    /// not for a task's session, which stays on its task's mantra), the shared bento, and Done.
    struct ResultsView: View {
        @Environment(\.modelContext) private var context
        @EnvironmentObject var sharedState: SharedStateClass
        @Binding var isPresented: Bool
        let savedSession: SessionDataModel
        /// Only after a sleep finish: carry the same session on (he was only dozing).
        var keepCounting: (() -> Void)? = nil
        /// Saved by sleep mode: no buzz from the streak moment.
        var asleep = false

        @State private var showMantraPicker = false
        @State private var chosenMantraName: String? = ""
        @State private var chosenMantraObject: MantraModel? = nil
        @State private var checkShown = false
        @State private var showHistory = false

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
        private var isTasbihFatimah: Bool {
            (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        /// A task's session keeps its task's mantra; Tasbih Fatimah is always Tasbih Fatimah.
        private var locked: Bool {
            savedSession.task != nil || (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        private var title: String { savedSession.mantra?.name ?? savedSession.title }

        /// A task's session: where the task stands today ("5 of 100 today"), since a continued
        /// session saves only its own counts.
        /// Today's progress on the session's task, this session included (nil: not a task session).
        private var taskProgress: TaskProgress? {
            guard let task = savedSession.task else { return nil }
            let mine = task.sessions.filter { $0.startTime >= PrayerDay.sessionDayStart() }
            return TaskProgress(count: mine.reduce(0) { $0 + $1.totalCount },
                                seconds: mine.reduce(0) { $0 + $1.secondsPassed })
        }

        /// The streak moment: only after the session that finished the task's goal for today (it wasn't
        /// done without this session's counts).
        private var finishedStreak: TaskStreak? {
            guard let task = savedSession.task, let p = taskProgress, task.isCompleted(with: p),
                  savedSession.startTime >= PrayerDay.sessionDayStart() else { return nil }
            let before = TaskProgress(count: p.count - savedSession.totalCount, seconds: p.seconds - savedSession.secondsPassed)
            guard !task.isCompleted(with: before) else { return nil }
            let streak = task.streak()
            return streak.current > 0 ? streak : nil
        }

        /// The card's line for a task session: where the task stands, never this session's count again
        /// (the tile has it; owner: "it says 50 three times"). "Done for today" / "70 to go today", with
        /// the streak still to keep after it.
        private func taskLine(_ task: TaskModel, _ p: TaskProgress) -> Text {
            let prefix = task.mantraLine == nil ? Text("") : Text("\(task.title) · ")
            if task.isCompleted(with: p) {
                return prefix.foregroundStyle(.secondary) + Text("Done for today").foregroundStyle(Color.sage)
            }
            let left = task.isCountMode ? "\(task.goal - p.count) to go today"
                                        : "\(max(1, Int((Double(task.goal * 60) - p.seconds) / 60 + 0.5))) min to go today"
            var line = prefix + Text(left)
            let streak = task.streak()
            if streak.current > 0 {
                line = line + Text(" · ") + Text(Image(systemName: "flame")) + Text(" keeps your \(streak.current)")
            }
            return line.foregroundStyle(.secondary)
        }

        private var sessionLabel: String {
            switch savedSession.sessionMode {
            case 1: return "\(savedSession.targetMin) min session"
            case 2: return "\(savedSession.targetCount) count session"
            default: return "freestyle session"
            }
        }

        var body: some View {
            ZStack {
                Color("pauseColor")
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    Group {
                        if let streak = finishedStreak {
                            StreakResultsHero(streak: streak, quiet: asleep)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(Color.sage)
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(Color.sage.opacity(0.16)))
                                    .scaleEffect(checkShown ? 1 : 0.4)
                                    .opacity(checkShown ? 1 : 0)
                                Text("saved to your history")
                                    .font(.system(size: 17, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        mantraCard
                        ZikrBento(count: savedSession.totalCount, seconds: savedSession.secondsPassed,
                                  secondsPerCount: savedSession.avgTimePerClick,
                                  perTasbeeh: savedSession.tasbeehRate,
                                  usualSecondsPerCount: savedSession.mantra?.secondsPerCount(excluding: savedSession))
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)

                    if let keepCounting {
                        Button(action: keepCounting) {
                            Label("Keep counting", systemImage: "play.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(Color.sage)
                                .background(Capsule().fill(Color.sage.opacity(0.06)))
                                .overlay(Capsule().stroke(Color.sage.opacity(0.6), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }

                    Button {
                        triggerSomeVibration(type: .success)
                        // Cleared once the session has gone: under a soft close the results are still fading (their
                        // title would read "Untitled" mid-fade).
                        SessionHandoff.shared.afterClose {
                            sharedState.titleForSession = ""
                            sharedState.mantraForSession = nil   // audit A8: a stale pick outlived a deleted zikr
                        }
                        isPresented = false
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.sage)
                            .background(Capsule().fill(Color.sage.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Button {
                        triggerSomeVibration(type: .light)
                        showHistory = true
                    } label: {
                        Label("View zikr history", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
                .fontDesign(.rounded)
            }
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.15)) { checkShown = true }
            }
            .onChange(of: chosenMantraName) {
                guard let newName = chosenMantraName, !newName.isEmpty else { return }
                withAnimation {
                    sharedState.titleForSession = newName
                    sharedState.mantraForSession = chosenMantraObject
                    savedSession.title = newName   // the saved session moves to that mantra
                    savedSession.mantra = chosenMantraObject
                    do { try context.save() } catch { print("Error saving context: \(error)") }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryPageView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showHistory = false }
                            }
                        }
                }
            }
        }

        private var mantraCard: some View {
            Button { showMantraPicker = true } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title.isEmpty ? "choose a zikr" : title)
                                .font(.system(size: 24, weight: .light, design: .rounded))
                                .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if !locked {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Group {
                            if let task = savedSession.task, let p = taskProgress {
                                taskLine(task, p)
                            } else {
                                Text(isTasbihFatimah ? "33 · 33 · 34 after salah" : sessionLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(cardShape.fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .contentShape(cardShape)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!locked)   // not .disabled: that grayed the card out
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
            )
        )
        .environmentObject(SharedStateClass())
    }

    
    /// The pause screen (redesigned 2026-09-25 — owner: the bottom buttons "didn't feel on
    /// brand", keep the bento, and make the mantra's full text and notes reachable). Top to
    /// bottom: "paused · 33 count session", the mantra card (name → picker, the full mantra, notes,
    /// its quick-add step, ✎ → the mantra's page), the stats bento, the finish estimate, then
    /// labelled setting chips and Finish / Resume. Tapping the dimmed background still resumes.
    struct pauseScreen_StatsSettingsBG: View {
        /// Sleep mode's one-time intro (owner, decision sleep-intro): shown until "Turn on" once.
        @AppStorage(SleepMorning.introConfirmedKey) private var sleepIntroConfirmed = false
        @State private var showSleepIntro = false
        @State private var showGoalIntro = false
        @EnvironmentObject var sharedState: SharedStateClass
        let paused: Bool
        let mantra: MantraModel?
        let tasbeeh: Int
        let secsToReport: TimeInterval
        let newAvrgTPC: TimeInterval
        let tasbeehRate: String
        let togglePause: () -> Void
        let stopTimer: () -> Void
        let takingNotes: Bool
        @Binding var toggleInactivityTimer: Bool
        @Binding var inactivityDimmer: Double
        @Binding var autoStop: Bool
        @Binding var tasbeehColorMode: Bool
        let appLookDark: Bool
        /// Past the goal on "continuous": the chip is locked and Finish isn't "early".
        let goalReached: Bool
        @Binding var currentVibrationMode: HapticFeedbackType
        /// The ring-above layout (decision session-flow-build A): the counter's ring stays on screen, raised, and these
        /// cards sit round it; the same cards carry the results, the ring centred. Classic (Today's) keeps `todayBody`.
        /// The surfaces come from the theme's material (ThemedRaised / ThemedPressed).
        var ringAbove = false
        /// Seconds already done today when continuing a timed task (the "left" tile counts them).
        var timeOffset: TimeInterval = 0
        /// The finished session, under the soft look.
        var results: SoftResults? = nil
        /// The tiles and buttons are up: paused, the results in, or finishing from the pause screen (they hold still
        /// through it — only the ring moves).
        var cardsShown = false
        /// The results' words are in (after the counter's have gone).
        var resultsIn = false
        /// Where the ring stands while paused (global), and the bottom block's top (global): the session moves its ring.
        var onRingSlot: (CGRect) -> Void = { _ in }
        var onBottomTop: (CGFloat) -> Void = { _ in }
        /// The sleep chip's place (global): the sleep dim leaves it uncovered while paused.
        var onSleepChipFrame: (CGRect) -> Void = { _ in }

        /// What the soft cards need of a finished session.
        struct SoftResults {
            let session: SessionDataModel
            var keepCounting: (() -> Void)?
            let done: () -> Void
        }

        // UI state
        @State private var showHistory = false
        @State private var wellRoom: CGFloat = 148
        @State private var bottomInset: CGFloat = 0
        @State private var showingFinishTime = false
        /// The rate tile's side: per count, or per tasbeeh (a tap flips it).
        @State private var showingPerTasbeeh = false
        @State private var finishArmed = false
        @State private var finishArmToken = 0
        @State private var showMantraPicker = false
        @State private var chosenMantraName: String? = ""
        @State private var chosenMantraObject: MantraModel? = nil
        @State private var fullTextExpanded = false

        // Computed variables for est time completion (only for target count mode)
        private var remainingCount: Int{
            return (Int(sharedState.targetCount) ?? 0) - Int(tasbeeh)
        }
        private var timeLeft : TimeInterval{
            return newAvrgTPC * Double(remainingCount)
        }
        private var finishTime: Date{
            return Date().addingTimeInterval(timeLeft)
        }

        /// The session's goal for the goal page: "33" or "10 min".
        private var goalText: String {
            sharedState.selectedMode == 1 ? "\(sharedState.selectedMinutes) min" : sharedState.targetCount
        }
        /// "You have a count goal of 33" / "You have a time goal of 3 minutes" (owner: no zikr name).
        private var goalSubtitle: String {
            if sharedState.selectedMode == 1 {
                let m = sharedState.selectedMinutes
                return "You have a time goal of \(m) minute\(m == 1 ? "" : "s")"
            }
            return "You have a count goal of \(sharedState.targetCount)"
        }

        /// Count goal, not post-salah, started and not done: the bento adds the finish tile.
        private var showsFinishEstimate: Bool {
            sharedState.selectedMode == 2 && remainingCount > 0 && !sharedState.isDoingPostNamazZikr && tasbeeh > 0
        }

        private var sessionLabel: String {
            switch sharedState.selectedMode {
            case 1: return "\(sharedState.selectedMinutes) min session"
            case 2: return "\(sharedState.targetCount) count session"
            default: return "freestyle session"
            }
        }

        /// Launched from a task card: the session counts toward that task, so its mantra stays
        /// (same rule as `saveSession`'s task link).
        private var isTaskSession: Bool {
            sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr && sharedState.selectedTask != nil
        }
        /// Task and post-salah sessions keep their mantra; only free sessions can switch.
        private var mantraLocked: Bool { isTaskSession || sharedState.isDoingPostNamazZikr }

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
        /// The pause card's scroll view height: its content fills it, so empty space there resumes.
        @State private var scrollHeight: CGFloat = 0

        var body: some View {
            if ringAbove { softBody } else { todayBody }
        }

        @ViewBuilder private var todayBody: some View {
            Color("pauseColor")
                .edgesIgnoringSafeArea(.all)
                .animation(.easeOut(duration: 0.3), value: paused)
                .opacity(paused ? 1 : 0.0)
                .onTapGesture { togglePause() }
                .allowsHitTesting(paused)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill").font(.caption2)
                    Text(sharedState.isDoingPostNamazZikr ? "paused · Tasbih Fatimah" : "paused · \(sessionLabel)")
                }
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary)
                .padding(.top, 18)

                ScrollView {
                    VStack(spacing: 12) {
                        // Tasbih Fatimah is its own thing (owner): the three phrases and where the
                        // count is, instead of the mantra card (no edit, no count-in-sets).
                        if sharedState.isDoingPostNamazZikr {
                            PostSalahPauseCard(count: tasbeeh)
                        } else {
                            mantraCard
                        }
                        ZikrBento(count: tasbeeh, seconds: secsToReport, secondsPerCount: newAvrgTPC,
                                  perTasbeeh: tasbeehRate,
                                  finish: showsFinishEstimate ? (timeLeft, finishTime) : nil,
                                  usualSecondsPerCount: mantra?.secondsPerCount)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    // The empty space round and under the cards resumes too (owner): the scroll view
                    // took every tap in its frame. Behind the cards, so a tap on one stays on it.
                    .frame(minHeight: scrollHeight, alignment: .top)
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { togglePause() })
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

                controls
            }
            .fontDesign(.rounded)
            .opacity(paused ? 1.0 : 0.0)
            .animation(.easeInOut, value: paused)
            .allowsHitTesting(paused)
            .onChange(of: chosenMantraName) {
                if let newSetMantra = chosenMantraName, !newSetMantra.isEmpty {
                    withAnimation {
                        sharedState.mantraForSession = chosenMantraObject
                        sharedState.titleForSession = newSetMantra
                        fullTextExpanded = false
                    }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
        }

        // MARK: soft look (decision session-flow-build A)

        /// Paused, not finished: the pause screen's own words (header, name, text well, chips) are up.
        private var pauseShown: Bool { paused && results == nil }

        /// The soft pause screen and results, one layout: the counter's ring stays on screen — raised while paused
        /// (`onRingSlot`), centred once finished — and the tiles and buttons at the bottom are the same on both, so
        /// finishing from the pause screen moves only the ring. The page doesn't scroll: a long zikr scrolls inside
        /// its fixed well.
        @ViewBuilder private var softBody: some View {
            ZStack {
                // The empty page resumes (as the dimmed background did).
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { togglePause() }
                    .allowsHitTesting(pauseShown)

                VStack(spacing: 0) {
                    Spacer(minLength: 4)
                    softHeader
                        .frame(height: 22)
                        .modifier(SoftCardsFade(shown: pauseShown, delay: 0.22))
                    // Clear of the hundreds' beads round the ring's top where there's room; on a small phone it gives
                    // way first, so everything stays on the screen (Sami's B2 / B3: the SE pushed it under the clock).
                    Spacer(minLength: 14)
                        .frame(maxHeight: 50)
                    // Where the ring stands while paused: as low as the cards under it allow, so it travels as little
                    // as it can (owner: "so then the ring doesn't have to travel so far up the page").
                    Color.clear
                        .frame(width: 206, height: 206)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onRingSlot($0) }
                    VStack(spacing: 10) {
                        softNameRow
                        // It takes its height before the space above the ring does; with too little room for its text
                        // (a small phone, the largest text) it stays out of sight rather than squeezed.
                        softWell
                            .opacity(wellRoom >= 72 ? 1 : 0)
                            .frame(minHeight: 0, maxHeight: 148)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wellRoom = $0 }
                            .layoutPriority(1)
                    }
                    .padding(.top, 12)
                    // A tap among the zikr's name, its media and its text never resumes (only the page round them does):
                    // a near-miss on ▶︎ resumed the session (owner).
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .modifier(SoftCardsFade(shown: pauseShown, delay: 0.22))
                    .allowsHitTesting(pauseShown)
                    softBottom
                        .padding(.top, 14)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                // Finish early off the edge where there's no home indicator (an SE); elsewhere the safe area does it.
                .padding(.bottom, bottomInset > 0 ? 0 : 6)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
            .fontDesign(.rounded)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // fixed slots: past this the tiles and chips truncated
            .onChange(of: chosenMantraName) {
                if let newSetMantra = chosenMantraName, !newSetMantra.isEmpty {
                    withAnimation {
                        sharedState.mantraForSession = chosenMantraObject
                        sharedState.titleForSession = newSetMantra
                    }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryPageView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showHistory = false }
                            }
                        }
                }
            }
        }

        /// "paused · 100 count session"; with sleep on, its dimmer in the same place (nothing else moves).
        @ViewBuilder private var softHeader: some View {
            // (The dimmer lives on the sleep page now — decision sleep-dimmer-place A; it sat here, at the top.)
            do {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill").font(.caption2)
                    Text(sharedState.isDoingPostNamazZikr ? "paused · Tasbih Fatimah" : "paused · \(sessionLabel)")
                }
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary)
            }
        }

        /// Under the ring: the zikr's name (→ the picker on a free session), "from your task", its memo and photo.
        private var softNameRow: some View {
            let title = sharedState.isDoingPostNamazZikr ? PostSalahTasbeeh.mantraName : sharedState.titleForSession
            return VStack(spacing: 2) {
                Button { showMantraPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(title.isEmpty ? "choose a zikr" : title)
                            .font(.system(size: 24, weight: .light, design: .rounded))
                            .foregroundStyle(title.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !mantraLocked {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!mantraLocked)   // not .disabled: that grayed the name out
                HStack(spacing: 12) {
                    if sharedState.isDoingPostNamazZikr {
                        Text("33 · 33 · 34 after salah")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isTaskSession {
                        Label("from your task", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let mantra, !sharedState.isDoingPostNamazZikr {
                        ZikrMediaStrip(mantra: mantra, paused: paused, compact: true)
                    }
                }
                .frame(minHeight: 24)
            }
        }

        /// The zikr's full text and notes in a well pressed into the page, a fixed height: long ones scroll inside it.
        /// Count in sets is its last row, as it was the card's.
        private var softWell: some View {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            return VStack(spacing: 0) {
                ScrollView {
                    Group {
                        if sharedState.isDoingPostNamazZikr {
                            PostSalahPauseCard(count: tasbeeh, bare: true)
                        } else {
                            softWellText
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center, for: .alignment)   // a short zikr sits in the middle of the well
                .defaultScrollAnchor(.top, for: .initialOffset)  // a long one starts at its top
                if !sharedState.isDoingPostNamazZikr {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                    QuickAddStepRow(mantra: mantra)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }
            .background(ThemedPressed(shape: shape))
            .clipShape(shape)
        }

        @ViewBuilder private var softWellText: some View {
            if let mantra {
                let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                VStack(spacing: 10) {
                    if !full.isEmpty {
                        // Arabic lines in the Uthmani face, the rest (transliteration, meaning) in the light rounded type.
                        VStack(spacing: 6) {
                            ForEach(Array(full.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let text = line.trimmingCharacters(in: .whitespaces)
                                if !text.isEmpty {
                                    let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                                    Text(text)
                                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: 26) : .system(size: 15, weight: .light, design: .rounded))
                                        .foregroundStyle(arabic ? .primary : .secondary)
                                        .lineSpacing(arabic ? 8 : 2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                            Text(notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                    if full.isEmpty && notes.isEmpty {
                        Text("no full text or notes yet — add them on its page")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(sharedState.titleForSession.isEmpty ? "its full text, notes and sets show up here" : "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: soft bottom block — the same on the pause screen and the results

        /// The finished session's values once it's saved, else the running session's.
        private var shownSeconds: TimeInterval { results?.session.secondsPassed ?? secsToReport }
        private var shownPerCount: Double { results?.session.avgTimePerClick ?? newAvrgTPC }
        private var shownPerTasbeeh: String { results?.session.tasbeehRate ?? tasbeehRate }
        private var shownUsualPace: Double? {
            if let s = results?.session { return s.mantra?.secondsPerCount(excluding: s) }
            return mantra?.secondsPerCount
        }

        /// The third tile while paused: what's left (a count goal: time left ⇄ the finish time; a time goal: time left
        /// ⇄ when it ends), else the pace per tasbeeh (freestyle, Tasbih Fatimah, past the goal).
        private enum ThirdTile { case left(TimeInterval, Date), toGo(Int), counted }
        private var thirdTile: ThirdTile {
            if !sharedState.isDoingPostNamazZikr && !goalReached {
                if sharedState.selectedMode == 2 && remainingCount > 0 {
                    return tasbeeh > 0 && newAvrgTPC > 0 ? .left(timeLeft, finishTime) : .toGo(remainingCount)
                }
                if sharedState.selectedMode == 1 {
                    let left = max(0, Double(sharedState.selectedMinutes * 60) - secsToReport - timeOffset)
                    if left > 0 { return .left(left, Date().addingTimeInterval(left)) }
                }
            }
            return .counted
        }

        private var softBottom: some View {
            let finished = results != nil
            let pace = ZikrBento.paceComparison(secondsPerCount: shownPerCount, usual: shownUsualPace, perCount: true)
            let pacePerTasbeeh = ZikrBento.paceComparison(secondsPerCount: shownPerCount, usual: shownUsualPace, perCount: false)
            return VStack(spacing: 0) {
                HStack(spacing: 10) {
                    softTile("time") { softValue(timerStyle(shownSeconds)) }
                    // The rate tile says how it compares with your usual pace inside it (owner: "the comparison text …
                    // to be in the rate tile"), and flips per count ⇄ per tasbeeh (100 counts) on a tap, as the old pause
                    // screen's rate did (owner: "we lost per tasbeeh rate").
                    Button {
                        triggerSomeVibration(type: .medium)
                        withAnimation(.easeInOut(duration: CircleMotion.quick)) { showingPerTasbeeh.toggle() }
                    } label: {
                        softTile(showingPerTasbeeh ? "per tasbeeh" : "per count", flips: true) {
                            ZStack {
                                rateLines(value: String(format: "%.2fs", shownPerCount), pace: pace)
                                    .opacity(showingPerTasbeeh ? 0 : 1)
                                rateLines(value: shownPerTasbeeh, pace: pacePerTasbeeh)
                                    .opacity(showingPerTasbeeh ? 1 : 0)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    ZStack {
                        softThirdTile
                            .modifier(SoftCardsFade(shown: !finished, delay: 0))
                        softTile("counted") { softValue((results?.session.totalCount ?? 0).formatted()) }
                            .modifier(SoftCardsFade(shown: finished, delay: 0.1))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { onBottomTop($0) }

                // The chips while paused; after a sleep finish, Keep counting in their place.
                ZStack {
                    if !sharedState.isDoingPostNamazZikr {
                        chipsRow
                            .modifier(SoftCardsFade(shown: pauseShown, delay: 0))
                            .allowsHitTesting(pauseShown)
                    }
                    if let keepCounting = results?.keepCounting {
                        Button(action: keepCounting) {
                            Label("Keep counting", systemImage: "play.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(Color.sage)
                                .background(Capsule().fill(Color.sage.opacity(0.06)))
                                .overlay(Capsule().stroke(Color.sage.opacity(0.6), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .modifier(SoftCardsFade(shown: resultsIn, delay: 0))
                    }
                }
                .frame(height: 62)
                .padding(.top, 14)

                // Resume ⇄ Done in one capsule that stays put; only its words change.
                Button {
                    if let results {
                        triggerSomeVibration(type: .success)
                        results.done()
                    } else {
                        togglePause()
                    }
                } label: {
                    ZStack {
                        Label("Resume", systemImage: "play.fill")
                            .modifier(SoftCardsFade(shown: !finished, delay: 0))
                        // In as "Resume" finishes going (0.12 s): the capsule is never bare (Sami's B5).
                        Text("Done")
                            .fontWeight(.semibold)
                            .modifier(SoftCardsFade(shown: finished, delay: 0.1))
                    }
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.sage)
                    .frame(width: 210, height: 52)
                    .background(Capsule().fill(Color.sage.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .allowsHitTesting(pauseShown || (finished && resultsIn))

                // Finish early ⇄ View zikr history, low, clear of the edge.
                Button {
                    if finished {
                        triggerSomeVibration(type: .light)
                        showHistory = true
                    } else {
                        finishTap()
                    }
                } label: {
                    ZStack {
                        finishLabel
                            .modifier(SoftCardsFade(shown: !finished, delay: 0))
                        Label("View zikr history", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                            .modifier(SoftCardsFade(shown: finished, delay: 0.1))
                    }
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.3), value: finishArmed)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .allowsHitTesting(pauseShown || (finished && resultsIn))
            }
            .modifier(SoftCardsFade(shown: cardsShown, delay: 0.12))
            .animation(.snappy(duration: 0.25), value: toggleInactivityTimer)
        }

        @ViewBuilder private var softThirdTile: some View {
            switch thirdTile {
            case .left(let left, let at):
                Button {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingFinishTime.toggle() }
                } label: {
                    softTile(showingFinishTime ? "finish" : "left", flips: true) {
                        ZStack {
                            softValue(String(inMinSecStyle2(from: left).dropFirst(3)))
                                .opacity(showingFinishTime ? 0 : 1)
                            softValue(shortTime(at))
                                .opacity(showingFinishTime ? 1 : 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            case .toGo(let n):
                softTile("to go") { softValue(n.formatted()) }
            case .counted:
                // No goal to count down to (freestyle, Tasbih Fatimah, past the goal): the session's whole count — the ring
                // shows only the last hundred. (It was "per tasbeeh", now the rate tile's other side.)
                softTile("counted") { softValue(tasbeeh.formatted()) }
            }
        }

        /// The rate tile's value with the pace line under it.
        @ViewBuilder private func rateLines(value: String, pace: (text: String, faster: Bool?)?) -> some View {
            VStack(spacing: 3) {
                softValue(value)
                if let pace {
                    Text(pace.text)
                        .font(.system(size: 11, weight: pace.faster == true ? .medium : .regular, design: .rounded))
                        .foregroundStyle(pace.faster == true ? Color.sage : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
            }
        }

        /// A tile raised off the page: its caption over its value (the rate's comparison under it, inside). One height for
        /// all three, with or without that line.
        private func softTile<Content: View>(_ caption: String, flips: Bool = false,
                                             @ViewBuilder value: () -> Content) -> some View {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                    if flips {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                value()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(ThemedRaised(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 6, offset: 3))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private func softValue(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 22, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 8)
        }

        // MARK: mantra card

        private var mantraCard: some View {
            let title = sharedState.titleForSession
            return VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Button { showMantraPicker = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(title.isEmpty ? "choose a zikr" : title)
                                    .font(.system(size: 24, weight: .light, design: .rounded))
                                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                if !mantraLocked {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if isTaskSession {
                                Label("from your task", systemImage: "checklist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!mantraLocked)   // not .disabled: that grayed the name out
                    Spacer(minLength: 8)
                    if let mantra {
                        // The voice memo and photo, a tap away (owner, #17). No editing from the pause
                        // screen (owner, 2026-09-29): a zikr is edited on its own page.
                        ZikrMediaStrip(mantra: mantra, paused: paused, compact: true)
                    }
                }

                if let mantra {
                    let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !full.isEmpty {
                        // Arabic lines in the Uthmani face, the rest (transliteration,
                        // meaning) in the app's light rounded type.
                        VStack(spacing: 6) {
                            ForEach(Array(full.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let text = line.trimmingCharacters(in: .whitespaces)
                                if !text.isEmpty {
                                    let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                                    Text(text)
                                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: 26) : .system(size: 15, weight: .light, design: .rounded))
                                        .foregroundStyle(arabic ? .primary : .secondary)
                                        .lineSpacing(arabic ? 8 : 2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .lineLimit(fullTextExpanded ? nil : 4)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: fullTextExpanded ? nil : 190, alignment: .top)
                        .clipped()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy) { fullTextExpanded.toggle() }
                        }
                    }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                            Text(notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                } else if title.isEmpty {
                    Text("its full text, notes and sets show up here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                QuickAddStepRow(mantra: mantra)
                    .font(.subheadline)
            }
            .padding(16)
            .background(cardShape.fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }

        // MARK: controls

        private var controls: some View {
            VStack(spacing: 14) {
                // (The dimmer lives on the sleep page now — decision sleep-dimmer-place A.)
                // Tasbih Fatimah: just Finish / Resume (owner: none of the settings chips).
                if !sharedState.isDoingPostNamazZikr {
                    chipsRow
                }
                // One button: Resume (owner, 2026-09-26: two big buttons side by side made the
                // coloured one feel like "end" — he was scared to press it). Finishing is a small
                // secondary "Finish early" underneath, still two taps: the first turns it green,
                // "Tap again to finish", the second finishes; it disarms after 3 s.
                VStack(spacing: 6) {
                    // A green edge and green text, not a filled bar (owner: the full green bar felt
                    // heavy), centred, not edge to edge.
                    Button { togglePause() } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.sage)
                            .frame(width: 210, height: 52)
                            .background(Capsule().fill(Color.sage.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    Button { finishTap() } label: {
                        finishLabel
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        // Just round its words: the empty sides of the bottom resume (owner), and a
                        // stray tap there mustn't arm Finish.
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.3), value: finishArmed)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(.snappy(duration: 0.25), value: toggleInactivityTimer)
        }

        /// Finish early: the first tap turns it green, "Tap again to finish"; the second finishes; it disarms after 3 s.
        private func finishTap() {
            if finishArmed {
                triggerSomeVibration(type: .medium)
                finishArmed = false
                stopTimer()
            } else {
                triggerSomeVibration(type: .light)
                finishArmToken += 1
                let token = finishArmToken
                finishArmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if token == finishArmToken { finishArmed = false }
                }
            }
        }

        private var finishLabel: some View {
            ZStack {
                Text(goalReached ? "Finish" : "Finish early")   // past the goal it isn't early
                    .foregroundStyle(.secondary)
                    .opacity(finishArmed ? 0 : 1)
                    .blur(radius: finishArmed ? 3 : 0)
                Text("Tap again to finish")
                    .foregroundStyle(Color.green)
                    .opacity(finishArmed ? 1 : 0)
                    .blur(radius: finishArmed ? 0 : 3)
            }
        }

        /// continuous (lit) / stops at goal (plain), sleep, haptics — each a chip, the first two with an (i).
        private var chipsRow: some View {
            HStack(spacing: 8) {
                if sharedState.selectedMode != 0 {   // freestyle has no goal to stop at
                    // Locked once the goal is passed (owner): switching back ended the session the
                    // moment it resumed.
                    // One name, lit when on (decision chip-continuous A, owner): continuous = it keeps counting past the
                    // goal; plain = it stops at the goal — like the sleep and haptics chips beside it.
                    chip("continuous", icon: "arrow.clockwise", on: !autoStop, locked: goalReached) { autoStop.toggle() }
                    .overlay(alignment: .topTrailing) { infoButton("About continuous", on: !autoStop) { showGoalIntro = true } }
                    .fullScreenCover(isPresented: $showGoalIntro) {
                        GoalIntroView(autoStop: $autoStop, locked: goalReached, goal: goalText,
                                      subtitle: goalSubtitle) { showGoalIntro = false }
                    }
                }
                chip("sleep", icon: toggleInactivityTimer ? "moon.zzz.fill" : "moon.zzz", on: toggleInactivityTimer) {
                    // The first time (until confirmed once): the intro, which turns it on.
                    if !toggleInactivityTimer && !sleepIntroConfirmed { showSleepIntro = true; return }
                    toggleInactivityTimer.toggle()
                    // On: dark. Off: back to the app's own look (there's no light / dark chip).
                    tasbeehColorMode = toggleInactivityTimer ? true : appLookDark
                }
                // Where it is, for the dim to leave it uncovered (always findable to turn sleep off — owner).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onSleepChipFrame($0) }
                // (i) in the chip's corner: the intro again, any time (owner).
                .overlay(alignment: .topTrailing) { infoButton("About sleep mode", on: toggleInactivityTimer) { showSleepIntro = true } }
                .fullScreenCover(isPresented: $showSleepIntro) {
                    SleepIntroView(isOn: toggleInactivityTimer, dimmer: $inactivityDimmer, onTurnOn: {
                        sleepIntroConfirmed = true
                        toggleInactivityTimer = true
                        tasbeehColorMode = true
                        showSleepIntro = false
                    }, onNotNow: { showSleepIntro = false })
                    .interactiveDismissDisabled()
                }
                hapticsChip
            }
        }

        /// The phone with waves either side: one wave lit for light taps, two for medium, all
        /// three for strong (the symbols' variable value). A change only steps the lit waves to
        /// the new level (owner, A1399C45: the full inner-to-outer ripple on every tap was too long);
        /// the phone stays still (owner, A7B8CB0A: "the waves is enough"). Silent: the waves fade out;
        /// back to light, the first returns.
        private var hapticsChip: some View {
            let level: Double = switch currentVibrationMode {
            case .off: 0
            case .light: 0.2     // a wave lights once the value passes 0, ⅓, ⅔
            case .heavy: 1
            default: 0.5
            }
            return Button {
                withAnimation(.snappy(duration: CircleMotion.quick)) { cycleHaptics() }
            } label: {
                VStack(spacing: 6) {
                    // Our own "iphone.radiowaves": the phone between two three-wave symbols
                    // (the stock one has only two waves a side, so medium = strong).
                    HStack(spacing: 1) {
                        Image(systemName: "wave.3.left", variableValue: level)
                            .opacity(currentVibrationMode == .off ? 0 : 1)
                        Image(systemName: "iphone")
                            .font(.system(size: 17, weight: .light))
                        Image(systemName: "wave.3.right", variableValue: level)
                            .opacity(currentVibrationMode == .off ? 0 : 1)
                    }
                    .font(.system(size: 11, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 20)
                    Text(hapticLabel)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(Color.primary.opacity(currentVibrationMode == .off ? 0.45 : 0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if ringAbove {
                        ThemedRaised(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 5, offset: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        private var hapticLabel: String {
            switch currentVibrationMode {
            case .off: return "silent"
            case .light: return "light taps"
            case .heavy: return "strong taps"
            default: return "medium taps"
            }
        }

        private func cycleHaptics() {
            switch currentVibrationMode {
            case .off: currentVibrationMode = .light
            case .light: currentVibrationMode = .medium
            case .medium: currentVibrationMode = .heavy
            case .heavy: currentVibrationMode = .off
            default: currentVibrationMode = .medium
            }
            triggerSomeVibration(type: currentVibrationMode)
        }

        /// A labelled setting: symbol over a short word, soft tile; sage while on.
        /// A chip's (i) in its top-right corner: opens its explainer page; its own tap target, so the
        /// chip underneath doesn't switch.
        private func infoButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button {
                triggerSomeVibration(type: .light)
                action()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(on ? Color.sage.opacity(0.8) : Color.primary.opacity(0.4))
                    .padding(7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }

        private func chip(_ title: String, icon: String, on: Bool, locked: Bool = false, action: @escaping () -> Void) -> some View {
            Button {
                guard !locked else { return }
                triggerSomeVibration(type: .light)
                withAnimation(.snappy(duration: CircleMotion.quick)) { action() }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .light))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 20)
                    Text(title)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(on ? Color.sage : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if ringAbove && !on {
                        ThemedRaised(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), radius: 5, offset: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(locked ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint(locked ? "Locked once the goal is reached" : "")
        }

    }

    
    struct TopOfSessionButton: View{
        var symbol: String? = nil   // an SF Symbol…
        var text: String? = nil     // …or a short label like "+10"
        let actionToDo: () -> Void
        let paused: Bool
        let togglePause: () -> Void
        /// A switched-on toggle (count in sets): green label on a green tint with a green edge.
        var active = false

        init(symbol: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void) {
            self.symbol = symbol; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
        }
        init(text: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void, active: Bool = false) {
            self.text = text; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
            self.active = active
        }
        
        var body: some View{
            Button(action: paused ? togglePause : actionToDo) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 20, height: 20)
                    } else {
                        Text(text ?? "")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(minWidth: 20, minHeight: 20)
                    }
                }
                    .foregroundColor(active ? .green : .gray.opacity(0.3))
                    .padding()
                    .background(paused ? .clear : (active ? Color.green.opacity(0.14) : .gray.opacity(0.08)))
                    .cornerRadius(100)
                    .overlay(Capsule().strokeBorder(Color.green.opacity(active && !paused ? 0.6 : 0), lineWidth: 1))
                    .opacity(paused ? 0 : 1.0)
            }
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
    
    struct PlayPauseButton: View {
        let togglePause: () -> Void
        let paused: Bool
        
        var body: some View {
            // eventually use this to toggle the settings modal that replaces the pause stats modal.
            /*
            if paused{
                Button(action: togglePause) {
                    Image(systemName: "gear")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray.opacity(0.8))
                        .padding()
                        .background(/*paused ? .clear : */.gray.opacity(0.08))
                        .cornerRadius(10)
                }
            }
             */
            Button(action: togglePause) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(paused ? .gray.opacity(0.8) : .gray.opacity(0.3))
                    .padding()
                    .background(/*paused ? .clear : */.gray.opacity(0.08))
                    .cornerRadius(10)
            }
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
    
    

    
}


/// Post-salah zikr (redesigned 2026-09-25): one 100-count session — Subhanallah ×33,
/// Alhamdulillah ×33, Allahu Akbar ×34 — saved once, under a "Tasbih Fatimah" mantra (the
/// traditional name for it), instead of three chained sessions that each reset the count, saved
/// separately and ended without a results screen. The phrase follows the count.
enum PostSalahTasbeeh {
    static let mantraName = "Tasbih Fatimah"
    static let phases: [(name: String, arabic: String, count: Int)] = [
        ("Subhanallah", "سُبْحَانَ ٱللَّٰهِ", 33),
        ("Alhamdulillah", "ٱلْحَمْدُ لِلَّٰهِ", 33),
        ("Allahu Akbar", "ٱللَّٰهُ أَكْبَرُ", 34),
    ]
    static var total: Int { phases.reduce(0) { $0 + $1.count } }

    /// The phrase at a total count, and how far into it (0-based index; `done` of `of`).
    static func phase(at count: Int) -> (index: Int, done: Int, of: Int) {
        var start = 0
        for (i, p) in phases.enumerated() {
            if count < start + p.count || i == phases.count - 1 {
                return (i, min(count - start, p.count), p.count)
            }
            start += p.count
        }
        return (0, 0, phases[0].count)
    }

    /// Sets up the session: a 100-count goal on the Tasbih Fatimah mantra (made on first use,
    /// with the three phrases as its full text so the pause card shows them).
    static func prepare(_ state: SharedStateClass, in context: ModelContext) {
        let mantra = MantraModel.find(named: mantraName, in: context) ?? {
            let text = phases.map { "\($0.arabic)  ×\($0.count)" }.joined(separator: "\n")
                + "\nSubhanallah · Alhamdulillah · Allahu Akbar"
            let new = MantraModel(name: mantraName, fullText: text,
                                  notes: "After each obligatory prayer: 33, 33 and 34 — 100 in all.")
            new.builtInID = BuiltInAzkar.key(BuiltInAzkar.tasbihFatimahName)
            context.insert(new)
            return new
        }()
        state.selectedMode = 2
        state.selectedMinutes = 0
        state.targetCount = String(total)
        state.mantraForSession = mantra
        state.titleForSession = mantra.name
    }
}

/// Under the circle during post-salah zikr: why it's worth the minute (owner asked for a
/// reminder of its significance). Both narrations are the well-known ones: the 33/33/34 after
/// each obligatory prayer (Sahih Muslim, from Ka'b ibn 'Ujrah) and the Prophet ﷺ teaching the
/// same words to Fatimah as better than a servant (Bukhari and Muslim, from 'Ali).
struct PostSalahReminder: View {
    var variant = 0

    /// Why this zikr matters, to move people to do it (owner): a short headline — the reason — and
    /// the narration behind it. One per session. Well-known narrations, paraphrased; no hadith
    /// numbers until checked.
    static let reminders: [(title: String, text: String, source: String)] = [
        ("Never let down",
         "Whoever says these after every obligatory prayer is never disappointed.",
         "Sahih Muslim"),
        ("Keep pace with the best",
         "The poor feared the wealthy were ahead of them in charity. The Prophet ﷺ gave them these words after every prayer: no one would surpass them, except one who did the same.",
         "Sahih al-Bukhari · Sahih Muslim"),
        ("They fill the scales",
         "Alhamdulillah fills the Scale, and Subhanallah with Alhamdulillah fill what is between the heavens and the earth.",
         "Sahih Muslim"),
        ("Better than a servant",
         "Worn out by her work, Fatimah asked for a servant. The Prophet ﷺ gave her these hundred words instead, and said they were better for her.",
         "Sahih al-Bukhari · Sahih Muslim"),   // its text doesn't say when — it was taught for bedtime
    ]
    static var count: Int { reminders.count }

    var body: some View {
        let r = Self.reminders[variant % Self.count]
        VStack(spacing: 8) {
            // Quieter than the count (owner: in dark mode it read bright white).
            Text(r.title)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(0.5))
            Text(r.text)
                .font(.footnote.weight(.light))
                .foregroundStyle(.primary.opacity(0.36))
            Text(r.source)
                .font(.caption2)
                .foregroundStyle(Color.sage.opacity(0.75))
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .fontDesign(.rounded)
    }
}

/// The pause screen's card for Tasbih Fatimah: the three phrases as rows — done ✓, the current
/// one with its count, the rest to come — plus the hadith's line. Replaces the mantra card
/// (nothing to edit here; owner: "it's a special one").
struct PostSalahPauseCard: View {
    let count: Int
    /// Inside the soft pause screen's text well: no name (the name row has it) and no card of its own.
    var bare = false

    var body: some View {
        if bare {
            content.padding(12)
        } else {
            content
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
    }

    private var content: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        return VStack(alignment: .leading, spacing: 14) {
            if !bare {
            Text(PostSalahTasbeeh.mantraName)
                .font(.system(size: 24, weight: .light, design: .rounded))
            }
            VStack(spacing: 8) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, phrase in
                    let done = i < now.index || (i == now.index && now.done >= now.of)
                    let current = i == now.index && !done
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phrase.name)
                                .font(.system(size: 16, weight: current ? .regular : .light, design: .rounded))
                                .foregroundStyle(current ? .primary : .secondary)
                            Text(done ? "done" : current ? "\(now.done) of \(phrase.count)" : "\(phrase.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(done ? Color.green : .secondary)
                        }
                        Spacer(minLength: 8)
                        Text(phrase.arabic)
                            .font(.custom("KFGQPCUthmanTahaNaskh", size: 24))
                            .foregroundStyle(current ? .primary : .secondary)
                            .environment(\.layoutDirection, .rightToLeft)
                        Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(done ? Color.green : current ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(width: 22)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(current ? Color.green.opacity(0.08) : Color.primary.opacity(0.03))
                    )
                }
            }
            Text("Never disappointed — Sahih Muslim")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Above the circle during post-salah zikr: the current phrase (Arabic + name), its own count,
/// and three segments that fill phrase by phrase.
struct PostSalahPhaseStrip: View {
    let count: Int

    var body: some View {
        let now = PostSalahTasbeeh.phase(at: count)
        let phrase = PostSalahTasbeeh.phases[now.index]
        VStack(spacing: 8) {
            Text(phrase.arabic)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 30))
                .id(now.index)
                .transition(.blurReplace)
            HStack(spacing: 6) {
                Text(phrase.name)
                Text("·").foregroundStyle(.tertiary)
                Text("\(now.done) of \(now.of)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(now.done)))
            }
            .font(.subheadline.weight(.light))
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(PostSalahTasbeeh.phases.enumerated()), id: \.offset) { i, p in
                    let fill: Double = i < now.index ? 1 : i > now.index ? 0 : Double(now.done) / Double(p.count)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.sage).frame(width: geo.size.width * fill)
                        }
                    }
                    .frame(width: 44, height: 4)
                }
            }
        }
        .fontDesign(.rounded)
        .animation(.snappy(duration: 0.3), value: count)
    }
}

/// Count, time and rate as glass tiles (same material and light rounded type as the pause
/// screen's mantra card), shared by the pause and results screens. Count and time stacked on
/// the left, rate on the right — tap it to flip per count ↔ per tasbeeh. With `finish` (a count goal in progress) a full-width tile underneath says when
/// you'll be done — "in 1m 20s", tap → "6:42 PM" — a tile so it reads as something to tap
/// (owner, 2026-09-25; it used to be loose caption text under the boxes).
/// The soft look's session ring (and its count) lifted to where the session wants it (decision session-flow-build A);
/// nil = untouched — Today's look gets no offset at all, so its pixels can't move.
struct RingLift: ViewModifier {
    let lift: CGFloat?
    var dimmed = false

    func body(content: Content) -> some View {
        if let lift {
            content.offset(y: lift).opacity(dimmed ? 0 : 1)
        } else {
            content
        }
    }
}

/// The soft session cards' words going and coming (decision session-flow-build A): out quick, in a little slower and,
/// where they'd meet the moving ring, a beat late — out, then in.
struct SoftCardsFade: ViewModifier {
    let shown: Bool
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .animation(shown ? .easeOut(duration: CircleMomentTiming.in).delay(delay) : .easeOut(duration: CircleMotion.cardsOutDuration),
                       value: shown)
    }
}

/// The finished session in the soft look's centred ring, as the Zikr wheel will show it (decision session-flow-build A,
/// owner: "content inside of the circle could instead be the title of the task"): the task's title and "done today" /
/// where it stands; a free session's zikr with ⌄ (the picker moves the saved session). Above the ring, "Saved to your
/// history" and, after the session that kept it, the streak.
struct SessionDoneFace: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var sharedState: SharedStateClass
    let session: SessionDataModel

    @State private var showMantraPicker = false
    @State private var chosenMantraName: String? = ""
    @State private var chosenMantraObject: MantraModel? = nil

    private var isTasbihFatimah: Bool { (session.mantra?.name ?? session.title) == PostSalahTasbeeh.mantraName }
    private var locked: Bool { session.task != nil || isTasbihFatimah }

    /// Today's progress on the session's task, this session included.
    private var taskProgress: TaskProgress? {
        guard let task = session.task else { return nil }
        let mine = task.sessions.filter { $0.startTime >= PrayerDay.sessionDayStart() }
        return TaskProgress(count: mine.reduce(0) { $0 + $1.totalCount },
                            seconds: mine.reduce(0) { $0 + $1.secondsPassed })
    }

    /// The streak, only after the session that finished the task's goal for today (as the results' hero).
    private var finishedStreak: TaskStreak? {
        guard let task = session.task, let p = taskProgress, task.isCompleted(with: p),
              session.startTime >= PrayerDay.sessionDayStart() else { return nil }
        let before = TaskProgress(count: p.count - session.totalCount, seconds: p.seconds - session.secondsPassed)
        guard !task.isCompleted(with: before) else { return nil }
        let streak = task.streak()
        return streak.current > 0 ? streak : nil
    }

    /// The task's own name, else the zikr's; a free session with none picked ("Untitled") asks for one.
    private var title: String {
        if let task = session.task { return task.title }
        if let name = session.mantra?.name { return name }
        return session.title == "Untitled" ? "" : session.title
    }

    var body: some View {
        face
            .frame(width: 200, height: 200)
            // Above the ring, its bottom 22 pt over the ring's top: it moves with the ring.
            .overlay(alignment: .top) {
                header
                    .fixedSize()
                    .alignmentGuide(.top) { $0[.bottom] + 22 }
            }
            .onChange(of: chosenMantraName) {
                guard let newName = chosenMantraName, !newName.isEmpty else { return }
                withAnimation {
                    sharedState.titleForSession = newName
                    sharedState.mantraForSession = chosenMantraObject
                    session.title = newName   // the saved session moves to that zikr
                    session.mantra = chosenMantraObject
                    do { try context.save() } catch { print("Error saving context: \(error)") }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
    }

    /// The wheel's face (ZikrCircleFace): the title, the zikr under a task's own name, then where it stands.
    private var face: some View {
        VStack(spacing: 4) {
            Button { showMantraPicker = true } label: {
                HStack(spacing: 6) {
                    Text(title.isEmpty ? "choose a zikr" : title)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .foregroundStyle(title.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                    if !locked {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!locked)
            if let task = session.task, let line = task.mantraLine {
                Text(line)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 150)
                    .padding(.top, -3)
            }
            subtitle
                .font(.subheadline)
                .fontWeight(.thin)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 150)
        }
        .fontDesign(.rounded)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // inside the ring: the largest sizes ran out of it (Sami's B3)
    }

    @ViewBuilder private var subtitle: some View {
        if let task = session.task, let p = taskProgress {
            if task.isCompleted(with: p) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("done today")
                }
                .foregroundStyle(Color.sage)
            } else {
                Text(task.isCountMode ? "\(p.count) of \(task.goal)" : "\(Int(p.seconds / 60)) of \(task.goal) min")
                    .foregroundStyle(.secondary)
            }
        } else if isTasbihFatimah {
            Text("33 · 33 · 34 after salah").foregroundStyle(.secondary)
        } else {
            Text(session.sessionMode == 1 ? "\(session.targetMin) min session"
                 : session.sessionMode == 2 ? "\(session.targetCount) count session" : "freestyle")
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                Text("Saved to your history")
                    .font(.system(size: 19, weight: .light, design: .rounded))
            }
            .foregroundStyle(Color.sage)
            if let streak = finishedStreak {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.sage)
                    Text(streak.current >= streak.best ? "Day \(streak.current) · your best yet"
                                                       : "Day \(streak.current) · your best is \(streak.best)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .regular, design: .rounded))
            }
        }
    }
}

struct ZikrBento: View {
    let count: Int
    let seconds: TimeInterval
    let secondsPerCount: Double
    let perTasbeeh: String
    var finish: (timeLeft: TimeInterval, at: Date)? = nil
    /// Lifetime use (a mantra's page): "25m 56s" instead of a stopwatch, other captions, and
    /// flat grouped-list tiles instead of glass.
    var timeText: String? = nil
    var countCaption = "count"
    var timeCaption = "time"
    var grouped = false
    /// Your usual pace for this zikr (`MantraModel.secondsPerCount`, this session left out): the
    /// rate tile says how this session compares — faster in sage, slower in secondary, never red.
    /// Nil = no line (first session, freestyle with no zikr, a mantra's lifetime page).
    var usualSecondsPerCount: Double? = nil

    @State private var showingPerCount = true
    @State private var showingFinishTime = false

    private let gap: CGFloat = 10
    private let tileHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    // Count and time just show (the old spin-and-buzz on tap did nothing — owner).
                    tile {
                        row(icon: "circle.hexagonpath", value: count.formatted(), caption: countCaption)
                    }
                    tile {
                        row(icon: "gauge.with.needle", value: timeText ?? timerStyle(seconds), caption: timeCaption)
                    }
                }

                tile {
                    VStack(spacing: 4) {
                        Text("rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        flip(showingPerCount,
                             String(format: "%.2fs", secondsPerCount), "per count",
                             perTasbeeh, "per tasbeeh", size: 30)
                        if let line = paceComparison(perCount: true), let line2 = paceComparison(perCount: false) {
                            ZStack {
                                comparisonText(line).opacity(showingPerCount ? 1 : 0)
                                comparisonText(line2).opacity(showingPerCount ? 0 : 1)
                            }
                            .padding(.top, 6)
                        }
                    }
                    // It flips: the same ⇆ as the finish tile (owner, 2026-09-28).
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) { flipMark.padding(12) }
                }
                .frame(height: tileHeight * 2 + gap)
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingPerCount.toggle() }
                }
            }

            if let finish {
                tile {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        ZStack(alignment: .leading) {
                            sentence(String(inMinSecStyle2(from: finish.timeLeft).dropFirst(3)), "left until you finish")
                                .opacity(showingFinishTime ? 0 : 1)
                                .offset(y: showingFinishTime ? -16 : 0)
                            sentence(shortTime(finish.at), "is your estimated finish")
                                .opacity(showingFinishTime ? 1 : 0)
                                .offset(y: showingFinishTime ? 0 : 16)
                        }
                        Spacer(minLength: 0)
                        flipMark
                    }
                    .padding(.horizontal, 16)
                    .frame(height: tileHeight)
                }
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingFinishTime.toggle() }
                }
                .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // tiles keep their height outside a ScrollView
    }

    /// The mark on every tile that flips on a tap (finish, rate).
    private var flipMark: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// This session against your usual pace, per count or per tasbeeh (100 counts, like the rate):
    /// "0.7s faster", "1m 10s slower", "about your usual" within 5 %. Nil without a usual pace.
    private func paceComparison(perCount: Bool) -> (text: String, faster: Bool?)? {
        Self.paceComparison(secondsPerCount: secondsPerCount, usual: usualSecondsPerCount, perCount: perCount)
    }

    /// The same line for the soft session's per-count tile (decision session-flow-build A).
    static func paceComparison(secondsPerCount: Double, usual: Double?, perCount: Bool) -> (text: String, faster: Bool?)? {
        guard let usual, usual > 0, secondsPerCount > 0 else { return nil }
        let diff = secondsPerCount - usual
        if abs(diff) / usual < 0.05 { return ("about your usual", nil) }
        let amount = abs(diff) * (perCount ? 1 : 100)
        let text: String
        if perCount {
            text = amount < 0.1 ? String(format: "%.2fs", amount) : String(format: "%.1fs", amount)
        } else {
            let whole = Int(amount.rounded())
            text = whole >= 60 ? "\(whole / 60)m \(whole % 60)s" : "\(whole)s"
        }
        return ("\(text) \(diff < 0 ? "faster" : "slower")", diff < 0)
    }

    private func comparisonText(_ line: (text: String, faster: Bool?)) -> some View {
        Text(line.text)
            .font(.system(size: 13, weight: line.faster == true ? .medium : .regular, design: .rounded))
            .foregroundStyle(line.faster == true ? Color.sage : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
    }

    /// "1m 37s left until you finish" as one line: the number first in the tiles' type, the
    /// words after it, quiet (owner, 2026-09-25).
    private func sentence(_ value: String, _ words: String) -> some View {
        (Text(value).font(.system(size: 22, weight: .light, design: .rounded))
            + Text(" " + words).font(.subheadline).foregroundColor(.secondary))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: tileHeight)
            .background {
                if grouped {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(grouped ? 0 : 0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(grouped ? 0 : 0.1), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(icon: String, value: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            valueStack(value, caption, size: 22, leading: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: tileHeight)
    }

    /// Two value / caption pairs in one place; the shown one slides up and out as the other
    /// slides in (the rate box's old flip).
    private func flip(_ showFirst: Bool, _ v1: String, _ c1: String, _ v2: String, _ c2: String,
                      size: CGFloat, leading: Bool = false) -> some View {
        ZStack(alignment: leading ? .leading : .center) {
            valueStack(v1, c1, size: size, leading: leading)
                .opacity(showFirst ? 1 : 0)
                .offset(y: showFirst ? 0 : -16)
            valueStack(v2, c2, size: size, leading: leading)
                .opacity(showFirst ? 0 : 1)
                .offset(y: showFirst ? 16 : 0)
        }
    }

    private func valueStack(_ value: String, _ caption: String, size: CGFloat, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: leading ? 0 : 2) {
            Text(value)
                .font(.system(size: size, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, leading ? 0 : 10)
    }
}

#Preview {
    @Previewable @StateObject var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool)
        .environmentObject(sharedState) // Inject shared state into the environment
}

/// Asks a running tasbeeh session to pause (its normal pause screen), e.g. before the widget's "Unmark?"
/// shows over it (owner, CA197AE2).
enum TasbeehSession {
    static let pauseRequest = Notification.Name("tasbeehPauseRequest")
}
