//
//  shukrApp.swift
//  shukr
//
//  Created on 8/3/24.
//

import SwiftUI
import SwiftData


@main
struct shukrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject var sharedState = SharedStateClass()
    @StateObject var prayerViewModel: PrayerViewModel // Add ViewModel here
    @State private var globalLocationManager = GlobalLocationManager()
    
    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SessionDataModel.self,
            MantraModel.self,
            TaskModel.self,
            DuaModel.self,
            PrayerModel.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { // without this, the previews donr work and result to a fatalerror.
                print("Preview mode: Using empty ModelContainer.")
                return try! ModelContainer(for: Schema([]), configurations: []) // essentially making it an empty dummy
            } else {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    init() {
        let context = sharedModelContainer.mainContext
        _prayerViewModel = StateObject(wrappedValue: PrayerViewModel(context: context))
    }
    
    var body: some Scene {
        
            WindowGroup {
                
                    if globalLocationManager.isAuthorized{
                            // v4. Nav View with PrayerTimesView and everything else as navlink inside. Reason: we were having unnecesary view redraws causing us to lose state in views like TasbeehView. Debugged this using onappear and ondisappear print statements. I learned tabView with NavigationView inside causes this issue. Well known issue apparently.
                        NavigationStack{
                                PrayerTimesView(/*context: sharedModelContainer.mainContext*/)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                    .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
//                                    .preferredColorScheme(colorModeToggle ? .dark : .light)
                                    .preferredColorScheme(
                                        colorModeToggleNew == 0 ? .light :
                                        colorModeToggleNew == 1 ? .dark :
                                        (prayerViewModel.isDaytime ? .light : .dark)
                                    )
                            }
                            .tag(1)
                            .environmentObject(prayerViewModel)
                    }
                    else{
                        ZStack{
                            Color.red.opacity(0.001)
                                .edgesIgnoringSafeArea(.all)
                            NeuCircularProgressView(progress: 0)
                            Text("shukr")
                                .font(.headline)
                                .fontWeight(.thin)
                                .fontDesign(.rounded)
                        }
                        VStack{
                            Spacer()
                            Text("gimme your location bruh...")
                                .padding()
                            Button("Allow Location Access in Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                
            }
            .modelContainer(sharedModelContainer)
            .environment(globalLocationManager)
            .environmentObject(sharedState) // Inject shared state into the environment (Global access point for `sharedState`)
//            .environmentObject(prayerViewModel) // Inject PrayerViewModel
            // Inject `sharedState` as an EnvironmentObject at the top level of the app.
            // This makes `sharedState` globally accessible to any view within the view hierarchy
            // that starts from `PrayerTimesView`.
            // All subviews can access it implicitly by declaring
            // `@EnvironmentObject var sharedState: SharedStateClass`.
            // NOTE: This injection covers all views in the hierarchy. Additional injections are unnecessary,
            // unless a view is presented outside this hierarchy, like with a new window or distinct view instance.

    }
}


class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()
    
    func requestUserNotificationPermission() {
        // Request notification permissions (if not already requested)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        
        // Register notification categories
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
            actions: [snooze5, snooze10],
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
            actions: [round2_snooze5],
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
            actions: [round2_conf, round2_deny],
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "SNOOZE_5_ACTION", "SNOOZE_10_ACTION":
            let firstOption = (response.actionIdentifier == "SNOOZE_5_ACTION" ? true : false)
            print(firstOption ? "SNOOZE_5_ACTION action tapped" : "SNOOZE_10_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: firstOption ? 5*60 : 10*60,
                body: firstOption ? "It's been 5 minutes" : "It's been 10 minutes",
                withActionsFromCatId: "Round2_Snooze"
            )

            
        case "ROUND2_SNOOZE_5_ACTION", "ROUND2_SNOOZE_10_ACTION": //got rid of snooze 10
            let firstOption = (response.actionIdentifier == "ROUND2_SNOOZE_5_ACTION" ? true : false)
            print(firstOption ? "ROUND2_SNOOZE_5_ACTION action tapped" : "ROUND2_SNOOZE_10_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: 0.1,
                body: "😑 Are you being serious? Another \(firstOption ? "5" : "10") minutes?",
                withActionsFromCatId: "Round2_Confirm"
            )
            
        case "ROUND2_CONFIRM_ACTION":
            print("ROUND2_CONFIRM_ACTION action tapped")
            makeNextSnoozeNotifBe(
                after: 5,
                body: "5 more minutes have passed!",
                withActionsFromCatId: nil
            )

        case "ROUND2_DENY_ACTION":
            print("ROUND2_DENY_ACTION action tapped")
            // open the app
            
        default:
            break
        }
        completionHandler()
    }

    private func makeNextSnoozeNotifBe(after seconds: TimeInterval, body: String, withActionsFromCatId: String?) {
        let content = UNMutableNotificationContent()
        let identifier = UUID().uuidString
        content.title = body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive
        if let withActionsFromCatId {
            content.categoryIdentifier = withActionsFromCatId
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error \(identifier): \(error.localizedDescription)")
            } else {
                print("✅ Scheduled \(identifier): in \(seconds)s")
            }
        }
    }
}
