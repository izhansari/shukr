//
//  WelcomeAnimation.swift
//  shukr
//
//  A short welcome when the app starts fresh (owner, 2026-09-25/26): "shukr" writes itself inside
//  a thin sage ring that sits exactly on the Salah page's circle (`WelcomeTarget`), two soft taps
//  like a heartbeat, a hold — then the ring *becomes* the circle: it starts snug round the word
//  (150 pt), and grows out to the circle's 200 pt while thickening from a hairline into the gray
//  track as the word fades; once it's there, the page fades in around it (owner, 2026-09-26:
//  "the circle grows into the other one"). It
//  always lands on the Salah page (list closed) so there's a circle to land on. About 2.6 s.
//  Plays only on a cold launch — when iOS had ended the app and it starts fresh (owner,
//  2026-09-27: after every 5 min away it came too often).
//

import SwiftUI

extension View {
    /// Shows `WelcomeOverlay` once per launch of the app process.
    func welcomeOnLaunch() -> some View { modifier(WelcomeGate()) }
}

/// Where the Salah page's main circle is on screen (global coordinates), written by
/// MainCircleView; and whether the welcome may land on it (PrayerTimesView says no while a tasbeeh
/// session covers the app).
@MainActor enum WelcomeTarget {
    /// The values, observable: what waits on them (the morning card, the lost page, the circle's gate) wakes when they
    /// change instead of polling (circle rule 5; tr-opening). Each is written only when it changes.
    static let state = WelcomeTargetState()

    static var circleFrame: CGRect? {
        get { state.circleFrame }
        set { if state.circleFrame != newValue { state.circleFrame = newValue } }
    }
    static var canLand: Bool {
        get { state.canLand }
        set { if state.canLand != newValue { state.canLand = newValue } }
    }
    /// The circle's track is the dashed "hasn't started" ring right now (MainCircleView): the
    /// welcome lands as that instead of the solid band.
    static var trackDashed: Bool {
        get { state.trackDashed }
        set { if state.trackDashed != newValue { state.trackDashed = newValue } }
    }
    /// The welcome is on screen (sheets — e.g. the reminders card — wait for it to finish). A new one hasn't landed yet
    /// (`landed` read stale true from the last one until its play() got going — audit B).
    static var playing: Bool {
        get { state.playing }
        set {
            if newValue, !state.playing, state.landed { state.landed = false }
            if state.playing != newValue { state.playing = newValue }
        }
    }
    /// The ring has landed and the page is fading in round it (the morning card's words start here).
    static var landed: Bool {
        get { state.landed }
        set { if state.landed != newValue { state.landed = newValue } }
    }
}

@MainActor @Observable final class WelcomeTargetState {
    fileprivate(set) var circleFrame: CGRect?
    fileprivate(set) var canLand = true
    fileprivate(set) var trackDashed = false
    fileprivate(set) var playing = false
    fileprivate(set) var landed = false
    /// The sleep curtain is up or the welcome is about to replay (`WelcomeGate.curtainUp`).
    fileprivate(set) var curtainUp = false
}

struct WelcomeGate: ViewModifier {
    @State private var showing = WelcomeGate.shouldShowOnLaunch
    /// Sleep mode ended a session and the app went to the background: black over everything until
    /// the next open, which replays the welcome from black and lands it on the morning card (owner,
    /// sleep-morning-open). Black is what the screen already showed, so iOS's picture of the app
    /// and the welcome's first frame match.
    @State private var curtain = false
    @State private var fromBlack = false
    /// ▶︎ Opening: the welcome replayed over the page as it is (not a launch).
    @State private var inPlace = false
    @Environment(\.scenePhase) private var scenePhase
    /// The curtain is up or the welcome is about to replay (the morning card waits under it). Observable (WelcomeTarget).
    @MainActor static var curtainUp: Bool {
        get { WelcomeTarget.state.curtainUp }
        set { if WelcomeTarget.state.curtainUp != newValue { WelcomeTarget.state.curtainUp = newValue } }
    }
    /// Sleep mode just saved a session in the background (`finishAsleep` / the lock after it): black at
    /// once, in this turn — iOS takes its picture of the app right after the background handlers, and
    /// one turn later it had already caught the tasbeeh cover being torn down.
    static let raiseCurtain = Notification.Name("WelcomeGate.raiseCurtain")

