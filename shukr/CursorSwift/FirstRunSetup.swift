//
//  FirstRunSetup.swift
//  shukr
//
//  The first-run setup (notes #18 + #6; owner-approved from the round-2 mockups, 2026-09-28). It
//  replaced the old first open (`GradientAnimationLoad`: wavy gradient, glass cards).
//
//  Look: the everyday opening's (WelcomeAnimation.swift) — the plain background, a sage ring, light
//  rounded type. The small ring at the top is the progress (where you pray · appearance · reminders
//  · Fajr · masjid) with the step's symbol inside; every title sits at the same height under it;
//  one calm primary button at the bottom; Skip on every step. Nothing blocks: each step shows the
//  real setting (so existing users see theirs), prompts only for a permission that isn't decided,
//  and the review nudges (never blocks) towards the best permissions.
//
//  Every control is bound to the setting it changes — no parallel keys:
//  - location: EnvLocationManager (Always asked here, "Enter a city" = CityPickerSheet);
//  - method: `calculationMethod` (0 = Automatic, AutoMethod) · madhab: `school` (app group);
//  - appearance: `modeToggleNew` (0 light, 1 dark, 2 auto);
//  - reminders: `<prayer>Notif` (at the start) + `<prayer>Nudges` (30 min in and 30 min left);
//  - Fajr alarm: `alarmEnabled` / `alarmOffsetMinutes` / `alarmIsBefore` / `alarmIsFajr`;
//  - masjid: `MosqueFavorites` + `MasjidArrival`.
//
//  Bismillah (last step) hands off to the everyday opening: the page fades, the ring glides onto the
//  Salah circle and becomes the welcome's ring (`WelcomeOverlay(startDrawn:)`), "shukr" writes
//  itself and the ring grows into the circle.
//
//  Shown once per install, existing users included (`FirstRunSetup.doneKey`), never over a widget /
//  control deep link (that launch goes straight there; the setup waits). DEBUG / TestFlight:
//  Settings → Run setup again. DEBUG: `-setupForce`, `-setupReset`, `-setupStep <step>`,
//  `-setupEnter` (presses Bismillah 3 s into the review).
//

import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import WidgetKit
import SwiftData
import Adhan

// MARK: - When it shows

enum FirstRunSetup {
    static let doneKey = "firstRunSetup.v1"
    /// Settings → Run setup again (DEBUG / TestFlight).
    static let rerun = Notification.Name("firstRunSetup.rerun")
    /// Bismillah's hand-off is over: PrayerTimesView acts on any widget / control deep link that
    /// arrived during the setup (it holds them while the setup is up, so the hand-off lands on the
    /// real circle).
    static let finished = Notification.Name("firstRunSetup.finished")
    /// The setup is on screen (the root sets it). PrayerTimesView leaves deep-link flags alone meanwhile.
    static var isShowing = false
    /// The Always upgrade prompt has been asked for (iOS shows it once; after that, only Settings).
    static let alwaysAskedKey = "locationAlwaysAsked"
    static var alwaysAsked: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysAskedKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysAskedKey) }
    }
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    /// The setup is up this launch (the launch welcome stays out of its way: the setup ends in it).
    static private(set) var showingAtLaunch = false

    /// Once per launch, before anything computes times: an install that never picked a method gets
    /// one written (existing users ISNA, what an unset value meant; new installs Automatic), and a
    /// new install starts on Auto appearance (the setup's recommendation).
    static func migrateDefaults() {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        let existing = group?.object(forKey: "lastLatitude") != nil || isDone
        AutoMethod.migrateDefault(existingUser: existing)
        NotificationDefaults.migrate(existingUser: existing)   // their reminders don't change; new installs: the owner's defaults
        if !existing && UserDefaults.standard.object(forKey: "modeToggleNew") == nil {
            UserDefaults.standard.set(2, forKey: "modeToggleNew")
        }
        // The Fajr alarm's rule shows "before" / "the start" when unset, but `bool(forKey:)` read an
        // unset key as false ("after" / "the end") in the Shortcut's intent — write the real defaults
        // once, so the setup, Settings and the intent agree.
        for key in ["alarmIsBefore", "alarmIsFajr"] where group?.object(forKey: key) == nil {
            group?.set(true, forKey: key)
        }
        // The alarm's stored description (Settings' row) in today's words: it was written by older
        // builds ("Alarm at Sunrise …") and otherwise only changes when the rule is edited.
        if group?.bool(forKey: "alarmEnabled") == true, let calc = try? PrayerUtils.calculateAlarmDescription() {
            if group?.string(forKey: "alarmDescription") != calc.description { group?.set(calc.description, forKey: "alarmDescription") }
            let time = shortTimePM(calc.time)
            if group?.string(forKey: "alarmTimeSetFor") != time { group?.set(time, forKey: "alarmTimeSetFor") }
        }
    }

    static func markDone() {
        if !isDone { UserDefaults.standard.set(true, forKey: doneKey) }
    }

    /// Widget / control / Action-button launches set one of these before the app opens.
    static let deepLinkFlags = ["widgetCompass", "widgetDailyAyah", "widgetNames", "widgetTasbeeh", "widgetZikrTask"]
    static var openedFromDeepLink: Bool {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        return deepLinkFlags.contains { group?.bool(forKey: $0) == true }
    }

    /// There's a location to open a deep link onto (a stored coordinate). Without one the widget
    /// can't be acted on anyway (no Salah page), so a new install opened from a widget still gets
    /// the setup — and a flag left behind never keeps it away.
    private static var hasStoredLocation: Bool {
        UserDefaults(suiteName: SharedStore.appGroup)?.object(forKey: "lastLatitude") != nil
    }

    /// Decided once, when the root view is built.
    static func shouldShowAtLaunch() -> Bool {
        var show = !isDone && !(openedFromDeepLink && hasStoredLocation)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-setupReset") {
            UserDefaults.standard.removeObject(forKey: doneKey)
            UserDefaults.standard.removeObject(forKey: alwaysAskedKey)
            show = !(openedFromDeepLink && hasStoredLocation)
        }
        if args.contains(where: { $0.hasPrefix("-demo") }) { show = false }   // screenshots / automation
        if args.contains("-setupForce") { show = true }
        #endif
        showingAtLaunch = show
        return show
    }
}

#if DEBUG
/// `-autoMethodTest`: checks the Automatic table for a few cities (the country code a geocode
/// returns, and the coordinate fallback), printed as ✅ / ❌. No test target in this project.
enum AutoMethodSelfTest {
    static func run() {
        let cities: [(String, Double, Double, String, Int)] = [
            ("New York", 40.71, -74.01, "US", 2), ("Toronto", 43.65, -79.38, "CA", 2),
            ("London", 51.51, -0.13, "GB", 3), ("Riyadh", 24.71, 46.68, "SA", 4),
            ("Cairo", 30.04, 31.24, "EG", 5), ("Karachi", 24.86, 67.01, "PK", 1),
            ("Istanbul", 41.01, 28.98, "TR", 13), ("Kuala Lumpur", 3.14, 101.69, "MY", 11),
            ("Dubai", 25.20, 55.27, "AE", 8), ("Doha", 25.29, 51.53, "QA", 10),
            ("Kuwait City", 29.38, 47.99, "KW", 9), ("Tehran", 35.69, 51.39, "IR", 7),
            ("Lagos", 6.52, 3.38, "NG", 5), ("Berlin", 52.52, 13.40, "DE", 3),
        ]
        for c in cities {
            let byCountry = AutoMethod.method(forCountry: c.3)
            print("\(byCountry == c.4 ? "✅" : "❌") AUTOMETHOD \(c.0) [\(c.3)] → \(AutoMethod.shortName(byCountry))")
        }
        let fallbackNY = AutoMethod.method(latitude: 40.71, longitude: -74.01), fallbackLondon = AutoMethod.method(latitude: 51.51, longitude: -0.13)
        print("\(fallbackNY == 2 ? "✅" : "❌") AUTOMETHOD fallback New York → \(AutoMethod.shortName(fallbackNY))")
        print("\(fallbackLondon == 3 ? "✅" : "❌") AUTOMETHOD fallback London → \(AutoMethod.shortName(fallbackLondon))")
        // France / Russia: real angles now (adhan-swift's .other had none), and their names.
        for (m, lat, lon, city) in [(12, 48.86, 2.35, "Paris"), (14, 55.76, 37.62, "Moscow")] {
            if let t = try? PrayerUtils.getPrayerTimes(for: Date(), coordinates: Coordinates(latitude: lat, longitude: lon),
                                                       params: PrayerUtils.parameters(method: m, school: 0)) {
                let ok = t.fajr < t.sunrise && t.isha > t.maghrib
                print("\(ok ? "✅" : "❌") AUTOMETHOD \(AutoMethod.shortName(m)) in \(city): Fajr \(t.fajr) · Isha \(t.isha)")
            }
        }
        // What a real reverse geocode says the country is (one at a time: CLGeocoder is rate-limited).
        Task { @MainActor in
            for c in cities {
                let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.1, longitude: c.2)).first
                let code = placemark?.isoCountryCode ?? "?"
                print("\(code == c.3 ? "✅" : "❌") AUTOMETHOD geocode \(c.0) → \(code) → \(AutoMethod.shortName(AutoMethod.method(forCountry: code)))")
            }
        }
    }
}
#endif

#if DEBUG
/// `-alarmCheck`: what the Fajr alarm's Shortcut intent would return now (the keys as stored).
enum AlarmSelfTest {
    static func run() {
        let g = UserDefaults(suiteName: SharedStore.appGroup)
        let keys = ["alarmEnabled", "alarmOffsetMinutes", "alarmIsBefore", "alarmIsFajr"]
        print("⏰ ALARMCHECK stored: " + keys.map { "\($0)=\(g?.object(forKey: $0).map { "\($0)" } ?? "unset")" }.joined(separator: " "))
        if let fajr = try? PrayerUtils.getNextTime(for: .fajr) { print("⏰ ALARMCHECK next Fajr: \(shortTimePM(fajr))") }
        do {
            let r = try PrayerUtils.calculateAlarmDescription()
            print("⏰ ALARMCHECK intent: \(r.description) → \(shortTimePM(r.time))")
        } catch { print("⏰ ALARMCHECK intent: \(error)") }
    }
}
#endif

