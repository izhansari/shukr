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
    @Environment(SharedStateClass.self) var sharedState
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
    /// The missed face (after Isha, until Fajr), tapped: the line says the total owed and "See all ›" opens To make up
    /// (owner, 2026-10-19: "make tap show total amount of prayers to make up with link to “to make up”"). Back on a second
    /// tap; never on its own.
    @State private var makeUpShowsAll = false
    @State private var makeUpTotal: Int?
    /// The flip's out, then in: the name row and the line go away together, swap, come back (CircleWordsAway).
    @State private var makeUpAway = false
    @State private var makeUpFlip: Task<Void, Never>?
    @Environment(\.modelContext) private var circleContext
    /// A prayer was just marked done: the flourish plays over the circle, then clears.
    @State private var flourish: PrayerCompletionEvent?
    @State private var flourishID = 0
    /// The flourish fades out on its own opacity (an implicit animation) while still mounted, then goes quietly: its
    /// removal transition never animated, so the full ring cut out in one frame and the arc faded in from nothing — a
    /// blink at the end of every mark (Sami's audit, 2026-10-02, finding 1; his verified fix).
    @State private var flourishOut = false
    /// Today's prayers as the mark left them: the day ring the flourish folds into (CompletionFlourish).
    @State private var flourishDay: [DayPrayer] = []
    /// A tap on the circle while a mark's flourish holds: it goes now (out, then the next face in).
    @State private var flourishSkipped = false
    /// The day's page comes next (the fifth of the five, the list up): the flourish's ring stays while the page's own,
    /// already whole, comes in under it, then goes unseen.
    @State private var flourishLands = false
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
    /// The opening's arc: from nothing to where the prayer stands as the ring lands (nil = where it stands). Owner:
    /// "I want it to animate from the beginning to its position … instead of just appearing and fading in the whole
    /// thing at 70%" (ask opening-ring-fill).
    @State private var arcSweep: Double?
    @State private var arcSweepTask: Task<Void, Never>?
    /// The sweep is moving: the 1 s tick waits (a tick redraws the arc with animations off, and that snapped the sweep to
    /// its end mid-way — owner: "sometimes it just jumps").
    @State private var sweeping = false
    /// What the circle shows at rest, from the data: the morning card's session while it's up, else the prayers'.
    private var derivedFace: CircleFace {
        if let lost = CircleStage.shared.lost, !lost.landed { return .lost }
        if let session = CircleStage.shared.morning { return .morning(session) }
        // Excused (Excused.swift): only with the list open (owner: the circle keeps showing the time, a little privacy).
        if let range = CircleStage.shared.excused, sharedState.navPosition == .bottom { return .excused(range) }
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
    /// Excused from prayer, while the circle shows it.
    private var excusedShown: ExcusedRange? {
        if case .excused(let range) = displayedFace ?? derivedFace { return range }
        return nil
    }
    /// The morning card's session, while the circle shows it.
    private var morningShown: SessionDataModel? {
        if case .morning(let session) = displayedFace ?? derivedFace { return session }
        return nil
    }
    /// The prayer the circle draws, if its face is a prayer.
    /// The day's score side is up (summaryCircle's day ring takes taps on the band).
    private var daySummaryShowing: Bool {
        guard case .summary = displayedFace ?? derivedFace else { return false }
        return summaryShowsScore ?? summaryWantsScore
    }

    /// Whether the clock moving to `next` changes the ring's colour (its grade, as `progressColor` reads it).
    private func tickChangesColor(to next: Date) -> Bool {
        guard let p = shownPrayer else { return false }
        func grade(_ at: Date) -> PrayerScoring.Grade {
            PrayerScoring.grade(for: PrayerScoring.score(start: p.startTime, end: p.endTime, markedAt: at))
        }
        return grade(currentTime) != grade(next)
    }

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
    /// The day's disc: 0.5 = flush with the page (unseen), 1 = raised (NeuLiftCard's `lift`); up on the score side.
    @State private var discLift: CGFloat = 0.5
    /// Drawn only while up or on its way down (flush, it would still cover what's behind the circle).
    @State private var discShown = false
    /// The dashed ring's drawing (CircleTrack.dashesDrawn): 0 → 1 as a prayer still to come comes in.
    @State private var dashesDrawn: CGFloat = 1
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
                // The day's score side: the whole circle raised, the fifths on it (owner) — under the band, which
                // gives way as it rises.
                if discShown {
                    NeuLiftCard(shape: Circle(), lift: discLift)
                        .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
                        // In the ring's own 200 pt box, drawing past it: at its own size the circle's layout grew while
                        // it showed and jumped back when it went.
                        .frame(width: 200, height: 200)
                        .opacity(openingHides ? 0 : 1)
                        .allowsHitTesting(false)
                }
                NeuRingTrack()
                    .opacity(openingHides ? 0 : 1 - Double(discLift - 0.5) * 2)
                    // ▶︎ Opening over the page as it is: the track fades out first (a launch has nothing to fade).
                    .animation(CircleStage.shared.opening?.inPlace == true ? .easeOut(duration: CircleMotion.openingTrackOutDuration) : nil, value: openingHides)
            }
            // main outer circle: dashed for a prayer that hasn't started, the solid band otherwise
            CircleTrack(solid: trackSolid, dashesDrawn: dashesDrawn, reduceMotion: reduceMotion, band: !theme.track.lifted)
                .opacity(openingHides ? 0 : 1)
                    // ▶︎ Opening over the page as it is: the track fades out first (a launch has nothing to fade).
                    .animation(CircleStage.shared.opening?.inPlace == true ? .easeOut(duration: CircleMotion.openingTrackOutDuration) : nil, value: openingHides)
                // Where the welcome's ring lands (WelcomeAnimation.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    WelcomeTarget.circleFrame = $0   // only this circle writes it
                    TourTargets.shared.circleMoved($0)   // the tour's, settled (Tour.swift)
                }
            
            //Inner Content — hidden while a completion flourish plays over it (PrayerCompletionFX)
            Group {
                if let lost = lostShown {
                    // Location lost (step 3b): the crossed-out symbol in the ring; its words round it (LostWords).
                    LostFace(stage: lost)
                        .transition(.opacity)
                }
                else if let range = excusedShown {
                    // Excused from prayer: what it is and the day, nothing to mark (Excused.swift).
                    ExcusedFace(range: range, now: currentTime)
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
                        // The tour's colours step draws its sweep directly, every frame (Tour.swift `colorSweep`).
                        if let sweep = TourRuntime.shared.colorSweep, TourRuntime.shared.isPractice(prayer) { return sweep }
                        guard status == .current else { return 1 }
                        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
                        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
                        let endVal = elapsed / totalDuration
                        return max(endVal, 0)
                    }
                    /// The score you'd get marking it now (PrayerScoring): green Perfect, yellow Middle,
                    /// red Closing. Was elapsed-time bands (yellow past 50 %) that didn't match the score.
                    var progressColor: Color {
                        if progress >= 1 { return .clear }
                        if shownIsPreview && status == .current { return .green }   // the preview's start (a held row is long past)
                        if let sweep = TourRuntime.shared.colorSweep, TourRuntime.shared.isPractice(prayer) {
                            return TourRuntime.sweepColor(sweep)   // blended across each change
                        }
                        return PrayerScoring.color(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: currentTime))
                    }
                    let upcoming = status == .upcoming
                    ZStack{
                        // "Next" → "now": the track expands (trackSolid) while NEXT and the name's
                        // dimming crossfade (2026-09-27).
                        // In the Perfect (green) window under the soft ring, the arc is the tasbeeh ring's living fill
                        // (AliveRingFill, "fine") cut to the arc — "it deserves it … we want to beautify when we are in
                        // that period of prayer" (owner, 2026-10-01). Yellow / red stay the solid arc below.
                        // Not during the tour's colour sweep: the swap to the solid arc at yellow popped (owner).
                        // Started, too: before the window a "score now" grades Perfect, and the fill (30 fps, ~700 specks,
                        // trimmed to nothing) ran from one prayer to the next — ~15 % CPU with the app just open (battery
                        // check, 2026-10-10).
                        let perfectNow = theme.arc.alivePerfect && progress > 0 && progress < 1
                            && currentTime >= prayer.startTime && TourRuntime.shared.colorSweep == nil
                            && PrayerScoring.grade(for: PrayerScoring.score(
                            start: prayer.startTime, end: prayer.endTime, markedAt: currentTime)) == .perfect
                        if perfectNow {
                            AliveRingFill(dark: colorScheme == .dark, tuning: .fine, tag: "salah ring \(prayer.name)")
                                .frame(width: 230, height: 230)
                                .mask {
                                    Circle()
                                        .trim(from: 0, to: progress * (arcSweep ?? 1))
                                        .stroke(style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 200, height: 200)
                                        .animation(animationStyle, value: currentTime)
                                }
                                .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 6)
                                .allowsHitTesting(false)
                                // Fades as the tour's colour sweep takes the ring (its own animation: the sweep's
                                // change carries none). Only in the tour — a real prayer's moment is untouched.
                                .transition(TourRuntime.shared.active
                                            ? .opacity.animation(.easeInOut(duration: CircleMotion.quick)) : .identity)
                        }
                        // progress arc. Under the soft ring it takes the tasbeeh arc's shape (NeuCircularProgressView,
                        // "fine"): as wide as the band, round ends, a soft glow in its own colour (owner, 2026-10-01).
                        Circle()
                            .trim(from: 0, to: progress * (arcSweep ?? 1)) // Adjust progress value (0 to 1)
                            .stroke(progressColor, style: StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                            .shadow(color: progressColor.opacity(theme.arc.glow), radius: 6)   // glow 0 = none
                            .opacity(perfectNow ? 0 : 1)
                            // The tour's colour sweep coming or going: the arc and the living fill cross-fade (it popped
                            // in one frame). Only then — the real ring's moments are untouched.
                            .animation(.easeInOut(duration: CircleMotion.quick), value: TourRuntime.shared.colorSweep == nil)
                            .animation(animationStyle, value: currentTime/*progress*/)
                    
                        // Inner content
                        ZStack{
                            VStack{
                                // Same type as the Insights ring: large, light, rounded.
                                HStack(alignment: .center, spacing: 8){
                                    if showsMakeUpTotal(status) {
                                        // Tapped, owed: the total in the name's place, and the line finishes the phrase
                                        // (owner, 2026-10-19: "change the prayer name to number and bottom finishes the phrase").
                                        Text("\(makeUpTotal ?? missedToday)")
                                            .font(.system(size: 32, weight: .light, design: .rounded))
                                            .monospacedDigit()
                                    } else {
                                        Image(systemName: prayerIcon(for: prayer.name))
                                            .font(.system(size: 22, weight: .light))
                                        Text(prayer.name)
                                            .font(.system(size: 32, weight: .light, design: .rounded))
                                    }
                                }
                                .modifier(CircleWordsAway(away: makeUpAway && status == .missed))
                                // Next ⇄ now changes only inside a moment, while the words are out (the face carries it).
                                .foregroundStyle(upcoming ? Color.primary.opacity(0.55) : Color.primary)
                                // Not started yet: "NEXT" above the name (owner: an empty ring read
                                // like a prayer that's on). An overlay, so the name sits at the same
                                // spot whether the prayer is next or current — it used to jump.
                                .overlay(alignment: .top) {
                                    // A small tag set apart, not a line of the stack (NextTag;
                                        // tuned in the DEBUG NEXT label playground).
                                    // The tour's pretend prayer says so (Tour.swift).
                                    NextTag(shown: (upcoming && showNextLabel) || TourRuntime.shared.isPractice(prayer),
                                            label: TourRuntime.shared.isPractice(prayer) ? "practice" : "next")
                                }
                                if let line = TourHints.shared.circleLine {
                                    // The tour's words in the time line's place (Tour.swift).
                                    Text(line)
                                        .font(.subheadline).fontDesign(.rounded).fontWeight(.thin)
                                        .foregroundStyle(.secondary)
                                }
                                else if status == .current{
                                    // The tour's colours demo runs the line on its own clock: the last hour shows the
                                    // time left, as the real ring does (owner).
                                    PrayerTimeLine(end: prayer.endTime, now: TourRuntime.shared.sweepNow(for: prayer) ?? currentTime,
                                                   lastHourLeft: !prayer.isCompleted && !shownIsPreview,
                                                   prayerKey: prayer.name, trigger: timeFlipPulse,
                                                   labelShift: PracticeClock.shift(for: prayer),
                                                   holds: TourRuntime.shared.step == .circle)
                                }
                                else if status ==  .upcoming{
                                    ExternalToggleText(
                                        originalText: "at \(shortTimePM(PracticeClock.shown(prayer.startTime, of: prayer)))",
                                        toggledText: timeUntilStart(prayer.startTime),
                                        externalTrigger: $timeFlipPulse,
                                        font: .subheadline,
                                        fontDesign: .rounded,
                                        fontWeight: .thin,
                                        hapticFeedback: true
                                    )
                                    .foregroundStyle(.secondary)
                                }else {
                                    // Owed: "to make up" / "and more to make up"; tapped, the total (MakeUpLine).
                                    MakeUpLine(text: showsMakeUpTotal(status) || missedToday <= 1 ? "to make up" : "and more to make up",
                                               quiet: makeUpAway)
                                        .modifier(CircleWordsAway(away: makeUpAway))
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
                else {
                    // Equatable on its three inputs: the circle's body runs every second (its clock) and on every page
                    // or list change, and the day's page (~1.5 ms a body) ran with it each time (paging lag, 2026-10-10).
                    // Its own data (the day's rows, photos, scores) still redraws it directly.
                    summaryCircle(ogText: $ogText, showsScore: summaryShowsScore ?? summaryWantsScore, away: summaryAway)
                        .equatable()
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
                CompletionFlourish(event: flourish, day: flourishDay)
                    .id(flourishID)
                    .opacity(flourishSkipped || (flourishOut && !flourishLands) ? 0 : 1)
                    .animation(.easeInOut(duration: CircleMotion.flourishOutDuration), value: flourishOut)
                    .animation(.easeOut(duration: CircleMomentTiming.out), value: flourishSkipped)
                    // In at once (its arc takes over from the prayer's in place), out with a fade.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }

            
            // tappable circle on top (cant mix with outer circle cuz then the progress goes under the circle stroke)
            Circle()
                .fill(Color(.systemBackground).opacity(0.001))
                .frame(width: 200, height: 200)
                // The day's page: the band is the day ring's (a tap there tells that prayer), the middle stays this one's.
                .contentShape(Circle().inset(by: daySummaryShowing ? 26 : 0))
                .onTapGesture {
                    handleTap()  // Toggle the trigger
                }
                // A prayer's photo or the make-up pill in the day page's centre takes its own tap.
                .allowsHitTesting(!(daySummaryShowing && DayPageState.shared.centreTakesTaps))
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            // Not while a mark's flourish is up: the circle shows the prayer just marked, but this acts
                            // on the next one (audit A).
                            guard momentKind != .marking, flourish == nil else { return }
                            if let prayer = viewModel.relevantPrayer, prayer.status() != .upcoming {
                                let marking = !prayer.isCompleted
                                // The tour lets only its own moves through (Ben's G1): a hold on step 1 marks nothing.
                                guard TourRuntime.shared.allows(marking: marking, prayer) else {
                                    TourRuntime.shared.nudge()   // the tour: not yet — a pulse, no buzz (owner)
                                    return
                                }
                                viewModel.togglePrayerCompletion(for: prayer)
                                // The tour's Mark step (a practice the user undoes next), or a first mark's celebration.
                                if marking { TourRuntime.shared.event(.marked(prayer, viewModel)) }
                                if marking, let container = prayer.modelContext?.container {
                                    MilestoneCelebration.shared.check(container: container)
                                }
                            }
                        }
                )

            // The missed face tapped open: "See all ›" at the bottom inside the ring, over the tap layer so it takes its own
            // tap (a tap anywhere else in the ring flips back). Opens To make up, as the day page's pill does.
            if makeUpShowsAll && missedFaceShown {
                MakeUpSeeAll {
                    JourneyPresenter.shared.makeUp = true
                    JourneyPresenter.shared.open = true
                }
                .offset(y: 64)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: CircleMomentTiming.in).delay(CircleMomentTiming.out)),
                    removal: .opacity.animation(.easeOut(duration: CircleMomentTiming.out))))
            }

            if morningShown == nil && lostShown == nil && !openingHides {
                // Its own view: only the arrow redraws with the compass, not the whole circle.
                QiblaArrow(onAligned: { checkToTriggerQiblaHaptic(aligned: $0) },
                           tap: {
                               // Inside the circle's opening, but not the tour's move (Sami): no map during the tour —
                               // except its own map step (the new flow).
                               guard !TourRuntime.shared.active || TourRuntime.shared.allowsMap else { TourRuntime.shared.nudge(); return }
                               TourRuntime.shared.event(.mapOpened); showQiblaMap = true
                           })
                    // Not on the day's score ring at all (owner, 2026-10-16: "when we're showing the day score ring, get rid of
                    // the compass arrow").
                    .opacity(daySummaryShowing ? 0 : 1)
                    .allowsHitTesting(!daySummaryShowing)
                    .animation(.easeOut(duration: CircleMotion.quick), value: daySummaryShowing)
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
        // The tour's map step: → closes the map for them; the map gone, by → or by itself, the tour knows.
        .onChange(of: TourRuntime.shared.closeMapRequests) { _, _ in showQiblaMap = false }
        .onChange(of: TourRuntime.shared.openMapRequests) { _, _ in showQiblaMap = true }   // the qibla's →
        .onChange(of: showQiblaMap) { _, open in if !open { TourRuntime.shared.mapClosed() } }
        // Off the missed face (marked, Fajr, a page change underneath): the line starts over on "to make up".
        .onChange(of: missedFaceShown) { _, shown in
            if !shown { makeUpFlip?.cancel(); makeUpShowsAll = false; makeUpAway = false }
        }
        // A prayer marked (or unmarked) under the total: back to the name and line, so the total is never stale.
        .onChange(of: missedToday) { _, _ in if makeUpShowsAll { flipMakeUp(to: false) } }
        .fullScreenCover(isPresented: $showQiblaMap) {
            // A cover on the stage: a widget open closes it and waits until it's gone (it pushed its page under the
            // closing map — tr-final), and moments wait for it.
            LocationMapContentView().stageCover("map")
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
        .onChange(of: daySummaryShowing) { _, up in raiseDisc(up) }
        .onAppear { if daySummaryShowing { discShown = true; discLift = 1 } }
        // The welcome on this circle: its arc waits at nothing under the mark (it's hidden then, so this is unseen),
        // and sweeps out from the start as the words come in on the landing.
        // `initial`: the opening can already cover the circle when it first appears (a cold launch), and then the arc
        // never went to nothing — it was simply there when the ring landed.
        .onChange(of: openingHidesWords, initial: true) { _, hidden in
            // The opening gone before it landed (a widget sent the app elsewhere): the arc back as it is, no sweep.
            if !hidden, CircleStage.shared.opening == nil {
                arcSweepTask?.cancel()
                quietly { arcSweep = nil }
                return
            }
            guard hidden, !reduceMotion else { return }
            // ▶︎ Opening in place: once the circle's words and arc have faded out (it vanished in a frame otherwise).
            let inPlace = CircleStage.shared.opening?.inPlace == true
            arcSweepTask?.cancel()
            arcSweepTask = Task { @MainActor in
                if inPlace { guard await CircleGate.pause(CircleMomentTiming.outDone) else { return } }
                quietly { arcSweep = 0 }
            }
        }
        .onChange(of: CircleStage.shared.opening?.landed == true) { _, landed in
            guard landed, CircleStage.shared.opening?.hidesWords == true else { return }
            sweepArcIn()
        }
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
        // A mark's flourish gone: the dashes it held back draw now.
        .onChange(of: flourish == nil) { _, clear in if clear, trackSolid == 0, dashesDrawn == 0 { drawDashes() } }
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
            guard !sweeping else { return }
            // A plain tick moves the arc a fraction of a pixel: no animation. Its spring (`animationStyle`) ran most of
            // every second, so the idle page drew at the display's rate (idle-cpu). A tick into a new colour keeps it.
            if tickChangesColor(to: newTime) {
                currentTime = newTime
            } else {
                var still = Transaction(); still.disablesAnimations = true
                withTransaction(still) { currentTime = newTime }
            }
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
        case .excused: return false   // a calm dashed ring: nothing is due
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

    /// The day's disc up (the score side) or back down; Reduce Motion: at once.
    private func raiseDisc(_ up: Bool) {
        if up {
            discShown = true
            if reduceMotion { discLift = 1; return }
            withAnimation(CircleMotion.dayDiscRise) { discLift = 1 }
        } else {
            if reduceMotion { discLift = 0.5; discShown = false; return }
            withAnimation(CircleMotion.dayDiscSink, completionCriteria: .logicallyComplete) { discLift = 0.5 } completion: {
                if !daySummaryShowing { discShown = false }
            }
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

    /// The opening's arc sweep (`arcSweep`): at nothing while the mark covers the circle, then out to where the prayer
    /// stands, in the prayer's final colour (a colour changing green → yellow → red in under a second read as a flicker).
    /// A prayer to come stays dashed; Reduce Motion: it's just there, as before.
    private func sweepArcIn() {
        arcSweepTask?.cancel()
        guard arcSweep != nil, shownStatus == .current, !shownIsPreview else { quietly { arcSweep = nil }; return }
        arcSweepTask = Task { @MainActor in
            defer { sweeping = false; quietly { arcSweep = nil } }
            // The words in first, round an empty ring; then the arc (sweeping under their fade-in, it was most of the
            // way out before it could be seen).
            guard await CircleGate.pause(CircleMomentTiming.in) else { return }
            // The clock now (the ring is still empty, so unseen), then no ticks until it's out.
            sweeping = true
            quietly { currentTime = Date() }
            guard await CircleGate.nextFrame() else { return }
            await CircleMotion.animate(CircleMotion.Opening.arcSweep) { arcSweep = 1 }
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
            flourishSkipped = false
            flourishLands = false
            displayedFace = derivedFace
            CircleStage.shared.holdRow(nil)
        }) {
            flourishID += 1
            flourishOut = false
            flourishSkipped = false
            flourishLands = false
            flourishDay = viewModel.todaysPrayers.map(DayPrayer.init)
            withAnimation(.easeOut(duration: CircleMotion.flourishCoverDuration)) { flourish = event }
            // Its length, or until a tap on the circle: then it goes first (out, then in — never two words at once).
            let ends = Uptime.now + CompletionFlourish.duration
            while Uptime.now < ends, !flourishSkipped {
                guard await CircleGate.pause(1.0 / 30) else { return }
            }
            if flourishSkipped { guard await CircleGate.pause(CircleMomentTiming.outDone) else { return } }
            // The day's page next, its ring whole at once: the flourish's ring is the same ring, so it hands over in place.
            if case .summary = derivedFace, summaryShowsScore ?? summaryWantsScore, !flourishSkipped {
                flourishLands = true
                DayRingHandoff.mark()
            }
            // The next prayer / the summary goes in while the words are still hidden, with no animation (the name and
            // icon morphed Maghrib → Isha as they faded in), then fades in.
            quietly { displayedFace = derivedFace }
            flourishOut = true                    // fades on its own (implicit), the words fade in
            CircleStage.shared.holdRow(nil)       // the list folds the row now (it animates itself)
            // The post-salah pill under the top bar (it animates its own arrival). The original event's name even after
            // a Jumu'ah correction ("Dhuhr"), as the row's (Sami's review of 98eeedf).
            // The first real mark's pill waits for the celebration's Continue (Tour.swift `holdPill`).
            // G · a mark the list's row took (PrayerRowActions) has its buttons there instead of the pill. A prayer marked
            // after its window (Qaza: progress at 1) gets no pill at all (owner, 2026-10-14).
            if event.progress < 1, !TourRuntime.shared.holdPill(event.name),
               PrayerRowActions.shared.name != (event.prayerName ?? event.name) {
                live?.postSalahNudge = event.name
            }
            guard await CircleGate.pause(0.5) else { return }
            quietly { flourish = nil; flourishOut = false; flourishSkipped = false; flourishLands = false }
        }
    }

    /// ▶︎ Prayer begins (Settings → My Dev Stuff → Preview too): the Salah page, the prayer as "next" for a moment, then
    /// it begins, then back. A script over the preview's data (`preview`, `heldPrayer`): the circle plays each change
    /// with the same moments as the real data — a swap into "next", the begins moment, a swap back — so what's played
    /// is what he sees at a real start. With every prayer done, today's Fajr row is held on the circle for it. Visual
    /// only: no rows, times or notifications are touched.
    /// Today's prayers owed: ended, not marked, not excused — more than one and the missed face says "and more to make up".
    private var missedToday: Int {
        let now = Date(), excused = Excused.ranges
        return viewModel.todaysPrayers.filter {
            !$0.isCompleted && $0.endTime < now && !Excused.covers(start: $0.startTime, end: $0.endTime, in: excused)
        }.count
    }
    /// The circle is on a missed prayer (after Isha ends, until Fajr turns the day).
    private var missedFaceShown: Bool {
        guard case .prayer(_, let status, let preview) = displayedFace ?? derivedFace else { return false }
        return status == .missed && !preview
    }
    /// The total in the name's place (the missed face, tapped; not the palette's preview).
    private func showsMakeUpTotal(_ status: PrayerModel.prayerStatus) -> Bool { makeUpShowsAll && status == .missed && !shownIsPreview }
    /// The missed face's tap: the total owed (Journey's To make up count, read off the main thread) in the name's place,
    /// "to make up" under it, and "See all ›"; again, back. Name and line go out, swap, come back in; a light buzz.
    private func toggleMakeUp() {
        triggerSomeVibration(type: .light)
        flipMakeUp(to: !makeUpShowsAll)
    }
    private func flipMakeUp(to showAll: Bool) {
        let container = circleContext.container
        makeUpFlip?.cancel()
        makeUpFlip = Task { @MainActor in
            if showAll {
                let total = await JourneyMakeUpPage.openCount(container: container)
                guard !Task.isCancelled, missedFaceShown else { return }
                makeUpTotal = total
            }
            makeUpAway = true
            try? await Task.sleep(for: .seconds(CircleMomentTiming.outDone))
            guard !Task.isCancelled else { return }
            // Swapped while out, unanimated (animated, the name and the total crossfaded through each other); See all
            // fades on its own transition.
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { makeUpShowsAll = showAll }
            makeUpAway = false
        }
    }

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
            // A prayer still to come: its dashes appear one by one from the top (owner). Under a mark's flourish they
            // wait for it to clear (the track goes dashed at the tap, solid while the flourish holds the marked prayer,
            // then dashed again — they'd have drawn twice). Reduce Motion: there at once.
            if !solid && !reduceMotion {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { dashesDrawn = 0 }
                if flourish == nil { drawDashes() }
            }
        } else {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { trackSolid = target; dashesDrawn = 1 }
        }
    }

    /// The dashes drawn in, one by one (CircleMotion.dashesDraw), from the empty ring.
    private func drawDashes() {
        Task { @MainActor in
            await Task.yield()   // the empty ring drawn first, so the draw animates from it
            guard trackSolid == 0, dashesDrawn == 0 else { return }
            withAnimation(CircleMotion.dashesDraw) { dashesDrawn = 1 }
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
        TourRuntime.shared.event(.circleTapped)   // the tour's first step ends on this tap
        // A mark's flourish holding the day ring: a tap moves on to the next prayer.
        if flourish != nil, !flourishOut, !flourishSkipped { flourishSkipped = true; return }
        // The day's page: the middle swaps the score and the rank, or lets a picked prayer go (the band picks a fifth).
        if daySummaryShowing {
            withAnimation(CircleMotion.dayPick) {
                if DayPageState.shared.centreTapped() { triggerSomeVibration(type: .light) }
            }
            return
        }
        if excusedShown != nil { NotificationCenter.default.post(name: Excused.openSheet, object: nil); return }
        guard morningShown == nil, lostShown == nil else { return }
        // Only when the circle has text to flip. "Missed" and the day's score have none (a buzz
        // there felt like a broken button); the prayer's "ends / at" text is an
        // ExternalToggleText that buzzes by itself (this used to buzz a second time).
        let flipsOwnText: Bool   // true = ExternalToggleText, haptic included
        if let prayer = viewModel.relevantPrayer, !(prayer.status() == .upcoming && prayer.name == "Fajr") {
            // Owed (after Isha, until Fajr): the line flips to the total owed and back (toggleMakeUp).
            if prayer.status() == .missed { toggleMakeUp(); return }
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



/// A mark's flourish folded into the day ring and the day's page comes next: it shows its ring whole at once instead of
/// drawing it again (`playMarking` → `summaryCircle.drawTo`). Taken once, within a moment of being set.
@MainActor enum DayRingHandoff {
    private static var at: TimeInterval?
    static func mark() { at = Uptime.now }
    static func take() -> Bool {
        defer { at = nil }
        guard let at else { return false }
        return Uptime.now - at < 1.5
    }
}

struct summaryCircle: View, Equatable {
    static func == (a: summaryCircle, b: summaryCircle) -> Bool {
        a.ogText == b.ogText && a.showsScore == b.showsScore && a.away == b.away
    }

    @AppStorage(NextLabel.key, store: UserDefaults(suiteName: SharedStore.appGroup)) private var showNextLabel = true
    // FIXME: think this through more and make sure it makes sense.
    @EnvironmentObject var viewModel: PrayerViewModel
    @Environment(SharedStateClass.self) var sharedState

    @Binding var ogText: Bool  // to control the toggle text in the middle
    /// The side shown and whether its words are out: MainCircleView's (its `flipSummary` moment). The score and next Fajr
    /// never crossfade through each other — one goes out, then the other comes in (owner, 2026-10-02).
    let showsScore: Bool
    let away: Bool
    @State private var nextFajr: (start: Date, end: Date)?
    // The day's page (DaySummary.swift): earlier days for the line, the tapped fifth, the glow.
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: SharedStore.appGroup)) private var fajrAlarmOn = false
    @State private var history: [[DayPrayer]] = []
    /// Today's place among your days (DayRank), once the day is finished; nil = the score alone.
    @State private var dayRank: DayRank?
    @State private var teachTask: Task<Void, Never>?
    /// The picked prayer lives in DayPageState (the rows pick too, the flip clears it — the day page merge).
    private var picked: Int? { DayPageState.shared.picked }
    /// The picked prayer's note, on the frosted card; its place, on the map sheet (DayPickLines' doors).
    @State private var noteShown = false
    @State private var placeSheet: PrayerModel?
    /// Prayers still owed, read when a missed prayer is picked (DayMakeUpPill).
    @State private var makeUpCount: Int?
    @State private var line: DayInsight.Line?
    @State private var glow = false
    /// The day's line's height (one or two lines, the Fajr alarm link): to centre it in the room under the ring.
    @State private var lineHeight: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The fifths drawn (DayRing's `drawn`): toward 1 on the score side, 0 otherwise, animated (CircleMotion.dayRing…).
    @State private var drawn: CGFloat = 0
    /// Leaving, the drawn ring just fades (as the dashed ring does); drawn back to 0 unseen once gone.
    @State private var ringFade: Double = 1
    @State private var drawToken = 0
    /// The first showing today: the score counts up from 0 once the ring is whole (nil = show the score as it is).
    @State private var countedScore: Double?
    /// DayHistory's first day only when it IS yesterday: DayHistory leaves out a day that doesn't count (excused, not
    /// prayed in full), and its first is then the day before (the helper's check of mark audit #12). A day with no rows
    /// is kept as an empty list.
    private var historyStartsYesterday: Bool {
        guard let day = history.first else { return false }
        guard let p = day.first else { return true }
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: PrayerDay.date()) else { return false }
        return PrayerDay.key(forRow: p.name, startingAt: p.start) == PrayerNotificationID.dayKey(y)
    }
    private var yesterday: [DayPrayer] { historyStartsYesterday ? (history.first ?? []) : [] }
    /// Yesterday's day score from its own rows, as every other count reads them — never DailyPrayerScore, whose bare-Date
    /// keys shift after a time-zone change (mark audit #12). The average of the five, unmarked = 0 (PrayerScoring.dayScore);
    /// an excused yesterday not prayed in full isn't in DayHistory: 0, as before.
    private var yesterdayScore: Double { yesterday.reduce(0) { $0 + ($1.score ?? 0) } / 5 }

    /// Before Fajr with nothing marked in a new prayer day, show the day that just finished
    /// instead of a 0 (owner, 2026-09-25). Since the day rolls over at Fajr this only happens
    /// without a saved location (the day then turns at 3 AM).
    private var showingYesterday: Bool {
        guard let fajr = viewModel.todaysPrayers.first(where: { $0.name == "Fajr" }) else { return false }
        return Date() < fajr.startTime && !fajr.isCompleted
    }
    private var shownScore: Double { showingYesterday ? yesterdayScore : viewModel.todaysScore }

    /// The prayers of the day shown (today, or yesterday before a Fajr with nothing marked).
    private var shownDay: [DayPrayer] {
        showingYesterday ? yesterday : viewModel.todaysPrayers.map(DayPrayer.init)
    }

    /// Today's row of the picked prayer (none while yesterday's day is shown: those rows are gone).
    private var pickedRow: PrayerModel? {
        guard let i = picked, DayRing.order.indices.contains(i), !showingYesterday else { return nil }
        return viewModel.todaysPrayers.first { $0.name == DayRing.order[i] }
    }
    /// "5:31 PM · Middle · 83", under the note on its card.
    private var pickedLine: String {
        guard let row = pickedRow else { return "" }
        return [row.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) }, row.scoreSummary].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var dayLine: some View {
        if picked != nil {
            // The picked prayer's note and place, each a door (the day page merge, owner 2026-10-15); neither: nothing.
            if let row = pickedRow {
                DayPickLines(note: DayFacts.note(row), place: DayFacts.place(row),
                             onNote: { noteShown = true }, onPlace: { placeSheet = row })
                    .id(row.name)   // another pick is another line: out, then in (never two notes over each other — Frank)
                    .transition(CircleMotion.dayPickSwap)
            }
        } else if shownDay.isEmpty {
            // No rows for the day shown (the app not opened that day): say so, not nothing (Ben's audit).
            Text(showingYesterday ? "No prayers marked yesterday." : "No prayers marked today.")
                .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
        } else if let line, !line.text.isEmpty {
            VStack(spacing: 6) {
                Text(line.text)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                // No "Set a Fajr alarm ›" nudge here any more (owner, 2026-10-15: don't push people to make one; the alarm
                // shows on the next-Fajr side only once it's set up).
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    /// The day's line, kept for the day (DayInsight); none during the tour (its practice day isn't the user's).
    /// Today's rank, for the middle's tap (finished, counted days only; none for yesterday's page). The first showing of
    /// each finished day teaches the tap: the rank flips in on its own and back (owner, 2026-10-17: "every time we finish
    /// the day — not just one time ever"), unless the middle was touched first.
    private func loadRank() {
        guard showsScore, !showingYesterday, shownDay.count == 5, shownDay.allSatisfy(\.done),
              !shownDay.contains(where: \.excused) else {
            dayRank = nil
            DayPageState.shared.rankReady = false
            return
        }
        let container = context.container
        Task { @MainActor in
            let rank = await DayRank.today(container: container)
            dayRank = rank
            DayPageState.shared.rankReady = rank != nil
            guard rank != nil else { return }
            teach()
        }
    }
    /// The rank's flip on its own, once per finished day: only one waiting at a time (refreshDay runs on every change),
    /// and the day counts as taught only once it has played.
    private func teach() {
        let key = PrayerNotificationID.dayKey(PrayerDay.date())
        guard !Self.stillForCheck, UserDefaults.standard.string(forKey: Self.rankTaughtKey) != key else { return }
        teachTask?.cancel()
        teachTask = Task { @MainActor in
            let state = DayPageState.shared
            try? await Task.sleep(for: .seconds(CircleMotion.dayRankTeachDelay))
            guard !Task.isCancelled, state.up, !state.centreTouched, state.picked == nil, !state.showsRank,
                  dayRank != nil else { return }
            UserDefaults.standard.set(key, forKey: Self.rankTaughtKey)
            withAnimation(CircleMotion.dayPick) { state.showsRank = true }
            try? await Task.sleep(for: .seconds(CircleMotion.dayRankTeachHold))
            guard !Task.isCancelled, !state.centreTouched, state.showsRank else { return }
            withAnimation(CircleMotion.dayPick) { state.showsRank = false }
        }
    }
    /// The prayer day whose rank flipped in on its own (once per finished day).
    static let rankTaughtKey = "daySummary.rankTaught"

    private func refreshDay() {
        guard !TourRuntime.shared.active else { line = nil; return }
        history = DayHistory.load(context)
        let today = PrayerDay.date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let input = DayInsight.Inputs(
            dayKey: PrayerNotificationID.dayKey(showingYesterday ? Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today : today),
            today: shownDay,
            history: showingYesterday && historyStartsYesterday ? Array(history.dropFirst()) : history,
            fajrAlarmOn: fajrAlarmOn,
            tomorrowStart: { viewModel.getPrayerTime(for: $0, on: tomorrow)?.start },
            tomorrowIsFriday: Calendar.current.component(.weekday, from: tomorrow) == 6)
        line = DayInsight.line(input)
        loadRank()
        // A full day glows once (per prayer day), the first time its page is shown.
        let key = input.dayKey
        if showsScore, !Self.stillForCheck, shownDay.count == 5, shownDay.allSatisfy(\.inTime),
           UserDefaults.standard.string(forKey: "daySummary.glowed") != key {
            UserDefaults.standard.set(key, forKey: "daySummary.glowed")
            withAnimation(.easeOut(duration: 0.8)) { glow = true }
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                withAnimation(.easeInOut(duration: 1.6)) { glow = false }
            }
        }
    }

    /// The score side shown with its words in: the fifths drawn; otherwise not.
    private var drawTarget: CGFloat { showsScore && !away ? 1 : 0 }

    /// Draw the fifths to `target`: in on every flip (the first time today slower, then the score counts up); out, quicker.
    private func drawTo(_ target: CGFloat) {
        drawToken += 1
        let token = drawToken
        guard drawn != target || ringFade < 1 else { return }
        if reduceMotion || Self.stillForCheck { drawn = target; ringFade = 1; countedScore = nil; return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        guard target == 1 else {
            // Out: a fade, as the dashed ring leaves (owner) — the draw only plays coming in. Reset unseen once gone.
            countedScore = nil
            withAnimation(.easeOut(duration: CircleMomentTiming.out)) { ringFade = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(CircleMomentTiming.outDone))
                guard token == drawToken else { return }
                withTransaction(quiet) { drawn = 0; ringFade = 1 }
            }
            return
        }
        // In (a flick back mid-fade too): from nothing, drawn clockwise.
        if ringFade < 1 { withTransaction(quiet) { drawn = 0; ringFade = 1 } }
        let today = PrayerNotificationID.dayKey(PrayerDay.date())
        let first = UserDefaults.standard.string(forKey: Self.firstDrawKey) != today && !TourRuntime.shared.active
        // Straight from the last mark's flourish, which drew this ring already: whole at once; a first showing still
        // counts its score up.
        if DayRingHandoff.take() {
            withTransaction(quiet) { drawn = 1 }
            guard first else { return }
            UserDefaults.standard.set(today, forKey: Self.firstDrawKey)
            withTransaction(quiet) { countedScore = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(CircleMotion.flourishUncoverDuration))
                guard countedScore != nil else { return }
                withAnimation(CircleMotion.dayScoreCount) { countedScore = shownScore }
                try? await Task.sleep(for: .seconds(0.8))
                countedScore = nil
            }
            return
        }
        guard first else {
            withAnimation(CircleMotion.dayRingDraw) { drawn = 1 }
            return
        }
        UserDefaults.standard.set(today, forKey: Self.firstDrawKey)
        // To 0 at once: set inside the face's own animated swap, it counted down from the old value first.
        withTransaction(quiet) { countedScore = 0 }
        withAnimation(CircleMotion.dayRingFirstDraw) { drawn = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CircleMotion.dayRingFirstDrawDuration))
            guard countedScore != nil else { return }
            withAnimation(CircleMotion.dayScoreCount) { countedScore = shownScore }
            try? await Task.sleep(for: .seconds(0.8))
            countedScore = nil
        }
    }
    /// The day the slow first draw played (once a day).
    static let firstDrawKey = "daySummary.firstDrawn"
    /// circle-check.sh's shots (`-demoCircleCheck still`, DEBUG): the ring and its score whole at once — no draw-in, no
    /// count-up, no glow — so a shot never catches them mid-way. Strips pass `YES` and keep the motion.
    #if DEBUG
    static let stillForCheck = UserDefaults.standard.string(forKey: "demoCircleCheck") == "still"
    #else
    static let stillForCheck = false
    #endif

    /// When the Fajr alarm rings for this Fajr — the rule from Settings (before / after Fajr or sunrise, by the offset);
    /// nil when it's off or excused (it won't ring).
    private func alarmTime(for fajr: (start: Date, end: Date)) -> Date? {
        // Only once it's set up: on, iOS's alarm permission given (AlarmKit), not excused — never a nudge (owner).
        // On 26.1+ the alarm is iOS's (AlarmKit): only with permission actually given; before, the Shortcut path.
        var permitted = true
        if #available(iOS 26.1, *) { permitted = FajrAlarms.allowed == true }
        guard fajrAlarmOn, permitted, !Excused.isActive,
              let g = UserDefaults(suiteName: SharedStore.appGroup) else { return nil }
        let isFajr = g.object(forKey: "alarmIsFajr") as? Bool ?? true
        let before = g.object(forKey: "alarmIsBefore") as? Bool ?? true
        let shift = TimeInterval(g.integer(forKey: "alarmOffsetMinutes") * 60) * (before ? -1 : 1)
        return (isFajr ? fajr.start : fajr.end).addingTimeInterval(shift)   // Fajr's window ends at sunrise
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
            // The day (decision day-score-end): the ring holds the day's five prayers round the score; a fifth tapped
            // tells that prayer; one line under the circle.
            DayCentre(day: shownDay, score: countedScore ?? shownScore, picked: picked, yesterday: showingYesterday,
                      makeUpCount: makeUpCount, onMakeUp: {
                          // To make up, in Journey (the pill in the ring; marking stays the list's dot — owner).
                          JourneyPresenter.shared.makeUp = true
                          JourneyPresenter.shared.open = true
                      }, rank: showingYesterday ? nil : dayRank,
                      showsRank: DayPageState.shared.showsRank && dayRank != nil && !showingYesterday)
                .animation(CircleMotion.dayPick, value: picked)
                .animation(CircleMotion.dayPick, value: DayPageState.shared.showsRank)
                .modifier(CircleWordsAway(away: away || !showsScore))
            DayRing(day: shownDay, picked: picked, drawn: drawn) { i in
                withAnimation(CircleMotion.dayPick) { DayPageState.shared.togglePick(i) }
                triggerSomeVibration(type: .light)
            }
            .opacity(ringFade)
            .background {
                // A full day: the ring glows once (its first showing that day), then settles.
                Circle().fill(Color.green.opacity(0.12)).frame(width: 290, height: 290).blur(radius: 32)
                    .opacity(glow ? 1 : 0).allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // Memories' link sits at the bottom, in "N done"'s spot above the bar (MemoriesFooterLink; decision
                // memories-link-place B — the list dragged up over it here).
                // Centred in the room between the ring and the list (DayPageState.ringListGap; 22 pt under the ring until
                // measured — owner: it sat crowded under the ring with the list far below).
                dayLine
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if abs(lineHeight - $0) > 0.5 { lineHeight = $0 } }
                    .frame(width: 310)
                    .offset(y: 206 + max(((DayPageState.shared.ringListGap ?? (32 + lineHeight)) - lineHeight) / 2, 12))   // from the ring view's top: 200 + its band
                    .animation(.easeOut(duration: CircleMotion.quick), value: DayPageState.shared.ringListGap)
                    .modifier(CircleWordsAway(away: away || !showsScore))
            }
            // The ring itself is drawn in and out (`drawn`), not faded.
            .allowsHitTesting(showsScore && !away)
            .onAppear { drawTo(drawTarget) }
            .onChange(of: drawTarget) { _, target in drawTo(target) }

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
        // The bridge to tomorrow (owner, 2026-10-15): when the Fajr alarm rings, under the ring on the next-Fajr side —
        // out of the circle (inside it, it pushed Fajr's name off its place); a tap opens Settings at the Fajr alarm.
        .overlay(alignment: .bottom) {
            if let fajr = nextFajr, let alarm = alarmTime(for: fajr) {
                Button {
                    triggerSomeVibration(type: .light)
                    // Settings, then its alarm row once the push has landed (scrolling mid-push stalls it).
                    SettingsPresenter.shared.show(jump: SettingsJump.fajrAlarm)
                } label: {
                    Label("Alarm \(shortTimePM(alarm))", systemImage: "alarm")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: 56)
                .modifier(CircleWordsAway(away: away || showsScore))
                .allowsHitTesting(!showsScore && !away)
                .accessibilityLabel("Fajr alarm at \(shortTimePM(alarm)). Change it in Settings.")
            }
        }
        .transition(.opacity)
        .onAppear { getTheNextFajrTime(); refreshDay(); DayPageState.shared.pageAppeared() }
        .onDisappear { DayPageState.shared.pageGone(); teachTask?.cancel() }
        .onChange(of: showsScore) { _, shows in
            teachTask?.cancel()   // the rank's flip on its own waits for the score side's next showing
            DayPageState.shared.leaveDay()   // the side swapped: nothing picked, the front up
            if shows { refreshDay() }
        }
        // An outside mark of an earlier day (the reconcile clears DayHistory, then posts this): yesterday's ring, score and
        // dots before a Fajr, and the line, are read again (Fable's review, gap 2 — the score moved with a @Query before #12).
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in refreshDay() }
        // A mark (or an unmark) changes the day.
        .onChange(of: viewModel.todaysPrayers.map { "\($0.name)\($0.isCompleted)\($0.timeAtComplete?.timeIntervalSince1970 ?? 0)" }) { _, _ in
            refreshDay()
        }
        // A pick stays until a second tap, the flip or the day changing clears it (owner: no timer). A missed prayer
        // picked reads how many are owed, for its pill.
        .onChange(of: picked) { _, i in
            guard let i, DayRing.order.indices.contains(i),
                  let p = shownDay.first(where: { $0.name == DayRing.order[i] }), p.missed else { return }
            let container = context.container
            Task { makeUpCount = await JourneyMakeUpPage.openCount(container: container) }
        }
        // The note's card (Settings' ⓘ way, grey: no sage on the Salah page) and the place's map sheet.
        .infoModal(isPresented: $noteShown, title: pickedRow?.displayName ?? "",
                   symbol: prayerIcon(for: pickedRow?.name ?? "Fajr"), tint: .secondary) {
            DayNoteInfo(text: pickedRow.flatMap(DayFacts.note) ?? "", line: pickedLine)
        }
        .sheet(item: $placeSheet) { row in
            if let spot = DayFacts.spot(row) {
                PrayerPlaceMapSheet(caption: "\(row.displayName) · \(row.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")",
                                    place: DayFacts.place(row) ?? "", spot: spot, score: row.numberScore, atMasjid: row.atMasjid)
                    .stageCover("dayPlace")
            }
        }
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
                // VoiceOver had nothing to read or press here; UI tests find it by this too (testMapPrayersLayer).
                .accessibilityLabel("Qibla map")
                .accessibilityAddTraits(.isButton)

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


