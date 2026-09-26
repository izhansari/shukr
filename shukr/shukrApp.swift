//
//  shukrApp.swift
//  shukr
//
//  Created on 8/3/24.
//

import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications
import CoreHaptics


@main
struct shukrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// @State, not @StateObject: the root only hands it down, it never reads it. As a
    /// @StateObject every published change (each page turn) re-ran this body and rebuilt the
    /// whole tree — the home screen rendered twice per change and Settings up to three times
    /// (measured on device 2026-09-24: 944 Settings renders in 90 s of paging). Views that read
    /// it still observe it through @EnvironmentObject.
    @State private var sharedState = SharedStateClass()
    
    // First define the two @StateObject properties *without* immediate assignment:
    @StateObject var environmentLocationManager: EnvLocationManager
    @StateObject var prayerViewModel: PrayerViewModel
    /// Notifications turned off while shukr is in the background: the welcome screen asks again
    /// when it comes back, same as at launch.
    @ObservedObject private var notificationStatus = NotificationStatus.shared



//    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    /// Set when the welcome screen asks for location; the app waits for its "continue" instead
    /// of jumping in the instant permission lands. A launch that's already authorized skips it.
    /// Also set at launch when notifications were last seen off, so the welcome screen asks for
    /// them again (read from a cached flag so there's no flash of the main page first).
    @State private var awaitingContinue = NotificationStatus.lastSeenDenied

    var sharedModelContainer: ModelContainer = {
        // Store lives in the app group so the widget can read/write it too. Schema + location
        // are defined once in SharedStore (SharedTargetForIntents.swift), shared with the widget.
        do {
            let container: ModelContainer
            do {
                container = try SharedStore.makeContainer()
            } catch {
                // Store exists but can't be opened (see recoverFromUnopenableStore). Set it aside
                // and rebuild from the legacy store rather than crash on every launch.
                guard let recovered = SharedStore.recoverFromUnopenableStore(after: error) else { throw error }
                container = recovered
            }
            // One-time merge of the pre-app-group store (Application Support/default.store).
            // Must run before PrayerViewModel or any view reads data. Never deletes the old files.
            SharedStore.importLegacyStoreIfNeeded(into: container)
            // What a set-aside (unopenable) store held beyond the legacy one: mantra text/notes,
            // prayer completions, newer sessions. Once per file.
            SharedStore.salvageSetAsideStoresIfNeeded(into: container)
            // Built-in mantras as rows, tasks/sessions linked to their mantra, task order.
            // Every launch, cheap on a healthy store; covers upgrades and fresh installs alike.
            SharedStore.runV2DataPass(in: container)
            // Rows scored by the old rule (fraction of window left) → points, once.
            PrayerScoring.recalculateHistoryIfNeeded(in: container)
            return container
        } catch {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { // without this, the previews donr work and result to a fatalerror.
                print("Preview mode: Using empty ModelContainer.")
                return try! ModelContainer(for: Schema([]), configurations: []) // essentially making it an empty dummy
            } else {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    
    // 2) Now in the init, create local variables first, then assign them.
    init() {
        WatchSync.shared.start()   // Apple Watch: prayer times + today's ✓s
        // 1a) Create EnvLocationManager in a local var
        let manager = EnvLocationManager()
        // 1b) Grab the ModelContext in a local var too
        let context = sharedModelContainer.mainContext
        // 2) Assign the local var to the @StateOobject...
        _environmentLocationManager = StateObject(wrappedValue: manager)
        // 2b) Assign both them badboys (context and the @StateObject envmanager) to the @StateObject
        _prayerViewModel = StateObject(
            wrappedValue: PrayerViewModel( context: context, envLocationManager: manager )
        )
    }
    
    var body: some Scene {

        WindowGroup {
            
            // v4. Nav View with PrayerTimesView and everything else as navlink inside. Reason: we were having unnecesary view redraws causing us to lose state in views like TasbeehView. Debugged this using onappear and ondisappear print statements. I learned tabView with NavigationView inside causes this issue. Well known issue apparently.
            NavigationStack{
                if (environmentLocationManager.isAuthorized || environmentLocationManager.hasManualLocation) && !awaitingContinue {
                    PrayerTimesView()
                        .transition(.blurReplace())
                    //.transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    //.toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
                }
                else{
                    GradientAnimationLoad(awaitingContinue: $awaitingContinue)
                        .transition(.blurReplace())
                }
                
            }
            .environmentObject(prayerViewModel)
            .welcomeOnLaunch()   // "shukr" + a ring + two soft taps; cold launch / back after 5+ min
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await notificationStatus.refresh() }
            }
            .onChange(of: notificationStatus.isOn) { _, isOn in
                if isOn == false { awaitingContinue = true }
            }
            .preferredColorScheme(
                colorModeToggleNew == 0 ? .light :
                    colorModeToggleNew == 1 ? .dark :
                    (prayerViewModel.isDaytime ? .light : .dark)
            )
            
            
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(environmentLocationManager)
        .environmentObject(environmentLocationManager.compass)   // compass views subscribe to this, nothing else does
        .environmentObject(sharedState) // Inject shared state into the environment (Global access point for `sharedState`)
//            .environmentObject(prayerViewModel) // Inject PrayerViewModel
        /*
         Inject `sharedState` as an EnvironmentObject at the top level of the app.
         This makes `sharedState` globally accessible to any view within the view hierarchy
         that starts from `PrayerTimesView`.
         All subviews can access it implicitly by declaring:
         `@EnvironmentObject var sharedState: SharedStateClass`.
         NOTE: This injection covers all views in the hierarchy. Additional injections are unnecessary,
         unless a view is presented outside this hierarchy, like with a new window or distinct view instance.
         */
        
    }
}



/// Notification permission for the welcome screen: nil = not asked yet, true = on, false = off.
/// One shared instance so the AppDelegate's permission request can refresh it when answered.
final class NotificationStatus: ObservableObject {
    static let shared = NotificationStatus()
    private static let deniedKey = "notificationsLastSeenDenied"
    static var lastSeenDenied: Bool { UserDefaults.standard.bool(forKey: deniedKey) }

    @Published private(set) var isOn: Bool? = NotificationStatus.lastSeenDenied ? false : nil

    @MainActor
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let value: Bool?
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: value = true
        case .denied: value = false
        default: value = nil
        }
        if isOn != value { isOn = value }
        UserDefaults.standard.set(value == false, forKey: Self.deniedKey)
    }

    /// Ask (first time) — the system shows its prompt once; after that it's Settings only.
    func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { await self.refresh() }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()
    
    func requestUserNotificationPermission() {
        #if DEBUG
        // Simulator demo launches (-demoPrayerCompletion / -demoStreakCelebration) record the
        // screen; the permission alert would sit on top of what they're showing.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") }) { return }
        #endif
        // Request notification permissions (if not already requested)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
            Task { await NotificationStatus.shared.refresh() }
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        QiblaSettings.migrateFromStandardDefaultsIfNeeded()
        
        // Register notification categories
        // "I already prayed": marks that prayer complete in place, the way the widget's
        // checkmark does (SharedStore.markPrayerComplete). On every prayer category.
        let markPrayed = UNNotificationAction(
            identifier: "MARK_PRAYED_ACTION",
            title: "I already prayed",
            options: []
        )
        let snooze5 = UNNotificationAction(
            identifier: "SNOOZE_5_ACTION",
            title: "Nudge in 5 minutes",
            options: []
        )
        let snooze10 = UNNotificationAction(
            identifier: "SNOOZE_10_ACTION",
            title: "Nudge in 10 minutes",
            options: []
        )
        let round1Actions = UNNotificationCategory(
            identifier: "Round1_Snooze",
            actions: [markPrayed, snooze5, snooze10],
            intentIdentifiers: [],
            options: []
        )
        // Register notification categories
        let round2_snooze5 = UNNotificationAction(
            identifier: "ROUND2_SNOOZE_5_ACTION",
            title: "5 more minutes",
            options: []
        )
        let round2Actions = UNNotificationCategory(
            identifier: "Round2_Snooze",
            actions: [markPrayed, round2_snooze5],
            intentIdentifiers: [],
            options: []
        )
        // Register notification categories
        let round2_conf = UNNotificationAction(
            identifier: "ROUND2_CONFIRM_ACTION",
            title: "Yes",
            options: []
        )
        let round2_deny = UNNotificationAction(
            identifier: "ROUND2_DENY_ACTION",
            title: "Lol, I'll pray right now!",
            options: [.foreground]
        )
        let round2Confirmation = UNNotificationCategory(
            identifier: "Round2_Confirm",
            actions: [markPrayed, round2_conf, round2_deny],
            intentIdentifiers: [],
            options: []
        )
        
        // Register the category with the notification center
        UNUserNotificationCenter.current().setNotificationCategories([round1Actions, round2Actions, round2Confirmation])
        print("✅ Notification categories registered")
        
        requestUserNotificationPermission()

        return true
    }
}