enum SetupStep: String, CaseIterable, Identifiable {
    case welcome, location, method, madhab, appearance, reminders, fajr, masjid, review
    var id: String { rawValue }

    /// The ring: a fifth per group (where you pray · appearance · reminders · Fajr · masjid).
    var progress: Double {
        switch self {
        case .welcome: 0
        case .location, .method, .madhab: 0.2
        case .appearance: 0.4
        case .reminders: 0.6
        case .fajr: 0.8
        case .masjid, .review: 1
        }
    }
    var symbol: String {
        switch self {
        case .welcome: "sparkle"
        case .location, .method, .madhab: "location.fill"
        case .appearance: "circle.lefthalf.filled"
        case .reminders: "bell"
        case .fajr: "alarm"
        case .masjid: "building.columns"
        case .review: "checkmark"
        }
    }
}

// MARK: - The flow

struct FirstRunSetupView: View {
    /// `.locationOnly`: shown after setup when there's no location at all (refused and no city, or
    /// location turned off later) — just the location step; it goes away once there is one.
    enum Mode { case full, locationOnly }
    var mode: Mode = .full
    var onFinish: () -> Void = {}

    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: SetupStep
    /// Bismillah was tapped: the page fades, the ring glides onto the Salah circle…
    @State private var leaving = false
    /// …and becomes the welcome, which plays as on every launch.
    @State private var welcome = false
    @State private var ringCentre: CGPoint = .zero
    /// A review row was tapped: that step (and, for "Prayer times", the madhab after the method) is
    /// edited and then it's straight back to the review (owner, 2026-09-29: "we shouldn't have to go
    /// through the whole flow again"). The ring stays full meanwhile, so nothing reads as going on.
    @State private var editing: SetupStep?
    /// The opening page (a new install / Run setup again): the original welcome's moving gradient and
    /// glass circle, before any step. The steps aren't there at all until it has drained away.
    @State private var opening: Bool
    /// How much of the first step has come in after the opening (ring 1 · title 2 · rows 3 · button 4);
    /// 4 = all, as every other time.
    @State private var reveal: Int

    init(mode: Mode = .full, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish
        var start: SetupStep = mode == .locationOnly ? .location : .welcome
        var withOpening = mode == .full
        #if DEBUG
        // `-setupStep opening` = the opening (as a fresh start); any other step skips it.
        if mode == .full, let raw = UserDefaults.standard.string(forKey: "setupStep") {
            if let s = SetupStep(rawValue: raw) { start = s }
            withOpening = raw == "opening"
        }
        #endif
        _step = State(initialValue: start)
        _opening = State(initialValue: withOpening)
        _reveal = State(initialValue: withOpening ? 0 : 4)
    }

