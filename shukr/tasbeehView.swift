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
    @State private var pageIn = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
    @State private var countIn = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
    @State private var chromeIn = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
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
    /// The finished ring's least room over the tiles (owner, stats-weight: "enough room to breathe").
    private static let resultsRingClearance: CGFloat = 36
    private var ringLiftTarget: CGFloat {
        guard ringAbove, ringSize.height > 0, ringHomeMid != .zero, !ringToCentre else { return 0 }
        if savedSession != nil {
            guard cardsBottomTop > 0 else { return 0 }
            let tilesTop = cardsBottomTop - resultsTilesLift   // they rise on the results
            return min(0, tilesTop - Self.resultsRingClearance - (ringHomeMid.y + ringSize.height / 2))
        }
        return 0   // paused: it stays where it is and fades (`ringAwayForPause`) — no trip up the page
    }
    /// The pause screen has no ring (owner, 2026-10-08: "get rid of keeping the ring in it … no need to do the transition
    /// of moving the ring"): the ring and its count fade where they stand while paused and come back on Resume. A close
    /// or a finish from the pause brings it back first (the close lands it on the wheel; the results raise it).
    private var ringAwayForPause: Bool { ringAbove && paused && savedSession == nil && !ringToCentre }
    @Environment(\.modelContext) private var context
    @Environment(SharedStateClass.self) var sharedState
    
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
    /// Counting in sets right now (a size set and switched on): +N in the top bar and the line at the bottom.
    private var setsOn: Bool { countingInSets && secondaryStep > 1 }
    /// The counter's top bar's height (the pause screen's top row matches it).
    @State private var topBarHeight: CGFloat = 0
    /// How far the results' tiles rise (as the pause view lifts them — the finish line's room at its fullest when
    /// there's none): the finished ring keeps its room above them. Worked out here, not reported up: setting this
    /// from the pause view as it laid out lost the sleep finish's results.
    private var resultsTilesLift: CGFloat {
        let finishLine = !sharedState.isDoingPostNamazZikr && sharedState.selectedMode != 0
        return pauseScreen_StatsSettingsBG.resultsLiftBase + (finishLine ? 0 : 48)
    }
    /// Finish asked for its second tap (it lets go after 3 s, or on resuming).
    @State private var finishArmed = false
    @State private var finishArmToken = 0
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
    @State private var ringOut = SessionHandoff.shared.enteringInPlace   // an in-place entry brings the ring in after the page
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
    /// Where ⏸ and the pause screen's chips are, for the first session's tips (CountTips).
    @State private var pauseButtonFrame: CGRect = .zero
    @State private var chipsFrame: CGRect = .zero
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
    /// A saved stop's cleanup (`finishStopCleanup`) waits for the results to land — or runs at once with no frames to wait for.
    @State private var stopCleanupPending = false
    /// The finish buzz already played on the goal's own tap / tick (stopTimer(goal:)): the cleanup doesn't play it again.
    @State private var finishBuzzPlayed = false
    @State private var totalPauseInSession: Double = 0
    @State private var secsToReport: TimeInterval = 0
    @State private var savedSession: SessionDataModel? = nil
    /// Counts made by the current drag (the session tour's "three in one stroke").
    @State private var strokesThisTouch = 0
    
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

    /// In place on the Salah page (SessionHandoff.openInPlace, decision post-salah-entry A): the close backwards — the
    /// page fades in over the Salah page (it goes), then the ring, the count and the buttons come in. Whatever stops it
    /// (the app sent away), everything ends up shown and the cover opaque.
    private func playEntryInPlace() {
        openingStyle = reduceMotion ? .fade : SessionOpening.current
        sequence?.cancel()
        sequence = Task { @MainActor in
            defer {
                if !pageIn || !countIn || !chromeIn || ringOut {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { pageIn = true; countIn = true; chromeIn = true; ringOut = false }
                }
                SessionHandoff.shared.enteredInPlace()
            }
            await CircleMotion.animate(.easeInOut(duration: CircleMotion.sessionPageOutDuration)) { pageIn = true }
            guard !Task.isCancelled else { return }
            await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.in)) {
                ringOut = false; countIn = true; chromeIn = true
            }
        }
    }

    /// Closing softly onto the wheel (the host asked: SessionHandoff `.leaving`): the same steps backwards, each
    /// awaited to its end, then `.done` — the host removes the cover. One sequence: the host, the session and the wheel
    /// kept time off a hand-summed `leaveDelay` before (audit E3).
    private func playClose() {
        sequence?.cancel()
        sequence = Task { @MainActor in
            // Whatever happens (cancelled, the app sent away mid-close: completions stop), the cover still goes.
            defer { SessionHandoff.shared.finishClose() }
            let handoff = SessionHandoff.shared
            if handoff.inPlace {
                // On the Salah page (post-salah): out, then in — everything on the page goes where it stands (no
                // slide, no ring to land), then the page itself fades and the Salah page is there under it.
                await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) {
                    leaving = true; countIn = false; chromeIn = false; ringOut = true
                }
                guard !Task.isCancelled else { return }
                handoff.reveal()
                await CircleMotion.animate(.easeInOut(duration: CircleMotion.sessionPageOutDuration)) { pageIn = false }
                return
            }
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
                // The beads round the ring go while paused (owner: "we don't need to keep the 100 neumorphic beads
                // around the edge of the circle in the pause screen"); the count stays.
                // Tasbih Fatimah shows the phrase's own count, 0…33 · 0…33 · 0…34: a big 0 says "next phrase" (owner,
                // fatimah-phase-count). The saved session, results and history keep the total.
                TasbeehCountView(tasbeeh: sharedState.isDoingPostNamazZikr ? PostSalahTasbeeh.phase(at: tasbeeh).done : tasbeeh,
                                 beadsShown: !paused)
                    .offset(entryOffset)
                    .modifier(SessionAppear(shown: countIn, style: openingStyle))
                    .modifier(RingLift(lift: ringAbove ? ringLift : nil, dimmed: ringDimmed || ringAwayForPause))
                    .blur(radius: ringAwayForPause ? CircleMotion.pauseBlur : 0)
                    .animation(CircleMotion.pauseFade, value: ringAwayForPause)
                
                GeometryReader { geometry in
                    VStack {
                        ZStack {
                            Color("bgColor").opacity(0.001) // Simulate clear color
                                .frame(width: geometry.size.width, height: geometry.size.height) // Fill the entire geometry
                                .onTapGesture {
                                    //                                            print("Tap gesture detected")
                                    // The Zikr Tour's lessons let only their own move count (ZikrTour.allows).
                                    guard ZikrTour.shared.allows(byDrag: false, total: sessionCount) else { return }
                                    incrementTasbeeh() // Increment on tap
                                    CountTips.shared.counted(byDrag: false)
                                    ZikrTour.shared.counted(byDrag: false, inTouch: 0, total: sessionCount)
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
                                                if ZikrTour.shared.allows(byDrag: true, total: sessionCount) {
                                                    incrementTasbeeh()
                                                    strokesThisTouch += 1
                                                    CountTips.shared.counted(byDrag: true, inTouch: strokesThisTouch)
                                                    ZikrTour.shared.counted(byDrag: true, inTouch: strokesThisTouch, total: sessionCount)
                                                }
                                                lowestPoint = value.translation.height // need to set it otherwise it will always be the lowest point of the entire drag sesh
                                                // Check if dragged up from lowest point by a value of incrementThreshold/2
                                            } else if !dragToIncrementBool && lowestPoint - offsetY > incrementThreshold/2 {
                                                dragToIncrementBool = true
                                                highestPoint = value.translation.height
                                            }
                                        }
                                        .onEnded { _ in
                                            CountTips.shared.dragEnded(strokes: strokesThisTouch)   // the session tour
                                            ZikrTour.shared.dragEnded(strokes: strokesThisTouch)
                                            strokesThisTouch = 0
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
                        TourTargets.shared.set("ct.ring", frame)   // the counting lessons' ghost finger stays above it
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
                    .modifier(RingLift(lift: ringAbove ? ringLift : nil, dimmed: ringDimmed || ringAwayForPause))
                    .blur(radius: ringAwayForPause ? CircleMotion.pauseBlur : 0)
                    .animation(CircleMotion.pauseFade, value: ringAwayForPause)
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
                    countingInSets: $countingInSets,
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
                    onSleepChipFrame: { sleepChipFrame = $0 },
                    onChipsFrame: { chipsFrame = $0 },
                    topBarHeight: topBarHeight,
                    finishArmed: finishArmed
                )
            }
            .animation(.easeInOut, value: paused)
            .modifier(SessionAppear(shown: !leaving, style: openingStyle))   // a soft close from the pause screen
            
            // Settings & Start/Stop
            VStack {
                
                // The Top Buttons During Session. ⏸ on the left — the same button becomes ‹ Resume while paused
                // (PauseResumeButton, decision pause-resume-morph A); − on the right, with +N beside it only while
                // counting in sets (decision top-bar-finish A; a tap turns sets off). The right side is always laid out,
                // faded out and inert while paused: removing it popped the layout on every pause / resume.
                HStack {
                    PauseResumeButton(paused: paused, raised: ringAbove, reduceMotion: reduceMotion, action: {
                        if !paused { CountTips.shared.pausePressed() }
                        togglePause()
                    })
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pauseButtonFrame = $0 }

                    Spacer()

                    HStack {
                        if setsOn {
                            TopOfSessionButton( // Count in sets is on: every tap counts N; a tap turns it off
                                text: "+\(secondaryStep)", actionToDo: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation(.easeInOut(duration: CircleMotion.quick)) { countingInSets = false }
                                },
                                paused: paused, togglePause: togglePause, active: true)
                            .accessibilityLabel("Counting in sets of \(secondaryStep), on. Turn off")
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            .opacity(paused ? 0 : 1)
                            .allowsHitTesting(!paused)
                        }
                        // − while counting; paused, the same button becomes Finish (decision minus-finish-morph, owner).
                        MinusFinishButton(paused: paused, armed: finishArmed, raised: ringAbove,
                                          reduceMotion: reduceMotion) {
                            if paused { finishTap() } else { decrementTasbeeh() }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.finish", $0) }
                    }
                }
                .animation(paused ? .easeOut(duration: ringAbove ? 0.15 : 0.35) : .easeIn, value: paused)
                // Right under the status bar, no padding above or below (owner: "why … so much gap at the top"); the pause
                // screen's row is as tall as this, so ‹ Resume still lands where ⏸ is.
                .padding(.horizontal)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
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
                                    Circle()
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
                            // it drew through the pause screen), and for the results (ring-above: they don't cover it);
                            // in with the count (an in-place entry: it showed over the Salah page before the page came).
                            .opacity(paused || savedSession != nil || !countIn ? 0 : 1)
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

                // Counting in sets: said at the bottom so it's never missed (owner: "that way you see that it's clearly
                // turned on"); above "goal reached" when that shows too. Not a button: a tap there counts.
                if setsOn && savedSession == nil && !showInactivityAlert {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack").font(.system(size: 12, weight: .regular))
                            Text("each tap counts \(secondaryStep) · tap +\(secondaryStep) to turn off")
                        }
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(Color.sage.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 28)
                        .padding(.bottom, goalReached && !autoStop ? 48 : 14)
                    }
                    .opacity(paused ? 0 : 1)
                    .allowsHitTesting(false)
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
                    .opacity(paused || savedSession != nil || !countIn ? 0 : 1)   // ring-above results sit under it (Sami's B4); in with the count
                    .animation(.easeInOut, value: paused || savedSession != nil)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: toggleInactivityTimer)

            // The session tour (CountTips): tapping, dragging, the pause screen, the results.
            // The Zikr Tour: counting its task, then its results (ZikrTour.swift).
            ZikrTourSessionLayer(paused: paused, results: savedSession != nil)
            CountTipsLayer(paused: paused,
                           clear: !showInactivityAlert && (countIn || savedSession != nil) && !leaving,
                           results: savedSession != nil,
                           pauseButton: pauseButtonFrame, chips: chipsFrame)
            
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
                    defer { finishStopCleanup() }   // once they're in (or this was cut short), never a guess of it
                    await CircleMotion.animate(.easeOut(duration: CircleMomentTiming.out)) {
                        ringOut = !ringAbove; countIn = false; chromeIn = false
                    }
                    guard !Task.isCancelled, savedSession != nil else { return }
                    await CircleMotion.animate(.easeOut(duration: CircleMotion.resultsInDuration)) { resultsIn = true }
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
            CountTips.shared.sessionOpened(postSalah: sharedState.isDoingPostNamazZikr,
                                           task: sharedState.selectedMode != 0 && sharedState.selectedTask != nil)
            appLookDark = colorScheme == .dark
            tasbeehColorMode = appLookDark
            // Post-salah: the Tasbih Fatimah zikr is set up BEFORE anything resolves the pick (audit A8).
            if !timerIsActive, sharedState.isDoingPostNamazZikr {
                PostSalahTasbeeh.prepare(sharedState, in: context)
                // On the Salah page: in and out in place. The pill opened it so (playEntryInPlace); any other way in still
                // closes in place.
                if SessionHandoff.shared.enteringInPlace { playEntryInPlace() } else { SessionHandoff.shared.openInPlace(entering: false) }
            }
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
        .onChange(of: paused) { _, nowPaused in
            if !nowPaused { finishArmed = false }   // resumed: Finish isn't left half-armed for the next pause
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
            if newScenePhase == .background { finishStopCleanup() }   // no frames, so the results' fade won't end
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
            CountTips.shared.sessionClosed()
            ZikrTour.shared.sessionClosed()
            finishStopCleanup()
            CircleCover.set("tasbeeh", false)
            if sleptSaved { SleepMorning.clear() }   // Done on the results after a sleep finish: awake, no card
            sharedState.isDoingPostNamazZikr = false
            UIApplication.shared.isIdleTimerDisabled = false // never leave this on after the cover closes
        }

        .preferredColorScheme(tasbeehColorMode ? .dark : .light)
    }
