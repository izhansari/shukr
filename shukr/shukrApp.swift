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
import WidgetKit


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
    /// The first-run setup (FirstRunSetup.swift) is up: once per install, existing users included,
    /// and again from Settings → Run setup again (DEBUG / TestFlight). It replaced the old first
    /// open (`GradientAnimationLoad`), which also re-appeared whenever notifications were off —
    /// now the setup's review and Settings nudge instead; nothing gates the app.
    @State private var setupShowing = FirstRunSetup.shouldShowAtLaunch()

    var sharedModelContainer: ModelContainer = {
        // Store lives in the app group so the widget can read/write it too. Schema + location
        // are defined once in SharedStore (SharedTargetForIntents.swift), shared with the widget.
        // Before anything computes prayer times: a method written for installs that never picked one
        // (Automatic for new installs), and Auto appearance for new installs (the setup recommends it).
        FirstRunSetup.migrateDefaults()
        do {
            #if DEBUG
            // `-forceStoreFailure`: straight to the in-memory fallback below (skips the recovery, which would
            // set the real store aside).
            if ProcessInfo.processInfo.arguments.contains("-forceStoreFailure") { throw StoreFallback.Forced() }
            #endif
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
            // Extra unmarked prayer rows from the old 5-row lookup in fetchPrayerTimes (2026-09-27).
            PrayerViewModel.removeDuplicatePrayerRows(in: container)
            // A tasbeeh session the last run never got to save (evicted / swiped away) is saved now (audit A7).
            SessionDraft.restoreIfAny(in: container)
            #if DEBUG
            // `-demoNextLabel on|off`: the "Next prayer" dev toggle, for screenshots.
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoNextLabel"),
               i + 1 < ProcessInfo.processInfo.arguments.count {
                UserDefaults(suiteName: SharedStore.appGroup)?.set(ProcessInfo.processInfo.arguments[i + 1] == "on", forKey: NextLabel.key)
            }
            // `-demoWidget "Fajr=0.95,Dhuhr=0.72" [-demoWidgetCorners dailyAyah,none] [-demoWidgetList] [-demoWidgetPlain]`:
            // the Prayers widget (DEBUG) shows these scores / corners / the list, for screenshots.
            // `-demoWidget off` clears it.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoWidget"), i + 1 < args.count {
                let group = UserDefaults(suiteName: SharedStore.appGroup)
                if args[i + 1] == "off" {
                    group?.removeObject(forKey: "demoWidget.scores"); group?.removeObject(forKey: "demoWidget.corners")
                } else {
                    group?.set(args[i + 1], forKey: "demoWidget.scores")
                    if let j = args.firstIndex(of: "-demoWidgetCorners"), j + 1 < args.count {
                        group?.set(args[j + 1], forKey: "demoWidget.corners")
                    } else { group?.removeObject(forKey: "demoWidget.corners") }
                }
                group?.set(args.contains("-demoWidgetPlain"), forKey: "demoWidget.plain")   // score colours off
                if args.contains("-demoWidgetShots") { group?.set(true, forKey: "demoWidget.renderShots") }   // exact-size renders
                if args.contains("-demoWidgetList") {
                    group?.set(true, forKey: WidgetListState.openKey)
                    group?.set(Date().timeIntervalSince1970, forKey: WidgetListState.openedAtKey)
                } else {
                    group?.set(false, forKey: WidgetListState.openKey)
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
            if ProcessInfo.processInfo.arguments.contains("-demoBackUpStore") {
                PrayerScoring.backUpStore(label: "debug-\(Int(Date().timeIntervalSince1970))")
            }
            #endif
            return container
        } catch {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { // without this, the previews donr work and result to a fatalerror.
                print("Preview mode: Using empty ModelContainer.")
                return try! ModelContainer(for: Schema([]), configurations: []) // essentially making it an empty dummy
            }
            // Neither the store nor a recovery opened (WF56; an App Store blocker as a crash): run on an
            // in-memory store so times, the qibla and the counter work. Nothing is saved; the store and any
            // set-aside copy stay untouched on disk; an alert says so once the app is up.
            print("❌ store: couldn't open or recover the shared store (\(error)); running in memory, nothing is saved")
            StoreFallback.active = true
            let memory = ModelConfiguration(schema: SharedStore.schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: SharedStore.schema, configurations: [memory]) { return container }
            print("❌ store: the in-memory store failed too")
            return try! ModelContainer(for: Schema([]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }()
    
    
    // 2) Now in the init, create local variables first, then assign them.
    init() {
        // Apple Watch: prayer times, today's ✓s, zikr. Not on the in-memory fallback: the phone would confirm the
        // watch's marks and sessions into a store that's thrown away, and the watch would drop them.
        if !StoreFallback.active { WatchSync.shared.start(container: sharedModelContainer) }
        NextLabelTuning.clearSavedTuningOnce()   // back to the original NEXT look (2026-09-27)
        #if DEBUG
        SalahLook.seedExploringDefaults()   // dev builds start the look exploration on Sunken well, no lines
        if ProcessInfo.processInfo.arguments.contains("-autoMethodTest") { AutoMethodSelfTest.run() }
        // `-sendNotificationSamples YES` (NotificationSamples): every notification, 6 s apart.
        if UserDefaults.standard.bool(forKey: "sendNotificationSamples") { Task { await NotificationSamples.send() } }
        if ProcessInfo.processInfo.arguments.contains("-alarmCheck") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { AlarmSelfTest.run() }   // after migrateDefaults
        }
        #endif
        WhatsNew.noteLaunch()      // a new build moves the last one to "previous" (NEW badges)
        // 1a) Create EnvLocationManager in a local var
        let manager = EnvLocationManager()
        let updates = manager.locationUpdates
        #if DEBUG
        // `-demoCompassJiggle`: the heading changes 5× a second, like a phone moving (the simulator
        // has no compass) — reproduces anything that re-renders with the compass.
        // Through the real heading path (smoothing, the qibla, aligned), turning 3° a step; with
        // `-demoCompassSweep` it sweeps back and forth across the qibla instead.
        if ProcessInfo.processInfo.arguments.contains("-demoCompassJiggle") {
            var degrees = 0.0, step = 3.0
            let sweep = ProcessInfo.processInfo.arguments.contains("-demoCompassSweep")
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak manager] _ in
                degrees += step
                if sweep, abs(degrees) > 30 { step = -step }
                manager?.debugHeading(degrees, around: sweep)
            }
        }
        #endif
        Task { @MainActor in
            MasjidArrival.shared.start()                        // entering / leaving duas (opt-in)
            HolyCityWelcome.shared.start(updates)   // "Welcome to Makkah / Madinah"
        }
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
                if environmentLocationManager.isAuthorized || environmentLocationManager.hasManualLocation
                    || environmentLocationManager.salahLingers
                    || (!setupShowing && environmentLocationManager.locationLost) {
                    // Under the setup too, once there's a location: its last step lands on this
                    // page's circle. Location turned off since, no city: "shukr lost your location" is a
                    // state of this page's circle (circle step 3b; LostPageLayer), so it stays up as location
                    // comes back and hands off on the same ring.
                    PrayerTimesView()
                        .transition(.blurReplace())
                } else if !setupShowing {
                    // No location at all (refused with no city): just the setup's location step.
                    FirstRunSetupView(mode: .locationOnly)
                        .transition(.blurReplace())
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }
            }
            .environmentObject(prayerViewModel)
            .overlay {
                if setupShowing {
                    FirstRunSetupView(onFinish: {
                        setupShowing = false
                        // Before the post: the onChange that mirrors `setupShowing` runs after it, and
                        // PrayerTimesView's hand-off skipped every waiting deep link while this was true.
                        FirstRunSetup.isShowing = false
                        // Any widget / control deep link that came in meanwhile, now (PrayerTimesView).
                        NotificationCenter.default.post(name: FirstRunSetup.finished, object: nil)
                    })
                    .environmentObject(prayerViewModel)
                    .transition(.opacity)
                }
            }
            .welcomeOnLaunch()   // "shukr" + a ring + two soft taps; cold launch (not under the setup: it ends in it)
            // The look for the root's overlays too (the setup, the welcome): they read the stored picks per access, not
            // reactively, without it (audit F, U5).
            .circleThemeRoot()
            .task { await StoreFallback.alertOnce() }   // the store couldn't be opened: say so, once per launch
            .onReceive(NotificationCenter.default.publisher(for: FirstRunSetup.rerun)) { _ in
                // Back to the Salah page (sheet closed) under it, so the hand-off lands on the circle.
                sharedState.horizontalPage = .main
                sharedState.navPosition = .main
                withAnimation(CircleMotion.ease()) { setupShowing = true }   // 0.35 s, CircleMotion.standard
            }
            .onChange(of: setupShowing, initial: true) { _, showing in
                FirstRunSetup.isShowing = showing
                // Location that came back inside the setup has nothing to acknowledge it (the lost
                // page is gated off under the setup): drop it, or "Location's back" would pop up after
                // the setup's own landing.
                environmentLocationManager.clearComeback()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await notificationStatus.refresh()
                    await NotificationHealth.shared.refresh()   // will the reminders arrive? (off / summary / …)
                }
            }
            .preferredColorScheme(
                colorModeToggleNew == 0 ? .light :
                    colorModeToggleNew == 1 ? .dark :
                    (prayerViewModel.isDaytime ? .light : .dark)
            )
            
            
        }
        .modelContainer(sharedModelContainer)
        // Tops the prayer notifications up while the app isn't opened (NotificationScheduler).
        .backgroundTask(.appRefresh(NotificationScheduler.refreshTaskID)) {
            NotificationHealth.noteBackgroundRefreshRan()   // for Settings → Scheduled notifications (beta)
            await NotificationScheduler.rescheduleNow(context: sharedModelContainer.mainContext, reason: "background refresh")
        }
        .environmentObject(environmentLocationManager)
        .environmentObject(environmentLocationManager.compass)   // compass views subscribe to this, nothing else does
        .environmentObject(environmentLocationManager.health)    // "needs calibrating": the ☰ badge / row, the line
        .environment(sharedState) // Inject shared state into the environment (Global access point for `sharedState`)