    var body: some View {
        ZStack {
            // Gone once the welcome takes over (it has its own background).
            Color(.systemBackground).ignoresSafeArea()
                .opacity(welcome ? 0 : 1)
            if opening {
                SetupOpening(onDone: finishOpening)
            } else {
                VStack(spacing: 0) {
                    topBar
                        .opacity(leaving || reveal < 1 ? 0 : 1)
                    SetupRing(progress: editing == nil ? step.progress : 1, symbol: step.symbol, handoff: leaving)
                        .onGeometryChange(for: CGPoint.self) { geo in
                            let f = geo.frame(in: .global); return CGPoint(x: f.midX, y: f.midY)
                        } action: { if !leaving { ringCentre = $0 } }
                        .offset(leaving ? handoffShift : .zero)
                        .padding(.top, 4)
                        .opacity(reveal >= 1 ? 1 : 0)
                        .zIndex(1)
                    Group {
                        switch step {
                        case .welcome: WelcomeStep(next: { go(.location) })
                        case .location: LocationStep(locationOnly: mode == .locationOnly, next: { advance(to: .method) })
                        case .method: MethodStep(next: { advance(to: .madhab) })
                        case .madhab: MadhabStep(next: { advance(to: .appearance) })
                        case .appearance: AppearanceStep(next: { advance(to: .reminders) })
                        case .reminders: RemindersStep(next: {
                            NotificationScheduler.reschedule(context: context, reason: "setup reminders")
                            advance(to: .fajr)
                        })
                        case .fajr: FajrStep(next: { advance(to: .masjid) })
                        case .masjid: MasjidStep(next: { advance(to: .review) })
                        case .review: ReviewStep(jump: { editing = $0; go($0) }, done: enterApp)
                        }
                    }
                    // The last step of an edit from the review: its "Continue" reads "Done".
                    .environment(\.setupReturnsToReview, editing != nil && step == lastEditedStep)
                    .padding(.top, 26)          // every title at the same height under the ring
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                    .opacity(leaving ? 0 : 1)
                    .environment(\.setupReveal, reveal)
                }
                .fontDesign(.rounded)
                .opacity(welcome ? 0 : 1)
            }
            if welcome {
                WelcomeOverlay(startDrawn: true, onFinish: { WelcomeTarget.playing = false; onFinish() })
                    .transition(.identity)
                    .onAppear { WelcomeTarget.playing = true }
            }
        }
        .onAppear { CircleCover.set("firstRunSetup", true) }
        .onDisappear { CircleCover.set("firstRunSetup", false) }
        #if DEBUG
        .task {
            guard step == .review, ProcessInfo.processInfo.arguments.contains("-setupEnter") else { return }
            try? await Task.sleep(for: .seconds(3))
            enterApp()
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            if step != .welcome && mode == .full {
                Button {
                    if editing != nil {
                        // Editing from the review: back = the review (the madhab's back = its method).
                        if editing == .method && step == .madhab { go(.method) } else { backToReview() }
                    } else if let i = SetupStep.allCases.firstIndex(of: step), i > 0 { go(SetupStep.allCases[i - 1]) }
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if step != .review && mode == .full {
                Button("Skip") { backToReview() }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    /// The opening has drained to the plain page: the first step comes in piece by piece — the ring
    /// (it draws itself as it appears), the title, the rows, then Begin.
    private func finishOpening() {
        typealias T = CircleMotion.Setup
        opening = false
        Task { @MainActor in
            guard await CircleGate.pause(T.revealStartDuration) else { return }
            for stage in 1...4 {
                withAnimation(reduceMotion ? T.revealReduced : T.reveal) { reveal = stage }
                guard stage < 4, await CircleGate.pause(reduceMotion ? T.revealBeatReducedDuration : T.revealBeatDuration) else { return }
            }
        }
    }

    /// A step's Continue: on to `next`, or — editing from the review — back to it once the edited
    /// row's steps are done ("Prayer times" = method, then madhab; everything else is one step).
    private func advance(to next: SetupStep) {
        if editing != nil && step == lastEditedStep { backToReview() } else { go(next) }
    }

    private var lastEditedStep: SetupStep? { editing == .method ? .madhab : editing }

    private func backToReview() {
        go(.review)
        editing = nil
    }

    private func go(_ s: SetupStep) {
        withAnimation(reduceMotion ? CircleMotion.Setup.stepReduced : CircleMotion.Setup.step) { step = s }
    }

    /// From the ring's place to the Salah circle's centre (the screen's centre if it isn't there).
    private var handoffShift: CGSize {
        let screen = UIScreen.main.bounds
        // The Salah circle when it's on screen and can be landed on (Run setup again from Settings:
        // the root pages back to Salah first); else the screen's centre, and the welcome opens out.
        let onScreen = WelcomeTarget.circleFrame.flatMap { f -> CGPoint? in
            guard WelcomeTarget.canLand, f.width > 100, screen.insetBy(dx: -1, dy: -1).contains(f) else { return nil }
            return CGPoint(x: f.midX, y: f.midY)
        }
        let target = onScreen ?? CGPoint(x: screen.midX, y: screen.midY)
        return CGSize(width: target.x - ringCentre.x, height: target.y - ringCentre.y)
    }

    /// Bismillah: save, bring everything up to date, then the hand-off into the everyday opening.
    private func enterApp() {
        guard !leaving else { return }
        FirstRunSetup.markDone()
        // A "no" to notifications here: 3 days' grace before the first "reminders are off" card.
        if NotificationStatus.shared.isOn != true { NotificationHealth.shared.markCardShown(.off) }
        viewModel.fetchPrayerTimes(cameFrom: "first-run setup done")
        NotificationScheduler.reschedule(context: context, reason: "first-run setup done")
        WidgetCenter.shared.reloadAllTimelines()
        WatchSync.shared.send()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        typealias T = CircleMotion.Setup
        Task { @MainActor in
            if reduceMotion {
                await CircleMotion.animate(T.leavingReduced) { leaving = true }
                welcome = true
                return
            }
            // The page lets go; the ring glides onto the circle and thins into the welcome's hairline (SetupRing's own
            // spring, `T.ringGlide`), and the welcome takes over once it's there.
            withAnimation(T.leaving) { leaving = true }
            guard await CircleGate.pause(T.ringGlideDuration) else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { welcome = true }   // same ring, same place: only the letters appear
        }
    }
}

// MARK: - Location lost (after setup)

/// Location was allowed, then turned off in iOS Settings, and there's no city (owner, 2026-09-28: the whole "Where do you
/// pray" setup read like starting over). "shukr lost your location" — a state of the Salah circle (circle step 3b;
/// decision lost-page-circle A, owner: "A"): the circle shows the crossed-out symbol in its own ring; the title above and
/// what sharing location gives below are the circle's (`LostWords`), so they rise with it into the lost page's place;
/// "Turn location back on" / "Enter a city instead" at the bottom (`LostPageLayer`). Location coming back: the symbol turns
/// on and the title says so, then the words go while the circle glides back to its place and draws in to the welcome's
/// starting ring round the symbol, rests, and grows into the track (the welcome's own landing, the same `WelcomeMark`);
/// the prayer and the page come in round it. It used to be a root overlay with its own ring, lined up by measured frames.
@MainActor @Observable final class LostStage {
    /// 0 the circle alone, in its usual place · 1 the title above it · 2 risen to the lost page's place · 3 the reasons
    /// and the buttons.
    var stage = 0
    /// A warm entry holds the title until the circle has risen.
    var titleHeld = false
    /// The symbol and caption in the ring (blur in on a warm entry, out as the ring lands back).
    var symbolIn = true
    /// Location's back (or a city): the symbol turns on, the title says so.
    var acknowledged = false
    /// The ring's words and the title out while they change to the acknowledgement (out, then in: rule 3).
    var wordsAway = false
    var comeback: EnvLocationManager.Comeback?
    /// The hand-off: the words, reasons and buttons go…
    var clearing = false
    /// …while the circle glides back to its usual place.
    var down = false
    /// The ring is the Salah track again: the prayer and the page come back.
    var landed = false
    /// ▶︎ No location: looks only (nothing to tap).
    var preview = false
    /// Measured: the room the title, the reasons and the buttons take round the risen circle (SalahPageContent).
    var titleHeight: CGFloat = 76
    var reasonsHeight: CGFloat = 160
    var buttonsHeight: CGFloat = 170

    /// A measured room changing once the page is up ("Location's back" and its line are taller than "Uh oh"): the
    /// circle eases to its new place with the title's own change — set straight, it stepped a few points in a frame.
    private var measured = false
    func measure(_ change: () -> Void) {
        if measured && stage >= 1 {
            withAnimation(CircleMotion.Lost.room, change)
        } else {
            change()
        }
        measured = true
    }

    var risen: Bool { stage >= 2 && !down }
    var titleShown: Bool { stage >= 1 && !clearing && !titleHeld }
    var textShown: Bool { stage >= 3 && !clearing }

    var onSymbol: String {
        if case .city = comeback { return "mappin.and.ellipse" }
        return "location.fill"
    }
    var onCaption: String {
        if case .city(let name) = comeback { return name.isEmpty ? "your city" : name }
        return "location is on"
    }
    var ackTitle: String {
        if case .city(let name) = comeback { return name.isEmpty ? "Using your city" : "Using \(name)" }
        return "Location's back"
    }
    var ackLine: String {
        switch comeback {
        case .city: return "Prayer times for there, until you turn location on"
        case .whileUsing: return "Choose Always in Settings so your times follow you when you travel"
        default: return "Your times follow you again"
        }
    }
}

/// In the ring: the crossed-out symbol and "location is off" (on, once it's back).
struct LostFace: View {
    let stage: LostStage

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: stage.acknowledged ? stage.onSymbol : "location.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(stage.acknowledged ? Color.sage : Color.secondary)
            Text(stage.acknowledged ? stage.onCaption : "location is off")
                .font(.system(.subheadline, design: .rounded, weight: .thin))
                .foregroundStyle(.secondary)
                // Inside the snug 150 pt ring too (a long city name).
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 112)
        }
        // Off → on: out, then in, like the circle's own words (they cross-faded — audit B).
        .modifier(CircleWordsAway(away: stage.wordsAway))
        // Leaves like the welcome's word as the ring grows (scale 0.9, blur 4).
        .scaleEffect(stage.symbolIn ? 1 : 0.9)
        .opacity(stage.symbolIn ? 1 : 0)
        .blur(radius: stage.symbolIn ? 0 : 4)
    }
}

/// Round the circle: the title above, what sharing location gives below — laid on a 200 pt frame centred on the circle, so
/// they move with it. Each reports its height (the page keeps that room round the risen circle).
struct LostWords: View {
    let stage: LostStage

    var body: some View {
        let width = UIScreen.main.bounds.width
        Color.clear
            .frame(width: 200, height: 200)
            .overlay(alignment: .top) {
                title
                    .padding(.horizontal, 28)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in stage.measure { stage.titleHeight = h } }
                    .opacity(stage.titleShown ? 1 : 0)
                    .blur(radius: stage.titleShown ? 0 : 6)
                    .modifier(CircleWordsAway(away: stage.wordsAway))   // "Uh oh" → "Location's back": out, then in
                    .alignmentGuide(.top) { $0[.bottom] + 28 }
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    whyRow("clock", "Prayer times that follow you", "They update by themselves when you travel.")
                    whyRow("mappin.and.ellipse", "Your prayers, pinned where you prayed", "On the map, with where you were.")
                    whyRow("building.columns", "Duas at your masjid", "When you arrive and when you leave.")
                }
                .padding(.horizontal, 32)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in stage.measure { stage.reasonsHeight = h } }
                .opacity(stage.textShown ? 1 : 0)
                .offset(y: stage.textShown ? 0 : 14)
                .alignmentGuide(.bottom) { $0[.top] - 28 }
            }
            .fontDesign(.rounded)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var title: some View {
        if stage.acknowledged {
            VStack(spacing: 6) {
                Text(stage.ackTitle)
                    .font(.system(.title, design: .rounded, weight: .light))
                    .multilineTextAlignment(.center)
                Text(stage.ackLine)
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 6) {
                Text("Uh oh,")
                    .font(.system(.title3, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                Text("shukr lost your location")
                    .font(.system(.title, design: .rounded, weight: .light))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The lost page's buttons at the bottom of the Salah page, and what runs it: in when location is lost (or ▶︎ No location),
/// the acknowledgement and the hand-off when it comes back (circle step 3b). On PrayerTimesView, over the page.
struct LostPageLayer: View {
    @EnvironmentObject private var location: EnvLocationManager
    @EnvironmentObject private var sharedState: SharedStateClass
    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickingCity = false

    private var isLost: Bool {
        location.lostPreview || (location.locationLost && !(location.isAuthorized || location.hasManualLocation))
    }

    var body: some View {
        ZStack {
            // Always there (an empty Group never appears, so its tasks never ran); takes no taps.
            Color.clear.allowsHitTesting(false)
            if let stage = CircleStage.shared.lost {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        PrimaryButton(title: "Turn location back on", action: SettingsLinks.app)
                        SecondaryButton(title: "Enter a city instead") { pickingCity = true }
                        Text("A fixed city keeps prayer times, but not the travel updates, the pins or the masjid duas.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                    .fontDesign(.rounded)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in stage.measure { stage.buttonsHeight = h } }
                    .opacity(stage.textShown ? 1 : 0)
                    .offset(y: stage.textShown ? 0 : 14)
                    .allowsHitTesting(stage.textShown && stage.comeback == nil && !stage.preview)
                }
            }
        }
        .task(id: isLost) { if isLost { await enter() } }
        .task(id: location.comeback) { if location.comeback != nil { await acknowledge() } }
        .sheet(isPresented: $pickingCity) {
            CityPickerSheet(onPicked: { pickingCity = false })
        }
    }

    private func quietly(_ change: () -> Void) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet, change)
    }

    /// Location lost: on a launch, under the welcome — the circle alone where the welcome lands, then the title appears
    /// above it, both rise to their place, the reasons and buttons fill in. While the app is open: the page round the
    /// circle fades, its prayer goes out and the symbol comes in, the circle rises, then the title, then the rest.
    private func enter() async {
        typealias T = CircleMotion.Lost
        guard CircleStage.shared.lost == nil else { return }
        guard await CircleGate.pause(T.launchSettleDuration) else { return }   // a launch: the welcome is up by now
        guard isLost, CircleStage.shared.lost == nil else { return }
        let stage = LostStage()
        stage.preview = location.lostPreview
        CircleCover.set("lost", true)   // no reminders card / qibla buzz meanwhile (not over the circle: CircleCover)
        if WelcomeTarget.playing || reduceMotion || !CircleStage.shared.sceneActive {
            quietly { sharedState.navPosition = .main }
            sharedState.go(to: .main, animated: false)
        } else if sharedState.horizontalPage != .main || sharedState.navPosition != .main {
            // Open on another page or with the list up: back to the circle the usual way first, and on once it's there
            // (it was a guessed 0.45 s).
            async let page = sharedState.navigate(to: .main)
            await CircleMotion.animate(CircleMotion.page) { sharedState.navPosition = .main }
            _ = await page
            guard !Task.isCancelled else { return }
        }
        if reduceMotion {
            stage.stage = 3
            withAnimation(T.reduced) { CircleStage.shared.lost = stage }
            location.endSalahLinger()
            return
        }
        // Each step returns if this run was cancelled (location back, or the page gone): the comeback takes it from
        // where it is — the rest of the steps used to fire at once (audit B).
        if WelcomeTarget.playing {
            // Under the welcome (it lands on this circle, solid, the lost ring).
            quietly { CircleStage.shared.lost = stage }
            let welcome = WelcomeTarget.state
            guard await CircleStage.shared.until({ !welcome.playing }) else { return }   // it polled every 100 ms
            guard await CircleGate.pause(T.afterWelcomeDuration), stage.comeback == nil else { return }
            withAnimation(T.titleIn) { stage.stage = 1 }
            guard await CircleGate.pause(T.titleDuration), stage.comeback == nil else { return }
            withAnimation(T.rise) { stage.stage = 2 }
            guard await CircleGate.pause(T.riseDuration), stage.comeback == nil else { return }
            withAnimation(T.restIn) { stage.stage = 3 }
            #if DEBUG
            // `-demoLostCity London`: pick that city 2 s after the page settles (the city sheet's path).
            if let city = UserDefaults.standard.string(forKey: "demoLostCity") {
                try? await Task.sleep(for: .seconds(2))
                location.setManualLocation(CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), name: city)
            }
            #endif
            return
        }
        // While the app is open. Only once it's really on screen (not under iOS's snapshot as it comes back).
        _ = await CircleStage.shared.until(deadline: T.onScreenDeadline) { CircleStage.shared.sceneActive }
        guard await CircleGate.pause(T.warmSettleDuration) else { return }
        stage.symbolIn = false
        stage.titleHeld = true
        stage.stage = 1
        // The page round the circle fades (its own animations); the circle's prayer goes out, its ring stays.
        CircleStage.shared.lost = stage
        location.endSalahLinger()
        guard await CircleGate.pause(T.pageAwayDuration), stage.comeback == nil else { return }
        withAnimation(T.rise) { stage.stage = 2 }
        withAnimation(T.symbolIn) { stage.symbolIn = true }
        guard await CircleGate.pause(T.warmRiseDuration), stage.comeback == nil else { return }
        withAnimation(T.titleIn) { stage.titleHeld = false }
        guard await CircleGate.pause(T.titleAfterRiseDuration), stage.comeback == nil else { return }
        withAnimation(T.restIn) { stage.stage = 3 }
    }

    /// Location's back (or a city): the symbol turns on with a soft success, the title says so; then the words go while
    /// the circle glides back to its place and draws in to the welcome's starting ring round the symbol; it rests, then
    /// does the welcome's own landing — grows into the track (or the dashes) as the symbol lets go — and the prayer and
    /// the page come in round it. Reduce Motion: the acknowledgement, a fade. Cancelled (a newer comeback), it stops
    /// where it is and the newer one carries on from there.
    private func acknowledge() async {
        typealias T = CircleMotion.Lost
        typealias Landing = CircleMotion.Opening
        guard let stage = CircleStage.shared.lost, let comeback = location.comeback else {
            // Nothing up to acknowledge it (it came back before the page did): just go on.
            if CircleStage.shared.lost == nil { location.clearComeback() }
            return
        }
        defer { if stage.wordsAway { stage.wordsAway = false } }   // stopped while the words were out: they come back
        pickingCity = false
        // Already saying it's back (a newer comeback: a city after "while using"): its words change out, then in, below.
        let newWords = stage.acknowledged && stage.comeback != comeback
        if !newWords { stage.comeback = comeback }
        if stage.stage < 3 || stage.titleHeld || !stage.symbolIn {
            withAnimation(T.catchUp) { stage.stage = 3; stage.titleHeld = false; stage.symbolIn = true }
        }
        // On screen first (Settings → back: the change lands while iOS still shows the snapshot).
        _ = await CircleStage.shared.until(deadline: T.onScreenDeadline) { CircleStage.shared.sceneActive }
        guard await CircleGate.pause(T.backInAppDuration) else { return }   // back in the app / the city sheet gone
        // Off → on: the words out, changed while they're away, then in with the success (they cross-faded — audit B).
        if !stage.acknowledged || newWords {
            stage.wordsAway = true
            guard await CircleGate.pause(CircleMomentTiming.outDone) else { return }
            // Quietly, while they're out (under an animation the two titles cross-faded back in); the title's measured
            // room eases on its own (`LostStage.measure`).
            quietly {
                stage.acknowledged = true
                stage.comeback = comeback
            }
            guard await CircleGate.nextFrame() else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            stage.wordsAway = false
        }
        guard await CircleGate.pause(comeback == .whileUsing ? T.readLongDuration : T.readDuration) else { return }
        if reduceMotion {
            await CircleMotion.animate(T.reduced) { stage.clearing = true; stage.down = true; stage.landed = true }
            finish()
            return
        }
        // The prayer's track under the ring as it lands: dashed for a prayer that hasn't started (or the next Fajr).
        let dashed: Bool = {
            guard let p = viewModel.relevantPrayer, !(p.status() == .upcoming && p.name == "Fajr") else {
                return sharedState.navPosition != .bottom
            }
            return p.status() == .upcoming
        }()
        // The landing is the circle's moment (audit B): played once it can be seen, snapped to landed by a newer one,
        // landed at once if it can't play in time. The ring becomes the welcome's mark — the same band, in the same
        // place, so nothing changes yet — and the circle's own track waits under it.
        let mark = WelcomeMarkState()
        mark.inCircle = true
        mark.ringDrawn = true
        mark.startDrawn = true
        mark.grow = true
        mark.hidesWords = false   // the symbol stays in the ring
        CircleStage.shared.play(CircleMomentRequest(kind: .comeback, phases: {
            quietly { CircleStage.shared.opening = mark }
            // The words go while the circle glides back to its place and draws in to the starting ring round the symbol.
            withAnimation(T.clear) { stage.clearing = true }
            withAnimation(T.down) { stage.down = true }   // no overshoot
            withAnimation(T.snug) { mark.grow = false }
            guard await CircleGate.pause(T.downDuration) else { return }   // back in place, snug
            guard await CircleGate.pause(T.restDuration) else { return }   // rests, like the welcome before it grows
            mark.dashedTarget = dashed
            withAnimation(Landing.grow) {
                mark.grow = true
                stage.symbolIn = false
            }
            if dashed {
                guard await CircleGate.pause(Landing.toDashesDuration) else { return }
                withAnimation(Landing.dashes) { mark.dashesIn = true }
                guard await CircleGate.pause(Landing.dashesDuration) else { return }
            } else {
                guard await CircleGate.pause(Landing.toBandDuration) else { return }
            }
        }, settle: {
            // Landed (or snapped there): the track is back under the ring, the prayer comes in on it (the circle plays
            // that as the face changes) and the page round it.
            stage.clearing = true
            stage.down = true
            stage.symbolIn = false
            mark.dashedTarget = dashed
            mark.grow = true
            mark.dashesIn = dashed
            mark.landed = true
            stage.landed = true
        }))
        guard await CircleStage.shared.until({ stage.landed }), await CircleGate.pause(T.landedDuration) else { return }
        finish()
    }

    private func finish() {
        quietly {
            if CircleStage.shared.opening?.inCircle == true, CircleStage.shared.opening?.hidesWords == false {
                CircleStage.shared.opening = nil
            }
            CircleStage.shared.lost = nil
        }
        CircleCover.set("lost", false)
        location.clearComeback()
    }
}

// MARK: - The opening (the original welcome's look)

/// The page before the setup's steps (owner, 2026-09-29: "I like the old style for its gradient and the
/// soft movement. Use it for one new page at the start of onboarding, and nowhere else"): the old first
/// screen's moving wavy gradient + grain (GradientAnimationLoad, removed in 9fce309) and its glass
/// circle, one piece at a time — the gradient, the circle, "welcome to shukr", "tap to continue". A tap:
/// the circle and words go, then the gradient drains to the plain page while its waves keep moving, and
/// only then does the first step come in (`onDone`). Shown on a new install and Run setup again; not
/// in `.locationOnly` mode or anywhere else. The white words carry a soft dark shadow (the original's
/// thin white on pale mint was hard to read in light mode).
private struct SetupOpening: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 gradient · 2 circle · 3 words · 4 "tap to continue".
    @State private var stage = 0
    @State private var leaving = false
    @State private var draining = false
    @State private var grain = 0.2

    static let drain: Double = 1.4

    var body: some View {
        ZStack {
            ZStack {
                AnimatedWavyGradient(still: reduceMotion)
                NoiseOverlay()
                    .blendMode(.overlay)
                    .opacity(grain)
            }
            .ignoresSafeArea()
            .opacity(stage >= 1 && !draining ? 1 : 0)

            circle
                .frame(width: 200, height: 200)
                .opacity(stage >= 2 && !leaving ? 1 : 0)
                .scaleEffect(reduceMotion || stage >= 2 ? 1 : 0.94)

            VStack {
                Spacer()
                Text("tap to continue")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    // A dark halo: it sits on the pale mint in light mode, which swallowed plain white.
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    .shadow(color: .black.opacity(0.3), radius: 14)
                    .padding(.bottom, 44)
                    .opacity(stage >= 4 && !leaving ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Welcome to shukr")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { advance() }
        .task { await open() }
    }

    /// The original's glass circle, the words heavier and shadowed so they read on any part of the gradient.
    private var circle: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .background(Circle().stroke(Color(.secondarySystemFill).opacity(0.7), lineWidth: 1))
            .overlay {
                VStack(spacing: 2) {
                    Text("welcome to")
                        .font(.system(.footnote, design: .rounded, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("shukr")
                        .font(.system(.title, design: .rounded, weight: .light))
                        .foregroundStyle(.white.opacity(0.97))
                }
                .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
                .opacity(stage >= 3 ? 1 : 0)
            }
            .shadow(radius: 5)
    }

    private func open() async {
        typealias T = CircleMotion.Setup
        /// One piece in; false once the opening has gone (a tap mid-way: `advance` takes it from there).
        func step(_ n: Int, after seconds: Double, _ animation: Animation) async -> Bool {
            guard await CircleGate.pause(seconds) else { return false }
            withAnimation(animation) { stage = max(stage, n) }
            return true
        }
        // A moment of blank page first.
        guard await step(1, after: T.gradientAfterDuration, reduceMotion ? T.gradientReduced : T.gradient) else { return }
        if !reduceMotion {
            withAnimation(T.grain) { grain = 0.3 }
        }
        guard await step(2, after: reduceMotion ? T.circleAfterReducedDuration : T.circleAfterDuration, T.circleIn),
              await step(3, after: T.wordsAfterDuration, T.wordsIn),
              await step(4, after: T.hintAfterDuration, T.wordsIn) else { return }
        #if DEBUG
        // `-setupOpeningTap <seconds>`: tap by itself that long after "tap to continue" (recordings).
        let auto = UserDefaults.standard.double(forKey: "setupOpeningTap")
        if auto > 0 {
            try? await Task.sleep(for: .seconds(auto))
            advance()
        }
        #endif
    }

    /// The circle, words and hint go; then the gradient drains (still moving); then the steps.
    private func advance() {
        guard stage >= 2, !leaving else { return }
        stage = 4
        triggerSomeVibration(type: .light)
        typealias T = CircleMotion.Setup
        Task { @MainActor in
            await CircleMotion.animate(T.openingAway) { leaving = true }
            await CircleMotion.animate(.easeInOut(duration: reduceMotion ? T.drainReducedDuration : Self.drain)) { draining = true }
            onDone()
        }
    }
}

// MARK: - The ring (progress + the step's symbol)

/// The opening's sage ring, small, at the top of every step: a hairline track, the sage arc filling
/// a fifth per group, the step's symbol inside. `handoff`: it becomes the welcome's ring — 150 pt,
/// a 1.2 pt sage hairline with its soft glow, empty inside.
struct SetupRing: View {
    let progress: Double
    let symbol: String
    var handoff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(Color.sage.opacity(handoff ? 0 : 0.18), lineWidth: 1.2)
                Circle()
                    .trim(from: 0, to: handoff ? 1 : (drawn || reduceMotion ? progress : 0))
                    .stroke(Color.sage.opacity(handoff ? 0.6 : 1),
                            style: StrokeStyle(lineWidth: handoff ? 1.2 : 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.sage.opacity(handoff ? 0.45 : 0), radius: 8)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.sage)
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(handoff ? 0 : 1)
            }
            // Grows inside a fixed frame, so it stays centred where it is.
            .frame(width: handoff ? 150 : 76, height: handoff ? 150 : 76)
            .opacity(handoff && reduceMotion ? 0 : 1)
        }
        .frame(width: 76, height: 76)
        .animation(CircleMotion.Setup.ringGlide, value: handoff)
        .onAppear { withAnimation(CircleMotion.Setup.ringDraw) { drawn = true } }
        .animation(CircleMotion.Setup.ringProgress, value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared pieces

/// A step: its title (same height on every step), a scrolling middle (small screens, big type),
/// and the bottom (the primary button).
private struct StepScaffold<Content: View, Bottom: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    /// After the opening the parts come in one by one (`setupReveal`); otherwise all at once.
    @Environment(\.setupReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    StepTitle(title: title, subtitle: subtitle)
                        .padding(.bottom, 22)
                        .modifier(RevealPart(shown: reveal >= 2, rise: !reduceMotion))
                    content
                        .modifier(RevealPart(shown: reveal >= 3, rise: !reduceMotion))
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            bottom
                .padding(.top, 8)
                .padding(.bottom, 8)
                .modifier(RevealPart(shown: reveal >= 4, rise: !reduceMotion))
        }
    }
}

/// A part of the first step coming in after the opening: fades up from a little below.
private struct RevealPart: ViewModifier {
    let shown: Bool
    let rise: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !rise ? 0 : 10)
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .light))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.callout, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
    }
}