//--------------------------------------functions--------------------------------------

    /// Finish: the first tap arms it ("Tap again to finish"), the second finishes; it lets go after 3 s.
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // an input timeout, not a motion
                if token == finishArmToken { finishArmed = false }
            }
        }
    }

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
                if !paused && (sharedState.selectedMode == 1) && totalTime > 0 {
                    progressFraction = CGFloat(Int(secsPassed + timeOffset))/TimeInterval(totalTime)
                }
            }
           
//            print("progFrac? \(progressFraction >= 1) -- paused? \(paused) -- autoStop? \(autoStop)") // for debugging
            if ((progressFraction >= 1) && !paused) {
                if(autoStop && timerIsActive){
                    stopTimer(goal: true)
                    print("homeboy auto stopped....")
                }
            }
        }
    }
    
        
    /// `goal`: the count goal's tap or the timed goal's tick ended it — the finish buzz plays now, on that tap, not a
    /// second later when the results' fade-in runs the cleanup (owner: "it feels like a visible hang"; zikr-goal-haptic).
    private func stopTimer(goal: Bool = false) {
        ZikrAudio.stopAll()     // a memo started on the pause card doesn't play on into the results
        guard timerIsActive else {
            print("Timer is not active")
            return
        }
        if goal, !stoppedDueToInactivity, !endedAsleep, !countingHapticsOff {   // never buzz someone asleep
            triggerSomeVibration(type: .vibrate)
            finishBuzzPlayed = true
            #if DEBUG
            if let at = lastTapAt { print("GOAL finish buzz \(Int(Date().timeIntervalSince(at) * 1000)) ms after the last tap") }
            #endif
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
            if let saved = savedSession {
                CountTips.shared.sessionSaved(saved.id, count: saved.totalCount)   // the session tour's practice session
                ZikrTour.shared.sessionSaved(saved)                                 // the Zikr Tour: the results
            }
            
            print("saved session: \(savedSession == nil ? "nil" : "\(savedSession!.title) with \(savedSession!.totalCount)")")
            // Shared-state writes re-render the whole home screen under this cover, so they wait
            // until the results screen is up (completeStopTimer, after its fade) instead of
            // landing in the same frame as it — part of the "lag before the completion page"
            // (owner, 2026-09-25). In the background nothing animates: at once.
            stopCleanupPending = true
            if UIApplication.shared.applicationState == .background { finishStopCleanup() }
        } else {
            completeStopTimer()
        }
    }


    /// A saved stop's cleanup, once: the results' fade-in ends it (`resultsTask`), or the app leaving / the cover closing.
    private func finishStopCleanup() {
        guard stopCleanupPending else { return }
        stopCleanupPending = false
        sharedState.selectedTask = nil
        completeStopTimer()
        // The Zikr widget reads the shared store: save, then let it redraw.
        try? context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.zikr)
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.zikrControl)   // its "N tasks left" line
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
    /// ring means the goal), a count goal fills to it. Timed sessions follow the ticker. Tasbih
    /// Fatimah follows the phrase — 33, 33, 34 — empty again with the big number at each switch (owner).
    private func refreshCountProgress() {
        if sharedState.isDoingPostNamazZikr {
            progressFraction = CGFloat(PostSalahTasbeeh.ringFraction(at: tasbeeh))
        } else if sharedState.selectedMode == 0 {
            let numerator = tasbeeh != 0 && tasbeeh % 100 == 0 ? 0 : tasbeeh % 100
            progressFraction = CGFloat(numerator) / 100
        } else if sharedState.selectedMode == 2 {
            let target = Int(sharedState.targetCount) ?? 0   // a goal of 0 (or none) gave an infinite ring
            progressFraction = target > 0 ? CGFloat(tasbeeh) / CGFloat(target) : 0
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
        if sessionCount <= 0 && SessionHandoff.shared.closesSoftly && UIApplication.shared.applicationState == .active {
            inactivityTimerHandler(run: "stop")
            if !finishBuzzPlayed && !stoppedDueToInactivity && !endedAsleep && !countingHapticsOff { triggerSomeVibration(type: .vibrate) }
            finishBuzzPlayed = false
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
        
        
        if !finishBuzzPlayed && !stoppedDueToInactivity && !endedAsleep && !countingHapticsOff {   // never buzz someone asleep
            triggerSomeVibration(type: .vibrate)
        }
        finishBuzzPlayed = false   // played on the goal's tap (stopTimer(goal:)), or just now
        
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
        CountTips.shared.resultsDone()
        ZikrTour.shared.resultsDone()
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
        // The first-session tips' practice session (decision count-tips-session B): never saved — held in memory by
        // CountTips, "Practice" in History until its pretend delete; no task, no zikr (another store's rows).
        let practice = linkedTask == nil && CountTips.shared.takesPractice(count: sessionCount)

        let item = SessionDataModel(
            title: practice ? TourCopy.Session.practiceTitle : placeholderTitle,
            sessionMode: sharedState.selectedMode,
            targetMin: sharedState.selectedMinutes,
            targetCount: Int(sharedState.targetCount) ?? 0,
            totalCount: sessionCount,
            startTime: startTime ?? Date(),
            secondsPassed: secsToReport,
            avgTimePerClick: newAvrgTPC,
            tasbeehRate: tasbeehRate,
            task: practice ? nil : linkedTask,
            // Picked from a task/picker (or Tasbih Fatimah for post-salah) → we have the row.
            mantra: practice ? nil : (sharedState.mantraForSession ?? MantraModel.find(named: placeholderTitle, in: context))
        )
        item.endedAsleep = endedAsleep
        if practice {
            CountTips.shared.holdPractice(item)
            SessionDraft.clear()
            return item
        }
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
                stopTimer(goal: true)
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

}


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

/// The pause screen over the counter (owner, 2026-10-08: "make the pause screen overlay fade over the counter page
/// nicely"): its parts come and go together, one fade, as the counter's ring softens away under them
/// (`CircleMotion.pauseFade`). Finishing keeps the results' timing: out quick, in a beat late, as the ring moves.
struct PauseLayerFade: ViewModifier {
    let shown: Bool
    let finishing: Bool
    var resultsDelay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .animation(finishing ? (shown ? .easeOut(duration: CircleMomentTiming.in).delay(resultsDelay)
                                          : .easeOut(duration: CircleMotion.cardsOutDuration))
                                 : CircleMotion.pauseFade,
                       value: shown)
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

#Preview {
    @Previewable @State var sharedState = SharedStateClass()
    @Previewable @State var dummyBool: Bool = true

    tasbeehView(isPresented: $dummyBool)
        .environment(sharedState) // Inject shared state into the environment
}

/// Asks a running tasbeeh session to pause (its normal pause screen), e.g. before the widget's "Unmark?"
/// shows over it (owner, CA197AE2).
enum TasbeehSession {
    static let pauseRequest = Notification.Name("tasbeehPauseRequest")
}