class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // An action tapped while the app isn't running launches it in the background just long
    // enough to handle the response; iOS can suspend it as soon as `completionHandler` runs.
    // Calling it before the follow-up notification was actually added is why "Nudge in 5
    // minutes" rarely produced one. Every branch now completes from inside `add`'s callback.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // The prayer the original notification was about: its userInfo (set when the app
        // scheduled it) rides along on every follow-up so "I already prayed" works from those too.
        let original = response.notification.request.content
        let subject = original.subtitle.isEmpty ? original.title : original.subtitle
        let userInfo = original.userInfo
        switch response.actionIdentifier {
        case "MARK_PRAYED_ACTION":
            if let name = userInfo["prayerName"] as? String,
               let start = userInfo["prayerStart"] as? TimeInterval,
               let end = userInfo["prayerEnd"] as? TimeInterval {
                let done = SharedStore.markPrayerComplete(named: name, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
                print(done ? "✅ \(name) marked complete from the notification" : "ℹ️ \(name) not marked (not started, already complete, or store unavailable)")
            } else {
                print("ℹ️ MARK_PRAYED_ACTION on a notification without prayer info (a test one?)")
            }
            completionHandler()

        case "SNOOZE_5_ACTION", "SNOOZE_10_ACTION":
            let minutes = response.actionIdentifier == "SNOOZE_5_ACTION" ? 5 : 10
            print("SNOOZE_\(minutes)_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: TimeInterval(minutes * 60),
                title: "It's been \(minutes) minutes",
                body: subject,
                userInfo: userInfo,
                withActionsFromCatId: "Round2_Snooze",
                then: completionHandler
            )

        case "ROUND2_SNOOZE_5_ACTION", "ROUND2_SNOOZE_10_ACTION": //got rid of snooze 10
            let minutes = response.actionIdentifier == "ROUND2_SNOOZE_5_ACTION" ? 5 : 10
            print("ROUND2_SNOOZE_\(minutes)_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: 1,
                title: "😑 Are you being serious? Another \(minutes) minutes?",
                body: subject,
                userInfo: userInfo,
                withActionsFromCatId: "Round2_Confirm",
                then: completionHandler
            )

        case "ROUND2_CONFIRM_ACTION":
            print("ROUND2_CONFIRM_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: 5 * 60,   // was 5 seconds
                title: "5 more minutes have passed!",
                body: subject,
                userInfo: userInfo,
                withActionsFromCatId: "Round1_Snooze",   // still offers "I already prayed"
                then: completionHandler
            )

        case "ROUND2_DENY_ACTION":
            print("ROUND2_DENY_ACTION action tapped")
            completionHandler() // .foreground: iOS opens the app

        default:
            completionHandler()
        }
    }

    private func makeNextSnoozeNotifBe(after seconds: TimeInterval, title: String, body: String, userInfo: [AnyHashable: Any], withActionsFromCatId: String?, then done: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        let identifier = "snooze-\(UUID().uuidString)"
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive
        if let withActionsFromCatId {
            content.categoryIdentifier = withActionsFromCatId
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error \(identifier): \(error.localizedDescription)")
            } else {
                print("✅ Scheduled \(identifier): in \(seconds)s")
            }
            done()
        }
    }
}