extension EnvironmentValues {
    /// The setup step was opened from the review and goes back to it: "Continue" reads "Done".
    @Entry var setupReturnsToReview = false
    /// How much of the first step has come in after the opening (FirstRunSetupView.reveal).
    @Entry var setupReveal = 4
}

/// The one primary button: the app's calm style (sage text on a soft sage tint, like the pause
/// screen's Resume), not a solid fill.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.setupReturnsToReview) private var returnsToReview
    var body: some View {
        Button(action: action) {
            Text(returnsToReview && title == "Continue" ? "Done" : title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(Capsule().fill(Color.sage.opacity(0.14)))
                .overlay(Capsule().stroke(Color.sage.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .padding(.horizontal, 24)
    }
}

/// A quiet text button under the primary one.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
    }
}

/// The review's (and a step's) gentle, never-blocking note: a line and a link.
struct Nudge: View {
    let text: String
    let action: String
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.caption)
                Text(text).font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(action).font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.sage)
            }
            .foregroundStyle(Color.orange.opacity(0.9))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

enum SettingsLinks {
    static func app() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    static func notifications() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
}

private func whyRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(Color.sage)
            .frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.body, design: .rounded))
            Text(detail).font(.system(.subheadline, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        StepScaffold(title: "Assalamu alaikum",
                     subtitle: "shukr helps you pray on time, keep Allah in mind through the day, and see how you're growing.") {
            VStack(alignment: .leading, spacing: 22) {
                whyRow("circle.dashed", "Your prayers, on time", "Accurate times, a circle that shows how long is left, and a score for each prayer.")
                whyRow("circle.hexagonpath", "Zikr, anywhere", "A tasbeeh that counts with a tap, daily tasks, and your own library of azkar.")
                whyRow("sparkles", "Made for you", "A few quick choices and you're in. Skip any of them.")
            }
            .padding(.horizontal, 32)
        } bottom: {
            PrimaryButton(title: "Begin", action: next)
        }
    }
}

