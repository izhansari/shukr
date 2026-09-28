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
//  - reminders: `<prayer>Notif` (at the start) + `<prayer>Nudges` (halfway and 30 min left);
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

    init(mode: Mode = .full, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish
        var start: SetupStep = mode == .locationOnly ? .location : .welcome
        #if DEBUG
        if mode == .full, let raw = UserDefaults.standard.string(forKey: "setupStep"), let s = SetupStep(rawValue: raw) { start = s }
        #endif
        _step = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            // Gone once the welcome takes over (it has its own background).
            Color(.systemBackground).ignoresSafeArea()
                .opacity(welcome ? 0 : 1)
            VStack(spacing: 0) {
                topBar
                    .opacity(leaving ? 0 : 1)
                SetupRing(progress: step.progress, symbol: step.symbol, handoff: leaving)
                    .onGeometryChange(for: CGPoint.self) { geo in
                        let f = geo.frame(in: .global); return CGPoint(x: f.midX, y: f.midY)
                    } action: { if !leaving { ringCentre = $0 } }
                    .offset(leaving ? handoffShift : .zero)
                    .padding(.top, 4)
                    .zIndex(1)
                Group {
                    switch step {
                    case .welcome: WelcomeStep(next: { go(.location) })
                    case .location: LocationStep(locationOnly: mode == .locationOnly, next: { go(.method) })
                    case .method: MethodStep(next: { go(.madhab) })
                    case .madhab: MadhabStep(next: { go(.appearance) })
                    case .appearance: AppearanceStep(next: { go(.reminders) })
                    case .reminders: RemindersStep(next: {
                        NotificationScheduler.reschedule(context: context, reason: "setup reminders")
                        go(.fajr)
                    })
                    case .fajr: FajrStep(next: { go(.masjid) })
                    case .masjid: MasjidStep(next: { go(.review) })
                    case .review: ReviewStep(jump: { go($0) }, done: enterApp)
                    }
                }
                .padding(.top, 26)          // every title at the same height under the ring
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                .opacity(leaving ? 0 : 1)
            }
            .fontDesign(.rounded)
            .opacity(welcome ? 0 : 1)
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
                    if let i = SetupStep.allCases.firstIndex(of: step), i > 0 { go(SetupStep.allCases[i - 1]) }
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if step != .review && mode == .full {
                Button("Skip") { go(.review) }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func go(_ s: SetupStep) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) { step = s }
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
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { welcome = true }
            return
        }
        // The page lets go; the ring glides onto the circle and thins into the welcome's hairline.
        withAnimation(.easeOut(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { welcome = true }   // same ring, same place: only the letters appear
        }
    }
}

// MARK: - Location lost (after setup)

/// Location was allowed, then turned off in iOS Settings, and there's no city (owner, 2026-09-28:
/// the whole "Where do you pray" setup read like starting over, and the opening animation had no
/// circle to land on). A page with the Salah circle's own ring — 200 pt, the 12 pt track, reported
/// to `WelcomeTarget` — so the welcome settles onto it; what sharing location gives; "Turn location
/// back on" (iOS Settings) or "Enter a city instead" (honest about what a fixed city misses). Once
/// location is back or a city is picked, the root goes straight into the app.
struct LostLocationView: View {
    @EnvironmentObject private var location: EnvLocationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickingCity = false
    /// The opening into this page (feedback 2396BDF1): 0 = only the circle, at the screen's centre
    /// (where the welcome's ring starts and lands, as on the Salah page); 1 = the title appears above
    /// it; 2 = circle and title rise together to their place; 3 = the reasons and buttons fill in.
    @State private var stage = 0
    /// The title + circle group's frame in the finished layout (the offset below doesn't move it).
    @State private var groupFrame: CGRect?