import SwiftUI

struct GradientAnimationLoad: View {
    @Binding var awaitingContinue: Bool
    /// "continue" was tapped: rings ripple in from the edges to the circle, haptics follow them,
    /// the circle blooms, then the app dissolves in. Longer than a plain crossfade on purpose
    /// (owner wanted it to feel magical). Timings live in `WelcomeRipple`.
    @State private var entering = false
    @State private var noiseOpacity: Double = 0.2
    @State private var dummyDarkOn: Bool = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    
    var body: some View {
        ZStack {
            // Animated Wavy Gradient Background
            AnimatedWavyGradient()
                .ignoresSafeArea()

            // Noise Overlay for a grainy effect
            NoiseOverlay()
                .blendMode(.overlay)
                .opacity(noiseOpacity)
                .ignoresSafeArea()
            
            // Rings that ripple in from the screen edges to the circle on "continue".
            WelcomeRippleRings(active: entering)
                .allowsHitTesting(false)

            // Glassmorphic Card
            GlassmorphicCard()
                .frame(width: 200, height: 200)
                // A small bounce as each ring lands, then a bloom as the app comes in.
                .keyframeAnimator(initialValue: 1.0, trigger: entering) { content, scale in
                    content.scaleEffect(scale).brightness((scale - 1) * 0.8)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(1, duration: WelcomeRipple.arrivals[0])
                        CubicKeyframe(1.035, duration: 0.08)
                        CubicKeyframe(1, duration: WelcomeRipple.gap - 0.08)
                        CubicKeyframe(1.045, duration: 0.08)
                        CubicKeyframe(1, duration: WelcomeRipple.gap - 0.08)
                        SpringKeyframe(1.14, duration: 0.5, spring: .bouncy)
                    }
                }
                .onTapGesture {
                    dummyDarkOn.toggle()
                    if dummyDarkOn{colorModeToggleNew = 0}
                    else {colorModeToggleNew = 1}
                    print(dummyDarkOn)
                }
            
            VStack(spacing: 14){
                Spacer()
                WelcomeStatusText()
                GlassmorphicButton(awaitingContinue: $awaitingContinue, onEnter: enterApp)
                    .frame(width: 200, height: 50)
                WelcomeSecondaryLinks(onEnter: enterApp)
            }
            .opacity(entering ? 0 : 1)
            .animation(.easeOut(duration: 0.35), value: entering)
            .allowsHitTesting(!entering)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                noiseOpacity = 0.3
            }
        }