// MARK: - Location

private struct LocationStep: View {
    var locationOnly = false
    let next: () -> Void
    @EnvironmentObject private var location: EnvLocationManager
    @AppStorage("lastCityName", store: UserDefaults(suiteName: SharedStore.appGroup)) private var cityName = ""
    @State private var pickingCity = false

    private var status: CLAuthorizationStatus { location.authorizationStatus }
    private var denied: Bool { status == .denied || status == .restricted }
    private var ready: Bool { location.isAuthorized || location.hasManualLocation }

    var body: some View {
        StepScaffold(title: "Where do you pray?",
                     subtitle: locationOnly ? "shukr needs a location for your prayer times."
                                            : "shukr works out your prayer times from where you are.") {
            VStack(alignment: .leading, spacing: 22) {
                whyRow("clock", "Accurate times, wherever you are",
                       "With Always, they follow you when you travel. No city to update.")
                whyRow("mappin.and.ellipse", "Your prayers, pinned where you prayed",
                       "Even the ones you mark from the widget, a notification or your watch.")
                whyRow("lock", "It stays on your phone", "No account, nothing sent anywhere.")
            }
            .padding(.horizontal, 32)
            statusLine
                .padding(.top, 26)
                .padding(.horizontal, 28)
        } bottom: {
            VStack(spacing: 0) {
                if status == .notDetermined && !location.hasManualLocation {
                    Text("iOS asks “While Using” first. Choose “Always” when it offers, so your times follow you.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 14)
                }
                PrimaryButton(title: primaryTitle, action: primary)
                if !ready || denied {
                    SecondaryButton(title: denied ? "Open Settings" : "Enter a city instead") {
                        if denied { SettingsLinks.app() } else { pickingCity = true }
                    }
                } else if status == .authorizedWhenInUse {
                    SecondaryButton(title: FirstRunSetup.alwaysAsked ? "Turn on “Always” in Settings" : "Allow “Always”") {
                        LocationUpgrade.askForAlways(location)
                    }
                }
            }
        }
        .sheet(isPresented: $pickingCity) {
            CityPickerSheet(onPicked: { pickingCity = false })
        }
        // Apple's way to Always (owner: ask for it here): When In Use first, then — right after it's
        // granted — the one-time upgrade prompt. (Asking Always straight away from "not decided" only
        // gives a provisional While Using, and the upgrade offer may never come.)
        .onChange(of: location.authorizationStatus) { old, new in
            if old == .notDetermined && new == .authorizedWhenInUse && !FirstRunSetup.alwaysAsked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { LocationUpgrade.askForAlways(location) }
            }
        }
    }

    private var primaryTitle: String {
        if denied && !location.hasManualLocation { return "Enter a city" }
        if status == .notDetermined && !location.hasManualLocation { return "Allow location" }
        return locationOnly ? "Done" : "Continue"
    }

    private func primary() {
        if denied && !location.hasManualLocation { pickingCity = true; return }
        if status == .notDetermined && !location.hasManualLocation { location.requestLocationPermission(); return }
        if !locationOnly { next() }
    }

    @ViewBuilder private var statusLine: some View {
        let text: String? = {
            switch status {
            case .authorizedAlways: return "Location: Always\(cityName.isEmpty ? "" : " · \(cityName)")"
            case .authorizedWhenInUse: return "Location: While Using\(cityName.isEmpty ? "" : " · \(cityName)")"
            default: return location.hasManualLocation ? "Using \(cityName.isEmpty ? "the city you picked" : cityName)" : nil
            }
        }()
        if let text {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity)
        } else if denied {
            Text("Location is off for shukr. Turn it on in Settings, or pick a city.")
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The Always upgrade: iOS shows its prompt once (from While Using); after that only Settings can.
enum LocationUpgrade {
    @MainActor static func askForAlways(_ location: EnvLocationManager) {
        if FirstRunSetup.alwaysAsked {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } else {
            FirstRunSetup.alwaysAsked = true
            location.requestAlwaysPermission()
        }
    }
}

// MARK: - Method

/// The picker's rows: Automatic first, then the most used, then the rest (a scroll away).
private let methodRows: [(tag: Int, title: String, region: String)] = [
    (0, "Automatic", ""),
    (2, "ISNA", "North America"),
    (3, "Muslim World League", "Europe, the Far East"),
    (4, "Umm al-Qura", "Saudi Arabia"),
    (1, "Karachi", "Pakistan, India, Bangladesh"),
    (5, "Egyptian", "Africa, the Levant"),
    (8, "Gulf (Dubai)", "United Arab Emirates, Oman"),
    (9, "Kuwait", "Kuwait"),
    (10, "Qatar", "Qatar"),
    (11, "Singapore", "Singapore, Malaysia, Indonesia"),
    (13, "Diyanet", "Turkey"),
    (7, "Tehran", "Iran"),
    (12, "UOIF", "France"),
    (14, "Muslims of Russia", "Russia"),
]

/// Today's times for the saved location with a given method / school (for the live strip).
private func todaysTimes(method: Int, school: Int) -> PrayerTimes? {
    guard let coords = try? PrayerUtils.getUserCoordinates() else { return nil }
    let resolved = method == AutoMethod.automatic ? AutoMethod.resolved() : method
    return try? PrayerUtils.getPrayerTimes(for: Date(), coordinates: coords,
                                           params: PrayerUtils.parameters(method: resolved, school: school))
}

private func clockTime(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }

private struct MethodStep: View {
    let next: () -> Void
    @EnvironmentObject private var viewModel: PrayerViewModel
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: SharedStore.appGroup)) private var method = AutoMethod.automatic
    @AppStorage("school", store: UserDefaults(suiteName: SharedStore.appGroup)) private var school = 0

    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "Your calculation method",
                      subtitle: "Picked for where you are. Match your masjid if its times differ.")
                .padding(.bottom, 16)
            // A short scroller: the popular ones show, the rest are a scroll away (the fade says so).
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(methodRows, id: \.tag) { row in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { method = row.tag }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.system(.body, design: .rounded))
                                    Text(row.tag == 0 ? "Follows where you are · \(AutoMethod.shortName(AutoMethod.resolved())) here" : row.region)
                                        .font(.system(.footnote, design: .rounded, weight: .light))
                                        .foregroundStyle(row.tag == 0 ? Color.sage : .secondary)
                                }
                                Spacer()
                                Image(systemName: method == row.tag ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(method == row.tag ? Color.sage : Color.secondary.opacity(0.4))
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(method == row.tag ? .isSelected : [])
                        if row.tag != methodRows.last?.tag { Divider() }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 36)
                }
            }
            TodayStrip(method: method, school: school)
                .padding(.top, 8)
                .padding(.bottom, 16)
            PrimaryButton(title: "Continue", action: next)
                .padding(.bottom, 8)
        }
        .onChange(of: method) { _, _ in
            viewModel.fetchPrayerTimes(cameFrom: "setup method")
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.send()
        }
    }
}

/// Today's five times, updating live as the method / madhab change.
private struct TodayStrip: View {
    let method: Int
    let school: Int
    var highlightAsr = false

