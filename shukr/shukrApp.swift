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
                            NavigationView{
                                // Middle page: Prayer time tracker
                                PrayerTimesView(/*context: sharedModelContainer.mainContext*/)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                    .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let remind5 = UNNotificationAction(
            identifier: "SNOOZE_5_ACTION",
            title: "Nudge in 5 minutes",
            options: []
        )
        let remind10 = UNNotificationAction(
            identifier: "SNOOZE_10_ACTION",
            title: "Nudge in 10 minutes",
            options: []
        )
        let prayerCategory = UNNotificationCategory(
            identifier: "PRAYER_CATEGORY",
            actions: [remind5, remind10],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([prayerCategory])
        return true
    }

    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "SNOOZE_5_ACTION":
            print("Snooze5 action tapped")
            scheduleSnoozeNotification(after: 5 * 60, identifier: "reminder5", body: "It's been 5 minutes")
            
        case "SNOOZE_10_ACTION":
            print("Snooze10 action tapped")
            scheduleSnoozeNotification(after: 10 * 60, identifier: "reminder10", body: "It's been 10 minutes")
            
        default:
            break
        }
        completionHandler()
        
        func scheduleSnoozeNotification(after seconds: TimeInterval, identifier: String, body: String) {
            let content = UNMutableNotificationContent()
            content.body = body
            content.sound = UNNotificationSound.default
            content.interruptionLevel = .timeSensitive
            
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

}

