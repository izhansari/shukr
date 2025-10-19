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
    
    // First define the two @StateObject properties *without* immediate assignment:
    @StateObject var environmentLocationManager: EnvLocationManager
    @StateObject var prayerViewModel: PrayerViewModel



//    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SessionDataModel.self,
            MantraModel.self,
            TaskModel.self,
            DuaModel.self,
            PrayerModel.self,
            DailyPrayerScore.self
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
    
    
    // 2) Now in the init, create local variables first, then assign them.
    init() {
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
                if environmentLocationManager.isAuthorized/* && false*/{
                    PrayerTimesView()
                        .transition(.blurReplace())
                    //.transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    //.toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
                }
                else{
                    ZStack{
                        if true {
                            GradientAnimationLoad()
                        }
                        else{
                            VStack {
                                Text("Location Access Required")
                                    .font(.headline)
                                    .padding()
                                Text("Please allow location access to fetch accurate prayer times.")
                                    .multilineTextAlignment(.center)
                                    .padding()
                                Button("Allow Location Access") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .transition(.blurReplace())
                }
                
            }
            .environmentObject(prayerViewModel)
            .preferredColorScheme(
                colorModeToggleNew == 0 ? .light :
                    colorModeToggleNew == 1 ? .dark :
                    (prayerViewModel.isDaytime ? .light : .dark)
            )
            
            
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(environmentLocationManager)
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







import SwiftUI

struct GradientAnimationLoad: View {
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
            
            // Glassmorphic Card
            GlassmorphicCard()
                .frame(width: 200, height: 200)
                .onTapGesture {
                    dummyDarkOn.toggle()
                    if dummyDarkOn{colorModeToggleNew = 0}
                    else {colorModeToggleNew = 1}
                    print(dummyDarkOn)
                }
            
            VStack{
                Spacer()
                GlassmorphicButton()
                    .frame(width: 200, height: 50)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                noiseOpacity = 0.3
            }
        }
//        .preferredColorScheme(dummyDarkOn ? .dark : .light)
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
    let settingsURL = URL(string: UIApplication.openSettingsURLString)
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
                        if envLocationManager.manager.authorizationStatus == .denied{
                            if let url = settingsURL {
                                UIApplication.shared.open(url)
                            }
                        } else{
                            envLocationManager.requestLocationPermission()
                        }
                    }) {
                        Label("allow location access", systemImage: "location")
                            .font(.footnote)
                            .fontWeight(.light)
                            .fontDesign(.rounded)
                            .foregroundColor(.white.opacity(0.6))
//                            .padding()
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            )
            .shadow(radius: 5)
    }
}
//// MARK: - Preview
//struct GradientAnimationLoad_Previews: PreviewProvider {
//    static var previews: some View {
//        GradientAnimationLoad()
//    }
//}
