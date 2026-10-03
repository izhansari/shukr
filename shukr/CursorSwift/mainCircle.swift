import SwiftUI
import QuartzCore
import Foundation
import SwiftData


/// What's presented over the Salah page from views PrayerTimesView's `somethingCovers` can't see
/// (the What's new sheet, the ☰ popover, a prayer row's time editor). The circle counts as not on
/// screen while any is up — no qibla buzz, no track animation. 2026-09-27 review.
@MainActor enum CircleCover {
    /// Kept on the stage (CircleMoments.swift), observable, so a moment waiting for a clear circle wakes when a cover
    /// goes instead of polling.
    static var active: Set<String> { CircleStage.shared.covers }
    static func set(_ key: String, _ on: Bool) { CircleStage.shared.cover(key, on) }
    /// A cover that can close itself says how (a widget open closes it rather than pushing its page underneath).
    static func set(_ key: String, _ on: Bool, close: @escaping () -> Void) { CircleStage.shared.cover(key, on, close: close) }
    static var closable: Bool { CircleStage.shared.closable }
    static func closeAll() { CircleStage.shared.closeAll() }
    /// The morning card is a cover for prompts (they wait for it) but not over the circle: its page has a hole there,
    /// and the circle shows the morning itself (circle step 3).
    static let besideCircle: Set<String> = ["morningCard", "lost"]
    static var nothingOverCircle: Bool { active.subtracting(besideCircle).isEmpty }
}

struct MainCircleView: View {
    /// The circle's 1 s clock (see `.onReceive(Self.ticker)`): created once, never per render.
    private static let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// "NEXT" above a prayer that hasn't started, or the dashed ring alone (dev toggle, NextLabel).
    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true
    /// The soft ring (the theme, CircleTheme.swift).
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var locationManager: EnvLocationManager   // only to start updates; publishes rarely
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @State private var ogText = true  // the summary circle's side (its own state and its own 3 s timer)
    /// A prayer's time line flips itself (ExternalToggleText: the buzz, the flip, back after 3 s); a tap only nudges
    /// it. It read `ogText` too, whose own 3 s timer then nudged it again — a buzz with no touch, and sometimes a second
    /// flip (audit A, bug 1).
    @State private var timeFlipPulse = false
    /// A prayer was just marked done: the flourish plays over the circle, then clears.
    @State private var flourish: PrayerCompletionEvent?
    @State private var flourishID = 0
    /// The flourish fades out on its own opacity (an implicit animation) while still mounted, then goes quietly: its
    /// removal transition never animated, so the full ring cut out in one frame and the arc faded in from nothing — a
    /// blink at the end of every mark (Sami's audit, 2026-10-02, finding 1; his verified fix).
    @State private var flourishOut = false
    private var contentHidden: Bool { flourish != nil && !flourishOut }
    /// The face the circle is showing (CircleMoments.swift): changed only by a moment, so the data changing (a mark,
    /// an unmark, a window ending) never swaps the words in place — they go out, then the new ones come in. nil = not
    /// shown yet (the derived face).
    @State private var displayedFace: CircleFace?
    /// The words are out between two faces (a swap).
    @State private var faceAway = false
    /// The running moment, its task, and how it snaps to its end if a newer one takes over (`run`).
    @State private var momentKind: CircleMomentKind?
    @State private var momentTask: Task<Void, Never>?
    @State private var momentSettle: (() -> Void)?
    /// ▶︎ Prayer begins with every prayer done: today's Fajr row, held on the circle for the preview.
    @State private var heldPrayer: PrayerModel?
    /// The summary's side shown — the day's score (sheet open) or the next Fajr — swapped out-then-in by a moment
    /// (`flipSummary`); the track follows it, never the sheet directly (it moved before the words were out — audit A).
    /// nil until it's first shown (the side the sheet asks for).
    @State private var summaryShowsScore: Bool?
    @State private var summaryAway = false
    private var summaryWantsScore: Bool { sharedState.navPosition == .bottom }
    /// ▶︎ Prayer begins' script (it changes the preview's data; the circle plays the moments that follow).
    @State private var previewTask: Task<Void, Never>?
    /// What the circle shows at rest, from the data: the morning card's session while it's up, else the prayers'.
    private var derivedFace: CircleFace {
        if let lost = CircleStage.shared.lost, !lost.landed { return .lost }
        if let session = CircleStage.shared.morning { return .morning(session) }
        return prayersFace
    }
    /// The prayer on the circle, or the day's summary (none; or the next prayer is tomorrow's Fajr).
    private var prayersFace: CircleFace {
        _ = currentTime
        // ▶︎ Prayer begins: its held prayer and the state it's playing, as if they were the data.
        if let held = heldPrayer { return .prayer(held, preview ?? held.status(), preview: preview != nil) }
        guard let p = viewModel.relevantPrayer else { return .summary }
        let status = preview ?? p.status()
        // Tomorrow's Fajr is the summary's (its next-Fajr side), unless the preview is playing it.
        if status == .upcoming && p.name == "Fajr" && preview == nil { return .summary }
        return .prayer(p, status, preview: preview != nil)
    }
    /// The opening is playing on this circle and hasn't landed: its own track and words wait.
    private var openingHides: Bool {
        guard let opening = CircleStage.shared.opening, opening.inCircle else { return false }
        return !opening.landed
    }
    /// The lost page's state, while the circle shows it (step 3b).
    private var lostShown: LostStage? {
        guard case .lost = displayedFace ?? derivedFace else { return nil }
        return CircleStage.shared.lost
    }
    /// The opening's mark keeps the circle's words out (the lost page's hand-off keeps its symbol in).
    private var openingHidesWords: Bool { openingHides && (CircleStage.shared.opening?.hidesWords ?? true) }
    /// The morning card's session, while the circle shows it.
    private var morningShown: SessionDataModel? {
        if case .morning(let session) = displayedFace ?? derivedFace { return session }
        return nil
    }
    /// The prayer the circle draws, if its face is a prayer.
    private var shownPrayer: PrayerModel? {
        if case .prayer(let p, _, _) = displayedFace ?? derivedFace { return p }
        return nil
    }
    /// The state the circle shows that prayer in (the face's, changed only by a moment).
    private var shownStatus: PrayerModel.prayerStatus? {
        if case .prayer(_, let status, _) = displayedFace ?? derivedFace { return status }
        return nil
    }
    /// The shown face is ▶︎ Prayer begins' (its "just begun" arc).
    private var shownIsPreview: Bool {
        if case .prayer(_, _, let preview) = displayedFace ?? derivedFace { return preview }
        return false
    }
    /// The prayer on the circle just came into its window, on screen: the moment plays once.
    /// The track: 0 = dashed (a prayer that hasn't started), 1 = the solid band (`CircleTrack`).
    @State private var trackSolid: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settings → My Dev Stuff → Preview (`PrayerStartPreview`): the circle draws its prayer in this
    /// state instead of the real one — "next", then "now" as the moment plays. Visual only.
    @State private var preview: PrayerModel.prayerStatus?
    /// When the circle last appeared: a flip in the first moments (launch, coming back) doesn't play.
    @State private var appearedAt = Uptime.now
    @Environment(\.scenePhase) private var scenePhase
    /// The pager's live state — the bottom nudge lives in the chrome and reads it.
    @Environment(PagerLiveState.self) private var live: PagerLiveState?
    
    
    @Binding var showQiblaMap: Bool
    @Binding var showTasbeehPage: Bool
    let animationStyle: Animation = .spring
    