    private static var shouldShowOnLaunch: Bool {
        // The first-run setup is up: it ends in this welcome itself (its Bismillah hand-off).
        if FirstRunSetup.showingAtLaunch { return false }
        // Opened from a widget: straight to what it points at, no opening (owner: "i think better we skip it and no
        // animation go straight to the desired task. same with daily ayah. and with 99 names. any widget action").
        if FirstRunSetup.openedFromWidget { return false }
        #if DEBUG
        // Demo launch args drive screenshots / automation — don't cover them.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") })
            && !ProcessInfo.processInfo.arguments.contains("-demoWelcome") { return false }
        #endif
        return true
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if showing {
                    WelcomeOverlay(fromBlack: fromBlack, inPlace: inPlace) {
                        showing = false; fromBlack = false; inPlace = false; WelcomeTarget.playing = false
                    }
                        .transition(.identity)
                        .onAppear { WelcomeTarget.playing = true; WelcomeGate.curtainUp = false }
                        // Gone some other way than its end (its steps return when cancelled): not playing.
                        .onDisappear { WelcomeTarget.playing = false }
                } else if curtain {
                    Color.black.ignoresSafeArea().transition(.identity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: WelcomeGate.raiseCurtain)) { _ in raise() }
            // A widget sent the app to another page while the welcome plays (its intent wrote the flags after the
            // launch began): the welcome steps aside at once, so that page has its bars and its taps (owner:
            // "it hides bottom bar and top bar … and doesn't register clicks"; widget-open-chrome). Not ▶︎ Opening.
            .onReceive(NotificationCenter.default.publisher(for: DeepLinkSignal.arrived)) { _ in
                guard showing, !inPlace else { return }
                var quiet = Transaction(); quiet.disablesAnimations = true
                // The opening's hold on the page (the bars, the list) goes in the same quiet turn: no fade-in.
                withTransaction(quiet) {
                    showing = false; fromBlack = false; WelcomeTarget.playing = false
                    CircleStage.shared.opening = nil
                }
            }
            // The palette's Play → Opening / Good morning (SalahLook.swift): the welcome again, in place.
            .onReceive(NotificationCenter.default.publisher(for: SalahLookPlay.welcome)) { note in
                guard !showing, !curtain else { return }
                var quiet = Transaction(); quiet.disablesAnimations = true
                withTransaction(quiet) {
                    fromBlack = (note.object as? Bool) ?? false
                    inPlace = !fromBlack
                    showing = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, SleepMorning.pendingID != nil { raise() }
                if phase == .active, curtain {
                    var quiet = Transaction(); quiet.disablesAnimations = true
                    withTransaction(quiet) {
                        curtain = false
                        // Still this morning's: the welcome, from black, onto the card. Otherwise
                        // (the card expired) just the app.
                        if SleepMorning.pendingID != nil, SleepMorning.endedAt.map({ Date().timeIntervalSince($0) < SleepMorning.expiresAfter }) ?? true {
                            fromBlack = true
                            showing = true
                        } else {
                            WelcomeGate.curtainUp = false
                        }
                    }
                }
            }
    }

    private func raise() {
        guard !showing, !curtain else { return }
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { curtain = true }
        WelcomeGate.curtainUp = true
    }
}

/// A ring drawn as a filled annulus, so its thickness animates (a stroke's line width doesn't).
/// Also the lost-location page's ring, so its hand-off onto the Salah circle is the welcome's own.
struct WelcomeRing: Shape {
    var width: CGFloat
    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect).strokedPath(StrokeStyle(lineWidth: width))
    }
}