/// A prayer that's on: "ends 11:59 PM" ⇄ the time left. In the last hour of one not yet marked it says the time left by
/// default, live (owner, decision ring-time-left A: "when we open the app, if we haven't marked it done … it defaults
/// that time text to show how much time is left" — like the Lock Screen widget's last hour). A tap shows the other: for
/// 3 s outside the last hour (as before); in it, until the hour begins or the prayer changes. Every change of words is
/// out, then in (they blurred through each other) — the time left counting down changes in place.
struct PrayerTimeLine: View {
    let end: Date
    let now: Date
    /// The last-hour default applies (an unmarked prayer, not the dev preview).
    let lastHourLeft: Bool
    let prayerKey: String
    /// The circle's tap (MainCircleView's `timeFlipPulse`): each change flips.
    let trigger: Bool
    /// Moves the shown "ends" time (the tour's practice clock); the time left is real.
    var labelShift: TimeInterval = 0
    /// No flip back by itself: only a tap flips it back (the tour's first step — owner, Ben's section K); the usual
    /// flip-back starts once it's let go.
    var holds = false

    private enum Mode { case ends, left }
    @State private var flipped = false
    @State private var shown: Mode?
    /// The prayer `shown` belongs to: a new prayer takes its line quietly (the circle's face swap already fades it).
    @State private var shownFor: String?
    /// Where a swap in progress is going (a second tap mid-swap compares with this, not with what's still shown).
    @State private var pending: Mode?
    @State private var away = false
    @State private var swap: Task<Void, Never>?
    @State private var revert: Task<Void, Never>?