//        .preferredColorScheme(dummyDarkOn ? .dark : .light)
    }

    private func enterApp() {
        guard !entering else { return }
        entering = true
        WelcomeHaptics.playRipple()
        DispatchQueue.main.asyncAfter(deadline: .now() + WelcomeRipple.dissolveAt) {
            withAnimation(.easeInOut(duration: 0.8)) { awaitingContinue = false }
        }
    }
}

// MARK: - Welcome Ripple
/// Timings shared by the rings, the circle's bounces and the haptics so they stay in step.
enum WelcomeRipple {
    static let travel = 0.8          // edge → circle
    static let gap = 0.2             // between rings
    static let starts: [Double] = [0, gap, gap * 2]
    static var arrivals: [Double] { starts.map { $0 + travel } }
    static var dissolveAt: Double { arrivals[2] + 0.15 }
}

/// Three faint rings drifting in from past the screen edges to the welcome circle, one after
/// another — sharpening and speeding up as they close in, landing with a slight overshoot like
/// a wave meeting the shore — then a soft glow at the circle. Invisible until `active` flips.
struct WelcomeRippleRings: View {
    var active: Bool

    private struct Frame {
        var scale: Double = 7
        var opacity: Double = 0
        var blur: Double = 6
    }

    var body: some View {
        ZStack {
            ForEach(WelcomeRipple.starts.indices, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 200, height: 200)
                    .keyframeAnimator(initialValue: Frame(), trigger: active) { content, f in
                        content.scaleEffect(f.scale).opacity(f.opacity).blur(radius: f.blur)
                    } keyframes: { _ in
                        let start = WelcomeRipple.starts[i]
                        let travel = WelcomeRipple.travel
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(7, duration: start)
                            // Ease in: slow from the edge, quickening as it's pulled to the centre.
                            CubicKeyframe(1.08, duration: travel * 0.85)
                            CubicKeyframe(0.94, duration: travel * 0.15)   // overshoot into the circle
                            CubicKeyframe(1.0, duration: 0.12)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: start)
                            CubicKeyframe(1, duration: travel * 0.6)
                            LinearKeyframe(1, duration: travel * 0.4)
                            CubicKeyframe(0, duration: 0.18)
                        }
                        KeyframeTrack(\.blur) {
                            LinearKeyframe(6, duration: start)
                            CubicKeyframe(0, duration: travel)
                        }
                    }
            }

            // Glow at the circle once the last ring lands.
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 200, height: 200)
                .keyframeAnimator(initialValue: Frame(scale: 1, opacity: 0, blur: 30), trigger: active) { content, f in
                    content.scaleEffect(f.scale).opacity(f.opacity).blur(radius: f.blur)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1, duration: WelcomeRipple.arrivals[2])
                        CubicKeyframe(1.7, duration: 0.7)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: WelcomeRipple.arrivals[2])
                        CubicKeyframe(1, duration: 0.2)
                        CubicKeyframe(0, duration: 0.6)
                    }
                }
        }
    }
}