//            .environmentObject(prayerViewModel) // Inject PrayerViewModel
        /*
         Inject `sharedState` as an EnvironmentObject at the top level of the app.
         This makes `sharedState` globally accessible to any view within the view hierarchy
         that starts from `PrayerTimesView`.
         All subviews can access it implicitly by declaring:
         `@Environment(SharedStateClass.self) var sharedState`.
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
        // New installs are asked in the first-run setup's Reminders step, after it says why.
        guard FirstRunSetup.isDone else { return }
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
        #if DEBUG
        // Scheduler test: queue a snooze like "Nudge in 10 minutes" does, then relaunch without
        // the flag — it must still be pending (NotificationScheduler never removes it).
        // `-debugDeliverKeepAlive`: a last-resort reminder delivered now (the next re-plan must clear it).
        if ProcessInfo.processInfo.arguments.contains("-debugDeliverKeepAlive") {
            let content = UNMutableNotificationContent()
            content.title = "Open shukr to keep your prayer reminders coming"
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: NotificationScheduler.keepAlivePrefix + "2026-09-20", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        }
        // `-demoMasjidDua`: a delivered "Leaving the masjid" dua (Upcoming reminders' Masjid cell).
        if ProcessInfo.processInfo.arguments.contains("-demoMasjidDua") {
            Task { @MainActor in MasjidArrival.notify(masjid: "Islamic Center of Cary", entering: false) }
        }
        if ProcessInfo.processInfo.arguments.contains("-debugQueueSnooze") {
            let content = UNMutableNotificationContent()
            content.title = "It's been 10 minutes"
            content.body = "Pray by 11:59 PM"
            content.categoryIdentifier = "Round2_Snooze"
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "snooze-debug-\(Int(Date().timeIntervalSince1970))", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
        }
        #endif
        // The "hide Ahmadiyya mosques" toggle is gone (871ae72): drop its leftover value.
        UserDefaults.standard.removeObject(forKey: "hideAhmadiyyaMosques")
        // The post-salah prompt is only the bottom pill now (2026-09-27): its dev picker is gone.
        UserDefaults.standard.removeObject(forKey: "postSalahPromptStyle")
        
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
        UNUserNotificationCenter.current().setNotificationCategories([round1Actions, round2Actions, round2Confirmation,
                                                                      ZikrReminders.registerCategory()])
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
        // Zikr task reminders (ZikrReminders): Start now / tap, Later.
        if original.categoryIdentifier == ZikrReminders.category, let taskID = userInfo["zikrTaskID"] as? String {
            switch response.actionIdentifier {
            case ZikrReminders.laterAction:
                ZikrReminders.later(original, taskID: taskID, then: completionHandler)
            case UNNotificationDismissActionIdentifier:
                completionHandler()
            default:   // Start now, or a tap on the notification
                DispatchQueue.main.async {
                    ZikrReminders.open(taskID: taskID)
                    completionHandler()
                }
            }
            return
        }
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

// The old first open (GradientAnimationLoad: this gradient, glass cards, ripple rings) was replaced
// by the first-run setup (FirstRunSetup.swift, 2026-09-28). Its gradient and grain live on in the
// setup's Bismillah capsule and the Daily Ayah share card.

// MARK: - Animated Wavy Gradient (COMPLETELY REWORKED)
struct AnimatedWavyGradient: View {
    /// Reduce Motion: the gradient as it is, no waves.
    var still = false
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
            if !still { animate.toggle() }
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

/// The shared store couldn't be opened, even after `recoverFromUnopenableStore` (WF56). The app then runs on an
/// in-memory store: times, the qibla and the counter work, nothing is saved. What would write lasting state from
/// those empty rows stays off — the streak recount (`PrayerViewModel`) and the watch sync — and the files on disk
/// are never touched. DEBUG `-forceStoreFailure` goes straight here.
enum StoreFallback {
    static var active = false
    struct Forced: Error {}
    private static var alerted = false

    /// A plain alert, once per launch, when the app is on screen: a moment in, after the welcome, waiting on the stage
    /// (it retried every 0.5 s, 40 times — tr-final).
    @MainActor static func alertOnce() async {
        guard active, !alerted, await CircleGate.pause(1.5) else { return }
        let welcome = WelcomeTarget.state
        guard await CircleStage.shared.until(deadline: 20, { CircleStage.shared.sceneActive && !welcome.playing }),
              !alerted, OverlayAlert.canShow else { return }
        alerted = true
        let alert = UIAlertController(
            title: "Couldn't open your saved data",
            message: "Your prayers and zikr are kept safe on this phone. Until the next update, what you mark or count won't be saved.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in OverlayAlert.finish() })
        OverlayAlert.show(alert)
    }
}