    var body: some View {
        if let t = todaysTimes(method: method, school: school) {
            VStack(spacing: 8) {
                Text("today").font(.caption).tracking(2).textCase(.uppercase).foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    cell("Fajr", t.fajr)
                    cell("Dhuhr", t.dhuhr)
                    cell("Asr", t.asr, strong: highlightAsr)
                    cell("Maghrib", t.maghrib)
                    cell("Isha", t.isha)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func cell(_ name: String, _ date: Date, strong: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.system(.caption, design: .rounded))
                .foregroundStyle(strong ? Color.sage : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(clockTime(date))
                .font(.system(.subheadline, design: .rounded, weight: strong ? .medium : .light))
                .monospacedDigit()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .contentTransition(.numericText())
                .foregroundStyle(strong ? Color.sage : .primary)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: date)
    }
}

// MARK: - Madhab

private struct MadhabStep: View {
    let next: () -> Void
    @EnvironmentObject private var viewModel: PrayerViewModel
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: SharedStore.appGroup)) private var method = AutoMethod.automatic
    @AppStorage("school", store: UserDefaults(suiteName: SharedStore.appGroup)) private var school = 0

    var body: some View {
        let shafiAsr = todaysTimes(method: method, school: 0)?.asr
        let hanafiAsr = todaysTimes(method: method, school: 1)?.asr
        let gap = (shafiAsr != nil && hanafiAsr != nil) ? Int(hanafiAsr!.timeIntervalSince(shafiAsr!) / 60) : nil
        StepScaffold(title: "When does Asr begin?",
                     subtitle: "The madhab only changes Asr. The other four prayers stay the same.") {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    card(title: "Shafi'i", note: "Maliki, Hanbali too", rule: "when a shadow is as long as the object",
                         lengths: 1, asr: shafiAsr, selected: school != 1) { school = 0 }
                    card(title: "Hanafi", note: nil, rule: "when a shadow is twice the object's length",
                         lengths: 2, asr: hanafiAsr, selected: school == 1) { school = 1 }
                }
                .padding(.horizontal, 24)
                if let gap {
                    Text("Hanafi Asr is \(gap) min later today.")
                        .font(.system(.subheadline, design: .rounded, weight: .light))
                        .foregroundStyle(.secondary)
                        .padding(.top, 18)
                }
                Text("Not sure? Go with what your masjid uses.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
                TodayStrip(method: method, school: school, highlightAsr: true)
                    .padding(.top, 26)
            }
        } bottom: {
            PrimaryButton(title: "Continue", action: next)
        }
        .onChange(of: school) { _, _ in
            viewModel.fetchPrayerTimes(cameFrom: "setup school")
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.send()
        }
    }

    private func card(title: String, note: String?, rule: String, lengths: CGFloat, asr: Date?,
                      selected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { pick() }
        } label: {
            VStack(spacing: 12) {
                ShadowSketch(lengths: lengths)
                    .frame(height: 64)
                VStack(spacing: 2) {
                    Text(title).font(.system(.title3, design: .rounded))
                    Text(note ?? " ").font(.caption).foregroundStyle(.tertiary)
                }
                Text(asr.map { "Asr \(clockTime($0))" } ?? "Asr")
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.sage : .primary)
                Text(rule)
                    .font(.system(.footnote, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(selected ? Color.sage.opacity(0.10) : Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.sage.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A post and its afternoon shadow: one length (Shafi'i) or two (Hanafi), with the sun.
private struct ShadowSketch: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            // The same scale in both cards, so the shadows compare: room for two lengths.
            let unit = min(size.height * 0.6, (size.width - 40) / 2.2)
            let groundY = size.height - 4
            let postX: CGFloat = 32
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 6, y: groundY)); p.addLine(to: CGPoint(x: size.width - 6, y: groundY)) },
                       with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX + unit * lengths, y: groundY)) },
                       with: .color(Color.sage.opacity(0.8)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX, y: groundY - unit)) },
                       with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // The sun behind the post, lower when the shadow is longer (later in the afternoon).
            let sunY = groundY - unit * (lengths == 1 ? 1.1 : 0.62)
            ctx.fill(Path(ellipseIn: CGRect(x: 8, y: sunY - 6, width: 12, height: 12)), with: .color(.orange.opacity(0.75)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Appearance

private struct AppearanceStep: View {
    let next: () -> Void
    /// 0 light, 1 dark, 2 auto (follows the sun: light from Fajr, dark after Maghrib). Applied live by
    /// the app root's preferredColorScheme.
    @AppStorage("modeToggleNew") private var mode = 0

    var body: some View {
        StepScaffold(title: "Light or dark?",
                     subtitle: "Auto follows the sun: light from Fajr, dark after Maghrib.") {
            HStack(spacing: 14) {
                ForEach([(0, "Light"), (1, "Dark"), (2, "Auto")], id: \.0) { tag, title in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { mode = tag }
                    } label: {
                        VStack(spacing: 10) {
                            AppearanceSwatch(tag: tag)
                                .frame(height: 150)
                                .overlay(RoundedRectangle(cornerRadius: 18)
                                    .stroke(mode == tag ? Color.sage : Color.secondary.opacity(0.25),
                                            lineWidth: mode == tag ? 2 : 1))
                            Text(title).font(.system(.body, design: .rounded))
                            Text(tag == 2 ? "Recommended" : " ")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.sage)
                            Image(systemName: mode == tag ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(mode == tag ? Color.sage : Color.secondary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tag == 2 ? "Auto, recommended" : title)
                    .accessibilityAddTraits(mode == tag ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
        } bottom: {
            PrimaryButton(title: "Continue", action: next)
        }
    }
}

/// A tiny Salah page: the circle on the page's colour. Auto is split light / dark with the sun and
/// the moon.
private struct AppearanceSwatch: View {
    let tag: Int
    var body: some View {
        ZStack {
            switch tag {
            case 0: page(.white, ink: .black)
            case 1: page(.black, ink: .white)
            default:
                ZStack {
                    page(.white, ink: .black)
                    page(.black, ink: .white)
                        .mask(Rectangle().rotationEffect(.degrees(28)).offset(x: 46).scaleEffect(2))
                }
                VStack {
                    HStack {
                        Image(systemName: "sun.max").foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "moon").foregroundStyle(.white.opacity(0.85))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(8)
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityHidden(true)
    }

    private func page(_ bg: Color, ink: Color) -> some View {
        ZStack {
            bg
            Circle().stroke(ink.opacity(0.14), lineWidth: 5).frame(width: 58, height: 58)
            Circle().trim(from: 0, to: 0.62).stroke(Color.sage, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 58, height: 58)
            Capsule().fill(ink.opacity(0.55)).frame(width: 26, height: 4)
        }
    }
}

// MARK: - Reminders


private struct RemindersStep: View {
    let next: () -> Void
    @ObservedObject private var notifications = NotificationStatus.shared
    // The same keys and the same control as Settings: one button per prayer cycling off → start →
    // nudge (`prayerCol`; owner, 2026-09-28: "it should follow the same toggling logic we have in
    // the settings" — the first version's two independent columns allowed states Settings can't).
    @AppStorage("fajrNotif") private var fajrNotif = NotificationDefaults.notify("Fajr")
    @AppStorage("dhuhrNotif") private var dhuhrNotif = NotificationDefaults.notify("Dhuhr")
    @AppStorage("asrNotif") private var asrNotif = NotificationDefaults.notify("Asr")
    @AppStorage("maghribNotif") private var maghribNotif = NotificationDefaults.notify("Maghrib")
    @AppStorage("ishaNotif") private var ishaNotif = NotificationDefaults.notify("Isha")
    @AppStorage("fajrNudges") private var fajrNudges = NotificationDefaults.nudges("Fajr")
    @AppStorage("dhuhrNudges") private var dhuhrNudges = NotificationDefaults.nudges("Dhuhr")
    @AppStorage("asrNudges") private var asrNudges = NotificationDefaults.nudges("Asr")
    @AppStorage("maghribNudges") private var maghribNudges = NotificationDefaults.nudges("Maghrib")
    @AppStorage("ishaNudges") private var ishaNudges = NotificationDefaults.nudges("Isha")

    var body: some View {
        StepScaffold(title: "Reminders that help",
                     subtitle: "Not just at the start: if you haven't marked it yet, a nudge 30 min in and with 30 min left.") {
            VStack(spacing: 18) {
                if notifications.isOn == false {
                    Nudge(text: "Notifications are off for shukr, so reminders can't reach you.",
                          action: "Turn on", tap: SettingsLinks.notifications)
                        .padding(.horizontal, 24)
                }
                HStack(spacing: 4) {
                    prayerCol(prayerName: "Fajr", notifIsOn: $fajrNotif, nudgeIsOn: $fajrNudges, accent: .sage)
                    prayerCol(prayerName: "Dhuhr", notifIsOn: $dhuhrNotif, nudgeIsOn: $dhuhrNudges, accent: .sage)
                    prayerCol(prayerName: "Asr", notifIsOn: $asrNotif, nudgeIsOn: $asrNudges, accent: .sage)
                    prayerCol(prayerName: "Maghrib", notifIsOn: $maghribNotif, nudgeIsOn: $maghribNudges, accent: .sage)
                    prayerCol(prayerName: "Isha", notifIsOn: $ishaNotif, nudgeIsOn: $ishaNudges, accent: .sage)
                }
                .frame(height: 76)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 24)
                // The legend, one line each: what the three states send.
                VStack(alignment: .leading, spacing: 6) {
                    legend("bell.slash.fill", "off", "no notification")
                    legend("bell.fill", "start", "when the prayer begins")
                    legend("bell.badge.fill", "nudge", "also 30 min in and with 30 min left, if it isn't marked")
                }
                .padding(.horizontal, 32)
                Text("Tap a bell to change it. “I already prayed” on a notification marks the prayer.")
                    .font(.system(.footnote, design: .rounded, weight: .light))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } bottom: {
            if notifications.isOn == nil {
                PrimaryButton(title: "Allow notifications") { notifications.request() }
                SecondaryButton(title: "Not now", action: next)
            } else {
                PrimaryButton(title: "Continue", action: next)
            }
        }
        .task { await notifications.refresh() }
    }

    private func legend(_ symbol: String, _ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Color.sage).frame(width: 18)
            (Text(name).fontWeight(.medium) + Text("  \(text)").foregroundStyle(.secondary))
                .font(.system(.footnote, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Fajr alarm

private struct FajrStep: View {
    let next: () -> Void
    // The Fajr alarm's own settings (Settings → Alarm Settings).
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: SharedStore.appGroup)) private var enabled = false
    @AppStorage("alarmOffsetMinutes", store: UserDefaults(suiteName: SharedStore.appGroup)) private var offset = 0
    @AppStorage("alarmIsBefore", store: UserDefaults(suiteName: SharedStore.appGroup)) private var isBefore = true
    @AppStorage("alarmIsFajr", store: UserDefaults(suiteName: SharedStore.appGroup)) private var isFajr = true
    @AppStorage("alarmTimeSetFor", store: UserDefaults(suiteName: SharedStore.appGroup)) private var timeSetFor = ""
    @AppStorage("alarmDescription", store: UserDefaults(suiteName: SharedStore.appGroup)) private var alarmDescription = ""
    @AppStorage("didShowAlarmSetupAlert") private var didShowShortcut = false

    private static let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/6ebcfeb12813483992687461d027fd14")

    var body: some View {
        StepScaffold(title: "Wake up for Fajr",
                     subtitle: "A real alarm from a rule you set once. It follows Fajr all year, so you never reset it.") {
            VStack(spacing: 18) {
                Toggle(isOn: $enabled.animation(.snappy)) {
                    Label("Daily Fajr alarm", systemImage: "alarm")
                        .font(.system(.body, design: .rounded))
                }
                .tint(Color.sage)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                if enabled {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            Picker("Minutes", selection: $offset) {
                                ForEach(Array(stride(from: 0, through: 60, by: 5)), id: \.self) { Text("\($0) min").tag($0) }
                            }
                            Picker("Before or after", selection: $isBefore) {
                                Text("before").tag(true)
                                if isFajr { Text("after").tag(false) }
                            }
                            // The start / end of Fajr (owner, 2026-09-28; stored as alarmIsFajr true / false).
                            Picker("Start or end of Fajr", selection: $isFajr) {
                                Text("Start").tag(true)
                                if isBefore { Text("End").tag(false) }
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .clipped()
                        // Just the result, backed by the time it's worked from (owner: the wheels already
                        // say the rule) — like Settings' "is 5:24 AM (Fajr starts 5:34 AM)".
                        // The result big, the Fajr time under it as the proof (owner, 2026-09-29).
                        if let next = nextAlarm {
                            VStack(spacing: 2) {
                                Text("Alarm tomorrow \(clockTime(next.alarm))")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.sage)
                                Text("Fajr \(isFajr ? "starts" : "ends") \(clockTime(next.reference))")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if FajrAlarms.supported {
                        // iOS 26.1+: shukr sets real alarms itself (Continue asks once).
                        Text("shukr sets a real alarm for each day, ringing even on silent. You'll be asked to allow alarms.")
                            .font(.system(.footnote, design: .rounded, weight: .light))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        VStack(spacing: 8) {
                            Text("shukr sets the alarm through a Shortcut you add once.")
                                .font(.system(.footnote, design: .rounded, weight: .light))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Get the Shortcut") {
                                didShowShortcut = true
                                if let url = Self.shortcutURL { UIApplication.shared.open(url) }
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.sage)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        } bottom: {
            PrimaryButton(title: "Continue") {
                saveDescription()
                // iOS 26.1+: ask for alarms and set them now; refused → the switch goes off.
                if enabled && FajrAlarms.supported {
                    Task { @MainActor in
                        if !(await FajrAlarms.enable()) { enabled = false }
                        next()
                    }
                } else {
                    next()
                }
            }
        }
        .onAppear {
            if offset % 5 != 0 { offset = min(60, Int((Double(offset) / 5).rounded()) * 5) }   // 5-minute steps
        }
    }

    /// Tomorrow's alarm from the rule, and the start / end of Fajr it's worked from.
    private var nextAlarm: (alarm: Date, reference: Date)? {
        guard let coords = try? PrayerUtils.getUserCoordinates(),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()),
              let t = try? PrayerUtils.getPrayerTimes(for: tomorrow, coordinates: coords, params: PrayerUtils.getCalculationParameters())
        else { return nil }
        let ref = isFajr ? t.fajr : t.sunrise
        return (ref.addingTimeInterval(Double(offset * 60) * (isBefore ? -1 : 1)), ref)
    }

    /// What Settings' Save writes, so its row reads right.
    private func saveDescription() {
        guard enabled, let calc = try? PrayerUtils.calculateAlarmDescription() else { return }
        timeSetFor = shortTimePM(calc.time)
        alarmDescription = calc.description
    }
}

// MARK: - Your masjid

private struct MasjidStep: View {
    let next: () -> Void
    @EnvironmentObject private var location: EnvLocationManager
    @AppStorage(MasjidArrival.enabledKey) private var duas = false
    @State private var found: [MKMapItem] = []
    @State private var searching = true
    @State private var favourites = Set(MosqueFavorites.all.map(\.id))

    var body: some View {
        StepScaffold(title: "Your masjid",
                     subtitle: "Star the one you pray at. shukr can show a dua when you arrive and when you leave.") {
            VStack(spacing: 18) {
                list
                Toggle(isOn: Binding(get: { duas }, set: { MasjidArrival.shared.setEnabled($0) ; duas = $0 })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Duas when I arrive and leave", systemImage: "hands.and.sparkles")
                            .font(.system(.body, design: .rounded))
                        Text("Asks for Always location. It stays on your phone.")
                            .font(.system(.footnote, design: .rounded, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Color.sage)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
            }
            .padding(.horizontal, 24)
        } bottom: {
            PrimaryButton(title: "Continue", action: next)
        }
        .task { await search() }
    }

    @ViewBuilder private var list: some View {
        if searching {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding masajid near you…").font(.system(.subheadline, design: .rounded, weight: .light))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
        } else if found.isEmpty {
            Text(MosqueSearch.lastSearchFailed ? "Couldn't search right now. You can star your masjid on the map later."
                                               : "No masajid found nearby. You can star one on the map later.")
                .font(.system(.subheadline, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(found.prefix(6).enumerated()), id: \.offset) { i, item in
                    let id = MosqueHiding.id(item)
                    Button {
                        let on = !favourites.contains(id)
                        MosqueFavorites.setFavorite(item, on)
                        withAnimation(.snappy(duration: 0.2)) {
                            if on { favourites.insert(id) } else { favourites.remove(id) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Mosque").font(.system(.body, design: .rounded)).lineLimit(2)
                                if let d = distance(item) {
                                    Text(d).font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: favourites.contains(id) ? "star.fill" : "star")
                                .font(.system(size: 19, weight: .light))
                                .foregroundStyle(favourites.contains(id) ? Color.sage : Color.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(favourites.contains(id) ? .isSelected : [])
                    if i < min(found.count, 6) - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
        }
    }

    private func distance(_ item: MKMapItem) -> String? {
        guard let here = location.effectiveLocation else { return nil }
        let c = item.placemark.coordinate
        let metres = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private func search() async {
        guard let here = location.effectiveLocation else { searching = false; return }
        let region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
        let results = MosqueFavorites.merged(await MosqueSearch.find(in: region), in: region)
            .filter { !MosqueHiding.isHidden($0) }
        let sorted = results.sorted {
            let a = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
            let b = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
            return a.distance(from: here) < b.distance(from: here)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            found = sorted
            searching = false
        }
    }
}

// MARK: - Review

private struct ReviewStep: View {
    let jump: (SetupStep) -> Void
    let done: () -> Void
    @EnvironmentObject private var location: EnvLocationManager
    @ObservedObject private var notifications = NotificationStatus.shared
    @ObservedObject private var health = NotificationHealth.shared
    @AppStorage("lastCityName", store: UserDefaults(suiteName: SharedStore.appGroup)) private var cityName = ""
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: SharedStore.appGroup)) private var method = AutoMethod.automatic
    @AppStorage("school", store: UserDefaults(suiteName: SharedStore.appGroup)) private var school = 0
    @AppStorage("modeToggleNew") private var mode = 0
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: SharedStore.appGroup)) private var alarmOn = false
    @AppStorage("alarmOffsetMinutes", store: UserDefaults(suiteName: SharedStore.appGroup)) private var alarmOffset = 0
    @AppStorage("alarmIsBefore", store: UserDefaults(suiteName: SharedStore.appGroup)) private var alarmBefore = true
    @AppStorage("alarmIsFajr", store: UserDefaults(suiteName: SharedStore.appGroup)) private var alarmFajr = true
    @AppStorage(MasjidArrival.enabledKey) private var duas = false
    @AppStorage("fajrNotif") private var fajrNotif = NotificationDefaults.notify("Fajr")
    @AppStorage("dhuhrNotif") private var dhuhrNotif = NotificationDefaults.notify("Dhuhr")
    @AppStorage("asrNotif") private var asrNotif = NotificationDefaults.notify("Asr")
    @AppStorage("maghribNotif") private var maghribNotif = NotificationDefaults.notify("Maghrib")
    @AppStorage("ishaNotif") private var ishaNotif = NotificationDefaults.notify("Isha")
    @AppStorage("fajrNudges") private var fajrNudges = NotificationDefaults.nudges("Fajr")
    @AppStorage("dhuhrNudges") private var dhuhrNudges = NotificationDefaults.nudges("Dhuhr")
    @AppStorage("asrNudges") private var asrNudges = NotificationDefaults.nudges("Asr")
    @AppStorage("maghribNudges") private var maghribNudges = NotificationDefaults.nudges("Maghrib")
    @AppStorage("ishaNudges") private var ishaNudges = NotificationDefaults.nudges("Isha")

    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "You're all set",
                      subtitle: "Tap anything to change it. It's all in Settings later, too.")
                .padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    row("location.fill", "Location", locationValue, step: .location) { locationNudge }
                    divider
                    row("clock", "Prayer times", methodValue, step: .method)
                    divider
                    row("circle.lefthalf.filled", "Appearance", ["Light", "Dark", "Auto · follows the sun"][min(max(mode, 0), 2)], step: .appearance)
                    divider
                    row("bell", "Reminders", remindersValue, step: .reminders,
                        sell: "Not just at the start: if it isn't marked yet, a nudge 30 min in and with 30 min left.") { notificationsNudge }
                    divider
                    row("alarm", "Fajr alarm", alarmValue, step: .fajr,
                        sell: "A real alarm from a rule you set once. It follows Fajr all year.")
                    divider
                    row("building.columns", "Your masjid", masjidValue, step: .masjid,
                        sell: "A dua when you arrive and when you leave.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            BismillahCapsule(action: done)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .task {
            await notifications.refresh()
            await health.refresh()
        }
    }

    private var divider: some View { Divider().padding(.leading, 44) }

    // MARK: values

    private var locationValue: String {
        let place = cityName.isEmpty ? "" : "\(cityName) · "
        switch location.authorizationStatus {
        case .authorizedAlways: return place + "Always"
        case .authorizedWhenInUse: return place + "While Using"
        default: return location.hasManualLocation ? "\(cityName.isEmpty ? "A city you picked" : cityName)" : "Not set"
        }
    }
    private var methodValue: String {
        let m = method == AutoMethod.automatic ? "Automatic (\(AutoMethod.shortName(AutoMethod.resolved())))" : AutoMethod.shortName(method)
        return "\(m) · \(school == 1 ? "Hanafi" : "Shafi'i")"
    }
    /// Settings' three states per prayer: off, start, nudge (nudge = start + the two nudges).
    private var remindersValue: String {
        let states = zip([fajrNotif, dhuhrNotif, asrNotif, maghribNotif, ishaNotif],
                         [fajrNudges, dhuhrNudges, asrNudges, maghribNudges, ishaNudges]).map { $0 ? ($1 ? 2 : 1) : 0 }
        let nudge = states.filter { $0 == 2 }.count, start = states.filter { $0 == 1 }.count, off = states.filter { $0 == 0 }.count
        if off == 5 { return "Off" }
        if nudge == 5 { return "All five, with nudges" }
        if start == 5 { return "All five, at the start" }
        return [nudge > 0 ? "nudges for \(nudge)" : nil, start > 0 ? "start for \(start)" : nil, off > 0 ? "off for \(off)" : nil]
            .compactMap { $0 }.joined(separator: " · ").capitalizedFirst
    }
    private var alarmValue: String {
        guard alarmOn else { return "Off" }
        return PrayerUtils.alarmRuleText(offset: alarmOffset, isBefore: alarmBefore, isStart: alarmFajr)
    }
    private var masjidValue: String {
        let names = MosqueFavorites.all.map(\.name)
        let place = names.isEmpty ? "None starred yet" : names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
        return place + (duas ? " · arrival duas on" : "")
    }

    // MARK: nudges (gentle, never blocking)

    @ViewBuilder private var locationNudge: some View {
        if !location.isAuthorized && !location.hasManualLocation {
            Nudge(text: "Prayer times need a location.", action: "Set up") { jump(.location) }
        } else if !location.isAuthorized {
            Nudge(text: "Allow location so your times follow you when you travel.", action: "Turn on", tap: SettingsLinks.app)
        } else if location.authorizationStatus == .authorizedWhenInUse {
            Nudge(text: "Turn on Always so your times follow you when you travel.", action: "Turn on") {
                LocationUpgrade.askForAlways(location)
            }
        } else if location.isAuthorized && location.manager.accuracyAuthorization == .reducedAccuracy {
            Nudge(text: "Precise Location is off: times can be a few minutes out.", action: "Turn on", tap: SettingsLinks.app)
        }
    }
    /// The same checks as Settings' status (NotificationHealth): off, not asked, held for the
    /// Scheduled Summary, Time Sensitive off.
    @ViewBuilder private var notificationsNudge: some View {
        let issues = health.issues
        switch notifications.isOn {
        case .some(false):
            Nudge(text: "Notifications are off, so reminders can't reach you.", action: "Turn on", tap: SettingsLinks.notifications)
        case .none:
            Nudge(text: "Reminders need notifications.", action: "Allow") { notifications.request() }
        default:
            if issues.contains(.held) {
                Nudge(text: "They're held for the Scheduled Summary and may arrive late. Turn on Time Sensitive.", action: "Fix", tap: SettingsLinks.notifications)
            } else if issues.contains(.timeSensitiveOff) {
                Nudge(text: "Time Sensitive is off, so Focus modes may hold them back.", action: "Settings", tap: SettingsLinks.notifications)
            }
        }
    }

    private func row<N: View>(_ symbol: String, _ title: String, _ value: String, step: SetupStep, sell: String? = nil,
                              @ViewBuilder nudge: () -> N = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { jump(step) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.sage)
                        .frame(width: 30, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title).font(.system(.body, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.medium)).foregroundStyle(.tertiary)
                        }
                        Text(value).font(.system(.subheadline, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                        if let sell {
                            Text(sell).font(.system(.footnote, design: .rounded, weight: .light)).italic()
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            nudge().padding(.leading, 44)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Bismillah

/// The owner's pick: the capsule, with the old first screen borrowed whole — its slowly moving
/// green / black gradient and breathing grain (`AnimatedWavyGradient` + `NoiseOverlay`) — and
/// "bismillah" in the type that screen wrote "shukr" in (title, thin, rounded, white 0.8).
private struct BismillahCapsule: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noiseOpacity: Double = 0.2

    var body: some View {
        Button(action: action) {
            Text("bismillah")
                .font(.title)
                .fontWeight(.thin)
                .fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 68)
                .background {
                    // The screen-sized gradient seen through the capsule (it was drawn for a full
                    // screen; its radii are in points). A background, so it can't widen the layout.
                    ZStack {
                        AnimatedWavyGradient()
                            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height * 0.5)
                        NoiseOverlay()
                            .blendMode(.overlay)
                            .opacity(noiseOpacity)
                    }
                }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(.secondarySystemFill).opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { noiseOpacity = 0.3 }
        }
        .accessibilityLabel("Bismillah, begin")
    }
}

extension CircleMotion {
    /// The lost page (LostPageLayer): going in — on a launch under the welcome, or while the app is open — and the
    /// comeback. Its landing is the opening's (`CircleMotion.Opening`).
    enum Lost {
        /// A launch: the welcome is up by then.
        static let launchSettleDuration: Double = 0.06
        /// Coming back from Settings: how long to wait for the app to be on screen before going on anyway.
        static let onScreenDeadline: Double = 3
        /// Reduce Motion: the page and the comeback, a fade.
        static let reduced = Animation.easeInOut(duration: 0.5)

        // Under the welcome
        static let afterWelcomeDuration: Double = 0.15
        static let titleIn = Animation.easeOut(duration: 0.5)
        static let titleDuration: Double = 0.75
        /// The circle rising to the lost page's place (on a launch and while open); the Salah page animates it itself.
        static let rise = Animation.spring(response: 0.75, dampingFraction: 0.9)
        static let riseDuration: Double = 0.45
        /// The reasons and the buttons.
        static let restIn = Animation.easeOut(duration: 0.5)

        // While the app is open
        static let warmSettleDuration: Double = 0.25
        /// The page round the circle and its prayer going.
        static let pageAwayDuration: Double = 0.6
        static let symbolIn = Animation.easeOut(duration: 0.4).delay(0.08)
        static let warmRiseDuration: Double = 0.55
        static let titleAfterRiseDuration: Double = 0.45

        // The comeback
        /// A comeback before the page had finished going in: the rest of it at once.
        static let catchUp = Animation.easeOut(duration: 0.3)
        static let backInAppDuration: Double = 0.45
        /// A measured room changing once the page is up (the title saying location's back is taller).
        static let room = Animation.snappy(duration: 0.45)
        /// Time to read "Location's back" (longer for "Choose Always in Settings…").
        static let readDuration: Double = 1.5
        static let readLongDuration: Double = 2
        /// The words go while the circle glides back down and draws in snug round the symbol.
        static let clear = Animation.easeOut(duration: 0.3)
        static let down = Animation.spring(response: 0.7, dampingFraction: 1)
        static let snug = Animation.easeInOut(duration: 0.6)
        static let downDuration: Double = 0.75
        static let restDuration: Double = 0.35
        static let landedDuration: Double = 0.6
    }
}

extension CircleMotion {
    /// The first-run setup: its opening page, the first step coming in, and Bismillah's hand-off to the welcome.
    enum Setup {
        // The opening page (the gradient, the glass circle, "welcome to shukr", "tap to continue")
        static let gradientAfterDuration: Double = 0.6
        static let gradient = Animation.easeInOut(duration: 1.4)
        static let gradientReduced = Animation.easeInOut(duration: 0.6)
        static let grain = Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)
        static let circleAfterDuration: Double = 1.1
        static let circleAfterReducedDuration: Double = 0.5
        static let circleIn = Animation.easeOut(duration: 0.8)
        static let wordsAfterDuration: Double = 0.6
        static let hintAfterDuration: Double = 0.8
        static let wordsIn = Animation.easeOut(duration: 0.7)
        /// A tap: the circle and words go, then the gradient drains (`SetupOpening.drain`).
        static let openingAway = Animation.easeOut(duration: 0.45)
        static let drainReducedDuration: Double = 0.6
        // The first step coming in: the ring, the title, the rows, then Begin.
        static let revealStartDuration: Double = 0.05
        static let reveal = Animation.easeOut(duration: 0.55)
        static let revealReduced = Animation.easeOut(duration: 0.3)
        static let revealBeatDuration: Double = 0.35
        static let revealBeatReducedDuration: Double = 0.15
        // Bismillah
        static let leaving = Animation.easeOut(duration: 0.35)
        static let leavingReduced = Animation.easeInOut(duration: 0.35)
        /// SetupRing gliding onto the circle and growing round the word; it has arrived by `ringGlideDuration`.
        static let ringGlide = Animation.spring(response: 0.8, dampingFraction: 0.9)
        static let ringGlideDuration: Double = 0.95
        /// SetupRing drawing itself in, and its progress round the steps.
        static let ringDraw = Animation.easeInOut(duration: 0.9).delay(0.15)
        static let ringProgress = Animation.easeInOut(duration: 0.7)
        /// One step of the setup to the next.
        static let step = Animation.smooth(duration: 0.45)
        static let stepReduced = Animation.easeInOut(duration: 0.2)
    }
}