    // Location coming back (Settings or a city, `EnvLocationManager.comeback`): acknowledge it, then
    // hand off to the Salah page appearing underneath (owner, 2026-09-28).
    /// The symbol turns on and the title says so.
    @State private var acknowledged = false
    /// The title, reasons and buttons have gone; the ring goes back to the screen's centre.
    @State private var clearing = false
    /// The Salah circle's centre (y) the ring settles on, like the welcome's landing.
    @State private var landingY: CGFloat?
    /// The page fades, leaving the real Salah page round the same ring.
    @State private var handedOff = false
    /// The Salah circle is the dashed "hasn't started" track: the ring turns into it as it lands.
    @State private var landDashed = false
    /// Lost while the app was open (feedback A535F50B): the ring starts on the Salah circle it replaces
    /// (its centre y) and glides up to its place; nil once it has, or on a cold launch.
    @State private var entryY: CGFloat?
    /// The symbol inside the ring (blurs in on a warm entry, out as the ring lands on the Salah circle).
    @State private var symbolIn = true
    /// A warm entry holds the title until the ring has risen.
    @State private var titleHeld = false
    /// A warm entry fades the whole page in over the Salah page (still there under it) once the app
    /// is really on screen — the change arrives while iOS still shows the app's snapshot.
    @State private var pageIn = true

    init() {
        // Read before this page reports its own circle: where the Salah circle is right now, if it's on
        // screen — then this is a warm entry and the ring starts exactly on it (one ring, never two).
        if let f = WelcomeTarget.circleFrame, f.width > 100,
           UIScreen.main.bounds.insetBy(dx: -1, dy: -1).contains(f) {
            _entryY = State(initialValue: f.midY)
            _symbolIn = State(initialValue: false)
            _titleHeld = State(initialValue: true)
            _pageIn = State(initialValue: false)
        }
    }

    private var comeback: EnvLocationManager.Comeback? { location.comeback }

    /// How far the group is pushed down: onto the Salah circle (a warm entry's start, the hand-off's
    /// landing), to the screen's centre during the cold opening, 0 in its place.
    private var lift: CGFloat {
        guard let g = groupFrame else { return 0 }
        let circleMid = g.maxY - 100
        if let landingY { return landingY - circleMid }
        if let entryY { return entryY - circleMid }
        if stage < 2 { return UIScreen.main.bounds.midY - circleMid }
        return 0
    }