    private var lastHour: Bool { lastHourLeft && end.timeIntervalSince(now) <= Self.lastHourSeconds }
    /// The last hour's default is the time left; a flip shows the other.
    private var wanted: Mode { lastHour != flipped ? .left : .ends }
    private var lastHourLeftShown: Bool { lastHour && (shown ?? wanted) == .left }

    var body: some View {
        Text((shown ?? wanted) == .left ? timeLeftString(from: end.timeIntervalSince(now)) : "ends \(shortTimePM(end.addingTimeInterval(labelShift)))")
            .font(.subheadline)
            .fontDesign(.rounded)
            // The last hour's time left in the prayer name's colour and weight (light), not thin grey (owner: "a little
            // more prominent … maybe its the weight" — thin read faint even in black; the watch's light looked right).
            .fontWeight(lastHourLeftShown ? .light : .thin)
            .foregroundStyle(lastHourLeftShown ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
            .modifier(CircleWordsAway(away: away))
            // The tour circles exactly these words when they flip (owner: not a box through the prayer's name). Only
            // while the tour runs: the pager moves this every frame.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if TourRuntime.shared.active { TourTargets.shared.set("circleTime", frame) }
            }
            .onAppear { if shown == nil { shown = wanted; shownFor = prayerKey } }
            .onChange(of: trigger) { _, _ in
                triggerSomeVibration(type: .light)
                flipped.toggle()
                revert?.cancel()
                scheduleRevert()
            }
            .onChange(of: holds) { _, _ in revert?.cancel(); scheduleRevert() }
            .onChange(of: lastHour) { _, _ in revert?.cancel(); flipped = false }   // the hour begins: its default
            .onChange(of: prayerKey) { _, key in
                // A new prayer: its own default, at once (the face swap fades the circle's words already).
                revert?.cancel()
                swap?.cancel()
                pending = nil
                flipped = false
                shown = lastHour ? .left : .ends
                shownFor = key
                away = false
            }
            .onChange(of: wanted) { _, mode in change(to: mode) }
    }

