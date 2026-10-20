//
//  SleepMode.swift
//  shukr
//
//  Tasbeeh sleep mode (owner, 2026-09-30, ideas F3BR + 4WTV, ask sleep-mode):
//  - `SleepIntroView`: the first time the sleep chip is turned on, a full-page sheet explains it;
//    "Turn on sleep mode" turns it on and never shows the sheet again, "Not now" leaves it off and
//    shows it again next time (decision sleep-intro A). The sleep chip's (i) opens it any time (owner,
//    2026-09-30); with sleep already on it has just "Done".
//  - `MorningCurtain`: when sleep mode ended a session, the next open plays the welcome (from black after
//    a warm lock — `WelcomeGate`'s curtain) and its ring lands on the Salah circle, which shows the session
//    (`MorningFace`) inside the card's page; "Good morning" fades the page away round it, leaving the Salah
//    page (decisions sleep-morning-card A, sleep-morning-open).
//

import SwiftUI
import SwiftData

/// The session sleep mode ended, waiting to be shown the next time the Salah page is up.
enum SleepMorning {
    static let pendingKey = "sleepMorningSession"
    static let introConfirmedKey = "sleepIntroConfirmed"

    /// When the last tap was (the clock time; the session's own seconds leave pauses out).
    static let endedAtKey = "sleepMorningEndedAt"
    /// Set once the app has been in the background since: the card waits for the next open — never
    /// in the same stretch he fell asleep in (owner, sleep-mode-fixes).
    static let armedKey = "sleepMorningArmed"
    /// Older than this and it's no longer "this morning": dropped without a word.
    static let expiresAfter: TimeInterval = 16 * 3600

    static func remember(_ session: SessionDataModel, endedAt: Date, armed: Bool) {
        let d = UserDefaults.standard
        d.set(session.id.uuidString, forKey: pendingKey)
        d.set(endedAt.timeIntervalSince1970, forKey: endedAtKey)
        d.set(armed, forKey: armedKey)
    }
    static var pendingID: UUID? {
        UserDefaults.standard.string(forKey: pendingKey).flatMap(UUID.init(uuidString:))
    }
    static var endedAt: Date? {
        let t = UserDefaults.standard.double(forKey: endedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static var isArmed: Bool { UserDefaults.standard.bool(forKey: armedKey) }
    /// The session's zikr as the card names it.
    static func name(of session: SessionDataModel) -> String {
        if let m = session.mantra?.name { return m }
        return session.title == "Untitled" || session.title.isEmpty ? "Freestyle" : session.title
    }
    /// The app went to the background with a card waiting: show it on the next open.
    static func armIfPending() { if pendingID != nil { UserDefaults.standard.set(true, forKey: armedKey) } }
    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: pendingKey); d.removeObject(forKey: endedAtKey); d.removeObject(forKey: armedKey)
    }

    /// The session to show, if it still exists and ended within `expiresAfter` (else the keys go).
    @MainActor static func pending(in context: ModelContext) -> SessionDataModel? {
        guard let id = pendingID else { return nil }
        if let endedAt, Date().timeIntervalSince(endedAt) > expiresAfter { clear(); return nil }
        let found = try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.id == id })).first
        if found == nil { clear() }
        return found
    }
}

// MARK: - The intro