    private var textShown: Bool { stage >= 3 && !clearing }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 0) {
                title
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .opacity(stage >= 1 && !clearing && !titleHeld ? 1 : 0)
                    .blur(radius: stage >= 1 && !clearing && !titleHeld ? 0 : 6)
                ZStack {
                    // The Salah circle's track (mainCircle.swift): the welcome lands on this, and the
                    // hand-off leaves it where the Salah page's own track is.
                    Circle().stroke(Color(.secondarySystemFill), lineWidth: 12)
                        .opacity(landDashed ? 0 : 1)
                    Circle()
                        .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        .opacity(landDashed ? 1 : 0)
                    VStack(spacing: 6) {
                        Image(systemName: acknowledged ? onSymbol : "location.slash")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(acknowledged ? Color.sage : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(acknowledged ? onCaption : "location is off")
                            .font(.system(.subheadline, design: .rounded, weight: .thin))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .opacity(symbolIn ? 1 : 0)
                    .blur(radius: symbolIn ? 0 : 8)
                }
                .frame(width: 200, height: 200)
            }
            .offset(y: lift)
            // Outside the offset: the finished layout's frame, measured once it's laid out.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { groupFrame = $0 }
            .opacity(groupFrame == nil ? 0 : 1)
            VStack(alignment: .leading, spacing: 14) {
                whyRow("clock", "Prayer times that follow you", "They update by themselves when you travel.")
                whyRow("mappin.and.ellipse", "Your prayers, pinned where you prayed", "On the map, with where you were.")
                whyRow("building.columns", "Duas at your masjid", "When you arrive and when you leave.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .opacity(textShown ? 1 : 0)
            .offset(y: textShown ? 0 : 14)
            Spacer(minLength: 16)
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
            .opacity(textShown ? 1 : 0)
            .offset(y: textShown ? 0 : 14)
            .allowsHitTesting(comeback == nil)
        }
        .fontDesign(.rounded)
        .background(Color(.systemBackground).ignoresSafeArea())
        .opacity(handedOff || !pageIn ? 0 : 1)
        .onAppear { WelcomeTarget.canLand = true; WelcomeTarget.trackDashed = false }
        // Where the circle is drawn right now (centred during the opening, then in its place).
        .onChange(of: groupFrame, initial: true) { _, _ in reportCircle() }
        .onChange(of: stage) { _, _ in reportCircle() }
        .task { await intro() }
        .task(id: comeback) { if comeback != nil { await acknowledge() } }
        .sheet(isPresented: $pickingCity) {
            CityPickerSheet(onPicked: { pickingCity = false })
        }
    }

    @ViewBuilder private var title: some View {
        if acknowledged {
            VStack(spacing: 6) {
                Text(ackTitle)
                    .font(.system(.title, design: .rounded, weight: .light))
                    .multilineTextAlignment(.center)
                Text(ackLine)
                    .font(.system(.subheadline, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .transition(.blurReplace)
        } else {
            VStack(spacing: 6) {
                Text("Uh oh,")
                    .font(.system(.title3, design: .rounded, weight: .light))
                    .foregroundStyle(.secondary)
                Text("shukr lost your location")
                    .font(.system(.title, design: .rounded, weight: .light))
                    .multilineTextAlignment(.center)
            }
            .transition(.blurReplace)
        }
    }

    private var onSymbol: String {
        if case .city = comeback { return "mappin.and.ellipse" }
        return "location.fill"
    }
    private var onCaption: String {
        if case .city(let name) = comeback { return name.isEmpty ? "your city" : name }
        return "location is on"
    }
    private var ackTitle: String {
        if case .city(let name) = comeback { return name.isEmpty ? "Using your city" : "Using \(name)" }
        return "Location's back"
    }
    private var ackLine: String {
        switch comeback {
        case .city: return "Prayer times for there, until you turn location on"
        case .whileUsing: return "Choose Always in Settings so your times follow you when you travel"
        default: return "Your times follow you again"
        }
    }

    private func reportCircle() {
        // After a comeback the Salah page's own circle reports itself (the hand-off lands on it).
        guard comeback == nil, let g = groupFrame else { return }
        WelcomeTarget.circleFrame = CGRect(x: g.midX - 100, y: g.maxY - 200 + lift, width: 200, height: 200)
    }

    private func intro() async {
        if reduceMotion || comeback != nil {
            entryY = nil; titleHeld = false; symbolIn = true; stage = 3
            if !pageIn { withAnimation(.easeInOut(duration: 0.35)) { pageIn = true } }
            try? await Task.sleep(for: .milliseconds(400))
            location.endSalahLinger()
            return
        }
        if entryY != nil { await warmEntry(); return }
        // The welcome (a cold launch) grows into the centred circle first; wait for it to finish.
        try? await Task.sleep(for: .milliseconds(300))
        while WelcomeTarget.playing {
            if Task.isCancelled { return }      // the page went away mid-welcome
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Each step only while nothing has come back (acknowledge() takes the page from there).
        try? await Task.sleep(for: .milliseconds(150))
        guard comeback == nil else { return }
        withAnimation(.easeOut(duration: 0.5)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        guard comeback == nil else { return }
        withAnimation(.spring(response: 0.75, dampingFraction: 0.9)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(450))
        guard comeback == nil else { return }
        withAnimation(.easeOut(duration: 0.5)) { stage = 3 }
        #if DEBUG
        // `-demoLostCity London`: pick that city 2 s after the page settles (the city sheet's path).
        if let city = UserDefaults.standard.string(forKey: "demoLostCity") {
            try? await Task.sleep(for: .seconds(2))
            location.setManualLocation(CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), name: city)
        }
        #endif
    }

    /// Lost while the app was open: the Salah page blurs out under the page fading in, whose ring sits
    /// exactly on the Salah circle; the ring springs up to its place as the crossed-out symbol blurs in,
    /// then the title, then the reasons and buttons.
    private func warmEntry() async {
        for _ in 0..<25 where groupFrame == nil { try? await Task.sleep(for: .milliseconds(20)) }
        // Only once the app is really on screen (not under iOS's snapshot as it comes back).
        for _ in 0..<60 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(250))
        // Fade in over the Salah page: its ring sits exactly on the Salah one, the prayer fades away.
        withAnimation(.easeOut(duration: 0.3)) { pageIn = true }
        try? await Task.sleep(for: .milliseconds(300))
        location.endSalahLinger()
        guard comeback == nil else { return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { entryY = nil; stage = 2 }
        withAnimation(.easeOut(duration: 0.4).delay(0.08)) { symbolIn = true }
        try? await Task.sleep(for: .milliseconds(550))
        guard comeback == nil else { return }
        withAnimation(.easeOut(duration: 0.5)) { titleHeld = false }
        try? await Task.sleep(for: .milliseconds(450))
        guard comeback == nil else { return }
        withAnimation(.easeOut(duration: 0.5)) { stage = 3 }
    }

    /// Location's back (or a city): the symbol turns on with a soft success, the title says so; then
    /// the words go, the ring returns to the centre and settles onto the Salah circle, and the page
    /// fades from round it — the welcome's own landing. Reduce Motion: the acknowledgement, a fade.
    private func acknowledge() async {
        CircleCover.set("lostHandoff", true)       // no reminders card / qibla buzz under it
        defer { CircleCover.set("lostHandoff", false) }
        pickingCity = false
        if stage < 3 { withAnimation(.easeOut(duration: 0.3)) { stage = 3 } }
        // On screen first (Settings → back: the change lands while iOS still shows the snapshot).
        for _ in 0..<60 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(450))   // back in the app / the city sheet gone
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy(duration: 0.45)) { acknowledged = true }
        try? await Task.sleep(for: .milliseconds(comeback == .whileUsing ? 2000 : 1500))
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.5)) { handedOff = true }
            try? await Task.sleep(for: .milliseconds(520))
            location.clearComeback()
            return
        }
        // The words go while the ring glides straight onto the Salah circle (underneath by now); as it
        // lands the symbol blurs out, the band becomes the Salah track (dashed if the prayer hasn't
        // started) and the page fades, so the prayer comes in round the same ring (feedback A535F50B).
        var target = UIScreen.main.bounds.midY
        if let f = WelcomeTarget.circleFrame, f.width > 100,
           UIScreen.main.bounds.insetBy(dx: -1, dy: -1).contains(f) { target = f.midY }
        withAnimation(.easeOut(duration: 0.3)) { clearing = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { landingY = target }
        try? await Task.sleep(for: .milliseconds(360))
        withAnimation(.easeInOut(duration: 0.4)) {
            landDashed = WelcomeTarget.trackDashed
            symbolIn = false
            handedOff = true
        }
        try? await Task.sleep(for: .milliseconds(450))
        location.clearComeback()
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
        .animation(.spring(response: 0.8, dampingFraction: 0.9), value: handoff)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { drawn = true } }
        .animation(.easeInOut(duration: 0.7), value: progress)
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    StepTitle(title: title, subtitle: subtitle)
                        .padding(.bottom, 22)
                    content
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            bottom
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
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

/// The one primary button: the app's calm style (sage text on a soft sage tint, like the pause
/// screen's Resume), not a solid fill.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
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
                     subtitle: "Not just at the start: if you haven't marked it yet, a nudge halfway through and with 30 min left.") {
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
                    legend("bell.badge.fill", "nudge", "also halfway through and with 30 min left, if it isn't marked")
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
                                ForEach(0...60, id: \.self) { Text("\($0) min").tag($0) }
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
                        if let next = nextAlarm {
                            Text("Alarm tomorrow \(clockTime(next.alarm)) · Fajr \(isFajr ? "starts" : "ends") \(clockTime(next.reference))")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.sage)
                        }
                    }
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
            .padding(.horizontal, 24)
        } bottom: {
            PrimaryButton(title: "Continue") {
                saveDescription()
                next()
            }
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
                        sell: "Not just at the start: if it isn't marked yet, a nudge halfway through and with 30 min left.") { notificationsNudge }
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