/// The welcome itself: letters fade up out of a blur one after another while a thin sage ring
/// draws round them, a light sweeps the word, it holds — then the ring thickens into the Salah
/// circle's track and dissolves onto it as the rest lifts away.
/// The welcome's ring and word, as they stand (circle step 4): one object the welcome's `play()` moves, drawn either by
/// the welcome's overlay (a landing elsewhere — the portal — or the first-run setup's hand-off) or, on a Salah landing,
/// by the Salah circle itself (`CircleStage.opening`), so the ring that grows into the track *is* the circle's.
@MainActor @Observable final class WelcomeMarkState {
    var lettersIn = false
    var ringDrawn = false
    var shine = false
    /// The small ring grows into the circle.
    var grow = false
    /// Opening onto a page with no Salah circle: the ring opens out past the edges like a doorway.
    var portal = false
    /// Landing on a dashed track (a prayer that hasn't started): grow to it and become the dashes.
    var dashedTarget = false
    /// Over a dashed track, once the grown ring is there: it breaks into the dashes in place (owner, 6F3BCE52).
    var dashesIn = false
    /// Handed off from a ring already on screen (the setup's): drawn from the first frame.
    var startDrawn = false
    /// The Salah circle draws the mark and the page waits round it; the overlay draws only the black (fromBlack).
    var inCircle = false
    /// Replayed over the page as it is (▶︎ Opening): the circle's track and words, and the page, go first.
    var inPlace = false
    /// The circle's own words wait under the mark (the opening); false = they stay (the lost page's symbol, as its
    /// ring lands back on the Salah track).
    var hidesWords = true
    /// The ring is the circle's track now: the circle's own track and words come back, the page fades in.
    var landed = false
}

/// The ring and the word (`WelcomeMarkState`), centred where it's drawn.
struct WelcomeMark: View {
    let state: WelcomeMarkState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.circleTheme) private var theme

    private let word = Array("shukr")
    /// The Salah page's circle: 200 pt with a 12 pt track centred on it (mainCircle.swift).
    static let ringSize: CGFloat = 200
    /// The ring's size round the word, before it grows.
    static let startSize: CGFloat = 150
    /// Past every corner of the screen.
    private var portalSize: CGFloat { max(UIScreen.main.bounds.height, UIScreen.main.bounds.width) * 1.4 }

    var body: some View {
        // Under the soft ring the band is there for a prayer still to come too, the dashes drawn in it (owner,
        // 2026-10-02), so the ring grows into the band either way.
        let track = theme.track
        let toDashes = state.dashedTarget && !track.dashesInBand
        let grow = state.grow, portal = state.portal
        let size = portal ? portalSize : (grow ? Self.ringSize : Self.startSize)
        ZStack {
            // The ring: drawn as a hairline, then grown into the circle's track (the soft band under the soft ring: its
            // width, surface and lift).
            WelcomeRing(width: grow ? (toDashes ? UpcomingTrack.style.lineWidth : track.width) : 1.2)
                .fill(grow ? (toDashes ? Color.secondary.opacity(UpcomingTrack.opacity) : track.fill)
                           : Color.sage.opacity(0.6))
                .shadow(color: track.lifted && grow ? theme.shade : .clear, radius: 4, x: 2, y: 2)
                .shadow(color: track.lifted && grow ? theme.light : .clear, radius: 6, x: -2, y: -2)
                .mask {
                    Circle()
                        .trim(from: 0, to: state.ringDrawn || reduceMotion || state.startDrawn ? 1 : 0)
                        .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .shadow(color: Color.sage.opacity((state.ringDrawn || state.startDrawn) && !grow ? 0.45 : 0), radius: 8)
                // Starts snug round the word, grows to the circle (frame, not scale, so the line keeps its own width).
                .frame(width: size, height: size)
                .opacity(reduceMotion || portal || (state.dashesIn && !track.dashesInBand) ? 0 : 1)
            // The dashed track, when that's what the circle is showing: in once the ring is there.
            Circle()
                .stroke(Color.secondary.opacity(UpcomingTrack.opacity), style: UpcomingTrack.style)
                .frame(width: Self.ringSize, height: Self.ringSize)
                .opacity(state.dashesIn && !portal ? 1 : 0)
            wordmark
                .scaleEffect(grow ? 0.9 : (portal ? 1.15 : 1))
                .blur(radius: grow || portal ? 4 : 0)
                .opacity(grow || portal ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            ForEach(self.word.indices, id: \.self) { i in
                Text(String(self.word[i]))
                    .opacity(state.lettersIn ? 1 : 0)
                    .blur(radius: state.lettersIn || reduceMotion ? 0 : 6)
                    .offset(y: state.lettersIn || reduceMotion ? 0 : 8)
                    .animation(CircleMotion.Opening.letter.delay(CircleMotion.Opening.letterStepDuration * Double(i)), value: state.lettersIn)
            }
        }
        .font(.system(size: 44, weight: .thin, design: .rounded))
        .foregroundStyle(.primary)
        .overlay {
            // A soft light passing over the letters once they're in.
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Color.sage.opacity(0.9), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: state.shine ? geo.size.width * 1.1 : -geo.size.width * 0.6)
            }
            .mask {
                HStack(spacing: 0) {
                    ForEach(self.word.indices, id: \.self) { i in Text(String(self.word[i])) }
                }
                .font(.system(size: 44, weight: .thin, design: .rounded))
            }
            .opacity(reduceMotion ? 0 : 1)
        }
    }
}