    /// Flipped (and not held): back by itself after `flipSeconds`.
    private func scheduleRevert() {
        guard flipped, !lastHour, !holds else { return }
        revert = Task { @MainActor in
            guard await CircleGate.pause(Self.flipSeconds) else { return }
            flipped = false
        }
    }

    private func change(to mode: Mode) {
        guard !((pending ?? shown) == mode && shownFor == prayerKey) else { return }
        swap?.cancel()
        guard shownFor == prayerKey else {
            shown = mode
            shownFor = prayerKey
            away = false
            return
        }
        pending = mode
        swap = Task { @MainActor in
            away = true
            guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { shown = mode }
            pending = nil
            guard await CircleGate.nextFrame() else { return }
            away = false
        }
    }

    private static let lastHourSeconds: TimeInterval = 60 * 60
    private static let flipSeconds: Double = 3
}


/// The missed face's line (owner, 2026-10-19, decision circle-make-up-wording): "to make up" or "and more to make up"; tapped,
/// "to make up" under the total in the name's place — the same type and place as "ends 11:59 PM" / "at 5:52", so nothing moves. A new line
/// swaps the circle's way: out, then in.
struct MakeUpLine: View {
    let text: String
    /// The face's own flip has the words out already: swap at once, no second fade.
    var quiet = false
    @State private var shown: String?
    @State private var away = false
    @State private var swap: Task<Void, Never>?

    var body: some View {
        Text(shown ?? text)
            .font(.subheadline)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .foregroundStyle(.secondary)
            .modifier(CircleWordsAway(away: away))
            .onChange(of: text) { old, new in
                swap?.cancel()
                if quiet { shown = new; away = false; return }
                if shown == nil { shown = old }
                away = true
                swap = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(CircleMomentTiming.outDone))
                    guard !Task.isCancelled else { return }
                    shown = new
                    away = false
                }
            }
    }
}

/// "See all ›" at the bottom inside the ring, the day page pill's look (DayMakeUpPill): opens To make up.
struct MakeUpSeeAll: View {
    let action: () -> Void
    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 4) {
                Text("See all")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
            }
            .font(.system(size: 13, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all prayers to make up")
    }
}