// MARK: - Welcome Haptics
/// The rings, felt: each one a soft swell that builds as it closes in and a tap as it lands on
/// the circle (a little stronger each time), then a low bloom that fades as the app appears.
/// Falls back to plain impacts on hardware without Core Haptics.
enum WelcomeHaptics {
    private static var engine: CHHapticEngine?

    static func playRipple() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback()
            return
        }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
            }
            try engine?.start()

            func param(_ id: CHHapticEvent.ParameterID, _ value: Float) -> CHHapticEventParameter {
                CHHapticEventParameter(parameterID: id, value: value)
            }
            var events: [CHHapticEvent] = []
            for (i, start) in WelcomeRipple.starts.enumerated() {
                let arrival = start + WelcomeRipple.travel
                let strength = Float(i) * 0.12
                // The approach: rises from nothing to a hum, the way the ring sharpens on screen.
                let swellStart = start + WelcomeRipple.travel * 0.35
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    param(.hapticIntensity, 0.28 + strength),
                    param(.hapticSharpness, 0.1),
                    param(.attackTime, Float(arrival - swellStart)),
                    param(.releaseTime, 0.05)
                ], relativeTime: swellStart, duration: arrival - swellStart))
                // The landing.
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    param(.hapticIntensity, 0.55 + strength),
                    param(.hapticSharpness, 0.3)
                ], relativeTime: arrival))
            }
            // The bloom, fading out as the app dissolves in.
            let bloomAt = WelcomeRipple.arrivals[2] + 0.02
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                param(.hapticIntensity, 0.5),
                param(.hapticSharpness, 0.05),
                param(.decayTime, 0.6),
                param(.sustained, 0)
            ], relativeTime: bloomAt, duration: 0.7))

            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    private static func fallback() {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        let arrivals = WelcomeRipple.arrivals
        for (delay, intensity) in [(arrivals[0], 0.55), (arrivals[1], 0.7), (arrivals[2], 0.85)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { soft.impactOccurred(intensity: intensity) }
        }
    }
}

// MARK: - Animated Wavy Gradient (COMPLETELY REWORKED)
struct AnimatedWavyGradient: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.green.opacity(0.3),
                    Color.black.opacity(0.9),
                    Color.white.opacity(0.1)
                ]),
                center: animate ? .topLeading : .bottomTrailing,
                startRadius: animate ? 100 : 300,
                endRadius: animate ? 600 : 800
            )
            .hueRotation(.degrees(animate ? 20 : -20))
            .blur(radius: 40)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.8),
                    Color.green.opacity(0.3),
                    Color.white.opacity(0.1)
                ]),
                center: animate ? .bottomTrailing : .topLeading,
                startRadius: animate ? 50 : 200,
                endRadius: animate ? 700 : 900
            )
            .hueRotation(.degrees(animate ? -10 : 15))
            .opacity(0.6)
            .blur(radius: 50)
        }
        .animation(
            .easeInOut(duration: 15).repeatForever(autoreverses: true),
            value: animate
        )
        .onAppear {
            animate.toggle()
        }
    }
}