struct WelcomeOverlay: View {
    /// Handed off from a ring already on screen in the same place (the first-run setup's ring,
    /// OnboardingMockups): the ring is there from the first frame, only the letters write in.
    var startDrawn = false
    /// Opening from the sleep curtain: starts black and fades to the page colour as the word writes in.
    var fromBlack = false
    /// Replayed over the page as it is (▶︎ Opening), not a launch: it fades in, and on the Salah circle the circle's own
    /// track and words go before the word writes in — it cut to the welcome in one frame (Sami, step 6).
    var inPlace = false
    let onFinish: () -> Void
    @State private var blackOn = true
    @State private var shownIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.circleTheme) private var theme
    /// The ring and the word; the Salah circle draws them on a Salah landing (`mark.inCircle`).
    @State private var mark = WelcomeMarkState()
    @State private var morph = false     // then the page fades in around it
    @State private var target: CGPoint? = WelcomeOverlay.handoffTarget

    var body: some View {
        // No GeometryReader here: one in this overlay left the whole app laid out off screen
        // (blank page) after the welcome — so the overlay fills the screen and the ring is
        // offset from the screen's centre to the circle's (global) centre.
        let screen = UIScreen.main.bounds
        let shift = target.map { CGSize(width: $0.x - screen.midX, height: $0.y - screen.midY) } ?? .zero
        ZStack {
            // The page, until the Salah circle takes the opening over (then the real page is there, waiting round it).
            if !mark.inCircle {
                theme.backdrop
                WelcomeMark(state: mark)
                    .offset(shift)
            } else {
                Color.clear.contentShape(Rectangle())   // nothing under it takes a tap meanwhile
            }
            Color.black.opacity(fromBlack && blackOn ? 1 : 0).allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .opacity(morph || (inPlace && !shownIn) ? 0 : 1)
        .allowsHitTesting(!morph)
        .onAppear { if inPlace { withAnimation(CircleMotion.Opening.inPlaceIn) { shownIn = true } } }
        .task { await play() }
        .onDisappear { if CircleStage.shared.opening === mark { CircleStage.shared.opening = nil } }
    }

    /// Where a hand-off ring already sits: the Salah circle's centre (so the first frame isn't at
    /// the screen's centre). Only read as the initial `target`; `play()` sets it again.
    private static var handoffTarget: CGPoint? {
        // Only a circle that's on screen: a stale frame from another page (the Salah page off to the
        // right of the Zikr page) started the welcome half off the screen (owner, sleep morning).
        guard let f = WelcomeTarget.circleFrame, f.width > 100,
              UIScreen.main.bounds.insetBy(dx: -1, dy: -1).contains(f) else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// The real circle's centre, if the welcome may land there and it's on screen.
    private func circleCentre() -> CGPoint? {
        guard WelcomeTarget.canLand, let f = WelcomeTarget.circleFrame,
              f.width > 100, UIScreen.main.bounds.insetBy(dx: -1, dy: -1).contains(f) else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
    }

    private func play() async {
        typealias T = CircleMotion.Opening
        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.prepare()
        // Sit on the circle from the start: on a cold launch it lays out a beat after the welcome
        // appears, so wait for it (the page is blank anyway; it wakes as the frame is reported); if it's still not
        // there, start centred and glide the few points onto it later.
        _ = await CircleStage.shared.until(deadline: T.findCircleDuration) { circleCentre() != nil }
        target = circleCentre()
        mark.startDrawn = startDrawn
        // On the Salah circle (circle step 4): the circle draws the ring and the word, and the page waits round it —
        // one ring, nothing lined up by measured frames — and plays it as one of its moments (audit B). The setup's
        // hand-off (a ring already on screen) and landings elsewhere keep this overlay.
        if target != nil, !startDrawn {
            // Claimed in this turn, the mark and the hidden page together. A launch: at once (nothing's there yet). In
            // place: animations allowed, so the circle's track and words and the page fade out (each on its own
            // implicit animation).
            let mark = mark
            var quiet = Transaction()
            quiet.disablesAnimations = !inPlace
            withTransaction(quiet) {
                mark.inPlace = inPlace
                mark.inCircle = true
                CircleStage.shared.opening = mark
            }
            CircleStage.shared.play(CircleMomentRequest(kind: .opening, phases: {
                // In place: the circle's track and words fade out first (MainCircleView), then the word writes in.
                if inPlace { guard await CircleGate.pause(CircleMomentTiming.outDone) else { return } }
                await steps(soft)
            }, settle: {
                // Done, or snapped by a newer moment: landed, the page in round it, the overlay gone.
                if !mark.landed {
                    mark.lettersIn = true
                    mark.ringDrawn = true
                    mark.grow = true
                    land()
                }
                onFinish()
            }))
            return
        }
        await steps(soft)
    }

    /// The opening's steps, on the circle (its moment) or in this overlay.
    private func steps(_ soft: UIImpactFeedbackGenerator) async {
        typealias T = CircleMotion.Opening
        WelcomeTarget.landed = false
        if fromBlack { withAnimation(T.blackAway) { blackOn = false } }
        mark.lettersIn = true
        withAnimation(T.ringDraw) { mark.ringDrawn = true }

        guard await CircleGate.pause(T.firstBeatDuration) else { return }
        soft.impactOccurred(intensity: 0.55)          // lub…
        withAnimation(T.shine) { mark.shine = true }
        guard await CircleGate.pause(T.secondBeatDuration) else { return }
        soft.impactOccurred(intensity: 1.0)           // …dub, as the ring closes

        guard await CircleGate.pause(T.holdDuration) else { return }
        if !mark.inCircle, let c = circleCentre(), c != target {
            withAnimation(T.glide) { target = c }
        }
        guard await CircleGate.pause(T.beforeGrowDuration) else { return }
        if !WelcomeTarget.canLand {
            if mark.inCircle {
                // Something came over the circle meanwhile (a widget's page): the circle is as it is under it (the
                // moment's settle finishes it).
                land()
                return
            }
            // Nothing to land on: the ring opens out like a doorway (thin, fading) and the word
            // and page go with it, onto whatever page was opened.
            withAnimation(T.portal) { mark.portal = true; mark.grow = false }
            withAnimation(T.portalPage) { morph = true }
            guard await CircleGate.pause(T.portalDuration) else { return }
            onFinish()
            return
        }
        // Become the circle: the word lets go and the ring grows out to the Salah circle,
        // thickening into its gray track — or, over a prayer that hasn't started, turning into its
        // dashed ring…
        mark.dashedTarget = WelcomeTarget.trackDashed
        withAnimation(T.grow) { mark.grow = true }
        if mark.dashedTarget {
            // The thin ring reaches the circle's edge first, then becomes its dashes.
            guard await CircleGate.pause(reduceMotion ? 0 : T.toDashesDuration) else { return }
            withAnimation(T.dashes) { mark.dashesIn = true }
            guard await CircleGate.pause(T.dashesDuration) else { return }
        } else {
            guard await CircleGate.pause(T.toBandDuration) else { return }
        }
        // …and once it's there, the page fades in around it. The welcome's ring and the real track
        // are the same shape in the same place, so only the page appears.
        if mark.inCircle {
            land()
            _ = await CircleGate.pause(T.pageInDuration)   // the page fading in; the moment's settle finishes it
            return
        }
        WelcomeTarget.landed = true
        withAnimation(T.overlayAway) { morph = true }
        guard await CircleGate.pause(T.pageInDuration) else { return }
        onFinish()
    }

    /// The opening on the Salah circle has landed: the circle's own track and words come back, the page fades in round
    /// it (each on its own animation, in MainCircleView and the chrome).
    private func land() {
        WelcomeTarget.landed = true
        mark.landed = true
    }
}

#Preview {
    WelcomeOverlay {}
}