/// The pause screen's explainer pages (sleep mode, continuous): one layout, so an (i) always
/// opens the same kind of page (owner, goal-info B: "keep that pattern").
struct ChipIntroPage: View {
    struct Point: Identifiable {
        let symbol: String, title: String, line: String
        var id: String { title }
    }
    let symbol: String
    let title: String
    let subtitle: String
    let points: [Point]
    let primary: String
    let onPrimary: () -> Void
    var secondary: String? = nil
    var onSecondary: () -> Void = {}
    /// Under the points (or instead of them): the goal page's two cards.
    var extra: AnyView? = nil

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().stroke(Color(.secondarySystemFill), lineWidth: 10).frame(width: 120, height: 120)
                        Image(systemName: symbol)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.sage)
                    }
                    .padding(.top, 40)
                    Text(title)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                    Text(subtitle)
                        .font(.subheadline).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: point.symbol)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.sage)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title).font(.headline.weight(.medium)).fontDesign(.rounded)
                                    Text(point.line).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, points.isEmpty ? 0 : 30)
                    if let extra {
                        extra
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    Button(action: onPrimary) {
                        Text(primary)
                            .font(.headline).fontDesign(.rounded)
                            .foregroundStyle(Color.sage)
                            .frame(maxWidth: 280).frame(height: 50)
                            .background(Capsule().fill(Color.sage.opacity(0.14)))
                            .overlay(Capsule().stroke(Color.sage.opacity(0.5), lineWidth: 1))
                    }
                    if let secondary {
                        Button(action: onSecondary) {
                            Text(secondary)
                                .font(.subheadline).fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
}

struct SleepIntroView: View {
    /// Opened from the chip's (i) with sleep already on: just "Done".
    var isOn = false
    /// How dark the counter gets (decision sleep-dimmer-place A: here, with a live preview — it sat at the top of the
    /// pause screen). Nil: no dimmer on the page.
    var dimmer: Binding<Double>? = nil
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ChipIntroPage(
            symbol: "moon.zzz.fill", title: "Sleep mode", subtitle: "for counting in bed",
            points: [
                .init(symbol: "sun.min", title: "The screen dims",
                      line: "Gentle in the dark. Set how dark below; the sleep button stays bright on the pause screen."),
                .init(symbol: "hand.tap", title: "Fall asleep counting?",
                      line: "After 45 seconds without a tap, a quiet 10-second countdown — then shukr saves the session, ending at your last tap."),
                .init(symbol: "lock", title: "Your phone locks as usual",
                      line: "Once it's saved, the screen turns off by itself. Locking it yourself while counting saves it the same way."),
                .init(symbol: "sunrise", title: "In the morning",
                      line: "shukr shows what you counted and about when you fell asleep."),
            ],
            primary: isOn ? "Done" : "Turn on sleep mode", onPrimary: isOn ? onNotNow : onTurnOn,
            secondary: isOn ? nil : "Not now", onSecondary: onNotNow,
            extra: dimmer.map { AnyView(SleepDimmerPreview(dimmer: $0)) })
    }
}

/// How dark the counter gets under sleep mode: a little counter, dimmed as the session will be, over the slider.
private struct SleepDimmerPreview: View {
    @Binding var dimmer: Double

    var body: some View {
        VStack(spacing: 14) {
            Text("How dark the counter gets")
                .font(.subheadline.weight(.medium)).fontDesign(.rounded)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.1))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 5).frame(width: 84, height: 84)
                    Circle().trim(from: 0, to: 0.62)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 84, height: 84)
                    Text("21").font(.system(size: 28, weight: .thin, design: .rounded)).foregroundStyle(.white)
                }
                // The session's own dim: the same formula as the counter's.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity((1 - dimmer) * 0.9))
            }
            .frame(height: 140)
            HStack(spacing: 10) {
                Image(systemName: "moon.fill").font(.caption)
                Slider(value: $dimmer, in: 0...1.0).tint(Color.sage)
                Image(systemName: "sun.max.fill").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// The "continuous" chip's (i) (owner: "the flexibility to read more than the task at hand, so
/// they don't get stopped at the goal and have to start a new session"). Made from this session:
/// its goal and where it stands, and the two settings as cards side by side — the current one
/// picked, tap the other to switch — each saying how this session would go (owner: no generic
/// lines that could alarm on the default).
struct GoalIntroView: View {
    @Binding var autoStop: Bool
    /// Past the goal on continuous: switching back is locked (it would end the session at once).
    let locked: Bool
    /// "33" or "10 min" (in the cards' lines; the subtitle carries it too).
    let goal: String
    /// "Alhamdulillah · 12 of 33 so far" — whatever the session knows.
    let subtitle: String
    let onDone: () -> Void

    var body: some View {
        // Named as its chip (decision chip-continuous A: "change the sheet to match").
        ChipIntroPage(
            symbol: "arrow.clockwise", title: "Continuous", subtitle: subtitle,
            points: [],
            primary: "Done", onPrimary: onDone,
            extra: AnyView(cards))
    }

    private var cards: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                card(stops: true, symbol: "flag.checkered", title: "Stops at goal", kind: "Auto stop",
                     line: "Ends and saves by itself at \(goal).")
                card(stops: false, symbol: "arrow.clockwise", title: "Continuous", kind: "Manual stop",
                     line: "Carries on past \(goal) — finish with \u{201C}goal reached\u{201D} at the bottom.")
            }
            Text(locked
                 ? "You're past \(goal), so this session keeps going. Finish it from \u{201C}goal reached\u{201D} or the pause screen."
                 : "Tap one to switch. It's for this session only.")
                .font(.footnote).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }

    private func card(stops: Bool, symbol: String, title: String, kind: String, line: String) -> some View {
        let picked = autoStop == stops
        let disabled = locked && stops
        return Button {
            guard !disabled, !picked else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.snappy(duration: 0.2)) { autoStop = stops }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(picked ? Color.sage : Color.primary.opacity(0.7))
                    Spacer()
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(picked ? Color.sage : Color.primary.opacity(0.25))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.weight(.medium)).fontDesign(.rounded)
                        .foregroundStyle(.primary)
                    // What the switch does, in two words (owner).
                    Text(kind)
                        .font(.subheadline.weight(.medium)).fontDesign(.rounded)
                        .foregroundStyle(picked ? Color.sage : Color.secondary)
                }
                Text(line)
                    .font(.footnote).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? Color.sage.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(picked ? Color.sage.opacity(0.6) : Color.clear, lineWidth: 1.2)
            )
            .opacity(disabled ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: - The morning card

/// The morning card's session in the Salah circle (circle step 3): its count and zikr inside the ring, a thin sage ring
/// just inside the track. The circle shows it while `CircleStage.morning` is set; the page round it is `MorningCurtain`.
struct MorningFace: View {
    let session: SessionDataModel

    var body: some View {
        ZStack {
            Circle().stroke(Color.sage.opacity(0.9), lineWidth: 2.5).padding(4.75)
            VStack(spacing: 2) {
                Text("\(session.totalCount)")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text(SleepMorning.name(of: session)).font(.subheadline).fontDesign(.rounded).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 200, height: 200)
    }
}

/// The morning card round the Salah circle (circle step 3; decisions sleep-morning-card A, sleep-morning-open): the page,
/// with a hole where the circle — the one ring, showing `MorningFace` — shows through; the words above, the numbers and
/// the way out below. It used to draw its own copy of the ring over the circle, lined up by measured frames.
struct MorningCurtain: View {
    let session: SessionDataModel
    let onDone: () -> Void
    let onHistory: () -> Void
    /// The page (opaque at once under the welcome, which lands on the circle) and, after, its words.
    @State private var pageIn = false
    @State private var shown = false
    @Environment(\.circleTheme) private var theme

    /// The last tap's clock time (stored when it ended); older builds' sessions: start + active time.
    private var ended: Date { SleepMorning.endedAt ?? session.startTime.addingTimeInterval(session.secondsPassed) }
    /// The hole: the ring, its band and the soft band's shadow, feathered into the page.
    private static let hole: CGFloat = 244

    var body: some View {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds
            ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let circle = WelcomeTarget.circleFrame
            ?? CGRect(x: screen.midX - 100, y: screen.midY - 100, width: 200, height: 200)
        ZStack(alignment: .topLeading) {
            theme.backdrop
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: Self.hole, height: Self.hole)
                                .blur(radius: 5)
                                .position(x: circle.midX, y: circle.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .opacity(pageIn ? 1 : 0)
                .contentShape(Rectangle())   // the hole too: nothing under the card takes a tap

            // Above the circle.
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sage)
                Text("You fell asleep counting")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                Text("shukr saved your session")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
            .frame(width: screen.width)
            .position(x: screen.midX, y: circle.minY - 70)
            .opacity(shown ? 1 : 0)

            // Under it: when it ended, the numbers, then the way out.
            VStack(spacing: 0) {
                Text("ended around \(ended.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 17, design: .rounded))
                Text("after your last tap · \(zikrDurationString(session.secondsPassed)) counting")
                    .font(.footnote).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                HStack(spacing: 10) {
                    tile("\(session.totalCount)", "counted")
                    tile(zikrDurationString(session.secondsPassed), "time")
                    tile(session.secondsPerCount.map { String(format: "%.1fs", $0) } ?? "–", "per count")
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                Spacer(minLength: 16)
                Button {
                    triggerSomeVibration(type: .light)
                    finish(then: onDone)
                } label: {
                    Text("Good morning")
                        .font(.headline).fontDesign(.rounded)
                        .foregroundStyle(Color.sage)
                        .frame(width: 210, height: 48)
                        .background(Capsule().fill(Color.sage.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.sage.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    finish(then: onHistory)
                } label: {
                    Text("View in Zikr History")
                        .font(.footnote).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .frame(width: screen.width, height: max(screen.maxY - circle.maxY - 28 - 34, 200))
            .position(x: screen.midX, y: (circle.maxY + 28 + screen.maxY - 34) / 2)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
        .ignoresSafeArea()
        .onAppear {
            CircleCover.set("morningCard", true)
            guard WelcomeTarget.playing || WelcomeGate.curtainUp else {
                withAnimation(CircleMotion.Morning.wordsIn) { pageIn = true; shown = true }
                return
            }
            // Under the welcome: its ring lands on the circle, then the words come in. The page eases in (it goes up a
            // beat after the welcome starts, over the page or a fading black: at once, it was a step).
            withAnimation(CircleMotion.Morning.pageUnderWelcome) { pageIn = true }
        }
        .task {
            guard !shown else { return }
            // From the moment the welcome's ring lands: its page fades out as the words fade in. It wakes when the
            // welcome's state changes (it polled every 50 ms, and spun once cancelled — audit B).
            let welcome = WelcomeTarget.state
            guard await CircleStage.shared.until({ !((welcome.playing && !welcome.landed) || welcome.curtainUp) }) else { return }
            withAnimation(CircleMotion.Morning.wordsIn) { pageIn = true; shown = true }
        }
        .onDisappear { CircleCover.set("morningCard", false) }
    }

    /// The words go — the card's and the circle's (its morning face goes out, then the prayer comes in: a swap) — and the
    /// page fades from round the ring, which stays.
    private func finish(then go: @escaping () -> Void) {
        typealias T = CircleMotion.Morning
        withAnimation(T.wordsOut) { shown = false }
        CircleStage.shared.morning = nil
        Task { @MainActor in
            // The page fades once the words are on their way, and the card goes when it has (it was a guessed 0.5 s).
            _ = await CircleGate.pause(T.pageAfterWordsDuration)
            await CircleMotion.animate(T.pageAway) { pageIn = false }
            go()
        }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).fontDesign(.rounded).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - The session's half (tasbeehView)

/// Sleep mode inside a counting session: the inactivity countdown, the finish that saves the session asleep, the
/// quiet close after it, "Keep counting", and what leaving the app does (cleanup-map tangle 5, step 7: moved out of
/// tasbeehView.swift; the session's state stays in its models, TasbeehModels.swift).
extension tasbeehView {
    /// What "Keep counting" needs to carry the session on after sleep mode saved it (owner,
    /// sleep-keep-going): taken just before the save, since the stop clears these a beat later.
    struct SleepResume {
        var startTime: Date?, endTime: Date?, totalPause: Double
        var targetCount: String, task: TaskModel?, lastTapAt: Date?
    }

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

    func requestKeepCounting() {
        if sleepResumeReady { keepCountingAfterSleep() } else { resumeWanted = true }
    }

    /// "Keep counting" on the results after a sleep finish: he was only dozing. The saved row goes and
    /// the same session carries on at the same count with sleep still on; the doze (last tap → now)
    /// counts as a pause, so it's saved once at its real end and the pace stays honest.
    func keepCountingAfterSleep() {
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

    /// Leaving the app mid-session, sleep mode's part (true when it took the change):
    /// Sleep mode on and counting: the phone locking or leaving the app means he's asleep —
    /// finish and save, ending at the last tap (he woke up on the pause screen before:
    /// pausing stopped the inactivity timer).
    func sleepModeTookScenePhase(_ newScenePhase: ScenePhase) -> Bool {
        // Saved by the countdown and now the phone has locked: close quietly in the background.
        if sleptSaved {
            if newScenePhase == .background {
                NotificationCenter.default.post(name: WelcomeGate.raiseCurtain, object: nil)   // black before iOS's picture
                closeAfterSleep()
            }
            return true
        }
        // Paused with sleep on counts too: auto-lock would leave him on the pause screen (or iOS
        // would kill the app and lose the session).
        // Inactive alone (the task switcher, Control Center) pauses as usual — he brings the pause
        // screen up that way (owner); the lock (inactive, then background) then finishes it.
        if toggleInactivityTimer && timerIsActive && newScenePhase == .background {
            finishAsleep()
            return true
        }
        return false
    }
}

// MARK: - The morning card's hand-off (PrayerTimesView)

/// The Salah page's half: be on it while the app is away, then open the card once nothing covers the circle
/// (cleanup-map tangle 5, step 7: moved out of PrayerTimesAndTracker.swift; `morningSession` stays its @State).
extension PrayerTimesView {
    /// A morning card is waiting: be on the Salah page (circle showing) while the app is away, so the
    /// next open's welcome and the card draw on the real circle from the first frame. Left on the Zikr
    /// page (where the session started), the circle's last frame was off screen and the welcome
    /// started half off the screen (owner, sleep morning). Behind the black curtain, so unseen.
    func goToSalahForMorningCard() {
        guard SleepMorning.pendingID != nil else { return }
        sharedState.go(to: .main, animated: false)   // in this turn: the curtain's snapshot is next
        SalahSheetDrag.closeQuietly(sharedState)
    }

    /// Sleep mode ended a session: once nothing is over the Salah page, go to it (circle showing) and
    /// open the morning card on its circle — under the welcome while it plays, which lands on the card. It waits on the
    /// stage (the app active; no cover — the session, a pushed page, a sheet, the setup, the map), waking when that
    /// changes: it retried every 0.5 s, 40 times (tr-final).
    func showMorningCardWhenClear() {
        guard morningSession == nil, SleepMorning.pendingID != nil, SleepMorning.isArmed else { return }
        morningWait?.cancel()
        morningWait = Task { await showMorningCard() }
    }

    private func showMorningCard() async {
        let stage = CircleStage.shared
        // Not waiting for the welcome: the card goes up under it, so the welcome lands on its ring.
        guard await stage.until(deadline: Self.morningCardDeadline, { stage.sceneActive && CircleCover.nothingOverCircle }),
              morningSession == nil, SleepMorning.pendingID != nil, SleepMorning.isArmed,
              let session = SleepMorning.pending(in: context) else { return }
        SalahSheetDrag.closeQuietly(sharedState)
        // The card draws round the circle's frame: mount it once the pager rests on Salah (at once — the page change
        // is quiet — but measured, not guessed: audit D, finding 2).
        await sharedState.navigate(to: .main, animated: false)
        guard !Task.isCancelled, morningSession == nil, SleepMorning.pendingID != nil else { return }
        morningSession = session
    }

    private static let morningCardDeadline: Double = 20

    /// The card itself, over the page while `morningSession` is set.
    @ViewBuilder var morningCard: some View {
        if let morningSession {
            MorningCurtain(session: morningSession, onDone: {
                SleepMorning.clear()
                self.morningSession = nil
            }, onHistory: {
                SleepMorning.clear()
                self.morningSession = nil
                // History is the Zikr tab's: locked, the Zikr page and its lock instead (ZikrLock).
                if ZikrLock.shared.locked { sharedState.go(to: .zikr) } else { showZikrHistory = true }
            })
            .transition(.identity)
        }
    }
}

extension CircleMotion {
    /// The morning card round the circle (MorningCurtain).
    enum Morning {
        /// Its words (and, with no welcome playing, the page) coming in.
        static let wordsIn = Animation.easeOut(duration: 0.5)
        /// The page going up under the welcome, before the ring lands.
        static let pageUnderWelcome = Animation.easeOut(duration: 0.3)
        /// Good morning / View in History: the words go, then the page round the ring.
        static let wordsOut = Animation.easeOut(duration: 0.22)
        static let pageAfterWordsDuration: Double = 0.15
        static let pageAway = Animation.easeInOut(duration: 0.3)
    }
}