// MARK: - Noise Overlay
struct NoiseOverlay: View {
    var body: some View {
        Canvas { context, size in
            for _ in 0..<6000 {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let brightness = CGFloat.random(in: 0.3...0.8)
                let alpha = CGFloat.random(in: 0.1...0.3)
                
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                    with: .color(Color.white.opacity(alpha))
                )
            }
        }
    }
}

// MARK: - Glassmorphic Card
struct GlassmorphicCard: View {

    var body: some View {
//        RoundedRectangle(cornerRadius: 25)
        Circle()
            .fill(Color.white.opacity(0.1))
            .background(
//                RoundedRectangle(cornerRadius: 25)
                Circle()
                    .stroke(Color(.secondarySystemFill).opacity(0.7), lineWidth: 1)
            )
            .overlay(
                VStack {
//                    Text("shukr")
//                        .font(.title2)
                    Text("welcom to")
                        .font(.footnote)
                        .fontWeight(.thin)
                        .fontDesign(.rounded)
                        .foregroundColor(.white.opacity(0.6))
                    Text("shukr")
                        .font(.title)
                        .fontWeight(.thin)
                        .fontDesign(.rounded)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding()
            )
            .shadow(radius: 5)
    }
}

// MARK: - Glassmorphic Button
struct GlassmorphicButton: View {
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @ObservedObject private var notifications = NotificationStatus.shared
    @Binding var awaitingContinue: Bool
    var onEnter: () -> Void
    let settingsURL = URL(string: UIApplication.openSettingsURLString)

    /// One step at a time: location (or a picked city), then notifications, then "continue".
    private enum Step { case location, openSettings, allowNotifications, notificationSettings, proceed }
    private var locationReady: Bool { envLocationManager.isAuthorized || envLocationManager.hasManualLocation }
    private var locationDenied: Bool {
        envLocationManager.authorizationStatus == .denied || envLocationManager.authorizationStatus == .restricted
    }
    private var step: Step {
        if !locationReady { return locationDenied ? .openSettings : .location }
        switch notifications.isOn {
        case .none: return .allowNotifications
        case .some(false): return .notificationSettings
        case .some(true): return .proceed
        }
    }
    /// Permissions are in: the same button becomes "continue" and the user goes in when ready.
    private var readyToContinue: Bool { step == .proceed && awaitingContinue }
    private var title: String {
        switch step {
        case .location: "allow location access"
        case .openSettings: "open settings"
        case .allowNotifications: "allow notifications"
        case .notificationSettings: "turn on notifications"
        case .proceed: "continue"
        }
    }
    private var symbol: String {
        switch step {
        case .location: "location"
        case .openSettings: "gear"
        case .allowNotifications, .notificationSettings: "bell"
        case .proceed: "arrow.right"
        }
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.white.opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color(.secondarySystemFill).opacity(0.7), lineWidth: 1)
            )
            .overlay(
                VStack {
                    Button(action: {
                        switch step {
                        case .proceed:
                            onEnter()
                        case .openSettings:
                            if let url = settingsURL { UIApplication.shared.open(url) }
                        case .location:
                            awaitingContinue = true   // hold the welcome screen until "continue"
                            envLocationManager.requestLocationPermission()
                        case .allowNotifications:
                            awaitingContinue = true
                            notifications.request()
                        case .notificationSettings:
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }) {
                        Label(title, systemImage: symbol)
                            .font(.footnote)
                            .fontWeight(.light)
                            .fontDesign(.rounded)
                            .foregroundColor(.white.opacity(readyToContinue ? 0.9 : 0.6))
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: title)
//                            .padding()
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            )
            .shadow(radius: 5)
            .onAppear {
                // The welcome screen is up and permission isn't in yet (the system prompt
                // fires on its own at first launch): hold here until "continue" even if the
                // prompt is answered before this button is ever tapped. Checked synchronously
                // so an already-authorized launch never arms the hold.
                switch envLocationManager.manager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways: break
                default: awaitingContinue = true
                }
            }
    }
}
// MARK: - Welcome Status Text
/// A line of copy above the welcome button saying where things stand, and which permissions
/// are on. Same light, rounded type as the rest of the welcome screen.
struct WelcomeStatusText: View {
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastCityName", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var cityName: String = ""
    @ObservedObject private var notifications = NotificationStatus.shared
    private var notificationsOn: Bool? { notifications.isOn }