    var body: some View {
        ZStack {
            // The soft ring's raised band, under everything and always there — for a prayer still to come too, with
            // the dashes drawn in it (owner, 2026-10-02: "make the future ring also soft… dashed ring inside the
            // track"). It stays through the completion flourish (which hides the content above) and for the day's
            // score (SalahLook.swift).
            if theme.track.lifted {
                NeuRingTrack()
                    .opacity(openingHides ? 0 : 1)
                    // ▶︎ Opening over the page as it is: the track fades out first (a launch has nothing to fade).
                    .animation(CircleStage.shared.opening?.inPlace == true ? .easeOut(duration: CircleMotion.openingTrackOutDuration) : nil, value: openingHides)
            }
            // main outer circle: dashed for a prayer that hasn't started, the solid band otherwise
            CircleTrack(solid: trackSolid, reduceMotion: reduceMotion, band: !theme.track.lifted)
                .opacity(openingHides ? 0 : 1)
                    // ▶︎ Opening over the page as it is: the track fades out first (a launch has nothing to fade).
                    .animation(CircleStage.shared.opening?.inPlace == true ? .easeOut(duration: CircleMotion.openingTrackOutDuration) : nil, value: openingHides)
                // Where the welcome's ring lands (WelcomeAnimation.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    WelcomeTarget.circleFrame = $0   // only this circle writes it
                }
            
            //Inner Content — hidden while a completion flourish plays over it (PrayerCompletionFX)
            Group {
                if let lost = lostShown {
                    // Location lost (step 3b): the crossed-out symbol in the ring; its words round it (LostWords).
                    LostFace(stage: lost)
                        .transition(.opacity)
                }
                else if let session = morningShown {
                    // The morning after a sleep finish: the session in the ring, the card's page round it (SleepMode).
                    MorningFace(session: session)
                        .transition(.opacity)
                }
                else if let prayer = shownPrayer, let status = shownStatus {
                    // The state the face shows (the real one, or the dev preview's), not read live: it changes in a
                    // moment, while the words are out.
                    var progress: Double {
                        // Not started: 0, so when it starts the arc grows from nothing (it was 1 in
                        // a clear colour, and sprang back from full to empty, green, at the start).
                        if status == .upcoming { return 0 }
                        // The dev preview of a prayer beginning: from (almost) nothing, as a real start does — its
                        // own clock drew it already most of the way round (Sami's audit, finding 8).
                        if shownIsPreview && status == .current { return 0.015 }
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
                        if shownIsPreview && status == .current { return .green }   // the preview's start (a held row is long past)
                        return PrayerScoring.color(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: currentTime))
                    }
                    let upcoming = status == .upcoming
                    ZStack{
                        // "Next" → "now": the track expands (trackSolid) while NEXT and the name's
                        // dimming crossfade (2026-09-27).
                        // In the Perfect (green) window under the soft ring, the arc is the tasbeeh ring's living fill
                        // (AliveRingFill, "fine") cut to the arc — "it deserves it … we want to beautify when we are in
                        // that period of prayer" (owner, 2026-10-01). Yellow / red stay the solid arc below.
                        let perfectNow = theme.arc.alivePerfect && progress < 1 && PrayerScoring.grade(for: PrayerScoring.score(
                            start: prayer.startTime, end: prayer.endTime, markedAt: currentTime)) == .perfect
                        if perfectNow {
                            AliveRingFill(dark: colorScheme == .dark, tuning: .fine)
                                .frame(width: 230, height: 230)
                                .mask {
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 200, height: 200)
                                        .animation(animationStyle, value: currentTime)
                                }
                                .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 6)
                                .allowsHitTesting(false)
                        }
                        // progress arc. Under the soft ring it takes the tasbeeh arc's shape (NeuCircularProgressView,
                        // "fine"): as wide as the band, round ends, a soft glow in its own colour (owner, 2026-10-01).
                        Circle()
                            .trim(from: 0, to: progress) // Adjust progress value (0 to 1)
                            .stroke(progressColor, style: StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                            .shadow(color: progressColor.opacity(theme.arc.glow), radius: 6)   // glow 0 = none
                            .opacity(perfectNow ? 0 : 1)
                            .animation(animationStyle, value: currentTime/*progress*/)
                    
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
                                // Next ⇄ now changes only inside a moment, while the words are out (the face carries it).
                                .foregroundStyle(upcoming ? Color.primary.opacity(0.55) : Color.primary)
                                // Not started yet: "NEXT" above the name (owner: an empty ring read
                                // like a prayer that's on). An overlay, so the name sits at the same
                                // spot whether the prayer is next or current — it used to jump.
                                .overlay(alignment: .top) {
                                    // A small tag set apart, not a line of the stack (NextTag;
                                        // tuned in the DEBUG NEXT label playground).
                                    NextTag(shown: upcoming && showNextLabel)
                                }
                                if status == .current{
                                    ExternalToggleText(
                                        originalText: "ends \(shortTimePM(prayer.endTime))",
                                        toggledText: timeLeftString(from: prayer.endTime.timeIntervalSinceNow),
                                        externalTrigger: $timeFlipPulse,
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
                                        externalTrigger: $timeFlipPulse,
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
                            }
                        }
                    }
                    .transition(.opacity)
                }
                else {
                    summaryCircle(ogText: $ogText, showsScore: summaryShowsScore ?? summaryWantsScore, away: summaryAway)
                        .transition(.opacity)
                }
            }
            // Between two faces (the summary ↔ a prayer, one prayer → the next) the words go out, then the new ones come
            // in (a swap moment) — they crossfaded through each other.
            .modifier(CircleWordsAway(away: faceAway || openingHidesWords))
            // Inside the ring: past this the words outgrew it ("missed" filled the ring at the largest size).
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            // Out quickly under the flourish (its arc sits on the prayer's own, so the ring never
            // blinks), back in as it fades.
            .opacity(contentHidden ? 0 : 1)
            .blur(radius: contentHidden && !reduceMotion ? 4 : 0)
            .animation(.easeOut(duration: contentHidden ? CircleMotion.flourishCoverDuration : CircleMotion.flourishUncoverDuration),
                       value: contentHidden)

            // The opening on a Salah landing (step 4): the welcome's ring and word, drawn here — it grows into this
            // track, then fades as the track and words come back (one ring).
            if let opening = CircleStage.shared.opening, opening.inCircle {
                WelcomeMark(state: opening)
                    .opacity(opening.landed ? 0 : 1)
                    .animation(.easeOut(duration: CircleMotion.openingMarkOutDuration), value: opening.landed)
            }

            // The lost page's title above the circle and what sharing location gives below (step 3b): the circle's own,
            // so they rise with it.
            if let lost = CircleStage.shared.lost {
                LostWords(stage: lost)
            }

            if let flourish {
                CompletionFlourish(event: flourish)
                    .id(flourishID)
                    .opacity(flourishOut ? 0 : 1)
                    .animation(.easeInOut(duration: CircleMotion.flourishOutDuration), value: flourishOut)
                    // In at once (its arc takes over from the prayer's in place), out with a fade.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
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
                            // Not while a mark's flourish is up: the circle shows the prayer just marked, but this acts
                            // on the next one (audit A).
                            guard momentKind != .marking, flourish == nil else { return }
                            if let prayer = viewModel.relevantPrayer, prayer.status() != .upcoming {
                                viewModel.togglePrayerCompletion(for: prayer)
                                // The post-salah pill follows the flourish (.prayerCompleted).
                            }
                        }
                )
            
            
            

            if morningShown == nil && lostShown == nil && !openingHides {
                // Its own view: only the arrow redraws with the compass, not the whole circle.
                QiblaArrow(onAligned: { checkToTriggerQiblaHaptic(aligned: $0) },
                           tap: { showQiblaMap = true })
                // "Compass needs a moment · tap" under the ring — laid out at zero size, so the circle
                // never moves (it stays centred on the page).
                Color.clear
                    .frame(width: 0, height: 0)
                    .overlay {
                        CompassHintLine(hidden: sharedState.navPosition == .bottom)
                            .fixedSize()
                            .offset(y: 134)
                    }
            }
            

        }
        .transition(.opacity)
        .fullScreenCover(isPresented: $showQiblaMap) {
            LocationMapContentView()
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoPostSalahOffer") {
                live?.postSalahNudge = "Asr"
            }
            #endif
            appearedAt = Uptime.now
            settleTrack(trackWantsSolid)
            locationManager.startUpdating() // Start location updates
        }
        // The prayer day, not the calendar date: after midnight (before the rollover) Date() is tomorrow's rows, so
        // today's score was never set and read 0 %. A beat after appearing, once today's rows have loaded.
        .task {
            guard await CircleGate.pause(Self.dayScoreAfterAppear) else { return }
            viewModel.calculateDayScore(for: PrayerDay.date())
        }
        // The palette's Play → Marking a prayer: the flourish for the prayer on the circle, at today's score — a
        // made-up event, nothing marked (SalahLook.swift).
        .onReceive(NotificationCenter.default.publisher(for: SalahLookPlay.mark)) { _ in
            // All done (the day's score / next Fajr, no prayer on the circle): replays the last mark — Isha's
            // (owner, 2026-10-02: "none of the transitions are working in my current state").
            guard let p = shownPrayer ?? viewModel.relevantPrayer ?? viewModel.todaysPrayers.last(where: { $0.isCompleted })
            else { return }
            let now = Date()
            let window = max(p.endTime.timeIntervalSince(p.startTime), 1)
            let event = PrayerCompletionEvent(name: p.name,
                                              score: PrayerScoring.score(start: p.startTime, end: p.endTime, markedAt: now),
                                              progress: min(max(now.timeIntervalSince(p.startTime) / window, 0), 1),
                                              prayerName: p.name)
            NotificationCenter.default.post(name: .prayerCompleted, object: event)
        }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-selfTestStage") { await StageSelfTest.run() } }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompleted)) { note in
            guard let event = note.object as? PrayerCompletionEvent else { return }
            if event.isCorrection {
                // Still on the circle: the new words in place. Gone: nothing to correct.
                if let shown = flourish, shown.prayerName == event.prayerName, !flourishOut {
                    withAnimation(.easeOut(duration: CircleMotion.flourishCoverDuration)) { flourish = event }
                }
                return
            }
            playMarking(event)
        }
        // The day just became perfect (all five Early): the list's cascade, once this mark's moment is over.
        .onReceive(NotificationCenter.default.publisher(for: .perfectDay)) { _ in CircleStage.shared.perfectDayReached() }
        // The data moved the face (an unmark, a window ending, Fajr beginning from the summary…): out, then in.
        .onChange(of: derivedFace) { _, _ in
            dropStaleOffer()
            faceChanged()
        }
        .onChange(of: summaryWantsScore) { _, score in flipSummary(to: score) }
        // The opening / the lost page's comeback, handed over to be played here like the circle's own moments.
        .onChange(of: CircleStage.shared.momentRequests) { _, _ in
            guard let moment = CircleStage.shared.takeMoment() else { return }
            run(moment.kind, gated: moment.kind != .opening, settle: moment.settle, moment.phases)
        }
        // Settled a moment after it appears (or the app comes back): the gate's input, observable.
        .task(id: appearedAt) {
            CircleStage.shared.circleSettled = false
            guard await CircleGate.pause(CircleMomentTiming.settleAfterAppear) else { return }
            CircleStage.shared.circleSettled = true
        }
        // Dev preview: the Salah page, then this prayer as "next" for a moment, then the look's
        // transition exactly as the real one plays it (haptic included). Visual only — no prayer
        // rows, test times or notifications are touched.
        .onReceive(NotificationCenter.default.publisher(for: PrayerStartPreview.request)) { _ in
            playBeginsPreview()
        }
        .onChange(of: trackWantsSolid) { _, solid in settleTrack(solid) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            CircleStage.shared.sceneActive = phase == .active
            // Away mid-moment: it snaps to its end (its sleeps would otherwise fire back to back on return — audit A).
            if phase == .background { snapMoment() }
            if phase == .active {
                currentTime = Date(); appearedAt = Uptime.now
                // What changed while away is shown as it is, not played (the moment's cause was long ago).
                if momentKind == nil, displayedFace != derivedFace { quietly { displayedFace = derivedFace } }
                settleTrack(trackWantsSolid)
            }
        }
        .onAppear {
            currentTime = Date()
            if momentKind == nil { displayedFace = derivedFace }
            if summaryShowsScore == nil { summaryShowsScore = summaryWantsScore }   // pinned: a later sheet change flips it
        }
        // One timer for the view's lifetime. It was created inline in `body`, so every re-render made a
        // new one — and this view re-rendered on every compass update then (QiblaArrow has its own now), so the
        // timer was replaced before it ever fired: `currentTime` froze and a prayer that had started
        // showed an empty ring (owner, 2026-09-27: Isha 8:28 PM, empty; fixed by leaving the app).
        .onReceive(Self.ticker) { newTime in
            currentTime = newTime
//            prayer = viewModel.relevantPrayer
        }
    }

    private static let dayScoreAfterAppear: Double = 0.5

    /// The moment's haptic (the expanding track does the rest; the real start and the dev preview
    /// share it).
    private func playStartMoment() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    }

    /// Should the track be solid? Dashed only while the circle shows a prayer that hasn't started:
    /// an upcoming prayer, or the summary's next Fajr (sheet closed; with the sheet open it shows the
    /// day's score, solid). Solid while a completion sweeps or the tasbih is offered, so after a
    /// mark the track shrinks back only once the sweep is done.
    private var trackWantsSolid: Bool {
        _ = currentTime
        // A mark: solid from the moment it's made (before the flourish's first frame) until the flourish fades.
        if momentKind == .marking && !flourishOut { return true }
        if flourish != nil && !flourishOut { return true }   // fading out: the next state may come in
        // The face shown, not the data: the ring changes while the words are out, never before them.
        var face = displayedFace ?? derivedFace
        if case .morning = face { face = prayersFace }   // the morning keeps the track it will leave behind
        if case .lost = face {
            // The lost page's ring is the solid band; handing back, the prayer's track (under the mark meanwhile).
            guard CircleStage.shared.lost?.down == true else { return true }
            face = prayersFace
        }
        switch face {
        case .summary: return summaryShowsScore ?? summaryWantsScore   // the side shown: score solid, next Fajr dashed
        case .prayer(_, let status, _): return status != .upcoming
        case .morning, .lost: return true
        }
    }

    /// The one gate (circle rule 5): the circle can be seen and is settled — the app active, the Salah page with the
    /// pager still, nothing over it, no welcome landing or playing, a moment since it appeared. Every moment, the
    /// track's own animation, the qibla buzz and the real "prayer begins" ask this — they were five checks that had
    /// drifted (audit A). The list being open doesn't matter (marks are made from it).
    private var canPlay: Bool {
        CircleStage.shared.sceneActive && CircleStage.shared.restingPage == .main   // nil while the pager moves
            && CircleCover.nothingOverCircle
            && WelcomeTarget.canLand && !WelcomeTarget.playing
            && CircleStage.shared.circleSettled
    }

    private func quietly(_ change: () -> Void) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet, change)
    }

    /// Runs a moment (CircleMoments.swift): cancels the running one (snapped to its end first — a mark replacing a
    /// mark keeps its flourish up, the new one takes over), waits for `canPlay` up to the gate's deadline (else
    /// just `settle`s), plays `phases`, settles, and if the data moved on meanwhile, swaps once more.
    private func run(_ kind: CircleMomentKind, gated: Bool = true, settle: @escaping () -> Void,
                     _ phases: @escaping () async -> Void) {
        momentTask?.cancel()
        if let old = momentSettle, !(kind == .marking && momentKind == .marking) { quietly(old) }
        momentKind = kind
        momentSettle = settle
        momentTask = Task { @MainActor in
            // The opening plays at once (it is the launch); everything else waits until the circle can be seen.
            let play = gated ? await CircleGate.wait({ canPlay }) : true
            #if DEBUG
            if !play && !Task.isCancelled {
                NSLog("⭕️ circle \(kind) not played: active \(CircleStage.shared.sceneActive) · salah \(sharedState.horizontalPage == .main) · pager \(live?.pagerPhase.isScrolling ?? false ? "scrolling" : "still") · covers \(CircleCover.active) · canLand \(WelcomeTarget.canLand) · welcome \(WelcomeTarget.playing) · appeared \((Uptime.now - appearedAt))s")
            }
            #endif
            if play { await phases() }
            guard !Task.isCancelled else { return }
            quietly(settle)
            momentKind = nil
            momentSettle = nil
            momentTask = nil
            faceChanged()
        }
    }

    /// The sheet opened or closed over the summary: its words go out, the side (and its track) changes, they come in.
    /// Not the summary on the circle, or not on screen: the side is just set.
    private func flipSummary(to score: Bool) {
        // During a mark (the last prayer's: its face is the summary for the run's last half second) the side is just
        // pinned — a run here would cancel the mark and snap its flourish off (Sami's review of 15f71d5).
        guard case .summary = displayedFace ?? derivedFace, summaryShowsScore != nil, momentKind != .marking else {
            quietly { summaryShowsScore = score; summaryAway = false }
            return
        }
        run(.summaryFlip, settle: {
            summaryShowsScore = score
            summaryAway = false
        }) {
            summaryAway = true
            guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
            quietly { summaryShowsScore = score }   // the track follows the side shown (trackWantsSolid)
            guard await CircleGate.nextFrame() else { return }
            summaryAway = false
            _ = await CircleGate.pause(CircleMomentTiming.in)
        }
    }

    /// The post-salah offer goes once another prayer is on (its moment has passed) — from the data, so it goes too
    /// when the start isn't played (away, just appeared, off screen). Only clearing it in the begins moment left the
    /// last prayer's pill up (Sami's review of b5ceca5).
    private func dropStaleOffer() {
        guard let offered = live?.postSalahNudge, case .prayer(let p, .current, false) = derivedFace,
              p.name != offered, p.displayName != offered else { return }
        if canPlay { live?.postSalahNudge = nil } else { quietly { live?.postSalahNudge = nil } }
    }

    /// The running moment, cancelled and snapped to its end at once.
    private func snapMoment() {
        guard let task = momentTask else { return }
        task.cancel()
        if let settle = momentSettle { quietly(settle) }
        momentKind = nil
        momentSettle = nil
        momentTask = nil
    }

    /// The face from the data differs from the one shown: the words go out, the face (and with it the ring) changes,
    /// the new words come in. A mark syncs the face itself at its end. The prayer on the circle beginning (next → now)
    /// is this too, with the start's haptic: the real start and ▶︎ Prayer begins play the same moment. Not on screen
    /// (the gate), it's just shown as it is — no haptic.
    private func faceChanged() {
        guard displayedFace != nil, displayedFace != derivedFace else { return }
        // Under the opening the circle's words wait under its mark: the face is just set (the data arriving on a launch,
        // the morning card going up under it — its ring lands on that face, and its track).
        if momentKind == .opening {
            quietly { displayedFace = derivedFace }
            return
        }
        guard momentKind == nil else { return }
        let isState: Bool = { switch derivedFace { case .morning, .lost: true; default: false } }()
        // Just appeared (a launch: the data arriving a beat after the circle): shown as it is, like anything that
        // changed while away — played, its waits stretched on the busy launch and the circle sat empty ~1 s.
        if !CircleStage.shared.circleSettled {
            quietly { displayedFace = derivedFace }
            return
        }
        if isState, WelcomeTarget.playing || WelcomeGate.curtainUp || !canPlay {
            quietly { displayedFace = derivedFace }
            return
        }
        let begins: Bool = {
            guard case .prayer(let now, .current, _) = derivedFace else { return false }
            switch displayedFace {
            case .prayer(let was, .upcoming, _)?: return was == now
            // Before Fajr the circle shows the summary's next Fajr: Fajr beginning comes from there (Sami's review).
            case .summary?: return now.name == "Fajr"
            default: return false
            }
        }()
        run(begins ? .begins : .swap, settle: {
            displayedFace = derivedFace
            faceAway = false
        }) {
            faceAway = true
            guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
            // The new face while the words are out: its ring follows (trackWantsSolid reads the shown face) — a start's
            // dashes expand into the band from here.
            quietly { displayedFace = derivedFace }
            if begins { playStartMoment() }
            guard await CircleGate.nextFrame() else { return }
            faceAway = false
            _ = await CircleGate.pause(CircleMomentTiming.in)
        }
    }

    /// A prayer was marked (or ▶︎ Marking a prayer): the flourish over the circle, the face it was showing kept under it
    /// until the flourish ends, then the next face goes in while the words are still hidden, and they come back.
    private func playMarking(_ event: PrayerCompletionEvent) {
        // The list keeps the row until the flourish goes (one clock: this moment's).
        CircleStage.shared.holdRow(event.prayerName ?? event.name)
        run(.marking, settle: {
            flourish = nil
            flourishOut = false
            displayedFace = derivedFace
            CircleStage.shared.holdRow(nil)
        }) {
            flourishID += 1
            flourishOut = false
            withAnimation(.easeOut(duration: CircleMotion.flourishCoverDuration)) { flourish = event }
            guard await CircleGate.pause(CompletionFlourish.duration) else { return }
            // The next prayer / the summary goes in while the words are still hidden, with no animation (the name and
            // icon morphed Maghrib → Isha as they faded in), then fades in.
            quietly { displayedFace = derivedFace }
            flourishOut = true                    // fades on its own (implicit), the words fade in
            CircleStage.shared.holdRow(nil)       // the list folds the row now (it animates itself)
            // The post-salah pill under the top bar (it animates its own arrival). The original event's name even after
            // a Jumu'ah correction ("Dhuhr"), as the row's (Sami's review of 98eeedf).
            live?.postSalahNudge = event.name
            guard await CircleGate.pause(0.5) else { return }
            quietly { flourish = nil; flourishOut = false }
        }
    }

    /// ▶︎ Prayer begins (Settings → My Dev Stuff → Preview too): the Salah page, the prayer as "next" for a moment, then
    /// it begins, then back. A script over the preview's data (`preview`, `heldPrayer`): the circle plays each change
    /// with the same moments as the real data — a swap into "next", the begins moment, a swap back — so what's played
    /// is what he sees at a real start. With every prayer done, today's Fajr row is held on the circle for it. Visual
    /// only: no rows, times or notifications are touched.
    private func playBeginsPreview() {
        var held: PrayerModel?
        if viewModel.relevantPrayer == nil {
            guard let fajr = viewModel.todaysPrayers.first(where: { $0.name == "Fajr" }) else { return }
            held = fajr
        }
        previewTask?.cancel()
        withAnimation(CircleMotion.page) { sharedState.navPosition = .main }
        previewTask = Task { @MainActor in
            // Not played through (the circle never came into view): back to the real data, not stuck on the preview's.
            defer { if !Task.isCancelled { preview = nil; heldPrayer = nil } }
            await sharedState.navigate(to: .main)   // returns once the pager rests there
            guard await CircleStage.shared.until(deadline: CircleGate.deadline, { canPlay }) else { return }
            heldPrayer = held
            preview = .upcoming                                       // → into "next"
            guard await CircleGate.pause(CircleMomentTiming.swapDuration + Self.previewHold) else { return }
            preview = .current                                        // → it begins
            guard await CircleGate.pause(CircleMomentTiming.swapDuration + Self.previewHold) else { return }
            // Back to the real data: a face change like the others (the preview's arc goes while the words are out).
            preview = nil
            heldPrayer = nil
        }
    }

    /// How long ▶︎ Prayer begins holds each state so it can be seen.
    private static let previewHold: Double = 1.4

    private func settleTrack(_ solid: Bool) {
        let target: CGFloat = solid ? 1 : 0
        WelcomeTarget.trackDashed = !solid
        guard trackSolid != target else { return }
        if canPlay {
            // Expand like the welcome's ring into the track; narrow a touch quicker — after a mark, in the same fade as
            // the sweep, one move (it lingered under "NEXT" and then went: two steps — owner, 2026-10-02). The same in
            // every look (rule 9: Today's waited 0.45 s after the sweep, on a `.delay`).
            let animation: Animation = solid ? CircleMotion.trackExpand : .easeInOut(duration: CircleMotion.trackNarrowDuration)
            withAnimation(CircleMotion.movement(animation, reduced: reduceMotion)) { trackSolid = target }
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { trackSolid = target }
        }
    }

    /// Buzz on lining up with the qibla — only when this circle and its arrow can be seen (the
    /// Salah page, nothing over it, no tasbeeh session, not under its own map). The pager keeps
    /// every page mounted and sheets don't fire onDisappear, so the old on/off flag stayed on
    /// (it buzzed on the Zikr page, in sheets, History…). 2026-09-27 quick fix.
    private func checkToTriggerQiblaHaptic(aligned: Bool){
        guard aligned, canPlay, !showQiblaMap else { return }
        triggerSomeVibration(type: .heavy)
    }
    
    private func handleTap() {
        guard morningShown == nil, lostShown == nil else { return }
        // Only when the circle has text to flip. "Missed" and the day's score have none (a buzz
        // there felt like a broken button); the prayer's "ends / at" text is an
        // ExternalToggleText that buzzes by itself (this used to buzz a second time).
        let flipsOwnText: Bool   // true = ExternalToggleText, haptic included
        if let prayer = viewModel.relevantPrayer, !(prayer.status() == .upcoming && prayer.name == "Fajr") {
            guard prayer.status() == .current || prayer.status() == .upcoming else { return }
            flipsOwnText = true
        } else {
            // Summary circle: the next-Fajr side flips; the score side (salah sheet open) doesn't.
            guard sharedState.navPosition != .bottom else { return }
            flipsOwnText = false
        }
        if flipsOwnText {
            timeFlipPulse.toggle()   // it buzzes, flips and comes back by itself
            return
        }
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
    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true
    // FIXME: think this through more and make sure it makes sense.
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var sharedState: SharedStateClass
    @Query private var scores: [DailyPrayerScore]

    @Binding var ogText: Bool  // to control the toggle text in the middle
    /// The side shown and whether its words are out: MainCircleView's (its `flipSummary` moment). The score and next Fajr
    /// never crossfade through each other — one goes out, then the other comes in (owner, 2026-10-02).
    let showsScore: Bool
    let away: Bool
    @State private var nextFajr: (start: Date, end: Date)?
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

                        
        // Score ↔ next Fajr take turns — one goes out, then the other comes in (CircleMoments.swift), in every look;
        // Today's look crossfaded them inside the sheet's animation, "100.0" over "Fajr" mid-swap.
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
            .modifier(CircleWordsAway(away: away || !showsScore))

            // Fajr Icon, Title, Time — a prayer that hasn't started, so the future look (NEXT over
            // a dimmed name, the dashed track), keeping its own time text: "in 4 hr" ⇄ its window.
            VStack{
                HStack(alignment: .center, spacing: 8){
                    Image(systemName: prayerIcon(for: "Fajr"))
                        .font(.system(size: 22, weight: .light))
                    Text("Fajr")
                        .font(.system(size: 32, weight: .light, design: .rounded))
                }
                .foregroundStyle(Color.primary.opacity(0.55))
                .overlay(alignment: .top) {
                    NextTag(shown: showNextLabel)   // same tag as the main circle's
                }

                // Displayed Fajr Time:
                if let fajrTime = nextFajr{
                    ZStack{
                        if ogText{
                            // The app's own countdown ("in 8h 5m", seconds only under a minute) —
                            // `.relative` said "in 8 hr, 5 min" (owner, 2026-09-27). Its own clock:
                            // this view isn't redrawn by the circle's tick.
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(timeUntilStart(fajrTime.start))
                            }
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
            .modifier(CircleWordsAway(away: away || showsScore))
        }
        .transition(.opacity)
        .onAppear { getTheNextFajrTime() }
    }
    

}













/// The qibla arrow on the Salah circle and the dot it lights when you face the qibla. Its own view
/// so only it redraws with the compass (up to ~30 times a second) — the whole circle used to, which
/// is how its 1 s clock froze while the phone moved (2026-09-27) — and nothing above it does
/// (4789a97, the picker flicker). Dashed while there's no place yet or iOS says the heading can't
/// be trusted (the app's "not live" look; owner: a faint arrow wasn't clear); never green then.
private struct QiblaArrow: View {
    @EnvironmentObject private var compass: CompassState
    let onAligned: (Bool) -> Void
    let tap: () -> Void
    #if DEBUG
    @AppStorage("compassDebug") private var debug = false
    #endif

    var body: some View {
        let usable = compass.status == .ok
        let aligned = usable && compass.qibla.aligned
        ZStack {
            Group {
                if usable {
                    Image(systemName: "chevron.up")
                        .font(.subheadline)
                } else {
                    DashedChevron()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.2, 2.2]))
                        .frame(width: 15, height: 8)
                }
            }
                .foregroundColor(aligned ? .green : .primary)
                .background(
                    Circle() // a bigger tap area
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 44, height: 44)
                )
                .opacity(0.5)
                .offset(y: -80)
                // −180…180, so snapping to "aligned" turns the short way (it could spin a full turn).
                .rotationEffect(Angle(degrees: aligned ? 0 : compass.qibla.heading))
                .animation(CircleMotion.arrowSnap, value: aligned)
                .onChange(of: aligned) { _, isAligned in onAligned(isAligned) }
                .onTapGesture(perform: tap)

            // Aligned: a dot above the arrow.
            Circle()
                .fill(Color(.systemGray))
                .frame(width: 8, height: 8)
                .offset(y: -100)
                .opacity(aligned ? 1.0 : 0)

            #if DEBUG
            if debug {
                Text(compass.debugLine)
                    .font(.system(size: 9, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 128)
                    .allowsHitTesting(false)
            }
            #endif
        }
    }
}

/// The arrow's chevron as a path, for the dashed (can't-be-trusted) look.
private struct DashedChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