extension CircleMotion {
    /// The opening (WelcomeOverlay) and the lost page's comeback, which lands the same way: every step's timing, written
    /// once (they were ms literals in both places — audit B).
    enum Opening {
        /// A cold launch: how long the welcome waits for the circle to report where it is.
        static let findCircleDuration: Double = 0.4
        /// ▶︎ Opening in place: the overlay comes in over the page.
        static let inPlaceIn = Animation.easeOut(duration: CircleMotion.quick)
        /// From the sleep curtain: the black lifts as the word writes in.
        static let blackAway = Animation.easeInOut(duration: 0.7)
        /// "shukr" writing itself: each letter fades in, one step after the last.
        static let letter = Animation.easeOut(duration: 0.5)
        static let letterStepDuration: Double = 0.08
        /// The ring drawing itself round the word, just after the letters start.
        static let ringDraw = Animation.easeInOut(duration: 0.9).delay(0.1)
        /// The heartbeat: lub…
        static let firstBeatDuration: Double = 0.56
        /// …the ring shining as it closes…
        static let shine = Animation.easeInOut(duration: 0.6)
        /// …dub.
        static let secondBeatDuration: Double = 0.17
        /// The word held in its ring.
        static let holdDuration: Double = 0.5
        /// A few points onto a circle that reported late.
        static let glide = Animation.easeInOut(duration: 0.5)
        static let beforeGrowDuration: Double = 0.45
        /// Nothing to land on: the ring opens out like a doorway, the page going with it.
        static let portal = Animation.easeIn(duration: 0.7)
        static let portalPage = Animation.easeInOut(duration: 0.6).delay(0.15)
        static let portalDuration: Double = 0.76
        /// The landing: the ring grows out into the circle's track…
        static let grow = Animation.spring(response: 0.75, dampingFraction: 0.9)
        /// …into the band…
        static let toBandDuration: Double = 0.65
        /// …or, for a prayer that hasn't started, its edge first, then the dashes.
        static let toDashesDuration: Double = 0.56
        static let dashes = Animation.easeInOut(duration: 0.3)
        static let dashesDuration: Double = 0.32
        /// The page round it fading in (CircleMotion.pageRevealDuration, the chrome's and the list's), and the overlay
        /// going on a landing that isn't the circle's.
        static let overlayAway = Animation.easeInOut(duration: CircleMotion.pageRevealDuration)
        /// Landed on a prayer that's on: its arc sweeps from the start out to where it stands.
        static let arcSweep = Animation.easeInOut(duration: 0.9)
        static let pageInDuration: Double = CircleMotion.pageRevealDuration + 0.02
    }
}