    private var status: CLAuthorizationStatus { envLocationManager.authorizationStatus }
    private var locationDenied: Bool { status == .denied || status == .restricted }
    private var locationReady: Bool { envLocationManager.isAuthorized || envLocationManager.hasManualLocation }

    /// Speaks to the step the button is on: location first, then notifications.
    private var message: String {
        if !locationReady {
            if locationDenied { return "location is off. turn it on in settings, or pick a city below." }
            return "shukr uses your location to set prayer times and find the qibla."
        }
        if notificationsOn == false {
            return "notifications are off, so shukr can't tell you when it's time to pray. turn them on in settings."
        }
        if notificationsOn == nil {
            return "allow notifications so shukr can tell you when it's time to pray."
        }
        if !envLocationManager.isAuthorized, !cityName.isEmpty {
            return "prayer times are set for \(cityName). turn on location anytime for your exact spot."
        }
        return "you're all set. prayer times and the qibla follow where you are, and shukr will remind you to pray."
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .fontWeight(.light)
                .fontDesign(.rounded)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .contentTransition(.opacity)

            HStack(spacing: 14) {
                permission("location",
                           on: envLocationManager.isAuthorized ? true : (locationDenied ? false : nil),
                           onSymbol: "location.fill", offSymbol: "location.slash")
                permission("notifications", on: notificationsOn,
                           onSymbol: "bell.fill", offSymbol: "bell.slash")
            }
        }
        // The gradient is pale green down here; a faint shadow keeps the light text legible.
        .shadow(color: .black.opacity(0.25), radius: 3)
        .animation(.easeInOut(duration: 0.3), value: message)
        .task { await notifications.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.refresh() } }
        }
    }

    /// on: true = granted, false = denied, nil = not asked yet.
    private func permission(_ name: String, on: Bool?, onSymbol: String, offSymbol: String) -> some View {
        Label(name, systemImage: on == false ? offSymbol : onSymbol)
            .font(.caption2)
            .fontWeight(.light)
            .fontDesign(.rounded)
            .foregroundColor(.white.opacity(on == true ? 0.8 : 0.45))
            .strikethrough(on == false, color: .white.opacity(0.45))
    }
}

// MARK: - Welcome Secondary Links
/// The quiet way forward under the welcome button: pick a city when location is off, and go in
/// without reminders when notifications are off. The big button always asks for the permission;
/// these keep the app usable without it (App Review: permissions can't be required).
struct WelcomeSecondaryLinks: View {
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @ObservedObject private var notifications = NotificationStatus.shared
    var onEnter: () -> Void
    @State private var showCityPicker = false

    private var locationDenied: Bool {
        envLocationManager.authorizationStatus == .denied || envLocationManager.authorizationStatus == .restricted
    }
    private var locationReady: Bool { envLocationManager.isAuthorized || envLocationManager.hasManualLocation }
    private var showCityLink: Bool { locationDenied && (!envLocationManager.hasManualLocation || notifications.isOn == true) }
    private var showSkipNotifications: Bool { locationReady && notifications.isOn == false }

    var body: some View {
        VStack(spacing: 8) {
            if showCityLink {
                link(envLocationManager.hasManualLocation ? "change city" : "or enter your city instead") {
                    showCityPicker = true
                }
            }
            if showSkipNotifications {
                link("continue without reminders", action: onEnter)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showCityLink)
        .animation(.easeInOut(duration: 0.3), value: showSkipNotifications)
        .sheet(isPresented: $showCityPicker) {
            CityPickerSheet()
                .environmentObject(envLocationManager)
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote)
            .fontWeight(.light)
            .fontDesign(.rounded)
            .foregroundColor(.white.opacity(0.7))
            .underline()
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.25), radius: 3)
    }
}

//// MARK: - Preview
//struct GradientAnimationLoad_Previews: PreviewProvider {
//    static var previews: some View {
//        GradientAnimationLoad()
//    }
//}
