import SwiftUI
import QuartzCore
import Foundation
import SwiftData


/// What's presented over the Salah page from views PrayerTimesView's `somethingCovers` can't see
/// (the What's new sheet, the ☰ popover, a prayer row's time editor). The circle counts as not on
/// screen while any is up — no qibla buzz, no track animation. 2026-09-27 review.
@MainActor enum CircleCover {
    private(set) static var active = Set<String>()
    static func set(_ key: String, _ on: Bool) {
        if on { active.insert(key) } else { active.remove(key) }
    }
    /// The morning card is a cover for prompts (they wait for it) but not over the circle: its page has a hole there,
    /// and the circle shows the morning itself (circle step 3).
    static let besideCircle: Set<String> = ["morningCard"]
    static var nothingOverCircle: Bool { active.subtracting(besideCircle).isEmpty }
}

struct MainCircleView: View {
    /// The circle's 1 s clock (see `.onReceive(Self.ticker)`): created once, never per render.
    private static let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// "NEXT" above a prayer that hasn't started, or the dashed ring alone (dev toggle, NextLabel).
    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true
    /// The soft ring (the theme, CircleTheme.swift).
    @Environment(\.circleTheme) private var theme
    private var softRing: Bool { theme.softRing }
    @EnvironmentObject var sharedState: SharedStateClass
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var locationManager: EnvLocationManager   // only to start updates; publishes rarely
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @State private var ogText = true  // to control the toggle text in the middle
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
    /// What the circle shows at rest, from the data: the morning card's session while it's up, else the prayers'.
    private var derivedFace: CircleFace {
        if let session = CircleStage.shared.morning { return .morning(session) }
        return prayersFace
    }
    /// The prayer on the circle, or the day's summary (none; or the next prayer is tomorrow's Fajr).
    private var prayersFace: CircleFace {
        _ = currentTime
        guard let p = viewModel.relevantPrayer, !(p.status() == .upcoming && p.name == "Fajr") else { return .summary }
        return .prayer(p)
    }
    /// The morning card's session, while the circle shows it.
    private var morningShown: SessionDataModel? {
        if case .morning(let session) = displayedFace ?? derivedFace { return session }
        return nil
    }
    /// The prayer the circle draws, if its face is a prayer.
    private var shownPrayer: PrayerModel? {
        if let heldPrayer { return heldPrayer }
        if case .prayer(let p) = displayedFace ?? derivedFace { return p }
        return nil
    }
    /// The prayer on the circle just came into its window, on screen: the moment plays once.
    /// The track: 0 = dashed (a prayer that hasn't started), 1 = the solid band (`CircleTrack`).
    @State private var trackSolid: CGFloat = 1
    /// When the last completion sweep faded: the track's shrink waits for it to be gone.
    @State private var flourishEndedAt: TimeInterval?
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
    
//    private var prayer: PrayerModel? { viewModel.relevantPrayer }
//    @State private var prayer: PrayerModel?

    
    var body: some View {
        ZStack {
            // The soft ring's raised band, under everything and always there — for a prayer still to come too, with
            // the dashes drawn in it (owner, 2026-10-02: "make the future ring also soft… dashed ring inside the
            // track"). It stays through the completion flourish (which hides the content above) and for the day's
            // score (SalahLook.swift).
            if softRing && sharedState.bottomTabPosition != .zikr {
                NeuRingTrack()
            }
            // main outer circle: dashed for a prayer that hasn't started, the solid band otherwise
            CircleTrack(solid: trackSolid, reduceMotion: reduceMotion, band: !softRing)
                // Where the welcome's ring lands (WelcomeAnimation.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    WelcomeTarget.circleFrame = $0
                    WelcomeTarget.salahCircleFrame = $0   // only this circle writes it (the lost page lands on it)
                }
            
            //Inner Content — hidden while a completion flourish plays over it (PrayerCompletionFX)
            Group {
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
                else if let session = morningShown {
                    // The morning after a sleep finish: the session in the ring, the card's page round it (SleepMode).
                    MorningFace(session: session)
                        .transition(.opacity)
                }
                else if let prayer = shownPrayer, preview != nil || !(prayer.status() == .upcoming && prayer.name == "Fajr") {
                    // The real state, or the dev preview's.
                    let status = preview ?? prayer.status()
                    var progress: Double {
                        // Not started: 0, so when it starts the arc grows from nothing (it was 1 in
                        // a clear colour, and sprang back from full to empty, green, at the start).
                        if status == .upcoming { return 0 }
                        // The dev preview of a prayer beginning: from (almost) nothing, as a real start does — its
                        // own clock drew it already most of the way round (Sami's audit, finding 8).
                        if preview == .current { return 0.015 }
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
                        if preview == .current { return .green }   // the preview's start (a held row is long past)
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
                        // "Next" → "now": the track expands (trackSolid) while NEXT and the name's
                        // dimming crossfade (2026-09-27).
                        // In the Perfect (green) window under the soft ring, the arc is the tasbeeh ring's living fill
                        // (AliveRingFill, "fine") cut to the arc — "it deserves it … we want to beautify when we are in
                        // that period of prayer" (owner, 2026-10-01). Yellow / red stay the solid arc below.
                        let perfectNow = softRing && progress < 1 && PrayerScoring.grade(for: PrayerScoring.score(
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
                            .stroke( progressColor, style: StrokeStyle(lineWidth: softRing ? AliveRingTuning.fine.band : 4,
                                                                       lineCap: softRing ? .round : .butt)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                            .shadow(color: softRing ? progressColor.opacity(AliveRingTuning.fine.glow) : .clear, radius: 6)
                            .opacity(perfectNow ? 0 : 1)
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
                                    // A small tag set apart, not a line of the stack (NextTag;
                                        // tuned in the DEBUG NEXT label playground).
                                    NextTag(shown: upcoming && showNextLabel)
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
            // Between two faces (the summary ↔ a prayer, one prayer → the next) the words go out, then the new ones come
            // in (a swap moment) — they crossfaded through each other.
            .modifier(CircleWordsAway(away: faceAway))
            // Out quickly under the flourish (its arc sits on the prayer's own, so the ring never
            // blinks), back in as it fades.
            .opacity(contentHidden ? 0 : 1)
            .blur(radius: contentHidden ? 4 : 0)
            .animation(contentHidden ? .easeOut(duration: 0.25) : (softRing ? .easeOut(duration: 0.4) : .easeInOut(duration: 0.45)),
                       value: contentHidden)

            if let flourish {
                CompletionFlourish(event: flourish)
                    .id(flourishID)
                    .opacity(flourishOut ? 0 : 1)
                    .animation(.easeInOut(duration: 0.45), value: flourishOut)
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
                            if let prayer = viewModel.relevantPrayer, prayer.status() != .upcoming {
                                viewModel.togglePrayerCompletion(for: prayer)
                                // The post-salah pill follows the flourish (.prayerCompleted).
                            }
                        }
                )
            
            
            

            if sharedState.bottomTabPosition != .zikr && morningShown == nil {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // The prayer day, not the calendar date: after midnight (before the rollover)
                // Date() is tomorrow's rows, so today's score was never set and read 0 %.
                viewModel.calculateDayScore(for: PrayerDay.date())
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompleted)) { note in
            guard let event = note.object as? PrayerCompletionEvent else { return }
            playMarking(event)
        }
        // The data moved the face (an unmark, a window ending, Fajr beginning from the summary…): out, then in.
        .onChange(of: derivedFace) { _, _ in faceChanged() }
        // The offer goes once the next prayer has begun (its moment has passed).
        .onChange(of: viewModel.relevantPrayer?.name) { _, name in
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
                  scenePhase == .active, (Uptime.now - appearedAt) > 2,
                  sharedState.horizontalPage == .main, WelcomeTarget.canLand,
                  momentKind == nil, flourish == nil else { return }
            playStartMoment()
            print("🌅 prayer begins moment played (\(new))")
        }
        // Dev preview: the Salah page, then this prayer as "next" for a moment, then the look's
        // transition exactly as the real one plays it (haptic included). Visual only — no prayer
        // rows, test times or notifications are touched.
        .onReceive(NotificationCenter.default.publisher(for: PrayerStartPreview.request)) { _ in
            playBeginsPreview()
        }
        .onChange(of: trackWantsSolid) { _, solid in settleTrack(solid) }
        .onChange(of: scenePhase) { _, phase in
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
        if let preview { return preview != .upcoming }
        // The face shown, not the data: the ring changes while the words are out, never before them.
        var face = displayedFace ?? derivedFace
        if case .morning = face { face = prayersFace }   // the morning keeps the track it will leave behind
        switch face {
        case .summary: return sharedState.navPosition == .bottom   // summary: score solid, next Fajr dashed
        case .prayer(let p): return p.status() != .upcoming
        case .morning: return true
        }
    }

    /// The circle can be seen (the Salah page, nothing over it, app active, settled) — only then
    /// does the track animate; otherwise it just is what it should be.
    private var circleOnScreen: Bool {
        scenePhase == .active && sharedState.horizontalPage == .main && WelcomeTarget.canLand
            && CircleCover.nothingOverCircle && (Uptime.now - appearedAt) > 0.6
    }

    /// A moment may play: the circle is seen and settled — the app active, the Salah page with the pager still,
    /// nothing over it, no welcome playing, at least 0.6 s since it appeared. The list being open doesn't matter
    /// (marks are made from it).
    private var canPlay: Bool {
        UIApplication.shared.applicationState == .active && sharedState.horizontalPage == .main
            && !(live?.pagerPhase.isScrolling ?? false) && CircleCover.nothingOverCircle
            && WelcomeTarget.canLand && !WelcomeTarget.playing && (Uptime.now - appearedAt) > 0.6
    }

    private func quietly(_ change: () -> Void) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet, change)
    }

    /// Runs a moment (CircleMoments.swift): cancels the running one (snapped to its end first — a mark replacing a
    /// mark keeps its flourish up, the new one takes over), waits for `canPlay` up to the gate's deadline (else
    /// just `settle`s), plays `phases`, settles, and if the data moved on meanwhile, swaps once more.
    private func run(_ kind: CircleMomentKind, settle: @escaping () -> Void, _ phases: @escaping () async -> Void) {
        momentTask?.cancel()
        if let old = momentSettle, !(kind == .marking && momentKind == .marking) { quietly(old) }
        momentKind = kind
        momentSettle = settle
        momentTask = Task { @MainActor in
            let play = await CircleGate.wait({ canPlay })
            #if DEBUG
            if !play && !Task.isCancelled {
                NSLog("⭕️ circle \(kind) not played: active \(UIApplication.shared.applicationState == .active) · salah \(sharedState.horizontalPage == .main) · pager \(live?.pagerPhase.isScrolling ?? false ? "scrolling" : "still") · covers \(CircleCover.active) · canLand \(WelcomeTarget.canLand) · welcome \(WelcomeTarget.playing) · appeared \((Uptime.now - appearedAt))s")
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

    /// The face from the data differs from the one shown: the words go out, the face (and with it the ring) changes,
    /// the new words come in. A mark or a preview syncs the face itself at its end.
    private func faceChanged() {
        guard momentKind == nil, displayedFace != nil, displayedFace != derivedFace else { return }
        // The morning goes up under the welcome (its ring lands on this one): there at once, nothing to play.
        if case .morning = derivedFace, WelcomeTarget.playing || WelcomeGate.curtainUp || !canPlay {
            quietly { displayedFace = derivedFace }
            return
        }
        run(.swap, settle: {
            displayedFace = derivedFace
            faceAway = false
        }) {
            faceAway = true
            guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
            quietly { displayedFace = derivedFace }
            guard await CircleGate.nextFrame() else { return }
            faceAway = false
            _ = await CircleGate.pause(CircleMomentTiming.in)
        }
    }

    /// A prayer was marked (or ▶︎ Marking a prayer): the flourish over the circle, the face it was showing kept under it
    /// until the flourish ends, then the next face goes in while the words are still hidden, and they come back.
    private func playMarking(_ event: PrayerCompletionEvent) {
        run(.marking, settle: {
            flourish = nil
            flourishOut = false
            displayedFace = derivedFace
        }) {
            flourishID += 1
            flourishOut = false
            withAnimation(.easeOut(duration: 0.25)) { flourish = event }
            guard await CircleGate.pause(CompletionFlourish.duration) else { return }
            flourishEndedAt = Uptime.now
            // The next prayer / the summary goes in while the words are still hidden, with no animation (the name and
            // icon morphed Maghrib → Isha as they faded in), then fades in.
            quietly { displayedFace = derivedFace }
            flourishOut = true                    // fades on its own (implicit), the words fade in
            withAnimation(.easeInOut(duration: 0.45)) {
                live?.postSalahNudge = event.name   // the post-salah pill under the top bar
            }
            guard await CircleGate.pause(0.5) else { return }
            quietly { flourish = nil; flourishOut = false }
        }
    }

    /// ▶︎ Prayer begins (Settings → My Dev Stuff → Preview too): the Salah page, the prayer as "next" for a moment, then
    /// it begins as a real start does (haptic included), then back. With every prayer done, today's Fajr row is held on
    /// the circle for it. Visual only: no rows, times or notifications are touched.
    private func playBeginsPreview() {
        var held: PrayerModel?
        if viewModel.relevantPrayer == nil {
            guard let fajr = viewModel.todaysPrayers.first(where: { $0.name == "Fajr" }) else { return }
            held = fajr
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            sharedState.navPosition = .main
            sharedState.horizontalPage = .main
        }
        run(.begins, settle: {
            preview = nil
            heldPrayer = nil
            faceAway = false
            displayedFace = derivedFace
        }) {
            if let held {
                // From the summary to Fajr: out, then in, like any face change.
                faceAway = true
                guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
                quietly { heldPrayer = held; preview = .upcoming }
                guard await CircleGate.nextFrame() else { return }
                faceAway = false
            } else {
                quietly { preview = .upcoming }                      // straight into "next"
            }
            guard await CircleGate.pause(1.4) else { return }
            preview = .current                                      // …and it begins
            playStartMoment()
            guard await CircleGate.pause(1.4) else { return }
            if held != nil {
                faceAway = true
                guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
                quietly { preview = nil; heldPrayer = nil; displayedFace = derivedFace }
                guard await CircleGate.nextFrame() else { return }
                faceAway = false
                _ = await CircleGate.pause(CircleMomentTiming.in)
            } else {
                preview = nil                                       // back to the real state
            }
        }
    }

    private func settleTrack(_ solid: Bool) {
        let target: CGFloat = solid ? 1 : 0
        WelcomeTarget.trackDashed = !solid
        guard trackSolid != target else { return }
        if circleOnScreen && preview != .upcoming {
            // Expand like the welcome's ring into the track; shrink a touch quicker. Right after a
            // completion the shrink waits until the green sweep has faded, or it happens hidden
            // under it.
            // Soft ring: no wait — its band narrows into the dashes in the same fade as the sweep, one move (it
            // lingered under "NEXT" and then went: two steps — owner, 2026-10-02).
            let afterSweep = !softRing && !solid && (flourishEndedAt.map { Uptime.now - $0 < 1 } ?? false)
            let animation: Animation = reduceMotion ? .easeInOut(duration: 0.35)
                : solid ? .spring(response: 0.75, dampingFraction: 0.9) : .easeInOut(duration: softRing ? 0.5 : 0.6)
            withAnimation(afterSweep ? animation.delay(0.45) : animation) { trackSolid = target }
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { trackSolid = target }
        }
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

    /// Buzz on lining up with the qibla — only when this circle and its arrow can be seen (the
    /// Salah page, nothing over it, no tasbeeh session, not under its own map). The pager keeps
    /// every page mounted and sheets don't fire onDisappear, so the old on/off flag stayed on
    /// (it buzzed on the Zikr page, in sheets, History…). 2026-09-27 quick fix.
    private func checkToTriggerQiblaHaptic(aligned: Bool){
        guard aligned, circleOnScreen, !showQiblaMap else { return }
        triggerSomeVibration(type: .heavy)
    }
    
    private func handleTap() {
        guard morningShown == nil else { return }
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
    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true
    // FIXME: think this through more and make sure it makes sense.
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var sharedState: SharedStateClass
    @Query private var scores: [DailyPrayerScore]

    @Binding var ogText: Bool  // to control the toggle text in the middle
    @State private var animationBool: Bool = false
    @State private var nextFajr: (start: Date, end: Date)?
    /// The score and next Fajr never crossfade through each other — one goes out, then the other comes in (owner,
    /// 2026-10-02: "today score to next upcoming fajr … i don't see the transition"; mid-swap "100.0" sat on "Fajr";
    /// every look since circle step 2). `.neither` = between the two; nil only before it first appears (the side the
    /// sheet asks for — nothing fades in then).
    @State private var shownSide: SummarySideShown?
    private enum SummarySideShown { case score, fajr, neither }
    private var showingScore: Bool? {
        switch shownSide ?? (wantsScore ? .score : .fajr) {
        case .score: true
        case .fajr: false
        case .neither: nil
        }
    }
    /// The swap's one task (the circle system's rule: one runner per moment; a newer toggle cancels it).
    @State private var swapTask: Task<Void, Never>?
    private var wantsScore: Bool { sharedState.navPosition == .bottom && sharedState.bottomTabPosition == .salah }
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
            .modifier(CircleWordsAway(away: showingScore != true))

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
            .modifier(CircleWordsAway(away: showingScore != false))
        }
        .transition(.opacity)
        .onChange(of: wantsScore) { _, score in
            swapTask?.cancel()
            swapTask = Task { @MainActor in
                shownSide = .neither
                guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }   // toggled again: the newer swap wins
                shownSide = score ? .score : .fajr
            }
        }


        .onAppear {
            // Pinned to the side it shows now (unchanged, so nothing animates): a later sheet change then swaps from it.
            if shownSide == nil { shownSide = wantsScore ? .score : .fajr }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: aligned)
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
